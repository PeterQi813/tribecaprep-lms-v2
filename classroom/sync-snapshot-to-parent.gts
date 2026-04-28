// Build a frozen per-(date, student) ImportSnapshot in Parent Daily realm
// from Classroom data (ActivityEntry + DailyPlan + LearningGoal + Staff).
//
// Replaces the pull-based fetch in parent-daily's ImportSnapshotManager.
// Trigger is manual (date+student picker) — snapshot semantic is "frozen end
// of day", not auto on every AE save.
//
// Dedup: update existing ImportSnapshot with same studentSlug + snapshotDate.
// Create new otherwise.

const DEFAULT_CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const DEFAULT_PARENT_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/';

export interface SyncSnapshotToParentInput {
  studentSlug: string;
  snapshotDate: string;
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  classroomRealm?: string;
  parentRealm?: string;
}

export interface SyncSnapshotToParentResult {
  success: boolean;
  studentSlug: string;
  snapshotDate: string;
  operation?:
    | 'created'
    | 'updated'
    | 'skipped-no-context'
    | 'skipped-no-student'
    | 'skipped-no-input';
  recordId?: string;
  entryCount?: number;
  error?: string;
}

function dateToYMD(d: any): string {
  try {
    const dt = typeof d === 'string' ? new Date(d) : d instanceof Date ? d : new Date(d);
    if (isNaN(dt.getTime())) return '';
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
  } catch (_) {
    return '';
  }
}

