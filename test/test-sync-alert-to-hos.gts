// Test card: exercises Classroom helper `syncAlertToHos` end-to-end.
// Test data uses "[TEST-ALERT]" prefix for cleanup-ability.
//
// Scenarios:
//   1. upsert creates HoS mirror
//   2. upsert updates same mirror (no duplicate)
//   3. delete removes HoS mirror

import {
  CardDef,
  Component,
} from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';

const CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';
const TEST_MESSAGE = '[TEST-ALERT] initial message';

export class TestSyncAlertToHos extends CardDef {
  static displayName = 'Test: syncAlertToHos';

  static isolated = class Isolated extends Component<typeof this> {
    @tracked log = '';
    @tracked running = false;
    @tracked testAlertId = '';
    @tracked t1 = ''; @tracked t1Detail = '';
    @tracked t2 = ''; @tracked t2Detail = '';

    get hostGetCards(): any {
      const a = this.args as any;
      return a.context?.getCards ?? a.context?.actions?.getCards ?? null;
    }
    get hostCommandContext(): any {
      const a = this.args as any;
      return a.context?.commandContext ?? a.context?.actions?.commandContext ?? null;
    }

    unwrapResource = async (resource: any, maxMs = 10000): Promise<any[]> => {
      try {
        const r: any = resource;
        if (Array.isArray(r)) return r;
        const read = () => Array.isArray(r?.instances) ? r.instances : (Array.isArray(r?.value) ? r.value : null);
        const t0 = Date.now();
        let hasSeenLoading = false;
        while (Date.now() - t0 < maxMs) {
          const loading = r?.isLoading === true;
          if (loading) hasSeenLoading = true;
          const arr = read();
          if (!loading && arr !== null) {
            if (arr.length > 0) return arr;
            if (hasSeenLoading) return arr;
            if (Date.now() - t0 > 1500) return arr;
          }
          await new Promise((res) => setTimeout(res, 100));
        }
        return read() ?? [];
      } catch (_) { return []; }
    };

    appendLog = (s: string) => {
      const stamp = new Date().toLocaleTimeString();
      this.log = this.log + `[${stamp}] ${s}\n`;
      console.log('[TestSyncAlertToHos]', s);
    };

    findHosMirror = async (sourceAlertId: string): Promise<any | null> => {
      const getCards = this.hostGetCards;
      if (!getCards) return null;
      const res = getCards(
        this,
        () => ({ filter: { type: { module: `${HOS_REALM}classroom-alert`, name: 'ClassroomAlert' } } }),
        () => [HOS_REALM],
      );
      const allHosAlerts = await this.unwrapResource(res, 8000);
      return allHosAlerts.find((h: any) => String(h?.sourceAlertId ?? '') === sourceAlertId) ?? null;
    };

    handleSetup = async () => {
      this.running = true;
      this.t1 = ''; this.t2 = '';
      this.t1Detail = ''; this.t2Detail = '';
      this.appendLog('=== SETUP ===');
      const ctx = this.hostCommandContext;
      if (!ctx) { this.appendLog('FAIL: no ctx'); this.running = false; return; }
      try {
        const mod: any = await import(`${CLASSROOM_REALM}classroom-alert`);
        const Alert = mod.ClassroomAlert;
        const card = new Alert();
        (card as any).alertType = 'Medical';
        (card as any).urgency = 'Info';
        (card as any).message = TEST_MESSAGE;
        (card as any).detail = 'test detail';
        (card as any).studentName = '[TEST-ALERT] Student';
        (card as any).createdAt = new Date();
        (card as any).createdBy = '[TEST-ALERT] Teacher';
        (card as any).resolved = false;
        (card as any).verified = false;
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const result = await new SaveCardCommand(ctx).execute({ card, realm: CLASSROOM_REALM });
        this.testAlertId = String((result as any)?.savedCard?.id ?? (card as any).id);
        this.appendLog(`Created test Alert in Classroom: ${this.testAlertId}`);
      } catch (e: any) {
        this.appendLog(`SETUP FAILED: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleRunTests = async () => {
      if (!this.testAlertId) { this.appendLog('No test alert — click Setup first.'); return; }
      this.running = true;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      try {
        const helperMod: any = await import(`${CLASSROOM_REALM}sync-alert-to-hos`);
        const syncAlertToHos = helperMod.syncAlertToHos;
        if (!syncAlertToHos) throw new Error('syncAlertToHos not exported from Classroom realm');

        // Reload test alert
        const aRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}classroom-alert`, name: 'ClassroomAlert' } } }),
          () => [CLASSROOM_REALM],
        );
        const classroomAlerts = await this.unwrapResource(aRes, 8000);
        const testAlert = classroomAlerts.find((a: any) => String(a?.id ?? '') === this.testAlertId);
        if (!testAlert) throw new Error(`test alert ${this.testAlertId} not found`);

        // === TEST 1: upsert creates mirror ===
        this.appendLog('--- TEST 1: upsert creates HoS mirror ---');
        const preMirror = await this.findHosMirror(this.testAlertId);
        if (preMirror) {
          this.appendLog(`(pre-existing mirror, deleting: ${preMirror.id})`);
          await fetch(preMirror.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          await new Promise(r => setTimeout(r, 1500));
        }
        const r1 = await syncAlertToHos({
          action: 'upsert', alert: testAlert, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r1)}`);
        await new Promise(r => setTimeout(r, 1500));
        const m1 = await this.findHosMirror(this.testAlertId);
        if (m1 && r1.success && r1.operation === 'created') {
          this.t1 = 'pass';
          this.t1Detail = `OK — mirror created at ${m1.id}, message="${m1.message}"`;
        } else {
          this.t1 = 'fail';
          this.t1Detail = `op=${r1.operation}, success=${r1.success}, mirror=${!!m1}, err=${r1.error ?? ''}`;
        }
        this.appendLog(`TEST 1: ${this.t1.toUpperCase()} — ${this.t1Detail}`);

        // === TEST 2: upsert updates (no duplicate) ===
        this.appendLog('--- TEST 2: upsert updates (no duplicate) ---');
        (testAlert as any).resolved = true;
        (testAlert as any).message = '[TEST-ALERT] updated message';
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        await new SaveCardCommand(ctx).execute({ card: testAlert, realm: CLASSROOM_REALM });
        await new Promise(r => setTimeout(r, 1000));
        const r2 = await syncAlertToHos({
          action: 'upsert', alert: testAlert, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r2)}`);
        await new Promise(r => setTimeout(r, 1500));
        const aRes2 = getCards(
          this,
          () => ({ filter: { type: { module: `${HOS_REALM}classroom-alert`, name: 'ClassroomAlert' } } }),
          () => [HOS_REALM],
        );
        const allHos = await this.unwrapResource(aRes2, 8000);
        const matches = allHos.filter((h: any) => String(h?.sourceAlertId ?? '') === this.testAlertId);
        const updated = matches[0];
        if (matches.length === 1 && r2.success && r2.operation === 'updated'
            && String(updated?.message ?? '') === '[TEST-ALERT] updated message'
            && updated?.resolved === true) {
          this.t2 = 'pass';
          this.t2Detail = `OK — 1 mirror, message updated, resolved=true`;
        } else {
          this.t2 = 'fail';
          this.t2Detail = `matches=${matches.length}, op=${r2.operation}, msg="${updated?.message}", resolved=${updated?.resolved}, err=${r2.error ?? ''}`;
        }
        this.appendLog(`TEST 2: ${this.t2.toUpperCase()} — ${this.t2Detail}`);

      } catch (e: any) {
        this.appendLog(`UNHANDLED ERROR: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleCleanup = async () => {
      this.running = true;
      this.appendLog('=== CLEANUP ===');
      try {
        if (this.testAlertId) {
          try {
            await fetch(this.testAlertId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`deleted Classroom alert: ${this.testAlertId}`);
          } catch (_) {}
          const m = await this.findHosMirror(this.testAlertId);
          if (m?.id) {
            await fetch(m.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`deleted HoS mirror: ${m.id}`);
          }
          this.testAlertId = '';
        }
      } catch (e: any) {
        this.appendLog(`CLEANUP error: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    <template>
      <div class='tc'>
        <h1>Test: syncAlertToHos</h1>
        <p class='hint'>Click Setup → Run All Tests → Cleanup in order.</p>
        <div class='actions'>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleSetup}}>1. Setup</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleRunTests}}>2. Run All Tests</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleCleanup}}>3. Cleanup</button>
        </div>
        <div class='results'>
          <div class='row {{if (eq this.t1 "pass") "pass"}} {{if (eq this.t1 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t1 "pass") "✅" (if (eq this.t1 "fail") "❌" "○")}}</span>
            <span class='name'>Test 1: upsert creates HoS mirror</span>
            <span class='detail'>{{this.t1Detail}}</span>
          </div>
          <div class='row {{if (eq this.t2 "pass") "pass"}} {{if (eq this.t2 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t2 "pass") "✅" (if (eq this.t2 "fail") "❌" "○")}}</span>
            <span class='name'>Test 2: upsert updates (no duplicate)</span>
            <span class='detail'>{{this.t2Detail}}</span>
          </div>
        </div>
        <div class='logsec'><h3>Log</h3><pre>{{this.log}}</pre></div>
      </div>
      <style scoped>
        .tc { padding: 1.5rem; font-family: -apple-system, sans-serif; background: #fafafa; min-height: 100%; color: #1a1816; }
        h1 { margin: 0 0 0.5rem; font-size: 1.4rem; }
        .hint { font-size: 0.8125rem; color: #555; margin: 0 0 1rem; }
        .actions { display: flex; gap: 0.5rem; margin-bottom: 1rem; }
        .actions button { padding: 0.5rem 1rem; border-radius: 6px; border: 1px solid #2a9d8f; background: #2a9d8f; color: white; cursor: pointer; font-weight: 600; font-size: 0.875rem; }
        .actions button[disabled] { opacity: 0.5; cursor: wait; }
        .results { background: white; border: 1px solid #e0e0e0; border-radius: 8px; padding: 0.75rem; margin-bottom: 1rem; }
        .row { display: grid; grid-template-columns: 32px 1fr 2fr; gap: 0.5rem; padding: 0.5rem; border-bottom: 1px solid #f0f0f0; align-items: start; }
        .row:last-child { border-bottom: none; }
        .row .icon { font-size: 1.25rem; }
        .row .name { font-weight: 600; }
        .row .detail { font-family: ui-monospace, monospace; font-size: 0.75rem; color: #555; }
        .row.pass { background: #f0faf7; }
        .row.fail { background: #fff0ee; }
        .logsec { background: white; border: 1px solid #e0e0e0; border-radius: 8px; padding: 0.75rem; }
        .logsec h3 { margin: 0 0 0.5rem; font-size: 0.875rem; }
        pre { font-family: ui-monospace, monospace; font-size: 0.75rem; white-space: pre-wrap; max-height: 400px; overflow-y: auto; margin: 0; }
      </style>
    </template>
  };
}
