import {
  CardDef,
  field,
  contains,
  linksTo,
  linksToMany,
  Component,
  // NOTE: getCards is a TYPE-ONLY export from card-api. The runtime function
  // must be accessed via this.args.context.getCards (host-injected).
  // Xiaoran's original code imported it here but it was always undefined at
  // runtime, causing loadData() to silently fail. Fixed below.
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import SchoolIcon from '@cardstack/boxel-icons/school';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { formatDateTime } from '@cardstack/boxel-ui/helpers';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import { Staff } from './staff';
import { Student } from './student';
import { generateDailyPlanSingle, generateDailyPlansBatch } from './generate-daily-plan';
import { syncObsToAdmin } from './sync-obs-to-admin';
import { syncAeToHos } from './sync-ae-to-hos';
import { syncGoalsToHos } from './sync-goals-to-hos';
import { syncAlertToHos } from './sync-alert-to-hos';
import { syncStudentLocationToHos } from './sync-student-location-to-hos';
import { syncSnapshotToParent } from './sync-snapshot-to-parent';

// ── AI Classification Helper ──
interface AiClassification {
  entryType: string;
  domain: string;
  matchedBlock: string;
  confidence: number;
  reasoning: string;
  suggestedGoal: string;
  score: string;
  flagNote: string;
  flagSeverity: string;
}

async function classifyWithAi(
  commandContext: any,
  observation: string,
  studentName: string,
  scheduleContext: string,
  goalContext: string,
): Promise<AiClassification> {
  let systemPrompt = `You are an AI classroom observation classifier for a special education LMS.
Given a teacher's observation about ${studentName}, produce a structured JSON object.

SCHEDULE BLOCKS:
${scheduleContext || 'None specified'}

LEARNING GOALS:
${goalContext || 'None specified'}

Return ONLY valid JSON (no markdown fences, no extra text) with these fields:
{
  "entryType": "Academic" | "Behavioral" | "Social",
  "domain": "Math" | "Reading" | "Social" | "Behavioral" | "Communication" | "Motor" | "General",
  "matchedBlock": "<schedule block activity name or empty string>",
  "confidence": <0-100>,
  "reasoning": "<1 sentence explaining classification>",
  "suggestedGoal": "<goal title or empty string>",
  "score": "<score as numerator/denominator — see scoring rules below>",
  "flagNote": "<safety/medical/urgent note or empty string>",
  "flagSeverity": "info" | "warning" | "urgent" | ""
}

Rules:
- CRITICAL: matchedBlock must be the EXACT activity name string from the SCHEDULE BLOCKS list above, copied character-for-character. Do NOT paraphrase or abbreviate.
- Use SEMANTIC matching, not just keyword matching. Common mappings:
  * "PE", "gym", "physical education", "exercise" → match the "Specials" block (Specials includes Art/Music/PE)
  * "art", "drawing", "painting", "craft" → match the "Specials" block
  * "music", "singing", "instruments" → match the "Specials" block
  * "OT", "occupational therapy", "fine motor" → match "Specialist" or relevant therapy block
  * "speech", "ST", "speech therapy" → match "Specialist" or relevant therapy block
  * "snack", "break", "sensory break" → match the sensory/snack block
  * "reading", "book", "phonics", "RM" → match any Reading block
  * "math", "counting", "addition", "DI Math" → match any Math block
  * "recess", "lunch", "playground" → match "Lunch + Recess"
  * "science", "social studies", "experiment" → match "Science / Social Studies"
  * "social skills", "group work", "sharing", "taking turns" → match "Social skills / group work"
  * "homeroom", "morning meeting", "arrival" → match "Homeroom"
  * "closing", "reflection", "pack up" → match "Closing / reflection"
- If the observation doesn't clearly relate to ANY schedule block, leave matchedBlock as an empty string.
- If observation relates to a learning goal, set suggestedGoal to the EXACT goal title from the LEARNING GOALS list. The goal title is the text in quotes BEFORE the | separator. Do NOT include domain/current/target info. Example: if you see '- "Sorting Non-Identical Objects" | domain: Math, current: 0%, target: 80%', the suggestedGoal should be exactly "Sorting Non-Identical Objects" (without quotes).
- SCORING RULES (IMPORTANT — always try to produce a score when a goal is matched):
  * CRITICAL: The numerator must NEVER exceed the denominator. Max score is always denominator/denominator (100%).
  * For academic tasks with explicit scores: use the stated score (e.g. "18/20", "10/10")
  * For time-based goals (e.g. "participate for 15+ minutes"): if the student met or exceeded the target, score = target/target (e.g. "15/15"). If below target, score = actual/target (e.g. "10/15"). Include the actual time in the reasoning field (e.g. "Completed 40 minutes, exceeding the 15-minute target").
  * For completion goals (e.g. "complete art project using 3+ materials"): if met or exceeded, score = target/target (e.g. "3/3"). If below, score = actual/target (e.g. "2/3").
  * For participation/behavior goals: score = 1/1 if fully met, 0/1 if not met, or partial like 3/5 based on quality
  * For reading fluency goals (e.g. "read at 60+ wpm"): if met or exceeded, score = target/target (e.g. "60/60"). If below, score = actual/target (e.g. "45/60").
  * If the observation clearly relates to a goal but you cannot determine a score, use "1/1" for completed or leave empty if unclear
  * NEVER leave score empty when a suggestedGoal is set and the observation indicates the student did the activity
- If observation mentions safety, medical, or urgent concerns, set flagNote and flagSeverity.
- Use title case for entryType (Academic, Social, Behavioral).`;

  let userPrompt = `Classify this observation: "${observation}"`;

  let requestBody = JSON.stringify({
    model: 'google/gemini-2.0-flash-001',
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    temperature: 0.2,
    max_tokens: 400,
  });

  // Wrap API call with 15-second timeout
  let apiCall = new SendRequestViaProxyCommand(
    commandContext,
  ).execute({
    url: 'https://openrouter.ai/api/v1/chat/completions',
    method: 'POST',
    requestBody,
    headers: {
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://app.boxel.ai',
      'X-Title': 'Classroom Dashboard AI',
    },
  });

  let timeout = new Promise((_resolve, reject) =>
    setTimeout(() => reject(new Error('AI classification timed out after 15s')), 15000),
  );

  let response: any = await Promise.race([apiCall, timeout]);

  // Extract response data — try every known Boxel proxy response shape
  let data: any;
  try {
    if (response?.response?.text) {
      let raw = await response.response.text();
      data = JSON.parse(raw);
    } else if (response?.response?.json) {
      data = await response.response.json();
    } else {
      data = response;
    }
  } catch (_e) {
    data = response;
  }

  // Walk every possible path to find the AI content string
  let content: string =
    data?.choices?.[0]?.message?.content ??
    data?.response?.choices?.[0]?.message?.content ??
    data?.data?.choices?.[0]?.message?.content ??
    (typeof data?.response === 'string' ? data.response : '') ??
    '';

  // If content is still empty, try to find it recursively in the response
  if (!content && data) {
    try {
      let jsonStr = typeof data === 'string' ? data : JSON.stringify(data);
      let match = jsonStr.match(/"content"\s*:\s*"((?:[^"\\]|\\.)*)"/);
      if (match) content = JSON.parse('"' + match[1] + '"');
    } catch (_e) { /* ignore */ }
  }

  content = content
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();

  let parsed: any;
  try {
    parsed = JSON.parse(content);
  } catch (_e) {
    parsed = {};
  }


  return {
    entryType: parsed.entryType ?? 'Academic',
    domain: parsed.domain ?? 'General',
    matchedBlock: parsed.matchedBlock ?? '',
    confidence: Number(parsed.confidence) > 0 ? Number(parsed.confidence) : 70,
    reasoning: parsed.reasoning ?? 'Observation logged.',
    suggestedGoal: parsed.suggestedGoal ?? '',
    score: parsed.score ?? '',
    flagNote: parsed.flagNote ?? '',
    flagSeverity: parsed.flagSeverity ?? '',
  };
}

export class Classroom extends CardDef {
  static displayName = 'Classroom';
  static icon = SchoolIcon;
  static prefersWideFormat = true;

  @field classroomName = contains(StringField);
  @field teacher = linksTo(Staff);
  @field students = linksToMany(Student);
  @field date = contains(DateField);

  @field title = contains(StringField, {
    computeVia: function (this: Classroom) {
      return this.classroomName ?? 'Untitled Classroom';
    },
  });

  static isolated = class Isolated extends Component<typeof Classroom> {
    @tracked selectedStudentIndex = 0;
    // Local date helper — avoids UTC timezone shift (e.g. EDT 8PM = UTC next day)
    static _localDateStr(d: Date = new Date()): string {
      const yyyy = d.getFullYear();
      const mm = String(d.getMonth() + 1).padStart(2, '0');
      const dd = String(d.getDate()).padStart(2, '0');
      return `${yyyy}-${mm}-${dd}`;
    }
    @tracked viewDate = (this.constructor as any)._localDateStr(); // yyyy-mm-dd, default today
    @tracked activityEntries: any[] = [];
    @tracked learningGoals: any[] = [];
    @tracked dailyPlans: any[] = [];
    @tracked classroomAlerts: any[] = [];
    @tracked skillCards: any[] = [];
    @tracked dynamicStudents: any[] = [];
    @tracked studentsLoading = true;
    // Per-section loading flags (progressive — each section renders as its data arrives)
    @tracked entriesLoading = true;
    @tracked goalsLoading = true;
    @tracked plansLoading = true;
    @tracked alertsLoading = true;
    get isLoading() { return this.studentsLoading || this.entriesLoading || this.goalsLoading || this.plansLoading; }
    @tracked noteContent = '';
    // Activity feed pagination
    @tracked feedPage = 0;
    feedPageSize = 5;
    // Highlighted entries
    @tracked highlightedEntries: Set<string> = new Set();
    @tracked generatePlanState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked generatePlanError: string | null = null;
    @tracked batchPlanState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchPlanMessage: string | null = null;
    @tracked batchPlanError: string | null = null;

    // ── Manual push: Rebuild Admin from Classroom ──
    // Safety-net that re-pushes every ActivityEntry to Admin as ObservationRecord.
    // Used to recover from Admin Reconcile's aggressive cleanup (known linksTo-resolve bug).
    @tracked rebuildAdminState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked rebuildAdminMsg: string | null = null;
    get isRebuildingAdmin() { return this.rebuildAdminState === 'running'; }

    // ── Manual push: Rebuild HoS mirrors (AEs + Goals + Alerts + Student locations) ──
    @tracked rebuildHosState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked rebuildHosMsg: string | null = null;
    get isRebuildingHos() { return this.rebuildHosState === 'running'; }

    // ── Manual push: Publish daily snapshot for (selectedStudent, viewDate) to Parent Daily ──
    @tracked publishSnapState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked publishSnapMsg: string | null = null;
    get isPublishingSnap() { return this.publishSnapState === 'running'; }


    // ── Staff (mirrored from Admin via Approach C push) ──
    @tracked dynamicStaff: any[] = [];
    @tracked selectedStaffIndex = 0;

    get staffList() {
      return this.dynamicStaff.map((s: any, i: number) => ({
        name: s?.name ?? 'Unknown',
        initials: s?.initials ?? '??',
        color: s?.color ?? s?.avatarColor ?? 'teal',
        id: s?.id ?? '',
        idx: i,
        card: s,
      }));
    }

    @tracked showStaffPicker = false;
    @tracked staffSearchQuery = '';

    get selectedStaff() {
      return this.staffList[this.selectedStaffIndex] ?? null;
    }

    get filteredStaffList() {
      const q = this.staffSearchQuery.toLowerCase().trim();
      if (!q) return this.staffList;
      return this.staffList.filter((s: any) => s.name.toLowerCase().includes(q));
    }

    toggleStaffPicker = () => {
      this.showStaffPicker = !this.showStaffPicker;
      if (this.showStaffPicker) this.staffSearchQuery = '';
    };

    setStaffSearch = (e: Event) => {
      this.staffSearchQuery = (e.target as HTMLInputElement).value;
    };

    pickStaff = (idx: number) => {
      this.selectedStaffIndex = idx;
      this.showStaffPicker = false;
    };

    // Helper: parse date string as local time
    _parseLocal(dateStr: string): Date | null {
      if (!dateStr) return null;
      const parts = dateStr.split(/[-\/]/);
      if (parts.length < 3) return null;
      const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
      return isNaN(d.getTime()) ? null : d;
    }

    // Helper: get the selected date as local Date
    _getViewDate(): Date {
      return this._parseLocal(this.viewDate) ?? new Date();
    }

    // Check if a program is active on the selected viewDate
    // Active = viewDate >= started AND viewDate <= dueDate (if dueDate exists)
    _isActiveOnDate(started: string, dueDate: string): boolean {
      const view = this._getViewDate();
      const s = this._parseLocal(started);
      if (!s) return false;
      // viewDate must be >= started
      if (view.getTime() < s.getTime()) return false;
      // If dueDate exists, viewDate must be <= dueDate
      if (dueDate) {
        const d = this._parseLocal(dueDate);
        if (d && view.getTime() > d.getTime()) return false;
      }
      return true;
    }

    // Backward compat alias
    _isThisWeek(dateStr: string): boolean {
      return this._isActiveOnDate(dateStr, '');
    }

    // ── Alert form state ──
    @tracked showAlertForm = false;
    @tracked alertTitle = '';
    @tracked alertType = 'pickup-change';
    @tracked alertSeverity = 'urgent';
    @tracked alertDesc = '';
    @tracked alertSaving = false;
    // ── Alert inline edit state ──
    @tracked _editAlertId: string | null = null;
    @tracked _editAlertField: string | null = null;
    @tracked _editAlertValue = '';
    @tracked localEntries: any[] = [];
    @tracked selectedEntryType = '';
    @tracked scheduleOverrides: Map<string, any> = new Map();
    @tracked locationOverrides: Map<string, string> = new Map();

    constructor(owner: any, args: any) {
      super(owner, args);
      this.loadData();
    }

    // ── Host-injected helpers (the correct way to call getCards) ──
    get hostGetCards(): any {
      const a = this.args as any;
      return a.context?.getCards ?? a.context?.actions?.getCards ?? null;
    }
    get hostCommandContext(): any {
      const a = this.args as any;
      return a.context?.commandContext ?? a.context?.actions?.commandContext ?? null;
    }

    async unwrapResource(resource: any, maxMs = 10000): Promise<any[]> {
      try {
        const r: any = resource;
        if (Array.isArray(r)) return r;
        const read = () => Array.isArray(r?.instances) ? r.instances : (Array.isArray(r?.value) ? r.value : null);
        const t0 = Date.now();
        let hasSeenLoading = false;
        while (Date.now() - t0 < maxMs) {
          const loading = r?.isLoading === true;
          if (loading) hasSeenLoading = true;
          const arr = read();
          if (!loading && arr !== null) {
            // Has actual data → return immediately
            if (arr.length > 0) return arr;
            // Resource was loading then stopped → truly empty
            if (hasSeenLoading) return arr;
            // Waited 1.5s without seeing loading → probably truly empty
            if (Date.now() - t0 > 1500) return arr;
          }
          await new Promise((res) => setTimeout(res, 100));
        }
        return read() ?? [];
      } catch (_) { return []; }
    }

    async loadData() {
      const getCards = this.hostGetCards;
      if (!getCards) {
        console.warn('[Classroom] getCards not available on context');
        this.studentsLoading = false;
        this.entriesLoading = false;
        this.goalsLoading = false;
        this.plansLoading = false;
        this.alertsLoading = false;
        return;
      }

      const studentModule = new URL('./student', import.meta.url).href;
      const staffModule = new URL('./staff', import.meta.url).href;
      const activityModule = new URL('./activity-entry', import.meta.url).href;
      const goalModule = new URL('./learning-goal', import.meta.url).href;
      const planModule = new URL('./daily-plan', import.meta.url).href;
      const alertModule = new URL('./classroom-alert', import.meta.url).href;
      const skillModule = new URL('./skill-card', import.meta.url).href;

      // Fire ALL queries immediately — each resolves independently for progressive UI
      const staffRes = getCards(this, () => ({
        filter: { type: { module: staffModule, name: 'Staff' } },
      }));
      const studentsRes = getCards(this, () => ({
        filter: { type: { module: studentModule, name: 'Student' } },
      }));
      const entriesRes = getCards(this, () => ({
        filter: { type: { module: activityModule, name: 'ActivityEntry' } },
      }));
      const goalsRes = getCards(this, () => ({
        filter: { type: { module: goalModule, name: 'LearningGoal' } },
      }));
      const plansRes = getCards(this, () => ({
        filter: { type: { module: planModule, name: 'DailyPlan' } },
      }));
      const alertsRes = getCards(this, () => ({
        filter: { type: { module: alertModule, name: 'ClassroomAlert' } },
      }));
      const skillRes = getCards(this, () => ({
        filter: { type: { module: skillModule, name: 'SkillCard' } },
      }));

      // Each section loads independently — UI updates progressively as data arrives
      this.unwrapResource(staffRes).then((staff) => {
        this.dynamicStaff = staff;
        console.log(`[Classroom] staff loaded: ${staff.length}`);
      }).catch(() => {});

      this.unwrapResource(studentsRes).then((students) => {
        this.dynamicStudents = students;
        this.studentsLoading = false;
        console.log(`[Classroom] students loaded: ${students.length}`);
      }).catch(() => { this.studentsLoading = false; });

      this.unwrapResource(entriesRes).then((entries) => {
        this.activityEntries = entries;
        this.entriesLoading = false;
        console.log(`[Classroom] entries loaded: ${entries.length}`);
        this._tryAutoSync();
      }).catch(() => { this.entriesLoading = false; });

      this.unwrapResource(goalsRes).then((goals) => {
        this.learningGoals = goals;
        this.goalsLoading = false;
        console.log(`[Classroom] goals loaded: ${goals.length}`);
        this._tryAutoSync();
      }).catch(() => { this.goalsLoading = false; });

      this.unwrapResource(plansRes).then((plans) => {
        this.dailyPlans = plans;
        this.plansLoading = false;
        console.log(`[Classroom] plans loaded: ${plans.length}`);
        this._tryAutoSync();
      }).catch(() => { this.plansLoading = false; });

      this.unwrapResource(alertsRes).then((alerts) => {
        this.classroomAlerts = alerts;
        this.alertsLoading = false;
        console.log(`[Classroom] alerts loaded: ${alerts.length}`);
      }).catch(() => { this.alertsLoading = false; });

      // SkillCards load lazily — low priority, no loading indicator needed
      this.unwrapResource(skillRes).then((skills) => {
        this.skillCards = skills.filter(
          (c: any) => String(c?.category ?? '') === 'daily-plan' && c?.isActive === true,
        );
      }).catch(() => {});
    }

    get allStudents() {
      // Dynamic: query all Student cards in the realm (auto-updates when HoS pushes new students)
      // Falls back to linksToMany field while dynamic query is still loading
      return this.dynamicStudents.length > 0 ? this.dynamicStudents : (this.args.model?.students ?? []);
    }

    getStudentLocation(student: any): string {
      const key = student?.id ?? student?.name;
      return this.locationOverrides.get(key) ?? student?.location ?? 'In Classroom';
    }

    get inClassroom() { return this.allStudents.filter((s: any) => this.getStudentLocation(s) === 'In Classroom'); }
    get atSpecialists() { return this.allStudents.filter((s: any) => this.getStudentLocation(s) === 'At Specialists'); }
    get absent() { return this.allStudents.filter((s: any) => this.getStudentLocation(s) === 'Absent'); }
    get presentCount() { return this.inClassroom.length + this.atSpecialists.length; }
    get totalCount() { return this.allStudents.length; }

    get selectedStudent() { return this.allStudents[this.selectedStudentIndex] ?? null; }
    get selectedStudentId() { return this.selectedStudent?.id ?? null; }

    // Strip AI-appended metadata like " (Math, current: 0%, target: 66%)"
    _cleanGoalName(s: string): string {
      return String(s ?? '').replace(/\s*\([^)]*\)\s*$/, '').toLowerCase().trim();
    }

