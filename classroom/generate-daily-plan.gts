// Phase 2 - AI Daily Plan Generator (Single + Batch helpers)
//
// Two exported helpers used by DailyPlanManager:
//   1. generateDailyPlanSingle(input) - one student, one AI call
//   2. generateDailyPlansBatch(input)  - many students, ONE AI call
//      (auto-splits into batches of <= 15 students if there are more)
//
// The batch mode is the boss's "aggregate many reads into one call" principle
// (see conversation_transcript.md): feed all students' context into ONE big
// markdown, have the AI output a JSON array of plans. Drastically reduces
// token count and latency vs N separate calls.
//
// Both helpers share the same underlying primitives:
//   - fetchStudentHistory(student, getCards) - queries active goals + last 5
//     DailyPlans + last 20 ActivityEntries for that student
//   - buildStudentSection(student, history) - renders one student's context
//     as markdown
//   - callGemini(...) - invokes OpenRouter via SendRequestViaProxyCommand
//   - parseAndSavePlan(...) - builds a DailyPlan card + persists it
//
// HTTP header values MUST be ASCII only (learned the hard way in parent-daily
// Phase 0 - em-dash in X-Title caused silent 500s).

import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import { DailyPlan } from './daily-plan';
import { ScheduleItem } from './schedule-item';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const DEFAULT_MODEL = 'google/gemini-2.0-flash-001';
const BATCH_MAX_SIZE = 15; // Split larger groups automatically

// =========================================================
//  Types
// =========================================================

export interface SingleInput {
  student: any;           // Student card instance
  classroom: any;         // Classroom card instance (optional)
  date: string;           // yyyy-mm-dd
  teacherNote: string;
  skillCard: any;         // SkillCard instance with compiledPrompt
  commandContext: any;    // Host command context
  realmHref: string;      // Target realm for saved DailyPlan
  getCards: any;          // Host-injected getCards (passed from Component)
  parent: any;            // The calling Component instance (for resource lifecycle)
}

export interface SingleResult {
  savedCardId: string;
  studentSlug: string;
  studentName: string;
  model: string;
  latencyMs: number;
  parsedJson: any;
}

export interface BatchInput {
  students: any[];        // all Student card instances to generate for
  classroom: any;
  date: string;
  teacherNote: string;
  skillCard: any;
  commandContext: any;
  realmHref: string;
  getCards: any;
  parent: any;            // The calling Component instance (for resource lifecycle)
}

export interface BatchResult {
  created: Array<{ studentSlug: string; studentName: string; cardId: string }>;
  failed: Array<{ studentSlug: string; studentName: string; reason: string }>;
  totalLatencyMs: number;
  splitsUsed: number;     // Number of AI calls made (1 if <=15 students, 2 if 16-30, etc.)
  modelUsed: string;
}

interface StudentHistory {
  goals: any[];           // active LearningGoals
  recentPlans: any[];     // last 5 DailyPlans, sorted desc by planDate
  recentActivities: any[];// last 20 ActivityEntries, sorted desc by timestamp
}

// =========================================================
//  Shared primitive: unwrap a StoreSearchResource
// =========================================================

async function unwrapResource(resource: any, maxWaitMs = 8000): Promise<any[]> {
  try {
    const r: any = resource;
    if (Array.isArray(r)) return r;
    const readArr = () => {
      if (Array.isArray(r?.instances)) return r.instances;
      if (Array.isArray(r?.value)) return r.value;
      return null;
    };
    const start = Date.now();
    while (Date.now() - start < maxWaitMs) {
      const loading = r?.isLoading === true;
      const arr = readArr();
      if (!loading && arr !== null) return arr;
      await new Promise((res) => setTimeout(res, 100));
    }
    return readArr() ?? [];
  } catch (_) {
    return [];
  }
}

// =========================================================
//  Shared primitive: fetch one student's history
// =========================================================

