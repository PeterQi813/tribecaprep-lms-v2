// Approach C helper: push Classroom ActivityEntry -> HoS ActivityEntry mirror.
//
// Same shape as sync-obs-to-admin (also from Classroom), different target realm
// and different field mapping (HoS schema includes more fields than Admin).
//
// SKIPPED:
//   entryType       — enum field on HoS, rejects raw strings (same bug class)
//   author/student/goalLink linksTo — cross-realm linksTo unreliable; use flat names
//
// Dedup key: sourceEntryId on HoS.ActivityEntry stores the Classroom AE's URL.

import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

const DEFAULT_HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';

export interface SyncAeToHosInput {
  action: 'upsert' | 'delete';
  ae: any;
  student?: any;
  staff?: any;
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  hosRealm?: string;
}

export interface SyncAeToHosResult {
  success: boolean;
  action: 'upsert' | 'delete';
  sourceEntryId: string;
  operation?:
    | 'created'
    | 'updated'
    | 'deleted'
    | 'skipped-no-entry-id'
    | 'skipped-nothing-to-delete'
    | 'skipped-no-context';
  recordId?: string;
  error?: string;
}

export async function syncAeToHos(
  input: SyncAeToHosInput,
): Promise<SyncAeToHosResult> {
  const {
    action,
    ae,
    student: studentArg,
    staff: staffArg,
    ctx,
    getCards,
    host,
    unwrapResource,
  } = input;
  const hosRealm = input.hosRealm ?? DEFAULT_HOS_REALM;
  const aeModuleUrl = `${hosRealm}activity-entry`;

  if (!ctx || !getCards) {
    return {
      success: false,
      action,
      sourceEntryId: '',
      operation: 'skipped-no-context',
      error: 'Missing ctx or getCards',
    };
  }

  const sourceEntryId = String(ae?.id ?? '');
  if (!sourceEntryId) {
    return {
      success: false,
      action,
      sourceEntryId: '',
      operation: 'skipped-no-entry-id',
      error: 'Empty sourceEntryId',
    };
  }

  try {
    const res = getCards(
      host,
      () => ({ filter: { type: { module: aeModuleUrl, name: 'ActivityEntry' } } }),
      () => [hosRealm],
    );
    const allHosAes = await unwrapResource(res, 8000);
    const existing = allHosAes.find(
      (h: any) => String((h as any)?.sourceEntryId ?? '') === sourceEntryId,
    );

    if (action === 'delete') {
      if (!existing?.id) {
        return { success: true, action, sourceEntryId, operation: 'skipped-nothing-to-delete' };
      }
      try {
        const resp = await fetch(existing.id, {
          method: 'DELETE',
          headers: { Accept: 'application/vnd.card+json' },
        });
        if (!resp.ok && resp.status !== 204 && resp.status !== 404) {
          const body = await resp.text().catch(() => '');
          throw new Error(`HTTP ${resp.status}: ${body.slice(0, 100)}`);
        }
        console.log('[Classroom-HoS] deleted ActivityEntry mirror:', existing.id);
        return { success: true, action, sourceEntryId, operation: 'deleted', recordId: existing.id };
      } catch (e: any) {
        console.warn('[Classroom-HoS] delete failed:', e);
        return {
          success: false,
          action,
          sourceEntryId,
          operation: 'deleted',
          error: String(e?.message ?? e),
        };
      }
    }

    // UPSERT — flat fields only
    const student = studentArg ?? ae?.student;
    const staff = staffArg ?? ae?.author;
    const studentName =
      `${String(student?.firstName ?? '')} ${String(student?.lastName ?? '')}`.trim() ||
      String(ae?.studentName ?? '');
    const authorName =
      String(staff?.name ?? '') ||
      String(ae?.authorName ?? '');

    const data: Record<string, any> = {
      studentName,
      authorName,
      timestamp: ae?.timestamp ?? null,
      activityDate: String(ae?.activityDate ?? ''),
      content: String(ae?.content ?? ''),
      score: String(ae?.score ?? ''),
      aiTagged: String(ae?.aiTagged ?? ''),
      flagNote: String(ae?.flagNote ?? ''),
      domain: String(ae?.domain ?? ''),
      suggestedGoal: String(ae?.suggestedGoal ?? ''),
      sourceEntryId,
    };
    // entryType INTENTIONALLY SKIPPED — enum bug class, same as gradeLevel/role.

    if (existing) {
      for (const [k, v] of Object.entries(data)) (existing as any)[k] = v;
      try {
        await new SaveCardCommand(ctx).execute({ card: existing, realm: hosRealm });
        console.log('[Classroom-HoS] updated ActivityEntry mirror:', existing.id);
        return { success: true, action, sourceEntryId, operation: 'updated', recordId: existing.id };
      } catch (e: any) {
        console.warn('[Classroom-HoS] update failed:', e);
        return {
          success: false,
          action,
          sourceEntryId,
          operation: 'updated',
          recordId: existing.id,
          error: String(e?.message ?? e),
        };
      }
    } else {
      try {
        const mod: any = await import(/* @vite-ignore */ aeModuleUrl);
        const HosActivityEntry = mod.ActivityEntry;
        if (!HosActivityEntry) {
          throw new Error('ActivityEntry class not found in HoS realm');
        }
        const card = new HosActivityEntry();
        for (const [k, v] of Object.entries(data)) (card as any)[k] = v;
        await new SaveCardCommand(ctx).execute({ card, realm: hosRealm });
        console.log('[Classroom-HoS] created ActivityEntry mirror for:', sourceEntryId);
        return {
          success: true,
          action,
          sourceEntryId,
          operation: 'created',
          recordId: (card as any).id,
        };
      } catch (e: any) {
        console.warn('[Classroom-HoS] create failed:', e);
        return {
          success: false,
          action,
          sourceEntryId,
          operation: 'created',
          error: String(e?.message ?? e),
        };
      }
    }
  } catch (e: any) {
    console.warn('[Classroom-HoS] sync failed (non-fatal):', e);
    return {
      success: false,
      action,
      sourceEntryId,
      error: String(e?.message ?? e),
    };
  }
}