    // Build live evidence from ActivityEntries
    // Key: "goalTitle|studentId" (lowercase) to prevent cross-contamination
    get _liveEvidenceByGoal(): Map<string, any[]> {
      const map = new Map<string, any[]>();
      for (const ae of this.activityEntries) {
        const goalName = this._cleanGoalName(String(ae?.suggestedGoal ?? ''));
        const score = String(ae?.score ?? '');
        let studentId = String(ae?.student?.id ?? '');
        if (!studentId) {
          const rel = (ae as any)?.relationships?.student?.links?.self;
          if (rel) studentId = String(rel);
        }
        if (!goalName || !score || !studentId) continue;
        if (String(ae?.aiTagged ?? '') !== 'true') continue;
        const parts = score.split('/');
        const entry = {
          scoreNumerator: Number(parts[0]) || 0,
          scoreDenominator: Number(parts[1]) || 0,
          score,
          text: String(ae?.content ?? '').slice(0, 200),
          author: String(ae?.author?.name ?? ae?.author ?? ''),
          date: ae?.timestamp ? new Date(ae.timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '',
          sourceActivityEntryId: String(ae?.id ?? ''),
          scoreRating: (() => {
            if (!parts[1]) return '';
            const pct = (Number(parts[0]) || 0) / (Number(parts[1]) || 1);
            if (pct >= 0.8) return 'good';
            if (pct >= 0.6) return 'ok';
            return 'needs-improvement';
          })(),
        };
        const key = `${goalName}|${studentId}`;
        if (!map.has(key)) map.set(key, []);
        map.get(key)!.push(entry);
      }
      return map;
    }

    get studentGoals() {
      if (!this.selectedStudentId) return [];
      // Resolve selected student's flat name as fallback for goals pushed via
      // Approach C (which set studentName but no cross-realm linksTo).
      const selStu = this.allStudents.find((s: any) => String(s?.id ?? '') === this.selectedStudentId);
      const selName = selStu
        ? `${String(selStu?.firstName ?? '')} ${String(selStu?.lastName ?? '')}`.trim().toLowerCase()
        : '';
      return this.learningGoals.filter((g: any) => {
        const linksId = String(g?.student?.id ?? '');
        const flatName = String(g?.studentName ?? '').trim().toLowerCase();
        const matched =
          (linksId && linksId === this.selectedStudentId) ||
          (selName && flatName === selName);
        if (!matched) return false;
        const sd = String(g?.startedDate ?? '');
        if (!sd) return true;
        const dd = String(g?.dueDate ?? '');
        let dueDateStr = '';
        if (dd) {
          try { const dt = new Date(dd); dueDateStr = `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; } catch (_) { dueDateStr = dd; }
        }
        return this._isActiveOnDate(sd, dueDateStr);
      });
    }

    getGoalProgress = (goal: any): number => {
      const goalTitle = this._cleanGoalName(String(goal?.goalTitle ?? ''));
      const studentId = String(goal?.student?.id ?? '');
      if (!goalTitle || !studentId) return 0;
      const live = this._liveEvidenceByGoal.get(`${goalTitle}|${studentId}`) ?? [];
      if (live.length === 0) return 0;
      let total = 0;
      for (const ev of live) {
        if (ev.scoreDenominator > 0) {
          total += (ev.scoreNumerator / ev.scoreDenominator) * 100;
        }
      }
      return Math.min(100, Math.round(total / live.length));
    };

    // Today's DailyPlan card for the selected student (if one exists)
    get todayDailyPlan(): any {
      if (!this.selectedStudentId) return null;
      const today = this.viewDate;
      return this.dailyPlans.find((p: any) => {
        const pStudent = String(p?.student?.id ?? '');
        let pDate = '';
        try { const dt = new Date(p?.planDate); pDate = `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; } catch (_) {}
        return pStudent === this.selectedStudentId && pDate === today;
      }) ?? null;
    }

    // Build a set of all known ActivityEntry IDs for orphan detection
    get _activityEntryIds(): Set<string> {
      const ids = new Set<string>();
      for (const a of this.activityEntries) {
        const id = String(a?.id ?? '');
        if (id) ids.add(id);
      }
      return ids;
    }

    get studentSchedule() {
      // During plans loading, show nothing (avoid flashing wrong data)
      if (this.plansLoading) return [];
      const plan = this.todayDailyPlan;
      if (!plan) return [];

      const items = plan.scheduleItems ?? [];
      const aeIds = this._activityEntryIds;

      return items;
    }

    // (Legacy studentSchedule getter removed — the new version above handles
    // both DailyPlan and Student.schedule with overrides)

    get studentEntries() {
      if (!this.selectedStudentId) return [];
      const viewDateStr = this.viewDate; // yyyy-mm-dd

      // Helper: check if a timestamp falls on viewDate (local time, not UTC)
      const matchesDate = (ts: any): boolean => {
        if (!ts) return false;
        try {
          const d = new Date(ts);
          const local = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
          return local === viewDateStr;
        } catch (_) { return false; }
      };

      // Match by activityDate first (if saved), then fallback to timestamp
      const matchesEntry = (e: any): boolean => {
        const ad = String(e?.activityDate ?? '');
        if (ad) return ad === viewDateStr;
        return matchesDate(e?.timestamp);
      };
      const fetched = this.activityEntries
        .filter((e: any) => e.student?.id === this.selectedStudentId && matchesEntry(e));
      const local = this.localEntries
        .filter((e: any) => e.student?.id === this.selectedStudentId && matchesEntry(e));
      return [...local, ...fetched]
        .sort((a: any, b: any) => {
          const ta = a.timestamp ? new Date(a.timestamp).getTime() : 0;
          const tb = b.timestamp ? new Date(b.timestamp).getTime() : 0;
          return tb - ta;
        });
    }

    get pagedEntries() {
      const start = this.feedPage * this.feedPageSize;
      return this.studentEntries.slice(start, start + this.feedPageSize);
    }
    get feedTotalPages() { return Math.ceil(this.studentEntries.length / this.feedPageSize) || 1; }
    get showFeedPagination() { return this.studentEntries.length > this.feedPageSize; }
    get cantPrevFeed() { return this.feedPage <= 0; }
    get cantNextFeed() { return (this.feedPage + 1) * this.feedPageSize >= this.studentEntries.length; }
    get feedPageLabel() { return `${this.feedPage + 1} / ${this.feedTotalPages}`; }
    get feedShowingLabel() {
      const total = this.studentEntries.length;
      if (total === 0) return '';
      const start = this.feedPage * this.feedPageSize + 1;
      const end = Math.min((this.feedPage + 1) * this.feedPageSize, total);
      return `Showing ${start}-${end} of ${total}`;
    }
    nextFeedPage = () => { if (!this.cantNextFeed) this.feedPage++; };
    prevFeedPage = () => { if (!this.cantPrevFeed) this.feedPage--; };

    isHighlighted = (entry: any): boolean => {
      // Saved cards: read from card field
      if (entry?.id && !entry?.isLocal) {
        return String(entry?.highlighted ?? '') === 'true';
      }
      // Local (not-yet-saved) entries: fallback to in-memory set
      const key = entry?.id ?? entry?.content ?? '';
      return this.highlightedEntries.has(key);
    };

    toggleHighlight = async (entry: any) => {
      const key = entry?.id ?? entry?.content ?? '';

      // For saved cards, toggle the field and save
      if (entry?.id && !entry?.isLocal) {
        const newVal = String(entry?.highlighted ?? '') === 'true' ? 'false' : 'true';
        try {
          (entry as any).highlighted = newVal;
          const ctx = this.hostCommandContext;
          if (ctx) {
            const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
            const realmUrl = new URL('./', import.meta.url).href;
            await new SaveCardCommand(ctx).execute({ card: entry, realm: realmUrl });
          }
          this.activityEntries = [...this.activityEntries];
        } catch (e: any) {
          console.warn('[Classroom] highlight toggle failed:', e?.message ?? e);
        }
        return;
      }

      // Local entries: toggle in-memory set
      const next = new Set(this.highlightedEntries);
      if (next.has(key)) { next.delete(key); } else { next.add(key); }
      this.highlightedEntries = next;
    };

    // ── Edit score inline ──
    @tracked _editScoreEntryId: string | null = null;
    @tracked editScoreValue = '';

    isEditingScore = (entry: any): boolean => {
      const id = entry?.id ?? entry?.content ?? '';
      return this._editScoreEntryId === id;
    };
    startEditScore = (entry: any, e: Event) => {
      e.stopPropagation();
      this._editScoreEntryId = entry?.id ?? entry?.content ?? '';
      this.editScoreValue = String(entry?.score ?? '');
    };
    setEditScoreValue = (e: Event) => {
      this.editScoreValue = (e.target as HTMLInputElement).value;
    };
    onScoreKeydown = (entry: any, e: KeyboardEvent) => {
      if (e.key === 'Enter') { e.preventDefault(); this.saveEditScore(entry); }
      else if (e.key === 'Escape') { this._editScoreEntryId = null; }
    };
    saveEditScore = async (entry: any) => {
      const newScore = this.editScoreValue.trim();
      this._editScoreEntryId = null;
      if (!newScore || newScore === String(entry?.score ?? '')) return;

      // Update local entry
      if (entry.isLocal) {
        this.localEntries = this.localEntries.map((e: any) =>
          e === entry ? { ...e, score: newScore } : e
        );
        return;
      }

      // Update saved ActivityEntry card
      try {
        const ctx = (this.args as any).context?.commandContext;
        if (ctx && entry?.id) {
          (entry as any).score = newScore;
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const realmUrl = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card: entry, realm: realmUrl });
          console.log('[Classroom] score saved to card:', newScore);

          // Sync updated score to Admin ObservationRecord + HoS AE mirror (Approach C)
          syncObsToAdmin({
            action: 'upsert',
            ae: entry,
            ctx: this.hostCommandContext,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          syncAeToHos({
            action: 'upsert',
            ae: entry,
            ctx: this.hostCommandContext,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });

          // Also reload entries to ensure UI reflects the change
          const getCards = this.hostGetCards;
          if (getCards) {
            const aeModule = new URL('./activity-entry', import.meta.url).href;
            const res = getCards(this, () => ({
              filter: { type: { module: aeModule, name: 'ActivityEntry' } },
            }));
            this.activityEntries = await this.unwrapResource(res);
          }
          // Trigger plan auto-sync
          this._syncRan = false;
          this._tryAutoSync();
        }
      } catch (e: any) {
        console.warn('[Classroom] score update failed:', e?.message ?? e);
      }
    };

    // ── Delete activity entry ──
    deleteActivityEntry = async (entry: any) => {
      // Remove local entry (not yet saved)
      if (entry.isLocal) {
        this.localEntries = this.localEntries.filter((e: any) => e !== entry);
        return;
      }

      // Delete saved ActivityEntry card via realm HTTP DELETE
      const cardId = String(entry?.id ?? '');
      if (!cardId) return;

      try {
        // Use fetch to send DELETE request to the card's URL
        const response = await fetch(cardId, {
          method: 'DELETE',
          headers: { 'Accept': 'application/vnd.card+json' },
        });
        if (response.ok || response.status === 204 || response.status === 404) {
          console.log('[Classroom] deleted ActivityEntry from realm:', cardId);
        } else {
          console.warn('[Classroom] delete returned status:', response.status);
        }
      } catch (e: any) {
        console.warn('[Classroom] delete fetch failed:', e?.message ?? e);
      }

      // Remove from local tracked array
      this.activityEntries = this.activityEntries.filter((e: any) => String(e?.id ?? '') !== cardId);

      // Delete matching ObservationRecord in Admin + HoS AE mirror (Approach C)
      syncObsToAdmin({
        action: 'delete',
        ae: { id: cardId },
        ctx: this.hostCommandContext,
        getCards: this.hostGetCards,
        host: this,
        unwrapResource: this.unwrapResource.bind(this),
      });
      syncAeToHos({
        action: 'delete',
        ae: { id: cardId },
        ctx: this.hostCommandContext,
        getCards: this.hostGetCards,
        host: this,
        unwrapResource: this.unwrapResource.bind(this),
      });

      // Trigger plan auto-sync (will revert Done items for deleted entries)
      this._syncRan = false;
      this._tryAutoSync();
    };

    get hudAlerts() {
      return this.classroomAlerts.filter((ca: any) => {
        if (ca.resolved === true) return false;
        if (ca.expiresAt) {
          try { if (new Date(ca.expiresAt).getTime() < Date.now()) return false; } catch (_) {}
        }
        return true;
      }).map((ca: any) => ({
        card: ca,
        alertType: String(ca.alertType ?? ''),
        urgency: String(ca.urgency ?? ''),
        message: String(ca.message ?? ''),
        detail: String(ca.detail ?? ''),
        studentName: String(ca.studentName ?? ''),
        verified: ca.verified === true,
        verifiedAt: String(ca.verifiedAt ?? ''),
      }));
    }

    get selectedStudentAlerts() {
      if (!this.selectedStudent) return [];
      const selName = `${this.selectedStudent?.firstName ?? ''} ${this.selectedStudent?.lastName ?? ''}`.trim().toLowerCase();
      return this.hudAlerts.filter((a: any) => {
        const sn = String(a.studentName ?? '').toLowerCase();
        return sn && sn === selName;
      });
    }

    get teacherName() { return this.args.model?.teacher?.name ?? 'Teacher'; }
    get teacherInitials() { return this.args.model?.teacher?.initials ?? ''; }
    get classLabel() { return this.args.model?.classroomName ?? 'Classroom'; }

    get todayFormatted() {
      const d = new Date(this.viewDate + 'T12:00:00');
      return d.toLocaleDateString('en-US', {
        weekday: 'long',
        month: 'short',
        day: 'numeric',
      });
    }
    get isViewingToday() {
      return this.viewDate === (this.constructor as any)._localDateStr();
    }

    @action selectStudent(index: number) {
      this.selectedStudentIndex = index;
      this.feedPage = 0;
      this.noteContent = '';
      if (this.textareaEl) this.textareaEl.value = '';
    }

    @action selectStudentByObj(student: any) {
      const idx = this.allStudents.indexOf(student);
      this.selectedStudentIndex = idx >= 0 ? idx : 0;
      this.noteContent = '';
      if (this.textareaEl) this.textareaEl.value = '';
    }

    isSelectedStudent(student: any) {
      return this.allStudents.indexOf(student) === this.selectedStudentIndex;
    }

    private textareaEl: HTMLTextAreaElement | null = null;

    @action updateNote(event: Event) {
      this.textareaEl = event.target as HTMLTextAreaElement;
      this.noteContent = this.textareaEl.value;
    }

    @action postNote() {
      if (!this.noteContent.trim() || !this.selectedStudent) return;
      const staff = this.selectedStaff;
      const entry: any = {
        content: this.noteContent,
        entryType: this.selectedEntryType || 'Academic',
        author: staff ? { name: staff.name, initials: staff.initials, color: staff.color } : { name: this.teacherName, initials: this.teacherInitials, color: 'teal' },
        authorCard: staff?.card ?? null,
        student: this.selectedStudent,
        timestamp: new Date().toISOString(),
        activityDate: this.viewDate,
        aiTagged: 'processing',
        isLocal: true,
      };
      this.localEntries = [entry, ...this.localEntries];
      const noteText = this.noteContent;
      this.noteContent = '';
      this.selectedEntryType = '';
      if (this.textareaEl) this.textareaEl.value = '';

      // Fire-and-forget AI classification
      this.classifyObservation(entry, noteText);
    }

    async classifyObservation(entry: any, noteText: string) {
      try {
        const student = entry.student;
        const studentName = student?.name ?? student?.shortName ?? 'Student';

        // Build schedule context from today's DailyPlan (not student.schedule)
        const planItems = this.studentSchedule;
        const scheduleLines = planItems.map((b: any) => {
          const status = typeof b?.status === 'object' ? (b.status?.value ?? 'Upcoming') : String(b?.status ?? 'Upcoming');
          // Send activity name only (no time) — AI must copy activity name exactly
          return `- ${b.activity} (time: ${b.time ?? '?'}, status: ${status})`;
        });
        const scheduleContext = scheduleLines.join('\n');

        // Build goal context
        // IMPORTANT: format so AI copies ONLY the goal title (before the | separator)
        const goals = this.studentGoals;
        const goalLines = goals.map((g: any) =>
          `- "${g.goalTitle}" | domain: ${g.domain}, current: ${this.getGoalProgress(g)}%, target: ${g.targetMastery}%`
        );
        const goalContext = goalLines.join('\n');

        // Resolve Boxel command context (same pattern as ai-student-workflow)
        const argsAny = this.args as any;
        const commandContext =
          argsAny.context?.commandContext ??
          argsAny.context?.actions?.commandContext ??
          argsAny.commandContext ??
          this;

        const result = await classifyWithAi(
          commandContext,
          noteText,
          studentName,
          scheduleContext,
          goalContext,
        );

        let matchedBlock = result.matchedBlock;

        // Immutable update: replace entry with new object so Glimmer re-renders
        // NOTE: Don't auto-apply schedule/goal changes yet — wait for user to Accept
        this.localEntries = this.localEntries.map((e: any) =>
          e === entry
            ? {
                content: entry.content,
                entryType: result.entryType,
                author: entry.author,
                student: entry.student,
                timestamp: entry.timestamp,
                isLocal: entry.isLocal,
                domain: result.domain,
                confidence: result.confidence,
                reasoning: result.reasoning,
                matchedBlock: matchedBlock,
                suggestedGoal: result.suggestedGoal,
                score: result.score || entry.score,
                flagNote: result.flagNote || entry.flagNote,
                aiTagged: 'true',
              }
            : e,
        );
      } catch (err) {
        console.error('AI classification failed:', err);
        // Immutable update: replace entry with new object to clear processing state
        this.localEntries = this.localEntries.map((e: any) =>
          e === entry
            ? {
                content: entry.content,
                entryType: entry.entryType,
                author: entry.author,
                student: entry.student,
                timestamp: entry.timestamp,
                isLocal: entry.isLocal,
                aiTagged: 'false',
              }
            : e,
        );
      }
    }

    // STRICT version: only matches if activity name EXACTLY equals or STARTS WITH the matched block.
    completeScheduleBlockStrict(student: any, matchedBlockName: string, score?: string) {
      const schedule = this.studentSchedule;
      const normalMatch = matchedBlockName.toLowerCase().trim();
      if (!normalMatch) { console.log('[Classroom] matchedBlock is empty, skipping'); return; }
      console.log(`[Classroom] trying to match "${normalMatch}" against ${schedule.length} schedule items`);
      for (let i = 0; i < schedule.length; i++) {
        const block = schedule[i];
        const rawStatus = block?.status;
        const statusStr = typeof rawStatus === 'object' ? (rawStatus?.value ?? '') : String(rawStatus ?? '');
        console.log(`[Classroom]   [${i}] "${block?.activity}" status="${statusStr}"`);
        if (statusStr === 'Done') continue;
        const activityLower = String(block?.activity ?? '').toLowerCase().trim();
        // Strict: exact match OR activity starts with the matched block name
        // OR matched block starts with the activity name (for abbreviated matches)
        const isExact = activityLower === normalMatch;
        const actStartsWithMatch = activityLower.startsWith(normalMatch);
        const matchStartsWithAct = normalMatch.startsWith(activityLower) && activityLower.length >= 5;
        if (isExact || actStartsWithMatch || matchStartsWithAct) {
          const key = `${student.id ?? student.name}:${i}`;
          this.scheduleOverrides = new Map(this.scheduleOverrides).set(key, {
            time: block.time,
            activity: block.activity,
            status: 'Done',
            result: score || block.result,
            goalTag: block.goalTag,
          });
          console.log(`[Classroom] marked schedule block "${block.activity}" as Done (matched "${matchedBlockName}")`);
          break;
        }
      }
    }

    completeScheduleBlock(student: any, matchedBlockName: string, score?: string) {
      const schedule = student?.schedule ?? [];
      const normalMatch = matchedBlockName.toLowerCase().trim();
      for (let i = 0; i < schedule.length; i++) {
        const block = schedule[i];
        if (block.status === 'Done') continue;
        const activityLower = (block.activity ?? '').toLowerCase();
        if (activityLower.includes(normalMatch) || normalMatch.includes(activityLower)) {
          const key = `${student.id ?? student.name}:${i}`;
          this.scheduleOverrides = new Map(this.scheduleOverrides).set(key, {
            activity: block.activity,
            status: 'Done',
            result: score || block.result,
            goalTag: block.goalTag,
          });
          break;
        }
      }
    }

    revertScheduleBlock(student: any, matchedBlockName: string) {
      const schedule = student?.schedule ?? [];
      const normalMatch = matchedBlockName.toLowerCase().trim();
      for (let i = 0; i < schedule.length; i++) {
        const block = schedule[i];
        const activityLower = (block.activity ?? '').toLowerCase();
        if (activityLower.includes(normalMatch) || normalMatch.includes(activityLower)) {
          const key = `${student.id ?? student.name}:${i}`;
          if (this.scheduleOverrides.has(key)) {
            const newMap = new Map(this.scheduleOverrides);
            newMap.delete(key);
            this.scheduleOverrides = newMap;
          }
          break;
        }
      }
    }

    @action async acceptSuggestion(entry: any) {
      // Step 1: Mark entry as accepted in local UI immediately
      this.localEntries = this.localEntries.map((e: any) =>
        e === entry
          ? {
              content: e.content, entryType: e.entryType, author: e.author,
              student: e.student, timestamp: e.timestamp, isLocal: e.isLocal,
              domain: e.domain, confidence: e.confidence, reasoning: e.reasoning,
              matchedBlock: e.matchedBlock, suggestedGoal: e.suggestedGoal,
              score: e.score, flagNote: e.flagNote, aiTagged: e.aiTagged,
              aiAccepted: true,
            }
          : e,
      );

      // Step 2: Save ActivityEntry card FIRST (need savedCard.id for schedule linking)
      let savedCard: any = null;
      try {
        const argsAny = this.args as any;
        const ctx = argsAny.context?.commandContext ?? argsAny.context?.actions?.commandContext ?? argsAny.commandContext ?? null;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const { ActivityEntry } = await import('./activity-entry');
          const realmUrl = new URL('./', import.meta.url).href;

          const card = new ActivityEntry();
          card.content = entry.content;
          (card as any).entryType = entry.entryType;
          card.domain = entry.domain;
          card.confidence = entry.confidence;
          card.reasoning = entry.reasoning;
          card.matchedBlock = entry.matchedBlock;
          card.suggestedGoal = entry.suggestedGoal;
          card.score = entry.score;
          card.flagNote = entry.flagNote;
          card.aiTagged = 'true';
          (card as any).activityDate = entry.activityDate || this.viewDate;
          (card as any).timestamp = new Date(entry.timestamp);
          (card as any).student = this.selectedStudent;
          (card as any).author = entry.authorCard ?? this.selectedStaff?.card ?? this.args.model?.teacher;

          const savedResult = await new SaveCardCommand(ctx).execute({ card, realm: realmUrl });
          savedCard = savedResult?.savedCard ?? savedResult ?? card;
          console.log('[Classroom] saved ActivityEntry', String(savedCard?.id ?? '(unknown id)'));

          // Push into activityEntries immediately (instant UX)
          this.activityEntries = [...this.activityEntries, savedCard];

          // Remove the local entry by content+timestamp (can't use object identity
          // because we replaced the entry earlier in this.localEntries.map).
          const entryContent = String(entry?.content ?? '');
          const entryTs = entry?.timestamp ? new Date(entry.timestamp).getTime() : 0;
          this.localEntries = this.localEntries.filter((e: any) => {
            const eContent = String(e?.content ?? '');
            const eTs = e?.timestamp ? new Date(e.timestamp).getTime() : 0;
            // Keep only entries that DON'T match this accepted one
            return !(eContent === entryContent && eTs === entryTs);
          });

          // Push to Admin ObservationRecord + HoS AE mirror (Approach C — realtime sync)
          syncObsToAdmin({
            action: 'upsert',
            ae: savedCard,
            student: this.selectedStudent,
            staff: entry.authorCard ?? this.selectedStaff?.card ?? this.args.model?.teacher,
            ctx: this.hostCommandContext,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          syncAeToHos({
            action: 'upsert',
            ae: savedCard,
            student: this.selectedStudent,
            staff: entry.authorCard ?? this.selectedStaff?.card ?? this.args.model?.teacher,
            ctx: this.hostCommandContext,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });

          // Reload from realm to get fully-resolved linksTo relationships (student, author)
          // This ensures _liveEvidenceByGoal can properly compute ae.student?.id
          const getCardsHelper = this.hostGetCards;
          if (getCardsHelper) {
            const aeModule = new URL('./activity-entry', import.meta.url).href;
            const res = getCardsHelper(this, () => ({
              filter: { type: { module: aeModule, name: 'ActivityEntry' } },
            }));
            try {
              this.activityEntries = await this.unwrapResource(res);
            } catch (_) { /* keep pushed version */ }
          }

          // Sync goal mastery immediately (cache for Admin)
          console.log('[Classroom] entry.suggestedGoal =', JSON.stringify(entry.suggestedGoal));
          console.log('[Classroom] goals available:', this.learningGoals.map((g: any) => ({ title: String(g?.goalTitle ?? ''), studentId: String(g?.student?.id ?? '') })));
          if (entry.suggestedGoal) {
            const goalTitleTrim = this._cleanGoalName(entry.suggestedGoal);
            const matchedGoal = this.learningGoals.find((g: any) => {
              if (this._cleanGoalName(String(g?.goalTitle ?? '')) !== goalTitleTrim) return false;
              return String(g?.student?.id ?? '') === String(this.selectedStudent?.id ?? '');
            });
            if (!matchedGoal) console.log('[Classroom] NO goal matched for suggestedGoal:', entry.suggestedGoal);
            if (matchedGoal) {
              const liveProgress = this.getGoalProgress(matchedGoal);
              const oldMastery = Number(matchedGoal?.currentMastery ?? 0);
              if (liveProgress !== oldMastery) {
                (matchedGoal as any).currentMastery = liveProgress;
                await new SaveCardCommand(ctx).execute({ card: matchedGoal, realm: realmUrl });
                console.log(`[Classroom] goal "${entry.suggestedGoal}" mastery: ${oldMastery}% -> ${liveProgress}%`);
                this.learningGoals = [...this.learningGoals];
              }
            }
          }
        }
      } catch (saveErr) {
        console.warn('[Classroom] save ActivityEntry failed (non-fatal):', saveErr);
      }

      // Step 3: Auto-complete the matched schedule block using savedCard.id
      if (entry.matchedBlock || entry.suggestedGoal) {
        try {
          const plan = this.todayDailyPlan;
          const items = plan?.scheduleItems ?? this.studentSchedule;
          if (items && items.length > 0) {
            const matchBlock = String(entry.matchedBlock ?? '').toLowerCase().trim();
            const matchGoal = String(entry.suggestedGoal ?? '').toLowerCase().trim();
            let foundIndex = -1;

            // Strategy A: match by activity name (strict)
            const cleanBlock = matchBlock.replace(/^\d{1,2}:\d{2}\s+/, '');
            if (matchBlock || cleanBlock) {
              for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const statusStr = typeof item?.status === 'object' ? (item.status?.value ?? '') : String(item?.status ?? '');
                if (statusStr === 'Done') continue;
                const actLower = String(item?.activity ?? '').toLowerCase().trim();
                if (actLower === matchBlock || actLower === cleanBlock || actLower.startsWith(matchBlock) || actLower.startsWith(cleanBlock) || (matchBlock.startsWith(actLower) && actLower.length >= 5) || (cleanBlock.startsWith(actLower) && actLower.length >= 5)) {
                  foundIndex = i;
                  console.log(`[Classroom] Strategy A matched: "${item.activity}" ← matchedBlock="${entry.matchedBlock}"`);
                  break;
                }
              }
            }

            // Strategy B: if A failed, match by goalTag ↔ suggestedGoal
            if (foundIndex < 0 && matchGoal) {
              for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const statusStr = typeof item?.status === 'object' ? (item.status?.value ?? '') : String(item?.status ?? '');
                if (statusStr === 'Done') continue;
                const tagLower = String(item?.goalTag ?? '').toLowerCase().trim();
                if (tagLower && (tagLower === matchGoal || tagLower.includes(matchGoal) || matchGoal.includes(tagLower))) {
                  foundIndex = i;
                  console.log(`[Classroom] Strategy B matched: "${item.activity}" (goalTag="${item.goalTag}") ← suggestedGoal="${entry.suggestedGoal}"`);
                  break;
                }
              }
            }

            // Strategy C: keyword-based fuzzy match from observation text
            if (foundIndex < 0 && entry.observation) {
              const obsLower = String(entry.observation).toLowerCase();
              const keywordMap: [string[], string[]][] = [
                [['pe ', 'pe,', 'pe.', 'physical education', 'gym class', 'gym '], ['specials', 'art/music/pe', 'pe']],
                [['art class', 'drawing', 'painting', 'craft'], ['specials', 'art/music/pe', 'art']],
                [['music class', 'singing', 'instrument', 'choir'], ['specials', 'art/music/pe', 'music']],
                [['occupational therapy', ' ot ', 'fine motor'], ['specialist', 'ot']],
                [['speech therapy', ' st ', 'speech session'], ['specialist', 'st', 'speech']],
                [['lunch', 'recess', 'playground', 'ate his', 'ate her', 'ate all'], ['lunch', 'recess']],
                [['sensory break', 'snack', 'calming', 'movement break'], ['sensory', 'snack', 'break']],
                [['homeroom', 'morning meeting', 'arrival'], ['homeroom', 'arrival']],
                [['science', 'experiment', 'social studies'], ['science', 'social studies']],
                [['social skill', 'group work', 'taking turns', 'sharing'], ['social skill', 'group work']],
                [['closing', 'reflection', 'pack up', 'dismissal'], ['closing', 'reflection', 'dismissal']],
              ];
              for (const [obsKeywords, blockKeywords] of keywordMap) {
                const obsMatch = obsKeywords.some(k => obsLower.includes(k));
                if (!obsMatch) continue;
                for (let i = 0; i < items.length; i++) {
                  const item = items[i];
                  const statusStr = typeof item?.status === 'object' ? (item.status?.value ?? '') : String(item?.status ?? '');
                  if (statusStr === 'Done') continue;
                  const actLower = String(item?.activity ?? '').toLowerCase();
                  if (blockKeywords.some(bk => actLower.includes(bk))) {
                    foundIndex = i;
                    console.log(`[Classroom] Strategy C matched: "${item.activity}" ← observation keyword in "${obsKeywords.find(k => obsLower.includes(k))}"`);
                    break;
                  }
                }
                if (foundIndex >= 0) break;
              }
            }

            if (foundIndex >= 0) {
              const matchedItem = items[foundIndex];
              (matchedItem as any).status = 'Done';
              if (entry.score) (matchedItem as any).result = entry.score;
              const savedId = String(savedCard?.id ?? '');
              if (savedId) (matchedItem as any).sourceActivityEntryId = savedId;
              console.log(`[Classroom] marked "${matchedItem.activity}" as Done, linked to: ${savedId}`);

              if (plan) {
                const argsAny = this.args as any;
                const ctx = argsAny.context?.commandContext ?? argsAny.context?.actions?.commandContext ?? null;
                if (ctx) {
                  const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
                  const realmUrl = new URL('./', import.meta.url).href;
                  await new SaveCardCommand(ctx).execute({ card: plan, realm: realmUrl });
                  console.log('[Classroom] DailyPlan card saved with Done status');
                }
              } else {
                const student = this.selectedStudent;
                const key = `${student?.id ?? student?.name}:${foundIndex}`;
                this.scheduleOverrides = new Map(this.scheduleOverrides).set(key, {
                  time: matchedItem.time,
                  activity: matchedItem.activity,
                  status: 'Done',
                  result: entry.score || matchedItem.result,
                  goalTag: matchedItem.goalTag,
                });
              }
            } else {
              console.log(`[Classroom] no schedule match found for matchedBlock="${entry.matchedBlock}" or suggestedGoal="${entry.suggestedGoal}"`);
            }
          }
        } catch (schedErr) {
          console.warn('[Classroom] schedule update failed (non-fatal):', schedErr);
        }
      }
    }

    @action rejectSuggestion(entry: any) {
      // Revert any schedule block override (in case it was applied)
      const student = this.selectedStudent;
      if (entry.matchedBlock && student) {
        this.revertScheduleBlock(student, entry.matchedBlock);
      }

      // Strip all AI fields, keep as plain note
      this.localEntries = this.localEntries.map((e: any) =>
        e === entry
          ? {
              content: e.content,
              entryType: e.entryType,
              author: e.author,
              student: e.student,
              timestamp: e.timestamp,
              isLocal: e.isLocal,
              aiTagged: 'rejected',
            }
          : e,
      );
    }

    @action editSuggestion(entry: any) {
      // Toggle the manual goal picker on this entry
      this.localEntries = this.localEntries.map((e: any) =>
        e === entry
          ? { ...e, showManualGoalPicker: !e.showManualGoalPicker }
          : e,
      );
    }

    @action manualAssignGoal(entry: any, e: Event) {
      const goalTitle = (e.target as HTMLSelectElement).value;
      if (!goalTitle) return;

      if (goalTitle === '__none__') {
        // No goal — keep as routine, hide picker
        this.localEntries = this.localEntries.map((le: any) =>
          le === entry
            ? { ...le, suggestedGoal: '', matchedBlock: '', showManualGoalPicker: false, reasoning: 'Manually set: no goal', confidence: 100 }
            : le,
        );
        return;
      }

      const goal = this.studentGoals.find((g: any) => String(g?.goalTitle ?? '') === goalTitle);
      if (!goal) return;

      // Replace the AI suggestion with the manually chosen goal
      this.localEntries = this.localEntries.map((le: any) =>
        le === entry
          ? {
              ...le,
              suggestedGoal: goalTitle,
              domain: String(goal?.domain?.value ?? goal?.domain ?? le.domain),
              matchedBlock: goalTitle,
              showManualGoalPicker: false,
              reasoning: 'Manually reassigned by teacher',
              confidence: 100,
            }
          : le,
      );
    }

    // ── Sync Evidence: remove orphaned evidence entries whose ActivityEntry no longer exists ──
    get isSyncingEvidence() { return this.syncEvidenceState === 'syncing'; }
    @tracked syncEvidenceState: 'idle' | 'syncing' | 'done' = 'idle';
    @tracked syncEvidenceMsg = '';

    @action async syncEvidence() {
      this.syncEvidenceState = 'syncing';
      this.syncEvidenceMsg = 'Checking evidence links...';
      try {
        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmUrl = new URL('./', import.meta.url).href;

        // Get all activity entry IDs
        const activityIds = new Set(this.activityEntries.map((a: any) => String(a?.id ?? '')).filter((s: string) => s));

        let cleaned = 0;
        for (const goal of this.learningGoals) {
          const entries = goal.evidenceEntries ?? [];
          if (entries.length === 0) continue;

          const validEntries = entries.filter((ev: any) => {
            const srcId = String(ev?.sourceActivityEntryId ?? '');
            if (!srcId) return true; // legacy evidence without link — keep
            return activityIds.has(srcId);
          });

          if (validEntries.length < entries.length) {
            const removed = entries.length - validEntries.length;
            (goal as any).evidenceEntries = validEntries;
            await new SaveCardCommand(ctx).execute({ card: goal, realm: realmUrl });
            cleaned += removed;
            console.log(`[Classroom] removed ${removed} orphaned evidence from "${goal.goalTitle}"`);
          }
        }

        // Also sync DailyPlan schedule items — revert "Done" if ActivityEntry is gone
        let plansCleaned = 0;
        for (const plan of this.dailyPlans) {
          const items = plan?.scheduleItems ?? [];
          let planChanged = false;
          for (const item of items) {
            const srcId = String((item as any)?.sourceActivityEntryId ?? '');
            const itemStatusStr = typeof item?.status === 'object' ? String(item.status?.value ?? '') : String(item?.status ?? '');
            if (srcId && !activityIds.has(srcId) && itemStatusStr === 'Done') {
              (item as any).status = 'Upcoming';
              (item as any).result = '';
              (item as any).sourceActivityEntryId = '';
              planChanged = true;
              plansCleaned++;
            }
          }
          if (planChanged) {
            await new SaveCardCommand(ctx).execute({ card: plan, realm: realmUrl });
            console.log(`[Classroom] reverted schedule items in plan for ${plan?.student?.firstName ?? 'unknown'}`);
          }
        }

        // Reload goals + plans
        const getCards = this.hostGetCards;
        if (getCards) {
          const goalModule = new URL('./learning-goal', import.meta.url).href;
          const goalsRes = getCards(this, () => ({
            filter: { type: { module: goalModule, name: 'LearningGoal' } },
          }));
          this.learningGoals = await this.unwrapResource(goalsRes);

          const planModule = new URL('./daily-plan', import.meta.url).href;
          const plansRes = getCards(this, () => ({
            filter: { type: { module: planModule, name: 'DailyPlan' } },
          }));
          this.dailyPlans = await this.unwrapResource(plansRes);
        }

        this.syncEvidenceState = 'done';
        const parts = [];
        if (cleaned > 0) parts.push(`${cleaned} evidence`);
        if (plansCleaned > 0) parts.push(`${plansCleaned} plan items`);
        this.syncEvidenceMsg = parts.length > 0 ? `Cleaned: ${parts.join(', ')}` : 'All in sync';
      } catch (e: any) {
        this.syncEvidenceState = 'done';
        this.syncEvidenceMsg = `Error: ${e?.message ?? e}`;
      }
    }

    @tracked _syncRan = false;
    _tryAutoSync() {
      if (this._syncRan) return;
      if (this.entriesLoading || this.plansLoading || this.goalsLoading) return;
      this._syncRan = true;
      this._autoSyncPlanScores();
      this._autoSyncGoalMastery();
    }

    // ── Auto-sync plan scores with current ActivityEntry data ──
    async _autoSyncPlanScores() {
      try {
        const ctx = (this.args as any).context?.commandContext ?? (this.args as any).context?.actions?.commandContext;
        if (!ctx) return;

        // Build maps from current ActivityEntries.
        // BUG FIX (2026-04-21): when multiple AEs share the same suggestedGoal,
        // keep the MOST RECENT one (by timestamp). Previous code was last-write-wins
        // by iteration order, which made the plan show stale (older) scores.
        const aeById = new Map<string, any>();
        const aeByGoal = new Map<string, any>();
        for (const ae of this.activityEntries) {
          const id = String(ae?.id ?? '');
          if (id) aeById.set(id, ae);
          const goal = String(ae?.suggestedGoal ?? '');
          if (goal && String(ae?.aiTagged ?? '') === 'true') {
            const key = goal.toLowerCase().trim();
            const prev = aeByGoal.get(key);
            if (!prev) {
              aeByGoal.set(key, ae);
            } else {
              const prevTs = prev?.timestamp ? new Date(prev.timestamp).getTime() : 0;
              const aeTs = ae?.timestamp ? new Date(ae.timestamp).getTime() : 0;
              if (aeTs > prevTs) aeByGoal.set(key, ae);
            }
          }
        }

        // Fuzzy lookup: case-insensitive, then partial includes (both directions)
        const findAeByTag = (tag: string): any => {
          const t = tag.toLowerCase().trim();
          if (!t) return null;
          const exact = aeByGoal.get(t);
          if (exact) return exact;
          for (const [key, ae] of aeByGoal) {
            if (key.includes(t) || t.includes(key)) return ae;
          }
          return null;
        };

        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmUrl = new URL('./', import.meta.url).href;

        for (const plan of this.dailyPlans) {
          const items = plan?.scheduleItems ?? [];
          let changed = false;

          for (const item of items) {
            const srcId = String(item?.sourceActivityEntryId ?? '');
            const goalTag = String(item?.goalTag ?? '');
            const status = String(item?.status?.value ?? item?.status ?? '');

            if (status !== 'Done') continue;
            if (!srcId && !goalTag) continue; // routine block, skip

            // Find linked ActivityEntry
            let ae = srcId ? (aeById.get(srcId) ?? null) : null;
            if (!ae && goalTag) ae = findAeByTag(goalTag);

            if (!ae) {
              // ActivityEntry deleted → revert
              (item as any).status = 'Upcoming';
              (item as any).result = '';
              changed = true;
            } else {
              // Update score from ActivityEntry
              const liveScore = String(ae?.score ?? '');
              if (liveScore && liveScore !== String(item?.result ?? '')) {
                (item as any).result = liveScore;
                changed = true;
              }
            }
          }

          if (changed) {
            await new SaveCardCommand(ctx).execute({ card: plan, realm: realmUrl });
            console.log('[Classroom] auto-synced plan scores');
          }
        }
      } catch (e) {
        console.warn('[Classroom] auto-sync plan scores failed:', e);
      }
    }

    async _autoSyncGoalMastery() {
      try {
        const ctx = (this.args as any).context?.commandContext ?? (this.args as any).context?.actions?.commandContext;
        if (!ctx) return;
        const liveEvidence = this._liveEvidenceByGoal;
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmUrl = new URL('./', import.meta.url).href;
        for (const goal of this.learningGoals) {
          const goalTitle = String(goal?.goalTitle ?? '');
          if (!goalTitle) continue;
          const liveProgress = this.getGoalProgress(goal);
          const current = Number(goal?.currentMastery ?? 0);
          if (current !== liveProgress) {
            (goal as any).currentMastery = liveProgress;
            await new SaveCardCommand(ctx).execute({ card: goal, realm: realmUrl });
            console.log(`[Classroom] synced goal "${goalTitle}" mastery: ${current}% -> ${liveProgress}%`);
          }
        }

        // Push all Classroom Goals to HoS (fire-and-forget).
        // Helper dedups by field compare, so unchanged goals skip — no wasted writes.
        // This catches both new goals (first time → created) and mastery changes (updated).
        const getCards = this.hostGetCards;
        if (getCards) {
          const goalsWithTitle = this.learningGoals.filter((g: any) => String(g?.goalTitle ?? '').trim());
          if (goalsWithTitle.length > 0) {
            syncGoalsToHos({
              goals: goalsWithTitle,
              ctx,
              getCards,
              host: this,
              unwrapResource: this.unwrapResource.bind(this),
            }).then((r) => {
              if (r.created + r.updated > 0) {
                console.log(`[Classroom-HoS] pushed goals: ${r.created} new, ${r.updated} updated, ${r.skipped} skipped`);
              } else if (r.failed > 0) {
                console.warn('[Classroom-HoS] goal push had failures:', r.errors);
              }
            }).catch((e) => console.warn('[Classroom-HoS] goal push exception:', e));
          }
        }
      } catch (e) {
        console.warn('[Classroom] auto-sync goal mastery failed:', e);
      }
    }

    // ── Manual push: Rebuild Admin ObservationRecord from every ActivityEntry ──
    @action async handleRebuildAdmin() {
      this.rebuildAdminState = 'running';
      this.rebuildAdminMsg = null;

      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.rebuildAdminState = 'error';
        this.rebuildAdminMsg = 'Context unavailable';
        return;
      }

      const entries = this.activityEntries.filter((e: any) => e && !e.isLocal && e.id);
      const total = entries.length;
      if (total === 0) {
        this.rebuildAdminState = 'success';
        this.rebuildAdminMsg = 'No entries to push';
        return;
      }

      const studentById = new Map<string, any>();
      for (const s of this.allStudents) {
        const sid = String((s as any)?.id ?? '');
        if (sid) studentById.set(sid, s);
      }
      const staffById = new Map<string, any>();
      for (const s of this.dynamicStaff) {
        const sid = String((s as any)?.id ?? '');
        if (sid) staffById.set(sid, s);
      }

      let created = 0;
      let updated = 0;
      let skipped = 0;
      let failed = 0;

      for (const ae of entries) {
        const studRaw: any = (ae as any)?.student;
        let studentId = '';
        if (studRaw?.id) studentId = String(studRaw.id);
        else if ((ae as any)?.relationships?.student?.links?.self) studentId = String((ae as any).relationships.student.links.self);
        const student = studentById.get(studentId) ?? studRaw;

        const auRaw: any = (ae as any)?.author;
        let authorId = '';
        if (auRaw?.id) authorId = String(auRaw.id);
        else if ((ae as any)?.relationships?.author?.links?.self) authorId = String((ae as any).relationships.author.links.self);
        const staff = staffById.get(authorId) ?? auRaw;

        try {
          const result = await syncObsToAdmin({
            action: 'upsert',
            ae,
            student,
            staff,
            ctx,
            getCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (result.success) {
            if (result.operation === 'created') created++;
            else if (result.operation === 'updated') updated++;
            else skipped++;
          } else {
            failed++;
          }
        } catch (e: any) {
          failed++;
          console.warn('[Classroom] rebuild-admin push failed for AE:', ae?.id, e?.message);
        }
      }

      this.rebuildAdminState = failed > 0 ? 'error' : 'success';
      this.rebuildAdminMsg = `Done: ${created} new, ${updated} updated, ${skipped} unchanged${failed > 0 ? `, ${failed} failed` : ''} (of ${total})`;
    }

    // ── Manual push: Rebuild HoS mirrors (AEs + Goals + Alerts + Student locations) ──
    @action async handleRebuildHos() {
      this.rebuildHosState = 'running';
      this.rebuildHosMsg = null;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.rebuildHosState = 'error';
        this.rebuildHosMsg = 'Context unavailable';
        return;
      }

      let aeOk = 0, aeFail = 0, alertOk = 0, alertFail = 0, locOk = 0, locFail = 0;

      // 1. AEs → HoS mirror
      for (const ae of this.activityEntries) {
        if (!ae?.id || (ae as any).isLocal) continue;
        try {
          const r = await syncAeToHos({
            action: 'upsert', ae,
            ctx, getCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (r.success) aeOk++; else aeFail++;
        } catch (_) { aeFail++; }
      }

      // 2. Goals → HoS mirror (bulk helper)
      let goalOk = 0, goalFail = 0;
      try {
        const goalsWithTitle = this.learningGoals.filter((g: any) => String(g?.goalTitle ?? '').trim());
        const r = await syncGoalsToHos({
          goals: goalsWithTitle,
          ctx, getCards, host: this,
          unwrapResource: this.unwrapResource.bind(this),
        });
        goalOk = ((r as any)?.created ?? 0) + ((r as any)?.updated ?? 0) + ((r as any)?.skipped ?? 0);
        goalFail = (r as any)?.failed ?? 0;
      } catch (_) { goalFail = 1; }

      // 3. Alerts → HoS mirror
      for (const alert of this.classroomAlerts) {
        if (!alert?.id) continue;
        try {
          const r = await syncAlertToHos({
            action: 'upsert', alert,
            ctx, getCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (r.success) alertOk++; else alertFail++;
        } catch (_) { alertFail++; }
      }

      // 4. Student locations → HoS mirror
      for (const student of this.allStudents) {
        if (!String(student?.studentId ?? '').trim()) continue;
        try {
          const r = await syncStudentLocationToHos({
            student,
            ctx, getCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (r.success) locOk++; else locFail++;
        } catch (_) { locFail++; }
      }

      const totalFail = aeFail + goalFail + alertFail + locFail;
      this.rebuildHosState = totalFail > 0 ? 'error' : 'success';
      this.rebuildHosMsg = `AEs ${aeOk}✓/${aeFail}✗ · Goals ${goalOk}✓/${goalFail}✗ · Alerts ${alertOk}✓/${alertFail}✗ · Locations ${locOk}✓/${locFail}✗`;
    }

    // ── Manual push: Publish snapshot for (selectedStudent, viewDate) to Parent Daily ──
    @action async handlePublishSnapshot() {
      this.publishSnapState = 'running';
      this.publishSnapMsg = null;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.publishSnapState = 'error';
        this.publishSnapMsg = 'Context unavailable';
        return;
      }
      const student = this.selectedStudent;
      if (!student) {
        this.publishSnapState = 'error';
        this.publishSnapMsg = 'Select a student first';
        return;
      }
      const studentSlug = String((student as any)?.id ?? '').split('/').pop() ?? '';
      const snapshotDate = this.viewDate;
      if (!studentSlug || !snapshotDate) {
        this.publishSnapState = 'error';
        this.publishSnapMsg = 'Missing studentSlug or viewDate';
        return;
      }
      try {
        const r = await syncSnapshotToParent({
          studentSlug, snapshotDate,
          ctx, getCards, host: this,
          unwrapResource: this.unwrapResource.bind(this),
        });
        if (r.success) {
          this.publishSnapState = 'success';
          this.publishSnapMsg = `${r.operation} — ${r.entryCount ?? 0} entries`;
        } else {
          this.publishSnapState = 'error';
          this.publishSnapMsg = r.error ?? String(r.operation ?? 'failed');
        }
      } catch (e: any) {
        this.publishSnapState = 'error';
        this.publishSnapMsg = e?.message ?? String(e);
      }
    }

    // ── AI Generate Today's Plan for the selected student (inline) ──
    @action async handleGeneratePlan() {
      this.generatePlanState = 'running';
      this.generatePlanError = null;
      try {
        const student = this.selectedStudent;
        if (!student) throw new Error('Select a student first');

        // Check active goals for this week
        if (this.studentGoals.length === 0) {
          throw new Error('No active goals for this week. Fetch goals from Admin first, or check your selected date.');
        }

        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');
        const getCards = this.hostGetCards;
        if (!getCards) throw new Error('getCards unavailable');

        const skillCard = this.skillCards[0];
        if (!skillCard) throw new Error('No active daily-plan SkillCard found');

        const realmHref = new URL('./', import.meta.url).href;
        const today = this.viewDate;

        const result = await generateDailyPlanSingle({
          student,
          classroom: this.args.model,
          date: today,
          teacherNote: '',
          skillCard,
          commandContext: ctx,
          realmHref,
          getCards,
          parent: this,
        });

        console.log(`[Classroom] generated plan for ${result.studentName} in ${result.latencyMs}ms`);

        // Reload plans to pick up the new one
        const planModule = new URL('./daily-plan', import.meta.url).href;
        const plansRes = getCards(this, () => ({
          filter: { type: { module: planModule, name: 'DailyPlan' } },
        }));
        this.dailyPlans = await this.unwrapResource(plansRes);

        this.generatePlanState = 'success';
      } catch (e: any) {
        console.error('[Classroom] generate plan failed', e);
        this.generatePlanState = 'error';
        this.generatePlanError = e?.message ?? String(e);
      }
    }

    // ── AI Batch Generate plans for ALL students ──
    @action async handleBatchGeneratePlans() {
      this.batchPlanState = 'running';
      this.batchPlanMessage = null;
      this.batchPlanError = null;
      try {
        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');
        const getCards = this.hostGetCards;
        if (!getCards) throw new Error('getCards unavailable');

        const skillCard = this.skillCards[0];
        if (!skillCard) throw new Error('No active daily-plan SkillCard found');

        const realmHref = new URL('./', import.meta.url).href;

        // Check active goals for all students
        if (this.learningGoals.length === 0) {
          throw new Error('No active goals found. Fetch goals from Admin first.');
        }

        const result = await generateDailyPlansBatch({
          students: this.allStudents,
          classroom: this.args.model,
          date: this.viewDate,
          teacherNote: '',
          skillCard,
          commandContext: ctx,
          realmHref,
          getCards,
          parent: this,
        });

        // Reload plans
        const planModule = new URL('./daily-plan', import.meta.url).href;
        const plansRes = getCards(this, () => ({
          filter: { type: { module: planModule, name: 'DailyPlan' } },
        }));
        this.dailyPlans = await this.unwrapResource(plansRes);

        this.batchPlanState = 'success';
        this.batchPlanMessage = `Generated ${result.created.length} plans in ${result.totalLatencyMs}ms (${result.splitsUsed} AI call${result.splitsUsed > 1 ? 's' : ''})${result.failed.length > 0 ? `, ${result.failed.length} failed` : ''}`;
      } catch (e: any) {
        console.error('[Classroom] batch generate failed', e);
        this.batchPlanState = 'error';
        this.batchPlanError = e?.message ?? String(e);
      }
    }

    // ── Date navigation ──
    @action setViewDate(e: Event) {
      this.viewDate = (e.target as HTMLInputElement).value;
    }
    @action prevDay() {
      const d = new Date(this.viewDate + 'T12:00:00');
      d.setDate(d.getDate() - 1);
      this.viewDate = (this.constructor as any)._localDateStr(d);
    }
    @action nextDay() {
      const d = new Date(this.viewDate + 'T12:00:00');
      d.setDate(d.getDate() + 1);
      this.viewDate = (this.constructor as any)._localDateStr(d);
    }
    @action goToday() {
      this.viewDate = (this.constructor as any)._localDateStr();
    }

    // ── Alert CRUD ──
    @action toggleAlertForm() { this.showAlertForm = !this.showAlertForm; }
    @action setAlertTitle(e: Event) { this.alertTitle = (e.target as HTMLInputElement).value; }
    @action setAlertType(e: Event) { this.alertType = (e.target as HTMLSelectElement).value; }
    @action setAlertSeverity(e: Event) { this.alertSeverity = (e.target as HTMLSelectElement).value; }
    @action setAlertDesc(e: Event) { this.alertDesc = (e.target as HTMLTextAreaElement).value; }

    @action async saveAlert() {
      if (!this.alertTitle.trim()) return;
      this.alertSaving = true;
      try {
        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');

        const typeMap: Record<string, string> = {
          'pickup-change': 'Pickup Change', 'parent-note': 'Parent Note',
          'schedule': 'Schedule', 'sub-alert': 'Sub Alert',
          'medical': 'Medical', 'behavioral': 'Behavioral',
        };

        const { ClassroomAlert } = await import('./classroom-alert');
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmUrl = new URL('./', import.meta.url).href;

        const card = new ClassroomAlert();
        (card as any).alertType = typeMap[this.alertType] ?? this.alertType;
        (card as any).urgency = this.alertSeverity === 'info' ? 'Info' : 'Urgent';
        (card as any).message = this.alertTitle.trim();
        (card as any).detail = this.alertDesc;
        (card as any).createdAt = new Date();
        (card as any).createdBy = this.teacherName;
        (card as any).resolved = false;
        (card as any).verified = false;
        // Expires at end of today by default
        const eod = new Date();
        eod.setHours(23, 59, 59, 999);
        (card as any).expiresAt = eod;

        // Student-specific alert types get the selected student's name
        const studentTypes = ['pickup-change', 'parent-note', 'medical', 'behavioral'];
        if (studentTypes.includes(this.alertType) && this.selectedStudent) {
          (card as any).studentName = `${this.selectedStudent?.firstName ?? ''} ${this.selectedStudent?.lastName ?? ''}`.trim();
        }

        await new SaveCardCommand(ctx).execute({ card, realm: realmUrl });
        console.log('[Classroom] saved ClassroomAlert:', this.alertTitle);

        // Auto-push to HoS mirror
        syncAlertToHos({
          action: 'upsert', alert: card,
          ctx, getCards: this.hostGetCards, host: this,
          unwrapResource: this.unwrapResource.bind(this),
        }).catch((e) => console.warn('[Classroom-HoS] alert push exception:', e));

        this.classroomAlerts = [...this.classroomAlerts, card];

        this.alertTitle = '';
        this.alertDesc = '';
        this.showAlertForm = false;
      } catch (e: any) {
        console.error('[Classroom] save alert failed', e);
      } finally {
        this.alertSaving = false;
      }
    }

    @action async dismissAlert(alertObj: any) {
      try {
        const card = alertObj.card ?? alertObj;
        (card as any).resolved = true;
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const realmUrl = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card, realm: realmUrl });

          // Auto-push resolved=true to HoS mirror
          syncAlertToHos({
            action: 'upsert', alert: card,
            ctx, getCards: this.hostGetCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          }).catch((e) => console.warn('[Classroom-HoS] alert dismiss push exception:', e));
        }
        this.classroomAlerts = [...this.classroomAlerts];
      } catch (e: any) {
        console.warn('[Classroom] dismiss alert failed:', e?.message ?? e);
      }
    }

    // ── Alert inline edit (double-click to edit) ──
    isEditingAlert = (alertObj: any, fieldName: string): boolean => {
      const id = String(alertObj?.card?.id ?? alertObj?.id ?? '');
      return this._editAlertId === id && this._editAlertField === fieldName;
    };
    startEditAlert = (alertObj: any, fieldName: string) => {
      const id = String(alertObj?.card?.id ?? alertObj?.id ?? '');
      this._editAlertId = id;
      this._editAlertField = fieldName;
      this._editAlertValue = String((alertObj as any)[fieldName] ?? '');
    };
    setEditAlertValue = (e: Event) => {
      this._editAlertValue = (e.target as HTMLInputElement).value;
    };
    onAlertEditKeydown = (alertObj: any, e: KeyboardEvent) => {
      if (e.key === 'Enter') { e.preventDefault(); this.saveAlertEdit(alertObj); }
      else if (e.key === 'Escape') { this._editAlertId = null; this._editAlertField = null; }
    };
    saveAlertEdit = async (alertObj: any) => {
      const field = this._editAlertField;
      const newVal = this._editAlertValue.trim();
      this._editAlertId = null;
      this._editAlertField = null;
      if (!field || !newVal) return;

      const card = alertObj.card ?? alertObj;
      if (String((card as any)[field] ?? '') === newVal) return;

      try {
        (card as any)[field] = newVal;
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const realmUrl = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card, realm: realmUrl });
          console.log(`[Classroom] alert ${field} updated to: ${newVal}`);

          // Auto-push edited field to HoS mirror
          syncAlertToHos({
            action: 'upsert', alert: card,
            ctx, getCards: this.hostGetCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          }).catch((e) => console.warn('[Classroom-HoS] alert edit push exception:', e));
        }
        this.classroomAlerts = [...this.classroomAlerts];
      } catch (e: any) {
        console.warn('[Classroom] alert edit failed:', e?.message ?? e);
      }
    };

