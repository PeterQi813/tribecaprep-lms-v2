// Approach C helper: push Admin StaffMember -> Classroom Staff.
//
// Called both auto (after CreateStaffCommand / deleteStaff in admin-dashboard)
// and manually (Rebuild Classroom Staff button — pushes ALL staff at once).
//
// Skipped fields:
//   role — Classroom's Staff.role is enum (rejects raw string). Same workaround
//          as gradeLevel in HoS->Classroom. Set via Classroom Staff card if needed.

const DEFAULT_HERO_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';

const COMPARE_FIELDS = ['name', 'initials', 'color', 'avatar'];

export interface SyncStaffToClassroomInput {
  staff: any[];
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  heroRealm?: string;
}

export interface SyncStaffToClassroomResult {
  success: boolean;
  total: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  errors: Array<{ staffName: string; error: string }>;
}

export async function syncStaffToClassroom(
  input: SyncStaffToClassroomInput,
): Promise<SyncStaffToClassroomResult> {
  const { staff, ctx, getCards, host, unwrapResource } = input;
  const heroRealm = input.heroRealm ?? DEFAULT_HERO_REALM;

  const result: SyncStaffToClassroomResult = {
    success: false,
    total: staff.length,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    errors: [],
  };

  if (!ctx || !getCards) {
    result.errors.push({ staffName: '(init)', error: 'Missing ctx or getCards' });
    return result;
  }

  try {
    // Load Classroom's existing Staff cards
    const heroStaffRes = getCards(
      host,
      () => ({ filter: { type: { module: `${heroRealm}staff`, name: 'Staff' } } }),
      () => [heroRealm],
    );
    const heroStaff = await unwrapResource(heroStaffRes, 8000);

    const byNameLower = new Map<string, any>();
    for (const hs of heroStaff) {
      const n = String(hs?.name ?? '').trim().toLowerCase();
      if (n) byNameLower.set(n, hs);
    }

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
    const heroStaffMod: any = await import(`${heroRealm}staff`);
    const HeroStaff = heroStaffMod.Staff;
    if (!HeroStaff) {
      result.errors.push({ staffName: '(init)', error: 'Staff class not found in hero-classroom realm' });
      return result;
    }

    for (const adminS of staff) {
      const sName = String(adminS?.name ?? '').trim();
      if (!sName) {
        result.skipped++;
        continue;
      }
      // Admin field is `avatarColor`, Classroom field is `color`
      const data: Record<string, string> = {
        name: sName,
        initials: String(adminS?.initials ?? sName.split(' ').map((w: string) => w.charAt(0)).join('').slice(0, 2).toUpperCase()),
        color: String(adminS?.avatarColor ?? adminS?.color ?? 'teal'),
        avatar: String(adminS?.avatar ?? ''),
      };

      const existing = byNameLower.get(sName.toLowerCase());

      try {
        if (existing) {
          let changed = false;
          for (const key of COMPARE_FIELDS) {
            const cur = String((existing as any)?.[key] ?? '');
            if (cur !== data[key]) { changed = true; break; }
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
          console.log(`[Admin-Classroom] updated Staff "${sName}"`);
        } else {
          const newStaff = new HeroStaff();
          for (const [k, v] of Object.entries(data)) {
            (newStaff as any)[k] = v;
          }
          await new SaveCardCommand(ctx).execute({ card: newStaff, realm: heroRealm });
          result.created++;
          console.log(`[Admin-Classroom] created Staff "${sName}"`);
        }
      } catch (e: any) {
        const errMsg = e?.message ?? String(e);
        console.warn(`[Admin-Classroom] failed for ${sName}:`, errMsg);
        result.failed++;
        result.errors.push({ staffName: sName, error: errMsg });
      }
    }

    result.success = result.failed === 0;
    return result;
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn('[Admin-Classroom] staff sync failed (top-level):', errMsg);
    result.errors.push({ staffName: '(top-level)', error: errMsg });
    return result;
  }
}

export interface DeleteStaffFromClassroomInput {
  staffName: string;
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  heroRealm?: string;
}

export async function deleteStaffFromClassroom(
  input: DeleteStaffFromClassroomInput,
): Promise<{ deleted: boolean; error?: string }> {
  const { staffName, ctx, getCards, host, unwrapResource } = input;
  const heroRealm = input.heroRealm ?? DEFAULT_HERO_REALM;
  if (!ctx || !getCards || !staffName.trim()) {
    return { deleted: false, error: 'Missing context or staff name' };
  }
  try {
    const heroStaffRes = getCards(
      host,
      () => ({ filter: { type: { module: `${heroRealm}staff`, name: 'Staff' } } }),
      () => [heroRealm],
    );
    const heroStaff = await unwrapResource(heroStaffRes, 8000);
    const target = heroStaff.find((hs: any) =>
      String(hs?.name ?? '').trim().toLowerCase() === staffName.trim().toLowerCase(),
    );
    if (!target?.id) {
      console.log(`[Admin-Classroom] no matching Classroom Staff to delete for "${staffName}"`);
      return { deleted: false };
    }
    await fetch(target.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
    console.log(`[Admin-Classroom] deleted Staff "${staffName}":`, target.id);
    return { deleted: true };
  } catch (e: any) {
    const errMsg = e?.message ?? String(e);
    console.warn(`[Admin-Classroom] delete failed for ${staffName}:`, errMsg);
    return { deleted: false, error: errMsg };
  }
}
// touched for re-index
