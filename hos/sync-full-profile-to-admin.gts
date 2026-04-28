// Approach C helper: push StudentFullProfile (HoS) -> StudentFullProfile (Admin).
//
// Mirror only the IdentitySection fields — Admin does not need (and should not
// store) the medical / family / custody / financial / IEP sections.
//
// Same shape as sync-students-to-classroom but writes to Admin realm.
// Uses dynamic import for SaveCardCommand to match HoS workspace pattern.

const DEFAULT_ADMIN_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/';

// gradeLevel intentionally NOT in COMPARE_FIELDS or `data` below — Admin's
// IdentitySection.gradeLevel is a typed GradeLevel enum and rejects raw strings
// (same bug as Classroom's Student.gradeLevel). Future fix: import the enum
// class from Admin realm and construct a proper instance.
const COMPARE_FIELDS = [
  'studentId',
  'firstName',
  'lastName',
  'preferredName',
  'dateOfBirth',
  'enrollmentDate',
];

export interface SyncFullProfileToAdminInput {
  profiles: any[];
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  adminRealm?: string;
  onProgress?: (current: number, total: number, profileName: string) => void;
}

export interface SyncFullProfileToAdminResult {
  success: boolean;
  total: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: Array<{ profileName: string; error: string }>;
}

export async function syncFullProfileToAdmin(
  input: SyncFullProfileToAdminInput,
): Promise<SyncFullProfileToAdminResult> {
  const { profiles, ctx, getCards, host, unwrapResource, onProgress } = input;
  const adminRealm = input.adminRealm ?? DEFAULT_ADMIN_REALM;

  const result: SyncFullProfileToAdminResult = {
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
    const adminProfModule = `${adminRealm}student-full-profile`;
    const adminProfRes = getCards(
      host,
      () => ({ filter: { type: { module: adminProfModule, name: 'StudentFullProfile' } } }),
      () => [adminRealm],
    );
    const adminProfiles = await unwrapResource(adminProfRes, 15000);

    const byId = new Map<string, any>();
    const byName = new Map<string, any>();
    for (const p of adminProfiles) {
      const pid = String(p?.identity?.studentId ?? '').trim();
      if (pid) byId.set(pid, p);
      const pname = `${String(p?.identity?.firstName ?? '')} ${String(p?.identity?.lastName ?? '')}`.trim().toLowerCase();
      if (pname) byName.set(pname, p);
    }

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    const adminProfMod: any = await import(`${adminRealm}student-full-profile`);
    const adminSectionsMod: any = await import(`${adminRealm}profile-sections`);
    const StudentFullProfile = adminProfMod.StudentFullProfile;
    const IdentitySection = adminSectionsMod.IdentitySection;
    if (!StudentFullProfile || !IdentitySection) {
      result.errors.push({ profileName: '(init)', error: 'StudentFullProfile or IdentitySection not found in Admin realm' });
      return result;
    }

    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i];
      const ident = profile?.identity;
      if (!ident) {
        result.skipped++;
        continue;
      }

      const profFirst = String(ident.firstName ?? '');
      const profLast = String(ident.lastName ?? '');
      const profId = String(ident.studentId ?? '').trim();
      const profName = `${profFirst} ${profLast}`.trim();

      if (!profFirst && !profLast) {
        result.skipped++;
        continue;
      }

      if (onProgress) onProgress(i + 1, profiles.length, profName);

      const data: Record<string, string> = {
        studentId: profId,
        firstName: profFirst,
        lastName: profLast,
        preferredName: String(ident.preferredName ?? ''),
        dateOfBirth: String(ident.dateOfBirth ?? ''),
        enrollmentDate: String(ident.enrollmentDate ?? ''),
        // gradeLevel skipped — see comment near COMPARE_FIELDS above
      };
      const profActive = ident.active ?? true;

      const existing = (profId ? byId.get(profId) : null) ?? byName.get(profName.toLowerCase()) ?? null;

      try {
        if (existing) {
          let changed = false;
          const exIdent = existing?.identity;
          for (const key of COMPARE_FIELDS) {
            const curRaw = exIdent?.[key];
            const curVal = String(typeof curRaw === 'object' && curRaw !== null ? (curRaw?.value ?? curRaw?.label ?? '') : (curRaw ?? ''));
            if (curVal !== data[key]) { changed = true; break; }
          }
          if (!changed && existing?.identity?.active === profActive) {
            result.skipped++;
            continue;
          }
          for (const [key, val] of Object.entries(data)) {
            (exIdent as any)[key] = val;
          }
          (exIdent as any).active = profActive;
          await new SaveCardCommand(ctx).execute({ card: existing, realm: adminRealm });
          result.updated++;
          console.log(`[HoS-Admin] updated profile for ${profName}`);
        } else {
          const newProfile = new StudentFullProfile();
          const newIdent = new IdentitySection();
          for (const [key, val] of Object.entries(data)) {
            (newIdent as any)[key] = val;
          }
          (newIdent as any).active = profActive;
          (newProfile as any).identity = newIdent;
          await new SaveCardCommand(ctx).execute({ card: newProfile, realm: adminRealm });
          result.created++;
          console.log(`[HoS-Admin] created profile for ${profName}`);
        }
      } catch (e: any) {
        const errMsg = e?.message ?? String(e);
        console.warn(`[HoS-Admin] failed for ${profName}:`, errMsg);
        result.failed++;
        result.errors.push({ profileName: profName, error: errMsg });
      }
    }

    result.success = result.failed === 0;
    return result;
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn('[HoS-Admin] sync failed (top-level):', errMsg);
    result.errors.push({ profileName: '(top-level)', error: errMsg });
    return result;
  }
}
// touched for re-index
