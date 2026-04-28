// Phase 5 - TribecaPrepDashboard (hub-and-spoke main entry)
//
// Customer's "one entry point" requirement. This is the single card the
// head teacher opens to see everything and navigate to everything else.
//
// Architecture: hub-and-spoke
//   - Dashboard is the hub. It shows:
//     * 3 sections: Snapshots, Daily Communications, Parent Summaries
//     * Each section has a control bar (date, student, action button)
//   - Each list uses query-backed linksToMany so Boxel auto-populates it
//     whenever a new card of that type is saved in parent-daily.
//   - Clicking a card uses <a href={{card.id}}> which Boxel's host routes
//     to "open in stack".

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
import { eq } from '@cardstack/boxel-ui/helpers';

import { ImportSnapshot } from './import-snapshot';
import { DailyCommunication, generateDailyCommunication } from './daily-communication';
import { ParentDailySummary, generateParentSummary } from './parent-daily-summary';
import { SkillCard } from './skill-card';
import type { FrozenEntry } from './import-snapshot';

const HERO_CLASSROOM_REALM = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';

export class TribecaPrepDashboard extends CardDef {
  static displayName = 'Tribeca Prep Dashboard';
  static prefersWideFormat = true;

  // ---- Query-backed collections ----
  @field parentSummaries = linksToMany(() => ParentDailySummary, {
    query: {
      filter: {
        type: {
          module: `${new URL('./parent-daily-summary', import.meta.url).href}`,
          name: 'ParentDailySummary',
        },
      },
    },
  });

  @field dailyCommunications = linksToMany(() => DailyCommunication, {
    query: {
      filter: {
        type: {
          module: `${new URL('./daily-communication', import.meta.url).href}`,
          name: 'DailyCommunication',
        },
      },
    },
  });

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