export async function syncSnapshotToParent(
  input: SyncSnapshotToParentInput,
): Promise<SyncSnapshotToParentResult> {
  const { studentSlug, snapshotDate, ctx, getCards, host, unwrapResource } = input;
  const classroomRealm = input.classroomRealm ?? DEFAULT_CLASSROOM_REALM;
  const parentRealm = input.parentRealm ?? DEFAULT_PARENT_REALM;

  if (!ctx || !getCards) {
    return { success: false, studentSlug, snapshotDate, operation: 'skipped-no-context', error: 'Missing ctx or getCards' };
  }
  if (!studentSlug || !snapshotDate) {
    return { success: false, studentSlug, snapshotDate, operation: 'skipped-no-input', error: 'studentSlug and snapshotDate required' };
  }

  try {
    const entriesRes = getCards(
      host,
      () => ({ filter: { type: { module: `${classroomRealm}activity-entry`, name: 'ActivityEntry' } } }),
      () => [classroomRealm],
    );
    const allEntries = await unwrapResource(entriesRes, 25000);

    const studentsRes = getCards(
      host,
      () => ({ filter: { type: { module: `${classroomRealm}student`, name: 'Student' } } }),
      () => [classroomRealm],
    );
    const allStudents = await unwrapResource(studentsRes, 25000);
    const student = allStudents.find((s: any) => {
      const id = String(s?.id ?? '');
      return id.split('/').pop() === studentSlug;
    });
    if (!student) {
      return { success: false, studentSlug, snapshotDate, operation: 'skipped-no-student', error: `No Classroom Student with slug ${studentSlug}` };
    }
    const studentName = `${String(student?.firstName ?? '')} ${String(student?.lastName ?? '')}`.trim();
    const studentGrade = String(student?.gradeLevel?.value ?? student?.gradeLevel ?? '');
    const studentFullId = String((student as any)?.id ?? '');

    // Read student/author from raw relationships (cross-realm linksTo may not hydrate)
    const getStudentSlug = (e: any): string => {
      const fromHydrated = String(e?.student?.id ?? '');
      if (fromHydrated) return fromHydrated.split('/').pop() ?? '';
      const fromRaw = String((e as any)?.relationships?.student?.links?.self ?? '');
      return fromRaw.split('/').pop() ?? '';
    };
    const getAuthorSlug = (e: any): string => {
      const fromHydrated = String(e?.author?.id ?? '');
      if (fromHydrated) return fromHydrated.split('/').pop() ?? '';
      const fromRaw = String((e as any)?.relationships?.author?.links?.self ?? '');
      return fromRaw.split('/').pop() ?? '';
    };

    const matchingEntries = allEntries.filter((e: any) => {
      if (getStudentSlug(e) !== studentSlug) return false;
      const ymd = dateToYMD(e?.timestamp);
      return ymd === snapshotDate;
    });

    const frozen = matchingEntries.map((e: any) => {
      let timestamp = '';
      try {
        if (e?.timestamp) timestamp = typeof e.timestamp === 'string' ? e.timestamp : new Date(e.timestamp).toISOString();
      } catch (_) {}
      return {
        id: String(e?.id ?? ''),
        content: String(e?.content ?? ''),
        entryType: String(e?.entryType ?? ''),
        timestamp,
        score: String(e?.score ?? ''),
        domain: String(e?.domain ?? ''),
        reasoning: String(e?.reasoning ?? ''),
        matchedBlock: String(e?.matchedBlock ?? ''),
        suggestedGoal: String(e?.suggestedGoal ?? ''),
        flagNote: String(e?.flagNote ?? ''),
        flagSeverity: String(e?.flagSeverity ?? ''),
        authorName: getAuthorSlug(e),
        studentSlug,
      };
    });

    let scheduleJson = '';
    try {
      const planRes = getCards(
        host,
        () => ({ filter: { type: { module: `${classroomRealm}daily-plan`, name: 'DailyPlan' } } }),
        () => [classroomRealm],
      );
      const allPlans = await unwrapResource(planRes, 25000);
      const studentPlan = allPlans.find((p: any) => {
        if (getStudentSlug(p) !== studentSlug) return false;
        return dateToYMD(p?.planDate) === snapshotDate;
      });
      if (studentPlan) {
        scheduleJson = JSON.stringify((studentPlan?.scheduleItems ?? []).map((item: any) => ({
          time: String(item?.time ?? ''),
          activity: String(item?.activity ?? ''),
          status: typeof item?.status === 'object' ? (item.status?.value ?? '') : String(item?.status ?? ''),
          result: String(item?.result ?? ''),
          goalTag: String(item?.goalTag ?? ''),
        })), null, 2);
      }
    } catch (e) {
      console.warn('[sync-snapshot] DailyPlan read failed (non-fatal):', e);
    }

    let goalsJson = '';
    try {
      const goalRes = getCards(
        host,
        () => ({ filter: { type: { module: `${classroomRealm}learning-goal`, name: 'LearningGoal' } } }),
        () => [classroomRealm],
      );
      const allGoals = await unwrapResource(goalRes, 25000);
      const studentGoals = allGoals
        .filter((g: any) => getStudentSlug(g) === studentSlug)
        .map((g: any) => ({
          goalTitle: String(g?.goalTitle ?? ''),
          domain: String(g?.domain?.value ?? g?.domain ?? ''),
          targetMastery: g?.targetMastery ?? 80,
          progressPercent: g?.progressPercent ?? 0,
          description: String(g?.description ?? ''),
        }));
      goalsJson = JSON.stringify(studentGoals, null, 2);
    } catch (e) {
      console.warn('[sync-snapshot] LearningGoal read failed (non-fatal):', e);
    }

    let teacherName = '';
    try {
      const staffRes = getCards(
        host,
        () => ({ filter: { type: { module: `${classroomRealm}staff`, name: 'Staff' } } }),
        () => [classroomRealm],
      );
      const allStaff = await unwrapResource(staffRes, 25000);
      const head = allStaff.find((s: any) => String(s?.role?.value ?? s?.role ?? '').includes('Lead'));
      teacherName = head ? String((head as any)?.name ?? '') : (allStaff[0] ? String((allStaff[0] as any)?.name ?? '') : '');
    } catch (e) {
      console.warn('[sync-snapshot] Staff read failed (non-fatal):', e);
    }

    const snapshotModuleUrl = `${parentRealm}import-snapshot`;
    const snapRes = getCards(
      host,
      () => ({ filter: { type: { module: snapshotModuleUrl, name: 'ImportSnapshot' } } }),
      () => [parentRealm],
    );
    const allSnapshots = await unwrapResource(snapRes, 25000);
    const existing = allSnapshots.find((s: any) => {
      if (String(s?.studentSlug ?? '') !== studentSlug) return false;
      return dateToYMD(s?.snapshotDate) === snapshotDate;
    });

    const [yStr, mStr, dStr] = snapshotDate.split('-');
    const snapshotDateObj = new Date(Number(yStr), Number(mStr) - 1, Number(dStr));
    if (isNaN(snapshotDateObj.getTime())) {
      return { success: false, studentSlug, snapshotDate, error: `Invalid snapshotDate: ${snapshotDate}` };
    }

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');

    if (existing) {
      (existing as any).studentSlug = studentSlug;
      (existing as any).studentName = studentName;
      (existing as any).studentGrade = studentGrade;
      (existing as any).snapshotDate = snapshotDateObj;
      (existing as any).sourceRealm = classroomRealm;
      (existing as any).fetchedAt = new Date();
      (existing as any).entryCount = frozen.length;
      (existing as any).entriesJson = JSON.stringify(frozen, null, 2);
      (existing as any).scheduleJson = scheduleJson;
      (existing as any).goalsJson = goalsJson;
      (existing as any).teacherName = teacherName;
      await new SaveCardCommand(ctx).execute({ card: existing, realm: parentRealm });
      console.log('[Classroom-Parent] updated ImportSnapshot:', (existing as any).id);
      return { success: true, studentSlug, snapshotDate, operation: 'updated', recordId: (existing as any).id, entryCount: frozen.length };
    } else {
      const mod: any = await import(/* @vite-ignore */ snapshotModuleUrl);
      const ImportSnapshot = mod.ImportSnapshot;
      if (!ImportSnapshot) throw new Error('ImportSnapshot class not found in Parent realm');
      const snap = new ImportSnapshot();
      (snap as any).studentSlug = studentSlug;
      (snap as any).studentName = studentName;
      (snap as any).studentGrade = studentGrade;
      (snap as any).snapshotDate = snapshotDateObj;
      (snap as any).sourceRealm = classroomRealm;
      (snap as any).fetchedAt = new Date();
      (snap as any).entryCount = frozen.length;
      (snap as any).entriesJson = JSON.stringify(frozen, null, 2);
      (snap as any).scheduleJson = scheduleJson;
      (snap as any).goalsJson = goalsJson;
      (snap as any).teacherName = teacherName;
      await new SaveCardCommand(ctx).execute({ card: snap, realm: parentRealm });
      console.log('[Classroom-Parent] created ImportSnapshot:', (snap as any).id);
      return { success: true, studentSlug, snapshotDate, operation: 'created', recordId: (snap as any).id, entryCount: frozen.length };
    }
  } catch (e: any) {
    console.warn('[Classroom-Parent] snapshot sync failed:', e);
    return { success: false, studentSlug, snapshotDate, error: String(e?.message ?? e) };
  }
}
// touched for re-index
