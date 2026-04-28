// Push Classroom Student.location -> HoS Student mirror.
//
// Matching path (HoS Student.studentId is a computed field from linked
// StudentFullProfile, which may not hydrate reliably via getCards):
//   Classroom Student.studentId (raw string)
//     → HoS StudentFullProfile.identity.studentId (raw string on profile)
//       → HoS Student.fullProfile link (the mirror)
//
// Pushes: location, locationDetail, returnTime (Location & Schedule group).

const DEFAULT_HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';

export interface SyncStudentLocationToHosInput {
  student: any;
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  hosRealm?: string;
}

export interface SyncStudentLocationToHosResult {
  success: boolean;
  studentId: string;
  operation?:
    | 'updated'
    | 'skipped-no-studentid'
    | 'skipped-no-profile'
    | 'skipped-no-mirror'
    | 'skipped-no-context'
    | 'unchanged';
  recordId?: string;
  error?: string;
}

export async function syncStudentLocationToHos(
  input: SyncStudentLocationToHosInput,
): Promise<SyncStudentLocationToHosResult> {
  const { student, ctx, getCards, host, unwrapResource } = input;
  const hosRealm = input.hosRealm ?? DEFAULT_HOS_REALM;
  const studentModuleUrl = `${hosRealm}student`;
  const profileModuleUrl = `${hosRealm}student-full-profile`;

  if (!ctx || !getCards) {
    return { success: false, studentId: '', operation: 'skipped-no-context', error: 'Missing ctx or getCards' };
  }

  const studentId = String(student?.studentId ?? '').trim();
  if (!studentId) {
    return { success: false, studentId: '', operation: 'skipped-no-studentid', error: 'Classroom Student has no studentId' };
  }

  try {
    // Step 1: find matching HoS StudentFullProfile (source of identity)
    const profRes = getCards(
      host,
      () => ({ filter: { type: { module: profileModuleUrl, name: 'StudentFullProfile' } } }),
      () => [hosRealm],
    );
    const profiles = await unwrapResource(profRes, 8000);
    const matchProfile = profiles.find(
      (p: any) => String(p?.identity?.studentId ?? '').trim() === studentId,
    );
    if (!matchProfile) {
      return { success: true, studentId, operation: 'skipped-no-profile' };
    }
    const profileId = String((matchProfile as any).id ?? '');

    // Step 2: find HoS Student linked to that profile
    const stuRes = getCards(
      host,
      () => ({ filter: { type: { module: studentModuleUrl, name: 'Student' } } }),
      () => [hosRealm],
    );
    const students = await unwrapResource(stuRes, 8000);
    const mirror = students.find(
      (s: any) => String((s as any)?.fullProfile?.id ?? '') === profileId,
    );
    if (!mirror) {
      return { success: true, studentId, operation: 'skipped-no-mirror' };
    }

    const newLocation = String(student?.location ?? '');
    const newDetail = String(student?.locationDetail ?? '');
    const newReturn = String(student?.returnTime ?? '');

    const oldLocation = String((mirror as any)?.location ?? '');
    const oldDetail = String((mirror as any)?.locationDetail ?? '');
    const oldReturn = String((mirror as any)?.returnTime ?? '');

    if (oldLocation === newLocation && oldDetail === newDetail && oldReturn === newReturn) {
      return { success: true, studentId, operation: 'unchanged', recordId: (mirror as any).id };
    }

    (mirror as any).location = newLocation;
    (mirror as any).locationDetail = newDetail;
    (mirror as any).returnTime = newReturn;

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    await new SaveCardCommand(ctx).execute({ card: mirror, realm: hosRealm });
    console.log('[Classroom-HoS] updated Student.location mirror:', (mirror as any).id, '→', newLocation);
    return { success: true, studentId, operation: 'updated', recordId: (mirror as any).id };
  } catch (e: any) {
    console.warn('[Classroom-HoS] student location sync failed (non-fatal):', e);
    return { success: false, studentId, error: String(e?.message ?? e) };
  }
}
