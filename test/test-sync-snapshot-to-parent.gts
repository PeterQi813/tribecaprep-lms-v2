// Test card: exercises Classroom helper `syncSnapshotToParent`.
//
// Setup: finds a Classroom Student + a date with ActivityEntry for that student.
//
// Scenarios:
//   1. create — first call builds new ImportSnapshot in Parent Daily realm
//   2. update — second call updates same snapshot (no duplicate by slug+date)
//   3. no-student — fake slug returns 'skipped-no-student'

import {
  CardDef,
  Component,
} from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';

const CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const PARENT_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/';

export class TestSyncSnapshotToParent extends CardDef {
  static displayName = 'Test: syncSnapshotToParent';

  static isolated = class Isolated extends Component<typeof this> {
    @tracked log = '';
    @tracked running = false;
    @tracked testStudentSlug = '';
    @tracked testDate = '';
    @tracked createdSnapshotId = '';
    @tracked t1 = ''; @tracked t1Detail = '';
    @tracked t2 = ''; @tracked t2Detail = '';
    @tracked t3 = ''; @tracked t3Detail = '';

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
            if (Date.now() - t0 > 8000) return arr;
          }
          await new Promise((res) => setTimeout(res, 100));
        }
        return read() ?? [];
      } catch (_) { return []; }
    };

    appendLog = (s: string) => {
      const stamp = new Date().toLocaleTimeString();
      this.log = this.log + `[${stamp}] ${s}\n`;
      console.log('[TestSyncSnapshotToParent]', s);
    };

    dateToYMD = (d: any): string => {
      try {
        const dt = typeof d === 'string' ? new Date(d) : d instanceof Date ? d : new Date(d);
        if (isNaN(dt.getTime())) return '';
        return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
      } catch (_) { return ''; }
    };

    findExistingSnapshot = async (slug: string, date: string): Promise<any | null> => {
      const getCards = this.hostGetCards;
      if (!getCards) return null;
      const res = getCards(
        this,
        () => ({ filter: { type: { module: `${PARENT_REALM}import-snapshot`, name: 'ImportSnapshot' } } }),
        () => [PARENT_REALM],
      );
      const all = await this.unwrapResource(res, 8000);
      return all.find((s: any) => {
        if (String(s?.studentSlug ?? '') !== slug) return false;
        return this.dateToYMD(s?.snapshotDate) === date;
      }) ?? null;
    };

    handleSetup = async () => {
      this.running = true;
      this.t1 = ''; this.t2 = ''; this.t3 = '';
      this.t1Detail = ''; this.t2Detail = ''; this.t3Detail = '';
      this.appendLog('=== SETUP: find Classroom Student + date with AEs ===');
      const getCards = this.hostGetCards;
      if (!getCards) { this.appendLog('FAIL: no getCards'); this.running = false; return; }
      try {
        const entriesRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}activity-entry`, name: 'ActivityEntry' } } }),
          () => [CLASSROOM_REALM],
        );
        const allEntries = await this.unwrapResource(entriesRes, 10000);
        this.appendLog(`found ${allEntries.length} ActivityEntry cards in Classroom`);

        // Group entries by (slug, ymd) to find a pair with maximum entries
        // Use raw relationships path because cross-realm linksTo may not hydrate
        const buckets = new Map<string, { slug: string; date: string; count: number }>();
        for (const e of allEntries) {
          const hydrated = String((e as any)?.student?.id ?? '');
          const raw = String((e as any)?.relationships?.student?.links?.self ?? '');
          const id = hydrated || raw;
          const slug = id.split('/').pop() ?? '';
          const ymd = this.dateToYMD(e?.timestamp);
          if (!slug || !ymd) continue;
          const key = `${slug}|${ymd}`;
          const cur = buckets.get(key);
          if (cur) cur.count++;
          else buckets.set(key, { slug, date: ymd, count: 1 });
        }
        const best = [...buckets.values()].sort((a, b) => b.count - a.count)[0];
        if (!best) {
          this.appendLog('FAIL: no ActivityEntry with both student + timestamp found.');
          this.running = false; return;
        }
        this.testStudentSlug = best.slug;
        this.testDate = best.date;
        this.appendLog(`picked slug="${best.slug}" date="${best.date}" with ${best.count} entries`);

        // Check if an existing snapshot already exists → note but don't delete
        const pre = await this.findExistingSnapshot(this.testStudentSlug, this.testDate);
        if (pre) {
          this.appendLog(`(pre-existing snapshot detected: ${pre.id})`);
        }

        // ─── Warm caches for all getCards calls the helper will make ───
        this.appendLog('warming cross-realm caches...');
        const warmSpecs: Array<[string, string, string, string]> = [
          [CLASSROOM_REALM, 'activity-entry', 'ActivityEntry', 'classroom AEs'],
          [CLASSROOM_REALM, 'student', 'Student', 'classroom Students'],
          [CLASSROOM_REALM, 'daily-plan', 'DailyPlan', 'classroom Plans'],
          [CLASSROOM_REALM, 'learning-goal', 'LearningGoal', 'classroom Goals'],
          [CLASSROOM_REALM, 'staff', 'Staff', 'classroom Staff'],
          [PARENT_REALM, 'import-snapshot', 'ImportSnapshot', 'parent ImportSnapshots'],
        ];
        const warmResources = warmSpecs.map(([realm, mod, name]) =>
          getCards(this, () => ({ filter: { type: { module: `${realm}${mod}`, name } } }), () => [realm])
        );
        for (let i = 0; i < warmResources.length; i++) {
          const arr = await this.unwrapResource(warmResources[i], 25000);
          this.appendLog(`  warm ${warmSpecs[i][3]}: ${arr.length}`);
        }
      } catch (e: any) {
        this.appendLog(`SETUP FAILED: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleRunTests = async () => {
      if (!this.testStudentSlug || !this.testDate) { this.appendLog('No setup — click Setup first.'); return; }
      this.running = true;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      try {
        const helperMod: any = await import(`${CLASSROOM_REALM}sync-snapshot-to-parent`);
        const syncSnapshotToParent = helperMod.syncSnapshotToParent;
        if (!syncSnapshotToParent) throw new Error('syncSnapshotToParent not exported from Classroom realm');

        // Clean slate: delete any pre-existing snapshot for this (slug, date)
        const pre = await this.findExistingSnapshot(this.testStudentSlug, this.testDate);
        if (pre?.id) {
          this.appendLog(`(deleting pre-existing snapshot ${pre.id} for clean test)`);
          await fetch(pre.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          await new Promise(r => setTimeout(r, 1500));
        }

        // === TEST 1: create ===
        this.appendLog('--- TEST 1: first call creates ImportSnapshot ---');
        const r1 = await syncSnapshotToParent({
          studentSlug: this.testStudentSlug, snapshotDate: this.testDate,
          ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r1)}`);
        await new Promise(r => setTimeout(r, 2000));
        const m1 = await this.findExistingSnapshot(this.testStudentSlug, this.testDate);
        if (m1 && r1.success && r1.operation === 'created' && (r1.entryCount ?? 0) > 0) {
          this.t1 = 'pass';
          this.t1Detail = `OK — created at ${m1.id}, entryCount=${r1.entryCount}`;
          this.createdSnapshotId = String(m1.id ?? '');
        } else {
          this.t1 = 'fail';
          this.t1Detail = `op=${r1.operation}, success=${r1.success}, entryCount=${r1.entryCount}, mirror=${!!m1}, err=${r1.error ?? ''}`;
        }
        this.appendLog(`TEST 1: ${this.t1.toUpperCase()} — ${this.t1Detail}`);

        // === TEST 2: update (no dup) ===
        this.appendLog('--- TEST 2: second call updates (no duplicate) ---');
        const r2 = await syncSnapshotToParent({
          studentSlug: this.testStudentSlug, snapshotDate: this.testDate,
          ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r2)}`);
        await new Promise(r => setTimeout(r, 2000));
        const allSnapsRes = getCards(
          this,
          () => ({ filter: { type: { module: `${PARENT_REALM}import-snapshot`, name: 'ImportSnapshot' } } }),
          () => [PARENT_REALM],
        );
        const allSnaps = await this.unwrapResource(allSnapsRes, 8000);
        const matches = allSnaps.filter((s: any) => {
          if (String(s?.studentSlug ?? '') !== this.testStudentSlug) return false;
          return this.dateToYMD(s?.snapshotDate) === this.testDate;
        });
        if (matches.length === 1 && r2.success && r2.operation === 'updated') {
          this.t2 = 'pass';
          this.t2Detail = `OK — 1 snapshot exists, op='updated'`;
        } else {
          this.t2 = 'fail';
          this.t2Detail = `matches=${matches.length}, op=${r2.operation}, err=${r2.error ?? ''}`;
        }
        this.appendLog(`TEST 2: ${this.t2.toUpperCase()} — ${this.t2Detail}`);

        // === TEST 3: fake slug ===
        this.appendLog('--- TEST 3: fake studentSlug returns skipped-no-student ---');
        const r3 = await syncSnapshotToParent({
          studentSlug: 'FAKE-NONEXISTENT-' + Date.now(),
          snapshotDate: this.testDate,
          ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r3)}`);
        if (!r3.success && r3.operation === 'skipped-no-student') {
          this.t3 = 'pass';
          this.t3Detail = `OK — operation='skipped-no-student'`;
        } else {
          this.t3 = 'fail';
          this.t3Detail = `op=${r3.operation}, success=${r3.success}, err=${r3.error ?? ''}`;
        }
        this.appendLog(`TEST 3: ${this.t3.toUpperCase()} — ${this.t3Detail}`);
      } catch (e: any) {
        this.appendLog(`UNHANDLED ERROR: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleCleanup = async () => {
      this.running = true;
      this.appendLog('=== CLEANUP: delete test snapshot ===');
      try {
        if (this.createdSnapshotId) {
          try {
            await fetch(this.createdSnapshotId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`deleted snapshot: ${this.createdSnapshotId}`);
          } catch (e) { this.appendLog(`delete by id failed: ${e}`); }
          this.createdSnapshotId = '';
        } else if (this.testStudentSlug && this.testDate) {
          const m = await this.findExistingSnapshot(this.testStudentSlug, this.testDate);
          if (m?.id) {
            await fetch(m.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            this.appendLog(`deleted snapshot by lookup: ${m.id}`);
          }
        }
        this.testStudentSlug = '';
        this.testDate = '';
      } catch (e: any) {
        this.appendLog(`CLEANUP error: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    <template>
      <div class='tc'>
        <h1>Test: syncSnapshotToParent</h1>
        <p class='hint'>Click Setup → Run All Tests → Cleanup in order. Auto-picks a (student, date) with AEs.</p>
        <div class='actions'>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleSetup}}>1. Setup</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleRunTests}}>2. Run All Tests</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleCleanup}}>3. Cleanup</button>
        </div>
        <div class='results'>
          <div class='row {{if (eq this.t1 "pass") "pass"}} {{if (eq this.t1 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t1 "pass") "✅" (if (eq this.t1 "fail") "❌" "○")}}</span>
            <span class='name'>Test 1: first call creates ImportSnapshot</span>
            <span class='detail'>{{this.t1Detail}}</span>
          </div>
          <div class='row {{if (eq this.t2 "pass") "pass"}} {{if (eq this.t2 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t2 "pass") "✅" (if (eq this.t2 "fail") "❌" "○")}}</span>
            <span class='name'>Test 2: second call updates (no duplicate)</span>
            <span class='detail'>{{this.t2Detail}}</span>
          </div>
          <div class='row {{if (eq this.t3 "pass") "pass"}} {{if (eq this.t3 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t3 "pass") "✅" (if (eq this.t3 "fail") "❌" "○")}}</span>
            <span class='name'>Test 3: fake slug returns 'skipped-no-student'</span>
            <span class='detail'>{{this.t3Detail}}</span>
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
