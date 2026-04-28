// Approach C helper: real-time push from Classroom → Admin ObservationRecord.
//
// Extracted from classroom.gts _syncObsToAdmin (2026-04-20) so the logic
// can be exercised from a test realm without driving the full Classroom UI.
//
// Called on 3 events in Classroom:
//   1. accept suggestion → upsert (with student + staff from current selection)
//   2. edit score        → upsert (student/staff derived from ae.student/ae.author)
//   3. delete AE         → delete (by sourceEntryId lookup)
//
// The helper never throws — all failures return { success: false, ... } so
// callers can decide whether to surface the error or swallow it.

import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

const DEFAULT_ADMIN_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/';

export interface SyncObsToAdminInput {
  action: 'upsert' | 'delete';
  ae: any;              // ActivityEntry card (upsert) or { id } shape (delete)
  student?: any;        // optional, caller-supplied (e.g. accept path)
  staff?: any;          // optional, caller-supplied

  // Host-injected dependencies:
  ctx: any;             // commandContext (host.args.context.commandContext)
  getCards: any;        // getCards factory (host.args.context.getCards)
  host: any;            // `this` for getCards reactivity binding
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;

  // Test/override point:
  adminRealm?: string;
}

export interface SyncObsToAdminResult {
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

export async function syncObsToAdmin(
  input: SyncObsToAdminInput,
): Promise<SyncObsToAdminResult> {
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
  const adminRealm = input.adminRealm ?? DEFAULT_ADMIN_REALM;
  const obsModuleUrl = `${adminRealm}observation-record`;

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
      () => ({ filter: { type: { module: obsModuleUrl, name: 'ObservationRecord' } } }),
      () => [adminRealm],
    );
    const allAdminObs = await unwrapResource(res, 8000);
    const existing = allAdminObs.find(
      (o: any) => String((o as any)?.sourceEntryId ?? '') === sourceEntryId,
    );

    if (action === 'delete') {
      if (!existing?.id) {
        return { success: true, action, sourceEntryId, operation: 'skipped-nothing-to-delete' };
      }
      try {
        await fetch(existing.id, {
          method: 'DELETE',
          headers: { Accept: 'application/vnd.card+json' },
        });
        console.log('[Classroom→Admin] deleted ObservationRecord:', existing.id);
        return { success: true, action, sourceEntryId, operation: 'deleted', recordId: existing.id };
      } catch (e: any) {
        console.warn('[Classroom→Admin] delete failed:', e);
        return {
          success: false,
          action,
          sourceEntryId,
          operation: 'deleted',
          error: String(e?.message ?? e),
        };
      }
    }

    // UPSERT action — prepare flat fields (no cross-realm linksTo resolution)
    const student = studentArg ?? ae?.student;
    const staff = staffArg ?? ae?.author;
    const studentName =
      `${String(student?.firstName ?? '')} ${String(student?.lastName ?? '')}`.trim() ||
      String(ae?.studentName ?? 'Unknown');
    const staffInitials =
      String(staff?.initials ?? '') ||
      (staff?.name
        ? String(staff.name)
            .split(' ')
            .map((w: string) => w.charAt(0))
            .join('')
            .slice(0, 2)
            .toUpperCase()
        : '??');
    const staffColor = String(staff?.color ?? staff?.avatarColor ?? 'teal');

    const actDate = String(ae?.activityDate ?? '');
    let dateStr = '';
    if (actDate) {
      const parts = actDate.split('-');
      if (parts.length >= 3) {
        try {
          dateStr = new Date(
            parseInt(parts[0]),
            parseInt(parts[1]) - 1,
            parseInt(parts[2]),
          ).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        } catch (_) {
          dateStr = actDate;
        }
      }
    }
    if (!dateStr && ae?.timestamp) {
      try {
        dateStr = new Date(ae.timestamp).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
        });
      } catch (_) {}
    }

    const data: Record<string, string> = {
      date: dateStr,
      studentName,
      category: String(
        typeof ae?.entryType === 'object'
          ? ae.entryType?.value ?? ''
          : ae?.entryType ?? 'Academic',
      ),
      linkedGoal: String(ae?.suggestedGoal ?? ''),
      score: String(ae?.score ?? '') || '\u2014',
      staffInitials,
      staffColor,
      flagged: ae?.flagNote ? 'true' : 'false',
      notes: String(ae?.content ?? ''),
      sourceEntryId,
    };

    if (existing) {
      for (const [k, v] of Object.entries(data)) (existing as any)[k] = v;
      try {
        await new SaveCardCommand(ctx).execute({ card: existing, realm: adminRealm });
        console.log('[Classroom→Admin] updated ObservationRecord:', existing.id);
        return {
          success: true,
          action,
          sourceEntryId,
          operation: 'updated',
          recordId: existing.id,
        };
      } catch (e: any) {
        console.warn('[Classroom→Admin] update failed:', e);
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
        const mod: any = await import(/* @vite-ignore */ obsModuleUrl);
        const ObservationRecord = mod.ObservationRecord;
        if (!ObservationRecord) {
          throw new Error('ObservationRecord class not found in admin realm');
        }
        const card = new ObservationRecord();
        for (const [k, v] of Object.entries(data)) (card as any)[k] = v;
        await new SaveCardCommand(ctx).execute({ card, realm: adminRealm });
        console.log('[Classroom→Admin] created ObservationRecord for AE:', sourceEntryId);
        return {
          success: true,
          action,
          sourceEntryId,
          operation: 'created',
          recordId: (card as any).id,
        };
      } catch (e: any) {
        console.warn('[Classroom→Admin] create failed (Admin reconcile will fix):', e);
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
    console.warn('[Classroom→Admin] sync failed (non-fatal):', e);
    return {
      success: false,
      action,
      sourceEntryId,
      error: String(e?.message ?? e),
    };
  }
}
// touched for re-index