    @action setEntryType(type: string) {
      this.selectedEntryType = this.selectedEntryType === type ? '' : type;
    }

    @action async setStudentLocation(location: string) {
      const student = this.selectedStudent;
      if (!student) return;
      const key = student.id ?? student.name;
      // Update in-memory cache for immediate UI
      this.locationOverrides = new Map(this.locationOverrides).set(key, location);
      // Persist to Student card
      try {
        (student as any).location = location;
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const realmUrl = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card: student, realm: realmUrl });
          console.log(`[Classroom] student "${student?.firstName ?? ''} ${student?.lastName ?? ''}" location saved: ${location}`);

          // Auto-push location to HoS Student mirror
          syncStudentLocationToHos({
            student,
            ctx, getCards: this.hostGetCards, host: this,
            unwrapResource: this.unwrapResource.bind(this),
          }).catch((e) => console.warn('[Classroom-HoS] student location push exception:', e));
        }
      } catch (e: any) {
        console.warn('[Classroom] setStudentLocation failed:', e?.message ?? e);
      }
    }

    get selectedStudentLocation(): string {
      return this.getStudentLocation(this.selectedStudent);
    }

    isSelected(student: any) {
      return this.allStudents.indexOf(student) === this.selectedStudentIndex;
    }

    getStudentIndex(student: any) {
      return this.allStudents.indexOf(student);
    }

    // Extract string from potential enum object (e.g. {value: "Done"} → "Done")
    itemStatus = (item: any): string => {
      const s = item?.status;
      if (!s) return '';
      return typeof s === 'object' ? String(s?.value ?? '') : String(s);
    };
    isItemDone = (item: any): boolean => this.itemStatus(item) === 'Done';
    isItemCurrent = (item: any): boolean => this.itemStatus(item) === 'Current';

    getStaffColorClass(color: string) {
      if (color === 'teal') return 'teal';
      if (color === 'purple') return 'purple';
      if (color === 'coral') return 'coral';
      if (color === 'amber') return 'amber';
      return 'teal';
    }

    getDomainColorClass(domain: string) {
      switch (domain) {
        case 'Math': return 'coral';
        case 'Reading': return 'amber';
        case 'Social': return 'purple';
        case 'Behavioral': return 'amber';
        case 'Motor': return 'teal';
        default: return 'teal';
      }
    }

    getEntryTypeClass(type: string) {
      switch (type) {
        case 'Academic': return 'academic';
        case 'Social': return 'social';
        case 'Behavioral': return 'behavioral';
        default: return 'academic';
      }
    }

    <template>
      <div class='hero-frame'>
        {{!-- Frame Bar --}}
        <div class='frame-bar'>
          <span class='frame-title'>{{this.classLabel}} · {{this.teacherName}}</span>
          <a class='frame-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main'>
            Parent Report →
          </a>
          <button
            type='button'
            class='frame-rebuild-btn'
            title='Push every ActivityEntry to Admin — recovers lost ObservationRecords'
            disabled={{this.isRebuildingAdmin}}
            {{on 'click' this.handleRebuildAdmin}}
          >
            {{#if this.isRebuildingAdmin}}Pushing…{{else}}⇪ Rebuild Admin{{/if}}
          </button>
          {{#if this.rebuildAdminMsg}}
            <span class='frame-rebuild-msg {{if (eq this.rebuildAdminState "error") "is-error" "is-ok"}}'>
              {{this.rebuildAdminMsg}}
            </span>
          {{/if}}
          <button
            type='button'
            class='frame-rebuild-btn'
            title='Push all AEs / Goals / Alerts / Student locations to HoS mirrors'
            disabled={{this.isRebuildingHos}}
            {{on 'click' this.handleRebuildHos}}
          >
            {{#if this.isRebuildingHos}}Pushing…{{else}}⇪ Rebuild HoS{{/if}}
          </button>
          {{#if this.rebuildHosMsg}}
            <span class='frame-rebuild-msg {{if (eq this.rebuildHosState "error") "is-error" "is-ok"}}'>
              {{this.rebuildHosMsg}}
            </span>
          {{/if}}
          <button
            type='button'
            class='frame-rebuild-btn'
            title='Publish snapshot for selected student + viewDate to Parent Daily'
            disabled={{this.isPublishingSnap}}
            {{on 'click' this.handlePublishSnapshot}}
          >
            {{#if this.isPublishingSnap}}Publishing…{{else}}⇪ Publish Snapshot{{/if}}
          </button>
          {{#if this.publishSnapMsg}}
            <span class='frame-rebuild-msg {{if (eq this.publishSnapState "error") "is-error" "is-ok"}}'>
              {{this.publishSnapMsg}}
            </span>
          {{/if}}
          <div class='frame-date-nav'>
            <button type='button' class='date-nav-btn' {{on 'click' this.prevDay}}>←</button>
            <input
              type='date'
              class='date-nav-input'
              value={{this.viewDate}}
              {{on 'change' this.setViewDate}}
            />
            <button type='button' class='date-nav-btn' {{on 'click' this.nextDay}}>→</button>
            {{#unless this.isViewingToday}}
              <button type='button' class='date-nav-today' {{on 'click' this.goToday}}>Today</button>
            {{/unless}}
          </div>
        </div>

        {{!-- HUD Banner --}}
        {{#if this.hudAlerts.length}}
          <div class='hud-banner'>
            {{#each this.hudAlerts as |alert|}}
              <div class='hud-alert {{if (eq alert.alertType "Pickup Change") "urgent"}} {{if (eq alert.alertType "Medical") "urgent"}} {{if (eq alert.alertType "Schedule") "schedule"}} {{if (eq alert.alertType "Sub Alert") "sub"}} {{if (eq alert.alertType "Parent Note") "note"}} {{if (eq alert.alertType "Behavioral") "note"}}'>
                {{#if (eq alert.alertType "Pickup Change")}}
                  <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='2'><path d='M8 4v4M8 11v1'/><path d='M3 14h10L8 3 3 14z'/></svg>
                {{else if (eq alert.alertType "Schedule")}}
                  <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='8' r='6'/><path d='M8 5v3.5l2.5 1.5'/></svg>
                {{else if (eq alert.alertType "Sub Alert")}}
                  <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='6' r='3'/><path d='M3 14c0-2.5 2.5-4 5-4s5 1.5 5 4'/></svg>
                {{else}}
                  <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='8' r='6'/><path d='M7 7h1v4'/><circle cx='8' cy='5' r='0.5' fill='currentColor'/></svg>
                {{/if}}
                <span class='hud-text'>
                  <strong>{{alert.alertType}}{{#if alert.studentName}}: {{alert.studentName}}{{/if}}</strong>
                  {{alert.message}}
                </span>
                {{#if alert.verified}}
                  <span class='hud-badge'>VERIFIED {{alert.verifiedAt}}</span>
                {{/if}}
                {{#if alert.detail}}
                  <span class='hud-detail'>{{alert.detail}}</span>
                {{/if}}
                <button class='hud-dismiss' type='button' {{on 'click' (fn this.dismissAlert alert)}} title='Dismiss'>x</button>
              </div>
            {{/each}}
          </div>
        {{/if}}

        {{!-- 3-Column Dashboard --}}
        <div class='classroom-dashboard'>

          {{!-- COLUMN 1: Roster --}}
          <div class='cd-roster'>
            <header class='cd-col-header'>
              <h3 class='cd-col-title'>Today's Roster</h3>
              <span class='cd-col-count'>{{this.presentCount}} of {{this.totalCount}} present</span>
            </header>

            {{#if this.inClassroom.length}}
              <div class='roster-section'>
                <div class='roster-label'>
                  <span class='roster-location'>
                    <svg width='10' height='10' viewBox='0 0 10 10' fill='currentColor'><circle cx='5' cy='5' r='4'/></svg>
                    In Classroom
                  </span>
                  <span class='roster-count'>{{this.inClassroom.length}}</span>
                </div>
                {{#each this.inClassroom as |student|}}
                  <div class='roster-student' role='button' {{on "click" (fn this.selectStudentByObj student)}}>
                    <div class='rs-avatar'>
                      {{#if student.avatar}}
                        <img src={{student.avatar}} alt='' />
                      {{/if}}
                      <span class='rs-status present'></span>
                    </div>
                    <div class='rs-info'>
                      <span class='rs-name'>{{if student.shortName student.shortName "Student"}}</span>
                      <div class='rs-tags'>
                        {{#each student.tags as |tag|}}
                          <span class='rs-tag {{if (eq tag.label "IEP") "iep"}} {{if (eq tag.label "Allergy") "allergy"}} {{if (eq tag.label "504") "plan"}}'>{{tag.label}}</span>
                        {{/each}}
                      </div>
                    </div>
                  </div>
                {{/each}}
              </div>
            {{/if}}

            {{#if this.atSpecialists.length}}
              <div class='roster-section'>
                <div class='roster-label'>
                  <span class='roster-location away'>
                    <svg width='10' height='10' viewBox='0 0 10 10' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M2 5h6M5 2l3 3-3 3'/></svg>
                    At Specialists
                  </span>
                  <span class='roster-count'>{{this.atSpecialists.length}}</span>
                </div>
                {{#each this.atSpecialists as |student|}}
                  <div class='roster-student away' role='button' {{on "click" (fn this.selectStudentByObj student)}}>
                    <div class='rs-avatar'>
                      {{#if student.avatar}}
                        <img src={{student.avatar}} alt='' />
                      {{/if}}
                      <span class='rs-status away'></span>
                    </div>
                    <div class='rs-info'>
                      <span class='rs-name'>{{if student.shortName student.shortName "Student"}}</span>
                      <span class='rs-location'>{{student.locationDetail}}</span>
                      {{#if student.returnTime}}
                        <span class='rs-return'>{{student.returnTime}}</span>
                      {{/if}}
                    </div>
                  </div>
                {{/each}}
              </div>
            {{/if}}

            {{#if this.absent.length}}
              <div class='roster-section'>
                <div class='roster-label'>
                  <span class='roster-location absent'>
                    <svg width='10' height='10' viewBox='0 0 10 10' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M2 2l6 6M8 2l-6 6'/></svg>
                    Absent
                  </span>
                  <span class='roster-count'>{{this.absent.length}}</span>
                </div>
                {{#each this.absent as |student|}}
                  <div class='roster-student absent-row' role='button' {{on "click" (fn this.selectStudentByObj student)}}>
                    <div class='rs-avatar'>
                      {{#if student.avatar}}
                        <img src={{student.avatar}} alt='' />
                      {{/if}}
                      <span class='rs-status absent'></span>
                    </div>
                    <div class='rs-info'>
                      <span class='rs-name'>{{if student.shortName student.shortName "Student"}}</span>
                      <span class='rs-reason'>{{student.locationDetail}}</span>
                    </div>
                  </div>
                {{/each}}
              </div>
            {{/if}}
          </div>

          {{!-- COLUMN 2: Student Detail --}}
          <div class='cd-daily'>
            {{#if this.selectedStudent}}
              <header class='cd-student-header'>
                <div class='cd-student-id'>
                  <div class='cd-student-avatar'>
                    <img src={{this.selectedStudent.avatar}} alt={{this.selectedStudent.name}} />
                  </div>
                  <div class='cd-student-info'>
                    <h2 class='cd-student-name'>{{this.selectedStudent.name}}</h2>
                    <span class='cd-student-meta'>
                      {{this.selectedStudent.grade}}
                      {{#if this.selectedStudent.age}}
                        · Age {{this.selectedStudent.age}}
                      {{/if}}
                    </span>
                    <div class='cd-student-tags'>
                      {{#each this.selectedStudent.tags as |tag|}}
                        <span class='cd-tag {{if (eq tag.label "IEP") "iep"}} {{if (eq tag.label "Allergy") "allergy"}} {{if (eq tag.label "504") "plan"}}'>{{tag.label}}</span>
                      {{/each}}
                    </div>
                  </div>
                </div>
                <div class='cd-location-controls'>
                  <span class='cd-location-label'>Status:</span>
                  <button class='loc-btn {{if (eq this.selectedStudentLocation "In Classroom") "active in-class"}}' type='button' {{on "click" (fn this.setStudentLocation "In Classroom")}}>
                    <svg width='8' height='8' viewBox='0 0 8 8' fill='currentColor'><circle cx='4' cy='4' r='3'/></svg>
                    In Class
                  </button>
                  <button class='loc-btn {{if (eq this.selectedStudentLocation "At Specialists") "active specialist"}}' type='button' {{on "click" (fn this.setStudentLocation "At Specialists")}}>
                    <svg width='8' height='8' viewBox='0 0 8 8' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M1.5 4h5M4.5 1.5L7 4l-2.5 2.5'/></svg>
                    Specialist
                  </button>
                  <button class='loc-btn {{if (eq this.selectedStudentLocation "Absent") "active absent"}}' type='button' {{on "click" (fn this.setStudentLocation "Absent")}}>
                    <svg width='8' height='8' viewBox='0 0 8 8' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M1.5 1.5l5 5M6.5 1.5l-5 5'/></svg>
                    Absent
                  </button>
                </div>

                {{#if this.selectedStudent.supportStaff}}
                  <div class='cd-student-staff'>
                    <span class='cd-staff-label'>Working with</span>
                    <div class='cd-staff-assigned'>
                      <span class='staff-avatar-sm {{this.getStaffColorClass this.selectedStudent.supportStaff.color}}'>{{this.selectedStudent.supportStaff.initials}}</span>
                      <span class='cd-staff-name'>{{this.selectedStudent.supportStaff.name}}</span>
                    </div>
                  </div>
                {{/if}}
              </header>

              {{!-- Student Alerts (from ClassroomAlert cards) --}}
              {{#if this.selectedStudentAlerts.length}}
                <div class='cd-alerts'>
                  {{#each this.selectedStudentAlerts as |alert|}}
                    <div class='cd-alert {{if (eq alert.urgency "Urgent") "urgent" "note"}}'>
                      {{#if (eq alert.urgency "Urgent")}}
                        <svg width='14' height='14' viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M7 4v3M7 9v.5'/><path d='M3 12h8L7 3 3 12z'/></svg>
                      {{else}}
                        <svg width='14' height='14' viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='7' cy='7' r='5.5'/><path d='M7 5v3'/><circle cx='7' cy='10' r='0.5' fill='currentColor'/></svg>
                      {{/if}}
                      <div class='cd-alert-content'>
                        <span class='cd-alert-title'>{{alert.alertType}}</span>
                        {{#if (this.isEditingAlert alert "message")}}
                          <input class='cd-alert-edit-input' type='text' value={{this._editAlertValue}} {{on 'input' this.setEditAlertValue}} {{on 'keydown' (fn this.onAlertEditKeydown alert)}} {{on 'blur' (fn this.saveAlertEdit alert)}} />
                        {{else}}
                          <span class='cd-alert-text cd-alert-editable' {{on 'dblclick' (fn this.startEditAlert alert "message")}}>{{alert.message}}</span>
                        {{/if}}
                        {{#if (this.isEditingAlert alert "detail")}}
                          <input class='cd-alert-edit-input small' type='text' value={{this._editAlertValue}} {{on 'input' this.setEditAlertValue}} {{on 'keydown' (fn this.onAlertEditKeydown alert)}} {{on 'blur' (fn this.saveAlertEdit alert)}} />
                        {{else}}
                          {{#if alert.detail}}
                            <span class='cd-alert-detail cd-alert-editable' {{on 'dblclick' (fn this.startEditAlert alert "detail")}}>({{alert.detail}})</span>
                          {{else}}
                            <span class='cd-alert-detail cd-alert-editable cd-alert-add-detail' {{on 'dblclick' (fn this.startEditAlert alert "detail")}}>+ detail</span>
                          {{/if}}
                        {{/if}}
                      </div>
                      <button class='cd-alert-dismiss' type='button' {{on 'click' (fn this.dismissAlert alert)}} title='Dismiss'>x</button>
                    </div>
                  {{/each}}
                </div>
              {{/if}}

              {{!-- Add Alert button + inline form --}}
              <div class='cd-add-alert-area'>
                <button
                  type='button'
                  class='cd-add-alert-btn'
                  {{on 'click' this.toggleAlertForm}}
                >
                  {{if this.showAlertForm "Cancel" "Add Alert"}}
                </button>

                {{#if this.showAlertForm}}
                  <div class='cd-alert-form'>
                    <div class='cd-af-row'>
                      <input
                        type='text'
                        class='cd-af-input'
                        placeholder='Alert message (e.g. Pickup changed to Aunt Wei @ 3:30)'
                        value={{this.alertTitle}}
                        {{on 'input' this.setAlertTitle}}
                      />
                    </div>
                    <div class='cd-af-row cd-af-selects'>
                      <select {{on 'change' this.setAlertType}}>
                        <option value='pickup-change'>Pickup Change</option>
                        <option value='parent-note'>Parent Note</option>
                        <option value='schedule'>Schedule</option>
                        <option value='sub-alert'>Sub Alert</option>
                        <option value='medical'>Medical</option>
                        <option value='behavioral'>Behavioral</option>
                      </select>
                      <select {{on 'change' this.setAlertSeverity}}>
                        <option value='urgent'>Urgent</option>
                        <option value='info'>Info</option>
                      </select>
                    </div>
                    <div class='cd-af-row'>
                      <textarea
                        class='cd-af-input'
                        rows='2'
                        placeholder='Details (optional)'
                        value={{this.alertDesc}}
                        {{on 'input' this.setAlertDesc}}
                      ></textarea>
                    </div>
                    <button
                      type='button'
                      class='cd-af-save'
                      disabled={{this.alertSaving}}
                      {{on 'click' this.saveAlert}}
                    >
                      {{if this.alertSaving "Saving..." "Save Alert"}}
                    </button>
                  </div>
                {{/if}}
              </div>

              {{!-- Schedule --}}
                <div class='cd-plan'>
                  <h4 class='cd-section-title'>
                    Today's Plan
                    {{#if this.todayDailyPlan}}
                      <a class='cd-edit-plan-link' href={{this.todayDailyPlan.id}}>
                        Edit
                      </a>
                    {{/if}}
                    <button
                      type='button'
                      class='cd-gen-plan-btn'
                      disabled={{eq this.generatePlanState 'running'}}
                      {{on 'click' this.handleGeneratePlan}}
                    >
                      {{#if (eq this.generatePlanState 'running')}}
                        ...
                      {{else}}
                        ✨ This Student
                      {{/if}}
                    </button>
                    <button
                      type='button'
                      class='cd-gen-plan-btn cd-batch-btn'
                      disabled={{eq this.batchPlanState 'running'}}
                      {{on 'click' this.handleBatchGeneratePlans}}
                    >
                      {{#if (eq this.batchPlanState 'running')}}
                        Batch...
                      {{else}}
                        ⚡ All Students
                      {{/if}}
                    </button>
                  </h4>
                  {{#if (eq this.generatePlanState 'error')}}
                    <p class='cd-gen-error'>{{this.generatePlanError}}</p>
                  {{/if}}
                  {{#if (eq this.batchPlanState 'success')}}
                    <p class='cd-gen-success'>{{this.batchPlanMessage}}</p>
                  {{/if}}
                  {{#if (eq this.batchPlanState 'error')}}
                    <p class='cd-gen-error'>{{this.batchPlanError}}</p>
                  {{/if}}
              {{#if this.studentSchedule.length}}
                  <div class='cd-schedule'>
                    {{#each this.studentSchedule as |item|}}
                      <div class='cd-sched-item {{if (this.isItemDone item) "done"}} {{if (this.isItemCurrent item) "current"}}'>
                        {{#if (this.isItemDone item)}}
                          <span class='cd-sched-check'>
                            <svg width='10' height='10' viewBox='0 0 10 10' fill='none' stroke='currentColor' stroke-width='2'><path d='M2 5.5L4 7.5 8 3'/></svg>
                          </span>
                        {{else}}
                          <span class='cd-sched-dot'></span>
                        {{/if}}
                        <div class='cd-sched-content'>
                          <span class='cd-sched-activity'>{{item.activity}}</span>
                          {{#if item.result}}
                            <span class='cd-sched-result good'>{{item.result}}</span>
                          {{/if}}
                          {{#if (this.isItemCurrent item)}}
                            <span class='cd-sched-tag'>Now</span>
                          {{/if}}
                          {{#if item.goalTag}}
                            <span class='cd-sched-tag goal'>{{item.goalTag}}</span>
                          {{/if}}
                        </div>
                      </div>
                    {{/each}}
                  </div>
              {{else}}
                {{#if this.plansLoading}}
                  <p class='cd-loading-plan'>Loading plan...</p>
                {{else}}
                  <p class='cd-empty-plan'>No plan for today yet. Use the Daily Plan Manager to create or AI-generate one.</p>
                {{/if}}
              {{/if}}
                </div>

              {{!-- Goals — mirrored from Admin via Approach C push --}}
                <div class='cd-goals'>
                  <h4 class='cd-section-title'>Active Goals <span class='cd-section-badge'>{{this.studentGoals.length}}</span></h4>
                  {{#if this.studentGoals.length}}
                    <div class='cd-goal-cards'>
                      {{#each this.studentGoals as |goal|}}
                        <a class='cd-goal-card' href={{goal.id}}>
                          <div class='cd-gc-header'>
                            <span class='cd-gc-domain {{this.getDomainColorClass goal.domain}}'>{{goal.domain}}</span>
                            <span class='cd-gc-pct'>{{this.getGoalProgress goal}}%</span>
                            <span class='cd-gc-edit'>Edit</span>
                          </div>
                          <span class='cd-gc-title'>{{goal.goalTitle}}</span>
                          <div class='cd-gc-track'>
                            <div class='cd-gc-fill' style='width: {{this.getGoalProgress goal}}%'></div>
                          </div>
                        </a>
                      {{/each}}
                    </div>
                  {{else}}
                    <p class='cd-empty-goals'>No goals yet. Click Fetch to import from Admin.</p>
                  {{/if}}
                </div>

            {{else}}
              <div class='empty-state'>Select a student from the roster</div>
            {{/if}}
          </div>

          {{!-- COLUMN 3: Activity Feed --}}
          <div class='cd-feed'>
            {{!-- Quick Entry --}}
            <div class='cd-quick-entry'>
              <div class='qe-input-row'>
                <div class='qe-avatar-wrap'>
                  <button class='qe-avatar-btn' type='button' {{on 'click' this.toggleStaffPicker}}>
                    {{#if this.selectedStaff}}
                      <span class='staff-avatar-sm {{this.selectedStaff.color}}'>{{this.selectedStaff.initials}}</span>
                    {{else}}
                      <span class='staff-avatar-sm teal'>??</span>
                    {{/if}}
                  </button>
                  {{#if this.showStaffPicker}}
                    <div class='staff-picker'>
                      <div class='sp-header'>
                        <input class='sp-search' type='text' placeholder='Search staff...' value={{this.staffSearchQuery}} {{on 'input' this.setStaffSearch}} />
                      </div>
                      {{#each this.filteredStaffList as |s|}}
                        <button class='sp-item {{if (eq this.selectedStaffIndex s.idx) "active"}}' type='button' {{on 'click' (fn this.pickStaff s.idx)}}>
                          <span class='staff-avatar-sm {{s.color}}'>{{s.initials}}</span>
                          <span class='sp-name'>{{s.name}}</span>
                        </button>
                      {{/each}}
                      {{#unless this.staffList.length}}
                        <div class='sp-empty'>No staff yet. Click Fetch.</div>
                      {{/unless}}
                    </div>
                  {{/if}}
                </div>
                <textarea class='qe-textarea' placeholder='Quick note about {{this.selectedStudent.shortName}}....' {{on "input" this.updateNote}}></textarea>
              </div>
              <div class='qe-type-selector'>
                <span class='qe-type-hint'>Hint:</span>
                <button class='type-btn {{if (eq this.selectedEntryType "Academic") "active"}}' type='button' {{on "click" (fn this.setEntryType "Academic")}}>Academic</button>
                <button class='type-btn {{if (eq this.selectedEntryType "Social") "active"}}' type='button' {{on "click" (fn this.setEntryType "Social")}}>Social</button>
                <button class='type-btn {{if (eq this.selectedEntryType "Behavioral") "active"}}' type='button' {{on "click" (fn this.setEntryType "Behavioral")}}>Behavioral</button>
              </div>
              <div class='qe-actions'>
                <div class='qe-attach'>
                  <button class='qe-attach-btn' title='Add photo' type='button'>
                    <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><rect x='2' y='3' width='12' height='10' rx='2'/><circle cx='5.5' cy='6.5' r='1.5'/><path d='M2 11l3-3 2 2 4-4 3 3'/></svg>
                  </button>
                  <button class='qe-attach-btn' title='Voice note' type='button'>
                    <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M8 2v8M5 6v4a3 3 0 006 0V6'/><path d='M8 14v1'/></svg>
                  </button>
                </div>
                <button class='qe-submit' type='button' {{on "click" this.postNote}}>
                  <span>Post</span>
                  <svg width='14' height='14' viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='2'><path d='M2 7h10M8 3l4 4-4 4'/></svg>
                </button>
              </div>
              <div class='qe-hint'>
                <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='6' cy='6' r='5'/><path d='M6 4v2'/><circle cx='6' cy='8' r='0.5' fill='currentColor'/></svg>
                <span>AI will tag after you post</span>
              </div>
            </div>

            {{!-- Feed Header --}}
            <header class='cd-feed-header'>
              <h4 class='cd-section-title'>Today's Activity</h4>
              <span class='cd-feed-count'>{{this.studentEntries.length}} entries</span>
            </header>

            {{!-- Feed Entries --}}
            <div class='cd-feed-entries'>
              {{#if this.isLoading}}
                <div class='empty-state'>Loading entries...</div>
              {{else if this.studentEntries.length}}
                {{#each this.pagedEntries as |entry|}}
                  <div class='cd-entry {{if entry.aiAccepted "ai-confirmed"}} {{if (eq entry.aiTagged "true") "ai-processed"}} {{if (eq entry.aiTagged "processing") "ai-analyzing"}} {{if (eq entry.aiTagged "rejected") "ai-rejected"}} {{if entry.isLocal "local-entry"}} {{if (this.isHighlighted entry) "highlighted"}}'>
                    {{!-- Processing indicator --}}
                    {{#if (eq entry.aiTagged "processing")}}
                      <div class='cd-entry-processing'>
                        <div class='ai-spinner'></div>
                        <span>AI analyzing...</span>
                      </div>
                    {{/if}}
                    {{!-- AI confirmed (accepted) — compact bar --}}
                    {{#if entry.aiAccepted}}
                      <div class='cd-entry-confirmed'>
                        <div class='confirmed-header'>
                          <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='2'><path d='M2.5 6.5L5 9l4.5-6'/></svg>
                          <span class='confirmed-label'>Confirmed</span>
                          <span class='ai-type {{this.getEntryTypeClass entry.entryType}}'>{{entry.entryType}}</span>
                          {{#if entry.domain}}
                            <span class='ai-domain {{this.getDomainColorClass entry.domain}}'>{{entry.domain}}</span>
                          {{/if}}
                        </div>
                        {{#if entry.matchedBlock}}
                          <div class='confirmed-plan-card'>
                            <div class='plan-card-icon'>
                              <svg width='10' height='10' viewBox='0 0 10 10' fill='none' stroke='currentColor' stroke-width='2'><path d='M2 5.5L4 7.5 8 3'/></svg>
                            </div>
                            <div class='plan-card-body'>
                              <span class='plan-card-block'>{{entry.matchedBlock}}</span>
                              {{#if entry.score}}
                                <span class='plan-card-score'>{{entry.score}}</span>
                              {{/if}}
                              {{#if entry.suggestedGoal}}
                                <span class='plan-card-goal'>→ {{entry.suggestedGoal}}</span>
                              {{/if}}
                            </div>
                          </div>
                        {{/if}}
                      </div>
                    {{/if}}
                    {{!-- AI classification card (pending review) — only show for localEntries, not fetched cards --}}
                    {{#if (eq entry.aiTagged "true")}}
                      {{#unless entry.aiAccepted}}
                      {{#if entry.isLocal}}
                        <div class='cd-entry-ai'>
                          <div class='ai-row-top'>
                            <div class='ai-badge'>
                              <svg width='10' height='10' viewBox='0 0 10 10' fill='currentColor'><circle cx='5' cy='5' r='4'/></svg>
                              AI Tagged
                            </div>
                            {{#if entry.confidence}}
                              <span class='ai-confidence'>{{entry.confidence}}%</span>
                            {{/if}}
                          </div>
                          <div class='ai-suggestion'>
                            <span class='ai-type {{this.getEntryTypeClass entry.entryType}}'>{{entry.entryType}}</span>
                            {{#if entry.domain}}
                              <span class='ai-domain {{this.getDomainColorClass entry.domain}}'>{{entry.domain}}</span>
                            {{/if}}
                            {{#if entry.matchedBlock}}
                              <span class='ai-block'>{{entry.matchedBlock}}</span>
                            {{/if}}
                            {{#if entry.suggestedGoal}}
                              <span class='ai-goal'>→ {{entry.suggestedGoal}}</span>
                            {{/if}}
                          </div>
                          {{#if entry.reasoning}}
                            <div class='ai-reasoning'>{{entry.reasoning}}</div>
                          {{/if}}
                          <div class='ai-actions'>
                            <button class='ai-accept' type='button' {{on "click" (fn this.acceptSuggestion entry)}}>
                              <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='2'><path d='M2.5 6.5L5 9l4.5-6'/></svg>
                              Accept
                            </button>
                            <button class='ai-edit' type='button' {{on "click" (fn this.editSuggestion entry)}}>
                              <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M8.5 1.5l2 2-6 6H2.5V7.5l6-6z'/></svg>
                              Edit
                            </button>
                            <button class='ai-reject' type='button' {{on "click" (fn this.rejectSuggestion entry)}}>
                              <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M3 3l6 6M9 3l-6 6'/></svg>
                              Dismiss
                            </button>
                          </div>
                          {{#if entry.showManualGoalPicker}}
                            <div class='cd-manual-goal'>
                              <label class='cd-manual-label'>Assign correct goal:</label>
                              <select class='cd-manual-select' {{on 'change' (fn this.manualAssignGoal entry)}}>
                                <option value=''>-- Select goal --</option>
                                {{#each this.studentGoals as |g|}}
                                  <option value={{g.goalTitle}}>{{g.goalTitle}} ({{g.domain}})</option>
                                {{/each}}
                                <option value='__none__'>No goal (routine activity)</option>
                              </select>
                            </div>
                          {{/if}}
                        </div>
                      {{/if}}
                      {{/unless}}
                    {{/if}}
                    {{!-- Rejected/dismissed notice --}}
                    {{#if (eq entry.aiTagged "rejected")}}
                      <div class='cd-entry-dismissed'>
                        <svg width='12' height='12' viewBox='0 0 12 12' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M3 3l6 6M9 3l-6 6'/></svg>
                        <span>AI suggestion dismissed</span>
                      </div>
                    {{/if}}
                    <div class='cd-entry-content'>
                      <div class='cd-entry-header'>
                        <span class='staff-avatar-mini {{this.getStaffColorClass entry.author.color}}'>{{entry.author.initials}}</span>
                        <span class='cd-entry-author'>
                          {{#if entry.author.name}}
                            {{entry.author.name}}
                          {{else if entry.author.firstName}}
                            {{entry.author.firstName}} {{entry.author.lastName}}
                          {{else}}
                            Staff
                          {{/if}}
                        </span>
                        {{#if entry.student}}
                          <span class='cd-entry-for'>→</span>
                          <span class='cd-entry-student-name'>
                            {{#if entry.student.firstName}}
                              {{entry.student.firstName}} {{entry.student.lastName}}
                            {{else if entry.student.name}}
                              {{entry.student.name}}
                            {{/if}}
                          </span>
                        {{/if}}
                        {{#if entry.timestamp}}
                          <span class='cd-entry-time'>{{formatDateTime entry.timestamp 'MMM D, YYYY'}}</span>
                        {{/if}}
                      </div>
                      <p class='cd-entry-text'>{{entry.content}}</p>
                      <div class='cd-entry-tags'>
                        <span class='cd-entry-type {{this.getEntryTypeClass entry.entryType}}'>{{entry.entryType}}</span>
                        {{#if entry.goalLink.goalTitle}}
                          <span class='cd-entry-goal'>→ {{entry.goalLink.goalTitle}}</span>
                        {{/if}}
                        {{#if entry.score}}
                          {{#if (this.isEditingScore entry)}}
                            <input class='cd-score-input' type='text' value={{this.editScoreValue}} {{on 'input' this.setEditScoreValue}} {{on 'keydown' (fn this.onScoreKeydown entry)}} {{on 'blur' (fn this.saveEditScore entry)}} />
                          {{else}}
                            <span class='cd-entry-score good cd-score-editable' {{on 'dblclick' (fn this.startEditScore entry)}}>{{entry.score}}</span>
                          {{/if}}
                        {{/if}}
                        <button class='cd-highlight-btn {{if (this.isHighlighted entry) "active"}}' type='button' {{on 'click' (fn this.toggleHighlight entry)}} title='Toggle highlight'>
                          {{#if (this.isHighlighted entry)}}★ Highlight{{else}}☆ Highlight{{/if}}
                        </button>
                        <button class='cd-delete-btn' type='button' {{on 'click' (fn this.deleteActivityEntry entry)}} title='Delete entry'>
                          ✕
                        </button>
                      </div>
                      {{#if entry.flagNote}}
                        <div class='cd-entry-flag'>{{entry.flagNote}}</div>
                      {{/if}}
                    </div>
                  </div>
                {{/each}}
              {{else}}
                <div class='empty-state'>No activity entries yet</div>
              {{/if}}
              {{#if this.showFeedPagination}}
                <div class='feed-pagination'>
                  <span class='feed-showing'>{{this.feedShowingLabel}}</span>
                  <div class='feed-page-btns'>
                    <button class='feed-page-btn' type='button' disabled={{this.cantPrevFeed}} {{on 'click' this.prevFeedPage}}>Prev</button>
                    <span class='feed-page-label'>{{this.feedPageLabel}}</span>
                    <button class='feed-page-btn' type='button' disabled={{this.cantNextFeed}} {{on 'click' this.nextFeedPage}}>Next</button>
                  </div>
                </div>
              {{/if}}
            </div>
          </div>

        </div>
      </div>

      <style scoped>
        /* ═══ Design Tokens ═══ */
        .hero-frame {
          --surface-0: #fffdfb;
          --surface-1: #faf8f6;
          --surface-2: #f5f2ef;
          --surface-3: #ebe7e3;
          --text-1: #1a1816;
          --text-2: #5c5650;
          --text-3: #8a8279;
          --coral: #e05d50;
          --coral-soft: #fdf0ee;
          --amber: #c08b30;
          --amber-soft: #fdf6e8;
          --purple: #7c5fc4;
          --purple-soft: #f4f0fa;
          --teal: #2a9d8f;
          --teal-soft: #e8f6f4;
          --radius-sm: 6px;
          --radius-md: 10px;
          --radius-lg: 14px;

          display: flex;
          flex-direction: column;
          height: 100%;
          min-height: 700px;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
          color: var(--text-1);
          background: var(--surface-2);
          border-radius: var(--radius-lg);
          overflow: hidden;
          box-shadow: 0 8px 24px rgba(26,24,22,0.08);
        }

        /* ═══ Frame Bar ═══ */
        .frame-bar {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.75rem 1rem;
          background: #1e1e2a;
          color: white;
        }
        .frame-title { font-size: 0.8125rem; color: rgba(255,255,255,0.6); font-weight: 500; }
        .frame-link {
          font-size: 0.6875rem;
          color: rgba(255,255,255,0.5);
          text-decoration: none;
          padding: 0.125rem 0.5rem;
          border: 1px solid rgba(255,255,255,0.2);
          border-radius: 4px;
          margin-left: 0.5rem;
        }
        .frame-link:hover {
          color: white;
          border-color: rgba(255,255,255,0.5);
          background: rgba(255,255,255,0.1);
        }
        .frame-rebuild-btn {
          font-size: 0.6875rem;
          color: rgba(255,255,255,0.65);
          background: rgba(255,255,255,0.08);
          border: 1px solid rgba(255,255,255,0.2);
          border-radius: 4px;
          padding: 0.2rem 0.55rem;
          cursor: pointer;
          font-weight: 500;
        }
        .frame-rebuild-btn:hover:not([disabled]) {
          color: white;
          border-color: rgba(255,255,255,0.5);
          background: rgba(255,255,255,0.15);
        }
        .frame-rebuild-btn[disabled] { opacity: 0.5; cursor: not-allowed; }
        .frame-rebuild-msg { font-size: 0.6875rem; opacity: 0.8; }
        .frame-rebuild-msg.is-ok { color: #8de38d; }
        .frame-rebuild-msg.is-error { color: #ff8e8e; }
        .frame-time { margin-left: auto; font-size: 0.75rem; opacity: 0.7; }
        .frame-date-nav {
          margin-left: auto;
          display: flex;
          align-items: center;
          gap: 0.25rem;
        }
        .date-nav-btn {
          padding: 0.125rem 0.5rem;
          background: rgba(255,255,255,0.15);
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          font-size: 0.75rem;
          font-family: inherit;
        }
        .date-nav-btn:hover { background: rgba(255,255,255,0.3); }
        .date-nav-input {
          padding: 0.125rem 0.375rem;
          background: rgba(255,255,255,0.1);
          color: white;
          border: 1px solid rgba(255,255,255,0.2);
          border-radius: 4px;
          font-size: 0.6875rem;
          font-family: inherit;
          color-scheme: dark;
        }
        .date-nav-today {
          padding: 0.125rem 0.5rem;
          background: var(--teal, #2a9d8f);
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          font-size: 0.625rem;
          font-weight: 700;
          font-family: inherit;
        }
        .date-nav-today:hover { background: #238077; }

        /* ═══ HUD Banner ═══ */
        .hud-banner {
          display: flex; flex-wrap: wrap; gap: 0.5rem;
          padding: 0.75rem 1rem;
          background: #1a1a24;
          border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .hud-alert {
          display: flex; align-items: center; gap: 0.5rem;
          padding: 0.5rem 0.75rem; border-radius: 6px;
          font-size: 0.75rem; flex-shrink: 0;
        }
        .hud-alert svg { flex-shrink: 0; }
        .hud-alert.urgent { background: rgba(224,93,80,0.2); color: #f0a8a0; border: 1px solid rgba(224,93,80,0.4); }
        .hud-alert.urgent svg { color: var(--coral); }
        .hud-alert.schedule { background: rgba(192,139,48,0.15); color: #e8c97a; border: 1px solid rgba(192,139,48,0.3); }
        .hud-alert.schedule svg { color: var(--amber); }
        .hud-alert.sub { background: rgba(124,95,196,0.15); color: #c4b5e8; border: 1px solid rgba(124,95,196,0.3); }
        .hud-alert.sub svg { color: var(--purple); }
        .hud-alert.note { background: rgba(192,139,48,0.15); color: #e8c97a; border: 1px solid rgba(192,139,48,0.3); }
        .hud-alert.note svg { color: var(--amber); }
        .hud-dismiss { background: none; border: none; color: inherit; opacity: 0.4; cursor: pointer; font-size: 0.75rem; padding: 0 0.25rem; margin-left: auto; font-family: inherit; flex-shrink: 0; }
        .hud-dismiss:hover { opacity: 1; }
        .hud-detail { font-size: 0.6875rem; opacity: 0.7; }
        .hud-text { white-space: nowrap; }
        .hud-text strong { font-weight: 600; }
        .hud-badge {
          font-size: 0.625rem; font-weight: 600; text-transform: uppercase;
          letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px;
          background: rgba(42,157,143,0.3); color: #80d0c8; margin-left: 0.25rem;
        }

        /* ═══ 3-Column Layout ═══ */
        .classroom-dashboard {
          display: grid;
          grid-template-columns: 220px 320px 1fr;
          flex: 1;
          overflow: hidden;
        }

        /* ═══ Column 1: Roster ═══ */
        .cd-roster { background: #2c2c2e; color: white; overflow-y: auto; }
        .cd-col-header {
          display: flex; justify-content: space-between; align-items: center;
          padding: 0.875rem 1rem; border-bottom: 1px solid rgba(255,255,255,0.1);
          position: sticky; top: 0; background: #2c2c2e; z-index: 2;
        }
        .cd-col-title { font-size: 0.875rem; font-weight: 600; margin: 0; }
        .cd-col-count { font-size: 0.6875rem; color: rgba(255,255,255,0.5); }
        .cd-fetch-btn {
          font-family: inherit; font-size: 0.625rem; font-weight: 600;
          background: #2a9d8f; color: white; border: none; border-radius: 4px;
          padding: 0.2rem 0.5rem; cursor: pointer;
        }
        .cd-fetch-btn:disabled { opacity: 0.5; cursor: wait; }
        .cd-fetch-all-btn { background: #7c5fc4; margin-left: 0.25rem; }
        .cd-sync-btn {
          font-family: inherit; font-size: 0.625rem; font-weight: 600;
          background: #c08b30; color: white; border: none; border-radius: 4px;
          padding: 0.2rem 0.5rem; cursor: pointer; margin-left: 0.25rem;
        }
        .cd-sync-btn:disabled { opacity: 0.5; cursor: wait; }
        .cd-fetch-msg { font-size: 0.625rem; padding: 0.375rem 0.75rem; }
        .cd-fetch-msg.fetch-success { color: #2a9d8f; }
        .cd-fetch-msg.fetch-error { color: #e05d50; }
        .cd-fetch-msg.fetch-info { color: rgba(255,255,255,0.5); }
        .roster-section { padding: 0.5rem 0; }
        .roster-label {
          display: flex; align-items: center; justify-content: space-between;
          padding: 0.5rem 1rem; font-size: 0.625rem;
          text-transform: uppercase; letter-spacing: 0.06em; color: rgba(255,255,255,0.4);
        }
        .roster-location { display: flex; align-items: center; gap: 0.375rem; }
        .roster-location svg { color: var(--teal); }
        .roster-location.away svg { color: var(--amber); }
        .roster-location.absent svg { color: var(--coral); }
        .roster-count { font-weight: 600; }

        .roster-student {
          display: flex; align-items: center; gap: 0.625rem;
          padding: 0.5rem 1rem; cursor: pointer; transition: background 0.15s;
          border: none; background: transparent; width: 100%;
          text-align: left; color: white; font: inherit;
        }
        .roster-student:hover { background: rgba(255,255,255,0.05); }
        .roster-student.selected { background: rgba(42,157,143,0.2); }
        .roster-student.away { opacity: 0.6; }
        .roster-student.absent-row { opacity: 0.4; }

        .rs-avatar { width: 32px; height: 32px; border-radius: 8px; overflow: hidden; position: relative; flex-shrink: 0; }
        .rs-avatar img { width: 100%; height: 100%; object-fit: cover; border-radius: 8px; }
        .rs-status {
          position: absolute; bottom: -1px; right: -1px;
          width: 10px; height: 10px; border-radius: 50%; border: 2px solid #2c2c2e;
        }
        .rs-status.present { background: var(--teal); }
        .rs-status.away { background: var(--amber); }
        .rs-status.absent { background: var(--coral); }

        .rs-info { flex: 1; min-width: 0; }
        .rs-name { display: block; font-size: 0.8125rem; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .rs-tags { display: flex; gap: 0.25rem; margin-top: 0.125rem; }
        .rs-tag { font-size: 0.5rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.125rem 0.25rem; border-radius: 2px; }
        .rs-tag.iep { background: rgba(124,95,196,0.3); color: #b8a5e0; }
        .rs-tag.allergy { background: rgba(224,93,80,0.3); color: #f0a8a0; }
        .rs-tag.plan { background: rgba(42,157,143,0.3); color: #80d0c8; }
        .rs-location { display: block; font-size: 0.6875rem; color: var(--amber); }
        .rs-reason { display: block; font-size: 0.6875rem; color: rgba(255,255,255,0.4); }
        .rs-return { display: block; font-size: 0.625rem; color: rgba(255,255,255,0.4); }
        .rs-staff { flex-shrink: 0; }

        .staff-avatar-mini {
          width: 20px; height: 20px; border-radius: 5px;
          display: flex; align-items: center; justify-content: center;
          font-size: 0.5rem; font-weight: 700; color: white;
        }
        .staff-avatar-mini.teal { background: var(--teal); }
        .staff-avatar-mini.purple { background: var(--purple); }
        .staff-avatar-mini.coral { background: var(--coral); }
        .staff-avatar-mini.amber { background: var(--amber); }

        .staff-avatar-sm {
          width: 28px; height: 28px; border-radius: 7px;
          display: flex; align-items: center; justify-content: center;
          font-size: 0.625rem; font-weight: 700; color: white;
        }
        .staff-avatar-sm.teal { background: var(--teal); }
        .staff-avatar-sm.purple { background: var(--purple); }
        .staff-avatar-sm.coral { background: var(--coral); }
        .staff-avatar-sm.amber { background: var(--amber); }

        /* ═══ Column 2: Student Detail ═══ */
        .cd-daily { background: var(--surface-1); border-right: 1px solid var(--surface-2); overflow-y: auto; }
        .cd-student-header { padding: 1rem; background: var(--surface-0); border-bottom: 1px solid var(--surface-2); }
        .cd-student-id { display: flex; gap: 0.75rem; margin-bottom: 0.75rem; }
        .cd-student-avatar { width: 48px; height: 48px; border-radius: 12px; overflow: hidden; flex-shrink: 0; }
        .cd-student-avatar img { width: 100%; height: 100%; object-fit: cover; }
        .cd-student-name { font-size: 1.125rem; font-weight: 600; margin: 0; letter-spacing: -0.01em; }
        .cd-student-meta { font-size: 0.75rem; color: var(--text-3); }
        .cd-student-tags { display: flex; gap: 0.25rem; margin-top: 0.375rem; }
        .cd-tag { font-size: 0.5rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px; }
        .cd-tag.iep { background: var(--purple-soft); color: var(--purple); }
        .cd-tag.allergy { background: var(--coral-soft); color: var(--coral); }
        .cd-tag.plan { background: var(--teal-soft); color: var(--teal); }

        /* Location Controls */
        .cd-location-controls {
          display: flex; align-items: center; gap: 0.25rem;
          padding-top: 0.625rem; margin-top: 0.375rem;
          border-top: 1px solid var(--surface-2);
        }
        .cd-location-label {
          font-size: 0.5625rem; font-weight: 600; text-transform: uppercase;
          letter-spacing: 0.04em; color: var(--text-3); margin-right: 0.25rem;
        }
        .loc-btn {
          display: flex; align-items: center; gap: 0.25rem;
          padding: 0.25rem 0.5rem; border-radius: 4px;
          border: 1px solid var(--surface-3); background: var(--surface-0);
          font-family: inherit; font-size: 0.625rem; font-weight: 500;
          color: var(--text-3); cursor: pointer; transition: all 0.15s;
        }
        .loc-btn:hover { border-color: var(--text-3); color: var(--text-2); }
        .loc-btn.active.in-class { border-color: var(--teal); background: var(--teal-soft); color: var(--teal); font-weight: 600; }
        .loc-btn.active.specialist { border-color: var(--amber); background: var(--amber-soft); color: var(--amber); font-weight: 600; }
        .loc-btn.active.absent { border-color: var(--coral); background: var(--coral-soft); color: var(--coral); font-weight: 600; }
        .loc-btn svg { flex-shrink: 0; }

        .cd-student-staff {
          display: flex; align-items: center; gap: 0.5rem;
          padding-top: 0.75rem; border-top: 1px solid var(--surface-2);
        }
        .cd-staff-label { font-size: 0.625rem; color: var(--text-3); text-transform: uppercase; letter-spacing: 0.04em; }
        .cd-staff-assigned { display: flex; align-items: center; gap: 0.375rem; margin-left: auto; }
        .cd-staff-name { font-size: 0.75rem; font-weight: 500; }

        /* Alerts */
        .cd-alerts { padding: 0.75rem; display: flex; flex-direction: column; gap: 0.5rem; }
        .cd-alert { display: flex; align-items: flex-start; gap: 0.5rem; padding: 0.625rem 0.75rem; border-radius: var(--radius-sm); font-size: 0.75rem; }
        .cd-alert.urgent { background: var(--coral-soft); color: var(--coral); }
        .cd-alert.note { background: var(--surface-0); color: var(--text-2); }
        .cd-alert-content { flex: 1; }
        .cd-alert-title { display: block; font-weight: 600; font-size: 0.625rem; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 0.125rem; }
        .cd-alert-text { display: block; line-height: 1.3; }
        .cd-alert-dismiss { background: none; border: none; color: inherit; opacity: 0.4; cursor: pointer; font-size: 0.75rem; padding: 0.125rem 0.25rem; margin-left: auto; flex-shrink: 0; font-family: inherit; }
        .cd-alert-dismiss:hover { opacity: 1; }
        .cd-alert-editable { cursor: pointer; border-bottom: 1px dashed transparent; }
        .cd-alert-editable:hover { border-bottom-color: rgba(0,0,0,0.2); }
        .cd-alert-edit-input { font-family: inherit; font-size: 0.75rem; padding: 0.125rem 0.25rem; background: white; border: 1px solid var(--teal, #2a9d8f); border-radius: 3px; color: #1a1816; outline: none; width: 100%; }
        .cd-alert-edit-input.small { font-size: 0.6875rem; color: #8a8279; }
        .cd-alert-detail { font-size: 0.6875rem; color: #8a8279; display: inline; }
        .cd-alert-add-detail { font-size: 0.625rem; color: rgba(0,0,0,0.25); font-style: italic; }

        /* Plan/Schedule */
        .cd-plan { padding: 0.75rem; }
        .cd-section-title {
          font-size: 0.625rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.08em; color: var(--text-3); margin: 0 0 0.625rem;
          display: flex; align-items: center; gap: 0.375rem;
        }
        .cd-section-badge { background: var(--surface-2); padding: 0.125rem 0.375rem; border-radius: 100px; font-weight: 500; }
        .cd-schedule { display: flex; flex-direction: column; gap: 0.125rem; }
        .cd-sched-item { display: grid; grid-template-columns: 10px 1fr; gap: 0.5rem; align-items: center; padding: 0.375rem 0; }
        .cd-sched-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--surface-3); }
        .cd-sched-check { width: 14px; height: 14px; border-radius: 50%; background: var(--teal); color: white; display: flex; align-items: center; justify-content: center; margin-left: -3px; }
        .cd-sched-item.done .cd-sched-dot { background: var(--teal); }
        .cd-sched-item.current .cd-sched-dot { background: var(--coral); box-shadow: 0 0 0 3px var(--coral-soft); }
        .cd-sched-content { display: flex; align-items: center; justify-content: space-between; gap: 0.5rem; }
        .cd-sched-activity { font-size: 0.75rem; }
        .cd-sched-item.done .cd-sched-activity { color: var(--text-3); }
        .cd-sched-item.current .cd-sched-activity { font-weight: 600; }
        .cd-sched-result { font-size: 0.625rem; font-weight: 600; }
        .cd-sched-result.good { color: var(--teal); }
        .cd-sched-tag {
          font-size: 0.5rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em;
          padding: 0.125rem 0.375rem; border-radius: 3px;
          background: var(--coral-soft); color: var(--coral);
        }
        .cd-sched-tag.goal { background: var(--purple-soft); color: var(--purple); }
        /* ── Add Alert inline form ── */
        .cd-add-alert-area {
          padding: 0 0.75rem 0.5rem;
        }
        .cd-add-alert-btn {
          padding: 0.25rem 0.625rem;
          background: var(--coral-soft, #fdf0ee);
          color: var(--coral, #e05d50);
          border: 1px solid var(--coral, #e05d50);
          border-radius: 6px;
          font-size: 0.6875rem;
          font-weight: 700;
          cursor: pointer;
          font-family: inherit;
        }
        .cd-add-alert-btn:hover {
          background: var(--coral, #e05d50);
          color: white;
        }
        .cd-alert-form {
          margin-top: 0.5rem;
          padding: 0.75rem;
          background: var(--surface-0, #fffdfb);
          border: 1px solid var(--surface-3, #ebe7e3);
          border-radius: var(--radius-sm, 6px);
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .cd-af-row { display: flex; gap: 0.5rem; }
        .cd-af-selects { display: flex; gap: 0.375rem; }
        .cd-af-input, .cd-alert-form select, .cd-alert-form textarea {
          flex: 1;
          padding: 0.375rem 0.5rem;
          border: 1px solid var(--surface-3, #ebe7e3);
          border-radius: 4px;
          font-family: inherit;
          font-size: 0.75rem;
          color: var(--text-1, #1a1816);
          background: white;
        }
        .cd-alert-form select { min-width: 100px; }
        .cd-af-save {
          align-self: flex-end;
          padding: 0.375rem 0.75rem;
          background: var(--coral, #e05d50);
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.6875rem;
          font-weight: 700;
          cursor: pointer;
          font-family: inherit;
        }
        .cd-af-save:disabled { opacity: 0.5; cursor: wait; }
        .cd-af-save:not(:disabled):hover { background: #c74a3e; }

        .cd-gen-plan-btn {
          margin-left: auto;
          padding: 0.25rem 0.75rem;
          background: var(--teal, #2a9d8f);
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.6875rem;
          font-weight: 700;
          cursor: pointer;
          font-family: inherit;
        }
        .cd-gen-plan-btn:disabled {
          background: var(--surface-3, #ebe7e3);
          color: var(--text-3, #8a8279);
          cursor: wait;
        }
        .cd-gen-plan-btn:not(:disabled):hover {
          background: #238077;
        }
        .cd-batch-btn {
          background: var(--purple, #7c5fc4);
        }
        .cd-batch-btn:not(:disabled):hover {
          background: #633fa8;
        }
        .cd-edit-plan-link {
          padding: 0.2rem 0.5rem;
          font-size: 0.625rem;
          font-weight: 600;
          color: var(--text-3, #8a8279);
          text-decoration: none;
          border: 1px solid var(--surface-3, #ebe7e3);
          border-radius: 4px;
        }
        .cd-edit-plan-link:hover {
          color: var(--teal, #2a9d8f);
          border-color: var(--teal, #2a9d8f);
        }
        .cd-gen-success {
          color: var(--teal, #2a9d8f);
          font-size: 0.6875rem;
          margin: 0.25rem 0 0;
          padding: 0.375rem 0.5rem;
          background: #e8f6f4;
          border-radius: 4px;
        }
        .cd-gen-error {
          color: var(--coral, #e05d50);
          font-size: 0.75rem;
          margin: 0.25rem 0 0;
          padding: 0.375rem 0.5rem;
          background: #fdf0ee;
          border-radius: 4px;
        }
        .cd-loading-plan {
          padding: 0.75rem;
          color: var(--teal, #2a9d8f);
          font-size: 0.8125rem;
          font-style: italic;
          margin: 0;
        }
        .cd-empty-plan {
          padding: 0.75rem;
          color: var(--text-3);
          font-size: 0.8125rem;
          font-style: italic;
          margin: 0;
        }

        /* Goals */
        .cd-goals { padding: 0.75rem; border-top: 1px solid var(--surface-2); }
        .cd-empty-goals { font-size: 0.75rem; color: rgba(255,255,255,0.4); font-style: italic; margin: 0.5rem 0 0; }
        .cd-goal-cards {
          display: flex; flex-direction: column; gap: 0.5rem;
          max-height: 480px; overflow-y: auto;
          padding-right: 4px;
        }
        .cd-goal-cards::-webkit-scrollbar { width: 6px; }
        .cd-goal-cards::-webkit-scrollbar-thumb { background: var(--surface-2); border-radius: 3px; }
        .cd-goal-card {
          padding: 0.625rem; background: var(--surface-0); border-radius: var(--radius-sm);
          text-decoration: none; color: inherit; display: block; cursor: pointer;
          transition: background 0.15s;
        }
        .cd-goal-card:hover { background: var(--surface-1, rgba(255,255,255,0.08)); }
        .cd-gc-edit {
          font-size: 0.5625rem; font-weight: 600; color: #2a9d8f;
          margin-left: auto; opacity: 0; transition: opacity 0.15s;
        }
        .cd-goal-card:hover .cd-gc-edit { opacity: 1; }
        .cd-gc-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.25rem; }
        .cd-gc-domain { font-size: 0.5rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; }
        .cd-gc-domain.coral { color: var(--coral); }
        .cd-gc-domain.purple { color: var(--purple); }
        .cd-gc-domain.amber { color: var(--amber); }
        .cd-gc-domain.teal { color: var(--teal); }
        .cd-gc-pct { font-size: 0.6875rem; font-weight: 700; color: var(--teal); }
        .cd-gc-title { display: block; font-size: 0.75rem; margin-bottom: 0.375rem; }
        .cd-gc-track { height: 4px; background: var(--surface-2); border-radius: 2px; overflow: hidden; }
        .cd-gc-fill { height: 100%; background: var(--teal); border-radius: 2px; }

        /* ═══ Column 3: Activity Feed ═══ */
        .cd-feed { background: var(--surface-0); display: flex; flex-direction: column; overflow: hidden; }

        /* Quick Entry */
        .cd-quick-entry { padding: 1rem; border-bottom: 1px solid var(--surface-2); background: var(--surface-0); }
        .qe-input-row { display: flex; gap: 0.625rem; margin-bottom: 0.625rem; }
        .qe-avatar { flex-shrink: 0; }
        .qe-textarea {
          flex: 1; min-height: 56px; padding: 0.625rem;
          border: 1px solid var(--surface-3); border-radius: var(--radius-sm);
          font-family: inherit; font-size: 0.875rem; resize: none;
          background: var(--surface-1); color: var(--text-1);
        }
        .qe-textarea:focus { outline: none; border-color: var(--coral); background: var(--surface-0); }
        .qe-actions { display: flex; justify-content: space-between; align-items: center; }
        .qe-attach { display: flex; gap: 0.25rem; }
        .qe-attach-btn {
          width: 32px; height: 32px; border-radius: var(--radius-sm);
          border: 1px solid var(--surface-3); background: var(--surface-0);
          color: var(--text-3); cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          transition: border-color 0.15s, color 0.15s;
        }
        .qe-attach-btn:hover { border-color: var(--coral); color: var(--coral); }
        .qe-submit {
          display: flex; align-items: center; gap: 0.375rem;
          padding: 0.5rem 1rem; border-radius: var(--radius-sm);
          border: none; background: var(--coral); color: white;
          font-family: inherit; font-size: 0.875rem; font-weight: 600;
          cursor: pointer; transition: background 0.15s, transform 0.1s;
        }
        .qe-submit:hover { background: #cf5349; }
        .qe-submit:active { transform: scale(0.97); }
        .qe-hint { display: flex; align-items: center; gap: 0.375rem; margin-top: 0.5rem; font-size: 0.6875rem; color: var(--text-3); }

        /* Entry Type Selector (optional hints) */
        .qe-avatar-wrap { position: relative; }
        .qe-avatar-btn {
          background: none; border: none; cursor: pointer; padding: 0;
          border-radius: 50%; transition: box-shadow 0.15s;
        }
        .qe-avatar-btn:hover { box-shadow: 0 0 0 2px rgba(42,157,143,0.5); }
        .staff-picker {
          position: absolute; top: 100%; left: 0; z-index: 100;
          background: #2c2c2e; border: 1px solid rgba(255,255,255,0.15);
          border-radius: 8px; width: 220px; max-height: 280px;
          overflow-y: auto; box-shadow: 0 8px 24px rgba(0,0,0,0.4);
          margin-top: 4px;
        }
        .sp-header {
          display: flex; gap: 0.375rem; padding: 0.5rem;
          border-bottom: 1px solid rgba(255,255,255,0.1);
          position: sticky; top: 0; background: #2c2c2e; z-index: 1;
        }
        .sp-search {
          flex: 1; font-family: inherit; font-size: 0.6875rem; padding: 0.3rem 0.5rem;
          background: rgba(255,255,255,0.08); color: white;
          border: 1px solid rgba(255,255,255,0.12); border-radius: 4px;
        }
        .sp-search::placeholder { color: rgba(255,255,255,0.35); }
        .sp-item {
          display: flex; align-items: center; gap: 0.5rem;
          width: 100%; padding: 0.5rem 0.625rem; background: none;
          border: none; color: white; cursor: pointer; font-family: inherit;
          text-align: left; transition: background 0.1s;
        }
        .sp-item:hover { background: rgba(255,255,255,0.08); }
        .sp-item.active { background: rgba(42,157,143,0.15); }
        .sp-name { font-size: 0.75rem; font-weight: 500; }
        .sp-empty {
          padding: 1rem; text-align: center;
          font-size: 0.6875rem; color: rgba(255,255,255,0.35);
        }
        .qe-type-selector { display: flex; gap: 0.25rem; margin-bottom: 0.625rem; align-items: center; }
        .qe-type-hint { font-size: 0.625rem; color: var(--text-3); margin-right: 0.25rem; }
        .type-btn {
          padding: 0.375rem 0.75rem; border-radius: var(--radius-sm);
          border: 1px solid var(--surface-3); background: var(--surface-1);
          font-family: inherit; font-size: 0.75rem; font-weight: 500;
          color: var(--text-3); cursor: pointer; transition: all 0.15s;
        }
        .type-btn:hover { border-color: var(--text-3); color: var(--text-2); }
        .type-btn.active { border-color: var(--coral); background: var(--coral-soft); color: var(--coral); font-weight: 600; }

        /* Local Entry Badge */
        .cd-entry.local-entry { border: 1px dashed var(--amber); }
        .cd-entry-local-badge {
          display: inline-block; padding: 0.125rem 0.5rem;
          background: var(--amber-soft); color: var(--amber);
          font-size: 0.5625rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.04em; border-radius: 0 0 var(--radius-sm) var(--radius-sm);
          margin: 0 0.75rem;
        }

        /* Feed Header */
        .cd-feed-header {
          display: flex; justify-content: space-between; align-items: center;
          padding: 0.75rem 1rem; border-bottom: 1px solid var(--surface-2);
        }
        .cd-feed-count { font-size: 0.6875rem; color: var(--text-3); }

        /* Feed Entries */
        .cd-feed-entries { flex: 1; overflow-y: auto; padding: 0.75rem; display: flex; flex-direction: column; gap: 0.75rem; }
        .cd-entry { background: var(--surface-1); border-radius: var(--radius-sm); overflow: hidden; max-height: 400px; overflow-y: auto; }
        .cd-entry.highlighted { border-left: 3px solid #c08b30; background: rgba(192,139,48,0.08); }
        .cd-highlight-btn {
          font-family: inherit; font-size: 0.625rem; font-weight: 600;
          background: rgba(192,139,48,0.08); border: 1px solid rgba(192,139,48,0.3); border-radius: 4px;
          color: #c08b30; padding: 0.15rem 0.5rem; cursor: pointer;
          margin-left: auto;
        }
        .cd-highlight-btn:hover { background: rgba(192,139,48,0.2); }
        .cd-highlight-btn.active { color: white; background: #c08b30; border-color: #c08b30; }
        .cd-delete-btn {
          font-family: inherit; font-size: 0.75rem; font-weight: 600;
          background: none; border: 1px solid rgba(224,93,80,0.3); border-radius: 4px;
          color: #e05d50; padding: 0.1rem 0.4rem; cursor: pointer;
        }
        .cd-delete-btn:hover { background: rgba(224,93,80,0.1); }
        .cd-score-editable { cursor: pointer; }
        .cd-score-editable:hover { text-decoration: underline; }
        .cd-score-input {
          width: 50px; padding: 0.15rem 0.3rem;
          border: 1.5px solid #c08b30; border-radius: 3px;
          font-family: inherit; font-size: 0.75rem; font-weight: 600;
          text-align: center; outline: none;
        }
        .feed-pagination {
          display: flex; justify-content: space-between; align-items: center;
          padding: 0.625rem 0.75rem; border-top: 1px solid rgba(255,255,255,0.08);
        }
        .feed-showing { font-size: 0.6875rem; color: rgba(255,255,255,0.4); }
        .feed-page-btns { display: flex; align-items: center; gap: 0.5rem; }
        .feed-page-btn {
          font-family: inherit; font-size: 0.625rem; font-weight: 600;
          color: #2a9d8f; background: none; border: 1px solid rgba(255,255,255,0.15);
          border-radius: 4px; padding: 0.2rem 0.5rem; cursor: pointer;
        }
        .feed-page-btn:disabled { opacity: 0.3; cursor: not-allowed; }
        .feed-page-label { font-size: 0.625rem; color: rgba(255,255,255,0.4); }
        .cd-entry.ai-processed { border: 1px solid var(--teal); }
        .cd-entry-ai {
          display: flex; align-items: center; gap: 0.75rem;
          padding: 0.5rem 0.75rem; background: var(--teal-soft); flex-wrap: wrap;
        }
        .ai-badge { display: flex; align-items: center; gap: 0.25rem; font-size: 0.5625rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--teal); }
        .ai-suggestion { display: flex; align-items: center; gap: 0.5rem; flex: 1; }
        .ai-type { font-size: 0.5625rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px; }
        .ai-type.social { background: var(--purple-soft); color: var(--purple); }
        .ai-type.academic { background: var(--coral-soft); color: var(--coral); }
        .ai-type.behavioral { background: var(--amber-soft); color: var(--amber); }
        .ai-goal { font-size: 0.6875rem; color: var(--purple); }
        .ai-score { font-size: 0.625rem; font-weight: 700; color: var(--teal); background: var(--teal-soft); padding: 0.125rem 0.375rem; border-radius: 3px; }
        .ai-actions { display: flex; gap: 0.375rem; margin-top: 0.375rem; }

        .cd-entry-content { padding: 0.75rem; }
        .cd-entry-header { display: flex; align-items: center; gap: 0.375rem; margin-bottom: 0.375rem; }
        .cd-entry-author { font-size: 0.75rem; font-weight: 600; }
        .cd-entry-for { font-size: 0.625rem; color: var(--text-3); margin: 0 0.125rem; }
        .cd-entry-student-name { font-size: 0.6875rem; font-weight: 600; color: var(--teal, #2a9d8f); }
        .cd-entry-time { font-size: 0.625rem; color: var(--text-3); margin-left: auto; }
        .cd-entry-text { font-size: 0.8125rem; line-height: 1.5; color: var(--text-2); margin: 0; }
        .cd-entry-tags { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.5rem; flex-wrap: wrap; }
        .cd-entry-type { font-size: 0.5rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px; }
        .cd-entry-type.academic { background: var(--coral-soft); color: var(--coral); }
        .cd-entry-type.social { background: var(--purple-soft); color: var(--purple); }
        .cd-entry-type.behavioral { background: var(--amber-soft); color: var(--amber); }
        .cd-entry-goal { font-size: 0.6875rem; color: var(--purple); }
        .cd-entry-score { font-size: 0.6875rem; font-weight: 600; }
        .cd-entry-score.good { color: var(--teal); }
        .cd-entry-flag {
          margin-top: 0.375rem; padding: 0.375rem 0.5rem;
          background: var(--amber-soft); border-left: 2px solid var(--amber);
          border-radius: 3px; font-size: 0.6875rem; color: var(--text-2);
        }

        /* AI Processing */
        .cd-entry.ai-analyzing { border: 1px dashed var(--teal); opacity: 0.85; }
        .cd-entry-processing {
          display: flex; align-items: center; gap: 0.5rem;
          padding: 0.5rem 0.75rem; background: var(--teal-soft);
          font-size: 0.6875rem; color: var(--teal); font-weight: 500;
        }
        .ai-spinner {
          width: 12px; height: 12px; border: 2px solid var(--teal-soft);
          border-top-color: var(--teal); border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* AI Classification Card */
        .ai-row-top { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.25rem; }
        .ai-confidence { font-size: 0.5625rem; font-weight: 700; color: var(--teal); }
        .ai-domain { font-size: 0.5625rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px; }
        .ai-domain.coral { background: var(--coral-soft); color: var(--coral); }
        .ai-domain.amber { background: var(--amber-soft); color: var(--amber); }
        .ai-domain.purple { background: var(--purple-soft); color: var(--purple); }
        .ai-domain.teal { background: var(--teal-soft); color: var(--teal); }
        .ai-block {
          font-size: 0.5625rem; font-weight: 500; color: var(--text-2);
          padding: 0.125rem 0.375rem; border-radius: 3px;
          background: var(--surface-2); border: 1px solid var(--surface-3);
        }
        .ai-reasoning {
          font-size: 0.6875rem; color: var(--text-2); font-style: italic;
          margin-top: 0.25rem; line-height: 1.3;
        }
        /* AI Confirmed (accepted) */
        .cd-entry.ai-confirmed { border: 2px solid var(--teal); }
        .cd-entry-confirmed {
          padding: 0.5rem 0.75rem; background: var(--teal-soft);
        }
        .confirmed-header {
          display: flex; align-items: center; gap: 0.5rem;
        }
        .confirmed-header svg { color: var(--teal); flex-shrink: 0; }
        .confirmed-label {
          font-size: 0.5625rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.04em; color: var(--teal); margin-right: 0.25rem;
        }
        /* Matched Plan Card */
        .confirmed-plan-card {
          display: flex; align-items: flex-start; gap: 0.5rem;
          margin-top: 0.375rem; padding: 0.375rem 0.5rem;
          background: white; border-radius: 6px; border: 1px solid var(--teal);
        }
        .plan-card-icon {
          width: 18px; height: 18px; border-radius: 50%; background: var(--teal);
          color: white; display: flex; align-items: center; justify-content: center;
          flex-shrink: 0; margin-top: 1px;
        }
        .plan-card-body { display: flex; flex-wrap: wrap; align-items: center; gap: 0.375rem; }
        .plan-card-block {
          font-size: 0.75rem; font-weight: 600; color: var(--text-1);
        }
        .plan-card-score {
          font-size: 0.6875rem; font-weight: 700; color: var(--teal);
          background: var(--teal-soft); padding: 0.0625rem 0.375rem; border-radius: 3px;
        }
        .plan-card-goal {
          font-size: 0.6875rem; color: var(--purple); font-weight: 500;
        }

        /* AI Dismissed (rejected) */
        .cd-entry.ai-rejected { border: 1px solid var(--surface-3); opacity: 0.75; }
        .cd-entry-dismissed {
          display: flex; align-items: center; gap: 0.375rem;
          padding: 0.375rem 0.75rem; background: var(--surface-2);
          font-size: 0.6875rem; color: var(--text-3); font-style: italic;
        }
        .cd-entry-dismissed svg { color: var(--text-3); flex-shrink: 0; }
        .cd-manual-goal {
          display: flex; align-items: center; gap: 0.5rem;
          padding: 0.5rem 0.75rem; background: #fdf6e8; border-radius: 6px;
        }
        .cd-manual-label {
          font-size: 0.6875rem; font-weight: 600; color: #c08b30; white-space: nowrap;
        }
        .cd-manual-select {
          flex: 1; font-family: inherit; font-size: 0.8125rem;
          padding: 0.3rem 0.5rem; border: 1px solid #c08b30;
          border-radius: 4px; background: white; color: #1a1816; cursor: pointer;
        }

        /* AI Action Buttons */
        .ai-accept, .ai-reject, .ai-edit {
          display: flex; align-items: center; gap: 0.25rem;
          padding: 0.25rem 0.625rem; border-radius: 4px; border: none;
          font-family: inherit; font-size: 0.6875rem; font-weight: 600; cursor: pointer;
          transition: all 0.15s;
        }
        .ai-accept { background: var(--teal); color: white; }
        .ai-accept:hover { background: #239083; }
        .ai-edit { background: #fdf6e8; color: #c08b30; border: 1px solid #c08b30; }
        .ai-edit:hover { background: #faecd0; }
        .ai-reject { background: var(--surface-2); color: var(--text-2); border: 1px solid var(--surface-3); }
        .ai-reject:hover { border-color: var(--coral); color: var(--coral); }

        /* ═══ Shared ═══ */
        .empty-state { padding: 2rem; text-align: center; color: var(--text-3); font-size: 0.8125rem; font-style: italic; }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Classroom> {
    get safeName() { return this.args.model?.classroomName ?? 'Classroom'; }
    get teacherName() { return this.args.model?.teacher?.name ?? ''; }
    get studentCount() { return this.args.model?.students?.length ?? 0; }

    <template>
      <div class='ce'>
        <div class='ce-info'>
          <div class='ce-name'>{{this.safeName}}</div>
          {{#if this.teacherName}}<div class='ce-teacher'>{{this.teacherName}}</div>{{/if}}
        </div>
        <span class='ce-count'>{{this.studentCount}} students</span>
      </div>
      <style scoped>
        .ce { display: flex; align-items: center; justify-content: space-between; gap: 0.5rem; padding: 0.75rem 1rem; background: var(--card); border: 1px solid var(--border); border-radius: var(--boxel-border-radius); height: 100%; }
        .ce-name { font-weight: 700; font-size: var(--boxel-font-size); }
        .ce-teacher { font-size: var(--boxel-font-size-xs); color: var(--muted-foreground); }
        .ce-count { font-size: var(--boxel-font-size-xs); color: var(--muted-foreground); }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof Classroom> {
    <template>
      <div class='card-edit'>
        <div class='field-row'>
          <label>Classroom Name</label>
          <@fields.classroomName />
        </div>
        <div class='field-row'>
          <label>Teacher</label>
          <@fields.teacher />
        </div>
        <div class='field-row'>
          <label>Date</label>
          <@fields.date />
        </div>
        <div class='field-row'>
          <label>Students</label>
          <@fields.students />
        </div>
      </div>

      <style scoped>
        .card-edit {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
        }

        .field-row {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .field-row label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Classroom> {
    get safeName() { return this.args.model?.classroomName ?? 'Classroom'; }

    <template>
      <div class='fitted-container'>
        <div class='tile'>
          <span class='tile-name'>{{this.safeName}}</span>
        </div>
      </div>
      <style scoped>
        .fitted-container { container-type: size; width: 100%; height: 100%; }
        .tile { display: flex; align-items: center; justify-content: center; padding: var(--boxel-sp); background: var(--card); border: 1px solid var(--border); border-radius: var(--boxel-border-radius); height: 100%; }
        .tile-name { font-weight: 700; font-size: var(--boxel-font-size); text-align: center; }
      </style>
    </template>
  };
}


