// Test card: exercises Classroom helper `syncAeToHos` end-to-end against the
// real Classroom + HoS realms. Logs each step and pass/fail flags so we can see
// exactly which scenario fails.
//
// Test data uses "[TEST]" prefix in content so it can be distinguished from
// real observations. Cleanup deletes test data afterwards.
//
// Open this card in Boxel and click the buttons in order:
//   1. Setup        → create a test ActivityEntry in Classroom realm
//   2. Run All Tests → upsert / update / delete via syncAeToHos, verify HoS state
//   3. Cleanup      → remove the test AE (and any leftover HoS mirror)

import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';

const CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';
const TEST_CONTENT_PREFIX = '[TEST sync-ae-to-hos]';

export class TestSyncAeToHos extends CardDef {
  static displayName = 'Test: syncAeToHos';

  static isolated = class Isolated extends Component<typeof this> {
    @tracked log = '';
    @tracked running = false;
    @tracked testAeId = '';
    @tracked t1 = ''; // '' | 'pass' | 'fail'
    @tracked t2 = '';
    @tracked t3 = '';
    @tracked t1Detail = '';
    @tracked t2Detail = '';
    @tracked t3Detail = '';

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
      console.log('[TestSyncAeToHos]', s);
    };

    // Find the HoS ActivityEntry mirror by sourceEntryId.
    findHosMirror = async (sourceEntryId: string): Promise<any | null> => {
      const getCards = this.hostGetCards;
      if (!getCards) return null;
      const aeModuleUrl = `${HOS_REALM}activity-entry`;
      const res = getCards(
        this,
        () => ({ filter: { type: { module: aeModuleUrl, name: 'ActivityEntry' } } }),
        () => [HOS_REALM],
      );
      const allHosAes = await this.unwrapResource(res, 8000);
      return allHosAes.find((h: any) => String(h?.sourceEntryId ?? '') === sourceEntryId) ?? null;
    };