async function fetchStudentHistory(
  student: any,
  getCards: any,
  parent: any,
  realmHref: string,
  date: string = '',
): Promise<StudentHistory> {
  const goalsModule = realmHref + 'learning-goal';
  const plansModule = realmHref + 'daily-plan';
  const activitiesModule = realmHref + 'activity-entry';

  // Query in parallel for speed (pass component parent for resource lifecycle)
  const goalsRes = getCards(
    parent,
    () => ({
      filter: { type: { module: goalsModule, name: 'LearningGoal' } },
    }),
  );
  const plansRes = getCards(
    parent,
    () => ({
      filter: { type: { module: plansModule, name: 'DailyPlan' } },
    }),
  );
  const activitiesRes = getCards(
    parent,
    () => ({
      filter: { type: { module: activitiesModule, name: 'ActivityEntry' } },
    }),
  );

  const allGoals = await unwrapResource(goalsRes);
  const allPlans = await unwrapResource(plansRes);
  const allActivities = await unwrapResource(activitiesRes);

  const studentId = String(student?.id ?? '');

  // Filter goals by student — try linksTo id first, then fallback to name match
  const studentFirst = String(student?.firstName ?? '').toLowerCase();
  const studentLast = String(student?.lastName ?? '').toLowerCase();
  const studentFullName = `${studentFirst} ${studentLast}`.trim();

  // Helper: parse date string as local time
  const parseLocal = (s: string): Date | null => {
    if (!s) return null;
    const p = s.split(/[-\/]/);
    if (p.length < 3) return null;
    const d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
    return isNaN(d.getTime()) ? null : d;
  };

  // View date (the plan date)
  const viewDate = parseLocal(date);

  // Check if a goal is active on the view date: started <= viewDate <= dueDate
  const isActiveOnDate = (sd: string, dd: string): boolean => {
    if (!sd || !viewDate) return true; // no date → include (legacy)
    const s = parseLocal(sd);
    if (!s) return true;
    if (viewDate.getTime() < s.getTime()) return false;
    if (dd) {
      const d = parseLocal(dd);
      if (d && viewDate.getTime() > d.getTime()) return false;
    }
    return true;
  };

  const goals = allGoals.filter((g: any) => {
    // Primary: match by linksTo student id
    const matchStudent = (studentId && String(g?.student?.id ?? '') === studentId) ||
      (() => {
        const gName = String(g?.studentName ?? '').toLowerCase().trim();
        return (gName && studentFullName && gName === studentFullName) ||
               (studentFirst && gName.includes(studentFirst));
      })();
    if (!matchStudent) return false;
    // Filter by date range: only goals active on the plan date
    const sd = String(g?.startedDate ?? '');
    let dd = '';
    try {
      const raw = g?.dueDate;
      if (raw) { if (typeof raw === 'string') { dd = raw; } else { const dt = new Date(raw); dd = `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; } }
    } catch (_) {}
    return isActiveOnDate(sd, dd);
  });

  const plans = allPlans
    .filter((p: any) => String(p?.student?.id ?? '') === studentId)
    .sort((a: any, b: any) => {
      const da = a?.planDate ? new Date(a.planDate).getTime() : 0;
      const db = b?.planDate ? new Date(b.planDate).getTime() : 0;
      return db - da; // desc
    })
    .slice(0, 5);

  const activities = allActivities
    .filter((e: any) => String(e?.student?.id ?? '') === studentId)
    .sort((a: any, b: any) => {
      const ta = a?.timestamp ? new Date(a.timestamp).getTime() : 0;
      const tb = b?.timestamp ? new Date(b.timestamp).getTime() : 0;
      return tb - ta;
    })
    .slice(0, 20);

  return { goals, recentPlans: plans, recentActivities: activities };
}

// =========================================================
//  Shared primitive: render one student's context as markdown
// =========================================================

function renderStudentSection(
  student: any,
  history: StudentHistory,
  index: number,
): string {
  const first = String(student?.firstName ?? '');
  const last = String(student?.lastName ?? '');
  const name = `${first} ${last}`.trim() || 'Unknown';
  const slug = String(student?.id ?? '').split('/').pop() ?? '';
  const grade = String(student?.gradeLevel?.value ?? student?.gradeLevel ?? '');

  const lines: string[] = [];
  lines.push(`## STUDENT ${index}: ${name} (${grade || 'grade ?'})`);
  lines.push(`Slug: \`${slug}\``);
  lines.push('');

  // Active goals — include description, target, alignment, materials
  lines.push('### Active Learning Goals');
  lines.push(`Total: ${history.goals.length} goals`);
  if (history.goals.length === 0) {
    lines.push('_(no learning goals found for this student)_');
  } else {
    for (const g of history.goals) {
      const title = String(g?.goalTitle ?? '(untitled)');
      const domain = String(g?.domain?.value ?? g?.domain ?? '');
      const priority = String(g?.priority?.value ?? g?.priority ?? '');
      const progress = g?.progressPercent ?? g?.currentMastery ?? 0;
      const desc = String(g?.description ?? '');
      const alignment = String(g?.standardAlignment ?? '');
      lines.push(`- **${title}** (${domain}, ${priority} priority, ${progress}% progress)`);
      if (desc) lines.push(`  Description: ${desc}`);
      if (alignment) lines.push(`  Standard: ${alignment}`);
      // Include evidence entries count
      const evCount = (g?.evidenceEntries ?? []).length;
      if (evCount > 0) lines.push(`  Evidence: ${evCount} observations recorded`);
    }
  }
  lines.push('');

  // Recent plans (last 5)
  lines.push('### Recent History - Last 5 Daily Plans');
  if (history.recentPlans.length === 0) {
    lines.push('_(no prior plans - this is the first plan for this student)_');
  } else {
    history.recentPlans.forEach((p: any, i: number) => {
      let dateStr = '?';
      if (p?.planDate) { try { const dt = new Date(p.planDate); dateStr = `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; } catch (_) {} }
      const status = String(p?.status?.value ?? p?.status ?? '').toUpperCase();
      const gen = String(p?.generatedBy?.value ?? p?.generatedBy ?? '');
      lines.push(`#### Day ${i + 1}: ${dateStr} [${status}] (generated by ${gen})`);
      const items = p?.scheduleItems ?? [];
      if (items.length === 0) {
        lines.push('  _(empty plan)_');
      } else {
        for (const item of items) {
          const time = String(item?.time ?? '');
          const act = String(item?.activity ?? '');
          const result = item?.result ? ` -> ${item.result}` : '';
          const tag = item?.goalTag ? ` [${item.goalTag}]` : '';
          lines.push(`  - ${time} ${act}${tag}${result}`);
        }
      }
      if (p?.notes) {
        lines.push(`  _notes: ${p.notes}_`);
      }
    });
  }
  lines.push('');

  // Recent activities (last 20, summarized)
  lines.push('### Recent Activity Outcomes - Last 20 entries');
  if (history.recentActivities.length === 0) {
    lines.push('_(no activity entries yet)_');
  } else {
    for (const a of history.recentActivities) {
      const ts = a?.timestamp ? new Date(a.timestamp).toLocaleString('en-US', {
        month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
      }) : '?';
      const type = String(a?.entryType?.value ?? a?.entryType ?? '');
      const score = a?.score ? ` [${a.score}]` : '';
      const content = String(a?.content ?? '').slice(0, 120);
      lines.push(`- ${ts} (${type})${score}: ${content}`);
    }
  }
  lines.push('');

  return lines.join('\n');
}

// =========================================================
//  Shared primitive: call Gemini via Boxel proxy
// =========================================================

async function callGemini(
  systemPrompt: string,
  userPrompt: string,
  commandContext: any,
  options: { maxTokens?: number; temperature?: number; model?: string } = {},
): Promise<{ parsedContent: any; modelUsed: string; rawContent: string }> {
  const model = options.model ?? DEFAULT_MODEL;
  const maxTokens = options.maxTokens ?? 1200;
  const temperature = options.temperature ?? 0.4;

  const requestBody = JSON.stringify({
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    temperature,
    max_tokens: maxTokens,
  });

  // IMPORTANT: all header values MUST be pure ASCII (no em-dash or unicode)
  const apiCall = new SendRequestViaProxyCommand(commandContext).execute({
    url: OPENROUTER_URL,
    method: 'POST',
    requestBody,
    headers: {
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://app.boxel.ai',
      'X-Title': 'Tribeca Prep Daily Plan Generator',
    },
  });

  const timeout = new Promise((_r, rej) =>
    setTimeout(() => rej(new Error('AI call timed out after 45s')), 45000),
  );

  const response: any = await Promise.race([apiCall, timeout]);

  if (response?.response && !response.response.ok) {
    let body = '';
    try { body = await response.response.text(); } catch (_) {}
    throw new Error(
      `HTTP ${response.response.status}: ${response.response.statusText} - body: ${body.slice(0, 500)}`,
    );
  }

  // Multi-shape unwrap
  let data: any;
  try {
    if (response?.response?.text) {
      const raw = await response.response.text();
      data = JSON.parse(raw);
    } else if (response?.response?.json) {
      data = await response.response.json();
    } else {
      data = response;
    }
  } catch (_) {
    data = response;
  }

  let content: string =
    data?.choices?.[0]?.message?.content ??
    data?.response?.choices?.[0]?.message?.content ??
    data?.data?.choices?.[0]?.message?.content ??
    (typeof data?.response === 'string' ? data.response : '') ??
    '';

  if (!content && data) {
    try {
      const jsonStr = typeof data === 'string' ? data : JSON.stringify(data);
      const match = jsonStr.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
      if (match) content = JSON.parse('"' + match[1] + '"');
    } catch (_) { /* ignore */ }
  }

  const clean = content
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();

  if (!clean) {
    throw new Error(
      `AI returned empty content. Response keys: ${Object.keys(data ?? {}).join(',')}`,
    );
  }

  let parsed: any;
  try {
    parsed = JSON.parse(clean);
  } catch (e) {
    throw new Error(
      `Failed to parse AI JSON: ${e}. Raw: ${clean.slice(0, 400)}`,
    );
  }

  return {
    parsedContent: parsed,
    modelUsed: data?.model ?? data?.response?.model ?? model,
    rawContent: clean,
  };
}

// =========================================================
//  Shared primitive: build a DailyPlan card and save it
// =========================================================

async function saveDailyPlan(args: {
  student: any;
  classroom: any;
  date: string;
  scheduleItemsRaw: any[];
  notes: string;
  aiModelUsed: string;
  commandContext: any;
  realmHref: string;
}): Promise<string> {
  const [yStr, mStr, dStr] = args.date.split('-');
  const planDateObj = new Date(
    Number(yStr),
    Number(mStr) - 1,
    Number(dStr),
  );
  if (isNaN(planDateObj.getTime())) {
    throw new Error(`Invalid date: ${args.date}`);
  }

  const plan = new DailyPlan();
  (plan as any).student = args.student;
  if (args.classroom) (plan as any).classroom = args.classroom;
  (plan as any).planDate = planDateObj;
  plan.status = 'draft';
  plan.generatedBy = 'ai';
  (plan as any).generatedAt = new Date();
  plan.aiModelUsed = args.aiModelUsed;
  plan.notes = args.notes;

  // Build ScheduleItem instances from the raw AI JSON items
  const items = (args.scheduleItemsRaw ?? []).map((raw: any) => {
    const si = new ScheduleItem();
    si.time = String(raw?.time ?? '');
    si.activity = String(raw?.activity ?? '');
    (si as any).status = String(raw?.status ?? 'Upcoming');
    si.result = String(raw?.result ?? '');
    si.goalTag = String(raw?.goalTag ?? '');
    return si;
  });
  (plan as any).scheduleItems = items;

  const { default: SaveCardCommand } = await import(
    '@cardstack/boxel-host/commands/save-card'
  );
  const saveResult: any = await new SaveCardCommand(args.commandContext).execute({
    card: plan,
    realm: args.realmHref,
  });
  return (
    saveResult?.savedCard?.id ??
    saveResult?.id ??
    (plan as any)?.id ??
    ''
  );
}

// =========================================================
//  The OUTPUT SCHEMA instruction, shared by single + batch
// =========================================================

const OUTPUT_SCHEMA_SINGLE = `

---

## YOUR TASK (single student)

Return ONLY a valid JSON object (no markdown fences, no commentary) with this shape:

{
  "scheduleItems": [
    {
      "time": "8:45",
      "activity": "Homeroom (morning arrival and settling)",
      "status": "Upcoming",
      "result": "",
      "goalTag": ""
    },
    {
      "time": "9:00",
      "activity": "DI Math: Count to 5 with objects using DI Connecting Math Concepts",
      "status": "Upcoming",
      "result": "",
      "goalTag": "Count with 1:1 Correspondence"
    }
  ],
  "planNotes": "Focus for today's plan in 1-2 sentences.",
  "progressionNote": "How this plan builds on / differs from yesterday in 1-2 sentences."
}

### Hard rules
1. The number of academic blocks should match the number of active goals — ONE block per goal, no more. Add 3-4 routine blocks (Homeroom, sensory break, Lunch+Recess, Closing).
2. Every item has time + activity + status="Upcoming" + result="" + goalTag
3. goalTag MUST exactly match a LearningGoal title from the student's context. Empty only for routine blocks.
4. Each goal gets exactly ONE dedicated activity block. Do NOT use the same goal twice.
5. The activity description should reference the goal's description and materials (e.g., "DI Math: Lesson 47 using Connecting Math Concepts" not just "Math class")
6. Include at least one sensory break between academic blocks
7. Follow all PROGRESSION RULES from the playbook — build on yesterday's results
8. Never hallucinate goals, activities, or materials not in the student's context
9. Time range: 8:45 to 2:30`;

const OUTPUT_SCHEMA_BATCH = `

---

## YOUR TASK (batch mode - multiple students in one call)

You will receive N students' contexts below. Return ONLY a valid JSON object
(no markdown fences, no commentary) with an array of plans, one per student:

{
  "plans": [
    {
      "studentSlug": "jamie-chen",
      "scheduleItems": [
        {
          "time": "8:45",
          "activity": "Homeroom",
          "status": "Upcoming",
          "result": "",
          "goalTag": ""
        },
        ...
      ],
      "planNotes": "...",
      "progressionNote": "..."
    },
    {
      "studentSlug": "alex-p",
      "scheduleItems": [...],
      ...
    }
  ]
}

### Hard rules
1. The "plans" array must have exactly one entry per student in the input, matched by studentSlug (the \`Slug:\` value shown in each STUDENT section)
2. Each entry follows single mode rules: ONE academic block per goal, 3-4 routine blocks, goalTag must exactly match goal title
3. Apply all PROGRESSION RULES per student based on their own RECENT HISTORY
4. Activity descriptions should reference the goal's description and materials
5. Each goal gets exactly ONE block. Do NOT duplicate goalTags.
6. Never hallucinate goals, activities, or materials not in a student's context
7. If a student has zero learning goals, produce a fallback plan (routine blocks only, no goalTag)`;

// =========================================================
//  PUBLIC: generateDailyPlanSingle
// =========================================================

export async function generateDailyPlanSingle(
  input: SingleInput,
): Promise<SingleResult> {
  const t0 = performance.now();

  const compiledPrompt = String(input.skillCard?.compiledPrompt ?? '').trim();
  if (!compiledPrompt) {
    throw new Error('SkillCard compiledPrompt is empty. Check the seed instance.');
  }

  // Fetch history for this one student
  console.log('[generateDailyPlanSingle] fetching history...');
  const history = await fetchStudentHistory(
    input.student,
    input.getCards,
    input.parent,
    input.realmHref,
    input.date,
  );

  // Build user prompt
  const studentSection = renderStudentSection(input.student, history, 1);
  const userPrompt = [
    'Generate a daily plan for ONE student.',
    '',
    studentSection,
    '',
    '## SHARED CONTEXT',
    `Date: ${input.date}`,
    `Classroom: ${String(input.classroom?.classroomName ?? '(unknown)')}`,
    input.teacherNote ? `Teacher note: ${input.teacherNote}` : '',
    '',
    'Generate the scheduleItems JSON now, following the progression rules strictly.',
  ].filter(Boolean).join('\n');

  const systemPrompt = compiledPrompt + OUTPUT_SCHEMA_SINGLE;

  console.log(`[generateDailyPlanSingle] sys=${systemPrompt.length} chars, usr=${userPrompt.length} chars`);

  // Call Gemini
  const { parsedContent, modelUsed } = await callGemini(
    systemPrompt,
    userPrompt,
    input.commandContext,
    { temperature: 0.4, maxTokens: 1500 },
  );

  console.log('[generateDailyPlanSingle] got JSON', parsedContent);

  // Build + save DailyPlan card
  const notes = [
    parsedContent?.planNotes ?? '',
    parsedContent?.progressionNote ? `[Progression] ${parsedContent.progressionNote}` : '',
    input.teacherNote ? `[Teacher note] ${input.teacherNote}` : '',
  ].filter(Boolean).join('\n');

  const savedId = await saveDailyPlan({
    student: input.student,
    classroom: input.classroom,
    date: input.date,
    scheduleItemsRaw: parsedContent?.scheduleItems ?? [],
    notes,
    aiModelUsed: modelUsed,
    commandContext: input.commandContext,
    realmHref: input.realmHref,
  });

  const latencyMs = Math.round(performance.now() - t0);
  const first = String(input.student?.firstName ?? '');
  const last = String(input.student?.lastName ?? '');
  const studentName = `${first} ${last}`.trim();
  const studentSlug = String(input.student?.id ?? '').split('/').pop() ?? '';

  return {
    savedCardId: savedId,
    studentSlug,
    studentName,
    model: modelUsed,
    latencyMs,
    parsedJson: parsedContent,
  };
}

// =========================================================
//  PUBLIC: generateDailyPlansBatch
// =========================================================

export async function generateDailyPlansBatch(
  input: BatchInput,
): Promise<BatchResult> {
  const t0 = performance.now();

  const compiledPrompt = String(input.skillCard?.compiledPrompt ?? '').trim();
  if (!compiledPrompt) {
    throw new Error('SkillCard compiledPrompt is empty.');
  }
  if (input.students.length === 0) {
    throw new Error('No students provided for batch generation');
  }

  // Split into sub-batches of BATCH_MAX_SIZE (default 15)
  const subBatches: any[][] = [];
  for (let i = 0; i < input.students.length; i += BATCH_MAX_SIZE) {
    subBatches.push(input.students.slice(i, i + BATCH_MAX_SIZE));
  }

  const created: BatchResult['created'] = [];
  const failed: BatchResult['failed'] = [];
  let modelUsed = DEFAULT_MODEL;

  console.log(
    `[generateDailyPlansBatch] ${input.students.length} students in ${subBatches.length} sub-batch(es) (max ${BATCH_MAX_SIZE} per call)`,
  );

  for (let batchIdx = 0; batchIdx < subBatches.length; batchIdx++) {
    const batch = subBatches[batchIdx];
    console.log(
      `[generateDailyPlansBatch] sub-batch ${batchIdx + 1}/${subBatches.length} (${batch.length} students): fetching histories in parallel...`,
    );

    // Fetch history for all students in this sub-batch in parallel
    const histories = await Promise.all(
      batch.map((s) =>
        fetchStudentHistory(s, input.getCards, input.parent, input.realmHref, input.date).catch((e) => {
          console.warn('[batch] history fetch failed for a student', e);
          return { goals: [], recentPlans: [], recentActivities: [] } as StudentHistory;
        }),
      ),
    );

    // Render each student as a markdown section
    const studentSections = batch
      .map((student, i) => renderStudentSection(student, histories[i], i + 1))
      .join('\n');

    const userPrompt = [
      `Generate daily plans for ALL ${batch.length} students below in ONE response.`,
      '',
      studentSections,
      '',
      '## SHARED CONTEXT',
      `Date: ${input.date}`,
      `Classroom: ${String(input.classroom?.classroomName ?? '(unknown)')}`,
      input.teacherNote ? `Teacher note (applies to all students): ${input.teacherNote}` : '',
      '',
      `Return ONE JSON object with a "plans" array of ${batch.length} entries, matched by studentSlug. Follow all progression rules per-student.`,
    ].filter(Boolean).join('\n');

    const systemPrompt = compiledPrompt + OUTPUT_SCHEMA_BATCH;

    console.log(
      `[batch] sub-batch ${batchIdx + 1}: sys=${systemPrompt.length} chars, usr=${userPrompt.length} chars`,
    );

    // Call Gemini ONCE for this sub-batch
    let batchParsed: any;
    try {
      const result = await callGemini(
        systemPrompt,
        userPrompt,
        input.commandContext,
        { temperature: 0.4, maxTokens: 10000 }, // Bigger output for many plans
      );
      batchParsed = result.parsedContent;
      modelUsed = result.modelUsed;
    } catch (e: any) {
      // Entire sub-batch failed - mark all students as failed
      for (const s of batch) {
        const first = String(s?.firstName ?? '');
        const last = String(s?.lastName ?? '');
        const name = `${first} ${last}`.trim() || '?';
        const slug = String(s?.id ?? '').split('/').pop() ?? '';
        failed.push({
          studentSlug: slug,
          studentName: name,
          reason: `AI call failed: ${e?.message ?? String(e)}`,
        });
      }
      continue;
    }

    const plansRaw = Array.isArray(batchParsed?.plans) ? batchParsed.plans : [];
    console.log(
      `[batch] sub-batch ${batchIdx + 1}: AI returned ${plansRaw.length} plans`,
    );

    // Save each plan independently so one parse error doesn't lose others
    for (const planRaw of plansRaw) {
      const slug = String(planRaw?.studentSlug ?? '').trim();
      if (!slug) {
        failed.push({
          studentSlug: '(missing)',
          studentName: '?',
          reason: 'AI returned plan without studentSlug',
        });
        continue;
      }

      // Find matching student card in this sub-batch
      const student = batch.find(
        (s) => (String(s?.id ?? '').split('/').pop() ?? '') === slug,
      );
      if (!student) {
        failed.push({
          studentSlug: slug,
          studentName: '?',
          reason: `AI returned unknown studentSlug "${slug}" (not in this batch)`,
        });
        continue;
      }

      const first = String(student?.firstName ?? '');
      const last = String(student?.lastName ?? '');
      const name = `${first} ${last}`.trim() || slug;

      try {
        const notes = [
          planRaw?.planNotes ?? '',
          planRaw?.progressionNote ? `[Progression] ${planRaw.progressionNote}` : '',
          input.teacherNote ? `[Teacher note] ${input.teacherNote}` : '',
        ].filter(Boolean).join('\n');

        const savedId = await saveDailyPlan({
          student,
          classroom: input.classroom,
          date: input.date,
          scheduleItemsRaw: planRaw?.scheduleItems ?? [],
          notes,
          aiModelUsed: modelUsed,
          commandContext: input.commandContext,
          realmHref: input.realmHref,
        });
        created.push({ studentSlug: slug, studentName: name, cardId: savedId });
      } catch (e: any) {
        failed.push({
          studentSlug: slug,
          studentName: name,
          reason: `Save failed: ${e?.message ?? String(e)}`,
        });
      }
    }

    // If AI didn't return a plan for some student in this sub-batch, mark missing
    for (const student of batch) {
      const slug = String(student?.id ?? '').split('/').pop() ?? '';
      if (!slug) continue;
      const hit = created.find((c) => c.studentSlug === slug) ||
                  failed.find((f) => f.studentSlug === slug);
      if (!hit) {
        const first = String(student?.firstName ?? '');
        const last = String(student?.lastName ?? '');
        failed.push({
          studentSlug: slug,
          studentName: `${first} ${last}`.trim() || slug,
          reason: 'AI did not return a plan for this student',
        });
      }
    }
  }

  const totalLatencyMs = Math.round(performance.now() - t0);
  console.log(
    `[generateDailyPlansBatch] done: ${created.length} created, ${failed.length} failed, ${subBatches.length} AI calls, ${totalLatencyMs}ms`,
  );

  return {
    created,
    failed,
    totalLatencyMs,
    splitsUsed: subBatches.length,
    modelUsed,
  };
}
// touched for re-index