  // ---- Computed ----
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TribecaPrepDashboard) {
      return 'Tribeca Prep Dashboard';
    },
  });

  // ---- Isolated view ----
  static isolated = class Isolated extends Component<typeof TribecaPrepDashboard> {
    // Pagination page size (items per page)
    PAGE_SIZE = 5;

    // ---- Search + pagination state (one set per section) ----
    @tracked psSearch = '';
    @tracked psPage = 0;

    @tracked dcSearch = '';
    @tracked dcPage = 0;

    @tracked snapSearch = '';
    @tracked snapPage = 0;

    // ---- Control bar state ----
    // Section 1: Snapshots
    @tracked snapDate = '';
    @tracked snapStudent = 'all';

    // Section 2: Daily Communications
    @tracked dcDate = '';
    @tracked dcStudent = 'all';

    // Section 3: Parent Summaries
    @tracked psDate = '';
    @tracked psStudent = 'all';

    // Students loaded from hero-classroom
    @tracked students: Array<{slug: string, displayName: string, grade: string}> = [];
    @tracked studentsLoading = true;

    // ── Batch states ──
    @tracked batchFetchState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchFetchMsg: string | null = null;
    @tracked batchDCState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchDCMsg: string | null = null;
    @tracked batchPSState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked batchPSMsg: string | null = null;

    constructor(owner: any, args: any) {
      super(owner, args);
      const now = new Date();
      const today = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
      this.snapDate = today;
      this.dcDate = today;
      this.psDate = today;
      this.loadStudents();
    }

    // ---- Load students from hero-classroom ----
    async loadStudents() {
      this.studentsLoading = true;
      try {
        const getCards = this.hostGetCards;
        if (!getCards) {
          console.warn('[Dashboard] host getCards unavailable, cannot load students');
          this.studentsLoading = false;
          return;
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

        const arr = await this.unwrapResource(resource);

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
        console.log(`[Dashboard] loaded ${this.students.length} students from hero-classroom`);
      } catch (e) {
        console.warn('[Dashboard] loadStudents error:', e);
      }
      this.studentsLoading = false;
    }

    // ---- Handlers ----
    handlePsSearch = (e: Event) => {
      this.psSearch = (e.target as HTMLInputElement).value;
      this.psPage = 0;
    };
    handlePsPrev = () => { if (this.psPage > 0) this.psPage--; };
    handlePsNext = () => { if (this.psPage + 1 < this.psPageCount) this.psPage++; };

    handleDcSearch = (e: Event) => {
      this.dcSearch = (e.target as HTMLInputElement).value;
      this.dcPage = 0;
    };
    handleDcPrev = () => { if (this.dcPage > 0) this.dcPage--; };
    handleDcNext = () => { if (this.dcPage + 1 < this.dcPageCount) this.dcPage++; };

    handleSnapSearch = (e: Event) => {
      this.snapSearch = (e.target as HTMLInputElement).value;
      this.snapPage = 0;
    };
    handleSnapPrev = () => { if (this.snapPage > 0) this.snapPage--; };
    handleSnapNext = () => { if (this.snapPage + 1 < this.snapPageCount) this.snapPage++; };

    // ---- Control bar handlers ----
    handleSnapDateChange = (e: Event) => { this.snapDate = (e.target as HTMLInputElement).value; };
    handleSnapStudentChange = (e: Event) => { this.snapStudent = (e.target as HTMLSelectElement).value; };
    handleDcDateChange = (e: Event) => { this.dcDate = (e.target as HTMLInputElement).value; };
    handleDcStudentChange = (e: Event) => { this.dcStudent = (e.target as HTMLSelectElement).value; };
    handlePsDateChange = (e: Event) => { this.psDate = (e.target as HTMLInputElement).value; };
    handlePsStudentChange = (e: Event) => { this.psStudent = (e.target as HTMLSelectElement).value; };

    // ---- Filter helper ----
    matchesSearch = (
      studentName: any,
      date: any,
      greeting: any,
      summary: any,
      q: string,
    ): boolean => {
      if (!q) return true;
      const needle = q.trim().toLowerCase();
      if (!needle) return true;
      const nameStr = String(studentName ?? '').toLowerCase();
      const greetStr = String(greeting ?? '').toLowerCase();
      const summaryStr = String(summary ?? '').toLowerCase();
      let dateStr = '';
      try {
        if (date) {
          const d = new Date(date);
          dateStr = d
            .toLocaleDateString('en-US', {
              weekday: 'long',
              year: 'numeric',
              month: 'long',
              day: 'numeric',
            })
            .toLowerCase();
          // also include ISO yyyy-mm-dd
          dateStr += ` ${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
        }
      } catch (_) { /* ignore */ }
      return (
        nameStr.includes(needle) ||
        greetStr.includes(needle) ||
        summaryStr.includes(needle) ||
        dateStr.includes(needle)
      );
    };

    // ---- Parent Summaries: filtered + paginated ----
    get psFiltered() {
      const all = this.args.model?.parentSummaries ?? [];
      return all.filter((p: any) =>
        this.matchesSearch(p?.studentName, p?.summaryDate, p?.greeting, '', this.psSearch),
      );
    }
    get psPageCount() {
      return Math.max(1, Math.ceil(this.psFiltered.length / this.PAGE_SIZE));
    }
    get psCurrentPage() {
      const start = this.psPage * this.PAGE_SIZE;
      return this.psFiltered.slice(start, start + this.PAGE_SIZE);
    }
    get psShowPagination() { return this.psFiltered.length > this.PAGE_SIZE; }
    get psPageDisplay() { return this.psPage + 1; }
    get psIsLastPage() { return this.psPage + 1 >= this.psPageCount; }

    // ---- Daily Communications: filtered + paginated ----
    get dcFiltered() {
      const all = this.args.model?.dailyCommunications ?? [];
      return all.filter((d: any) =>
        this.matchesSearch(d?.studentName, d?.snapshotDate, '', d?.daySummary, this.dcSearch),
      );
    }
    get dcPageCount() {
      return Math.max(1, Math.ceil(this.dcFiltered.length / this.PAGE_SIZE));
    }
    get dcCurrentPage() {
      const start = this.dcPage * this.PAGE_SIZE;
      return this.dcFiltered.slice(start, start + this.PAGE_SIZE);
    }
    get dcShowPagination() { return this.dcFiltered.length > this.PAGE_SIZE; }
    get dcPageDisplay() { return this.dcPage + 1; }
    get dcIsLastPage() { return this.dcPage + 1 >= this.dcPageCount; }

    // ---- Snapshots: filtered + paginated ----
    get snapFiltered() {
      const all = this.args.model?.snapshots ?? [];
      return all.filter((s: any) =>
        this.matchesSearch(s?.studentName, s?.snapshotDate, '', '', this.snapSearch),
      );
    }
    get snapPageCount() {
      return Math.max(1, Math.ceil(this.snapFiltered.length / this.PAGE_SIZE));
    }
    get snapCurrentPage() {
      const start = this.snapPage * this.PAGE_SIZE;
      return this.snapFiltered.slice(start, start + this.PAGE_SIZE);
    }
    get snapShowPagination() { return this.snapFiltered.length > this.PAGE_SIZE; }
    get snapPageDisplay() { return this.snapPage + 1; }
    get snapIsLastPage() { return this.snapPage + 1 >= this.snapPageCount; }

    get hostGetCards(): any {
      const a = this.args as any;
      return a.context?.getCards ?? a.context?.actions?.getCards ?? null;
    }
    get hostCommandContext(): any {
      const a = this.args as any;
      return a.context?.commandContext ?? a.context?.actions?.commandContext ?? null;
    }
    async unwrapResource(r: any, maxMs = 10000): Promise<any[]> {
      try {
        if (Array.isArray(r)) return r;
        const read = () => Array.isArray(r?.instances) ? r.instances : (Array.isArray(r?.value) ? r.value : null);
        const t0 = Date.now();
        let seen = false;
        while (Date.now() - t0 < maxMs) {
          if (r?.isLoading) seen = true;
          const arr = read();
          if (!r?.isLoading && arr !== null) {
            if (arr.length > 0 || seen || Date.now() - t0 > 1500) return arr;
          }
          await new Promise(res => setTimeout(res, 100));
        }
        return read() ?? [];
      } catch (_) { return []; }
    }

    // ── Helper: format date to ISO yyyy-mm-dd ──
    toISO = (d: any): string => {
      try {
        const dt = new Date(d);
        return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`;
      } catch (_) { return ''; }
    };

    // ── Batch Fetch with 3-rule logic ──
    handleBatchFetch = async () => {
      this.batchFetchState = 'running';
      this.batchFetchMsg = 'Loading students...';
      try {
        const getCards = this.hostGetCards;
        const ctx = this.hostCommandContext;
        if (!getCards || !ctx) throw new Error('Context unavailable');

        const targetDate = this.snapDate;
        if (!targetDate) throw new Error('Please select a date');

        // Determine which students to fetch
        let studentsToFetch: Array<{slug: string, displayName: string, grade: string}> = [];
        if (this.snapStudent === 'all') {
          if (this.students.length === 0) {
            // Fallback: load from hero-classroom directly
            const studRes = getCards(this, () => ({
              filter: { type: { module: `${HERO_CLASSROOM_REALM}student`, name: 'Student' } },
            }), () => [HERO_CLASSROOM_REALM]);
            const rawStudents = await this.unwrapResource(studRes);
            studentsToFetch = rawStudents.map((s: any) => {
              const slug = String(s?.id ?? '').split('/').pop() ?? '';
              const first = s?.firstName ?? '';
              const last = s?.lastName ?? '';
              const display = `${first} ${last}`.trim() || slug;
              const grade = String(s?.gradeLevel?.value ?? s?.gradeLevel ?? '');
              return { slug, displayName: display, grade };
            });
          } else {
            studentsToFetch = this.students;
          }
        } else {
          const found = this.students.find(s => s.slug === this.snapStudent);
          if (found) {
            studentsToFetch = [found];
          } else {
            studentsToFetch = [{ slug: this.snapStudent, displayName: this.snapStudent, grade: '' }];
          }
        }

        if (studentsToFetch.length === 0) throw new Error('No students found');

        this.batchFetchMsg = `Loading activity entries...`;

        // Load hero-classroom activity entries
        const entRes = getCards(this, () => ({
          filter: { type: { module: `${HERO_CLASSROOM_REALM}activity-entry`, name: 'ActivityEntry' } },
        }), () => [HERO_CLASSROOM_REALM]);
        const allEntries = await this.unwrapResource(entRes);

        // Load hero-classroom daily plans
        const planRes = getCards(this, () => ({
          filter: { type: { module: `${HERO_CLASSROOM_REALM}daily-plan`, name: 'DailyPlan' } },
        }), () => [HERO_CLASSROOM_REALM]);
        const allPlans = await this.unwrapResource(planRes);

        // Load hero-classroom learning goals
        const goalRes = getCards(this, () => ({
          filter: { type: { module: `${HERO_CLASSROOM_REALM}learning-goal`, name: 'LearningGoal' } },
        }), () => [HERO_CLASSROOM_REALM]);
        const allGoals = await this.unwrapResource(goalRes);

        // Load hero-classroom staff
        const staffRes = getCards(this, () => ({
          filter: { type: { module: `${HERO_CLASSROOM_REALM}staff`, name: 'Staff' } },
        }), () => [HERO_CLASSROOM_REALM]);
        const allStaff = await this.unwrapResource(staffRes);
        const headTeacher = allStaff.find((s: any) => String(s?.role?.value ?? s?.role ?? '').includes('Lead') || String(s?.role?.value ?? s?.role ?? '').includes('Head'));
        const teacherName = headTeacher ? String(headTeacher?.name ?? '') : (allStaff[0] ? String(allStaff[0]?.name ?? '') : '');

        // Build Map index of existing snapshots: "date|studentSlug" -> snapshotCard
        const existingSnaps = this.args.model?.snapshots ?? [];
        const snapIndex = new Map<string, any>();
        for (const snap of existingSnaps) {
          const snapDateStr = this.toISO(snap?.snapshotDate);
          const snapSlug = String(snap?.studentSlug ?? '');
          if (snapDateStr && snapSlug) {
            snapIndex.set(`${snapDateStr}|${snapSlug}`, snap);
          }
        }

        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmHref = new URL('./', import.meta.url).href;
        const dateObj = new Date(targetDate + 'T00:00:00');

        let created = 0;
        let updated = 0;
        let skipped = 0;

        for (let i = 0; i < studentsToFetch.length; i++) {
          const stu = studentsToFetch[i];
          const slug = stu.slug;
          const name = stu.displayName;
          this.batchFetchMsg = `Fetching ${i + 1}/${studentsToFetch.length}: ${name}...`;

          const matching = allEntries.filter((e: any) => String(e?.student?.id ?? '').split('/').pop() === slug);
          const frozen: FrozenEntry[] = matching.map((e: any) => ({
            id: String(e?.id ?? ''), content: String(e?.content ?? ''),
            entryType: String(e?.entryType ?? ''), timestamp: e?.timestamp ? new Date(e.timestamp).toISOString() : '',
            score: String(e?.score ?? ''), domain: String(e?.domain ?? ''),
            reasoning: String(e?.reasoning ?? ''), matchedBlock: String(e?.matchedBlock ?? ''),
            suggestedGoal: String(e?.suggestedGoal ?? ''), flagNote: String(e?.flagNote ?? ''),
            flagSeverity: String(e?.flagSeverity ?? ''),
            authorName: String(e?.author?.id ?? '').split('/').pop() ?? '',
            studentSlug: slug,
          }));

          // Find plan for target date
          const studentPlan = allPlans.find((p: any) => {
            const pStudentId = String(p?.student?.id ?? '');
            // Match by slug (last segment of ID)
            if (String(pStudentId).split('/').pop() !== slug) {
              // Also try full ID match
              const fullId = `${HERO_CLASSROOM_REALM}Student/${slug}`;
              if (pStudentId !== fullId) return false;
            }
            try {
              const pDate = this.toISO(p?.planDate);
              return pDate === targetDate;
            } catch (_) { return false; }
          });
          const scheduleItems = (studentPlan?.scheduleItems ?? []).map((item: any) => ({
            time: String(item?.time ?? ''),
            activity: String(item?.activity ?? ''),
            status: typeof item?.status === 'object' ? (item.status?.value ?? '') : String(item?.status ?? ''),
            result: String(item?.result ?? ''),
            goalTag: String(item?.goalTag ?? ''),
          }));

          // Find active goals for this student
          const studentGoals = allGoals
            .filter((g: any) => {
              const gStudentId = String(g?.student?.id ?? '');
              return gStudentId.split('/').pop() === slug;
            })
            .map((g: any) => ({
              goalTitle: String(g?.goalTitle ?? ''),
              domain: String(g?.domain?.value ?? g?.domain ?? ''),
              targetMastery: g?.targetMastery ?? 80,
              progressPercent: g?.progressPercent ?? 0,
              description: String(g?.description ?? ''),
            }));

          // 3-rule logic
          const key = `${targetDate}|${slug}`;
          const existing = snapIndex.get(key);

          if (existing) {
            // Rule 2: same entryCount -> SKIP
            if (existing.entryCount === frozen.length) {
              skipped++;
              continue;
            }
            // Rule 3: different data -> UPDATE (overwrite existing card)
            try {
              existing.entryCount = frozen.length;
              existing.entriesJson = JSON.stringify(frozen, null, 2);
              existing.scheduleJson = JSON.stringify(scheduleItems, null, 2);
              existing.goalsJson = JSON.stringify(studentGoals, null, 2);
              existing.teacherName = teacherName;
              (existing as any).fetchedAt = new Date();
              await new SaveCardCommand(ctx).execute({ card: existing, realm: realmHref });
              updated++;
            } catch (e) { console.warn('[Dashboard batch fetch update]', e); }
          } else {
            // Rule 1: no existing -> CREATE
            try {
              const snap = new ImportSnapshot();
              snap.studentSlug = slug; snap.studentName = name;
              snap.studentGrade = stu.grade;
              (snap as any).snapshotDate = dateObj;
              snap.sourceRealm = HERO_CLASSROOM_REALM;
              (snap as any).fetchedAt = new Date();
              snap.entryCount = frozen.length;
              snap.entriesJson = JSON.stringify(frozen, null, 2);
              snap.scheduleJson = JSON.stringify(scheduleItems, null, 2);
              snap.goalsJson = JSON.stringify(studentGoals, null, 2);
              snap.teacherName = teacherName;
              await new SaveCardCommand(ctx).execute({ card: snap, realm: realmHref });
              created++;
            } catch (e) { console.warn('[Dashboard batch fetch create]', e); }
          }
        }
        this.batchFetchState = 'success';
        this.batchFetchMsg = `Done: ${created} new, ${updated} updated, ${skipped} unchanged`;
      } catch (e: any) {
        this.batchFetchState = 'error';
        this.batchFetchMsg = e?.message ?? String(e);
      }
    };

    // ── Batch Generate DCs ──
    handleBatchDC = async () => {
      this.batchDCState = 'running';
      this.batchDCMsg = 'Loading SkillCards...';
      try {
        const getCards = this.hostGetCards;
        const ctx = this.hostCommandContext;
        if (!getCards || !ctx) throw new Error('Context unavailable');

        const targetDate = this.dcDate;
        if (!targetDate) throw new Error('Please select a date');

        const skillRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./skill-card', import.meta.url).href}`, name: 'SkillCard' } },
        }));
        const skills = await this.unwrapResource(skillRes);
        const dcSkill = skills.find((c: any) => String(c?.category ?? '') === 'daily-communication' && c?.isActive);
        if (!dcSkill) throw new Error('No active daily-communication SkillCard');

        // Filter snapshots by selected date AND student
        const snapshots = (this.args.model?.snapshots ?? []).filter((s: any) => {
          try {
            const snapDateStr = this.toISO(s.snapshotDate);
            if (snapDateStr !== targetDate) return false;
            if (this.dcStudent !== 'all') {
              const slug = String(s?.studentSlug ?? '');
              if (slug !== this.dcStudent) return false;
            }
            return true;
          } catch (_) { return false; }
        });
        if (snapshots.length === 0) throw new Error(`No snapshots for ${targetDate}${this.dcStudent !== 'all' ? ' / ' + this.dcStudent : ''}. Fetch first.`);

        const realmHref = new URL('./', import.meta.url).href;
        let created = 0;
        for (let i = 0; i < snapshots.length; i++) {
          const snap = snapshots[i];
          this.batchDCMsg = `Generating DC ${i + 1}/${snapshots.length}: ${snap.studentName || '?'}...`;
          try {
            await generateDailyCommunication({ snapshotCard: snap, skillCard: dcSkill, commandContext: ctx, realmHref });
            created++;
          } catch (e) { console.warn('[Dashboard batch DC]', e); }
        }
        this.batchDCState = 'success';
        this.batchDCMsg = `Generated ${created} of ${snapshots.length} DCs`;
      } catch (e: any) {
        this.batchDCState = 'error';
        this.batchDCMsg = e?.message ?? String(e);
      }
    };

    // ── Batch Generate Parent Summaries ──
    handleBatchPS = async () => {
      this.batchPSState = 'running';
      this.batchPSMsg = 'Loading SkillCards...';
      try {
        const getCards = this.hostGetCards;
        const ctx = this.hostCommandContext;
        if (!getCards || !ctx) throw new Error('Context unavailable');

        const targetDate = this.psDate;
        if (!targetDate) throw new Error('Please select a date');

        const skillRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./skill-card', import.meta.url).href}`, name: 'SkillCard' } },
        }));
        const skills = await this.unwrapResource(skillRes);
        const psSkill = skills.find((c: any) => String(c?.category ?? '') === 'parent-summary' && c?.isActive);
        if (!psSkill) throw new Error('No active parent-summary SkillCard');

        // Filter DCs by selected date AND student
        const dcs = (this.args.model?.dailyCommunications ?? []).filter((dc: any) => {
          try {
            const dcDateStr = this.toISO(dc.snapshotDate);
            if (dcDateStr !== targetDate) return false;
            if (this.psStudent !== 'all') {
              const slug = String(dc?.studentSlug ?? dc?.studentName ?? '').toLowerCase().replace(/\s+/g, '-');
              if (slug !== this.psStudent && String(dc?.studentSlug ?? '') !== this.psStudent) return false;
            }
            return true;
          } catch (_) { return false; }
        });
        if (dcs.length === 0) throw new Error(`No DCs for ${targetDate}${this.psStudent !== 'all' ? ' / ' + this.psStudent : ''}. Generate DCs first.`);

        const realmHref = new URL('./', import.meta.url).href;
        let created = 0;
        for (let i = 0; i < dcs.length; i++) {
          const dc = dcs[i];
          this.batchPSMsg = `Generating PS ${i + 1}/${dcs.length}: ${dc.studentName || '?'}...`;
          try {
            await generateParentSummary({ dailyCommCard: dc, skillCard: psSkill, commandContext: ctx, realmHref });
            created++;
          } catch (e) { console.warn('[Dashboard batch PS]', e); }
        }
        this.batchPSState = 'success';
        this.batchPSMsg = `Generated ${created} of ${dcs.length} Parent Summaries`;
      } catch (e: any) {
        this.batchPSState = 'error';
        this.batchPSMsg = e?.message ?? String(e);
      }
    };

    get todayString() {
      return new Date().toLocaleDateString('en-US', {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });
    }

    get snapshotsCount() {
      return this.args.model?.snapshots?.length ?? 0;
    }
    get dcCount() {
      return this.args.model?.dailyCommunications?.length ?? 0;
    }
    get psCount() {
      return this.args.model?.parentSummaries?.length ?? 0;
    }

    get sentCount() {
      const pss = this.args.model?.parentSummaries ?? [];
      let sent = 0;
      for (const p of pss) {
        if (String(p?.status ?? '') === 'sent') sent++;
      }
      return sent;
    }

    get draftCount() {
      return this.psCount - this.sentCount;
    }

    // ---- Helpers ----
    displayName = (raw: string | undefined | null): string => {
      const s = String(raw ?? '').trim();
      if (!s) return 'Student';
      if (!/\s/.test(s) && s.includes('-')) {
        return s
          .split('-')
          .map((w) => (w ? w.charAt(0).toUpperCase() + w.slice(1) : ''))
          .join(' ');
      }
      return s;
    };

    formatDate = (d: any): string => {
      if (!d) return '';
      try {
        return new Date(d).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
        });
      } catch (_) {
        return String(d);
      }
    };

    <template>
      <div class='tpd-root'>
        {{! ---- HEADER ---- }}
        <header class='tpd-header'>
          <div class='tpd-brand'>
            <div class='tpd-logo'>
              <svg width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'>
                <path d='M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'/>
              </svg>
            </div>
            <div class='tpd-brand-text'>
              <h1 class='tpd-title'>Tribeca Prep</h1>
              <p class='tpd-subtitle'>Daily Communication Dashboard</p>
            </div>
            <a class='tpd-classroom-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/Classroom/classroom-2a'>
              ← Classroom
            </a>
          </div>
          <div class='tpd-today'>
            <span class='tpd-today-label'>Today</span>
            <span class='tpd-today-date'>{{this.todayString}}</span>
          </div>
        </header>

        {{! ---- STATS ROW ---- }}
        <div class='tpd-stats'>
          <div class='tpd-stat'>
            <span class='tpd-stat-num'>{{this.snapshotsCount}}</span>
            <span class='tpd-stat-label'>Snapshots</span>
          </div>
          <div class='tpd-stat'>
            <span class='tpd-stat-num'>{{this.dcCount}}</span>
            <span class='tpd-stat-label'>Daily Comms</span>
          </div>
          <div class='tpd-stat'>
            <span class='tpd-stat-num'>{{this.psCount}}</span>
            <span class='tpd-stat-label'>Parent Summaries</span>
          </div>
          <div class='tpd-stat tpd-stat-draft'>
            <span class='tpd-stat-num'>{{this.draftCount}}</span>
            <span class='tpd-stat-label'>Drafts</span>
          </div>
          <div class='tpd-stat tpd-stat-sent'>
            <span class='tpd-stat-num'>{{this.sentCount}}</span>
            <span class='tpd-stat-label'>Sent</span>
          </div>
        </div>

        {{! ---- SECTION 1: SNAPSHOTS ---- }}
        <section class='tpd-section'>
          <div class='tpd-section-header'>
            <h2 class='tpd-section-title'>
              <span class='tpd-section-badge tpd-badge-snap'>1</span>
              Snapshots
            </h2>
            <span class='tpd-section-sub'>
              {{this.snapFiltered.length}} of {{@model.snapshots.length}}
            </span>
          </div>

          <div class='tpd-control-bar'>
            <label>
              Date:
              <input
                type='date'
                value={{this.snapDate}}
                {{on 'input' this.handleSnapDateChange}}
              />
            </label>
            <label>
              Student:
              <select
                value={{this.snapStudent}}
                {{on 'change' this.handleSnapStudentChange}}
              >
                <option value='all'>All Students</option>
                {{#each this.students as |stu|}}
                  <option value={{stu.slug}}>{{stu.displayName}} ({{stu.grade}})</option>
                {{/each}}
              </select>
            </label>
            <button
              type='button'
              class='tpd-control-btn fetch'
              disabled={{eq this.batchFetchState 'running'}}
              {{on 'click' this.handleBatchFetch}}
            >{{if (eq this.batchFetchState 'running') 'Fetching...' 'Fetch'}}</button>
            {{#if this.batchFetchMsg}}
              <span class='tpd-control-msg {{if (eq this.batchFetchState "success") "success" (if (eq this.batchFetchState "error") "error" "")}}'>
                {{this.batchFetchMsg}}
              </span>
            {{/if}}
          </div>

          <div class='tpd-search'>
            <svg class='tpd-search-icon' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'>
              <circle cx='11' cy='11' r='8'/><path d='M21 21l-4.35-4.35'/>
            </svg>
            <input
              type='text'
              class='tpd-search-input'
              placeholder='Search by name or date (e.g. "jamie", "apr 8")'
              value={{this.snapSearch}}
              {{on 'input' this.handleSnapSearch}}
            />
          </div>

          {{#if this.snapCurrentPage.length}}
            <div class='tpd-card-list'>
              {{#each this.snapCurrentPage as |snap|}}
                <a class='tpd-card tpd-card-snap' href={{snap.id}}>
                  <div class='tpd-card-body'>
                    <div class='tpd-snap-row'>
                      <span class='tpd-snap-date'>{{this.formatDate snap.snapshotDate}}</span>
                      <span class='tpd-card-name small'>
                        {{this.displayName snap.studentName}}
                      </span>
                    </div>
                  </div>
                  <div class='tpd-card-right'>
                    <span class='tpd-count-pill'>{{snap.entryCount}} entries</span>
                  </div>
                </a>
              {{/each}}
            </div>

            {{#if this.snapShowPagination}}
              <div class='tpd-pagination'>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{eq this.snapPage 0}}
                  {{on 'click' this.handleSnapPrev}}
                >← Prev</button>
                <span class='tpd-page-info'>
                  Page {{this.snapPageDisplay}} of {{this.snapPageCount}}
                </span>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{this.snapIsLastPage}}
                  {{on 'click' this.handleSnapNext}}
                >Next →</button>
              </div>
            {{/if}}
          {{else if @model.snapshots.length}}
            <p class='tpd-empty'>No results for "{{this.snapSearch}}".</p>
          {{else}}
            <p class='tpd-empty'>
              No snapshots yet. Use the Fetch button above to pull data from hero-classroom.
            </p>
          {{/if}}
        </section>

        {{! ---- SECTION 2: DAILY COMMUNICATIONS ---- }}
        <section class='tpd-section'>
          <div class='tpd-section-header'>
            <h2 class='tpd-section-title'>
              <span class='tpd-section-badge tpd-badge-dc'>2</span>
              Daily Communications
            </h2>
            <span class='tpd-section-sub'>
              {{this.dcFiltered.length}} of {{@model.dailyCommunications.length}}
            </span>
          </div>

          <div class='tpd-control-bar'>
            <label>
              Date:
              <input
                type='date'
                value={{this.dcDate}}
                {{on 'input' this.handleDcDateChange}}
              />
            </label>
            <label>
              Student:
              <select
                value={{this.dcStudent}}
                {{on 'change' this.handleDcStudentChange}}
              >
                <option value='all'>All Students</option>
                {{#each this.students as |stu|}}
                  <option value={{stu.slug}}>{{stu.displayName}} ({{stu.grade}})</option>
                {{/each}}
              </select>
            </label>
            <button
              type='button'
              class='tpd-control-btn generate'
              disabled={{eq this.batchDCState 'running'}}
              {{on 'click' this.handleBatchDC}}
            >{{if (eq this.batchDCState 'running') 'Generating...' 'Generate'}}</button>
            {{#if this.batchDCMsg}}
              <span class='tpd-control-msg {{if (eq this.batchDCState "success") "success" (if (eq this.batchDCState "error") "error" "")}}'>
                {{this.batchDCMsg}}
              </span>
            {{/if}}
          </div>

          <div class='tpd-search'>
            <svg class='tpd-search-icon' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'>
              <circle cx='11' cy='11' r='8'/><path d='M21 21l-4.35-4.35'/>
            </svg>
            <input
              type='text'
              class='tpd-search-input'
              placeholder='Search by name or date (e.g. "jamie", "apr 8")'
              value={{this.dcSearch}}
              {{on 'input' this.handleDcSearch}}
            />
          </div>

          {{#if this.dcCurrentPage.length}}
            <div class='tpd-card-list'>
              {{#each this.dcCurrentPage as |dc|}}
                <a class='tpd-card tpd-card-dc' href={{dc.id}}>
                  <div class='tpd-card-left'>
                    <div class='tpd-dc-avatar'>
                      <svg width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'>
                        <circle cx='12' cy='8' r='4'/>
                        <path d='M4 21c0-4 4-7 8-7s8 3 8 7'/>
                      </svg>
                    </div>
                  </div>
                  <div class='tpd-card-body'>
                    <div class='tpd-card-name'>
                      {{this.displayName dc.studentName}}
                      <span class='tpd-card-date'>{{this.formatDate dc.snapshotDate}}</span>
                    </div>
                    <div class='tpd-card-summary'>{{dc.daySummary}}</div>
                  </div>
                  <div class='tpd-card-right'>
                    <span class='tpd-mood-chip'>{{dc.myDayWas}}</span>
                    <span class='tpd-status tpd-status-{{dc.status}}'>{{dc.status}}</span>
                  </div>
                </a>
              {{/each}}
            </div>

            {{#if this.dcShowPagination}}
              <div class='tpd-pagination'>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{eq this.dcPage 0}}
                  {{on 'click' this.handleDcPrev}}
                >← Prev</button>
                <span class='tpd-page-info'>
                  Page {{this.dcPageDisplay}} of {{this.dcPageCount}}
                </span>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{this.dcIsLastPage}}
                  {{on 'click' this.handleDcNext}}
                >Next →</button>
              </div>
            {{/if}}
          {{else if @model.dailyCommunications.length}}
            <p class='tpd-empty'>No results for "{{this.dcSearch}}".</p>
          {{else}}
            <p class='tpd-empty'>
              No daily communications yet. Fetch snapshots first, then generate.
            </p>
          {{/if}}
        </section>

        {{! ---- SECTION 3: PARENT SUMMARIES ---- }}
        <section class='tpd-section'>
          <div class='tpd-section-header'>
            <h2 class='tpd-section-title'>
              <span class='tpd-section-badge tpd-badge-ps'>3</span>
              Parent Summaries
            </h2>
            <span class='tpd-section-sub'>
              {{this.psFiltered.length}} of {{@model.parentSummaries.length}}
            </span>
          </div>

          <div class='tpd-control-bar'>
            <label>
              Date:
              <input
                type='date'
                value={{this.psDate}}
                {{on 'input' this.handlePsDateChange}}
              />
            </label>
            <label>
              Student:
              <select
                value={{this.psStudent}}
                {{on 'change' this.handlePsStudentChange}}
              >
                <option value='all'>All Students</option>
                {{#each this.students as |stu|}}
                  <option value={{stu.slug}}>{{stu.displayName}} ({{stu.grade}})</option>
                {{/each}}
              </select>
            </label>
            <button
              type='button'
              class='tpd-control-btn generate'
              disabled={{eq this.batchPSState 'running'}}
              {{on 'click' this.handleBatchPS}}
            >{{if (eq this.batchPSState 'running') 'Generating...' 'Generate'}}</button>
            {{#if this.batchPSMsg}}
              <span class='tpd-control-msg {{if (eq this.batchPSState "success") "success" (if (eq this.batchPSState "error") "error" "")}}'>
                {{this.batchPSMsg}}
              </span>
            {{/if}}
          </div>

          <div class='tpd-search'>
            <svg class='tpd-search-icon' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'>
              <circle cx='11' cy='11' r='8'/><path d='M21 21l-4.35-4.35'/>
            </svg>
            <input
              type='text'
              class='tpd-search-input'
              placeholder='Search by name or date (e.g. "jamie", "apr 8")'
              value={{this.psSearch}}
              {{on 'input' this.handlePsSearch}}
            />
          </div>

          {{#if this.psCurrentPage.length}}
            <div class='tpd-card-list'>
              {{#each this.psCurrentPage as |ps|}}
                <a class='tpd-card tpd-card-ps' href={{ps.id}}>
                  <div class='tpd-card-left'>
                    <div class='tpd-mood'>{{ps.moodEmoji}}</div>
                  </div>
                  <div class='tpd-card-body'>
                    <div class='tpd-card-name'>
                      {{this.displayName ps.studentName}}
                    </div>
                    <div class='tpd-card-meta'>
                      <span class='tpd-card-greeting'>{{ps.greeting}}</span>
                      <span class='tpd-card-date'>{{this.formatDate ps.summaryDate}}</span>
                    </div>
                  </div>
                  <div class='tpd-card-right'>
                    <span class='tpd-status tpd-status-{{ps.status}}'>{{ps.status}}</span>
                  </div>
                </a>
              {{/each}}
            </div>

            {{#if this.psShowPagination}}
              <div class='tpd-pagination'>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{eq this.psPage 0}}
                  {{on 'click' this.handlePsPrev}}
                >← Prev</button>
                <span class='tpd-page-info'>
                  Page {{this.psPageDisplay}} of {{this.psPageCount}}
                </span>
                <button
                  type='button'
                  class='tpd-page-btn'
                  disabled={{this.psIsLastPage}}
                  {{on 'click' this.handlePsNext}}
                >Next →</button>
              </div>
            {{/if}}
          {{else if @model.parentSummaries.length}}
            <p class='tpd-empty'>No results for "{{this.psSearch}}".</p>
          {{else}}
            <p class='tpd-empty'>
              No parent summaries yet. Generate DCs first, then generate summaries.
            </p>
          {{/if}}
        </section>

        <footer class='tpd-footer'>
          <p>
            This dashboard is a hub. All navigation opens individual cards in
            the Boxel stack, so you can return here with the back arrow.
          </p>
        </footer>
      </div>

      <style scoped>
        .tpd-root {
          max-width: 900px;
          margin: 0 auto;
          padding: 32px;
          background: #faf8f6;
          font-family: system-ui, -apple-system, sans-serif;
          color: #1a1816;
          min-height: 100%;
        }

        /* ---- Header ---- */
        .tpd-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding-bottom: 20px;
          margin-bottom: 20px;
          border-bottom: 2px solid #e05d50;
        }
        .tpd-brand {
          display: flex;
          align-items: center;
          gap: 14px;
        }
        .tpd-logo {
          width: 44px;
          height: 44px;
          background: #e05d50;
          color: white;
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .tpd-title {
          margin: 0 0 2px;
          font-size: 22px;
          font-weight: 700;
          color: #1a1816;
          letter-spacing: -0.3px;
        }
        .tpd-classroom-link {
          font-size: 12px;
          color: #e05d50;
          text-decoration: none;
          padding: 4px 10px;
          border: 1px solid #e05d50;
          border-radius: 6px;
          margin-left: 12px;
          font-weight: 600;
          white-space: nowrap;
        }
        .tpd-classroom-link:hover {
          background: #e05d50;
          color: white;
        }
        .tpd-subtitle {
          margin: 0;
          font-size: 12px;
          color: #8a8279;
          letter-spacing: 0.3px;
        }
        .tpd-today {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 2px;
        }
        .tpd-today-label {
          font-size: 10px;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.6px;
          font-weight: 700;
        }
        .tpd-today-date {
          font-size: 14px;
          color: #1a1816;
          font-weight: 600;
        }

        /* ---- Stats ---- */
        .tpd-stats {
          display: grid;
          grid-template-columns: repeat(5, 1fr);
          gap: 10px;
          margin-bottom: 28px;
        }
        .tpd-stat {
          background: white;
          border-radius: 10px;
          padding: 14px 16px;
          display: flex;
          flex-direction: column;
          gap: 4px;
          box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
          border: 1px solid #f5f2ef;
        }
        .tpd-stat-num {
          font-size: 24px;
          font-weight: 800;
          color: #1a1816;
          line-height: 1;
        }
        .tpd-stat-label {
          font-size: 11px;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          font-weight: 600;
        }
        .tpd-stat-draft .tpd-stat-num { color: #c08b30; }
        .tpd-stat-sent .tpd-stat-num { color: #2a9d8f; }

        /* ---- Sections ---- */
        .tpd-section { margin-bottom: 28px; }
        .tpd-section-header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          margin-bottom: 12px;
        }
        .tpd-section-title {
          display: flex;
          align-items: center;
          gap: 10px;
          margin: 0;
          font-size: 15px;
          font-weight: 700;
          color: #1a1816;
        }
        .tpd-section-badge {
          width: 22px;
          height: 22px;
          border-radius: 50%;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          font-size: 11px;
          font-weight: 700;
          color: white;
        }
        .tpd-badge-snap { background: #8a8279; }
        .tpd-badge-dc { background: #7c5fc4; }
        .tpd-badge-ps { background: #e05d50; }
        .tpd-section-sub {
          font-size: 11px;
          color: #8a8279;
          letter-spacing: 0.3px;
        }

        /* ---- Control bar ---- */
        .tpd-control-bar {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.75rem 1rem;
          background: #faf8f6;
          border: 1px solid rgba(0,0,0,0.08);
          border-radius: 8px;
          margin-bottom: 0.5rem;
          flex-wrap: wrap;
        }
        .tpd-control-bar label {
          font-size: 0.6875rem;
          font-weight: 600;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .tpd-control-bar input,
        .tpd-control-bar select {
          font-family: inherit;
          font-size: 0.8125rem;
          padding: 0.375rem 0.5rem;
          border: 1px solid rgba(0,0,0,0.12);
          border-radius: 6px;
          background: white;
        }
        .tpd-control-btn {
          font-family: inherit;
          font-size: 0.75rem;
          font-weight: 600;
          padding: 0.5rem 1rem;
          border: none;
          border-radius: 6px;
          cursor: pointer;
          color: white;
        }
        .tpd-control-btn.fetch { background: #e05d50; }
        .tpd-control-btn.generate { background: #2a9d8f; }
        .tpd-control-btn:disabled { opacity: 0.5; cursor: wait; }
        .tpd-control-msg {
          font-size: 0.6875rem;
          color: #8a8279;
          margin-left: auto;
        }
        .tpd-control-msg.success { color: #2a9d8f; }
        .tpd-control-msg.error { color: #e05d50; }

        /* ---- Batch buttons on section headers (legacy, kept for compat) ---- */
        .tpd-batch-btn {
          margin-left: auto;
          padding: 4px 12px;
          border: none;
          border-radius: 6px;
          font-size: 11px;
          font-weight: 700;
          cursor: pointer;
          font-family: inherit;
          color: white;
        }
        .tpd-batch-btn:disabled { opacity: 0.6; cursor: wait; }
        .tpd-batch-ps { background: #e05d50; }
        .tpd-batch-ps:not(:disabled):hover { background: #c74a3e; }
        .tpd-batch-dc { background: #7c5fc4; }
        .tpd-batch-dc:not(:disabled):hover { background: #633fa8; }
        .tpd-batch-snap { background: #718096; }
        .tpd-batch-snap:not(:disabled):hover { background: #5c6978; }
        .tpd-batch-ok {
          color: #2a9d8f;
          font-weight: 600;
          font-size: 11px;
          margin-left: 8px;
        }
        .tpd-batch-err {
          color: #e05d50;
          font-size: 11px;
          margin-left: 8px;
        }

        /* ---- Search input ---- */
        .tpd-search {
          position: relative;
          margin-bottom: 12px;
        }
        .tpd-search-icon {
          position: absolute;
          top: 50%;
          left: 12px;
          transform: translateY(-50%);
          color: #a0aec0;
          pointer-events: none;
        }
        .tpd-search-input {
          width: 100%;
          padding: 10px 14px 10px 34px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          font-family: inherit;
          font-size: 13px;
          color: #1a1816;
          box-sizing: border-box;
        }
        .tpd-search-input:focus {
          outline: none;
          border-color: #2a9d8f;
          box-shadow: 0 0 0 3px rgba(42, 157, 143, 0.1);
        }
        .tpd-search-input::placeholder { color: #a0aec0; }

        /* ---- Pagination ---- */
        .tpd-pagination {
          display: flex;
          justify-content: center;
          align-items: center;
          gap: 14px;
          margin-top: 14px;
          padding: 10px 0;
        }
        .tpd-page-btn {
          padding: 8px 16px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 6px;
          font-family: inherit;
          font-size: 12px;
          font-weight: 600;
          color: #4a5568;
          cursor: pointer;
        }
        .tpd-page-btn:not(:disabled):hover {
          background: #faf8f6;
          border-color: #2a9d8f;
          color: #2a9d8f;
        }
        .tpd-page-btn:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }
        .tpd-page-info {
          font-size: 12px;
          color: #5c5650;
          font-weight: 600;
          font-family: ui-monospace, monospace;
        }

        /* ---- Card lists ---- */
        .tpd-card-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .tpd-card {
          display: flex;
          align-items: center;
          gap: 14px;
          padding: 12px 16px;
          background: white;
          border: 1px solid #f5f2ef;
          border-radius: 10px;
          text-decoration: none;
          color: #1a1816;
          transition: border-color 0.12s, transform 0.12s;
        }
        .tpd-card:hover {
          border-color: #e2e8f0;
          transform: translateX(2px);
        }
        .tpd-card-left { flex-shrink: 0; }
        .tpd-mood {
          font-size: 26px;
          width: 44px;
          height: 44px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: #fef5e7;
          border-radius: 10px;
        }
        .tpd-dc-avatar {
          width: 40px;
          height: 40px;
          background: #2a9d8f;
          color: white;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .tpd-card-body {
          flex: 1;
          min-width: 0;
        }
        .tpd-card-name {
          font-size: 14px;
          font-weight: 700;
          color: #1a1816;
          margin-bottom: 2px;
          display: flex;
          align-items: baseline;
          gap: 10px;
        }
        .tpd-card-name.small { font-size: 13px; font-weight: 600; }
        .tpd-card-meta {
          display: flex;
          gap: 10px;
          align-items: baseline;
          font-size: 12px;
          color: #5c5650;
        }
        .tpd-card-greeting { font-weight: 600; color: #c08b30; }
        .tpd-card-date { color: #a0aec0; font-family: ui-monospace, monospace; font-size: 11px; }
        .tpd-card-summary {
          font-size: 12px;
          color: #5c5650;
          line-height: 1.4;
          overflow: hidden;
          text-overflow: ellipsis;
          display: -webkit-box;
          -webkit-line-clamp: 1;
          -webkit-box-orient: vertical;
        }
        .tpd-card-right {
          display: flex;
          align-items: center;
          gap: 8px;
          flex-shrink: 0;
        }
        .tpd-status {
          font-size: 10px;
          padding: 3px 9px;
          border-radius: 999px;
          text-transform: uppercase;
          font-weight: 700;
          letter-spacing: 0.5px;
        }
        .tpd-status-draft { background: #fef5e7; color: #975a16; }
        .tpd-status-reviewed { background: #ebf8ff; color: #2c5282; }
        .tpd-status-sent { background: #f0fff4; color: #22543d; }
        .tpd-mood-chip {
          font-size: 11px;
          color: #2a9d8f;
          font-weight: 600;
          background: #e8f6f4;
          padding: 3px 9px;
          border-radius: 999px;
        }

        .tpd-snap-row {
          display: flex;
          align-items: baseline;
          gap: 12px;
        }
        .tpd-snap-date {
          font-family: ui-monospace, monospace;
          font-size: 12px;
          color: #8a8279;
        }
        .tpd-count-pill {
          font-size: 11px;
          padding: 3px 9px;
          background: #faf8f6;
          border-radius: 999px;
          color: #5c5650;
          font-weight: 600;
        }

        .tpd-empty {
          padding: 20px;
          text-align: center;
          color: #a0aec0;
          font-size: 13px;
          font-style: italic;
          background: white;
          border: 1px dashed #e2e8f0;
          border-radius: 10px;
          margin: 0;
        }

        .tpd-footer {
          margin-top: 32px;
          padding-top: 20px;
          border-top: 1px solid #f5f2ef;
        }
        .tpd-footer p {
          margin: 0;
          font-size: 11px;
          color: #a0aec0;
          text-align: center;
          line-height: 1.5;
        }
      </style>
    </template>
  };

  // Minimal embedded view
  static embedded = class Embedded extends Component<typeof TribecaPrepDashboard> {
    <template>
      <div class='tpd-embed'>
        <strong>Tribeca Prep Dashboard</strong>
        <span class='tpd-embed-desc'>Single entry point for daily communications workflow.</span>
      </div>
      <style scoped>
        .tpd-embed {
          padding: 14px 16px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          font-family: system-ui, sans-serif;
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .tpd-embed strong { color: #1a1816; font-size: 14px; }
        .tpd-embed-desc { font-size: 12px; color: #8a8279; }
      </style>
    </template>
  };
}
