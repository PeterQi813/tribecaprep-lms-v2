// Push Classroom LearningGoal -> HoS LearningGoal mirror.
//
// Source of truth is Classroom Goal (has live currentMastery + evidence aggregation).
// Called from _autoSyncGoalMastery after mastery changes, or from a manual
// rebuild button.
//
// SKIPPED fields:
//   domain, priority  — enum fields; raw string rejected (same bug class as elsewhere)
//   dueDate           — DateField; date-fns strict serializer rejects raw strings
//   student linksTo   — cross-realm linksTo is unreliable; flat studentName covers it
//   evidenceEntries   — computed live from Classroom AE; HoS derives its own from AE mirrors

const DEFAULT_HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';

const COMPARE_FIELDS = [
  'goalTitle',
  'description',
  'studentName',
  'currentMastery',
  'targetMastery',
  'startedDate',
];

export interface SyncGoalsToHosInput {
  goals: any[];
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  hosRealm?: string;
}

export interface SyncGoalsToHosResult {
  success: boolean;
  total: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: Array<{ goalKey: string; error: string }>;
}

export async function syncGoalsToHos(
  input: SyncGoalsToHosInput,
): Promise<SyncGoalsToHosResult> {
  const { goals, ctx, getCards, host, unwrapResource } = input;
  const hosRealm = input.hosRealm ?? DEFAULT_HOS_REALM;

  const result: SyncGoalsToHosResult = {
    success: false,
    total: goals.length,
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
    const goalModuleUrl = `${hosRealm}learning-goal`;
    const res = getCards(
      host,
      () => ({ filter: { type: { module: goalModuleUrl, name: 'LearningGoal' } } }),
      () => [hosRealm],
    );
    const hosGoals = await unwrapResource(res, 8000);

    const byKey = new Map<string, any>();
    for (const g of hosGoals) {
      const t = String(g?.goalTitle ?? '').trim().toLowerCase();
      const s = String(g?.studentName ?? '').trim().toLowerCase();
      if (t) byKey.set(`${t}|${s}`, g);
    }

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    const mod: any = await import(/* @vite-ignore */ goalModuleUrl);
    const HosLearningGoal = mod.LearningGoal;
    if (!HosLearningGoal) {
      result.errors.push({ goalKey: '(init)', error: 'LearningGoal class not found in HoS realm' });
      return result;
    }

    for (const goal of goals) {
      const title = String(goal?.goalTitle ?? '').trim();
      const studentName = String(goal?.studentName ?? '').trim();
      const goalKey = `${title}|${studentName}`;
      if (!title) {
        result.skipped++;
        continue;
      }

      const data: Record<string, any> = {
        goalTitle: title,
        description: String(goal?.description ?? ''),
        studentName,
        currentMastery: Number(goal?.currentMastery ?? 0) || 0,
        targetMastery: Number(goal?.targetMastery ?? 0) || 0,
        startedDate: String(goal?.startedDate ?? ''),
      };

      const existing = byKey.get(`${title.toLowerCase()}|${studentName.toLowerCase()}`);

      try {
        if (existing) {
          let changed = false;
          for (const key of COMPARE_FIELDS) {
            const cur = (existing as any)?.[key];
            const curStr = key === 'currentMastery' || key === 'targetMastery'
              ? String(Number(cur ?? 0) || 0)
              : String(cur ?? '');
            const newStr = String(data[key] ?? '');
            if (curStr !== newStr) { changed = true; break; }
          }
          if (!changed) {
            result.skipped++;
            continue;
          }
          for (const [k, v] of Object.entries(data)) (existing as any)[k] = v;
          await new SaveCardCommand(ctx).execute({ card: existing, realm: hosRealm });
          result.updated++;
          console.log(`[Classroom-HoS] updated Goal "${title}" for "${studentName}": ${data.currentMastery}%`);
        } else {
          const newGoal = new HosLearningGoal();
          for (const [k, v] of Object.entries(data)) (newGoal as any)[k] = v;
          await new SaveCardCommand(ctx).execute({ card: newGoal, realm: hosRealm });
          result.created++;
          console.log(`[Classroom-HoS] created Goal "${title}" for "${studentName}": ${data.currentMastery}%`);
        }
      } catch (e: any) {
        const errMsg = e?.message ?? String(e);
        console.warn(`[Classroom-HoS] failed for Goal "${goalKey}":`, errMsg);
        result.failed++;
        result.errors.push({ goalKey, error: errMsg });
      }
    }

    result.success = result.failed === 0;
    return result;
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn('[Classroom-HoS] goals sync failed (top-level):', errMsg);
    result.errors.push({ goalKey: '(top-level)', error: errMsg });
    return result;
  }
}
// touched for re-index
