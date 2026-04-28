// Test card: exercises Classroom helper `syncStudentLocationToHos` end-to-end.
//
// Requires a Classroom Student WITH studentId that already has a matching
// HoS Student mirror (same studentId stored on HoS side). Setup snapshots
// original field values so cleanup restores them.
//
// Scenarios:
//   1. update — change location/detail/returnTime, push, verify HoS mirror matches
//   2. unchanged — push again without changes, verify operation='unchanged'
//   3. no-mirror — push with fake studentId, verify operation='skipped-no-mirror'

import {
  CardDef,
  Component,
} from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';

const CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';
const TEST_LOC = '[TEST-LOC] Nurse';
const TEST_DETAIL = '[TEST-LOC] seen @ 2pm';
const TEST_RETURN = '[TEST-LOC] 3:00 PM';

export class TestSyncStudentLocationToHos extends CardDef {
  static displayName = 'Test: syncStudentLocationToHos';

  static isolated = class Isolated extends Component<typeof this> {
    @tracked log = '';
    @tracked running = false;
    @tracked testStudentId = '';
    @tracked testClassroomCardId = '';
    @tracked origLocation = '';
    @tracked origDetail = '';
    @tracked origReturn = '';
    @tracked origHosLocation = '';
    @tracked origHosDetail = '';
    @tracked origHosReturn = '';
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
      console.log('[TestSyncStudentLocationToHos]', s);
    };

    findHosMirror = async (studentId: string): Promise<any | null> => {
      const getCards = this.hostGetCards;
      if (!getCards) return null;
      const profRes = getCards(
        this,
        () => ({ filter: { type: { module: `${HOS_REALM}student-full-profile`, name: 'StudentFullProfile' } } }),
        () => [HOS_REALM],
      );
      const profiles = await this.unwrapResource(profRes, 8000);
      const matchProfile = profiles.find(
        (p: any) => String(p?.identity?.studentId ?? '').trim() === studentId,
      );
      if (!matchProfile) return null;
      const profileId = String((matchProfile as any).id ?? '');
      const stuRes = getCards(
        this,
        () => ({ filter: { type: { module: `${HOS_REALM}student`, name: 'Student' } } }),
        () => [HOS_REALM],
      );
      const all = await this.unwrapResource(stuRes, 8000);
      return all.find((s: any) => String((s as any)?.fullProfile?.id ?? '') === profileId) ?? null;
    };

