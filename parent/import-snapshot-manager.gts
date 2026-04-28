// Phase 1 — ImportSnapshotManager (developer back-office tool)
//
// All cross-realm fetch + persistence logic lives in this Component because
// `getCards` is a host-injected helper available only via args.context, not
// importable. Command.run() bodies cannot use it. Phase 1 doesn't call AI
// (Phase 0 already validated that path), so we don't need a Command wrapper —
// the Component does the fetch + freeze + save inline.
//
// IMPORTANT: `getCards` from card-api is a TYPE-only export. The runtime
// function is `this.args.context.getCards`. Do NOT `import { getCards }`.

import {
  CardDef,
  field,
  contains,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';

import { ImportSnapshot } from './import-snapshot';
import type { FrozenEntry } from './import-snapshot';
import { SkillCard } from './skill-card';
import { generateDailyCommunication } from './daily-communication';
import { generateParentSummary } from './parent-daily-summary';

const HERO_CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
const DASHBOARD_URL =
  'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main';

interface StudentOption {
  slug: string;
  displayName: string;
  grade: string;
}

interface SkillCardOption {
  card: any;            // the live SkillCard instance
  id: string;           // card URL
  name: string;
  version: string;
  isActive: boolean;
}

export class ImportSnapshotManager extends CardDef {
  static displayName = 'Import Snapshot Manager';
  static prefersWideFormat = true;

  // Auto-query all ImportSnapshot cards in this (parent-daily) realm
  @field snapshots = linksToMany(() => ImportSnapshot, {
    query: {
      filter: {
        type: {
          module: `${new URL('./import-snapshot', import.meta.url).href}`,
          name: 'ImportSnapshot',
        },
      },
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: ImportSnapshotManager) {
      return 'Import Snapshot Manager (Phase 1 dev tool)';
    },
  });

  static isolated = class Isolated extends Component<typeof ImportSnapshotManager> {
    dashboardUrl = DASHBOARD_URL;

    @tracked students: StudentOption[] = [];
    @tracked studentsLoading = true;
    @tracked studentsError: string | null = null;

    @tracked selectedSlug = 'jamie-chen';
    @tracked selectedDate = (() => { const n = new Date(); return `${n.getFullYear()}-${String(n.getMonth()+1).padStart(2,'0')}-${String(n.getDate()).padStart(2,'0')}`; })();

    @tracked lastSavedId: string | null = null;

    @tracked previewSnapshot: any = null;

    // ── Phase 3: SkillCard selection + Generate state ──
    @tracked skillCards: SkillCardOption[] = [];
    @tracked skillCardsLoading = false;
    @tracked selectedSkillCardId: string | null = null;
    @tracked generateState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked generateMessage: string | null = null;

    // ── Batch states ──
    @tracked batchDCState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchDCMessage: string | null = null;
    @tracked batchDCError: string | null = null;

    @tracked batchPSState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchPSMessage: string | null = null;
    @tracked batchPSError: string | null = null;
    @tracked generateError: string | null = null;
    @tracked lastGeneratedCardId: string | null = null;
    @tracked lastGeneratedLatencyMs: number | null = null;

    constructor(owner: any, args: any) {
      super(owner, args);
      this.loadStudents();
      this.loadSkillCards();
    }

    // ─── Resolve host-injected helpers from args.context ───
    get hostGetCards(): any {
      const argsAny = this.args as any;
      return (
        argsAny.context?.getCards ??
        argsAny.context?.actions?.getCards ??
        null
      );
    }

    get hostCommandContext(): any {
      const argsAny = this.args as any;
      return (
        argsAny.context?.commandContext ??
        argsAny.context?.actions?.commandContext ??
        null
      );
    }

    // ─── Unwrap a StoreSearchResource: poll isLoading then read .instances ───
    // Per Boxel host real-world usage (e.g. playground-panel.gts):
    //   const resource = this.getCards(this, () => query, () => realms);
    //   resource?.isLoading      <-- loading flag
    //   resource?.instances      <-- the actual array
    // The type alias in card-api.gts says `.value`, but the runtime field is
    // `.instances`. We try both, preferring instances.
    async unwrapCardsResource(resource: any, maxWaitMs = 10000): Promise<any[]> {
      try {
        const r: any = resource;
        if (Array.isArray(r)) return r;

        const readArr = (): any[] | null => {
          if (Array.isArray(r?.instances)) return r.instances;
          if (Array.isArray(r?.value)) return r.value;
          return null;
        };

        const start = Date.now();
        let lastLog = 0;
        while (Date.now() - start < maxWaitMs) {
          const loading = r?.isLoading === true;
          const arr = readArr();
          if (!loading && arr !== null) {
            console.log(
              `[unwrap] resolved after ${Date.now() - start}ms with ${arr.length} items`,
            );
            return arr;
          }
          if (Date.now() - lastLog > 1000) {
            console.log(
              `[unwrap] still waiting: isLoading=${loading}, instances=${Array.isArray(r?.instances) ? r.instances.length : 'n/a'}, value=${Array.isArray(r?.value) ? r.value.length : 'n/a'}, keys=[${r && typeof r === 'object' ? Object.keys(r).join(',') : typeof r}]`,
            );
            lastLog = Date.now();
          }
          await new Promise((res) => setTimeout(res, 100));
        }
        // Final attempt: return whatever's there even if isLoading=true
        const finalArr = readArr();
        if (finalArr !== null) {
          console.warn(
            `[unwrap] timeout after ${maxWaitMs}ms but found ${finalArr.length} items, returning anyway`,
          );
          return finalArr;
        }
        console.warn(
          `[unwrap] timeout after ${maxWaitMs}ms; resource keys: ${r && typeof r === 'object' ? Object.keys(r).join(',') : typeof r}`,
        );
      } catch (e) {
        console.error('[Manager] unwrapCardsResource failed', e);
      }
      return [];
    }

    // ─── Load student list from hero-classroom (one-time, on mount) ───
    async loadStudents() {
      this.studentsLoading = true;
      this.studentsError = null;
      try {
        const getCards = this.hostGetCards;
        if (!getCards) {
          throw new Error(
            'host getCards helper unavailable on args.context — open this card in isolated format from the main UI',
          );
        }

        const resource = getCards(
          this,
          () => ({
            filter: {
              type: {
                module: `${HERO_CLASSROOM_REALM}student`,
                name: 'Student',
              },
            },
          }),
          () => [HERO_CLASSROOM_REALM],
        );

        const arr = await this.unwrapCardsResource(resource);

        this.students = arr.map((s: any) => {
          const slug = String(s?.id ?? '').split('/').pop() ?? '';
          const first = s?.firstName ?? '';
          const last = s?.lastName ?? '';
          const display = `${first} ${last}`.trim() || slug;
          const grade = s?.gradeLevel?.value ?? s?.gradeLevel ?? '';
          return { slug, displayName: display, grade: String(grade) };
        });

        this.students.sort((a, b) =>
          a.displayName.localeCompare(b.displayName),
        );
        console.log(
          `[Manager] loaded ${this.students.length} students from hero-classroom`,
        );
      } catch (e: any) {
        console.error('[Manager] failed to load students', e);
        this.studentsError = e?.message ?? String(e);
      } finally {
        this.studentsLoading = false;
      }
    }

    // ─── Load SkillCards from parent-daily (filter: daily-communication + active) ───
    async loadSkillCards() {
      this.skillCardsLoading = true;
      try {
        const getCards = this.hostGetCards;
        if (!getCards) {
          console.warn('[Manager] getCards unavailable, cannot load skill cards');
          return;
        }
        const resource = getCards(
          this,
          () => ({
            filter: {
              type: {
                module: `${new URL('./skill-card', import.meta.url).href}`,
                name: 'SkillCard',
              },
            },
          }),
        );
        const arr = await this.unwrapCardsResource(resource);
        const opts: SkillCardOption[] = arr
          .filter(
            (c: any) =>
              String(c?.category ?? '') === 'daily-communication' &&
              c?.isActive === true,
          )
          .map((c: any) => ({
            card: c,
            id: String(c?.id ?? ''),
            name: String(c?.name ?? ''),
            version: String(c?.version ?? ''),
            isActive: Boolean(c?.isActive),
          }));
        this.skillCards = opts;
        if (opts.length > 0 && !this.selectedSkillCardId) {
          this.selectedSkillCardId = opts[0].id;
        }
        console.log(`[Manager] loaded ${opts.length} active daily-communication SkillCards`);
      } catch (e: any) {
        console.error('[Manager] failed to load skill cards', e);
      } finally {
        this.skillCardsLoading = false;
      }
    }

    handleSkillCardChange = (event: Event) => {
      this.selectedSkillCardId = (event.target as HTMLSelectElement).value;
    };

    // ─── Phase 3: Generate Daily Communication via AI ───
    handleGenerate = async () => {
      this.generateState = 'running';
      this.generateMessage = null;
      this.generateError = null;
      this.lastGeneratedCardId = null;
      this.lastGeneratedLatencyMs = null;

      try {
        if (!this.previewSnapshot) {
          throw new Error('Select a snapshot first (click one from the list)');
        }
        const selectedSkill = this.skillCards.find(
          (s) => s.id === this.selectedSkillCardId,
        );
        if (!selectedSkill) {
          throw new Error('No SkillCard selected');
        }

        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');

        const realmHref = new URL('./', import.meta.url).href;

        const result = await generateDailyCommunication({
          snapshotCard: this.previewSnapshot,
          skillCard: selectedSkill.card,
          commandContext: ctx,
          realmHref,
        });

        this.generateState = 'success';
        this.generateMessage = `Generated via ${result.model} in ${result.latencyMs}ms`;
        this.lastGeneratedCardId = result.savedCardId;
        this.lastGeneratedLatencyMs = result.latencyMs;
      } catch (e: any) {
        console.error('[Manager] generate failed', e);
        this.generateState = 'error';
        this.generateError = e?.message ?? String(e);
      }
    };

    // ─── UI handlers ───
    handleStudentChange = (event: Event) => {
      this.selectedSlug = (event.target as HTMLSelectElement).value;
    };

    handleDateChange = (event: Event) => {
      this.selectedDate = (event.target as HTMLInputElement).value;
    };

    selectPreview = (snap: any) => {
      this.previewSnapshot = snap;
    };

    // ═══════════════════════════════════════════════════════
    //  BATCH: Generate DC for ALL today's snapshots
    // ═══════════════════════════════════════════════════════
    handleBatchDC = async () => {
      this.batchDCState = 'running';
      this.batchDCMessage = 'Starting...';
      this.batchDCError = null;
      try {
        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');

        const dcSkill = this.skillCards.find((s: any) => s.id === this.selectedSkillCardId);
        if (!dcSkill) throw new Error('No active daily-communication SkillCard selected');

        const snapshots = this.args.model?.snapshots ?? [];
        const todaySnapshots = snapshots.filter((s: any) => {
          try {
            const dt = new Date(s.snapshotDate); return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}` === this.selectedDate;
          } catch (_) { return false; }
        });

        if (todaySnapshots.length === 0) throw new Error(`No snapshots found for ${this.selectedDate}. Fetch first.`);

        const realmHref = new URL('./', import.meta.url).href;
        let created = 0;
        let failed = 0;
        const total = todaySnapshots.length;

        for (let i = 0; i < todaySnapshots.length; i++) {
          const snap = todaySnapshots[i];
          const name = snap.studentName || snap.studentSlug || '?';
          this.batchDCMessage = `Generating DC ${i + 1}/${total}: ${name}...`;
          try {
            await generateDailyCommunication({
              snapshotCard: snap,
              skillCard: dcSkill.card,
              commandContext: ctx,
              realmHref,
            });
            created++;
          } catch (e: any) {
            console.warn(`[Batch DC] failed for ${name}:`, e);
            failed++;
          }
        }

        this.batchDCState = 'success';
        this.batchDCMessage = `Generated ${created} of ${total} Daily Communications${failed > 0 ? ` (${failed} failed)` : ''}`;
      } catch (e: any) {
        this.batchDCState = 'error';
        this.batchDCError = e?.message ?? String(e);
      }
    };

    // ═══════════════════════════════════════════════════════
    //  BATCH: Generate Parent Summary for ALL today's DCs
    // ═══════════════════════════════════════════════════════
    handleBatchPS = async () => {
      this.batchPSState = 'running';
      this.batchPSMessage = 'Starting...';
      this.batchPSError = null;
      try {
        const ctx = this.hostCommandContext;
        if (!ctx) throw new Error('commandContext unavailable');

        // Load parent-summary SkillCards
        const getCards = this.hostGetCards;
        if (!getCards) throw new Error('getCards unavailable');
        const skillRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./skill-card', import.meta.url).href}`, name: 'SkillCard' } },
        }));
        const allSkills = await this.unwrapCardsResource(skillRes);
        const psSkill = allSkills.find(
          (c: any) => String(c?.category ?? '') === 'parent-summary' && c?.isActive === true,
        );
        if (!psSkill) throw new Error('No active parent-summary SkillCard found');

        // Load all DailyCommunication cards
        const dcRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./daily-communication', import.meta.url).href}`, name: 'DailyCommunication' } },
        }));
        const allDCs = await this.unwrapCardsResource(dcRes);

        // Filter to today's DCs
        const todayDCs = allDCs.filter((dc: any) => {
          try {
            const dt = new Date(dc.snapshotDate); return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}` === this.selectedDate;
          } catch (_) { return false; }
        });

        if (todayDCs.length === 0) throw new Error(`No Daily Communications found for ${this.selectedDate}. Generate DCs first.`);

        const realmHref = new URL('./', import.meta.url).href;
        let created = 0;
        let failed = 0;
        const total = todayDCs.length;

        for (let i = 0; i < todayDCs.length; i++) {
          const dc = todayDCs[i];
          const name = dc.studentName || dc.studentSlug || '?';
          this.batchPSMessage = `Generating PS ${i + 1}/${total}: ${name}...`;
          try {
            await generateParentSummary({
              dailyCommCard: dc,
              skillCard: psSkill,
              commandContext: ctx,
              realmHref,
            });
            created++;
          } catch (e: any) {
            console.warn(`[Batch PS] failed for ${name}:`, e);
            failed++;
          }
        }

        this.batchPSState = 'success';
        this.batchPSMessage = `Generated ${created} of ${total} Parent Summaries${failed > 0 ? ` (${failed} failed)` : ''}`;
      } catch (e: any) {
        this.batchPSState = 'error';
        this.batchPSError = e?.message ?? String(e);
      }
    };

    <template>
      <div class='mgr-root'>
        <a class='mgr-back' href={{this.dashboardUrl}}>← Back to Dashboard</a>
        <header class='mgr-header'>
          <h1>{{@model.title}}</h1>
          <p class='subtitle'>
            Developer back-office tool for fetching raw observation snapshots from
            hero-classroom into parent-daily. Customer never sees this. Phase 3
            (Daily Communication) and Phase 4 (Parent Daily Summary) are the
            customer-facing cards.
          </p>
        </header>

        {{! ── FETCH FORM ── }}
        <section class='card form-card'>
          <h2>Fetch a snapshot</h2>

          <div class='field-row'>
            <label>Student</label>
            {{#if this.studentsLoading}}
              <span class='note'>Loading students from hero-classroom...</span>
            {{else if this.studentsError}}
              <span class='error-inline'>Failed: {{this.studentsError}}</span>
            {{else}}
              <select {{on 'change' this.handleStudentChange}}>
                {{#each this.students as |s|}}
                  <option value={{s.slug}} selected={{eq s.slug this.selectedSlug}}>
                    {{s.displayName}}
                    {{#if s.grade}}({{s.grade}}){{/if}}
                  </option>
                {{/each}}
              </select>
            {{/if}}
          </div>

          <div class='field-row'>
            <label>Date</label>
            <input
              type='date'
              value={{this.selectedDate}}
              {{on 'change' this.handleDateChange}}
            />
          </div>

          <div class='banner info'>
            <strong>Fetch moved to Classroom Dashboard</strong>
            <div class='id-line'>Use "⇪ Publish Snapshot" button in Classroom (push-based, Approach C).</div>
          </div>
        </section>

        {{! ── EXISTING SNAPSHOTS LIST ── }}
        <section class='card'>
          <h2>Existing snapshots in parent-daily ({{@model.snapshots.length}})</h2>
          {{#if @model.snapshots.length}}
            <ul class='snap-list'>
              {{#each @model.snapshots as |snap|}}
                <li>
                  <button
                    type='button'
                    class='snap-btn {{if (eq this.previewSnapshot snap) "active"}}'
                    {{on 'click' (fn this.selectPreview snap)}}
                  >
                    <span class='mono'>{{snap.snapshotDate}}</span>
                    <span class='snap-name'>{{snap.studentName}}</span>
                    <span class='count-pill'>{{snap.entryCount}} entries</span>
                  </button>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p class='empty'>No snapshots yet. Fetch one above.</p>
          {{/if}}
        </section>

        {{! ── PREVIEW PANEL ── }}
        {{#if this.previewSnapshot}}
          <section class='card'>
            <h2>Preview: rawMarkdown (computed)</h2>
            <p class='note'>
              This is what the Phase 3 AI translator will read. Single
              file, single read - no per-entry fetches.
            </p>
            <pre class='markdown-box'>{{this.previewSnapshot.rawMarkdown}}</pre>
          </section>

          {{! ── PHASE 3: AI GENERATE TRIGGER ── }}
          <section class='card generate-card'>
            <h2>Generate Daily Communication (Phase 3 - AI)</h2>
            <p class='note'>
              Calls Gemini with the selected SkillCard playbook + the snapshot's
              rawMarkdown above. One AI call. Creates a new DailyCommunication
              card in parent-daily.
            </p>

            <div class='field-row'>
              <label>Playbook</label>
              {{#if this.skillCardsLoading}}
                <span class='note'>Loading SkillCards...</span>
              {{else if (eq this.skillCards.length 0)}}
                <span class='error-inline'>
                  No active daily-communication SkillCard found. Check
                  SkillCard/daily-communication-generator.json exists and
                  isActive is true.
                </span>
              {{else}}
                <select {{on 'change' this.handleSkillCardChange}}>
                  {{#each this.skillCards as |sc|}}
                    <option value={{sc.id}} selected={{eq sc.id this.selectedSkillCardId}}>
                      {{sc.name}} ({{sc.version}})
                    </option>
                  {{/each}}
                </select>
              {{/if}}
            </div>

            <div class='btn-row'>
              <button
                type='button'
                class='generate-btn'
                disabled={{eq this.generateState 'running'}}
                {{on 'click' this.handleGenerate}}
              >
                {{#if (eq this.generateState 'running')}}
                  Generating...
                {{else}}
                  ✨ Generate ONE DC
                {{/if}}
              </button>

              <button
                type='button'
                class='generate-btn batch-btn-dc'
                disabled={{eq this.batchDCState 'running'}}
                {{on 'click' this.handleBatchDC}}
              >
                {{#if (eq this.batchDCState 'running')}}
                  {{this.batchDCMessage}}
                {{else}}
                  ⚡ Generate ALL DCs
                {{/if}}
              </button>
            </div>

            {{#if (eq this.batchDCState 'success')}}
              <div class='banner success'>
                <strong>BATCH DC</strong> {{this.batchDCMessage}}
              </div>
            {{/if}}
            {{#if (eq this.batchDCState 'error')}}
              <div class='banner error'>
                <strong>BATCH DC ERROR</strong>
                <pre>{{this.batchDCError}}</pre>
              </div>
            {{/if}}

            {{#if (eq this.generateState 'success')}}
              <div class='banner success'>
                <strong>SUCCESS</strong> {{this.generateMessage}}
                {{#if this.lastGeneratedCardId}}
                  <div class='id-line'>
                    <a href={{this.lastGeneratedCardId}} target='_blank' rel='noopener'>
                      Open generated DailyCommunication →
                    </a>
                  </div>
                {{/if}}
              </div>
            {{/if}}

            {{#if (eq this.generateState 'error')}}
              <div class='banner error'>
                <strong>ERROR</strong>
                <pre>{{this.generateError}}</pre>
              </div>
            {{/if}}
          </section>

          {{! ── BATCH: Generate Parent Summaries ── }}
          <section class='card generate-card ps-card'>
            <h2>Generate Parent Summaries (batch)</h2>
            <p class='note'>
              Takes all today's Daily Communications and generates a Parent
              Summary for each one. Runs sequentially (one AI call per DC).
            </p>

            <button
              type='button'
              class='generate-btn batch-btn-ps'
              disabled={{eq this.batchPSState 'running'}}
              {{on 'click' this.handleBatchPS}}
            >
              {{#if (eq this.batchPSState 'running')}}
                {{this.batchPSMessage}}
              {{else}}
                ⚡ Generate ALL Parent Summaries
              {{/if}}
            </button>

            {{#if (eq this.batchPSState 'success')}}
              <div class='banner success'>
                <strong>BATCH PS</strong> {{this.batchPSMessage}}
              </div>
            {{/if}}
            {{#if (eq this.batchPSState 'error')}}
              <div class='banner error'>
                <strong>BATCH PS ERROR</strong>
                <pre>{{this.batchPSError}}</pre>
              </div>
            {{/if}}
          </section>
        {{/if}}
      </div>

      <style scoped>
        .mgr-root {
          padding: 24px;
          max-width: 980px;
          margin: 0 auto;
          font-family: system-ui, sans-serif;
          color: #1a202c;
        }
        .mgr-back {
          display: inline-block;
          padding: 8px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          color: #4a5568;
          font-size: 12px;
          font-weight: 600;
          text-decoration: none;
          margin-bottom: 16px;
        }
        .mgr-back:hover {
          background: #faf8f6;
          border-color: #2a9d8f;
          color: #2a9d8f;
        }
        .mgr-header h1 {
          margin: 0 0 8px;
          color: #2c5282;
          font-size: 22px;
        }
        .subtitle {
          margin: 0 0 24px;
          color: #718096;
          font-size: 13px;
          line-height: 1.5;
        }
        .card {
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 16px;
        }
        .card h2 {
          margin: 0 0 12px;
          font-size: 14px;
          font-weight: 600;
          text-transform: uppercase;
          color: #4a5568;
          letter-spacing: 0.5px;
        }
        .form-card { background: #f7fafc; }
        .btn-row {
          display: flex;
          gap: 10px;
          flex-wrap: wrap;
        }
        .batch-btn {
          background: #7c5fc4 !important;
        }
        .batch-btn:not(:disabled):hover { background: #633fa8 !important; }
        .batch-btn-dc {
          background: #7c5fc4 !important;
        }
        .batch-btn-dc:not(:disabled):hover { background: #633fa8 !important; }
        .batch-btn-ps {
          background: #e05d50;
        }
        .batch-btn-ps:not(:disabled):hover { background: #c74a3e; }
        .ps-card { background: #fdf0ee; border-color: #e05d50; }
        .ps-card h2 { color: #9a2d1f; }
        .generate-card { background: #f0fff4; border-color: #68d391; }
        .generate-card h2 { color: #22543d; }
        .generate-btn {
          margin-top: 8px;
          padding: 10px 24px;
          background: #2a9d8f;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
        }
        .generate-btn:disabled { background: #cbd5e0; cursor: wait; }
        .generate-btn:not(:disabled):hover { background: #238077; }
        .id-line a {
          color: #2b6cb0;
          text-decoration: none;
          font-weight: 600;
          font-family: ui-monospace, monospace;
          font-size: 12px;
        }
        .id-line a:hover { text-decoration: underline; }
        .field-row {
          display: flex;
          align-items: center;
          gap: 12px;
          margin-bottom: 12px;
        }
        .field-row label {
          font-size: 12px;
          font-weight: 600;
          text-transform: uppercase;
          color: #4a5568;
          width: 80px;
        }
        .field-row select,
        .field-row input[type='date'] {
          flex: 1;
          padding: 8px 12px;
          border: 1px solid #cbd5e0;
          border-radius: 6px;
          font-size: 14px;
          font-family: inherit;
          background: white;
        }
        .fetch-btn {
          margin-top: 8px;
          padding: 10px 24px;
          background: #319795;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
        }
        .fetch-btn:disabled { background: #cbd5e0; cursor: wait; }
        .fetch-btn:not(:disabled):hover { background: #2c7a7b; }
        .banner {
          margin-top: 14px;
          padding: 12px 14px;
          border-radius: 6px;
          font-size: 13px;
        }
        .banner.success {
          background: #f0fff4;
          border: 1px solid #38a169;
          color: #22543d;
        }
        .banner.error {
          background: #fff5f5;
          border: 1px solid #e53e3e;
          color: #742a2a;
        }
        .banner pre {
          margin: 8px 0 0;
          font-family: ui-monospace, monospace;
          font-size: 11px;
          white-space: pre-wrap;
          word-break: break-word;
        }
        .id-line {
          font-family: ui-monospace, monospace;
          font-size: 11px;
          color: #4a5568;
          margin-top: 4px;
        }
        .snap-list {
          list-style: none;
          padding: 0;
          margin: 0;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .snap-btn {
          width: 100%;
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 6px;
          cursor: pointer;
          font-family: inherit;
          font-size: 13px;
          text-align: left;
        }
        .snap-btn:hover { background: #edf2f7; }
        .snap-btn.active {
          background: #ebf8ff;
          border-color: #3182ce;
        }
        .mono { font-family: ui-monospace, monospace; color: #718096; }
        .snap-name { font-weight: 600; color: #2d3748; flex: 1; }
        .count-pill {
          font-size: 11px;
          padding: 2px 10px;
          background: #edf2f7;
          border-radius: 999px;
          color: #4a5568;
        }
        .empty {
          color: #a0aec0;
          font-style: italic;
          font-size: 13px;
          margin: 0;
        }
        .note {
          color: #718096;
          font-size: 12px;
          margin: 0 0 8px;
        }
        .error-inline { color: #c53030; font-size: 12px; }
        .markdown-box {
          background: #1a202c;
          color: #e2e8f0;
          padding: 16px;
          border-radius: 6px;
          font-family: ui-monospace, monospace;
          font-size: 12px;
          line-height: 1.6;
          white-space: pre-wrap;
          word-break: break-word;
          max-height: 600px;
          overflow-y: auto;
          margin: 0;
        }
      </style>
    </template>
  };
}
