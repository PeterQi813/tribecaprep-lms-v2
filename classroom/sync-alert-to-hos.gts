// Push Classroom ClassroomAlert -> HoS ClassroomAlert mirror.
//
// ClassroomAlert schema is identical in both realms (+ sourceAlertId on HoS).
// No enums, no linksTo — all fields are StringField / DatetimeField / BooleanField.
// Dedup key: sourceAlertId on HoS side stores the Classroom alert's URL.

const DEFAULT_HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';

export interface SyncAlertToHosInput {
  action: 'upsert' | 'delete';
  alert: any;
  ctx: any;
  getCards: any;
  host: any;
  unwrapResource: (resource: any, maxMs?: number) => Promise<any[]>;
  hosRealm?: string;
}

export interface SyncAlertToHosResult {
  success: boolean;
  action: 'upsert' | 'delete';
  sourceAlertId: string;
  operation?:
    | 'created'
    | 'updated'
    | 'deleted'
    | 'skipped-no-id'
    | 'skipped-nothing-to-delete'
    | 'skipped-no-context';
  recordId?: string;
  error?: string;
}

export async function syncAlertToHos(
  input: SyncAlertToHosInput,
): Promise<SyncAlertToHosResult> {
  const { action, alert, ctx, getCards, host, unwrapResource } = input;
  const hosRealm = input.hosRealm ?? DEFAULT_HOS_REALM;
  const alertModuleUrl = `${hosRealm}classroom-alert`;

  if (!ctx || !getCards) {
    return { success: false, action, sourceAlertId: '', operation: 'skipped-no-context', error: 'Missing ctx or getCards' };
  }

  const sourceAlertId = String(alert?.id ?? '');
  if (!sourceAlertId) {
    return { success: false, action, sourceAlertId: '', operation: 'skipped-no-id', error: 'Empty alert id' };
  }

  try {
    const res = getCards(
      host,
      () => ({ filter: { type: { module: alertModuleUrl, name: 'ClassroomAlert' } } }),
      () => [hosRealm],
    );
    const allHosAlerts = await unwrapResource(res, 8000);
    const existing = allHosAlerts.find(
      (h: any) => String((h as any)?.sourceAlertId ?? '') === sourceAlertId,
    );

    if (action === 'delete') {
      if (!existing?.id) {
        return { success: true, action, sourceAlertId, operation: 'skipped-nothing-to-delete' };
      }
      try {
        const resp = await fetch(existing.id, {
          method: 'DELETE',
          headers: { Accept: 'application/vnd.card+json' },
        });
        if (!resp.ok && resp.status !== 204 && resp.status !== 404) {
          throw new Error(`HTTP ${resp.status}`);
        }
        console.log('[Classroom-HoS] deleted ClassroomAlert mirror:', existing.id);
        return { success: true, action, sourceAlertId, operation: 'deleted', recordId: existing.id };
      } catch (e: any) {
        console.warn('[Classroom-HoS] alert delete failed:', e);
        return { success: false, action, sourceAlertId, operation: 'deleted', error: String(e?.message ?? e) };
      }
    }

    // UPSERT
    const data: Record<string, any> = {
      alertType: String(alert?.alertType ?? ''),
      urgency: String(alert?.urgency ?? ''),
      message: String(alert?.message ?? ''),
      detail: String(alert?.detail ?? ''),
      studentName: String(alert?.studentName ?? ''),
      createdAt: alert?.createdAt ?? null,
      expiresAt: alert?.expiresAt ?? null,
      createdBy: String(alert?.createdBy ?? ''),
      verified: Boolean(alert?.verified ?? false),
      verifiedAt: String(alert?.verifiedAt ?? ''),
      resolved: Boolean(alert?.resolved ?? false),
      sourceAlertId,
    };

    const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');

    if (existing) {
      for (const [k, v] of Object.entries(data)) (existing as any)[k] = v;
      try {
        await new SaveCardCommand(ctx).execute({ card: existing, realm: hosRealm });
        console.log('[Classroom-HoS] updated ClassroomAlert mirror:', existing.id);
        return { success: true, action, sourceAlertId, operation: 'updated', recordId: existing.id };
      } catch (e: any) {
        console.warn('[Classroom-HoS] alert update failed:', e);
        return { success: false, action, sourceAlertId, operation: 'updated', recordId: existing.id, error: String(e?.message ?? e) };
      }
    } else {
      try {
        const mod: any = await import(/* @vite-ignore */ alertModuleUrl);
        const HosAlert = mod.ClassroomAlert;
        if (!HosAlert) throw new Error('ClassroomAlert class not found in HoS realm');
        const card = new HosAlert();
        for (const [k, v] of Object.entries(data)) (card as any)[k] = v;
        await new SaveCardCommand(ctx).execute({ card, realm: hosRealm });
        console.log('[Classroom-HoS] created ClassroomAlert mirror for:', sourceAlertId);
        return { success: true, action, sourceAlertId, operation: 'created', recordId: (card as any).id };
      } catch (e: any) {
        console.warn('[Classroom-HoS] alert create failed:', e);
        return { success: false, action, sourceAlertId, operation: 'created', error: String(e?.message ?? e) };
      }
    }
  } catch (e: any) {
    console.warn('[Classroom-HoS] alert sync failed (non-fatal):', e);
    return { success: false, action, sourceAlertId, error: String(e?.message ?? e) };
  }
}
// touched for re-index