    handleSetup = async () => {
      this.running = true;
      this.t1 = ''; this.t2 = ''; this.t3 = '';
      this.t1Detail = ''; this.t2Detail = ''; this.t3Detail = '';
      this.appendLog('=== SETUP ===');
      const ctx = this.hostCommandContext;
      if (!ctx) { this.appendLog('FAIL: no commandContext'); this.running = false; return; }
      try {
        const aeMod: any = await import(`${CLASSROOM_REALM}activity-entry`);
        const AE = aeMod.ActivityEntry;
        if (!AE) throw new Error('ActivityEntry class not found in Classroom realm');
        const card = new AE();
        (card as any).content = `${TEST_CONTENT_PREFIX} initial content`;
        (card as any).studentName = '[TEST] Student';
        (card as any).authorName = '[TEST] Staff';
        (card as any).activityDate = '2026-04-21';
        (card as any).score = '7/10';
        (card as any).aiTagged = 'false';
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const result = await new SaveCardCommand(ctx).execute({ card, realm: CLASSROOM_REALM });
        const savedId = (result as any)?.savedCard?.id ?? (card as any).id;
        this.testAeId = String(savedId);
        this.appendLog(`Created test AE in Classroom realm: ${this.testAeId}`);
      } catch (e: any) {
        this.appendLog(`SETUP FAILED: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleRunTests = async () => {
      if (!this.testAeId) {
        this.appendLog('No test AE — click Setup first.');
        return;
      }
      this.running = true;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) { this.appendLog('FAIL: no ctx/getCards'); this.running = false; return; }

      try {
        // Import the helper from Classroom realm (this is what we're TESTING)
        const helperMod: any = await import(`${CLASSROOM_REALM}sync-ae-to-hos`);
        const syncAeToHos = helperMod.syncAeToHos;
        if (!syncAeToHos) throw new Error('syncAeToHos not exported from Classroom realm');

        // Reload the test AE to get a fresh card instance
        const aeMod: any = await import(`${CLASSROOM_REALM}activity-entry`);
        const aeRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}activity-entry`, name: 'ActivityEntry' } } }),
          () => [CLASSROOM_REALM],
        );
        const allClassroomAes = await this.unwrapResource(aeRes, 8000);
        const testAe = allClassroomAes.find((a: any) => String(a?.id ?? '') === this.testAeId);
        if (!testAe) throw new Error(`Test AE ${this.testAeId} not found in Classroom realm`);

        // === TEST 1: upsert creates HoS mirror ===
        this.appendLog('--- TEST 1: upsert creates HoS mirror ---');
        // First, ensure no existing mirror
        const preMirror = await this.findHosMirror(this.testAeId);
        if (preMirror) {
          this.appendLog(`(pre-existing mirror found, deleting first: ${preMirror.id})`);
          await fetch(preMirror.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          await new Promise(r => setTimeout(r, 1500));
        }

        const r1 = await syncAeToHos({
          action: 'upsert', ae: testAe, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`syncAeToHos result: ${JSON.stringify(r1)}`);
        await new Promise(r => setTimeout(r, 1500)); // wait for indexer

        const m1 = await this.findHosMirror(this.testAeId);
        if (m1 && r1.success && r1.operation === 'created') {
          this.t1 = 'pass';
          this.t1Detail = `OK — mirror created at ${m1.id}, content="${m1.content}"`;
        } else {
          this.t1 = 'fail';
          this.t1Detail = `FAIL — operation=${r1.operation}, success=${r1.success}, mirror found=${!!m1}, error=${r1.error ?? ''}`;
        }
        this.appendLog(`TEST 1: ${this.t1.toUpperCase()} — ${this.t1Detail}`);

        // === TEST 2: upsert again with changed score → updates same mirror, no dup ===
        this.appendLog('--- TEST 2: upsert updates (no duplicate) ---');
        (testAe as any).score = '9/10';
        (testAe as any).content = `${TEST_CONTENT_PREFIX} updated content`;
        const { default: SaveCardCommand2 } = await import('@cardstack/boxel-host/commands/save-card');
        await new SaveCardCommand2(ctx).execute({ card: testAe, realm: CLASSROOM_REALM });
        await new Promise(r => setTimeout(r, 1000));

        const r2 = await syncAeToHos({
          action: 'upsert', ae: testAe, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`syncAeToHos result: ${JSON.stringify(r2)}`);
        await new Promise(r => setTimeout(r, 1500));

        // Count all HoS mirrors with our sourceEntryId — must be exactly 1
        const aeRes2 = getCards(
          this,
          () => ({ filter: { type: { module: `${HOS_REALM}activity-entry`, name: 'ActivityEntry' } } }),
          () => [HOS_REALM],
        );
        const allHosAes = await this.unwrapResource(aeRes2, 8000);
        const matches = allHosAes.filter((h: any) => String(h?.sourceEntryId ?? '') === this.testAeId);
        const updatedMirror = matches[0];
        if (matches.length === 1 && r2.success && r2.operation === 'updated' && String(updatedMirror?.score ?? '') === '9/10') {
          this.t2 = 'pass';
          this.t2Detail = `OK — exactly 1 mirror, score=${updatedMirror.score}, operation=updated`;
        } else {
          this.t2 = 'fail';
          this.t2Detail = `FAIL — matches=${matches.length}, operation=${r2.operation}, success=${r2.success}, mirror score=${updatedMirror?.score}, error=${r2.error ?? ''}`;
        }
        this.appendLog(`TEST 2: ${this.t2.toUpperCase()} — ${this.t2Detail}`);

        // === TEST 3: delete via syncAeToHos → mirror gone ===
        this.appendLog('--- TEST 3: delete removes HoS mirror ---');
        const r3 = await syncAeToHos({
          action: 'delete', ae: { id: this.testAeId }, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`syncAeToHos result: ${JSON.stringify(r3)}`);
        await new Promise(r => setTimeout(r, 2000)); // delete needs longer settling

        const m3 = await this.findHosMirror(this.testAeId);
        if (!m3 && r3.success && r3.operation === 'deleted') {
          this.t3 = 'pass';
          this.t3Detail = `OK — mirror removed, operation=deleted`;
        } else {
          this.t3 = 'fail';
          this.t3Detail = `FAIL — mirror still exists=${!!m3}, operation=${r3.operation}, success=${r3.success}, error=${r3.error ?? ''}`;
        }
        this.appendLog(`TEST 3: ${this.t3.toUpperCase()} — ${this.t3Detail}`);
      } catch (e: any) {
        this.appendLog(`UNHANDLED ERROR: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleCleanup = async () => {
      this.running = true;
      this.appendLog('=== CLEANUP ===');
      try {
        // Delete the test AE in Classroom realm
        if (this.testAeId) {
          try {
            await fetch(this.testAeId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`Deleted test AE in Classroom: ${this.testAeId}`);
          } catch (_) {}
          // Also delete any HoS mirror that survived
          const m = await this.findHosMirror(this.testAeId);
          if (m?.id) {
            await fetch(m.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`Deleted leftover HoS mirror: ${m.id}`);
          }
          this.testAeId = '';
        }
      } catch (e: any) {
        this.appendLog(`CLEANUP error: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    <template>
      <div class='test-card'>
        <h1>Test: syncAeToHos</h1>
        <p class='hint'>Click Setup → Run All Tests → Cleanup, in order. Watch the log + pass/fail flags below.</p>

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
          <div class='row {{if (eq this.t3 "pass") "pass"}} {{if (eq this.t3 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t3 "pass") "✅" (if (eq this.t3 "fail") "❌" "○")}}</span>
            <span class='name'>Test 3: delete removes HoS mirror</span>
            <span class='detail'>{{this.t3Detail}}</span>
          </div>
        </div>

        <div class='log-section'>
          <h3>Log</h3>
          <pre>{{this.log}}</pre>
        </div>
      </div>

      <style scoped>
        .test-card {
          padding: 1.5rem;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          color: #1a1816;
          background: #fafafa;
          min-height: 100%;
        }
        h1 { margin: 0 0 0.5rem; font-size: 1.5rem; }
        .hint { font-size: 0.875rem; color: #666; margin: 0 0 1rem; }
        .actions { display: flex; gap: 0.5rem; margin-bottom: 1rem; }
        .actions button {
          padding: 0.5rem 1rem; border-radius: 6px; border: 1px solid #2a9d8f;
          background: #2a9d8f; color: white; cursor: pointer; font-weight: 600;
        }
        .actions button[disabled] { opacity: 0.5; cursor: wait; }
        .results { background: white; border: 1px solid #e0e0e0; border-radius: 8px; padding: 0.75rem; margin-bottom: 1rem; }
        .row { display: grid; grid-template-columns: 32px 1fr 2fr; gap: 0.5rem; padding: 0.5rem; border-bottom: 1px solid #f0f0f0; align-items: start; }
        .row:last-child { border-bottom: none; }
        .row .icon { font-size: 1.25rem; }
        .row .name { font-weight: 600; }
        .row .detail { font-family: ui-monospace, monospace; font-size: 0.75rem; color: #555; }
        .row.pass { background: #f0faf7; }
        .row.fail { background: #fff0ee; }
        .log-section { background: white; border: 1px solid #e0e0e0; border-radius: 8px; padding: 0.75rem; }
        .log-section h3 { margin: 0 0 0.5rem; font-size: 0.875rem; }
        pre { font-family: ui-monospace, monospace; font-size: 0.75rem; white-space: pre-wrap; max-height: 400px; overflow-y: auto; margin: 0; }
      </style>
    </template>
  };
}
// touched for re-index
