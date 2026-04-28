// Approach C helper: push StudentFullProfile -> Classroom Student.
//
// Extracted from hos-dashboard.gts handlePushToClassroom so the logic can be
// called both from the manual push button (with all profiles) AND from the
// auto-push trigger in saveNewStudent (with a single profile).
//
// Uses dynamic imports for SaveCardCommand (matching hos-dashboard.gts own
// pattern) to stay compatible with HoS workspace indexer.

const DEFAULT_HERO_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';

export interface SyncStudentsToClassroomInput {
  profiles: any[];
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  heroRealm?: string;
  onProgress?: (current: number, total: number, profileName: string) => void;
}

export interface SyncStudentsToClassroomResult {
  success: boolean;
  total: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: Array<{ profileName: string; error: string }>;
}

export async function syncStudentsToClassroom(
  input: SyncStudentsToClassroomInput,
): Promise<SyncStudentsToClassroomResult> {
  const { profiles, ctx, getCards, host, unwrapResource, onProgress } = input;
  const heroRealm = input.heroRealm ?? DEFAULT_HERO_REALM;

  const result: SyncStudentsToClassroomResult = {
    success: false,
    total: profiles.length,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    errors: [],
  };

  if (!ctx || !getCards) {
    result.errors.push({ profileName: '(init)', error: 'Missing ctx or getCards' });
    return result;
  }

  try {
    const studRes = getCards(
      host,
      () => ({ filter: { type: { module: `${heroRealm}student`, name: 'Student' } } }),
      () => [heroRealm],
    );
    const heroStudents = await unwrapResource(studRes);

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    const heroStudentModule: any = await import(`${heroRealm}student`);
    const Student = heroStudentModule.Student;
    if (!Student) {
      result.errors.push({ profileName: '(init)', error: 'Student class not found in hero-classroom realm' });
      return result;
    }

    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i];
      const ident = profile?.identity;
      if (!ident) {
        result.skipped++;
        continue;
      }

      const profId = String(ident.studentId ?? '').trim();
      const profFirst = String(ident.firstName ?? '');
      const profLast = String(ident.lastName ?? '');
      const profGrade = String(ident.gradeLevel?.value ?? ident.gradeLevel ?? '');
      const profName = `${profFirst} ${profLast}`.trim();

      if (onProgress) onProgress(i + 1, profiles.length, profName);

      let heroStudent = heroStudents.find((s: any) => {
        const hId = String(s?.studentId ?? '').trim();
        return hId && hId === profId;
      });
      if (!heroStudent) {
        heroStudent = heroStudents.find((s: any) => {
          const hFirst = String(s?.firstName ?? '').toLowerCase();
          const hLast = String(s?.lastName ?? '').toLowerCase();
          return hFirst === profFirst.toLowerCase() && hLast === profLast.toLowerCase();
        });
      }

      try {
        if (heroStudent) {
          (heroStudent as any).firstName = profFirst;
          (heroStudent as any).lastName = profLast;
          if (profId) (heroStudent as any).studentId = profId;
          // gradeLevel intentionally NOT synced here — Classroom's Student.gradeLevel
          // is a typed GradeLevel enum and won't accept a raw string. Set it in
          // Classroom's Student card directly, or via a future dedicated sync path.
          await new SaveCardCommand(ctx).execute({ card: heroStudent, realm: heroRealm });
          result.updated++;
        } else {
          const newStudent = new Student();
          (newStudent as any).firstName = profFirst;
          (newStudent as any).lastName = profLast;
          if (profId) (newStudent as any).studentId = profId;
          (newStudent as any).active = true;
          (newStudent as any).location = 'In Classroom';
          await new SaveCardCommand(ctx).execute({ card: newStudent, realm: heroRealm });
          result.created++;
          console.log(`[HoS-Classroom] enrolled new student "${profName}"`);
        }
      } catch (e: any) {
        const errMsg = e?.message ?? String(e);
        console.warn(`[HoS-Classroom] failed for ${profName}:`, errMsg);
        result.failed++;
        result.errors.push({ profileName: profName, error: errMsg });
      }
    }

    result.success = result.failed === 0;
    return result;
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn('[HoS-Classroom] sync failed (top-level):', errMsg);
    result.errors.push({ profileName: '(top-level)', error: errMsg });
    return result;
  }
}
// touched for re-index
