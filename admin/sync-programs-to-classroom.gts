// Approach C helper: push Admin ProgramRecord -> Classroom LearningGoal.
//
// Field mapping (intentional skips below):
//   program        -> goalTitle
//   notes          -> description
//   studentName    -> studentName  (flat — NO linksTo, cross-realm is brittle)
//   targetMastery  -> targetMastery (number)
//   started        -> startedDate (string)
//   dueDate        -> dueDate (try string; if Boxel rejects we skip)
//
// SKIPPED:
//   domain         (DomainField enum — same string/enum bug as Staff.role)
//   priority       (PriorityField enum, also missing on Program)
//   student linksTo (cross-realm linksTo unreliable; flat studentName covers it)
//   materials      (no equivalent field on Classroom Goal)
//   evidenceEntries (computed from Classroom ObservationRecord — out of scope)
//
// Dedup key: (goalTitle + studentName) composite.

const DEFAULT_HERO_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';

const COMPARE_FIELDS = [
  'goalTitle',
  'description',
  'studentName',
  'targetMastery',
  'startedDate',
];

export interface SyncProgramsToClassroomInput {
  programs: any[];
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  heroRealm?: string;
}

export interface SyncProgramsToClassroomResult {
  success: boolean;
  total: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: Array<{ goalKey: string; error: string }>;
}

export async function syncProgramsToClassroom(
  input: SyncProgramsToClassroomInput,
): Promise<SyncProgramsToClassroomResult> {
  const { programs, ctx, getCards, host, unwrapResource } = input;
  const heroRealm = input.heroRealm ?? DEFAULT_HERO_REALM;

  const result: SyncProgramsToClassroomResult = {
    success: false,
    total: programs.length,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    errors: [],
  };

  if (!ctx || !getCards) {
    result.errors.push({ goalKey: '(init)', error: 'Missing ctx or getCards' });
    return result;
  }

  try {
    const goalRes = getCards(
      host,
      () => ({ filter: { type: { module: `${heroRealm}learning-goal`, name: 'LearningGoal' } } }),
      () => [heroRealm],
    );
    const heroGoals = await unwrapResource(goalRes, 8000);

    const byKey = new Map<string, any>();
    for (const g of heroGoals) {
      const t = String(g?.goalTitle ?? '').trim().toLowerCase();
      const s = String(g?.studentName ?? '').trim().toLowerCase();
      if (t) byKey.set(`${t}|${s}`, g);
    }

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    const heroGoalMod: any = await import(`${heroRealm}learning-goal`);
    const HeroLearningGoal = heroGoalMod.LearningGoal;
    if (!HeroLearningGoal) {
      result.errors.push({ goalKey: '(init)', error: 'LearningGoal class not found in hero-classroom realm' });
      return result;
    }

    for (const prog of programs) {
      const title = String(prog?.program ?? '').trim();
      const studentName = String(prog?.studentName ?? '').trim();
      const goalKey = `${title}|${studentName}`;

      if (!title) {
        result.skipped++;
        continue;
      }

      const data: Record<string, any> = {
        goalTitle: title,
        description: String(prog?.notes ?? ''),
        studentName,
        targetMastery: Number(prog?.targetMastery ?? 0) || 0,
        startedDate: String(prog?.started ?? ''),
      };
      // dueDate INTENTIONALLY SKIPPED — Classroom's LearningGoal.dueDate is a typed
      // DateField (date-fns serializer) and rejects raw strings: "Invalid time value"
      // RangeError. Same bug class as gradeLevel/role enums. Confirmed in console
      // 2026-04-21 against Sorting Non-Identical Objects, Sight Words, etc.

      const existing = byKey.get(`${title.toLowerCase()}|${studentName.toLowerCase()}`);

      try {
        if (existing) {
          let changed = false;
          for (const key of COMPARE_FIELDS) {
            const cur = (existing as any)?.[key];
            const curStr = key === 'targetMastery' ? String(Number(cur ?? 0) || 0) : String(cur ?? '');
            const newStr = String(data[key] ?? '');
            if (curStr !== newStr) { changed = true; break; }
          }
          if (!changed) {
            result.skipped++;
            continue;
          }
          for (const [k, v] of Object.entries(data)) {
            (existing as any)[k] = v;
          }
          await new SaveCardCommand(ctx).execute({ card: existing, realm: heroRealm });
          result.updated++;
          console.log(`[Admin-Classroom] updated Goal "${title}" for "${studentName}"`);
        } else {
          const newGoal = new HeroLearningGoal();
          for (const [k, v] of Object.entries(data)) {
            (newGoal as any)[k] = v;
          }
          await new SaveCardCommand(ctx).execute({ card: newGoal, realm: heroRealm });
          result.created++;
          console.log(`[Admin-Classroom] created Goal "${title}" for "${studentName}"`);
        }
      } catch (e: any) {
        const errMsg = e?.message ?? String(e);
        console.warn(`[Admin-Classroom] failed for Goal "${goalKey}":`, errMsg);
        result.failed++;
        result.errors.push({ goalKey, error: errMsg });
      }
    }

    result.success = result.failed === 0;
    return result;
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn('[Admin-Classroom] programs sync failed (top-level):', errMsg);
    result.errors.push({ goalKey: '(top-level)', error: errMsg });
    return result;
  }
}