    handleSetup = async () => {
      this.running = true;
      this.t1 = ''; this.t2 = ''; this.t3 = '';
      this.t1Detail = ''; this.t2Detail = ''; this.t3Detail = '';
      this.appendLog('=== SETUP: find matched Classroom+HoS student pair ===');
      const getCards = this.hostGetCards;
      if (!getCards) { this.appendLog('FAIL: no getCards'); this.running = false; return; }
      try {
        const cRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}student`, name: 'Student' } } }),
          () => [CLASSROOM_REALM],
        );
        const classroomStudents = await this.unwrapResource(cRes, 8000);
        const profRes = getCards(
          this,
          () => ({ filter: { type: { module: `${HOS_REALM}student-full-profile`, name: 'StudentFullProfile' } } }),
          () => [HOS_REALM],
        );
        const profiles = await this.unwrapResource(profRes, 8000);
        const hRes = getCards(
          this,
          () => ({ filter: { type: { module: `${HOS_REALM}student`, name: 'Student' } } }),
          () => [HOS_REALM],
        );
        const hosStudents = await this.unwrapResource(hRes, 8000);
        this.appendLog(`found ${classroomStudents.length} Classroom Students, ${profiles.length} HoS profiles, ${hosStudents.length} HoS Students`);

        // profiles by studentId → profile id
        const profileIdByStudentId = new Map<string, string>();
        for (const p of profiles) {
          const sid = String(p?.identity?.studentId ?? '').trim();
          const pid = String((p as any)?.id ?? '');
          if (sid && pid) profileIdByStudentId.set(sid, pid);
        }
        // HoS Students by fullProfile.id
        const hosByProfileId = new Map<string, any>();
        for (const s of hosStudents) {
          const pid = String((s as any)?.fullProfile?.id ?? '');
          if (pid) hosByProfileId.set(pid, s);
        }

        let match: any = null;
        let hosMirror: any = null;
        for (const c of classroomStudents) {
          const sid = String(c?.studentId ?? '').trim();
          if (!sid) continue;
          const pid = profileIdByStudentId.get(sid);
          if (!pid) continue;
          const mirror = hosByProfileId.get(pid);
          if (mirror) { match = c; hosMirror = mirror; break; }
        }
        if (!match) {
          this.appendLog('FAIL: no matched triple found. Classroom Student → HoS StudentFullProfile (by studentId) → HoS Student (by fullProfile link).');
          this.running = false; return;
        }
        this.testStudentId = String((match as any)?.studentId ?? '').trim();
        this.testClassroomCardId = String((match as any)?.id ?? '');
        this.origLocation = String((match as any)?.location ?? '');
        this.origDetail = String((match as any)?.locationDetail ?? '');
        this.origReturn = String((match as any)?.returnTime ?? '');
        this.origHosLocation = String((hosMirror as any)?.location ?? '');
        this.origHosDetail = String((hosMirror as any)?.locationDetail ?? '');
        this.origHosReturn = String((hosMirror as any)?.returnTime ?? '');
        this.appendLog(`matched studentId=${this.testStudentId}`);
        this.appendLog(`Classroom: ${(match as any).id}  loc="${this.origLocation}"  detail="${this.origDetail}"  return="${this.origReturn}"`);
        this.appendLog(`HoS mirror: ${(hosMirror as any).id}  loc="${this.origHosLocation}"  detail="${this.origHosDetail}"  return="${this.origHosReturn}"`);
      } catch (e: any) {
        this.appendLog(`SETUP FAILED: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    handleRunTests = async () => {
      if (!this.testStudentId) { this.appendLog('No test pair — click Setup first.'); return; }
      this.running = true;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      try {
        const helperMod: any = await import(`${CLASSROOM_REALM}sync-student-location-to-hos`);
        const syncStudentLocationToHos = helperMod.syncStudentLocationToHos;
        if (!syncStudentLocationToHos) throw new Error('syncStudentLocationToHos not exported from Classroom realm');

        // Reload Classroom Student
        const cRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}student`, name: 'Student' } } }),
          () => [CLASSROOM_REALM],
        );
        const classroomStudents = await this.unwrapResource(cRes, 8000);
        const testStudent = classroomStudents.find((s: any) => String(s?.id ?? '') === this.testClassroomCardId);
        if (!testStudent) throw new Error(`test Classroom Student ${this.testClassroomCardId} not found`);

        // === TEST 1: update ===
        this.appendLog('--- TEST 1: push updates HoS mirror ---');
        (testStudent as any).location = TEST_LOC;
        (testStudent as any).locationDetail = TEST_DETAIL;
        (testStudent as any).returnTime = TEST_RETURN;
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        await new SaveCardCommand(ctx).execute({ card: testStudent, realm: CLASSROOM_REALM });
        await new Promise(r => setTimeout(r, 800));
        const r1 = await syncStudentLocationToHos({
          student: testStudent, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r1)}`);
        await new Promise(r => setTimeout(r, 1500));
        const m1 = await this.findHosMirror(this.testStudentId);
        if (m1 && r1.success && r1.operation === 'updated'
            && String(m1?.location ?? '') === TEST_LOC
            && String(m1?.locationDetail ?? '') === TEST_DETAIL
            && String(m1?.returnTime ?? '') === TEST_RETURN) {
          this.t1 = 'pass';
          this.t1Detail = `OK — HoS mirror loc="${m1.location}" detail="${m1.locationDetail}" return="${m1.returnTime}"`;
        } else {
          this.t1 = 'fail';
          this.t1Detail = `op=${r1.operation}, success=${r1.success}, HoS loc="${m1?.location}" detail="${m1?.locationDetail}" return="${m1?.returnTime}", err=${r1.error ?? ''}`;
        }
        this.appendLog(`TEST 1: ${this.t1.toUpperCase()} — ${this.t1Detail}`);

        // === TEST 2: unchanged ===
        this.appendLog('--- TEST 2: push with no changes returns unchanged ---');
        const r2 = await syncStudentLocationToHos({
          student: testStudent, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r2)}`);
        if (r2.success && r2.operation === 'unchanged') {
          this.t2 = 'pass';
          this.t2Detail = `OK — operation='unchanged'`;
        } else {
          this.t2 = 'fail';
          this.t2Detail = `op=${r2.operation}, success=${r2.success}, err=${r2.error ?? ''}`;
        }
        this.appendLog(`TEST 2: ${this.t2.toUpperCase()} — ${this.t2Detail}`);

        // === TEST 3: no profile match ===
        this.appendLog('--- TEST 3: push with fake studentId returns skipped-no-profile ---');
        const fake = { studentId: 'FAKE-NONEXISTENT-' + Date.now(), location: 'X', locationDetail: 'Y', returnTime: 'Z' };
        const r3 = await syncStudentLocationToHos({
          student: fake, ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        this.appendLog(`result: ${JSON.stringify(r3)}`);
        if (r3.success && r3.operation === 'skipped-no-profile') {
          this.t3 = 'pass';
          this.t3Detail = `OK — operation='skipped-no-profile'`;
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
      if (!this.testStudentId) { this.appendLog('nothing to clean up.'); return; }
      this.running = true;
      this.appendLog('=== CLEANUP: restore original values ===');
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      try {
        const cRes = getCards(
          this,
          () => ({ filter: { type: { module: `${CLASSROOM_REALM}student`, name: 'Student' } } }),
          () => [CLASSROOM_REALM],
        );
        const classroomStudents = await this.unwrapResource(cRes, 8000);
        const testStudent = classroomStudents.find((s: any) => String(s?.id ?? '') === this.testClassroomCardId);
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        if (testStudent) {
          (testStudent as any).location = this.origLocation;
          (testStudent as any).locationDetail = this.origDetail;
          (testStudent as any).returnTime = this.origReturn;
          await new SaveCardCommand(ctx).execute({ card: testStudent, realm: CLASSROOM_REALM });
          this.appendLog(`restored Classroom Student to loc="${this.origLocation}" detail="${this.origDetail}" return="${this.origReturn}"`);
        }
        const mirror = await this.findHosMirror(this.testStudentId);
        if (mirror) {
          (mirror as any).location = this.origHosLocation;
          (mirror as any).locationDetail = this.origHosDetail;
          (mirror as any).returnTime = this.origHosReturn;
          await new SaveCardCommand(ctx).execute({ card: mirror, realm: HOS_REALM });
          this.appendLog(`restored HoS mirror to loc="${this.origHosLocation}" detail="${this.origHosDetail}" return="${this.origHosReturn}"`);
        }
        this.testStudentId = '';
        this.testClassroomCardId = '';
      } catch (e: any) {
        this.appendLog(`CLEANUP error: ${e?.message ?? String(e)}`);
      }
      this.running = false;
    };

    <template>
      <div class='tc'>
        <h1>Test: syncStudentLocationToHos</h1>
        <p class='hint'>Click Setup → Run All Tests → Cleanup in order. Uses an existing matched Student pair.</p>
        <div class='actions'>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleSetup}}>1. Setup</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleRunTests}}>2. Run All Tests</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleCleanup}}>3. Cleanup</button>
        </div>
        <div class='results'>
          <div class='row {{if (eq this.t1 "pass") "pass"}} {{if (eq this.t1 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t1 "pass") "✅" (if (eq this.t1 "fail") "❌" "○")}}</span>
            <span class='name'>Test 1: push updates HoS mirror</span>
            <span class='detail'>{{this.t1Detail}}</span>
          </div>
          <div class='row {{if (eq this.t2 "pass") "pass"}} {{if (eq this.t2 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t2 "pass") "✅" (if (eq this.t2 "fail") "❌" "○")}}</span>
            <span class='name'>Test 2: no-op push returns 'unchanged'</span>
            <span class='detail'>{{this.t2Detail}}</span>
          </div>
          <div class='row {{if (eq this.t3 "pass") "pass"}} {{if (eq this.t3 "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.t3 "pass") "✅" (if (eq this.t3 "fail") "❌" "○")}}</span>
            <span class='name'>Test 3: missing profile returns 'skipped-no-profile'</span>
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
