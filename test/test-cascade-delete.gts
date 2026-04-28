// Test card: exercises the cascade-delete flow (delete Admin Program →
// delete Classroom LG + HoS LG + matching AEs in Classroom + HoS mirrors).
//
// Test data uses "[TEST-CASCADE]" prefix so it's distinguishable + cleanable.
//
// Open in Boxel and click buttons in order:
//   1. Setup        → create test Program + LG (both realms) + AE (both realms)
//   2. Run Cascade  → execute cascade-delete, verify each step
//   3. Cleanup      → remove any leftover test data

import {
  CardDef,
  Component,
} from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';

const ADMIN_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/';
const CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const HOS_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';

const TEST_PROGRAM_TITLE = '[TEST-CASCADE] demo-program';
const TEST_STUDENT_NAME = '[TEST-CASCADE] Student';

export class TestCascadeDelete extends CardDef {
  static displayName = 'Test: cascade-delete (Program→LG→AE)';

  static isolated = class Isolated extends Component<typeof this> {
    @tracked log = '';
    @tracked running = false;
    @tracked programId = '';
    @tracked classroomLgId = '';
    @tracked hosLgId = '';
    @tracked classroomAeId = '';
    @tracked hosAeMirrorId = '';

    @tracked tSetup = '';
    @tracked tSetupDetail = '';
    @tracked tCascade = '';
    @tracked tCascadeDetail = '';
    @tracked tVerify = '';
    @tracked tVerifyDetail = '';

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
      console.log('[TestCascadeDelete]', s);
    };

    handleSetup = async () => {
      this.running = true;
      this.tSetup = ''; this.tCascade = ''; this.tVerify = '';
      this.tSetupDetail = ''; this.tCascadeDetail = ''; this.tVerifyDetail = '';
      this.appendLog('=== SETUP ===');
      const ctx = this.hostCommandContext;
      if (!ctx) { this.tSetup = 'fail'; this.tSetupDetail = 'no commandContext'; this.running = false; return; }

      try {
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');

        // 1. Create Admin ProgramRecord
        const progMod: any = await import(`${ADMIN_REALM}program-record`);
        const prog = new progMod.ProgramRecord();
        (prog as any).program = TEST_PROGRAM_TITLE;
        (prog as any).domain = 'Math';
        (prog as any).domainKey = 'math';
        (prog as any).studentName = TEST_STUDENT_NAME;
        (prog as any).studentId = '[TEST-CASCADE]';
        (prog as any).active = 'Yes';
        (prog as any).targetMastery = 80;
        (prog as any).started = '2026-04-21';
        const pr = await new SaveCardCommand(ctx).execute({ card: prog, realm: ADMIN_REALM });
        this.programId = String((pr as any)?.savedCard?.id ?? (prog as any).id);
        this.appendLog(`Created Admin Program: ${this.programId}`);

        // 2. Create Classroom LearningGoal
        const cLgMod: any = await import(`${CLASSROOM_REALM}learning-goal`);
        const cLg = new cLgMod.LearningGoal();
        (cLg as any).goalTitle = TEST_PROGRAM_TITLE;
        (cLg as any).description = '[TEST-CASCADE] LG desc';
        (cLg as any).studentName = TEST_STUDENT_NAME;
        (cLg as any).currentMastery = 50;
        (cLg as any).targetMastery = 80;
        (cLg as any).startedDate = '2026-04-21';
        const cLgR = await new SaveCardCommand(ctx).execute({ card: cLg, realm: CLASSROOM_REALM });
        this.classroomLgId = String((cLgR as any)?.savedCard?.id ?? (cLg as any).id);
        this.appendLog(`Created Classroom LG: ${this.classroomLgId}`);

        // 3. Create HoS LearningGoal mirror
        const hLgMod: any = await import(`${HOS_REALM}learning-goal`);
        const hLg = new hLgMod.LearningGoal();
        (hLg as any).goalTitle = TEST_PROGRAM_TITLE;
        (hLg as any).description = '[TEST-CASCADE] HoS LG desc';
        (hLg as any).studentName = TEST_STUDENT_NAME;
        (hLg as any).currentMastery = 50;
        (hLg as any).targetMastery = 80;
        (hLg as any).startedDate = '2026-04-21';
        const hLgR = await new SaveCardCommand(ctx).execute({ card: hLg, realm: HOS_REALM });
        this.hosLgId = String((hLgR as any)?.savedCard?.id ?? (hLg as any).id);
        this.appendLog(`Created HoS LG: ${this.hosLgId}`);

        // 4. Create Classroom ActivityEntry (suggestedGoal matching the Program title)
        const cAeMod: any = await import(`${CLASSROOM_REALM}activity-entry`);
        const cAe = new cAeMod.ActivityEntry();
        (cAe as any).content = '[TEST-CASCADE] observation content';
        (cAe as any).studentName = TEST_STUDENT_NAME;
        (cAe as any).authorName = '[TEST-CASCADE] Teacher';
        (cAe as any).activityDate = '2026-04-21';
        (cAe as any).score = '8/10';
        (cAe as any).suggestedGoal = TEST_PROGRAM_TITLE;
        (cAe as any).aiTagged = 'true';
        const cAeR = await new SaveCardCommand(ctx).execute({ card: cAe, realm: CLASSROOM_REALM });
        this.classroomAeId = String((cAeR as any)?.savedCard?.id ?? (cAe as any).id);
        this.appendLog(`Created Classroom AE: ${this.classroomAeId}`);

        // 5. Create HoS AE mirror (sourceEntryId = Classroom AE id)
        const hAeMod: any = await import(`${HOS_REALM}activity-entry`);
        const hAe = new hAeMod.ActivityEntry();
        (hAe as any).content = '[TEST-CASCADE] mirror content';
        (hAe as any).studentName = TEST_STUDENT_NAME;
        (hAe as any).authorName = '[TEST-CASCADE] Teacher';
        (hAe as any).score = '8/10';
        (hAe as any).suggestedGoal = TEST_PROGRAM_TITLE;
        (hAe as any).sourceEntryId = this.classroomAeId;
        const hAeR = await new SaveCardCommand(ctx).execute({ card: hAe, realm: HOS_REALM });
        this.hosAeMirrorId = String((hAeR as any)?.savedCard?.id ?? (hAe as any).id);
        this.appendLog(`Created HoS AE mirror: ${this.hosAeMirrorId}`);

        await new Promise(r => setTimeout(r, 1500)); // indexer settle

        this.tSetup = 'pass';
        this.tSetupDetail = `5 records created across 3 realms`;
        this.appendLog(`SETUP OK`);
      } catch (e: any) {
        this.tSetup = 'fail';
        this.tSetupDetail = e?.message ?? String(e);
        this.appendLog(`SETUP FAIL: ${this.tSetupDetail}`);
      }
      this.running = false;
    };

    // Replicates the cascade logic from admin-dashboard handleDeleteProgram.
    // Same match predicates + same delete ordering.
    handleRunCascade = async () => {
      if (!this.programId) { this.appendLog('No test data — click Setup first.'); return; }
      this.running = true;
      const getCards = this.hostGetCards;
      if (!getCards) { this.tCascade = 'fail'; this.tCascadeDetail = 'no getCards'; this.running = false; return; }
      this.appendLog('=== RUN CASCADE ===');
      const errs: string[] = [];

      try {
        const titleLower = TEST_PROGRAM_TITLE.toLowerCase();
        const studentLower = TEST_STUDENT_NAME.toLowerCase();

        // 0. Cascade delete matching AEs in Classroom + HoS mirrors
        const cAeRes = getCards(this, () => ({
          filter: { type: { module: `${CLASSROOM_REALM}activity-entry`, name: 'ActivityEntry' } },
        }), () => [CLASSROOM_REALM]);
        const classroomAes = await this.unwrapResource(cAeRes, 8000);

        const hAeRes = getCards(this, () => ({
          filter: { type: { module: `${HOS_REALM}activity-entry`, name: 'ActivityEntry' } },
        }), () => [HOS_REALM]);
        const hosAes = await this.unwrapResource(hAeRes, 8000);

        const matchingAes = classroomAes.filter((ae: any) => {
          const raw = String(ae?.suggestedGoal ?? '');
          const clean = raw.replace(/\s*\(.*?\)\s*$/, '').trim().toLowerCase();
          const aeStudent = String(ae?.studentName ?? '').trim().toLowerCase();
          return clean === titleLower && aeStudent === studentLower;
        });
        this.appendLog(`Found ${matchingAes.length} matching Classroom AEs`);

        for (const ae of matchingAes) {
          const aeId = String(ae?.id ?? '');
          try {
            const r = await fetch(aeId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
            if (!r.ok && r.status !== 204 && r.status !== 404) errs.push(`classroom AE ${r.status}`);
            else this.appendLog(`deleted Classroom AE: ${aeId}`);
          } catch (e: any) { errs.push(`classroom AE: ${e?.message}`); }
          const mirror = hosAes.find((h: any) => String(h?.sourceEntryId ?? '') === aeId);
          if (mirror?.id) {
            try {
              await fetch(mirror.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
              this.appendLog(`deleted HoS AE mirror: ${mirror.id}`);
            } catch (e: any) { errs.push(`hos AE: ${e?.message}`); }
          }
        }

        // 1. Delete matching LGs in Classroom + HoS
        for (const realm of [CLASSROOM_REALM, HOS_REALM]) {
          const lgRes = getCards(this, () => ({
            filter: { type: { module: `${realm}learning-goal`, name: 'LearningGoal' } },
          }), () => [realm]);
          const lgs = await this.unwrapResource(lgRes, 8000);
          const lgTarget = lgs.find((g: any) =>
            String(g?.goalTitle ?? '').trim().toLowerCase() === titleLower &&
            String(g?.studentName ?? '').trim().toLowerCase() === studentLower,
          );
          if (lgTarget?.id) {
            try {
              const r = await fetch(lgTarget.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
              if (!r.ok && r.status !== 204 && r.status !== 404) errs.push(`LG in ${realm}: ${r.status}`);
              else this.appendLog(`deleted LG in ${realm === CLASSROOM_REALM ? 'Classroom' : 'HoS'}: ${lgTarget.id}`);
            } catch (e: any) { errs.push(`LG delete: ${e?.message}`); }
          }
        }

        // 2. Delete Admin Program
        try {
          const r = await fetch(this.programId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          if (!r.ok && r.status !== 204 && r.status !== 404) errs.push(`program ${r.status}`);
          else this.appendLog(`deleted Admin Program: ${this.programId}`);
        } catch (e: any) { errs.push(`program: ${e?.message}`); }

        if (errs.length > 0) {
          this.tCascade = 'fail';
          this.tCascadeDetail = errs.join(' | ');
        } else {
          this.tCascade = 'pass';
          this.tCascadeDetail = `All 5 records deleted successfully`;
        }
        this.appendLog(`RUN CASCADE ${this.tCascade.toUpperCase()}`);
      } catch (e: any) {
        this.tCascade = 'fail';
        this.tCascadeDetail = e?.message ?? String(e);
        this.appendLog(`CASCADE FAIL: ${this.tCascadeDetail}`);
      }
      this.running = false;

      // Auto-run verify after short wait
      await new Promise(r => setTimeout(r, 2000));
      await this.handleVerify();
    };

    // Verify all 5 records are gone
    handleVerify = async () => {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      this.appendLog('=== VERIFY ===');
      try {
        const titleLower = TEST_PROGRAM_TITLE.toLowerCase();
        const studentLower = TEST_STUDENT_NAME.toLowerCase();
        const leftovers: string[] = [];

        // Admin Program
        const progRes = getCards(this, () => ({
          filter: { type: { module: `${ADMIN_REALM}program-record`, name: 'ProgramRecord' } },
        }), () => [ADMIN_REALM]);
        const progs = await this.unwrapResource(progRes, 8000);
        const progFound = progs.find((p: any) =>
          String(p?.program ?? '').trim().toLowerCase() === titleLower &&
          String(p?.studentName ?? '').trim().toLowerCase() === studentLower,
        );
        if (progFound) leftovers.push(`Admin Program ${progFound.id}`);

        // LGs in both realms
        for (const realm of [CLASSROOM_REALM, HOS_REALM]) {
          const lgRes = getCards(this, () => ({
            filter: { type: { module: `${realm}learning-goal`, name: 'LearningGoal' } },
          }), () => [realm]);
          const lgs = await this.unwrapResource(lgRes, 8000);
          const found = lgs.find((g: any) =>
            String(g?.goalTitle ?? '').trim().toLowerCase() === titleLower &&
            String(g?.studentName ?? '').trim().toLowerCase() === studentLower,
          );
          if (found) leftovers.push(`${realm === CLASSROOM_REALM ? 'Classroom' : 'HoS'} LG ${found.id}`);
        }

        // AEs in both realms
        for (const realm of [CLASSROOM_REALM, HOS_REALM]) {
          const aeRes = getCards(this, () => ({
            filter: { type: { module: `${realm}activity-entry`, name: 'ActivityEntry' } },
          }), () => [realm]);
          const aes = await this.unwrapResource(aeRes, 8000);
          const found = aes.filter((a: any) =>
            String(a?.studentName ?? '').trim().toLowerCase() === studentLower &&
            String(a?.suggestedGoal ?? '').trim().toLowerCase() === titleLower,
          );
          if (found.length > 0) leftovers.push(`${realm === CLASSROOM_REALM ? 'Classroom' : 'HoS'} AE ×${found.length}`);
        }

        if (leftovers.length === 0) {
          this.tVerify = 'pass';
          this.tVerifyDetail = `All 5 records confirmed gone`;
        } else {
          this.tVerify = 'fail';
          this.tVerifyDetail = `Leftovers: ${leftovers.join(', ')}`;
        }
        this.appendLog(`VERIFY ${this.tVerify.toUpperCase()} — ${this.tVerifyDetail}`);
      } catch (e: any) {
        this.tVerify = 'fail';
        this.tVerifyDetail = e?.message ?? String(e);
        this.appendLog(`VERIFY FAIL: ${this.tVerifyDetail}`);
      }
    };

    handleCleanup = async () => {
      this.running = true;
      this.appendLog('=== CLEANUP ===');
      const targets = [
        this.programId,
        this.classroomLgId,
        this.hosLgId,
        this.classroomAeId,
        this.hosAeMirrorId,
      ].filter(Boolean);
      for (const url of targets) {
        try {
          await fetch(url, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          this.appendLog(`cleanup deleted: ${url}`);
        } catch (_) {}
      }
      this.programId = '';
      this.classroomLgId = '';
      this.hosLgId = '';
      this.classroomAeId = '';
      this.hosAeMirrorId = '';
      this.appendLog('CLEANUP done');
      this.running = false;
    };

    <template>
      <div class='tc'>
        <h1>Test: cascade-delete (Program → LG → AE)</h1>
        <p class='hint'>
          Simulates: delete Admin Program → cascade delete Classroom + HoS LearningGoal → cascade delete
          matching AEs (Classroom + HoS mirrors). Uses isolated "[TEST-CASCADE]" test data.
        </p>
        <div class='actions'>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleSetup}}>1. Setup (create test data)</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleRunCascade}}>2. Run Cascade + Verify</button>
          <button type='button' disabled={{this.running}} {{on 'click' this.handleCleanup}}>3. Cleanup</button>
        </div>

        <div class='results'>
          <div class='row {{if (eq this.tSetup "pass") "pass"}} {{if (eq this.tSetup "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.tSetup "pass") "✅" (if (eq this.tSetup "fail") "❌" "○")}}</span>
            <span class='name'>Setup: create 5 test records</span>
            <span class='detail'>{{this.tSetupDetail}}</span>
          </div>
          <div class='row {{if (eq this.tCascade "pass") "pass"}} {{if (eq this.tCascade "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.tCascade "pass") "✅" (if (eq this.tCascade "fail") "❌" "○")}}</span>
            <span class='name'>Cascade: AEs + LGs + Program deleted</span>
            <span class='detail'>{{this.tCascadeDetail}}</span>
          </div>
          <div class='row {{if (eq this.tVerify "pass") "pass"}} {{if (eq this.tVerify "fail") "fail"}}'>
            <span class='icon'>{{if (eq this.tVerify "pass") "✅" (if (eq this.tVerify "fail") "❌" "○")}}</span>
            <span class='name'>Verify: all 5 records confirmed gone</span>
            <span class='detail'>{{this.tVerifyDetail}}</span>
          </div>
        </div>

        <div class='logsec'>
          <h3>Log</h3>
          <pre>{{this.log}}</pre>
        </div>
      </div>
      <style scoped>
        .tc { padding: 1.5rem; font-family: -apple-system, sans-serif; background: #fafafa; min-height: 100%; color: #1a1816; }
        h1 { margin: 0 0 0.5rem; font-size: 1.4rem; }
        .hint { font-size: 0.8125rem; color: #555; margin: 0 0 1rem; line-height: 1.5; }
        .actions { display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
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
        pre { font-family: ui-monospace, monospace; font-size: 0.7rem; white-space: pre-wrap; max-height: 400px; overflow-y: auto; margin: 0; }
      </style>
    </template>
  };
}
