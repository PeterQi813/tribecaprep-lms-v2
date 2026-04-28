// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  field,
  contains,
  containsMany,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { StaffMember } from './staff-member';
import { ObservationRecord } from './observation-record';
import { ProgramRecord } from './program-record';
import { ScheduleCard } from './schedule-card';
import { LearningGoal } from './learning-goal';
import { syncStaffToClassroom, deleteStaffFromClassroom } from './sync-staff-to-classroom';
import { syncProgramsToClassroom } from './sync-programs-to-classroom';

class StudentRef extends CardDef {
  static displayName = 'Student Reference';
  @field name = contains(StringField);
  @field initials = contains(StringField);
  @field iepGoal = contains(StringField);
}
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { restartableTask } from 'ember-concurrency';
import {
  AnalyzeStaffCommand,
  CreateStaffCommand,
  CreateLearningGoalCommand,
} from './create-staff-command';

export class AdminDashboard extends CardDef {
  static displayName = 'Admin Dashboard';
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field realmName = contains(StringField);
  @field staff = linksToMany(() => StaffMember);
  @field observations = containsMany(ObservationRecord);
  @field programs = linksToMany(() => ProgramRecord);
  @field scheduleCards = containsMany(ScheduleCard);
  @field studentRefs = containsMany(StudentRef);
  @field learningGoals = linksToMany(() => LearningGoal);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AdminDashboard) {
      return this.title || 'Admin Dashboard';
    },
  });

  // Isolated view — Staff Directory + Observation Data Grid
  static isolated = class Isolated extends Component<typeof this> {
    // ── Host-injected helpers ──
    get hostGetCards(): any {
      const a = this.args as any;
      const ctx = a.context;
      return ctx?.getCards ?? ctx?.actions?.getCards ?? ctx?.cardContext?.getCards ?? null;
    }
    get hostCommandContext(): any {
      const a = this.args as any;
      return a.context?.commandContext ?? a.context?.actions?.commandContext ?? null;
    }
    async unwrapResource(resource: any, maxMs = 10000): Promise<any[]> {
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
    }

    // ── Dynamic staff loading via getCards ──
    @tracked dynamicStaff: any[] = [];
    @tracked staffLoaded = false;

    constructor(owner: any, args: any) {
      super(owner, args);
      this.loadStaff();
      this.loadGoals();
      this.loadLocalProfiles();
      this.loadObservations();
      this.loadPrograms();
    }

    // Load persisted ObservationRecord cards from admin realm
    async loadObservations() {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      try {
        const obsModule = new URL('./observation-record', import.meta.url).href;
        const res = getCards(this, () => ({
          filter: { type: { module: obsModule, name: 'ObservationRecord' } },
        }));
        const obs = await this.unwrapResource(res, 15000);
        // Put into localRows for the existing table UI
        this.localRows = obs.map((o: any) => ({
          date: o.date ?? '',
          studentName: o.studentName ?? '',
          category: o.category ?? '',
          linkedGoal: o.linkedGoal ?? '',
          score: o.score ?? '',
          staffInitials: o.staffInitials ?? '??',
          staffColor: o.staffColor ?? 'teal',
          flagged: o.flagged ?? 'false',
          notes: o.notes ?? '',
        }));
        this._obsTick++;
        console.log(`[Admin] loaded ${obs.length} observations from realm`);
      } catch (e) {
        console.warn('[Admin] loadObservations failed:', e);
      }
    }

    async loadPrograms() {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      try {
        const progModule = new URL('./program-record', import.meta.url).href;
        const res = getCards(this, () => ({
          filter: { type: { module: progModule, name: 'ProgramRecord' } },
        }));
        this.dynamicPrograms = await this.unwrapResource(res, 15000);
        // Clear localPrograms to avoid duplicates with realm data
        if (this.dynamicPrograms.length > 0) this.localPrograms = [];
        console.log(`[Admin] loaded ${this.dynamicPrograms.length} programs from realm`);
      } catch (e) {
        console.warn('[Admin] loadPrograms failed:', e);
      }
    }

    async loadStaff() {
      const getCards = this.hostGetCards;
      if (!getCards) {
        console.warn('[Admin] getCards not available — staff will show from linksToMany only');
        this.staffLoaded = true;
        return;
      }
      try {
        const staffModule = new URL('./staff-member', import.meta.url).href;
        console.log(`[Admin] querying staff with module: ${staffModule}`);
        const res = getCards(this, () => ({
          filter: { type: { module: staffModule, name: 'StaffMember' } },
        }));
        this.dynamicStaff = await this.unwrapResource(res, 15000);
        console.log(`[Admin] loaded ${this.dynamicStaff.length} staff via getCards`);
      } catch (e) {
        console.warn('[Admin] loadStaff failed:', e);
      }
      this.staffLoaded = true;
    }

    // ── Local Student Full Profile mirror (pushed from HoS via Approach C) ──
    @tracked fetchedProfiles: any[] = [];

    async loadLocalProfiles() {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      try {
        // Read from admin's own realm (local copies created by fetch)
        const profModule = new URL('./student-full-profile', import.meta.url).href;
        const res = getCards(this, () => ({
          filter: { type: { module: profModule, name: 'StudentFullProfile' } },
        }));
        this.fetchedProfiles = await this.unwrapResource(res, 15000);
        console.log(`[Admin] loaded ${this.fetchedProfiles.length} local profiles`);
      } catch (e) {
        console.warn('[Admin] loadLocalProfiles failed:', e);
      }
    }

    get profileDisplayList() {
      return this.fetchedProfiles.map((p: any) => {
        const ident = p?.identity;
        const first = String(ident?.firstName ?? '');
        const last = String(ident?.lastName ?? '');
        const grade = typeof ident?.gradeLevel === 'object' ? (ident.gradeLevel?.value ?? '') : String(ident?.gradeLevel ?? '');
        return {
          displayName: `${first} ${last}`.trim() || 'Unknown',
          grade,
          studentId: String(ident?.studentId ?? ''),
        };
      });
    }

    // ── Fetch goal progress from classroom ──
    @tracked classroomGoals: any[] = [];
    @tracked classroomActivities: any[] = [];
    @tracked goalProgressFetchState: 'idle' | 'fetching' | 'success' | 'error' = 'idle';
    @tracked goalProgressFetchMsg = '';
    get isFetchingGoalProgress() { return this.goalProgressFetchState === 'fetching'; }

    // Strip AI-appended metadata " (Math, current: 0%, target: 66%)" from goal names
    _cleanGoalName(s: string): string {
      return String(s ?? '').replace(/\s*\([^)]*\)\s*$/, '').trim();
    }

    // Progress Map + Evidence Map keyed by "programTitle|studentName" (lowercase)
    // This isolates progress per student+program pair (same program for different students are independent)
    get _goalProgressMap(): Map<string, number> {
      const aggregate = new Map<string, { total: number; count: number }>();
      for (const obs of this.localRows) {
        const goalRaw = String(obs?.linkedGoal ?? '');
        const studentName = String(obs?.studentName ?? '').toLowerCase().trim();
        const goal = this._cleanGoalName(goalRaw).toLowerCase();
        const score = String(obs?.score ?? '');
        if (!goal || !studentName || !score || score === '\u2014') continue;
        const parts = score.split('/');
        const n = Number(parts[0]) || 0;
        const d = Number(parts[1]) || 0;
        if (d <= 0) continue;
        const key = `${goal}|${studentName}`;
        const p = aggregate.get(key) || { total: 0, count: 0 };
        p.total += (n / d) * 100;
        p.count++;
        aggregate.set(key, p);
      }
      const out = new Map<string, number>();
      for (const [k, v] of aggregate) out.set(k, Math.min(100, Math.round(v.total / v.count)));
      return out;
    }

    get _goalEvidenceMap(): Map<string, any[]> {
      const map = new Map<string, any[]>();
      for (const obs of this.localRows) {
        const goalRaw = String(obs?.linkedGoal ?? '');
        const studentName = String(obs?.studentName ?? '').toLowerCase().trim();
        const goal = this._cleanGoalName(goalRaw).toLowerCase();
        if (!goal || !studentName) continue;
        const key = `${goal}|${studentName}`;
        if (!map.has(key)) map.set(key, []);
        map.get(key)!.push({
          score: String(obs?.score ?? ''),
          text: String(obs?.notes ?? '').slice(0, 200),
          staff: String(obs?.staffInitials ?? ''),
          date: String(obs?.date ?? ''),
          studentName: String(obs?.studentName ?? ''),
        });
      }
      return map;
    }

    // Enriched goals: derived from ProgramRecord cards (Admin's source of truth) + ObservationRecord evidence
    get enrichedGoals(): any[] {
      const progressMap = this._goalProgressMap;
      const evidenceMap = this._goalEvidenceMap;
      const programs = this.dynamicPrograms.length > 0 ? this.dynamicPrograms : this.localPrograms;

      return programs.map((pg: any) => {
        const title = String(pg?.program ?? '');
        const studentName = String(pg?.studentName ?? '');
        const titleKey = this._cleanGoalName(title).toLowerCase();
        const studentKey = studentName.toLowerCase().trim();
        const key = `${titleKey}|${studentKey}`;
        const progress = progressMap.get(key) ?? 0;
        return {
          goalTitle: title,
          studentName: studentName,
          domain: String(pg?.domain ?? ''),
          priority: 'High',
          currentMastery: progress,
          targetMastery: Number(pg?.targetMastery ?? 80),
          progressPercent: progress,
          active: String(pg?.active ?? 'Yes'),
          evidence: evidenceMap.get(key) ?? [],
        };
      }).filter((g: any) => g.active !== 'No');
    }

    // ── Dynamic goals loading via getCards ──
    @tracked dynamicGoals: any[] = [];

    async loadGoals() {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      try {
        const goalModule = new URL('./learning-goal', import.meta.url).href;
        const res = getCards(this, () => ({
          filter: { type: { module: goalModule, name: 'LearningGoal' } },
        }));
        this.dynamicGoals = await this.unwrapResource(res, 15000);
        console.log(`[Admin] loaded ${this.dynamicGoals.length} goals via getCards`);
      } catch (e) {
        console.warn('[Admin] loadGoals failed:', e);
      }
    }

    @tracked showAddForm = false;
    @tracked newStudent = '';
    @tracked newCategory = 'Academic';
    @tracked newGoal = '';
    @tracked newScore = '';
    @tracked newStaffInitials = '';
    @tracked newStaffColor = 'teal';

    // Staff AI creation state
    @tracked showAddStaffForm = false;
    @tracked staffAiInput = '';
    @tracked staffAiState:
      | 'input'
      | 'analyzing'
      | 'preview'
      | 'saving'
      | 'error' = 'input';
    @tracked staffAiError = '';
    // Preview fields (editable after AI extraction)
    @tracked newMemberName = '';
    @tracked newMemberRole = 'Lead Teacher';
    @tracked newMemberInitials = '';
    @tracked newMemberColor = 'teal';
    @tracked newMemberStudents = '';
    @tracked newMemberObs = '';
    @tracked newMemberEmail = '';
    @tracked localStaffCards: Array<{
      name: string;
      role: string;
      initials: string;
      avatarColor: string;
      studentCount: string;
      weeklyObservations: string;
      status: string;
    }> = [];

    // New observation rows (local state — always works without realm model)
    @tracked localRows: Array<{
      date: string;
      studentName: string;
      category: string;
      linkedGoal: string;
      score: string;
      staffInitials: string;
      staffColor: string;
      flagged: string;
      notes: string;
    }> = [];

    // Flag overrides for model observations (keyed by model index)
    @tracked flagOverrides: Record<number, string> = {};

    // Staff inline edit state
    @tracked editingStaffIndex: number | null = null;
    @tracked editStaffValues: {
      name: string;
      role: string;
      initials: string;
      avatarColor: string;
      studentCount: string;
      weeklyObservations: string;
      status: string;
    } = {
      name: '',
      role: 'Lead Teacher',
      initials: '',
      avatarColor: 'teal',
      studentCount: '',
      weeklyObservations: '',
      status: 'Active',
    };

    // Search / filter / sort state
    @tracked searchQuery = '';
    @tracked activeTypeFilter = 'All';
    @tracked staffFilter = 'All Staff';
    @tracked sortCol = 'date';
    @tracked sortDir = 'desc';
    // Observation pagination
    @tracked obsPage = 0;
    obsPageSize = 8;

    // Manual push: Rebuild Classroom Staff (Approach C — covers Boxel-edit gap)
    @tracked rebuildStaffState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked rebuildStaffMsg: string | null = null;
    get isRebuildingStaff() { return this.rebuildStaffState === 'running'; }

    // Manual push: Rebuild Classroom Goals (from Programs)
    @tracked rebuildGoalsState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked rebuildGoalsMsg: string | null = null;
    get isRebuildingGoals() { return this.rebuildGoalsState === 'running'; }

    // Delete program state
    @tracked deletingProgramId = '';
    @tracked deleteProgramMsg = '';

    // Inline edit state
    @tracked editingRowKey: string | null = null;
    @tracked editValues: {
      studentName: string;
      category: string;
      linkedGoal: string;
      score: string;
      staffInitials: string;
      staffColor: string;
    } = {
      studentName: '',
      category: 'Academic',
      linkedGoal: '',
      score: '',
      staffInitials: '',
      staffColor: 'teal',
    };

    // Bulk select state
    @tracked selectedRowKeys: string[] = [];

    // Confirm dialog state
    @tracked confirmPending: { message: string; action: () => void } | null =
      null;

    // Reactivity invalidation counters — incremented after every model mutation
    @tracked _staffTick = 0;
    @tracked _obsTick = 0;

    // Weekly Schedule — derived from ProgramRecord.scheduledWeek
    // scheduledWeek: "0" = this week, "1" = next week, "2" = week 3, "3" or "" = backlog

    // Calculate the Monday of the current week
    get _currentMonday(): Date {
      const now = new Date();
      const day = now.getDay();
      const mon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (day === 0 ? 6 : day - 1));
      return mon;
    }

    // Parse a date string as local time
    _parseLocalDate(dateStr: string): Date | null {
      if (!dateStr) return null;
      const parts = dateStr.split(/[-\/]/);
      if (parts.length < 3) return null;
      const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
      return isNaN(d.getTime()) ? null : d;
    }

    // Check if a program is active during a specific week
    _isActiveInWeek(prog: any, weekCol: number): boolean {
      const started = this._parseLocalDate(prog.started);
      if (!started) return false;
      const mon = this._currentMonday;
      const weekStart = new Date(mon);
      weekStart.setDate(mon.getDate() + weekCol * 7);
      const weekEnd = new Date(weekStart);
      weekEnd.setDate(weekStart.getDate() + 6); // Sunday

      const dueDate = this._parseLocalDate(prog.dueDate ?? prog._srcCard?.dueDate ?? '');

      if (!dueDate) {
        // No dueDate: only show in the started week (old behavior)
        const diffDays = Math.round((started.getTime() - weekStart.getTime()) / (1000 * 60 * 60 * 24));
        return diffDays >= 0 && diffDays < 7;
      }

      // Has both dates: active if started <= weekEnd AND dueDate >= weekStart
      return started.getTime() <= weekEnd.getTime() && dueDate.getTime() >= weekStart.getTime();
    }

    // Check if a program should be in backlog
    _isBacklog(prog: any): boolean {
      const started = this._parseLocalDate(prog.started);
      if (!started) return true; // no date → backlog

      const dueDate = this._parseLocalDate(prog.dueDate ?? prog._srcCard?.dueDate ?? '');
      const mon = this._currentMonday;

      if (!dueDate) {
        // No dueDate: backlog if started is before this Monday
        return started.getTime() < mon.getTime();
      }

      // Has dueDate: backlog only if dueDate is before this Monday (expired)
      return dueDate.getTime() < mon.getTime();
    }

    // Given a week column, return the Monday date of that week
    _weekColToMonday(col: number): Date {
      const mon = new Date(this._currentMonday);
      mon.setDate(mon.getDate() + col * 7);
      return mon;
    }

    // Backlog pagination + search
    @tracked backlogPage = 0;
    @tracked backlogSearch = '';
    backlogPageSize = 4;

    setBacklogSearch = (e: Event) => {
      this.backlogSearch = (e.target as HTMLInputElement).value;
      this.backlogPage = 0;
    };
    nextBacklogPage = () => { this.backlogPage++; };
    prevBacklogPage = () => { if (this.backlogPage > 0) this.backlogPage--; };

    // Build a card object from a program record
    _toSchedCard(p: any): {
      id: string; name: string; domainKey: string; domainLabel: string;
      ablls: string; target: string; started: string; dueDate: string;
      muted: boolean; note: string; _srcCard: any;
    } {
      return {
        id: p.program || '',
        name: p.program || '',
        domainKey: p.domainKey || '',
        domainLabel: p.domain || '',
        ablls: p.abllsCode || '',
        target: p.currentTarget || '',
        started: p.started || '',
        dueDate: p.dueDate ?? p._srcCard?.dueDate ?? '',
        muted: p.active === 'No',
        note: (p.active === 'No') ? (p.notes || 'Discontinued') : (p.notes || ''),
        _srcCard: p._srcCard,
      };
    }

    get schedCol0() {
      return this.studentPrograms.filter((p: any) => this._isActiveInWeek(p, 0)).map((p: any) => this._toSchedCard(p));
    }
    get schedCol1() {
      return this.studentPrograms.filter((p: any) => this._isActiveInWeek(p, 1)).map((p: any) => this._toSchedCard(p));
    }
    get schedCol2() {
      return this.studentPrograms.filter((p: any) => this._isActiveInWeek(p, 2)).map((p: any) => this._toSchedCard(p));
    }

    // Backlog: expired (dueDate < this Monday) or no date
    get backlogAll() {
      return this.studentPrograms.filter((p: any) => this._isBacklog(p)).map((p: any) => this._toSchedCard(p));
    }
    get backlogFiltered() {
      const all = this.backlogAll;
      const q = this.backlogSearch.toLowerCase().trim();
      if (!q) return all;
      return all.filter((c) =>
        c.name.toLowerCase().includes(q) ||
        c.domainLabel.toLowerCase().includes(q) ||
        c.target.toLowerCase().includes(q) ||
        c.started.includes(q)
      );
    }
    get backlogPaged() {
      const start = this.backlogPage * this.backlogPageSize;
      return this.backlogFiltered.slice(start, start + this.backlogPageSize);
    }
    get backlogTotalPages() {
      return Math.ceil(this.backlogFiltered.length / this.backlogPageSize) || 1;
    }
    get backlogHasMore() {
      return this.backlogFiltered.length > this.backlogPageSize;
    }
    get isBacklogFirstPage() { return this.backlogPage === 0; }
    get isBacklogLastPage() { return this.backlogPage >= this.backlogTotalPages - 1; }
    get backlogPageDisplay() { return `${this.backlogPage + 1} / ${this.backlogTotalPages}`; }
    get schedCol3() {
      return this.backlogPaged;
    }

    @tracked dragCardId: string | null = null;
    @tracked dragOverCol: number | null = null;

    onDragStart = (id: string, e: DragEvent) => {
      this.dragCardId = id;
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', id);
      }
    };
    onDragOver = (col: number, e: DragEvent) => {
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
      this.dragOverCol = col;
    };
    onDrop = async (col: number, e: DragEvent) => {
      e.preventDefault();
      if (this.dragCardId === null) return;
      const allCards = [...this.schedCol0, ...this.schedCol1, ...this.schedCol2, ...this.backlogAll];
      const card = allCards.find((c) => c.id === this.dragCardId);
      this.dragCardId = null;
      this.dragOverCol = null;
      if (!card || !card._srcCard) return;

      // Update started date to the target week
      if (col < 3) {
        // Move to a specific week — set started to same weekday in target week
        const oldStarted = String((card._srcCard as any).started || '');
        let dayOfWeek = 0; // default Monday
        if (oldStarted) {
          // Parse as local time to avoid UTC offset issues
          const parts = oldStarted.split(/[-\/]/);
          if (parts.length >= 3) {
            const d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
            if (!isNaN(d.getTime())) {
              const dow = d.getDay();
              dayOfWeek = dow === 0 ? 6 : dow - 1; // 0=Mon ... 6=Sun
            }
          }
        }
        const targetMon = this._weekColToMonday(col);
        targetMon.setDate(targetMon.getDate() + dayOfWeek);
        const yyyy = targetMon.getFullYear();
        const mm = String(targetMon.getMonth() + 1).padStart(2, '0');
        const dd = String(targetMon.getDate()).padStart(2, '0');
        (card._srcCard as any).started = `${yyyy}-${mm}-${dd}`;
      } else {
        // Backlog — clear the date
        (card._srcCard as any).started = '';
      }

      // Persist
      try {
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const adminRealm = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card: card._srcCard, realm: adminRealm });
          console.log(`[Admin] moved "${card.name}" to week col ${col}`);
          await this.loadPrograms();
        }
      } catch (err: any) {
        console.warn('[Admin] failed to update schedule:', err?.message ?? err);
      }
    };
    onDragEnd = () => {
      this.dragCardId = null;
      this.dragOverCol = null;
    };
    onDragLeave = () => {
      this.dragOverCol = null;
    };
    isDragOver = (col: number) => this.dragOverCol === col;

    // Dynamic week date labels
    get weekLabels(): Array<{ label: string; dates: string }> {
      const now = new Date();
      const day = now.getDay();
      const mon = new Date(now);
      mon.setDate(now.getDate() - (day === 0 ? 6 : day - 1)); // Current Monday
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const fmt = (d: Date) => `${monthNames[d.getMonth()]} ${d.getDate()}`;
      const weekRange = (start: Date) => {
        const end = new Date(start);
        end.setDate(start.getDate() + 4); // Friday
        return `${fmt(start)}–${fmt(end)}`;
      };
      const w0 = new Date(mon);
      const w1 = new Date(mon);
      w1.setDate(mon.getDate() + 7);
      const w2 = new Date(mon);
      w2.setDate(mon.getDate() + 14);
      return [
        { label: 'THIS WEEK', dates: weekRange(w0) },
        { label: 'NEXT WEEK', dates: weekRange(w1) },
        { label: 'WEEK 3', dates: weekRange(w2) },
        { label: 'BACKLOG', dates: 'Not scheduled' },
      ];
    }
    get weekLabel0() {
      return this.weekLabels[0].label;
    }
    get weekDates0() {
      return this.weekLabels[0].dates;
    }
    get weekLabel1() {
      return this.weekLabels[1].label;
    }
    get weekDates1() {
      return this.weekLabels[1].dates;
    }
    get weekLabel2() {
      return this.weekLabels[2].label;
    }
    get weekDates2() {
      return this.weekLabels[2].dates;
    }
    get weekLabel3() {
      return this.weekLabels[3].label;
    }
    get weekDates3() {
      return this.weekLabels[3].dates;
    }

    // Tracking date range selector
    @tracked dateRangePreset = 'semester'; // 'week' | 'month' | '30days' | 'semester' | 'custom'
    @tracked customStartDate = '';
    @tracked customEndDate = '';
    @tracked selectedTrackingStudentIndex = 0;
    @tracked showStudentDropdown = false;
    @tracked studentSearchQuery = '';

    // Program Index state
    @tracked piDomainFilter = 'All Domains';
    @tracked piStatusFilter = 'Active Only';
    @tracked showPiDomainDrop = false;
    @tracked showPiStatusDrop = false;
    @tracked showAddProgramForm = false;
    @tracked piViewMode = 'table';
    @tracked piSortCol = 'program';
    @tracked piSortDir = 'asc';
    @tracked piSelectedStudentName = '';
    @tracked piSelectedStudentId = '';
    @tracked showPiStudentDrop = false;
    @tracked piStudentSearch = '';
    @tracked dynamicPrograms: any[] = [];
    // Inline edit state: "rowIdx:colName" or '' for no edit
    @tracked piEditCell = '';
    @tracked piEditValue = '';
    @tracked newProgName = '';
    @tracked newProgDomain = 'Math';
    @tracked newProgDomainKey = 'math';
    @tracked newProgAblls = '';
    @tracked newProgMaster = 'Yes';
    @tracked newProgSheet = 'Yes';
    @tracked newProgStarted = '';
    @tracked newProgTarget = '';
    @tracked newProgActive = 'Yes';
    @tracked newProgNotes = '';
    @tracked newProgDueDate = '';
    @tracked newProgTargetMastery = 80;
    @tracked newProgMaterials: Array<{ materialType: string; name: string; detail: string }> = [];
    @tracked localPrograms: Array<{
      program: string;
      domain: string;
      domainKey: string;
      abllsCode: string;
      masterSheet: string;
      programSheet: string;
      started: string;
      currentTarget: string;
      active: string;
      notes: string;
      studentName: string;
      studentId: string;
    }> = [];

    // Learning Goals state
    @tracked showAddGoalForm = false;
    @tracked goalSaveState: 'input' | 'saving' | 'error' | 'done' = 'input';
    @tracked goalSaveError = '';
    @tracked newGoalTitle = '';
    @tracked newGoalDesc = '';
    @tracked newGoalStudent = '';
    @tracked newGoalDomain = 'Mathematics';
    @tracked newGoalPriority = 'Medium';
    @tracked newGoalCurrentMastery = 0;
    @tracked newGoalTargetMastery = 80;
    @tracked newGoalDueDate = '';
    @tracked newGoalStandard = '';
    @tracked localGoals: Array<{
      goalTitle: string;
      domain: string;
      priority: string;
      currentMastery: number;
      targetMastery: number;
      dueDate: string;
      standardAlignment: string;
    }> = [];

    get allGoals() {
      // Prefer dynamically loaded goals from realm
      if (this.dynamicGoals.length > 0) {
        return this.dynamicGoals.map((g: any) => ({
          goalTitle: g.goalTitle ?? g.title ?? '',
          domain: g.domain ?? '',
          priority: g.priority ?? '',
          currentMastery: g.currentMastery ?? 0,
          targetMastery: g.targetMastery ?? 80,
          dueDate: g.dueDate ?? '',
          standardAlignment: g.standardAlignment ?? '',
          studentName: g.studentName ?? '',
        }));
      }
      return this.localGoals;
    }

    // ── Staff search + pagination ──
    @tracked staffSearchQuery = '';
    @tracked staffPage = 0;
    staffPageSize = 6;

    setStaffSearch = (e: Event) => { this.staffSearchQuery = (e.target as HTMLInputElement).value; this.staffPage = 0; };
    nextStaffPage = () => { if ((this.staffPage + 1) * this.staffPageSize < this.filteredStaff.length) this.staffPage++; };
    prevStaffPage = () => { if (this.staffPage > 0) this.staffPage--; };

    get visibleStaff() {
      void this._staffTick;
      // Prefer dynamically loaded staff (all StaffMember cards in realm)
      if (this.dynamicStaff.length > 0) {
        return this.dynamicStaff.map((s: any, i: number) => ({ s, i }));
      }
      // Fallback to linksToMany + local
      const model = (this.args.model.staff || []).map((s: any, i: number) => ({
        s,
        i,
      }));
      const local = this.localStaffCards.map((s: any, i: number) => ({
        s,
        i: model.length + i,
      }));
      return [...model, ...local];
    }

    get filteredStaff() {
      const q = this.staffSearchQuery.toLowerCase().trim();
      if (!q) return this.visibleStaff;
      return this.visibleStaff.filter((item: any) => {
        const name = String(item.s?.name ?? '').toLowerCase();
        const role = String(item.s?.role ?? '').toLowerCase();
        const email = String(item.s?.email ?? '').toLowerCase();
        return name.includes(q) || role.includes(q) || email.includes(q);
      });
    }

    get pagedStaff() {
      const start = this.staffPage * this.staffPageSize;
      return this.filteredStaff.slice(start, start + this.staffPageSize);
    }

    get showStaffPagination() { return this.filteredStaff.length > this.staffPageSize; }
    get cantPrevStaffPage() { return this.staffPage <= 0; }
    get cantNextStaffPage() { return (this.staffPage + 1) * this.staffPageSize >= this.filteredStaff.length; }
    get staffPageLabel() {
      const total = Math.ceil(this.filteredStaff.length / this.staffPageSize) || 1;
      return `${this.staffPage + 1} / ${total}`;
    }

    openAddStaffModal = () => {
      this.staffAiInput = '';
      this.staffAiState = 'input';
      this.staffAiError = '';
      this.newMemberName = '';
      this.newMemberRole = 'Lead Teacher';
      this.newMemberInitials = '';
      this.newMemberColor = 'teal';
      this.newMemberStudents = '';
      this.newMemberObs = '';
      this.newMemberEmail = '';
      this.showAddStaffForm = true;
      // Scroll to the modal after it renders
      setTimeout(() => {
        const el = document.querySelector('.staff-modal-overlay');
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 50);
    };
    closeAddStaffModal = () => {
      this.showAddStaffForm = false;
    };
    setStaffAiInput = (e: Event) => {
      this.staffAiInput = (e.target as HTMLTextAreaElement).value;
    };

    setMemberName = (e: Event) => {
      this.newMemberName = (e.target as HTMLInputElement).value;
    };
    setMemberRole = (e: Event) => {
      this.newMemberRole = (e.target as HTMLSelectElement).value;
    };
    setMemberInitials = (e: Event) => {
      this.newMemberInitials = (e.target as HTMLInputElement).value;
    };
    setMemberColor = (e: Event) => {
      this.newMemberColor = (e.target as HTMLSelectElement).value;
    };
    setMemberStudents = (e: Event) => {
      this.newMemberStudents = (e.target as HTMLInputElement).value;
    };
    setMemberObs = (e: Event) => {
      this.newMemberObs = (e.target as HTMLInputElement).value;
    };
    setMemberEmail = (e: Event) => {
      this.newMemberEmail = (e.target as HTMLInputElement).value;
    };

    // AI analysis task
    analyzeStaffTask = restartableTask(async () => {
      if (!this.staffAiInput.trim()) return;
      this.staffAiState = 'analyzing';
      this.staffAiError = '';
      try {
        const commandContext = (this.args as any).context?.commandContext;
        if (!commandContext) throw new Error('Command context not available');
        const input = new (await new AnalyzeStaffCommand(
          commandContext,
        ).getInputType())();
        input.rawText = this.staffAiInput;
        const result = await new AnalyzeStaffCommand(commandContext).execute(
          input,
        );
        this.newMemberName = result.name || '';
        this.newMemberRole = result.role || 'Lead Teacher';
        this.newMemberInitials = result.initials || '';
        this.newMemberColor = result.avatarColor || 'teal';
        this.newMemberStudents = String(result.studentCount || 0);
        this.newMemberObs = String(result.weeklyObservations || 0);
        this.newMemberEmail = result.email || '';
        this.staffAiState = 'preview';
      } catch (err: any) {
        this.staffAiError = err?.message || 'Analysis failed';
        this.staffAiState = 'error';
      }
    });

    triggerAnalyze = () => {
      this.analyzeStaffTask.perform();
    };

    // Save task — creates card in realm via SaveCardCommand
    saveStaffTask = restartableTask(async () => {
      if (!this.newMemberName.trim()) return;
      this.staffAiState = 'saving';
      try {
        const commandContext = (this.args as any).context?.commandContext;
        if (!commandContext) throw new Error('Command context not available');
        // Derive realm URL: card id is like https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/AdminDashboard/main
        // Realm URL is https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/
        const cardId = this.args.model.id || '';
        const idUrl = new URL(cardId);
        // Remove the last 2 segments (e.g. AdminDashboard/main) to get the realm path
        const segments = idUrl.pathname.split('/').filter(Boolean);
        const realmPath = segments.slice(0, -2).join('/');
        const realmUrl = `${idUrl.origin}/${realmPath}/`;

        const input = new (await new CreateStaffCommand(
          commandContext,
        ).getInputType())();
        input.name = this.newMemberName;
        input.role = this.newMemberRole;
        input.initials =
          this.newMemberInitials ||
          this.newMemberName
            .split(' ')
            .map((w: string) => w[0])
            .join('')
            .substring(0, 2)
            .toUpperCase();
        input.avatarColor = this.newMemberColor;
        input.studentCount = parseInt(this.newMemberStudents) || 0;
        input.weeklyObservations = parseInt(this.newMemberObs) || 0;
        input.email = this.newMemberEmail;
        input.realmUrl = realmUrl;

        await new CreateStaffCommand(commandContext).execute(input);

        // Auto-push to Classroom + HoS (Approach C — fire-and-forget so UI stays responsive)
        const newStaffSnapshot = {
          name: input.name,
          initials: input.initials,
          avatarColor: input.avatarColor,
          avatar: '',
        };
        const pushTargets = [
          { name: 'Classroom', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/' },
          { name: 'HoS', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/' },
        ];
        for (const t of pushTargets) {
          syncStaffToClassroom({
            staff: [newStaffSnapshot],
            ctx: commandContext,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
            heroRealm: t.realm,
          }).then((r) => {
            if (r.created + r.updated > 0) {
              console.log(`[Admin-${t.name}] auto-pushed Staff "${input.name}" (${r.created} new, ${r.updated} updated)`);
            } else if (r.failed > 0) {
              console.warn(`[Admin-${t.name}] auto-push Staff failed:`, r.errors);
            }
          }).catch((e) => console.warn(`[Admin-${t.name}] auto-push exception:`, e));
        }

        // Also add to localStaffCards for immediate UI
        this.localStaffCards = [
          ...this.localStaffCards,
          {
            name: this.newMemberName,
            role: this.newMemberRole,
            initials: this.newMemberInitials,
            avatarColor: this.newMemberColor,
            studentCount: this.newMemberStudents,
            weeklyObservations: this.newMemberObs,
            status: 'Active',
            email: this.newMemberEmail,
          },
        ];
        this._staffTick++;
        this.showAddStaffForm = false;
        // Reload staff list from realm to show the new card
        // Also push to dynamicStaff for immediate display even if getCards is slow
        this.dynamicStaff = [...this.dynamicStaff, {
          name: this.newMemberName,
          role: this.newMemberRole,
          initials: this.newMemberInitials || this.newMemberName.split(' ').map((w: string) => w[0]).join('').substring(0, 2).toUpperCase(),
          avatarColor: this.newMemberColor,
          studentCount: parseInt(this.newMemberStudents) || 0,
          weeklyObservations: parseInt(this.newMemberObs) || 0,
          status: 'Active',
          email: this.newMemberEmail,
        }];
        // Also try to reload from realm
        this.loadStaff();
      } catch (err: any) {
        this.staffAiError = err?.message || 'Save failed';
        this.staffAiState = 'error';
      }
    });

    triggerSaveStaff = () => {
      this.saveStaffTask.perform();
    };
    backToInput = () => {
      this.staffAiState = 'input';
    };
    isStaffStep = (step: string) => this.staffAiState === step;

    deleteStaff = async (index: number) => {
      // Find the actual staff card from visibleStaff (handles both dynamicStaff and model.staff)
      const item = this.visibleStaff[index];
      const card = item?.s;
      if (!card) return;
      const cardId = String(card?.id ?? '');
      const staffName = String(card?.name ?? '').trim();

      try {
        // Delete the StaffMember card from realm via HTTP DELETE
        if (cardId) {
          const resp = await fetch(cardId, { method: 'DELETE', headers: { 'Accept': 'application/vnd.card+json' } });
          if (resp.ok || resp.status === 204 || resp.status === 404) {
            console.log('[Admin] deleted staff card:', cardId);
          } else {
            console.warn('[Admin] staff delete returned:', resp.status);
          }
        }

        // Auto-delete matching Staff in Classroom + HoS (Approach C — fire-and-forget)
        if (staffName) {
          const ctx = this.hostCommandContext;
          const getCards = this.hostGetCards;
          if (ctx && getCards) {
            const delTargets = [
              { name: 'Classroom', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/' },
              { name: 'HoS', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/' },
            ];
            for (const t of delTargets) {
              deleteStaffFromClassroom({
                staffName,
                ctx,
                getCards,
                host: this,
                unwrapResource: this.unwrapResource.bind(this),
                heroRealm: t.realm,
              }).catch((e) => console.warn(`[Admin-${t.name}] auto-delete exception:`, e));
            }
          }
        }

        // Remove from local arrays
        this.dynamicStaff = this.dynamicStaff.filter((s: any) => String(s?.id ?? '') !== cardId);
        this.localStaffCards = this.localStaffCards.filter((s: any) => String(s?.id ?? '') !== cardId);
        (this.args.model as any).staff = (this.args.model.staff || []).filter((s: any) => String(s?.id ?? '') !== cardId);
        this._staffTick++;
      } catch (e: any) {
        console.warn('[Admin] staff delete failed:', e?.message ?? e);
      }
    };

    // Manual push: rebuild Classroom + HoS Staff from ALL Admin staff
    handleRebuildClassroomStaff = async () => {
      this.rebuildStaffState = 'running';
      this.rebuildStaffMsg = null;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.rebuildStaffState = 'error';
        this.rebuildStaffMsg = 'Context unavailable';
        return;
      }
      const allStaff = (this.dynamicStaff || []).filter((s: any) => s && String(s?.name ?? '').trim());
      if (allStaff.length === 0) {
        this.rebuildStaffState = 'success';
        this.rebuildStaffMsg = 'No Admin staff to push';
        return;
      }
      const targets = [
        { name: 'Classroom', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/' },
        { name: 'HoS', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/' },
      ];
      const summary: string[] = [];
      const errs: string[] = [];
      for (const t of targets) {
        try {
          const r = await syncStaffToClassroom({
            staff: allStaff,
            ctx,
            getCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
            heroRealm: t.realm,
          });
          if (r.failed > 0) {
            errs.push(`${t.name}: ${r.errors[0]?.error ?? 'unknown'}`);
          } else {
            summary.push(`${t.name} (${r.created}+${r.updated}, skip ${r.skipped})`);
          }
        } catch (e: any) {
          errs.push(`${t.name}: ${e?.message ?? String(e)}`);
        }
      }
      this.rebuildStaffState = errs.length > 0 ? 'error' : 'success';
      this.rebuildStaffMsg = errs.length > 0
        ? `Pushed ${summary.join(', ') || 'none'}; failed: ${errs.join(' | ')}`
        : `Done: ${summary.join(', ')} (of ${allStaff.length})`;
    };

    // Manual push: rebuild Classroom Goals from ALL Admin programs
    handleRebuildClassroomGoals = async () => {
      this.rebuildGoalsState = 'running';
      this.rebuildGoalsMsg = null;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.rebuildGoalsState = 'error';
        this.rebuildGoalsMsg = 'Context unavailable';
        return;
      }
      const allPrograms = (this.dynamicPrograms || []).filter((p: any) => p && String(p?.program ?? '').trim());
      if (allPrograms.length === 0) {
        this.rebuildGoalsState = 'success';
        this.rebuildGoalsMsg = 'No Admin programs to push';
        return;
      }
      // Only push to Classroom — HoS Goal syncs from Classroom-side via
      // _autoSyncGoalMastery (see sync-goals-to-hos in Classroom workspace).
      try {
        const r = await syncProgramsToClassroom({
          programs: allPrograms,
          ctx,
          getCards,
          host: this,
          unwrapResource: this.unwrapResource.bind(this),
        });
        this.rebuildGoalsState = r.failed > 0 ? 'error' : 'success';
        this.rebuildGoalsMsg = `Done: ${r.created} new, ${r.updated} updated, ${r.skipped} unchanged${r.failed > 0 ? `, ${r.failed} failed` : ''} (of ${r.total})`;
      } catch (e: any) {
        this.rebuildGoalsState = 'error';
        this.rebuildGoalsMsg = `Failed: ${e?.message ?? String(e)}`;
      }
    };

    // Delete a Program in Admin AND the matching LearningGoal in Classroom (by title+studentName)
    handleDeleteProgram = async (prog: any) => {
      // allPrograms wraps each ProgramRecord card under _srcCard, so id lives there
      const cardId = String(prog?._srcCard?.id ?? prog?.id ?? '');
      const title = String(prog?.program ?? '').trim();
      const studentName = String(prog?.studentName ?? '').trim();
      if (!cardId || !title) return;

      const ok = window.confirm(
        `Delete Program "${title}" for "${studentName}" from Admin AND remove matching Goal in Classroom + HoS?\n\nThis cannot be undone.`,
      );
      if (!ok) return;

      this.deletingProgramId = cardId;
      this.deleteProgramMsg = `Deleting "${title}"...`;
      const errs: string[] = [];

      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;

      // 0. Cascade delete matching ActivityEntries in Classroom + HoS mirrors
      //    AE.suggestedGoal may carry AI-appended metadata like " (Math, 66%)" —
      //    strip trailing "(...)" before comparing.
      if (ctx && getCards) {
        try {
          const heroRealm = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
          const hosRealm = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/';
          const cRes = getCards(this, () => ({
            filter: { type: { module: `${heroRealm}activity-entry`, name: 'ActivityEntry' } },
          }), () => [heroRealm]);
          const classroomAes = await this.unwrapResource(cRes, 8000);
          const hRes = getCards(this, () => ({
            filter: { type: { module: `${hosRealm}activity-entry`, name: 'ActivityEntry' } },
          }), () => [hosRealm]);
          const hosAes = await this.unwrapResource(hRes, 8000);

          const titleLower = title.toLowerCase();
          const studentLower = studentName.toLowerCase();
          const matchingAes = classroomAes.filter((ae: any) => {
            const raw = String(ae?.suggestedGoal ?? '');
            const clean = raw.replace(/\s*\(.*?\)\s*$/, '').trim().toLowerCase();
            const aeStudent = String(ae?.studentName ?? '').trim().toLowerCase();
            return clean === titleLower && aeStudent === studentLower;
          });
          console.log(`[Admin-cascade] ${matchingAes.length} AEs matched goal "${title}" for "${studentName}"`);

          for (const ae of matchingAes) {
            const aeId = String(ae?.id ?? '');
            if (!aeId) continue;
            try {
              const r = await fetch(aeId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
              if (r.ok || r.status === 204 || r.status === 404) {
                console.log(`[Admin-cascade] deleted Classroom AE: ${aeId}`);
              } else {
                errs.push(`Classroom AE ${r.status}`);
              }
            } catch (e: any) { errs.push(`Classroom AE: ${e?.message ?? String(e)}`); }
            // Delete HoS AE mirror by sourceEntryId
            const mirror = hosAes.find((h: any) => String(h?.sourceEntryId ?? '') === aeId);
            if (mirror?.id) {
              try {
                await fetch(mirror.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
                console.log(`[Admin-cascade] deleted HoS AE mirror: ${mirror.id}`);
              } catch (e: any) { errs.push(`HoS AE: ${e?.message ?? String(e)}`); }
            }
          }
        } catch (e: any) {
          errs.push(`AE cascade: ${e?.message ?? String(e)}`);
          console.warn('[Admin] AE cascade failed:', e);
        }
      }

      // 1. Delete matching LearningGoal in Classroom + HoS (title + studentName)
      if (ctx && getCards) {
        const delTargets = [
          { name: 'Classroom', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/' },
          { name: 'HoS', realm: 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/' },
        ];
        for (const dt of delTargets) {
          try {
            const goalRes = getCards(this, () => ({
              filter: { type: { module: `${dt.realm}learning-goal`, name: 'LearningGoal' } },
            }), () => [dt.realm]);
            const mirrorGoals = await this.unwrapResource(goalRes, 8000);
            const target = mirrorGoals.find((g: any) => {
              const t = String(g?.goalTitle ?? '').trim().toLowerCase();
              const s = String(g?.studentName ?? '').trim().toLowerCase();
              return t === title.toLowerCase() && s === studentName.toLowerCase();
            });
            if (target?.id) {
              await fetch(target.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
              console.log(`[Admin-${dt.name}] deleted LearningGoal "${title}":`, target.id);
            } else {
              console.log(`[Admin-${dt.name}] no matching LearningGoal for "${title}/${studentName}"`);
            }
          } catch (e: any) {
            errs.push(`${dt.name}: ${e?.message ?? String(e)}`);
            console.warn(`[Admin-${dt.name}] LearningGoal delete failed:`, e);
          }
        }
      }

      // 2. Delete the Admin ProgramRecord itself
      try {
        const resp = await fetch(cardId, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
        console.log(`[Admin] DELETE ${cardId} -> status ${resp.status} ok=${resp.ok}`);
        if (resp.ok || resp.status === 204 || resp.status === 404) {
          console.log(`[Admin] deleted ProgramRecord "${title}":`, cardId);
          this.dynamicPrograms = (this.dynamicPrograms || []).filter((p: any) => String(p?.id ?? '') !== cardId);
        } else {
          const body = await resp.text().catch(() => '(no body)');
          errs.push(`Admin DELETE returned ${resp.status}: ${body.slice(0, 120)}`);
          console.warn(`[Admin] DELETE non-OK status ${resp.status}, body:`, body);
        }
      } catch (e: any) {
        errs.push(`Admin: ${e?.message ?? String(e)}`);
        console.warn('[Admin] ProgramRecord delete fetch threw:', e);
      }

      this.deletingProgramId = '';
      if (errs.length > 0) {
        this.deleteProgramMsg = `Delete error: ${errs.join(' | ')}`;
      } else {
        this.deleteProgramMsg = `Deleted "${title}".`;
        setTimeout(() => { this.deleteProgramMsg = ''; }, 4000);
      }
    };

    isEditingStaff = (index: number) => this.editingStaffIndex === index;

    startEditStaff = (index: number, s: any) => {
      this.editingStaffIndex = index;
      this.editStaffValues = {
        name: s.name || '',
        role: s.role || 'Lead Teacher',
        initials: s.initials || '',
        avatarColor: s.avatarColor || 'teal',
        studentCount: String(s.studentCount ?? '0'),
        weeklyObservations: String(s.weeklyObservations ?? '0'),
        status: s.status || 'Active',
      };
    };

    cancelEditStaff = () => {
      this.editingStaffIndex = null;
    };

    saveEditStaff = async (index: number, e: Event) => {
      e.preventDefault();
      if (!this.editStaffValues.name.trim()) return;
      const initials =
        this.editStaffValues.initials.trim() ||
        this.editStaffValues.name
          .split(' ')
          .map((w: string) => w[0])
          .join('')
          .substring(0, 2)
          .toUpperCase();

      // Find the actual card object from dynamicStaff or model.staff
      const staffCard = this.dynamicStaff[index] ?? (this.args.model.staff || [])[index];
      if (staffCard) {
        // Update card fields
        (staffCard as any).name = this.editStaffValues.name;
        (staffCard as any).role = this.editStaffValues.role;
        (staffCard as any).initials = initials;
        (staffCard as any).avatarColor = this.editStaffValues.avatarColor;
        (staffCard as any).studentCount = parseInt(this.editStaffValues.studentCount) || 0;
        (staffCard as any).weeklyObservations = parseInt(this.editStaffValues.weeklyObservations) || 0;
        (staffCard as any).status = this.editStaffValues.status;

        // Persist to realm
        try {
          const commandContext = (this.args as any).context?.commandContext;
          if (commandContext) {
            const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
            const realmUrl = new URL('./', import.meta.url).href;
            await new SaveCardCommand(commandContext).execute({ card: staffCard, realm: realmUrl });
            console.log(`[Admin] saved staff "${this.editStaffValues.name}" to realm`);
          }
        } catch (err) {
          console.warn('[Admin] failed to persist staff edit:', err);
        }
      }

      this._staffTick++;
      this.editingStaffIndex = null;
      // Refresh list
      this.loadStaff();
    };

    setEditStaffName = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        name: (e.target as HTMLInputElement).value,
      };
    };
    setEditStaffRole = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        role: (e.target as HTMLSelectElement).value,
      };
    };
    setEditStaffInitials = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        initials: (e.target as HTMLInputElement).value,
      };
    };
    setEditStaffColor = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        avatarColor: (e.target as HTMLSelectElement).value,
      };
    };
    setEditStaffStudents = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        studentCount: (e.target as HTMLInputElement).value,
      };
    };
    setEditStaffObs = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        weeklyObservations: (e.target as HTMLInputElement).value,
      };
    };
    setEditStaffStatus = (e: Event) => {
      this.editStaffValues = {
        ...this.editStaffValues,
        status: (e.target as HTMLSelectElement).value,
      };
    };

    isEditStaffRole = (role: string) => this.editStaffValues.role === role;
    isEditStaffColor = (color: string) =>
      this.editStaffValues.avatarColor === color;
    isEditStaffStatus = (status: string) =>
      this.editStaffValues.status === status;

    get filteredRows() {
      void this._obsTick;
      const modelRows = (this.args.model.observations || []).map(
        (obs: any, i: number) => ({
          data: obs,
          isLocal: false,
          idx: i,
        }),
      );
      const localRows = this.localRows.map((row: any, i: number) => ({
        data: row,
        isLocal: true,
        idx: i,
      }));
      let rows: any[] = [...modelRows, ...localRows];

      const q = this.searchQuery.trim().toLowerCase();
      if (q) {
        rows = rows.filter(
          (r: any) =>
            (r.data.studentName || '').toLowerCase().includes(q) ||
            (r.data.linkedGoal || '').toLowerCase().includes(q) ||
            (r.data.staffInitials || '').toLowerCase().includes(q) ||
            (r.data.date || '').toLowerCase().includes(q),
        );
      }

      if (this.activeTypeFilter !== 'All') {
        rows = rows.filter(
          (r: any) => r.data.category === this.activeTypeFilter,
        );
      }

      if (this.staffFilter !== 'All Staff') {
        rows = rows.filter(
          (r: any) => (r.data.staffInitials || '') === this.staffFilter,
        );
      }

      const col = this.sortCol;
      const dir = this.sortDir;
      rows = [...rows].sort((a: any, b: any) => {
        let aVal = '';
        let bVal = '';
        if (col === 'student') {
          aVal = a.data.studentName || '';
          bVal = b.data.studentName || '';
        } else if (col === 'type') {
          aVal = a.data.category || '';
          bVal = b.data.category || '';
        } else if (col === 'goal') {
          aVal = a.data.linkedGoal || '';
          bVal = b.data.linkedGoal || '';
        } else if (col === 'score') {
          aVal = a.data.score || '';
          bVal = b.data.score || '';
        } else if (col === 'staff') {
          aVal = a.data.staffInitials || '';
          bVal = b.data.staffInitials || '';
        } else {
          aVal = a.data.date || '';
          bVal = b.data.date || '';
        }
        const cmp = aVal.localeCompare(bVal);
        return dir === 'asc' ? cmp : -cmp;
      });

      return rows;
    }

    setSearch = (e: Event) => {
      this.searchQuery = (e.target as HTMLInputElement).value;
      this.obsPage = 0;
    };
    setTypeFilter = (type: string) => {
      this.activeTypeFilter = type;
      this.obsPage = 0;
    };
    setStaffFilter = (e: Event) => {
      this.staffFilter = (e.target as HTMLSelectElement).value;
      this.obsPage = 0;
    };
    isActiveType = (type: string) => this.activeTypeFilter === type;

    // Observation pagination
    get pagedRows() {
      const start = this.obsPage * this.obsPageSize;
      return this.filteredRows.slice(start, start + this.obsPageSize);
    }
    get obsTotalCount() { return this.filteredRows.length; }
    get obsShowingStart() { return this.obsTotalCount === 0 ? 0 : this.obsPage * this.obsPageSize + 1; }
    get obsShowingEnd() { return Math.min((this.obsPage + 1) * this.obsPageSize, this.obsTotalCount); }
    get showObsPagination() { return this.obsTotalCount > this.obsPageSize; }
    get cantPrevObs() { return this.obsPage <= 0; }
    get cantNextObs() { return (this.obsPage + 1) * this.obsPageSize >= this.obsTotalCount; }
    get obsTotalPages() { return Math.ceil(this.obsTotalCount / this.obsPageSize) || 1; }
    nextObsPage = () => { if (!this.cantNextObs) this.obsPage++; };
    prevObsPage = () => { if (!this.cantPrevObs) this.obsPage--; };
    goObsPage = (p: number) => { this.obsPage = p; };

    // Staff names for filter dropdown
    get obsStaffList() {
      const names = new Set<string>();
      for (const r of this.filteredRows) {
        const si = r.data.staffInitials || '';
        if (si) names.add(si);
      }
      return [...names].sort();
    }

    get obsPageNumbers() {
      const total = this.obsTotalPages;
      const current = this.obsPage;
      const pages: Array<{ page: number; label: string; active: boolean }> = [];
      for (let i = 0; i < total; i++) {
        if (total <= 5 || i === 0 || i === total - 1 || Math.abs(i - current) <= 1) {
          pages.push({ page: i, label: String(i + 1), active: i === current });
        } else if (pages.length > 0 && pages[pages.length - 1].label !== '...') {
          pages.push({ page: -1, label: '...', active: false });
        }
      }
      return pages;
    }


    toggleSort = (col: string) => {
      if (this.sortCol === col) {
        this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
      } else {
        this.sortCol = col;
        this.sortDir = 'asc';
      }
    };

    sortIndicator = (col: string) =>
      this.sortCol === col ? (this.sortDir === 'asc' ? ' ↑' : ' ↓') : '';

    deleteRow = (isLocal: boolean, index: number) => {
      if (isLocal) {
        this.localRows = this.localRows.filter(
          (_: any, i: number) => i !== index,
        );
      } else {
        (this.args.model as any).observations = (
          this.args.model.observations || []
        ).filter((_: any, i: number) => i !== index);
        this._obsTick++;
      }
    };

    get totalCount() {
      return this.filteredRows.length;
    }

    toggleForm = () => {
      this.showAddForm = !this.showAddForm;
      if (!this.showAddForm) {
        this.newStudent = '';
        this.newCategory = 'Academic';
        this.newGoal = '';
        this.newScore = '';
        this.newStaffInitials = '';
        this.newStaffColor = 'teal';
      }
    };

    setStudent = (e: Event) => {
      this.newStudent = (e.target as HTMLInputElement).value;
    };
    setCategory = (e: Event) => {
      this.newCategory = (e.target as HTMLSelectElement).value;
    };
    setGoal = (e: Event) => {
      this.newGoal = (e.target as HTMLInputElement).value;
    };
    setScore = (e: Event) => {
      this.newScore = (e.target as HTMLInputElement).value;
    };
    setStaffInitials = (e: Event) => {
      this.newStaffInitials = (e.target as HTMLInputElement).value;
    };
    setStaffColor = (e: Event) => {
      this.newStaffColor = (e.target as HTMLSelectElement).value;
    };

    submitRow = (e: Event) => {
      e.preventDefault();
      if (!this.newStudent.trim()) return;
      const now = new Date();
      const dateStr =
        now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
        ', ' +
        now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
      const newObs = {
        date: dateStr,
        studentName: this.newStudent,
        category: this.newCategory,
        linkedGoal: this.newGoal || '—',
        score: this.newScore || '—',
        staffInitials: this.newStaffInitials || '?',
        staffColor: this.newStaffColor,
        flagged: 'false',
        notes: '',
      };
      this.localRows = [...this.localRows, newObs];
      this._obsTick++;
      this.showAddForm = false;
      this.newStudent = '';
      this.newCategory = 'Academic';
      this.newGoal = '';
      this.newScore = '';
      this.newStaffInitials = '';
      this.newStaffColor = 'teal';
    };

    isFlaggedItem = (item: any) => {
      if (item.isLocal) {
        return item.data.flagged === 'true';
      }
      const override = this.flagOverrides[item.idx];
      if (override !== undefined) return override === 'true';
      return item.data.flagged === 'true';
    };
    catLower = (obs: any) => (obs.category || '').toLowerCase();
    goodScore = (obs: any) => {
      let s = obs.score || '';
      let m = s.match(/^(\d+)\/(\d+)$/);
      return m ? parseInt(m[1]) / parseInt(m[2]) >= 0.8 : false;
    };

    // Row identity helpers
    rowKey = (item: any) => `${item.isLocal ? 'local' : 'model'}-${item.idx}`;
    isEditing = (item: any) => this.editingRowKey === this.rowKey(item);
    isRowSelected = (item: any) =>
      this.selectedRowKeys.includes(this.rowKey(item));
    isEditCat = (cat: string) => this.editValues.category === cat;
    isEditColor = (color: string) => this.editValues.staffColor === color;

    get hasSelection() {
      return this.selectedRowKeys.length > 0;
    }
    get selectionCount() {
      return this.selectedRowKeys.length;
    }
    get isAllSelected() {
      return (
        this.filteredRows.length > 0 &&
        this.selectedRowKeys.length === this.filteredRows.length
      );
    }

    // Inline edit
    startEdit = (item: any) => {
      this.editingRowKey = this.rowKey(item);
      this.editValues = {
        studentName: item.data.studentName || '',
        category: item.data.category || 'Academic',
        linkedGoal:
          item.data.linkedGoal === '—' ? '' : item.data.linkedGoal || '',
        score: item.data.score === '—' ? '' : item.data.score || '',
        staffInitials:
          item.data.staffInitials === '?' ? '' : item.data.staffInitials || '',
        staffColor: item.data.staffColor || 'teal',
      };
    };

    cancelEdit = () => {
      this.editingRowKey = null;
    };

    saveEdit = (item: any) => {
      const updated = {
        date: item.data.date,
        studentName: this.editValues.studentName || item.data.studentName,
        category: this.editValues.category,
        linkedGoal: this.editValues.linkedGoal || '—',
        score: this.editValues.score || '—',
        staffInitials: this.editValues.staffInitials || '?',
        staffColor: this.editValues.staffColor,
        flagged: this.isFlaggedItem(item) ? 'true' : 'false',
      };
      if (item.isLocal) {
        this.localRows = this.localRows.map((r: any, i: number) =>
          i === item.idx ? updated : r,
        );
      } else {
        (this.args.model as any).observations = (
          this.args.model.observations || []
        ).map((obs: any, i: number) => (i === item.idx ? updated : obs));
        this._obsTick++;
      }
      const key = this.rowKey(item);
      this.selectedRowKeys = this.selectedRowKeys.filter(
        (k: string) => k !== key,
      );
      this.editingRowKey = null;
    };

    setEditStudent = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        studentName: (e.target as HTMLInputElement).value,
      };
    };
    setEditCategory = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        category: (e.target as HTMLSelectElement).value,
      };
    };
    setEditGoal = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        linkedGoal: (e.target as HTMLInputElement).value,
      };
    };
    setEditScore = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        score: (e.target as HTMLInputElement).value,
      };
    };
    setEditObsStaffInitials = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        staffInitials: (e.target as HTMLInputElement).value,
      };
    };
    setEditObsStaffColor = (e: Event) => {
      this.editValues = {
        ...this.editValues,
        staffColor: (e.target as HTMLSelectElement).value,
      };
    };

    // Duplicate
    duplicateRow = (item: any) => {
      this.localRows = [
        ...this.localRows,
        {
          date: item.data.date,
          studentName: `${item.data.studentName} (copy)`,
          category: item.data.category,
          linkedGoal: item.data.linkedGoal,
          score: item.data.score,
          staffInitials: item.data.staffInitials,
          staffColor: item.data.staffColor,
          flagged: 'false',
          notes: item.data.notes || '',
        },
      ];
    };

    // Bulk select & delete
    toggleRowSelection = (item: any) => {
      const key = this.rowKey(item);
      if (this.selectedRowKeys.includes(key)) {
        this.selectedRowKeys = this.selectedRowKeys.filter(
          (k: string) => k !== key,
        );
      } else {
        this.selectedRowKeys = [...this.selectedRowKeys, key];
      }
    };

    toggleSelectAll = () => {
      if (this.isAllSelected) {
        this.selectedRowKeys = [];
      } else {
        this.selectedRowKeys = (this.filteredRows as any[]).map((item: any) =>
          this.rowKey(item),
        );
      }
    };

    bulkDelete = () => {
      const modelToDelete: number[] = [];
      const localToDelete: number[] = [];
      for (const key of this.selectedRowKeys) {
        const [type, idxStr] = key.split('-');
        const idx = parseInt(idxStr);
        if (type === 'local') {
          localToDelete.push(idx);
        } else {
          modelToDelete.push(idx);
        }
      }
      if (localToDelete.length) {
        this.localRows = this.localRows.filter(
          (_: any, i: number) => !localToDelete.includes(i),
        );
      }
      if (modelToDelete.length) {
        (this.args.model as any).observations = (
          this.args.model.observations || []
        ).filter((_: any, i: number) => !modelToDelete.includes(i));
        this._obsTick++;
      }
      this.selectedRowKeys = [];
    };

    // Type counts across all visible rows (ignores active filter)
    get typeCounts() {
      void this._obsTick;
      const all: any[] = [
        ...(this.args.model.observations || []),
        ...this.localRows,
      ];
      return {
        Academic: all.filter((r: any) => r.category === 'Academic').length,
        Social: all.filter((r: any) => r.category === 'Social').length,
        Behavioral: all.filter((r: any) => r.category === 'Behavioral').length,
      };
    }

    get isFiltered() {
      return this.searchQuery.trim() !== '' || this.activeTypeFilter !== 'All';
    }

    get isEmpty() {
      return this.filteredRows.length === 0;
    }

    resetFilters = () => {
      this.searchQuery = '';
      this.activeTypeFilter = 'All';
    };

    // Flag toggle — use local override map for reliable toggling
    toggleFlag = (item: any) => {
      if (item.isLocal) {
        this.localRows = this.localRows.map((r: any, i: number) =>
          i === item.idx
            ? { ...r, flagged: r.flagged === 'true' ? 'false' : 'true' }
            : r,
        );
      } else {
        const currentlyFlagged = this.isFlaggedItem(item);
        this.flagOverrides = {
          ...this.flagOverrides,
          [item.idx]: currentlyFlagged ? 'false' : 'true',
        };
        this._obsTick++;
      }
    };

    // Confirmation dialog
    requestConfirm = (msg: string, action: () => void) => {
      this.confirmPending = { message: msg, action };
    };

    confirmAction = () => {
      if (this.confirmPending) {
        this.confirmPending.action();
        this.confirmPending = null;
      }
    };

    cancelConfirm = () => {
      this.confirmPending = null;
    };
    stopPropagation = (e: Event) => {
      e.stopPropagation();
    };

    // ── Program Index ────────────────────────────────────────────────
    // Student list for program index picker
    get piStudentList(): Array<{ name: string; id: string; initials: string }> {
      if (this.fetchedProfiles.length > 0) {
        return this.fetchedProfiles.map((p: any) => {
          const ident = p?.identity;
          const first = String(ident?.firstName ?? '');
          const last = String(ident?.lastName ?? '');
          const name = `${first} ${last}`.trim() || 'Unknown';
          const id = String(ident?.studentId ?? p?.id ?? '');
          const initials = (first.charAt(0) + last.charAt(0)).toUpperCase() || '??';
          return { name, id, initials };
        });
      }
      return this.trackingStudents.map((s: any) => ({
        name: s.name,
        id: '',
        initials: s.initials,
      }));
    }

    get piFilteredStudentList() {
      const q = this.piStudentSearch.toLowerCase().trim();
      if (!q) return this.piStudentList;
      return this.piStudentList.filter((s) => s.name.toLowerCase().includes(q));
    }

    get piSelectedStudentDisplay() {
      return this.piSelectedStudentName || 'Select a student';
    }

    get piSelectedStudentInitials() {
      const s = this.piStudentList.find((s) => s.name === this.piSelectedStudentName);
      return s?.initials || '';
    }

    selectPiStudent = (name: string, id: string) => {
      this.piSelectedStudentName = name;
      this.piSelectedStudentId = id;
      this.showPiStudentDrop = false;
      this.piStudentSearch = '';
    };

    togglePiStudentDrop = (e: Event) => {
      e.stopPropagation();
      this.showPiStudentDrop = !this.showPiStudentDrop;
      this.showPiDomainDrop = false;
      this.showPiStatusDrop = false;
    };

    setPiStudentSearch = (e: Event) => {
      this.piStudentSearch = (e.target as HTMLInputElement).value;
    };

    get allPrograms(): any[] {
      // Read from ProgramRecord cards (dynamicPrograms loaded on startup)
      const progs = this.dynamicPrograms.length > 0
        ? this.dynamicPrograms
        : (this.args.model.programs || []);
      const realmProgs = progs.map((p: any, i: number) => ({
        _srcCard: p,
        _idx: i,
        program: p.program || '',
        domain: p.domain || '',
        domainKey: p.domainKey || '',
        abllsCode: p.abllsCode || '',
        masterSheet: p.masterSheet || '',
        programSheet: p.programSheet || '',
        started: p.started || '',
        currentTarget: p.currentTarget || '',
        active: p.active || 'Yes',
        notes: p.notes || '',
        studentName: p.studentName || '',
        studentId: p.studentId || '',
        dueDate: p.dueDate || '',
        targetMastery: p.targetMastery ?? '',
        materials: p.materials || [],
      }));
      return [...realmProgs, ...this.localPrograms];
    }

    get isAllStudentsSelected() { return this.piSelectedStudentName === 'All Students'; }

    get studentPrograms(): any[] {
      if (!this.piSelectedStudentName) return [];
      if (this.isAllStudentsSelected) {
        return this.allPrograms.map((p: any, i: number) => ({ ...p, _rowIdx: i }));
      }
      const sName = this.piSelectedStudentName.toLowerCase().trim();
      return this.allPrograms
        .filter((p: any) => (p.studentName || '').toLowerCase().trim() === sName)
        .map((p: any, i: number) => ({ ...p, _rowIdx: i }));
    }

    get piDomains() {
      const domains = Array.from(
        new Set(this.allPrograms.map((p: any) => p.domain)),
      );
      return ['All Domains', ...domains];
    }

    get piFilteredPrograms() {
      let rows = this.studentPrograms;
      if (this.piDomainFilter !== 'All Domains') {
        rows = rows.filter((p: any) => p.domain === this.piDomainFilter);
      }
      if (this.piStatusFilter === 'Active Only') {
        rows = rows.filter((p: any) => p.active === 'Yes');
      } else if (this.piStatusFilter === 'Discontinued') {
        rows = rows.filter((p: any) => p.active === 'No');
      }
      const col = this.piSortCol;
      const dir = this.piSortDir;
      rows = [...rows].sort((a: any, b: any) => {
        const aVal: string =
          col === 'domain'
            ? a.domain
            : col === 'started'
              ? a.started
              : col === 'active'
                ? a.active
                : a.program;
        const bVal: string =
          col === 'domain'
            ? b.domain
            : col === 'started'
              ? b.started
              : col === 'active'
                ? b.active
                : b.program;
        const cmp = aVal.localeCompare(bVal);
        return dir === 'asc' ? cmp : -cmp;
      });
      return rows;
    }

    setPiDomain = (d: string) => {
      this.piDomainFilter = d;
      this.showPiDomainDrop = false;
    };
    setPiStatus = (s: string) => {
      this.piStatusFilter = s;
      this.showPiStatusDrop = false;
    };
    togglePiDomainDrop = (e: Event) => {
      e.stopPropagation();
      this.showPiDomainDrop = !this.showPiDomainDrop;
      this.showPiStatusDrop = false;
    };
    togglePiStatusDrop = (e: Event) => {
      e.stopPropagation();
      this.showPiStatusDrop = !this.showPiStatusDrop;
      this.showPiDomainDrop = false;
    };
    closePiDrops = () => {
      this.showPiDomainDrop = false;
      this.showPiStatusDrop = false;
      this.showPiStudentDrop = false;
    };
    isPiStudentSelected = (name: string) => this.piSelectedStudentName === name;
    isMatPrimary = (mat: any) => (mat?.materialType || '').toLowerCase() === 'primary';

    // Inline materials editor
    @tracked editMatProgIdx: number | null = null;
    @tracked editMats: Array<{ materialType: string; name: string; detail: string }> = [];

    openMatEditor = (prog: any, e: Event) => {
      e.stopPropagation();
      this.editMatProgIdx = prog._rowIdx;
      this.editMats = (prog.materials || []).map((m: any) => ({
        materialType: m.materialType || 'Primary',
        name: m.name || '',
        detail: m.detail || '',
      }));
      if (this.editMats.length === 0) this.editMats = [{ materialType: 'Primary', name: '', detail: '' }];
    };
    closeMatEditor = () => { this.editMatProgIdx = null; this.editMats = []; };
    isEditingMats = (idx: number) => this.editMatProgIdx === idx;
    addEditMat = () => { this.editMats = [...this.editMats, { materialType: 'Primary', name: '', detail: '' }]; };
    removeEditMat = (idx: number) => { this.editMats = this.editMats.filter((_, i) => i !== idx); };
    setEditMatType = (idx: number, e: Event) => {
      const m = [...this.editMats]; m[idx] = { ...m[idx], materialType: (e.target as HTMLSelectElement).value }; this.editMats = m;
    };
    setEditMatName = (idx: number, e: Event) => {
      const m = [...this.editMats]; m[idx] = { ...m[idx], name: (e.target as HTMLInputElement).value }; this.editMats = m;
    };
    setEditMatDetail = (idx: number, e: Event) => {
      const m = [...this.editMats]; m[idx] = { ...m[idx], detail: (e.target as HTMLInputElement).value }; this.editMats = m;
    };
    saveEditMats = async (prog: any) => {
      const srcCard = prog._srcCard;
      if (!srcCard) { this.closeMatEditor(); return; }
      try {
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { ProgramMaterial } = await import('./program-record');
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const adminRealm = new URL('./', import.meta.url).href;
          const mats = this.editMats.filter((m) => m.name.trim()).map((m) => {
            const mat = new ProgramMaterial();
            (mat as any).materialType = m.materialType;
            (mat as any).name = m.name;
            (mat as any).detail = m.detail;
            return mat;
          });
          (srcCard as any).materials = mats;
          await new SaveCardCommand(ctx).execute({ card: srcCard, realm: adminRealm });
          await this.loadPrograms();
        }
      } catch (err: any) {
        console.warn('[Admin] save materials failed:', err?.message ?? err);
      }
      this.closeMatEditor();
    };
    setPiView = (mode: string) => {
      this.piViewMode = mode;
    };

    isDomainSelected = (d: string) => this.piDomainFilter === d;
    isStatusSelected = (s: string) => this.piStatusFilter === s;
    isYes = (v: string) => v === 'Yes';
    get isPiViewTable() {
      return this.piViewMode === 'table';
    }
    get isPiViewCard() {
      return this.piViewMode === 'card';
    }
    isProgActive = (p: any) => p.active === 'Yes';
    isProgDiscontinued = (p: any) =>
      p.notes === 'Discontinued' || p.active === 'No';
    isSortedBy = (col: string) => this.piSortCol === col;

    togglePiSort = (col: string) => {
      if (this.piSortCol === col) {
        this.piSortDir = this.piSortDir === 'asc' ? 'desc' : 'asc';
      } else {
        this.piSortCol = col;
        this.piSortDir = 'asc';
      }
    };

    get piSortIndicator() {
      return this.piSortDir === 'asc' ? ' ↑' : ' ↓';
    }

    toggleAddProgramForm = () => {
      this.showAddProgramForm = !this.showAddProgramForm;
    };

    // ── Inline cell editing (spreadsheet-style) ──
    isEditingCell = (idx: number, col: string) => this.piEditCell === `${idx}:${col}`;

    startEditCell = (idx: number, col: string, currentValue: string, e: Event) => {
      e.stopPropagation();
      this.piEditCell = `${idx}:${col}`;
      this.piEditValue = currentValue || '';
    };

    setPiEditValue = (e: Event) => {
      this.piEditValue = (e.target as HTMLInputElement).value;
    };

    cancelEdit = () => {
      this.piEditCell = '';
      this.piEditValue = '';
    };

    commitEdit = async (prog: any, col: string) => {
      const val = this.piEditValue;
      const srcCard = prog._srcCard;
      if (!srcCard) { this.cancelEdit(); return; }

      // Map col name to ProgramRecord field
      const fieldMap: Record<string, string> = {
        program: 'program',
        domain: 'domain',
        abllsCode: 'abllsCode',
        masterSheet: 'masterSheet',
        programSheet: 'programSheet',
        started: 'started',
        currentTarget: 'currentTarget',
        active: 'active',
        notes: 'notes',
        dueDate: 'dueDate',
        targetMastery: 'targetMastery',
      };
      const field = fieldMap[col];
      if (!field) { this.cancelEdit(); return; }

      // Update domain key when domain changes
      if (col === 'domain') {
        const dkMap: Record<string, string> = {
          Math: 'math', 'Visual Performance': 'visual', Reading: 'reading',
          Language: 'language', 'Receptive Language': 'receptive',
          Requests: 'requests', 'Fine Motor': 'finemotor',
          Labeling: 'labeling', 'Gross Motor': 'grossmotor', Social: 'social',
        };
        (srcCard as any).domainKey = dkMap[val] || 'math';
      }

      // Convert number fields
      if (col === 'targetMastery') {
        (srcCard as any)[field] = parseInt(val) || 0;
      } else {
        (srcCard as any)[field] = val;
      }
      this.cancelEdit();

      // Persist to realm
      try {
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const adminRealm = new URL('./', import.meta.url).href;
          await new SaveCardCommand(ctx).execute({ card: srcCard, realm: adminRealm });
          console.log(`[Admin] updated ProgramRecord field ${field} = "${val}"`);
          await this.loadPrograms();
        }
      } catch (err: any) {
        console.warn('[Admin] failed to update ProgramRecord:', err?.message ?? err);
      }
    };

    onEditKeydown = (prog: any, col: string, e: KeyboardEvent) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this.commitEdit(prog, col);
      } else if (e.key === 'Escape') {
        this.cancelEdit();
      }
    };

    onEditBlur = (prog: any, col: string) => {
      // Small delay to allow click events on select options to fire
      setTimeout(() => this.commitEdit(prog, col), 150);
    };

    setNewProgName = (e: Event) => {
      this.newProgName = (e.target as HTMLInputElement).value;
    };
    setNewProgDomain = (e: Event) => {
      const v = (e.target as HTMLSelectElement).value;
      const map: Record<string, string> = {
        Math: 'math',
        'Visual Performance': 'visual',
        Reading: 'reading',
        Language: 'language',
        'Receptive Language': 'receptive',
        Requests: 'requests',
        'Fine Motor': 'finemotor',
        Labeling: 'labeling',
        'Gross Motor': 'grossmotor',
        Social: 'social',
      };
      this.newProgDomain = v;
      this.newProgDomainKey = map[v] || 'math';
    };
    setNewProgAblls = (e: Event) => {
      this.newProgAblls = (e.target as HTMLInputElement).value;
    };
    setNewProgMaster = (e: Event) => {
      this.newProgMaster = (e.target as HTMLSelectElement).value;
    };
    setNewProgSheet = (e: Event) => {
      this.newProgSheet = (e.target as HTMLSelectElement).value;
    };
    setNewProgStarted = (e: Event) => {
      this.newProgStarted = (e.target as HTMLInputElement).value;
    };
    setNewProgTarget = (e: Event) => {
      this.newProgTarget = (e.target as HTMLInputElement).value;
    };
    setNewProgActive = (e: Event) => {
      this.newProgActive = (e.target as HTMLSelectElement).value;
    };
    setNewProgNotes = (e: Event) => {
      this.newProgNotes = (e.target as HTMLInputElement).value;
    };
    setNewProgDueDate = (e: Event) => {
      this.newProgDueDate = (e.target as HTMLInputElement).value;
    };
    setNewProgTargetMastery = (e: Event) => {
      this.newProgTargetMastery = parseInt((e.target as HTMLInputElement).value) || 80;
    };
    addMaterial = () => {
      this.newProgMaterials = [...this.newProgMaterials, { materialType: 'Primary', name: '', detail: '' }];
    };
    removeMaterial = (idx: number) => {
      this.newProgMaterials = this.newProgMaterials.filter((_, i) => i !== idx);
    };
    setMatType = (idx: number, e: Event) => {
      const mats = [...this.newProgMaterials];
      mats[idx] = { ...mats[idx], materialType: (e.target as HTMLSelectElement).value };
      this.newProgMaterials = mats;
    };
    setMatName = (idx: number, e: Event) => {
      const mats = [...this.newProgMaterials];
      mats[idx] = { ...mats[idx], name: (e.target as HTMLInputElement).value };
      this.newProgMaterials = mats;
    };
    setMatDetail = (idx: number, e: Event) => {
      const mats = [...this.newProgMaterials];
      mats[idx] = { ...mats[idx], detail: (e.target as HTMLInputElement).value };
      this.newProgMaterials = mats;
    };

    submitProgram = async (e: Event) => {
      e.preventDefault();
      if (!this.newProgName.trim()) return;
      if (!this.piSelectedStudentName) return;

      // Determine which students to create for
      const targetStudents = this.isAllStudentsSelected
        ? this.piStudentList.map((s) => ({ name: s.name, id: s.id }))
        : [{ name: this.piSelectedStudentName, id: this.piSelectedStudentId }];

      const baseProg = {
        program: this.newProgName,
        domain: this.newProgDomain,
        domainKey: this.newProgDomainKey,
        abllsCode: this.newProgAblls || '',
        masterSheet: this.newProgMaster,
        programSheet: this.newProgSheet,
        started: this.newProgStarted || '',
        currentTarget: this.newProgTarget || '',
        active: this.newProgActive,
        notes: this.newProgNotes,
      };
      // Persist as ProgramRecord card(s) — one per target student
      try {
        const ctx = this.hostCommandContext;
        if (ctx) {
          const { ProgramRecord: PR, ProgramMaterial } = await import('./program-record');
          const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
          const adminRealm = new URL('./', import.meta.url).href;

          for (const student of targetStudents) {
            const card = new PR();
            (card as any).program = baseProg.program;
            (card as any).domain = baseProg.domain;
            (card as any).domainKey = baseProg.domainKey;
            (card as any).abllsCode = baseProg.abllsCode;
            (card as any).masterSheet = baseProg.masterSheet;
            (card as any).programSheet = baseProg.programSheet;
            (card as any).started = baseProg.started;
            (card as any).currentTarget = baseProg.currentTarget;
            (card as any).active = baseProg.active;
            (card as any).notes = baseProg.notes;
            (card as any).studentName = student.name;
            (card as any).studentId = student.id;
            (card as any).dueDate = this.newProgDueDate;
            (card as any).targetMastery = this.newProgTargetMastery;
            if (this.newProgMaterials.length > 0) {
              const mats = this.newProgMaterials.filter((m) => m.name.trim()).map((m) => {
                const mat = new ProgramMaterial();
                (mat as any).materialType = m.materialType;
                (mat as any).name = m.name;
                (mat as any).detail = m.detail;
                return mat;
              });
              (card as any).materials = mats;
            }
            await new SaveCardCommand(ctx).execute({ card, realm: adminRealm });
            console.log(`[Admin] saved ProgramRecord: ${baseProg.program} for ${student.name}`);
          }
          await this.loadPrograms();

          // Auto-push the just-created Programs to Classroom Goal (Approach C — fire-and-forget)
          // NOTE: HoS is NOT pushed here — Classroom Goal holds live currentMastery
          // data, and Classroom's own _autoSyncGoalMastery pushes Goal→HoS separately.
          const justPushed = targetStudents.map((s) => ({
            program: baseProg.program,
            notes: baseProg.notes,
            studentName: s.name,
            studentId: s.id,
            targetMastery: this.newProgTargetMastery,
            started: baseProg.started,
            dueDate: this.newProgDueDate,
          }));
          syncProgramsToClassroom({
            programs: justPushed,
            ctx,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          }).then((r) => {
            if (r.created + r.updated > 0) {
              console.log(`[Admin-Classroom] auto-pushed Goal "${baseProg.program}" to ${r.created + r.updated} student(s)`);
            } else if (r.failed > 0) {
              console.warn(`[Admin-Classroom] auto-push Goals failed:`, r.errors);
            }
          }).catch((e) => console.warn('[Admin-Classroom] auto-push exception:', e));
        }
      } catch (err: any) {
        console.warn('[Admin] failed to save ProgramRecord:', err?.message ?? err);
      }
      this.showAddProgramForm = false;
      this.newProgName = '';
      this.newProgDomain = 'Math';
      this.newProgDomainKey = 'math';
      this.newProgAblls = '';
      this.newProgMaster = 'Yes';
      this.newProgSheet = 'Yes';
      this.newProgStarted = '';
      this.newProgTarget = '';
      this.newProgActive = 'Yes';
      this.newProgNotes = '';
      this.newProgDueDate = '';
      this.newProgTargetMastery = 80;
      this.newProgMaterials = [];
    };

    // ── Live classroom realm queries ─────────────────────────────────
    // ⁷ Query all Student cards from classroom realm dynamically
    // ── Students (from embedded studentRefs — never wiped by auto-save) ──
    get trackingStudents(): Array<{
      name: string;
      goal: string;
      initials: string;
    }> {
      // Build from fetched profiles (real data from HoS)
      if (this.fetchedProfiles.length > 0) {
        return this.fetchedProfiles.map((p: any) => {
          const ident = p?.identity;
          const first = String(ident?.firstName ?? '');
          const last = String(ident?.lastName ?? '');
          const name = `${first} ${last}`.trim() || 'Unknown';
          const initials = (first.charAt(0) + last.charAt(0)).toUpperCase() || '??';
          return { name, goal: '', initials };
        });
      }
      // Fallback to manual studentRefs
      const refs = this.args.model.studentRefs || [];
      return refs.map((s: any) => ({
        name: s?.name || 'Unknown Student',
        goal: s?.iepGoal || 'No current goal',
        initials: s?.initials || '??',
      }));
    }

    // Match LearningGoal cards to a student by name
    goalsForStudent = (studentName: string): any[] => {
      const goals = this.enrichedGoals.length > 0 ? this.enrichedGoals : (this.dynamicGoals.length > 0 ? this.dynamicGoals : (this.args.model.learningGoals || []));
      console.log(`[Admin] goalsForStudent("${studentName}"): checking ${goals.length} goals`);
      const sLower = (studentName || '').toLowerCase().trim();
      const sFirst = sLower.split(' ')[0];
      if (!sFirst) return [];

      return goals.filter((g: any) => {
        // Check studentName field (set by admin)
        const gStudentName = String(g?.studentName ?? '').toLowerCase().trim();
        if (gStudentName && gStudentName === sLower) return true;
        if (gStudentName && gStudentName.includes(sFirst)) return true;
        // Check linked student
        const gLinkedName = (g?.student?.name || g?.student?.firstName || '').toLowerCase();
        if (gLinkedName && gLinkedName.includes(sFirst)) return true;
        return false;
      });
    };

    // (goalsForStudent defined above)

    // ¹⁵ Class Progress Overview — now driven by classroom LearningGoal.currentMastery
    get cpoStudentCards(): Array<{
      name: string;
      initials: string;
      goalCount: number;
      avgProgress: number;
      sparkPoints: string;
      trending: string;
    }> {
      const students = this.trackingStudents;

      return students.map((s: any) => {
        const myGoals = this.goalsForStudent(s.name);
        const goalCount = myGoals.length;
        const progresses = myGoals
          .map((g: any) => Math.min(100, g.progressPercent || 0))
          .filter((p: number) => p > 0);
        const avgProgress = progresses.length
          ? Math.round(
              progresses.reduce((a: number, b: number) => a + b, 0) /
                progresses.length,
            )
          : 0;

        const allEvScores: number[] = [];
        for (const g of myGoals) {
          for (const ev of g.evidence || []) {
            const m = (ev.score || '').match(/^(\d+)\/(\d+)$/);
            if (m) allEvScores.push(Math.min(1, parseInt(m[1]) / parseInt(m[2])));
          }
        }
        const recent = allEvScores.slice(-7);
        let sparkPoints = '0,15 120,15';
        if (recent.length >= 2) {
          sparkPoints = recent
            .map((sc: number, i: number) => {
              const x = Math.round(i * (120 / (recent.length - 1)));
              const y = Math.round(28 - sc * 26);
              return `${x},${y}`;
            })
            .join(' ');
        }
        let delta = 0;
        if (allEvScores.length >= 2) {
          const mid = Math.floor(allEvScores.length / 2);
          const avg1 =
            allEvScores.slice(0, mid).reduce((a, b) => a + b, 0) / mid;
          const avg2 =
            allEvScores.slice(mid).reduce((a, b) => a + b, 0) /
            (allEvScores.length - mid);
          delta = Math.round((avg2 - avg1) * 100);
        }
        return {
          name: s.name,
          initials: s.initials,
          goalCount,
          avgProgress:
            avgProgress ||
            Math.round(
              (allEvScores.length
                ? allEvScores.reduce((a, b) => a + b, 0) / allEvScores.length
                : 0) * 100,
            ),
          sparkPoints,
          trending: delta >= 0 ? 'up' : 'down',
        };
      });
    }

    get selectedTrackingStudentObj() {
      const list = this.trackingStudents;
      if (!list.length) return null;
      const idx = Math.min(this.selectedTrackingStudentIndex, list.length - 1);
      return list[idx] ?? null;
    }

    selectTrackingStudent = (idx: number) => {
      this.selectedTrackingStudentIndex = idx;
      this.showStudentDropdown = false;
    };

    toggleStudentDropdown = () => {
      this.showStudentDropdown = !this.showStudentDropdown;
      if (this.showStudentDropdown) this.studentSearchQuery = '';
    };

    closeStudentDropdown = () => {
      this.showStudentDropdown = false;
    };

    setStudentSearch = (e: Event) => {
      this.studentSearchQuery = (e.target as HTMLInputElement).value;
    };

    get filteredTrackingStudents() {
      const q = this.studentSearchQuery.trim().toLowerCase();
      const all = this.trackingStudents;
      if (!q)
        return all.map((s: any, i: number) => ({ ...s, originalIndex: i }));
      return all
        .map((s: any, i: number) => ({ ...s, originalIndex: i }))
        .filter((s: any) => s.name.toLowerCase().includes(q));
    }

    // ¹² Per-student timeline — built from classroom LearningGoal.currentMastery (0–100%)
    // Each student's goals are matched by exact student card ID
    // ── Goal selector for timeline ──
    @tracked selectedTimelineGoalIndex = 0;

    get timelineGoals() {
      const student = this.selectedTrackingStudentObj;
      if (!student) return [];
      return this.goalsForStudent(student.name);
    }

    get selectedTimelineGoal() {
      const goals = this.timelineGoals;
      if (goals.length === 0) return null;
      const idx = Math.min(this.selectedTimelineGoalIndex, goals.length - 1);
      return goals[idx] ?? null;
    }

    selectTimelineGoal = (e: Event) => {
      this.selectedTimelineGoalIndex = parseInt((e.target as HTMLSelectElement).value) || 0;
    };

    // Build timeline data points for the selected goal
    get timelineDataPoints(): Array<{ dateStr: string; date: Date; pct: number; score: string }> {
      const goal = this.selectedTimelineGoal;
      if (!goal) return [];

      const evidence = goal.evidence || goal.evidenceEntries || [];
      const points: Array<{ dateStr: string; date: Date; pct: number; score: string }> = [];

      const parseDate = (dateStr: string): Date | null => {
        if (!dateStr) return null;
        const now = new Date();
        // Try "Mon DD, YYYY" format
        const monthMap: Record<string, number> = { Jan:0, Feb:1, Mar:2, Apr:3, May:4, Jun:5, Jul:6, Aug:7, Sep:8, Oct:9, Nov:10, Dec:11 };
        const m = dateStr.match(/^(\w+)\s+(\d+),?\s*(\d{4})?/);
        if (m && monthMap[m[1]] !== undefined) {
          const year = m[3] ? parseInt(m[3]) : now.getFullYear();
          return new Date(year, monthMap[m[1]], parseInt(m[2]));
        }
        // Try ISO format
        const iso = new Date(dateStr);
        if (!isNaN(iso.getTime())) return iso;
        if (dateStr.toLowerCase().startsWith('today')) return new Date(now.getFullYear(), now.getMonth(), now.getDate());
        return null;
      };

      for (const ev of evidence) {
        const scoreStr = ev.score ?? `${ev.scoreNumerator ?? 0}/${ev.scoreDenominator ?? 0}`;
        const sm = scoreStr.match(/^(\d+)\/(\d+)$/);
        if (!sm) continue;
        const pct = Math.min(100, Math.round((parseInt(sm[1]) / parseInt(sm[2])) * 100));
        const date = parseDate(ev.date ?? '');
        if (!date) continue;
        points.push({
          dateStr: `${date.getMonth() + 1}/${date.getDate()}`,
          date,
          pct,
          score: scoreStr,
        });
      }

      // Sort by date
      points.sort((a, b) => a.date.getTime() - b.date.getTime());
      return points;
    }

    // Build SVG chart data
    get timelineChartData() {
      const points = this.timelineDataPoints;
      if (points.length === 0) return { polyline: '', dots: [], labels: [], gapLines: [], hasData: false };

      const W = 700, H = 200, padL = 60, padR = 20, padT = 20, padB = 40;
      const chartW = W - padL - padR;
      const chartH = H - padT - padB;

      const dots: Array<{ cx: number; cy: number; pct: number; score: string; label: string }> = [];

      // Find date range
      const minDate = points[0].date.getTime();
      const maxDate = points[points.length - 1].date.getTime();
      const dateRange = maxDate - minDate || 1;

      for (const p of points) {
        const xFrac = points.length === 1 ? 0.5 : (p.date.getTime() - minDate) / dateRange;
        const cx = padL + xFrac * chartW;
        const cy = padT + chartH - (p.pct / 100) * chartH;
        dots.push({ cx, cy, pct: p.pct, score: p.score, label: p.dateStr });
      }

      const polyline = dots.map(d => `${d.cx},${d.cy}`).join(' ');

      // X-axis labels (use unique dates)
      const labels = dots.map(d => ({ x: d.cx, label: d.label }));

      // Find gaps: if consecutive points are more than 2 days apart, draw red line
      const gapLines: Array<{ x: number }> = [];
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      for (let i = 1; i < points.length; i++) {
        const dayDiff = (points[i].date.getTime() - points[i - 1].date.getTime()) / (1000 * 60 * 60 * 24);
        if (dayDiff > 2) {
          // Only show gap line if it's in the past (not future)
          const gapDate = new Date(points[i - 1].date.getTime() + (points[i].date.getTime() - points[i - 1].date.getTime()) / 2);
          if (gapDate <= today) {
            const xFrac = (gapDate.getTime() - minDate) / dateRange;
            gapLines.push({ x: padL + xFrac * chartW });
          }
        }
      }

      return { polyline, dots, labels, gapLines, hasData: true };
    }

    get timelineStats() {
      const points = this.timelineDataPoints;
      if (points.length === 0) return { levelGain: '0', observations: 0, toTarget: '0%' };
      const first = points[0].pct;
      const last = points[points.length - 1].pct;
      const gain = ((last - first) / 100).toFixed(1);
      const goal = this.selectedTimelineGoal;
      const target = goal?.targetMastery ?? 80;
      const toTarget = `${Math.min(100, Math.round((last / target) * 100))}%`;
      return { levelGain: (parseFloat(gain) >= 0 ? '+' : '') + gain, observations: points.length, toTarget };
    }

    // Keep old getter signature for backward compat but simplified
    get allStudentObservations(): any[] {
      return []; // No longer used — timeline uses timelineDataPoints instead
    }

    // (old allStudentObservations code removed — timeline uses timelineDataPoints)

    // Compute active date range from preset or custom
    get activeDateRange(): { start: Date; end: Date; label: string } {
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const fmt = (d: Date) =>
        `${monthNames[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;

      if (
        this.dateRangePreset === 'custom' &&
        this.customStartDate &&
        this.customEndDate
      ) {
        const s = new Date(this.customStartDate + 'T00:00:00');
        const e = new Date(this.customEndDate + 'T00:00:00');
        return { start: s, end: e, label: `${fmt(s)} – ${fmt(e)}` };
      }

      let start: Date;
      let end = today;
      switch (this.dateRangePreset) {
        case 'week': {
          const day = today.getDay();
          start = new Date(today);
          start.setDate(today.getDate() - (day === 0 ? 6 : day - 1)); // Monday
          break;
        }
        case 'month':
          start = new Date(today.getFullYear(), today.getMonth(), 1);
          break;
        case '30days':
          start = new Date(today);
          start.setDate(today.getDate() - 30);
          break;
        case 'semester':
        default: {
          const m = today.getMonth();
          if (m >= 8 || m <= 0) {
            // Sep–Jan → Fall
            start = new Date(
              m >= 8 ? today.getFullYear() : today.getFullYear() - 1,
              8,
              1,
            );
            end = new Date(
              m >= 8 ? today.getFullYear() + 1 : today.getFullYear(),
              0,
              31,
            );
            if (end > today) end = today;
          } else {
            // Feb–Jun → Spring
            start = new Date(today.getFullYear(), 1, 1);
            end = new Date(today.getFullYear(), 5, 30);
            if (end > today) end = today;
          }
          break;
        }
      }
      return { start, end, label: `${fmt(start)} – ${fmt(end)}` };
    }

    // Filter + layout observations for the active date range
    get currentTrackingPeriod(): {
      label: string;
      skill: string;
      points: any[];
      stats: { levelGain: string; observations: number; toTarget: string };
      empty: boolean;
    } {
      const { start, end, label } = this.activeDateRange;
      const studentIdx = Math.min(
        this.selectedTrackingStudentIndex,
        this.allStudentObservations.length - 1,
      );
      const allObs = this.allStudentObservations[studentIdx] || [];

      const filtered = allObs.filter((o) => o.date >= start && o.date <= end);
      if (!filtered.length) {
        return {
          label,
          skill: '',
          points: [],
          stats: { levelGain: '—', observations: 0, toTarget: '—' },
          empty: true,
        };
      }

      // Determine dominant skill in range
      const skillCounts: Record<string, number> = {};
      for (const o of filtered) {
        skillCounts[o.skill] = (skillCounts[o.skill] || 0) + 1;
      }
      let skill = filtered[0].skill;
      let maxCount = 0;
      for (const [s, c] of Object.entries(skillCounts)) {
        if (c > maxCount) {
          maxCount = c;
          skill = s;
        }
      }

      // Layout points evenly across chart width (60–660)
      const n = filtered.length;
      const points = filtered.map((o, i) => ({
        x: n === 1 ? 375 : Math.round(80 + i * (560 / (n - 1))),
        y: o.y,
        date: o.dateStr,
      }));

      // Compute stats from y values (y is inverted: 190 = 0%, 10 = 100%)
      const firstY = filtered[0].y;
      const lastY = filtered[filtered.length - 1].y;
      // Convert y to percentage: (190 - y) / 180 * 100
      const firstPct = (190 - firstY) / 180;
      const lastPct = (190 - lastY) / 180;
      const levelGain = ((lastPct - firstPct) * 5).toFixed(1); // 5 mastery levels
      const toTarget = Math.round(lastPct * 100);

      return {
        label,
        skill,
        points,
        stats: {
          levelGain: Number(levelGain) >= 0 ? `+${levelGain}` : levelGain,
          observations: filtered.length,
          toTarget: `${toTarget}%`,
        },
        empty: false,
      };
    }

    get chartPointsStr() {
      const pts = this.currentTrackingPeriod.points;
      return pts.length ? pts.map((p: any) => `${p.x},${p.y}`).join(' ') : '';
    }

    setDatePreset = (preset: string) => {
      this.dateRangePreset = preset;
    };
    isActivePreset = (preset: string) => this.dateRangePreset === preset;
    setCustomStart = (e: Event) => {
      this.customStartDate = (e.target as HTMLInputElement).value;
      this.dateRangePreset = 'custom';
    };
    setCustomEnd = (e: Event) => {
      this.customEndDate = (e.target as HTMLInputElement).value;
      this.dateRangePreset = 'custom';
    };

    isSelectedTrackingStudent = (idx: number) => {
      return idx === this.selectedTrackingStudentIndex;
    };

    // ── CPO student card search + pagination ──
    @tracked cpoSearchQuery = '';
    @tracked cpoPage = 0;
    cpoPageSize = 4;

    setCpoSearch = (e: Event) => { this.cpoSearchQuery = (e.target as HTMLInputElement).value; this.cpoPage = 0; };
    nextCpoPage = () => { if ((this.cpoPage + 1) * this.cpoPageSize < this.filteredCpoCards.length) this.cpoPage++; };
    prevCpoPage = () => { if (this.cpoPage > 0) this.cpoPage--; };

    get filteredCpoCards() {
      const q = this.cpoSearchQuery.toLowerCase().trim();
      const all = this.cpoStudentCards;
      if (!q) return all;
      return all.filter((c: any) => c.name.toLowerCase().includes(q));
    }

    get pagedCpoCards() {
      const start = this.cpoPage * this.cpoPageSize;
      return this.filteredCpoCards.slice(start, start + this.cpoPageSize);
    }

    get showCpoPagination() { return this.filteredCpoCards.length > this.cpoPageSize; }
    get cantPrevCpo() { return this.cpoPage <= 0; }
    get cantNextCpo() { return (this.cpoPage + 1) * this.cpoPageSize >= this.filteredCpoCards.length; }
    get cpoPageLabel() {
      const total = Math.ceil(this.filteredCpoCards.length / this.cpoPageSize) || 1;
      return `${this.cpoPage + 1} / ${total}`;
    }

    selectCpoStudent = (idx: number) => {
      // idx is relative to pagedCpoCards — find the original index by name
      const card = this.pagedCpoCards[idx];
      if (!card) return;
      const allCards = this.cpoStudentCards;
      const originalIdx = allCards.findIndex((c: any) => c.name === card.name);
      this.selectedTrackingStudentIndex = originalIdx >= 0 ? originalIdx : 0;
    };

    deleteRowWithConfirm = (isLocal: boolean, index: number) => {
      this.requestConfirm('Delete this observation?', () =>
        this.deleteRow(isLocal, index),
      );
    };

    bulkDeleteWithConfirm = () => {
      const n = this.selectionCount;
      this.requestConfirm(`Delete ${n} observation${n === 1 ? '' : 's'}?`, () =>
        this.bulkDelete(),
      );
    };

    // ── Learning Goals ──────────────────────────────────────────────
    openAddGoalModal = () => {
      this.newGoalTitle = '';
      this.newGoalDesc = '';
      this.newGoalStudent = '';
      this.newGoalDomain = 'Mathematics';
      this.newGoalPriority = 'Medium';
      this.newGoalCurrentMastery = 1;
      this.newGoalTargetMastery = 4;
      this.newGoalDueDate = '';
      this.newGoalStandard = '';
      this.goalSaveState = 'input';
      this.goalSaveError = '';
      this.showAddGoalForm = true;
    };
    closeAddGoalModal = () => {
      this.showAddGoalForm = false;
    };

    setGoalTitle = (e: Event) => {
      this.newGoalTitle = (e.target as HTMLInputElement).value;
    };
    setGoalDesc = (e: Event) => {
      this.newGoalDesc = (e.target as HTMLTextAreaElement).value;
    };
    setGoalStudent = (e: Event) => {
      this.newGoalStudent = (e.target as HTMLSelectElement).value;
    };
    setGoalDomain = (e: Event) => {
      this.newGoalDomain = (e.target as HTMLSelectElement).value;
    };
    setGoalPriority = (e: Event) => {
      this.newGoalPriority = (e.target as HTMLSelectElement).value;
    };
    setGoalCurrentMastery = (e: Event) => {
      this.newGoalCurrentMastery =
        Math.min(100, Math.max(0, parseInt((e.target as HTMLInputElement).value) || 0));
    };
    setGoalTargetMastery = (e: Event) => {
      this.newGoalTargetMastery =
        Math.min(100, Math.max(0, parseInt((e.target as HTMLInputElement).value) || 80));
    };
    setGoalDueDate = (e: Event) => {
      this.newGoalDueDate = (e.target as HTMLInputElement).value;
    };
    setGoalStandard = (e: Event) => {
      this.newGoalStandard = (e.target as HTMLInputElement).value;
    };

    get isGoalSaving() {
      return this.goalSaveState === 'saving';
    }
    get isGoalError() {
      return this.goalSaveState === 'error';
    }

    get studentOptions(): Array<{ id: string; name: string }> {
      return this.trackingStudents.map((s: any) => ({
        id: s.name,
        name: s.name,
      }));
    }

    get goalProgressPreview(): number {
      // currentMastery is already 0-100 percentage
      return this.newGoalCurrentMastery || 0;
    }

    isGoalDomainSelected = (d: string) => this.newGoalDomain === d;
    isGoalPrioritySelected = (p: string) => this.newGoalPriority === p;
    isGoalCurrentSelected = (n: number) => this.newGoalCurrentMastery === n;
    isGoalTargetSelected = (n: number) => this.newGoalTargetMastery === n;

    saveGoalTask = restartableTask(async () => {
      if (!this.newGoalTitle.trim()) return;
      if (!this.newGoalStudent) {
        this.goalSaveError = 'Please select a student first';
        this.goalSaveState = 'error';
        return;
      }
      this.goalSaveState = 'saving';
      this.goalSaveError = '';
      try {
        const commandContext = (this.args as any).context?.commandContext;
        if (!commandContext) throw new Error('Command context not available');
        const cardId = this.args.model.id || '';
        const idUrl = new URL(cardId);
        const segments = idUrl.pathname.split('/').filter(Boolean);
        const realmPath = segments.slice(0, -2).join('/');
        const realmUrl = `${idUrl.origin}/${realmPath}/`;

        const input = new (await new CreateLearningGoalCommand(
          commandContext,
        ).getInputType())();
        input.goalTitle = this.newGoalTitle;
        input.description = this.newGoalDesc;
        input.domain = this.newGoalDomain;
        input.priority = this.newGoalPriority;
        input.currentMastery = this.newGoalCurrentMastery;
        input.targetMastery = this.newGoalTargetMastery;
        input.dueDate = this.newGoalDueDate;
        input.standardAlignment = this.newGoalStandard;
        input.studentCardId = this.newGoalStudent;
        input.realmUrl = realmUrl;

        await new CreateLearningGoalCommand(commandContext).execute(input);

        // Add to local list for immediate UI
        this.localGoals = [
          ...this.localGoals,
          {
            goalTitle: this.newGoalTitle,
            domain: this.newGoalDomain,
            priority: this.newGoalPriority,
            currentMastery: this.newGoalCurrentMastery,
            targetMastery: this.newGoalTargetMastery,
            dueDate: this.newGoalDueDate,
            standardAlignment: this.newGoalStandard,
          },
        ];
        this.showAddGoalForm = false;
        this.goalSaveState = 'done';
        // Reload from realm
        this.loadGoals();
      } catch (err: any) {
        this.goalSaveError = err?.message || 'Save failed';
        this.goalSaveState = 'error';
      }
    });

    triggerSaveGoal = () => {
      this.saveGoalTask.perform();
    };

    get goalMasteryLabel() {
      const names = [
        'Emerging',
        'Developing',
        'Approaching',
        'Proficient',
        'Mastered',
      ];
      return (n: number) => names[(n || 1) - 1] || '';
    }

    <template>
      <div class='admin-board'>

        <!-- Cross-workspace nav -->
        <nav class='cross-nav'>
          <a class='cross-nav-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/Classroom/classroom-2a'>Classroom</a>
          <a class='cross-nav-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/HoSDashboard/main'>HoS Dashboard</a>
          <a class='cross-nav-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main'>Parent Report</a>
        </nav>

        <!-- Header -->
        <header class='admin-header'>
          <div class='admin-title-block'>
            <div class='realm-badge'>
              <svg
                width='8'
                height='8'
                viewBox='0 0 8 8'
                fill='currentColor'
              ><circle cx='4' cy='4' r='3' /></svg>
              Admin Realm
            </div>
            <h1 class='admin-title'>{{@model.title}}</h1>
          </div>
        </header>

        <!-- Class Progress Overview -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag chart'>Chart</span>
            <span class='section-name'>Class Progress Overview</span>
            <span class='staff-count'>Auto-synced in real-time from Classroom observations</span>
          </div>
          <div class='cpo-search-bar'>
            <input class='cpo-search-input' type='text' placeholder='Search students...' value={{this.cpoSearchQuery}} {{on 'input' this.setCpoSearch}} />
          </div>
          <div class='cpo-grid'>
            {{#each this.pagedCpoCards as |card index|}}
              <button
                class='cpo-card
                  {{if (eq card.trending "down") "alert"}}
                  {{if (this.isSelectedTrackingStudent index) "selected"}}'
                {{on 'click' (fn this.selectCpoStudent index)}}
              >
                <div class='cpo-student-row'>
                  <div class='cpo-avatar' style='background:#f5e6d3'>
                    <span class='cpo-initials'>{{card.initials}}</span>
                  </div>
                  <span class='cpo-name'>{{card.name}}</span>
                  <span class='cpo-delta {{card.trending}}'>
                    {{#if (eq card.trending 'up')}}↑{{else}}↓{{/if}}
                    {{card.delta}}%
                  </span>
                </div>
                <svg
                  class='cpo-sparkline'
                  viewBox='0 0 120 30'
                  preserveAspectRatio='none'
                >
                  <polyline
                    points={{card.sparkPoints}}
                    fill='none'
                    stroke='{{if
                      (eq card.trending "down")
                      "#e05d50"
                      "#2a9d8f"
                    }}'
                    stroke-width='2'
                  />
                </svg>
                <div class='cpo-stats'>
                  <span>{{card.goalCount}} goals</span>
                  <span
                    class='{{if (eq card.trending "down") "cpo-stat-warn"}}'
                  >{{card.avgProgress}}% progress</span>
                </div>
              </button>
            {{/each}}
          </div>
          {{#if this.showCpoPagination}}
            <div class='cpo-pagination'>
              <button class='cpo-page-btn' type='button' disabled={{this.cantPrevCpo}} {{on 'click' this.prevCpoPage}}>Prev</button>
              <span class='cpo-page-label'>{{this.cpoPageLabel}}</span>
              <button class='cpo-page-btn' type='button' disabled={{this.cantNextCpo}} {{on 'click' this.nextCpoPage}}>Next</button>
            </div>
          {{/if}}
        </section>

        <!-- Tracking, Charts & Tables -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag tracking'>Tracking</span>
            <span class='section-name'>Mastery Progress Timeline</span>
            <span class='staff-count'>How a student's skills develop over weeks</span>
          </div>
          <div class='tracking-card'>
            {{!-- Student + Goal selector --}}
            <div class='tl-header'>
              <div class='tl-student-info'>
                {{#if this.selectedTrackingStudentObj}}
                  <span class='tl-student-name'>{{this.selectedTrackingStudentObj.name}}</span>
                {{else}}
                  <span class='tl-student-name'>No student selected</span>
                {{/if}}
              </div>
              <div class='tl-goal-selector'>
                {{#if this.timelineGoals.length}}
                  <select class='tl-goal-select' {{on 'change' this.selectTimelineGoal}}>
                    {{#each this.timelineGoals as |g idx|}}
                      <option value={{idx}}>{{g.goalTitle}}</option>
                    {{/each}}
                  </select>
                {{else}}
                  <span class='tl-no-goals'>No goals — Fetch Progress first</span>
                {{/if}}
              </div>
            </div>

            {{!-- Chart --}}
            {{#if this.selectedTimelineGoal}}
              <div class='tl-goal-title'>{{this.selectedTimelineGoal.goalTitle}}</div>
            {{/if}}
            {{#if this.timelineChartData.hasData}}
              <div class='tracking-chart'>
                <svg viewBox='0 0 700 200' preserveAspectRatio='xMidYMid meet' class='tl-svg'>
                  {{!-- Grid lines --}}
                  <line x1='60' y1='20' x2='680' y2='20' stroke='#ebe7e3' stroke-width='1'/>
                  <line x1='60' y1='55' x2='680' y2='55' stroke='#f5f2ef' stroke-width='1'/>
                  <line x1='60' y1='90' x2='680' y2='90' stroke='#f5f2ef' stroke-width='1'/>
                  <line x1='60' y1='125' x2='680' y2='125' stroke='#f5f2ef' stroke-width='1'/>
                  <line x1='60' y1='160' x2='680' y2='160' stroke='#ebe7e3' stroke-width='1'/>
                  {{!-- Y-axis labels --}}
                  <text x='50' y='24' fill='#8a8279' font-size='10' text-anchor='end'>100%</text>
                  <text x='50' y='59' fill='#8a8279' font-size='10' text-anchor='end'>75%</text>
                  <text x='50' y='94' fill='#8a8279' font-size='10' text-anchor='end'>50%</text>
                  <text x='50' y='129' fill='#8a8279' font-size='10' text-anchor='end'>25%</text>
                  <text x='50' y='164' fill='#8a8279' font-size='10' text-anchor='end'>0%</text>
                  {{!-- Gap lines (red) --}}
                  {{#each this.timelineChartData.gapLines as |gap|}}
                    <line x1={{gap.x}} y1='18' x2={{gap.x}} y2='162' stroke='#e05d50' stroke-width='1.5' opacity='0.6'/>
                  {{/each}}
                  {{!-- Data line --}}
                  <polyline points={{this.timelineChartData.polyline}} fill='none' stroke='#1a1816' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'/>
                  {{!-- Data dots + labels --}}
                  {{#each this.timelineChartData.dots as |dot|}}
                    <circle cx={{dot.cx}} cy={{dot.cy}} r='5' fill='#1a1816'/>
                    <text x={{dot.cx}} y='185' fill='#8a8279' font-size='9' text-anchor='middle'>{{dot.label}}</text>
                  {{/each}}
                </svg>
                <div class='tl-x-label'>Session</div>
              </div>
            {{else}}
              <div class='tl-empty'>
                <div class='tl-empty-icon'>
                  <svg width='32' height='32' viewBox='0 0 32 32' fill='none' stroke='#c0b8af' stroke-width='1.5'><rect x='4' y='8' width='24' height='18' rx='2'/><polyline points='4,20 12,14 18,18 28,10'/></svg>
                </div>
                <span class='tl-empty-text'>No data for this period</span>
                <span class='tl-empty-sub'>Record activities in the classroom to see progress</span>
              </div>
            {{/if}}

            {{!-- Stats --}}
            <div class='tracking-stats'>
              <div class='tracking-stat'>
                <span class='stat-value good'>{{this.timelineStats.levelGain}}</span>
                <span class='stat-label'>Level gain (period)</span>
              </div>
              <div class='tracking-stat'>
                <span class='stat-value'>{{this.timelineStats.observations}}</span>
                <span class='stat-label'>Observations</span>
              </div>
              <div class='tracking-stat'>
                <span class='stat-value'>{{this.timelineStats.toTarget}}</span>
                <span class='stat-label'>To target</span>
              </div>
            </div>
          </div>
        </section>


        <!-- Observation Data Grid -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag table'>Table</span>
            <span class='section-name'>Observation Data Grid</span>
            <div class='type-counts'>
              {{#if this.typeCounts.Academic}}
                <span class='tc-badge academic'>{{this.typeCounts.Academic}}
                  Academic</span>
              {{/if}}
              {{#if this.typeCounts.Social}}
                <span class='tc-badge social'>{{this.typeCounts.Social}}
                  Social</span>
              {{/if}}
              {{#if this.typeCounts.Behavioral}}
                <span class='tc-badge behavioral'>{{this.typeCounts.Behavioral}}
                  Behavioral</span>
              {{/if}}
            </div>
          </div>
          <div class='data-table-wrap'>
            <div class='table-toolbar'>
              <div class='toolbar-left'>
                <input
                  class='search-input'
                  type='text'
                  placeholder='Search students, goals or staff…'
                  value={{this.searchQuery}}
                  {{on 'input' this.setSearch}}
                />
                <div class='table-filters'>
                  <button
                    class='filter-chip
                      {{if (this.isActiveType "All") "active"}}'
                    {{on 'click' (fn this.setTypeFilter 'All')}}
                  >All</button>
                  <button
                    class='filter-chip academic
                      {{if (this.isActiveType "Academic") "active"}}'
                    {{on 'click' (fn this.setTypeFilter 'Academic')}}
                  >Academic</button>
                  <button
                    class='filter-chip social
                      {{if (this.isActiveType "Social") "active"}}'
                    {{on 'click' (fn this.setTypeFilter 'Social')}}
                  >Social</button>
                  <button
                    class='filter-chip behavioral
                      {{if (this.isActiveType "Behavioral") "active"}}'
                    {{on 'click' (fn this.setTypeFilter 'Behavioral')}}
                  >Behavioral</button>
                  <select class='staff-filter-select' {{on 'change' this.setStaffFilter}}>
                    <option value='All Staff'>All Staff</option>
                    {{#each this.obsStaffList as |si|}}
                      <option value={{si}}>{{si}}</option>
                    {{/each}}
                  </select>
                </div>
              </div>
            </div>

            <table class='data-table'>
              <thead>
                <tr>
                  <th class='td-check'>
                    <input
                      type='checkbox'
                      checked={{this.isAllSelected}}
                      {{on 'change' this.toggleSelectAll}}
                    />
                  </th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'date')}}
                  >Date{{this.sortIndicator 'date'}}</th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'student')}}
                  >Student{{this.sortIndicator 'student'}}</th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'type')}}
                  >Type{{this.sortIndicator 'type'}}</th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'goal')}}
                  >Goal{{this.sortIndicator 'goal'}}</th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'score')}}
                  >Score{{this.sortIndicator 'score'}}</th>
                  <th
                    class='th-sortable'
                    {{on 'click' (fn this.toggleSort 'staff')}}
                  >Staff{{this.sortIndicator 'staff'}}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {{#each this.pagedRows as |item|}}
                  <tr
                    class='{{if (this.isFlaggedItem item) "row-flagged"}}
                      {{if (this.isEditing item) "row-editing"}}'
                  >
                    <td class='td-check'>
                      <input
                        type='checkbox'
                        checked={{this.isRowSelected item}}
                        {{on 'change' (fn this.toggleRowSelection item)}}
                      />
                    </td>
                    {{#if (this.isEditing item)}}
                      <td class='td-date'>{{item.data.date}}</td>
                      <td><input
                          class='cell-input'
                          value={{this.editValues.studentName}}
                          {{on 'input' this.setEditStudent}}
                        /></td>
                      <td>
                        <select
                          class='cell-select'
                          {{on 'change' this.setEditCategory}}
                        >
                          <option
                            value='Academic'
                            selected={{this.isEditCat 'Academic'}}
                          >Academic</option>
                          <option
                            value='Social'
                            selected={{this.isEditCat 'Social'}}
                          >Social</option>
                          <option
                            value='Behavioral'
                            selected={{this.isEditCat 'Behavioral'}}
                          >Behavioral</option>
                        </select>
                      </td>
                      <td><input
                          class='cell-input goal'
                          value={{this.editValues.linkedGoal}}
                          {{on 'input' this.setEditGoal}}
                        /></td>
                      <td><input
                          class='cell-input narrow'
                          value={{this.editValues.score}}
                          {{on 'input' this.setEditScore}}
                        /></td>
                      <td class='td-staff-edit'>
                        <input
                          class='cell-input initials'
                          maxlength='3'
                          value={{this.editValues.staffInitials}}
                          {{on 'input' this.setEditObsStaffInitials}}
                        />
                        <select
                          class='cell-select color'
                          {{on 'change' this.setEditObsStaffColor}}
                        >
                          <option
                            value='teal'
                            selected={{this.isEditColor 'teal'}}
                          >Teal</option>
                          <option
                            value='purple'
                            selected={{this.isEditColor 'purple'}}
                          >Purple</option>
                          <option
                            value='coral'
                            selected={{this.isEditColor 'coral'}}
                          >Coral</option>
                          <option
                            value='amber'
                            selected={{this.isEditColor 'amber'}}
                          >Amber</option>
                        </select>
                      </td>
                      <td class='td-actions'>
                        <button
                          class='action-btn save'
                          {{on 'click' (fn this.saveEdit item)}}
                        >✓</button>
                        <button
                          class='action-btn cancel-edit'
                          {{on 'click' this.cancelEdit}}
                        >✕</button>
                      </td>
                    {{else}}
                      <td class='td-date'>{{item.data.date}}</td>
                      <td class='td-student'>{{item.data.studentName}}</td>
                      <td class='td-type'>
                        <span
                          class='type-badge {{this.catLower item.data}}'
                        >{{item.data.category}}</span>
                      </td>
                      <td class='td-goal'>{{item.data.linkedGoal}}</td>
                      <td class='td-score'>
                        <span
                          class='score-badge
                            {{if (this.goodScore item.data) "good"}}'
                        >{{item.data.score}}</span>
                      </td>
                      <td class='td-staff'>
                        <span
                          class='staff-pip {{item.data.staffColor}}'
                        >{{item.data.staffInitials}}</span>
                      </td>
                      <td class='td-actions'>
                        <button
                          class='action-btn flag
                            {{if (this.isFlaggedItem item) "flagged"}}'
                          {{on 'click' (fn this.toggleFlag item)}}
                        >⚑</button>
                        <button
                          class='action-btn edit'
                          {{on 'click' (fn this.startEdit item)}}
                        >✎</button>
                        <button
                          class='action-btn dup'
                          {{on 'click' (fn this.duplicateRow item)}}
                        >⧉</button>
                        <button
                          class='del-btn'
                          {{on
                            'click'
                            (fn this.deleteRowWithConfirm item.isLocal item.idx)
                          }}
                        >✕</button>
                      </td>
                    {{/if}}
                  </tr>
                {{/each}}
                {{#if this.isEmpty}}
                  <tr><td colspan='8' class='empty-cell'>
                      {{#if this.isFiltered}}
                        <div class='empty-state'>
                          <div class='es-icon'>🔍</div>
                          <div class='es-msg'>No observations match your filters</div>
                          <button
                            class='es-reset'
                            {{on 'click' this.resetFilters}}
                          >Clear filters</button>
                        </div>
                      {{else}}
                        <div class='empty-state'>
                          <div class='es-icon'>📋</div>
                          <div class='es-msg'>No observations yet</div>
                          <div class='es-sub'>No observations have been recorded
                            yet</div>
                        </div>
                      {{/if}}
                    </td></tr>
                {{/if}}
              </tbody>
            </table>
            <div class='table-footer'>
              {{#if this.hasSelection}}
                <button
                  class='table-btn danger'
                  {{on 'click' this.bulkDeleteWithConfirm}}
                >
                  Delete
                  {{this.selectionCount}}
                  selected
                </button>
              {{/if}}
              <span class='table-showing'>Showing {{this.obsShowingStart}}-{{this.obsShowingEnd}} of {{this.obsTotalCount}} entries</span>
              {{#if this.showObsPagination}}
                <div class='obs-pagination'>
                  <button class='obs-page-btn' type='button' disabled={{this.cantPrevObs}} {{on 'click' this.prevObsPage}}>◀</button>
                  {{#each this.obsPageNumbers as |pn|}}
                    <button class='obs-page-num {{if pn.active "active"}}' type='button' {{on 'click' (fn this.goObsPage pn.page)}}>{{pn.label}}</button>
                  {{/each}}
                  <button class='obs-page-btn' type='button' disabled={{this.cantNextObs}} {{on 'click' this.nextObsPage}}>▶</button>
                </div>
              {{/if}}
            </div>
          </div>
        </section>

        <!-- Learning Goals section removed — replaced by Student Program Index above -->

        {{! Add Goal Modal removed — use Add Program in Student Program Index }}

        <!-- Student Program Index -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag admin'>Admin</span>
            <span class='section-name'>Student Program Index</span>
            <span class='staff-count'>Dense spreadsheet view for IEP goal
              management</span>
          </div>
          <div class='prog-index-card' {{on 'click' this.closePiDrops}}>
            <div class='pi-header'>
              <div class='pi-title-row'>
                <h3 class='pi-title'>{{if this.piSelectedStudentName (this.piSelectedStudentName) "Student"}} Programs</h3>
                <div class='pi-student-picker-wrap'>
                  <button class='pi-student-chip' {{on 'click' this.togglePiStudentDrop}}>
                    {{#if this.piSelectedStudentInitials}}
                      <span class='pi-student-avatar'>{{this.piSelectedStudentInitials}}</span>
                    {{else}}
                      <svg
                        width='14'
                        height='14'
                        viewBox='0 0 14 14'
                        fill='none'
                      ><circle cx='7' cy='5' r='3' fill='#8a8279' /><path
                          d='M2 13c0-3 2-5 5-5s5 2 5 5'
                          fill='#8a8279'
                        /></svg>
                    {{/if}}
                    {{this.piSelectedStudentDisplay}}
                    <svg width='10' height='10' viewBox='0 0 10 10' fill='none' stroke='currentColor' stroke-width='1.5'><path d='M2 3.5l3 3 3-3' /></svg>
                  </button>
                  {{#if this.showPiStudentDrop}}
                    <div class='pi-student-dropdown' {{on 'click' this.stopPropagation}}>
                      <input
                        class='pi-student-search'
                        type='text'
                        placeholder='Search students...'
                        value={{this.piStudentSearch}}
                        {{on 'input' this.setPiStudentSearch}}
                      />
                      <div class='pi-student-list'>
                        <button
                          class='pi-student-item pi-all-students {{if (this.isPiStudentSelected "All Students") "selected"}}'
                          {{on 'click' (fn this.selectPiStudent 'All Students' '')}}
                        >
                          <span class='pi-student-item-avatar pi-all-avatar'>ALL</span>
                          <span class='pi-student-item-name'>All Students</span>
                          {{#if (this.isPiStudentSelected "All Students")}}<span class='pi-student-check'>✓</span>{{/if}}
                        </button>
                        {{#each this.piFilteredStudentList as |s|}}
                          <button
                            class='pi-student-item {{if (this.isPiStudentSelected s.name) "selected"}}'
                            {{on 'click' (fn this.selectPiStudent s.name s.id)}}
                          >
                            <span class='pi-student-item-avatar'>{{s.initials}}</span>
                            <span class='pi-student-item-name'>{{s.name}}</span>
                            {{#if (this.isPiStudentSelected s.name)}}<span class='pi-student-check'>✓</span>{{/if}}
                          </button>
                        {{/each}}
                        {{#unless this.piFilteredStudentList.length}}
                          <div class='pi-student-empty'>No students found</div>
                        {{/unless}}
                      </div>
                    </div>
                  {{/if}}
                </div>
              </div>
              <div class='pi-controls'>
                <!-- View toggle -->
                <div class='pi-view-toggle'>
                  <button
                    class='pi-view-btn {{if this.isPiViewTable "active"}}'
                    title='Table view'
                    {{on 'click' (fn this.setPiView 'table')}}
                  >
                    <svg
                      width='14'
                      height='14'
                      viewBox='0 0 14 14'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><rect x='1' y='1' width='12' height='3' rx='1' /><rect
                        x='1'
                        y='6'
                        width='12'
                        height='3'
                        rx='1'
                      /><rect x='1' y='11' width='12' height='2' rx='1' /></svg>
                  </button>
                  <button
                    class='pi-view-btn {{if this.isPiViewCard "active"}}'
                    title='Card view'
                    {{on 'click' (fn this.setPiView 'card')}}
                  >
                    <svg
                      width='14'
                      height='14'
                      viewBox='0 0 14 14'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><rect x='1' y='1' width='5' height='5' rx='1' /><rect
                        x='8'
                        y='1'
                        width='5'
                        height='5'
                        rx='1'
                      /><rect x='1' y='8' width='5' height='5' rx='1' /><rect
                        x='8'
                        y='8'
                        width='5'
                        height='5'
                        rx='1'
                      /></svg>
                  </button>
                </div>
                <!-- Domain dropdown -->
                <div class='pi-drop-wrap'>
                  <button
                    class='pi-drop-btn'
                    {{on 'click' this.togglePiDomainDrop}}
                  >
                    {{this.piDomainFilter}}
                    <svg
                      width='10'
                      height='10'
                      viewBox='0 0 10 10'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><path d='M2 3.5l3 3 3-3' /></svg>
                  </button>
                  {{#if this.showPiDomainDrop}}
                    <div
                      class='pi-drop-menu'
                      {{on 'click' this.stopPropagation}}
                    >
                      {{#each this.piDomains as |d|}}
                        <button
                          class='pi-drop-item
                            {{if (this.isDomainSelected d) "selected"}}'
                          {{on 'click' (fn this.setPiDomain d)}}
                        >
                          {{#if (this.isDomainSelected d)}}✓ {{/if}}{{d}}
                        </button>
                      {{/each}}
                    </div>
                  {{/if}}
                </div>
                <!-- Status dropdown -->
                <div class='pi-drop-wrap'>
                  <button
                    class='pi-drop-btn'
                    {{on 'click' this.togglePiStatusDrop}}
                  >
                    {{this.piStatusFilter}}
                    <svg
                      width='10'
                      height='10'
                      viewBox='0 0 10 10'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='1.5'
                    ><path d='M2 3.5l3 3 3-3' /></svg>
                  </button>
                  {{#if this.showPiStatusDrop}}
                    <div
                      class='pi-drop-menu'
                      {{on 'click' this.stopPropagation}}
                    >
                      <button
                        class='pi-drop-item
                          {{if
                            (this.isStatusSelected "Active Only")
                            "selected"
                          }}'
                        {{on 'click' (fn this.setPiStatus 'Active Only')}}
                      >
                        {{#if (this.isStatusSelected 'Active Only')}}✓
                        {{/if}}Active Only
                      </button>
                      <button
                        class='pi-drop-item
                          {{if
                            (this.isStatusSelected "All Programs")
                            "selected"
                          }}'
                        {{on 'click' (fn this.setPiStatus 'All Programs')}}
                      >
                        {{#if (this.isStatusSelected 'All Programs')}}✓
                        {{/if}}All Programs
                      </button>
                      <button
                        class='pi-drop-item
                          {{if
                            (this.isStatusSelected "Discontinued")
                            "selected"
                          }}'
                        {{on 'click' (fn this.setPiStatus 'Discontinued')}}
                      >
                        {{#if (this.isStatusSelected 'Discontinued')}}✓
                        {{/if}}Discontinued
                      </button>
                    </div>
                  {{/if}}
                </div>
                {{#if this.piSelectedStudentName}}
                  <button
                    class='pi-add-btn'
                    {{on 'click' this.toggleAddProgramForm}}
                  >
                    {{#if this.showAddProgramForm}}✕ Cancel{{else}}+ Add Program{{/if}}
                  </button>
                {{else}}
                  <button class='pi-add-btn disabled' disabled>+ Add Program</button>
                {{/if}}
                <button
                  class='pi-add-btn'
                  type='button'
                  title='Push every Admin Program to Classroom Goals (covers edits made via Boxel UI)'
                  disabled={{this.isRebuildingGoals}}
                  {{on 'click' this.handleRebuildClassroomGoals}}
                >
                  {{#if this.isRebuildingGoals}}Pushing…{{else}}⇪ Rebuild Classroom Goals{{/if}}
                </button>
                {{#if this.rebuildGoalsMsg}}
                  <span class='rebuild-staff-msg {{if (eq this.rebuildGoalsState "error") "is-error" "is-ok"}}'>
                    {{this.rebuildGoalsMsg}}
                  </span>
                {{/if}}
              </div>
            </div>

            {{#if this.showAddProgramForm}}
              <form class='pi-add-form' {{on 'submit' this.submitProgram}}>
                <div class='pi-add-fields'>
                  <div class='pi-add-group wide'>
                    <label class='pi-add-label'>Program Name *</label>
                    <input
                      class='pi-add-input'
                      type='text'
                      placeholder='e.g. Counting to 20'
                      value={{this.newProgName}}
                      {{on 'input' this.setNewProgName}}
                    />
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Domain</label>
                    <select
                      class='pi-add-select'
                      {{on 'change' this.setNewProgDomain}}
                    >
                      <option>Math</option>
                      <option>Visual Performance</option>
                      <option>Reading</option>
                      <option>Language</option>
                      <option>Receptive Language</option>
                      <option>Labeling</option>
                      <option>Requests</option>
                      <option>Fine Motor</option>
                      <option>Gross Motor</option>
                      <option>Social</option>
                    </select>
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>ABLLS Code</label>
                    <input
                      class='pi-add-input'
                      type='text'
                      placeholder='e.g. R5'
                      value={{this.newProgAblls}}
                      {{on 'input' this.setNewProgAblls}}
                    />
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Master Sheet?</label>
                    <select
                      class='pi-add-select'
                      {{on 'change' this.setNewProgMaster}}
                    >
                      <option value='Yes'>Yes</option>
                      <option value='No'>No</option>
                      <option value='N/A'>N/A</option>
                    </select>
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Program Sheet?</label>
                    <select
                      class='pi-add-select'
                      {{on 'change' this.setNewProgSheet}}
                    >
                      <option value='Yes'>Yes</option>
                      <option value='No'>No</option>
                      <option value='N/A'>N/A</option>
                    </select>
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Started</label>
                    <input
                      class='pi-add-input'
                      type='date'
                      value={{this.newProgStarted}}
                      {{on 'input' this.setNewProgStarted}}
                    />
                  </div>
                  <div class='pi-add-group wide'>
                    <label class='pi-add-label'>Current Target</label>
                    <input
                      class='pi-add-input'
                      type='text'
                      placeholder='e.g. Lesson 1–5'
                      value={{this.newProgTarget}}
                      {{on 'input' this.setNewProgTarget}}
                    />
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Active?</label>
                    <select
                      class='pi-add-select'
                      {{on 'change' this.setNewProgActive}}
                    >
                      <option value='Yes'>Yes</option>
                      <option value='No'>No</option>
                    </select>
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Notes</label>
                    <input
                      class='pi-add-input'
                      type='text'
                      placeholder='Optional'
                      value={{this.newProgNotes}}
                      {{on 'input' this.setNewProgNotes}}
                    />
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Due Date</label>
                    <input
                      class='pi-add-input'
                      type='date'
                      value={{this.newProgDueDate}}
                      {{on 'input' this.setNewProgDueDate}}
                    />
                  </div>
                  <div class='pi-add-group'>
                    <label class='pi-add-label'>Target Mastery (%)</label>
                    <input
                      class='pi-add-input'
                      type='number'
                      min='0'
                      max='100'
                      value={{this.newProgTargetMastery}}
                      {{on 'input' this.setNewProgTargetMastery}}
                    />
                  </div>
                </div>
                {{!-- Materials --}}
                <div class='pi-mat-section'>
                  <div class='pi-mat-header'>
                    <span class='pi-add-label'>Instructional Materials</span>
                    <button type='button' class='pi-mat-add-btn' {{on 'click' this.addMaterial}}>+ Add Material</button>
                  </div>
                  {{#each this.newProgMaterials as |mat idx|}}
                    <div class='pi-mat-row'>
                      <select class='pi-add-select pi-mat-type' {{on 'change' (fn this.setMatType idx)}}>
                        <option value='Primary' selected={{eq mat.materialType 'Primary'}}>Primary</option>
                        <option value='Secondary' selected={{eq mat.materialType 'Secondary'}}>Secondary</option>
                      </select>
                      <input class='pi-add-input pi-mat-name' type='text' placeholder='Material name' value={{mat.name}} {{on 'input' (fn this.setMatName idx)}} />
                      <input class='pi-add-input pi-mat-detail' type='text' placeholder='Detail (e.g. Lessons 43-60)' value={{mat.detail}} {{on 'input' (fn this.setMatDetail idx)}} />
                      <button type='button' class='pi-mat-remove' {{on 'click' (fn this.removeMaterial idx)}}>✕</button>
                    </div>
                  {{/each}}
                </div>
                <div class='pi-add-actions'>
                  <button
                    type='button'
                    class='pi-cancel-btn'
                    {{on 'click' this.toggleAddProgramForm}}
                  >Cancel</button>
                  <button type='submit' class='pi-submit-btn'>Add Program</button>
                </div>
              </form>
            {{/if}}

            {{#unless this.piSelectedStudentName}}
              <div class='pi-empty-state'>
                <svg width='48' height='48' viewBox='0 0 48 48' fill='none'><circle cx='24' cy='18' r='8' stroke='#c4bdb6' stroke-width='2' /><path d='M8 44c0-9 7-16 16-16s16 7 16 16' stroke='#c4bdb6' stroke-width='2' /></svg>
                <p class='pi-empty-text'>Select a student above to view and manage their programs</p>
              </div>
            {{/unless}}

            {{#if this.piSelectedStudentName}}
            {{#if this.isPiViewTable}}
              <table class='pi-table'>
                <thead>
                  <tr>
                    <th
                      class='sortable'
                      {{on 'click' (fn this.togglePiSort 'program')}}
                    >PROGRAM{{if
                        (this.isSortedBy 'program')
                        this.piSortIndicator
                        ''
                      }}</th>
                    <th
                      class='sortable'
                      {{on 'click' (fn this.togglePiSort 'domain')}}
                    >DOMAIN{{if
                        (this.isSortedBy 'domain')
                        this.piSortIndicator
                        ''
                      }}</th>
                    <th>ABLLS CODE</th>
                    <th>MASTER SHEET</th>
                    <th>PROGRAM SHEET</th>
                    <th
                      class='sortable'
                      {{on 'click' (fn this.togglePiSort 'started')}}
                    >STARTED{{if
                        (this.isSortedBy 'started')
                        this.piSortIndicator
                        ''
                      }}</th>
                    <th>CURRENT TARGET</th>
                    <th>DUE DATE</th>
                    <th>TARGET %</th>
                    <th>MATERIALS</th>
                    <th
                      class='sortable'
                      {{on 'click' (fn this.togglePiSort 'active')}}
                    >ACTIVE?{{if
                        (this.isSortedBy 'active')
                        this.piSortIndicator
                        ''
                      }}</th>
                    <th>NOTES</th>
                    <th>DEL</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.piFilteredPrograms as |prog|}}
                    <tr class='{{if (this.isProgDiscontinued prog) "discontinued-row"}}'>
                      {{!-- Program Name --}}
                      <td class='prog-name pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'program' prog.program)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'program')}}
                          <input class='pi-cell-input' type='text' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'program')}} {{on 'blur' (fn this.onEditBlur prog 'program')}} />
                        {{else}}
                          {{prog.program}}
                        {{/if}}
                      </td>
                      {{!-- Domain --}}
                      <td class='pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'domain' prog.domain)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'domain')}}
                          <select class='pi-cell-select' {{on 'change' this.setPiEditValue}} {{on 'blur' (fn this.onEditBlur prog 'domain')}}>
                            <option value='Math' selected={{this.piEditValue 'Math'}}>Math</option>
                            <option value='Reading' selected={{this.piEditValue 'Reading'}}>Reading</option>
                            <option value='Language' selected={{this.piEditValue 'Language'}}>Language</option>
                            <option value='Receptive Language' selected={{this.piEditValue 'Receptive Language'}}>Receptive Language</option>
                            <option value='Visual Performance' selected={{this.piEditValue 'Visual Performance'}}>Visual Performance</option>
                            <option value='Fine Motor' selected={{this.piEditValue 'Fine Motor'}}>Fine Motor</option>
                            <option value='Gross Motor' selected={{this.piEditValue 'Gross Motor'}}>Gross Motor</option>
                            <option value='Labeling' selected={{this.piEditValue 'Labeling'}}>Labeling</option>
                            <option value='Requests' selected={{this.piEditValue 'Requests'}}>Requests</option>
                            <option value='Social' selected={{this.piEditValue 'Social'}}>Social</option>
                          </select>
                        {{else}}
                          <span class='pi-tag {{prog.domainKey}}'>{{prog.domain}}</span>
                        {{/if}}
                      </td>
                      {{!-- ABLLS Code --}}
                      <td class='pi-code pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'abllsCode' prog.abllsCode)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'abllsCode')}}
                          <input class='pi-cell-input sm' type='text' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'abllsCode')}} {{on 'blur' (fn this.onEditBlur prog 'abllsCode')}} />
                        {{else}}
                          {{prog.abllsCode}}
                        {{/if}}
                      </td>
                      {{!-- Master Sheet --}}
                      <td class='pi-check pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'masterSheet' prog.masterSheet)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'masterSheet')}}
                          <select class='pi-cell-select sm' {{on 'change' this.setPiEditValue}} {{on 'blur' (fn this.onEditBlur prog 'masterSheet')}}>
                            <option value='Yes'>Yes</option>
                            <option value='No'>No</option>
                            <option value='N/A'>N/A</option>
                          </select>
                        {{else}}
                          <span class='check-icon {{if (this.isYes prog.masterSheet) "yes" "no"}}'>{{if (this.isYes prog.masterSheet) "✓" "✗"}}</span>
                        {{/if}}
                      </td>
                      {{!-- Program Sheet --}}
                      <td class='pi-check pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'programSheet' prog.programSheet)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'programSheet')}}
                          <select class='pi-cell-select sm' {{on 'change' this.setPiEditValue}} {{on 'blur' (fn this.onEditBlur prog 'programSheet')}}>
                            <option value='Yes'>Yes</option>
                            <option value='No'>No</option>
                            <option value='N/A'>N/A</option>
                          </select>
                        {{else}}
                          <span class='check-icon {{if (this.isYes prog.programSheet) "yes" "no"}}'>{{if (this.isYes prog.programSheet) "✓" "✗"}}</span>
                        {{/if}}
                      </td>
                      {{!-- Started --}}
                      <td class='pi-date pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'started' prog.started)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'started')}}
                          <input class='pi-cell-input' type='date' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'started')}} {{on 'blur' (fn this.onEditBlur prog 'started')}} />
                        {{else}}
                          {{prog.started}}
                        {{/if}}
                      </td>
                      {{!-- Current Target --}}
                      <td class='pi-target pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'currentTarget' prog.currentTarget)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'currentTarget')}}
                          <input class='pi-cell-input wide' type='text' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'currentTarget')}} {{on 'blur' (fn this.onEditBlur prog 'currentTarget')}} />
                        {{else}}
                          {{prog.currentTarget}}
                        {{/if}}
                      </td>
                      {{!-- Due Date --}}
                      <td class='pi-date pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'dueDate' prog.dueDate)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'dueDate')}}
                          <input class='pi-cell-input' type='date' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'dueDate')}} {{on 'blur' (fn this.onEditBlur prog 'dueDate')}} />
                        {{else}}
                          {{prog.dueDate}}
                        {{/if}}
                      </td>
                      {{!-- Target Mastery --}}
                      <td class='pi-check pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'targetMastery' prog.targetMastery)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'targetMastery')}}
                          <input class='pi-cell-input sm' type='number' min='0' max='100' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'targetMastery')}} {{on 'blur' (fn this.onEditBlur prog 'targetMastery')}} />
                        {{else}}
                          {{prog.targetMastery}}%
                        {{/if}}
                      </td>
                      {{!-- Materials --}}
                      <td class='pi-mat-cell pi-editable' {{on 'dblclick' (fn this.openMatEditor prog)}}>
                        {{#if (this.isEditingMats prog._rowIdx)}}
                          <div class='pi-mat-editor' {{on 'click' this.stopPropagation}}>
                            {{#each this.editMats as |mat idx|}}
                              <div class='pi-mat-edit-row'>
                                <select class='pi-cell-select' {{on 'change' (fn this.setEditMatType idx)}}>
                                  <option value='Primary' selected={{eq mat.materialType 'Primary'}}>Primary</option>
                                  <option value='Secondary' selected={{eq mat.materialType 'Secondary'}}>Secondary</option>
                                </select>
                                <input class='pi-cell-input' type='text' placeholder='Name' value={{mat.name}} {{on 'input' (fn this.setEditMatName idx)}} />
                                <input class='pi-cell-input' type='text' placeholder='Detail' value={{mat.detail}} {{on 'input' (fn this.setEditMatDetail idx)}} />
                                <button type='button' class='pi-mat-remove' {{on 'click' (fn this.removeEditMat idx)}}>✕</button>
                              </div>
                            {{/each}}
                            <div class='pi-mat-edit-actions'>
                              <button type='button' class='pi-mat-add-btn' {{on 'click' this.addEditMat}}>+ Add</button>
                              <button type='button' class='pi-mat-save-btn' {{on 'click' (fn this.saveEditMats prog)}}>Save</button>
                              <button type='button' class='pi-mat-cancel-btn' {{on 'click' this.closeMatEditor}}>Cancel</button>
                            </div>
                          </div>
                        {{else}}
                          {{#each prog.materials as |mat|}}
                            <div class='pi-mat-tag {{if (this.isMatPrimary mat) "primary" "secondary"}}'>
                              {{mat.name}}{{#if mat.detail}} — {{mat.detail}}{{/if}}
                            </div>
                          {{/each}}
                          {{#unless prog.materials.length}}
                            <span class='pi-mat-empty'>Double-click to edit</span>
                          {{/unless}}
                        {{/if}}
                      </td>
                      {{!-- Active --}}
                      <td class='pi-check pi-editable' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'active' prog.active)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'active')}}
                          <select class='pi-cell-select sm' {{on 'change' this.setPiEditValue}} {{on 'blur' (fn this.onEditBlur prog 'active')}}>
                            <option value='Yes'>Yes</option>
                            <option value='No'>No</option>
                          </select>
                        {{else}}
                          <span class='check-icon {{if (this.isProgActive prog) "yes" "no"}}'>{{if (this.isProgActive prog) "Yes" "No"}}</span>
                        {{/if}}
                      </td>
                      {{!-- Notes --}}
                      <td class='pi-note pi-editable {{if (this.isProgDiscontinued prog) "discontinued"}}' {{on 'dblclick' (fn this.startEditCell prog._rowIdx 'notes' prog.notes)}}>
                        {{#if (this.isEditingCell prog._rowIdx 'notes')}}
                          <input class='pi-cell-input' type='text' value={{this.piEditValue}} {{on 'input' this.setPiEditValue}} {{on 'keydown' (fn this.onEditKeydown prog 'notes')}} {{on 'blur' (fn this.onEditBlur prog 'notes')}} />
                        {{else}}
                          {{prog.notes}}
                        {{/if}}
                      </td>
                      {{!-- Delete --}}
                      <td class='pi-del-cell'>
                        <button
                          type='button'
                          class='pi-del-btn'
                          title='Delete this Program (also removes matching Classroom Goal)'
                          disabled={{eq this.deletingProgramId prog._srcCard.id}}
                          {{on 'click' (fn this.handleDeleteProgram prog)}}
                        >
                          {{#if (eq this.deletingProgramId prog._srcCard.id)}}…{{else}}✕{{/if}}
                        </button>
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
              {{#if this.deleteProgramMsg}}
                <div class='pi-del-msg'>{{this.deleteProgramMsg}}</div>
              {{/if}}
            {{else}}
              <div class='pi-card-grid'>
                {{#each this.piFilteredPrograms as |prog|}}
                  <div
                    class='pi-card-item
                      {{if (this.isProgDiscontinued prog) "discontinued"}}'
                  >
                    <div class='pi-card-top'>
                      <span
                        class='pi-tag {{prog.domainKey}}'
                      >{{prog.domain}}</span>
                      <span
                        class='check-icon
                          {{if (this.isProgActive prog) "yes" "no"}}'
                      >{{if
                          (this.isProgActive prog)
                          'Active'
                          'Inactive'
                        }}</span>
                    </div>
                    <div class='pi-card-name'>{{prog.program}}</div>
                    <div class='pi-card-meta'>
                      {{#if prog.abllsCode}}<span
                          class='pi-card-code'
                        >{{prog.abllsCode}}</span>{{/if}}
                      {{#if prog.started}}<span class='pi-card-date'>Started
                          {{prog.started}}</span>{{/if}}
                    </div>
                    <div class='pi-card-target'>{{prog.currentTarget}}</div>
                    <div class='pi-card-sheets'>
                      <span
                        class='sheet-badge
                          {{if
                            (this.isYes prog.masterSheet)
                            "ready"
                            "missing"
                          }}'
                      >Master Sheet</span>
                      <span
                        class='sheet-badge
                          {{if
                            (this.isYes prog.programSheet)
                            "ready"
                            "missing"
                          }}'
                      >Program Sheet</span>
                    </div>
                    {{#if prog.notes}}<div
                        class='pi-card-notes'
                      >{{prog.notes}}</div>{{/if}}
                  </div>
                {{/each}}
              </div>
            {{/if}}

            {{/if}}

            <!-- Color Legend -->
            <div class='pi-legend'>
              <span class='pi-legend-item'><span
                  class='pi-tag math'
                >Math</span></span>
              <span class='pi-legend-item'><span
                  class='pi-tag reading'
                >Reading</span></span>
              <span class='pi-legend-item'><span
                  class='pi-tag language'
                >Language</span></span>
              <span class='pi-legend-item'><span
                  class='pi-tag receptive'
                >Receptive Lang</span></span>
              <span class='pi-legend-item'><span class='pi-tag visual'>Visual
                  Perf</span></span>
              <span class='pi-legend-item'><span class='pi-tag finemotor'>Fine
                  Motor</span></span>
              <span class='pi-legend-item'><span
                  class='pi-tag requests'
                >Requests</span></span>
            </div>
          </div>
        </section>

        <!-- Weekly Program Schedule -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag admin'>Admin</span>
            <span class='section-name'>Weekly Program Schedule</span>
            <span class='staff-count'>Drag-and-drop weekly planning board</span>
          </div>
          {{#unless this.piSelectedStudentName}}
            <div class='pi-empty-state'>
              <p class='pi-empty-text'>Select a student in Student Program Index to view their weekly schedule</p>
            </div>
          {{/unless}}
          {{#if this.piSelectedStudentName}}
          <div class='schedule-board'>
            {{! Column 0: This Week }}
            <div
              class='sched-col {{if (this.isDragOver 0) "drag-over"}}'
              {{on 'dragover' (fn this.onDragOver 0)}}
              {{on 'drop' (fn this.onDrop 0)}}
              {{on 'dragleave' this.onDragLeave}}
            >
              <div class='sched-col-header'>
                <span class='sched-week-label'>{{this.weekLabel0}}</span>
                <span class='sched-week-dates'>{{this.weekDates0}}</span>
                <span class='sched-count'>{{this.schedCol0.length}}</span>
              </div>
              {{#each this.schedCol0 as |card|}}
                <div
                  class='sched-card
                    {{card.domainKey}}
                    {{if card.muted "muted"}}'
                  draggable='true'
                  {{on 'dragstart' (fn this.onDragStart card.id)}}
                  {{on 'dragend' this.onDragEnd}}
                >
                  <div class='sched-card-top'>
                    <span
                      class='sched-tag {{card.domainKey}}'
                    >{{card.domainLabel}}</span>
                    {{#if card.ablls}}<span
                        class='sched-code'
                      >{{card.ablls}}</span>{{/if}}
                  </div>
                  <div
                    class='sched-card-title {{if card.muted "muted"}}'
                  >{{card.name}}</div>
                  <div
                    class='sched-card-sub {{if card.muted "muted"}}'
                  >{{card.target}}</div>
                  {{#if card.started}}<div class='sched-card-date'>{{card.started}}{{#if card.dueDate}} → {{card.dueDate}}{{/if}}</div>{{/if}}
                  {{#if card.note}}
                    <div class='sched-card-note'>{{card.note}}</div>
                  {{/if}}
                </div>
              {{/each}}
              <div class='sched-drop-zone'>+ Drop program here</div>
            </div>
            {{! Column 1: Next Week }}
            <div
              class='sched-col {{if (this.isDragOver 1) "drag-over"}}'
              {{on 'dragover' (fn this.onDragOver 1)}}
              {{on 'drop' (fn this.onDrop 1)}}
              {{on 'dragleave' this.onDragLeave}}
            >
              <div class='sched-col-header'>
                <span class='sched-week-label'>{{this.weekLabel1}}</span>
                <span class='sched-week-dates'>{{this.weekDates1}}</span>
                <span class='sched-count'>{{this.schedCol1.length}}</span>
              </div>
              {{#each this.schedCol1 as |card|}}
                <div
                  class='sched-card
                    {{card.domainKey}}
                    {{if card.muted "muted"}}'
                  draggable='true'
                  {{on 'dragstart' (fn this.onDragStart card.id)}}
                  {{on 'dragend' this.onDragEnd}}
                >
                  <div class='sched-card-top'>
                    <span
                      class='sched-tag {{card.domainKey}}'
                    >{{card.domainLabel}}</span>
                    {{#if card.ablls}}<span
                        class='sched-code'
                      >{{card.ablls}}</span>{{/if}}
                  </div>
                  <div
                    class='sched-card-title {{if card.muted "muted"}}'
                  >{{card.name}}</div>
                  <div
                    class='sched-card-sub {{if card.muted "muted"}}'
                  >{{card.target}}</div>
                  {{#if card.started}}<div class='sched-card-date'>{{card.started}}{{#if card.dueDate}} → {{card.dueDate}}{{/if}}</div>{{/if}}
                  {{#if card.note}}
                    <div class='sched-card-note'>{{card.note}}</div>
                  {{/if}}
                </div>
              {{/each}}
              <div class='sched-drop-zone'>+ Drop program here</div>
            </div>
            {{! Column 2: Week 3 }}
            <div
              class='sched-col {{if (this.isDragOver 2) "drag-over"}}'
              {{on 'dragover' (fn this.onDragOver 2)}}
              {{on 'drop' (fn this.onDrop 2)}}
              {{on 'dragleave' this.onDragLeave}}
            >
              <div class='sched-col-header'>
                <span class='sched-week-label'>{{this.weekLabel2}}</span>
                <span class='sched-week-dates'>{{this.weekDates2}}</span>
                <span class='sched-count'>{{this.schedCol2.length}}</span>
              </div>
              {{#each this.schedCol2 as |card|}}
                <div
                  class='sched-card
                    {{card.domainKey}}
                    {{if card.muted "muted"}}'
                  draggable='true'
                  {{on 'dragstart' (fn this.onDragStart card.id)}}
                  {{on 'dragend' this.onDragEnd}}
                >
                  <div class='sched-card-top'>
                    <span
                      class='sched-tag {{card.domainKey}}'
                    >{{card.domainLabel}}</span>
                    {{#if card.ablls}}<span
                        class='sched-code'
                      >{{card.ablls}}</span>{{/if}}
                  </div>
                  <div
                    class='sched-card-title {{if card.muted "muted"}}'
                  >{{card.name}}</div>
                  <div
                    class='sched-card-sub {{if card.muted "muted"}}'
                  >{{card.target}}</div>
                  {{#if card.started}}<div class='sched-card-date'>{{card.started}}{{#if card.dueDate}} → {{card.dueDate}}{{/if}}</div>{{/if}}
                  {{#if card.note}}
                    <div class='sched-card-note'>{{card.note}}</div>
                  {{/if}}
                </div>
              {{/each}}
              <div class='sched-drop-zone'>+ Drop program here</div>
            </div>
            {{! Column 3: Backlog — with search + pagination }}
            <div
              class='sched-col sched-col-backlog {{if (this.isDragOver 3) "drag-over"}}'
              {{on 'dragover' (fn this.onDragOver 3)}}
              {{on 'drop' (fn this.onDrop 3)}}
              {{on 'dragleave' this.onDragLeave}}
            >
              <div class='sched-col-header'>
                <span
                  class='sched-week-label backlog'
                >{{this.weekLabel3}}</span>
                <span class='sched-week-dates'>{{this.weekDates3}}</span>
                <span class='sched-count'>{{this.backlogFiltered.length}}</span>
              </div>
              {{#if this.backlogHasMore}}
                <input
                  class='backlog-search'
                  type='text'
                  placeholder='Search backlog...'
                  value={{this.backlogSearch}}
                  {{on 'input' this.setBacklogSearch}}
                />
              {{/if}}
              <div class='backlog-cards'>
                {{#each this.schedCol3 as |card|}}
                  <div
                    class='sched-card
                      {{card.domainKey}}
                      {{if card.muted "muted"}}'
                    draggable='true'
                    {{on 'dragstart' (fn this.onDragStart card.id)}}
                    {{on 'dragend' this.onDragEnd}}
                  >
                    <div class='sched-card-top'>
                      <span
                        class='sched-tag {{card.domainKey}}'
                      >{{card.domainLabel}}</span>
                      {{#if card.ablls}}<span
                          class='sched-code'
                        >{{card.ablls}}</span>{{/if}}
                    </div>
                    <div
                      class='sched-card-title {{if card.muted "muted"}}'
                    >{{card.name}}</div>
                    <div
                      class='sched-card-sub {{if card.muted "muted"}}'
                    >{{card.target}}</div>
                    {{#if card.started}}<div class='sched-card-date'>{{card.started}}{{#if card.dueDate}} → {{card.dueDate}}{{/if}}</div>{{/if}}
                    {{#if card.note}}
                      <div class='sched-card-note'>{{card.note}}</div>
                    {{/if}}
                  </div>
                {{/each}}
              </div>
              {{#if this.backlogHasMore}}
                <div class='backlog-pager'>
                  <button class='backlog-page-btn' disabled={{this.isBacklogFirstPage}} {{on 'click' this.prevBacklogPage}}>Prev</button>
                  <span class='backlog-page-info'>{{this.backlogPageDisplay}}</span>
                  <button class='backlog-page-btn' disabled={{this.isBacklogLastPage}} {{on 'click' this.nextBacklogPage}}>Next</button>
                </div>
              {{/if}}
              <div class='sched-drop-zone'>+ Drop program here</div>
            </div>
          </div>

          <!-- Color Key -->
          <div class='sched-key'>
            <div class='sched-key-title'>KEY</div>
            <div class='sched-key-header'>
              <span>Program</span>
              <span>Color Code</span>
            </div>
            <div class='sched-key-item'><span
                class='sched-key-swatch math'
              ></span><span>Math Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch reading'
              ></span><span>Reading Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch language'
              ></span><span>Language/Communication Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch visual'
              ></span><span>Spelling/Writing Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch social'
              ></span><span>Social/Emotional Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch labeling'
              ></span><span>Self-Management Programs</span></div>
            <div class='sched-key-item'><span
                class='sched-key-swatch requests'
              ></span><span>Behavior Goals and Data Programs</span></div>
          </div>
          {{/if}}
        </section>

        <!-- Staff Directory -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag admin'>Admin</span>
            <span class='section-name'>Staff Directory</span>
            <span class='staff-count'>{{this.filteredStaff.length}}
              members</span>
            <button
              class='section-add-btn'
              {{on 'click' this.openAddStaffModal}}
            >
              <svg
                width='12'
                height='12'
                viewBox='0 0 12 12'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M6 1.5v9M1.5 6h9' /></svg>
              Add Staff
            </button>
            <button
              class='section-add-btn'
              type='button'
              title='Push every Admin staff to Classroom — covers edits made via Boxel UI'
              disabled={{this.isRebuildingStaff}}
              {{on 'click' this.handleRebuildClassroomStaff}}
            >
              {{#if this.isRebuildingStaff}}Pushing…{{else}}⇪ Rebuild Classroom + HoS Staff{{/if}}
            </button>
            {{#if this.rebuildStaffMsg}}
              <span class='rebuild-staff-msg {{if (eq this.rebuildStaffState "error") "is-error" "is-ok"}}'>
                {{this.rebuildStaffMsg}}
              </span>
            {{/if}}
          </div>

          <div class='staff-search-bar'>
            <input class='staff-search-input' type='text' placeholder='Search staff by name or role...' value={{this.staffSearchQuery}} {{on 'input' this.setStaffSearch}} />
          </div>

          <div class='staff-cards-direct'>
            {{#each this.pagedStaff as |item|}}
              <div
                class='staff-card-item
                  {{if (this.isEditingStaff item.i) "editing"}}'
              >
                {{#if (this.isEditingStaff item.i)}}
                  <form
                    class='staff-edit-form'
                    {{on 'submit' (fn this.saveEditStaff item.i)}}
                  >
                    <div class='sef-row'>
                      <div class='sef-group wide'>
                        <label class='sef-label'>Name *</label>
                        <input
                          class='sef-input'
                          type='text'
                          value={{this.editStaffValues.name}}
                          {{on 'input' this.setEditStaffName}}
                        />
                      </div>
                      <div class='sef-group'>
                        <label class='sef-label'>Role</label>
                        <select
                          class='sef-select'
                          {{on 'change' this.setEditStaffRole}}
                        >
                          <option
                            value='Lead Teacher'
                            selected={{this.isEditStaffRole 'Lead Teacher'}}
                          >Lead Teacher</option>
                          <option
                            value='1:1 Aide'
                            selected={{this.isEditStaffRole '1:1 Aide'}}
                          >1:1 Aide</option>
                          <option
                            value='OT Specialist'
                            selected={{this.isEditStaffRole 'OT Specialist'}}
                          >OT Specialist</option>
                          <option
                            value='Speech'
                            selected={{this.isEditStaffRole 'Speech'}}
                          >Speech</option>
                        </select>
                      </div>
                    </div>
                    <div class='sef-row'>
                      <div class='sef-group narrow'>
                        <label class='sef-label'>Initials</label>
                        <input
                          class='sef-input'
                          type='text'
                          maxlength='3'
                          value={{this.editStaffValues.initials}}
                          {{on 'input' this.setEditStaffInitials}}
                        />
                      </div>
                      <div class='sef-group narrow'>
                        <label class='sef-label'>Color</label>
                        <select
                          class='sef-select'
                          {{on 'change' this.setEditStaffColor}}
                        >
                          <option
                            value='teal'
                            selected={{this.isEditStaffColor 'teal'}}
                          >Teal</option>
                          <option
                            value='purple'
                            selected={{this.isEditStaffColor 'purple'}}
                          >Purple</option>
                          <option
                            value='coral'
                            selected={{this.isEditStaffColor 'coral'}}
                          >Coral</option>
                          <option
                            value='amber'
                            selected={{this.isEditStaffColor 'amber'}}
                          >Amber</option>
                        </select>
                      </div>
                      <div class='sef-group narrow'>
                        <label class='sef-label'>Students</label>
                        <input
                          class='sef-input'
                          type='number'
                          value={{this.editStaffValues.studentCount}}
                          {{on 'input' this.setEditStaffStudents}}
                        />
                      </div>
                      <div class='sef-group narrow'>
                        <label class='sef-label'>Obs/week</label>
                        <input
                          class='sef-input'
                          type='number'
                          value={{this.editStaffValues.weeklyObservations}}
                          {{on 'input' this.setEditStaffObs}}
                        />
                      </div>
                      <div class='sef-group narrow'>
                        <label class='sef-label'>Status</label>
                        <select
                          class='sef-select'
                          {{on 'change' this.setEditStaffStatus}}
                        >
                          <option
                            value='Active'
                            selected={{this.isEditStaffStatus 'Active'}}
                          >Active</option>
                          <option
                            value='Pending'
                            selected={{this.isEditStaffStatus 'Pending'}}
                          >Pending</option>
                        </select>
                      </div>
                    </div>
                    <div class='sef-actions'>
                      <button
                        type='button'
                        class='action-btn cancel-edit'
                        {{on 'click' this.cancelEditStaff}}
                      >Cancel</button>
                      <button
                        type='submit'
                        class='action-btn save'
                      >Save</button>
                    </div>
                  </form>
                {{else}}
                  <button
                    class='staff-edit-btn'
                    {{on 'click' (fn this.startEditStaff item.i item.s)}}
                  >✎</button>
                  <button
                    class='staff-del-btn'
                    {{on 'click' (fn this.deleteStaff item.i)}}
                  >✕</button>
                  <div
                    class='sci-avatar {{item.s.avatarColor}}'
                  >{{item.s.initials}}</div>
                  <div class='sci-info'>
                    <span class='sci-name'>{{item.s.name}}</span>
                    <span class='sci-role'>{{item.s.role}}</span>
                  </div>
                  <div class='sci-meta'>
                    <span class='sci-stat'>{{item.s.studentCount}}
                      students</span>
                    <span class='sci-stat'>{{item.s.weeklyObservations}}
                      obs/week</span>
                  </div>
                  <span
                    class='sci-status {{item.s.status}}'
                  >{{item.s.status}}</span>
                {{/if}}
              </div>
            {{/each}}
            <button
              class='staff-add-card'
              {{on 'click' this.openAddStaffModal}}
            >
              <svg
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
              ><line x1='12' y1='5' x2='12' y2='19' /><line
                  x1='5'
                  y1='12'
                  x2='19'
                  y2='12'
                /></svg>
            </button>
          </div>
          {{#if this.showStaffPagination}}
            <div class='staff-pagination'>
              <button class='sp-btn' type='button' disabled={{this.cantPrevStaffPage}} {{on 'click' this.prevStaffPage}}>Prev</button>
              <span class='sp-label'>{{this.staffPageLabel}}</span>
              <button class='sp-btn' type='button' disabled={{this.cantNextStaffPage}} {{on 'click' this.nextStaffPage}}>Next</button>
            </div>
          {{/if}}
        </section>

        <!-- Student Full Profiles (mirrored from HoS via Approach C push) -->
        <section class='admin-section'>
          <div class='section-label'>
            <span class='section-tag sensitive'>Sensitive</span>
            <span class='section-name'>Student Full Profiles</span>
            <span class='staff-count'>{{this.profileDisplayList.length}} students</span>
          </div>
          {{#if this.profileDisplayList.length}}
            <div class='admin-profile-list'>
              {{#each this.profileDisplayList as |prof|}}
                <div class='admin-profile-row'>
                  <span class='apr-name'>{{prof.displayName}}</span>
                  <span class='apr-grade'>{{prof.grade}}</span>
                  <span class='apr-id'>{{prof.studentId}}</span>
                </div>
              {{/each}}
            </div>
          {{else}}
            <div class='empty-state'>
              <div class='es-msg'>No student profiles yet</div>
              <div class='es-sub'>Click "Fetch from HoS" to import student profiles from the Head of School dashboard</div>
            </div>
          {{/if}}
        </section>

      </div>

      {{#if this.confirmPending}}
        <div class='confirm-overlay' {{on 'click' this.cancelConfirm}}>
          <div class='confirm-dialog' {{on 'click' this.stopPropagation}}>
            <p class='confirm-msg'>{{this.confirmPending.message}}</p>
            <div class='confirm-btns'>
              <button
                class='confirm-btn'
                {{on 'click' this.cancelConfirm}}
              >Cancel</button>
              <button
                class='confirm-btn danger'
                {{on 'click' this.confirmAction}}
              >Delete</button>
            </div>
          </div>
        </div>
      {{/if}}

      {{#if this.showAddStaffForm}}
        <div class='staff-modal-overlay' {{on 'click' this.closeAddStaffModal}}>
          <div class='staff-modal' {{on 'click' this.stopPropagation}}>
            <div class='staff-modal-header'>
              <h2 class='staff-modal-title'>Add New Staff Member</h2>
              <button
                class='staff-modal-close'
                {{on 'click' this.closeAddStaffModal}}
              >
                <svg
                  width='16'
                  height='16'
                  viewBox='0 0 16 16'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path d='M4 4l8 8M12 4l-8 8' /></svg>
              </button>
            </div>

            {{! Step 1: AI Input }}
            {{#if (this.isStaffStep 'input')}}
              <div class='staff-modal-form'>
                <div class='smf-ai-section'>
                  <div class='smf-ai-label'>Describe the staff member</div>
                  <textarea
                    class='smf-ai-textarea'
                    placeholder='e.g. Dana Rivers, 1:1 Aide, 3 students, 32 obs/week, d.rivers@tribecaprep.org'
                    value={{this.staffAiInput}}
                    {{on 'input' this.setStaffAiInput}}
                  ></textarea>
                  <div class='smf-ai-hint'>AI will extract name, role, email,
                    and other details from your description</div>
                </div>
                <div class='smf-actions'>
                  <button
                    type='button'
                    class='smf-btn cancel'
                    {{on 'click' this.closeAddStaffModal}}
                  >Cancel</button>
                  <button
                    type='button'
                    class='smf-btn ai'
                    {{on 'click' this.triggerAnalyze}}
                  >
                    <svg
                      width='14'
                      height='14'
                      viewBox='0 0 14 14'
                      fill='none'
                    ><path
                        d='M7 1l1.5 3.5L12 6l-3.5 1.5L7 11 5.5 7.5 2 6l3.5-1.5L7 1z'
                        fill='currentColor'
                      /></svg>
                    Add with AI
                  </button>
                </div>
              </div>
            {{/if}}

            {{! Step 2: Analyzing }}
            {{#if (this.isStaffStep 'analyzing')}}
              <div class='staff-modal-form'>
                <div class='smf-analyzing'>
                  <div class='smf-spinner'></div>
                  <span>Analyzing with AI...</span>
                </div>
              </div>
            {{/if}}

            {{! Step 3: Preview (editable) }}
            {{#if (this.isStaffStep 'preview')}}
              <div class='staff-modal-form'>
                <div class='smf-preview-badge'>AI Extracted — review and edit
                  before saving</div>
                <div class='smf-row'>
                  <div class='smf-group full'>
                    <label class='smf-label'>Full Name
                      <span class='smf-req'>*</span></label>
                    <input
                      class='smf-input'
                      type='text'
                      value={{this.newMemberName}}
                      {{on 'input' this.setMemberName}}
                    />
                  </div>
                </div>
                <div class='smf-row'>
                  <div class='smf-group'>
                    <label class='smf-label'>Role</label>
                    <select
                      class='smf-select'
                      {{on 'change' this.setMemberRole}}
                    >
                      <option value='Lead Teacher'>Lead Teacher</option>
                      <option value='1:1 Aide'>1:1 Aide</option>
                      <option value='OT Specialist'>OT Specialist</option>
                      <option value='Speech'>Speech</option>
                      <option value='Administrator'>Administrator</option>
                    </select>
                  </div>
                  <div class='smf-group'>
                    <label class='smf-label'>Initials</label>
                    <div class='smf-color-row'>
                      <input
                        class='smf-input'
                        type='text'
                        maxlength='3'
                        value={{this.newMemberInitials}}
                        {{on 'input' this.setMemberInitials}}
                      />
                      <span
                        class='smf-color-preview {{this.newMemberColor}}'
                      >{{this.newMemberInitials}}</span>
                    </div>
                  </div>
                </div>
                <div class='smf-row'>
                  <div class='smf-group'>
                    <label class='smf-label'>Avatar Color</label>
                    <select
                      class='smf-select'
                      {{on 'change' this.setMemberColor}}
                    >
                      <option value='teal'>Teal</option>
                      <option value='purple'>Purple</option>
                      <option value='coral'>Coral</option>
                      <option value='amber'>Amber</option>
                    </select>
                  </div>
                  <div class='smf-group'>
                    <label class='smf-label'>Email</label>
                    <input
                      class='smf-input'
                      type='email'
                      value={{this.newMemberEmail}}
                      {{on 'input' this.setMemberEmail}}
                    />
                  </div>
                </div>
                <div class='smf-row'>
                  <div class='smf-group'>
                    <label class='smf-label'>Student Count</label>
                    <input
                      class='smf-input'
                      type='number'
                      min='0'
                      value={{this.newMemberStudents}}
                      {{on 'input' this.setMemberStudents}}
                    />
                  </div>
                  <div class='smf-group'>
                    <label class='smf-label'>Weekly Observations</label>
                    <input
                      class='smf-input'
                      type='number'
                      min='0'
                      value={{this.newMemberObs}}
                      {{on 'input' this.setMemberObs}}
                    />
                  </div>
                </div>
                <div class='smf-actions'>
                  <button
                    type='button'
                    class='smf-btn cancel'
                    {{on 'click' this.backToInput}}
                  >Back</button>
                  <button
                    type='button'
                    class='smf-btn save'
                    {{on 'click' this.triggerSaveStaff}}
                  >Save to Realm</button>
                </div>
              </div>
            {{/if}}

            {{! Step 4: Saving }}
            {{#if (this.isStaffStep 'saving')}}
              <div class='staff-modal-form'>
                <div class='smf-analyzing'>
                  <div class='smf-spinner'></div>
                  <span>Saving staff member...</span>
                </div>
              </div>
            {{/if}}

            {{! Error state }}
            {{#if (this.isStaffStep 'error')}}
              <div class='staff-modal-form'>
                <div class='smf-error'>{{this.staffAiError}}</div>
                <div class='smf-actions'>
                  <button
                    type='button'
                    class='smf-btn cancel'
                    {{on 'click' this.backToInput}}
                  >Try Again</button>
                </div>
              </div>
            {{/if}}

          </div>
        </div>
      {{/if}}

      <style scoped>
        .admin-board {
          background: #faf8f6;
          min-height: 100%;
          padding: 2rem;
          font-family:
            'Inter',
            system-ui,
            -apple-system,
            sans-serif;
          color: #1a1816;
        }

        .section-tag.sensitive {
          background: #fdf0ee;
          color: #e05d50;
        }
        .section-tag.chart {
          background: #fdf6e8;
          color: #c08b30;
        }

        /* ── Weekly Schedule Board ── */
        .schedule-board {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 0.75rem;
          background: #fff;
          border-radius: 12px;
          border: 1px solid #ebe7e3;
          padding: 1rem;
        }
        .sched-col {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .sched-col-header {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding-bottom: 0.5rem;
          border-bottom: 1px solid #ebe7e3;
          margin-bottom: 0.25rem;
        }
        .sched-week-label {
          font-size: 0.625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #1a1816;
        }
        .sched-week-label.backlog {
          color: #8a8279;
        }
        .sched-week-dates {
          font-size: 0.625rem;
          color: #8a8279;
        }
        .sched-count {
          margin-left: auto;
          font-size: 0.6875rem;
          font-weight: 600;
          color: #8a8279;
          background: #f5f2ef;
          border-radius: 100px;
          padding: 0.1rem 0.4rem;
        }
        .sched-card {
          border-radius: 8px;
          padding: 0.625rem 0.75rem;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .sched-card.math {
          background: #fde8e8;
        }
        .sched-card.reading {
          background: #e8f5e9;
        }
        .sched-card.language {
          background: #fff3e0;
        }
        .sched-card.visual {
          background: #fdf6e8;
        }
        .sched-card.receptive {
          background: #fff3e0;
        }
        .sched-card.labeling {
          background: #f4f0fa;
        }
        .sched-card.requests {
          background: #fde8e8;
        }
        .sched-card.finemotor {
          background: #e3eeff;
        }
        .sched-card.social {
          background: #e8f6f4;
        }
        .sched-card.muted {
          opacity: 0.6;
        }
        .sched-card-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .sched-tag {
          font-size: 0.5625rem;
          font-weight: 700;
          padding: 0.15rem 0.4rem;
          border-radius: 3px;
        }
        .sched-tag.math {
          background: #f9b8b8;
          color: #c05050;
        }
        .sched-tag.reading {
          background: #b8e8bc;
          color: #3a8a4a;
        }
        .sched-tag.language {
          background: #fdd5a0;
          color: #c07830;
        }
        .sched-tag.visual {
          background: #fde8a0;
          color: #a07020;
        }
        .sched-tag.receptive {
          background: #fdd5a0;
          color: #c07830;
        }
        .sched-tag.labeling {
          background: #d8ccf0;
          color: #7c5fc4;
        }
        .sched-tag.requests {
          background: #f9b8b8;
          color: #c05050;
        }
        .sched-tag.finemotor {
          background: #b8ccf0;
          color: #4a6ac0;
        }
        .sched-tag.social {
          background: #b8e8e4;
          color: #2a9d8f;
        }
        .sched-code {
          font-size: 0.625rem;
          color: #8a8279;
        }
        .sched-card-title {
          font-size: 0.8125rem;
          font-weight: 600;
          color: #1a1816;
          line-height: 1.3;
        }
        .sched-card-title.muted {
          color: #8a8279;
        }
        .sched-card-sub {
          font-size: 0.75rem;
          color: #5c5650;
        }
        .sched-card-sub.muted {
          color: #aeaaa6;
        }
        .sched-card-date {
          font-size: 0.625rem;
          color: #8a8279;
          margin-top: 0.25rem;
        }
        /* Backlog column — fixed height with overflow */
        .sched-col-backlog {
          align-self: flex-start;
        }
        .backlog-cards {
          max-height: none; /* controlled by pagination, not scroll */
        }
        .backlog-search {
          width: 100%;
          padding: 0.375rem 0.5rem;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          font-family: inherit;
          font-size: 0.75rem;
          outline: none;
          margin-bottom: 0.5rem;
          box-sizing: border-box;
        }
        .backlog-search:focus {
          border-color: #c08b30;
        }
        .backlog-pager {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 0.375rem 0;
          margin-top: 0.25rem;
        }
        .backlog-page-btn {
          font-family: inherit;
          font-size: 0.6875rem;
          font-weight: 600;
          color: #5c5650;
          background: #faf8f6;
          border: 1px solid #ebe7e3;
          border-radius: 4px;
          padding: 0.2rem 0.5rem;
          cursor: pointer;
        }
        .backlog-page-btn:disabled {
          opacity: 0.3;
          cursor: not-allowed;
        }
        .backlog-page-btn:not(:disabled):hover {
          background: #f0ece8;
        }
        .backlog-page-info {
          font-size: 0.6875rem;
          color: #8a8279;
        }
        .sched-card-sessions {
          font-size: 0.6875rem;
          font-weight: 600;
          color: #2a9d8f;
        }
        .sched-card-sessions.warn {
          color: #e05d50;
          font-weight: 400;
          font-style: italic;
        }
        .sched-sessions-row {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-top: 0.25rem;
        }
        .sched-sess-btn {
          background: none;
          border: 1px solid rgba(0, 0, 0, 0.12);
          border-radius: 4px;
          width: 18px;
          height: 18px;
          font-size: 0.75rem;
          line-height: 1;
          cursor: pointer;
          color: #5c5650;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 0;
        }
        .sched-sess-btn:hover {
          background: rgba(0, 0, 0, 0.06);
        }
        .sched-card-top {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-bottom: 0.375rem;
        }
        /* Drag-and-drop */
        .sched-card {
          cursor: grab;
        }
        .sched-card:active {
          cursor: grabbing;
        }
        .sched-card[draggable='true']:active {
          opacity: 0.5;
        }
        .sched-col.drag-over {
          background: rgba(42, 157, 143, 0.06);
          outline: 2px dashed #2a9d8f;
          outline-offset: -4px;
          border-radius: 10px;
        }
        .sched-drop-zone {
          border: 1.5px dashed #ddd8d3;
          border-radius: 8px;
          padding: 0.875rem;
          text-align: center;
          font-size: 0.75rem;
          color: #aeaaa6;
          cursor: pointer;
        }
        .sched-drop-zone:hover {
          border-color: #7c5fc4;
          color: #7c5fc4;
        }

        /* Color Key */
        .sched-key {
          background: #faf8f6;
          border-top: 1px solid #ebe7e3;
          padding: 0.875rem 1.25rem;
          margin-top: 0.75rem;
          display: flex;
          flex-direction: column;
          gap: 0.35rem;
        }
        .sched-key-title {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #8a8279;
          margin-bottom: 0.1rem;
        }
        .sched-key-header {
          display: flex;
          gap: 1rem;
          font-size: 0.75rem;
          font-weight: 700;
          color: #1a1816;
          margin-bottom: 0.1rem;
        }
        .sched-key-item {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          font-size: 0.75rem;
          color: #1a1816;
        }
        .sched-key-swatch {
          display: inline-block;
          width: 36px;
          height: 14px;
          border-radius: 4px;
          flex-shrink: 0;
        }
        .sched-key-swatch.math {
          background: linear-gradient(135deg, #f87171, #ef4444);
        }
        .sched-key-swatch.reading {
          background: linear-gradient(135deg, #4ade80, #22c55e);
        }
        .sched-key-swatch.language {
          background: linear-gradient(135deg, #fde047, #eab308);
        }
        .sched-key-swatch.visual {
          background: linear-gradient(135deg, #fdba74, #fb923c);
          opacity: 0.8;
        }
        .sched-key-swatch.social {
          background: linear-gradient(135deg, #93c5fd, #3b82f6);
        }
        .sched-key-swatch.labeling {
          background: linear-gradient(135deg, #c4b5fd, #8b5cf6);
        }
        .sched-key-swatch.requests {
          background: linear-gradient(135deg, #d1d5db, #9ca3af);
        }

        /* ── Student Full Record ── */
        .sfr-card {
          background: #fff;
          border-radius: 12px;
          border: 1px solid #ebe7e3;
          overflow: hidden;
        }
        .sfr-banner {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.625rem 1.25rem;
          background: #fdf0ee;
        }
        .sfr-realm-badge {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #e05d50;
        }
        .sfr-protected {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.6875rem;
          font-weight: 600;
          color: #e05d50;
        }
        .sfr-student {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding: 1.5rem 1.25rem;
          border-bottom: 1px solid #ebe7e3;
        }
        .sfr-avatar {
          width: 56px;
          height: 56px;
          border-radius: 12px;
          overflow: hidden;
          flex-shrink: 0;
        }
        .sfr-avatar svg {
          width: 100%;
          height: 100%;
        }
        .sfr-name {
          font-size: 1.375rem;
          font-weight: 700;
          margin: 0 0 0.25rem;
          color: #1a1816;
        }
        .sfr-meta {
          font-size: 0.8125rem;
          color: #5c5650;
          line-height: 1.5;
        }
        .sfr-section {
          padding: 1.25rem;
          border-bottom: 1px solid #f5f2ef;
        }
        .sfr-section:last-child {
          border-bottom: none;
        }
        .sfr-section-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
          margin-bottom: 0.875rem;
        }
        .sfr-grid-2 {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.5rem;
        }
        .sfr-field {
          padding: 0.75rem;
          background: #faf8f6;
          border-radius: 6px;
        }
        .sfr-field.allergy {
          background: #fdf0ee;
        }
        .sfr-field-label {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #8a8279;
          margin-bottom: 0.375rem;
        }
        .sfr-field-val {
          font-size: 0.875rem;
          color: #1a1816;
          line-height: 1.4;
        }
        .sfr-docs {
          display: flex;
          flex-direction: column;
        }
        .sfr-doc-row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.75rem 0;
          border-bottom: 1px solid #f5f2ef;
          font-size: 0.875rem;
          color: #1a1816;
        }
        .sfr-doc-row:last-child {
          border-bottom: none;
        }
        .sfr-doc-date {
          margin-left: auto;
          font-size: 0.75rem;
          color: #8a8279;
        }

        /* ── Learning Goals ── */
        .section-tag.goals {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .lg-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 0.75rem 1.25rem;
          background: #faf8f6;
          border-radius: 8px;
          margin-top: 0.5rem;
        }
        .lg-count {
          font-size: 0.8125rem;
          color: #8a8279;
        }
        .btn-add-goal {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.5rem 1rem;
          background: #7c5fc4;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
          font-family: inherit;
          transition: background 0.15s;
        }
        .btn-add-goal:hover {
          background: #6a4fb5;
        }
        .btn-add-goal svg {
          width: 12px;
          height: 12px;
        }
        .lg-cards {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
          gap: 0.75rem;
          margin-top: 0.75rem;
        }
        .lg-card {
          padding: 1rem;
          background: #fffdfb;
          border: 1px solid #f5f2ef;
          border-radius: 8px;
        }
        .lg-card-top {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }
        .lg-domain-tag {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: #7c5fc4;
        }
        .lg-priority-tag {
          font-size: 0.5625rem;
          font-weight: 600;
          text-transform: uppercase;
          padding: 0.125rem 0.375rem;
          border-radius: 3px;
          background: #f0f4ff;
          color: #5b7bc0;
        }
        .lg-priority-tag.high {
          background: #fdf6e8;
          color: #c08b30;
        }
        .lg-card-title {
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
          margin-bottom: 0.375rem;
        }
        .lg-card-student {
          display: inline-flex; align-items: center; gap: 0.25rem;
          font-size: 0.6875rem; font-weight: 600; color: #7c5fc4;
          margin-bottom: 0.375rem;
        }
        .lg-card-meta {
          display: flex;
          gap: 0.5rem;
          font-size: 0.6875rem;
          color: #8a8279;
          flex-wrap: wrap;
        }
        .staff-add-card {
          min-height: 96px;
          border: 1.5px dashed #d4c8f0;
          border-radius: 10px;
          background: transparent;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition:
            border-color 0.15s,
            background 0.15s;
          font-family: inherit;
          color: #c8b8f0;
        }
        .staff-add-card:hover {
          border-color: #7c5fc4;
          background: #f9f6ff;
          color: #7c5fc4;
        }
        .staff-add-card svg {
          width: 28px;
          height: 28px;
          stroke-width: 1.5;
        }

        .lg-add-card {
          min-height: 96px;
          border: 1.5px dashed #d4c8f0;
          border-radius: 8px;
          background: transparent;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition:
            border-color 0.15s,
            background 0.15s;
          font-family: inherit;
          color: #c8b8f0;
        }
        .lg-add-card:hover {
          border-color: #7c5fc4;
          background: #f9f6ff;
          color: #7c5fc4;
        }
        .lg-add-card svg {
          width: 28px;
          height: 28px;
          stroke-width: 1.5;
        }

        /* ── Goal Modal ── */
        .modal-backdrop {
          position: fixed;
          inset: 0;
          background: rgba(26, 24, 22, 0.5);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9999;
        }
        .modal-card {
          background: #fff;
          border-radius: 16px;
          width: 100%;
          box-shadow: 0 12px 48px rgba(26, 24, 22, 0.2);
          overflow: hidden;
        }
        .goal-modal {
          max-width: 560px;
        }
        .modal-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 1.25rem 1.5rem;
          border-bottom: 1px solid #f5f2ef;
        }
        .modal-title {
          font-size: 1.125rem;
          font-weight: 600;
          margin: 0;
          color: #1a1816;
        }
        .modal-close {
          background: none;
          border: none;
          font-size: 1.25rem;
          color: #8a8279;
          cursor: pointer;
          padding: 0.25rem;
        }
        .modal-body {
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
          max-height: 65vh;
          overflow-y: auto;
        }
        .modal-footer {
          display: flex;
          justify-content: flex-end;
          gap: 0.75rem;
          padding: 1rem 1.5rem;
          border-top: 1px solid #f5f2ef;
        }
        .form-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .form-label {
          font-size: 0.625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #8a8279;
        }
        .form-input,
        .form-select,
        .form-textarea {
          padding: 0.5rem 0.75rem;
          border: 1px solid #e5e2df;
          border-radius: 6px;
          font-size: 0.875rem;
          font-family: inherit;
          color: #1a1816;
          background: white;
        }
        .form-input:focus,
        .form-select:focus,
        .form-textarea:focus {
          outline: none;
          border-color: #7c5fc4;
          box-shadow: 0 0 0 2px rgba(124, 95, 196, 0.15);
        }
        .form-hint {
          font-size: 0.625rem;
          color: #8a8279;
          margin-top: 0.125rem;
        }
        .form-textarea {
          min-height: 80px;
          resize: vertical;
        }
        .form-row-2 {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1rem;
        }
        .mastery-preview {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          background: #faf8f6;
          border-radius: 6px;
        }
        .mastery-preview-label {
          font-size: 0.625rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: #8a8279;
          white-space: nowrap;
        }
        .mastery-preview-bar {
          flex: 1;
          height: 6px;
          background: #f5f2ef;
          border-radius: 3px;
          overflow: hidden;
        }
        .mastery-preview-fill {
          height: 100%;
          background: #2a9d8f;
          border-radius: 3px;
          transition: width 0.2s;
        }
        .mastery-preview-pct {
          font-size: 0.875rem;
          font-weight: 700;
          color: #2a9d8f;
        }
        .btn-cancel {
          padding: 0.5rem 1rem;
          background: white;
          border: 1px solid #e5e2df;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-weight: 500;
          color: #5c5650;
          cursor: pointer;
          font-family: inherit;
        }
        .btn-save-goal {
          padding: 0.5rem 1.25rem;
          background: #7c5fc4;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
          font-family: inherit;
          transition: background 0.15s;
        }
        .btn-save-goal:hover {
          background: #6a4fb5;
        }
        .btn-save-goal:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }
        .goal-error {
          padding: 0.5rem 0.75rem;
          background: #fdf0ee;
          border-left: 3px solid #e05d50;
          border-radius: 4px;
          font-size: 0.8125rem;
          color: #e05d50;
        }

        /* ── Class Progress Overview ── */
        .cpo-search-bar { margin-bottom: 0.75rem; }
        .cpo-search-input {
          width: 100%; box-sizing: border-box; font-family: inherit; font-size: 0.8125rem;
          padding: 0.5rem 0.75rem; background: #faf8f6; border: 1px solid #ebe7e3;
          border-radius: 6px; color: #1a1816;
        }
        .cpo-search-input::placeholder { color: #8a8279; }
        .cpo-pagination {
          display: flex; align-items: center; justify-content: center;
          gap: 0.75rem; padding: 0.75rem 0;
        }
        .cpo-page-btn {
          font-family: inherit; font-size: 0.75rem; font-weight: 600;
          color: #7c5fc4; background: none; border: 1px solid #ebe7e3;
          border-radius: 4px; padding: 0.25rem 0.625rem; cursor: pointer;
        }
        .cpo-page-btn:disabled { opacity: 0.3; cursor: not-allowed; }
        .cpo-page-label { font-size: 0.75rem; color: #8a8279; }
        .cpo-grid {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          max-height: 330px;
          overflow-y: auto;
        }
        .cpo-card {
          background: #fff;
          border-radius: 12px;
          border: 1px solid #ebe7e3;
          padding: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
          cursor: pointer;
          text-align: left;
          font-family: inherit;
          transition:
            border-color 0.12s,
            box-shadow 0.12s;
          flex: 1 1 calc(25% - 0.75rem);
          min-width: 180px;
          max-width: calc(50% - 0.375rem);
        }
        .cpo-card:hover {
          border-color: #ccc;
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
        }
        .cpo-card.selected {
          border-color: #2a9d8f;
          box-shadow: 0 0 0 2px rgba(42, 157, 143, 0.18);
        }
        .cpo-card.alert {
          background: #fff8f8;
          border-color: #f9c8c4;
        }
        .cpo-card.alert.selected {
          border-color: #e05d50;
          box-shadow: 0 0 0 2px rgba(224, 93, 80, 0.18);
        }
        .cpo-student-row {
          display: flex;
          align-items: center;
          gap: 0.625rem;
        }
        .cpo-avatar {
          width: 36px;
          height: 36px;
          border-radius: 8px;
          overflow: hidden;
          flex-shrink: 0;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .cpo-avatar svg {
          width: 100%;
          height: 100%;
        }
        .cpo-initials {
          font-size: 0.75rem;
          font-weight: 700;
          color: #3d2314;
        }
        .cpo-name {
          font-size: 0.9375rem;
          font-weight: 600;
          color: #1a1816;
          flex: 1;
        }
        .cpo-delta {
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .cpo-delta.up {
          color: #2a9d8f;
        }
        .cpo-delta.down {
          color: #e05d50;
        }
        .cpo-delta.flat {
          color: #c08b30;
        }
        .cpo-sparkline {
          width: 100%;
          height: 30px;
          display: block;
        }
        .cpo-stats {
          display: flex;
          justify-content: space-between;
          font-size: 0.75rem;
          color: #8a8279;
        }
        .cpo-stat-warn {
          color: #e05d50;
          font-weight: 600;
        }

        .fetch-btn { background: #2a9d8f !important; }
        .fetch-btn:disabled { opacity: 0.5; cursor: wait; }
        .profile-fetch-bar {
          padding: 0.5rem 1rem; font-size: 0.75rem; font-weight: 500;
          border-radius: 6px; margin-bottom: 0.75rem;
        }
        .pfb-success { background: rgba(42,157,143,0.1); color: #2a9d8f; }
        .pfb-error { background: rgba(224,93,80,0.1); color: #e05d50; }
        .pfb-info { background: #f5f2ef; color: #5c5650; }
        .admin-profile-list { display: flex; flex-direction: column; }
        .admin-profile-row {
          display: flex; align-items: center; gap: 0.75rem;
          padding: 0.625rem 0.75rem; border-bottom: 1px solid #f5f2ef;
          font-size: 0.8125rem;
        }
        .admin-profile-row:last-child { border-bottom: none; }
        .apr-name { font-weight: 600; color: #1a1816; flex: 1; }
        .apr-grade { font-size: 0.75rem; color: #5c5650; }
        .apr-id { font-size: 0.6875rem; color: #8a8279; }
        .student-profiles-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
          gap: 0.75rem;
        }

        .student-profile-item {
          border-radius: 10px;
          overflow: hidden;
        }

        /* Cross-nav */
        .cross-nav { display: flex; gap: 1rem; padding: 0.5rem 0; margin-bottom: 0.5rem; }
        .cross-nav-link { font-size: 0.75rem; font-weight: 600; color: #7c5fc4; text-decoration: none; }
        .cross-nav-link:hover { text-decoration: underline; }
        /* Header */
        .admin-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          margin-bottom: 2rem;
          padding-bottom: 1.5rem;
          border-bottom: 1px solid #ebe7e3;
        }
        .realm-badge {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #7c5fc4;
          background: #f4f0fa;
          padding: 0.25rem 0.625rem;
          border-radius: 4px;
          margin-bottom: 0.5rem;
        }
        .admin-title {
          font-size: 1.75rem;
          font-weight: 600;
          margin: 0;
          letter-spacing: -0.02em;
        }
        .admin-btn {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.5rem 1rem;
          border-radius: 8px;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
          border: none;
        }
        .admin-btn.primary {
          background: #2a9d8f;
          color: white;
        }
        .admin-btn.cancel {
          background: #fdf0ee;
          color: #e05d50;
        }

        /* Section layout */
        .admin-section {
          margin-bottom: 2.5rem;
        }
        .section-label {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 1rem;
        }
        .section-tag {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.2rem 0.5rem;
          border-radius: 3px;
        }
        .section-tag.admin {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .section-tag.table {
          background: #e8f6f4;
          color: #2a9d8f;
        }
        .section-tag.tracking {
          background: #e8f6f4;
          color: #2a9d8f;
        }

        /* Tracking Card */
        .tl-header {
          display: flex; justify-content: space-between; align-items: center;
          margin-bottom: 1rem; flex-wrap: wrap; gap: 0.75rem;
        }
        .tl-student-name { font-size: 1.125rem; font-weight: 600; color: #1a1816; }
        .tl-goal-selector { display: flex; align-items: center; gap: 0.5rem; }
        .tl-goal-select {
          font-family: inherit; font-size: 0.8125rem; padding: 0.375rem 0.75rem;
          border: 1px solid #ebe7e3; border-radius: 6px; color: #1a1816; background: white;
          max-width: 320px;
        }
        .tl-no-goals { font-size: 0.75rem; color: #8a8279; font-style: italic; }
        .tl-goal-title {
          font-size: 1rem; font-weight: 600; color: #1a1816; margin-bottom: 0.75rem;
        }
        .tl-svg { width: 100%; height: auto; }
        .tl-x-label { text-align: center; font-size: 0.6875rem; color: #8a8279; margin-top: 0.25rem; }
        .tl-empty {
          display: flex; flex-direction: column; align-items: center; justify-content: center;
          padding: 3rem 1rem; gap: 0.5rem;
        }
        .tl-empty-icon { opacity: 0.4; }
        .tl-empty-text { font-size: 0.9375rem; font-weight: 600; color: #5c5650; }
        .tl-empty-sub { font-size: 0.75rem; color: #8a8279; }
        .tracking-card {
          background: #fff;
          border-radius: 12px;
          border: 1px solid #ebe7e3;
          overflow: hidden;
        }
        .tracking-student {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 1rem 1.25rem;
          border-bottom: 1px solid #ebe7e3;
        }
        .tracking-avatar {
          width: 40px;
          height: 40px;
          border-radius: 10px;
          overflow: hidden;
          flex-shrink: 0;
        }
        .tracking-avatar svg {
          width: 100%;
          height: 100%;
        }
        .tracking-name {
          font-size: 0.9375rem;
          font-weight: 600;
          color: #1a1816;
        }
        .tracking-goal {
          font-size: 0.75rem;
          color: #8a8279;
          max-width: 220px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .tracking-name-link {
          text-decoration: none;
          color: #1a1816;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
        }
        .tracking-name-link:hover {
          color: #2a9d8f;
        }
        .tracking-link-icon {
          width: 11px;
          height: 11px;
          opacity: 0;
          transition: opacity 0.15s;
          flex-shrink: 0;
        }
        .tracking-name-link:hover .tracking-link-icon {
          opacity: 0.7;
        }
        .tracking-student-selector {
          position: relative;
          flex-shrink: 0;
        }
        .student-select-btn {
          display: flex;
          align-items: center;
          gap: 0.35rem;
          background: #faf8f6;
          border: 1px solid #ebe7e3;
          border-radius: 8px;
          padding: 0.35rem 0.6rem;
          font-size: 0.75rem;
          font-weight: 600;
          color: #1a1816;
          cursor: pointer;
        }
        .student-select-btn:hover {
          border-color: #ccc;
          background: #f5f2ef;
        }
        .select-chevron {
          width: 10px;
          height: 6px;
          transition: transform 0.15s;
        }
        .select-chevron.open {
          transform: rotate(180deg);
        }
        .student-dropdown {
          position: absolute;
          top: calc(100% + 4px);
          right: 0;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 10px;
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
          z-index: 20;
          min-width: 200px;
          padding: 0.3rem;
        }
        .student-dropdown-item {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          width: 100%;
          background: none;
          border: none;
          padding: 0.5rem 0.65rem;
          border-radius: 7px;
          cursor: pointer;
          text-align: left;
          font-size: 0.8125rem;
          color: #1a1816;
        }
        .student-dropdown-item:hover {
          background: #faf8f6;
        }
        .student-dropdown-item.active {
          background: #e8f6f4;
          color: #2a9d8f;
        }
        .sdd-initials {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 26px;
          height: 26px;
          border-radius: 7px;
          background: #f0e6d8;
          font-size: 0.625rem;
          font-weight: 700;
          color: #5c5650;
          flex-shrink: 0;
        }
        .student-dropdown-item.active .sdd-initials {
          background: #d0ece8;
          color: #2a9d8f;
        }
        .sdd-name {
          font-weight: 500;
        }
        .sdd-search-wrap {
          display: flex;
          align-items: center;
          gap: 0.4rem;
          padding: 0.4rem 0.5rem;
          border-bottom: 1px solid #ebe7e3;
          margin-bottom: 0.2rem;
        }
        .sdd-search-icon {
          width: 14px;
          height: 14px;
          flex-shrink: 0;
        }
        .sdd-search-input {
          border: none;
          outline: none;
          font-size: 0.8125rem;
          color: #1a1816;
          width: 100%;
          background: transparent;
          font-family: inherit;
        }
        .sdd-search-input::placeholder {
          color: #b0a99f;
        }
        .sdd-no-results {
          padding: 0.75rem 0.65rem;
          font-size: 0.8125rem;
          color: #8a8279;
          text-align: center;
        }
        .date-range-bar {
          padding: 0.75rem 1.25rem;
          border-bottom: 1px solid #ebe7e3;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .date-presets {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
        }
        .preset-btn {
          background: #faf8f6;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          font-size: 0.6875rem;
          font-weight: 500;
          padding: 0.3rem 0.65rem;
          cursor: pointer;
          color: #5c5650;
          transition: all 0.12s;
        }
        .preset-btn:hover {
          border-color: #ccc;
          background: #f0ede9;
        }
        .preset-btn.active {
          background: #1a1816;
          color: #fff;
          border-color: #1a1816;
        }
        .custom-date-row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .date-label {
          font-size: 0.6875rem;
          font-weight: 600;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .date-input {
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.3rem 0.5rem;
          font-size: 0.75rem;
          color: #1a1816;
          font-family: inherit;
          background: #fff;
        }
        .date-input:focus {
          outline: none;
          border-color: #2a9d8f;
        }
        .date-range-label {
          font-size: 0.75rem;
          color: #8a8279;
        }
        .tracking-chart {
          padding: 1.25rem 1.25rem 0.5rem;
        }
        .chart-skill-label {
          font-size: 0.875rem;
          font-weight: 600;
          margin-bottom: 0.75rem;
          color: #1a1816;
        }
        .chart-svg {
          width: 100%;
          height: 220px;
          display: block;
        }
        .chart-empty {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 2.5rem 1rem;
          min-height: 200px;
        }
        .chart-empty-icon {
          width: 48px;
          height: 48px;
          margin-bottom: 0.75rem;
          opacity: 0.5;
        }
        .chart-empty-icon svg {
          width: 100%;
          height: 100%;
        }
        .chart-empty-text {
          font-size: 0.9375rem;
          font-weight: 600;
          color: #8a8279;
          margin-bottom: 0.25rem;
        }
        .chart-empty-sub {
          font-size: 0.75rem;
          color: #b0a99f;
        }
        .tracking-legend {
          display: flex;
          gap: 1.5rem;
          justify-content: center;
          padding: 0.75rem 0;
          font-size: 0.75rem;
          color: #5c5650;
        }
        .tl-item {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .tl-line {
          display: inline-block;
          width: 20px;
          height: 2px;
          border-radius: 2px;
        }
        .tl-line.teal {
          background: #2a9d8f;
        }
        .tl-line.amber {
          background: #c08b30;
        }
        .tracking-stats {
          display: grid;
          grid-template-columns: 1fr 1fr 1fr;
          border-top: 1px solid #ebe7e3;
        }
        .tracking-stat {
          display: flex;
          flex-direction: column;
          align-items: center;
          padding: 1rem;
          border-right: 1px solid #ebe7e3;
        }
        .tracking-stat:last-child {
          border-right: none;
        }
        .stat-value {
          font-size: 1.5rem;
          font-weight: 700;
          letter-spacing: -0.02em;
          color: #1a1816;
        }
        .stat-value.good {
          color: #2a9d8f;
        }
        .stat-label {
          font-size: 0.75rem;
          color: #8a8279;
          margin-top: 0.125rem;
        }

        /* Program Index */
        .prog-index-card {
          background: #fff;
          border-radius: 12px;
          border: 1px solid #ebe7e3;
          overflow: hidden;
        }
        .pi-header {
          padding: 1rem 1.25rem;
          border-bottom: 1px solid #ebe7e3;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .pi-title-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .pi-title {
          font-size: 1.125rem;
          font-weight: 700;
          margin: 0;
          color: #1a1816;
        }
        .pi-student-picker-wrap {
          position: relative;
        }
        .pi-student-chip {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-family: inherit;
          font-size: 0.8125rem;
          color: #5c5650;
          background: #faf8f6;
          border: 1px solid #ebe7e3;
          border-radius: 100px;
          padding: 0.3rem 0.75rem;
          cursor: pointer;
          transition: border-color 0.15s;
        }
        .pi-student-chip:hover {
          border-color: #c4bdb6;
        }
        .pi-student-avatar {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 22px;
          height: 22px;
          border-radius: 50%;
          background: #c08b30;
          color: #fff;
          font-size: 0.625rem;
          font-weight: 700;
        }
        .pi-student-dropdown {
          position: absolute;
          top: calc(100% + 4px);
          left: 0;
          min-width: 240px;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 8px;
          box-shadow: 0 8px 24px rgba(26,24,22,0.12);
          z-index: 100;
          overflow: hidden;
        }
        .pi-student-search {
          width: 100%;
          padding: 0.5rem 0.75rem;
          border: none;
          border-bottom: 1px solid #ebe7e3;
          font-family: inherit;
          font-size: 0.8125rem;
          outline: none;
          box-sizing: border-box;
        }
        .pi-student-list {
          max-height: 240px;
          overflow-y: auto;
        }
        .pi-student-item {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          width: 100%;
          padding: 0.5rem 0.75rem;
          border: none;
          background: transparent;
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          cursor: pointer;
          text-align: left;
        }
        .pi-student-item:hover {
          background: #faf8f6;
        }
        .pi-student-item.selected {
          background: #f5f0eb;
          font-weight: 600;
        }
        .pi-student-item-avatar {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: #e8e2dc;
          color: #5c5650;
          font-size: 0.625rem;
          font-weight: 700;
          flex-shrink: 0;
        }
        .pi-student-item-name {
          flex: 1;
        }
        .pi-student-check {
          color: #2a9d8f;
          font-weight: 700;
        }
        .pi-student-empty {
          padding: 1rem;
          text-align: center;
          color: #8a8279;
          font-size: 0.8125rem;
        }
        .pi-all-students {
          border-bottom: 1px solid #ebe7e3;
        }
        .pi-all-avatar {
          background: #5c5650 !important;
          font-size: 0.5rem !important;
          letter-spacing: 0.03em;
        }
        .pi-empty-state {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 3rem 1rem;
          gap: 1rem;
        }
        .pi-empty-text {
          font-size: 0.875rem;
          color: #8a8279;
          margin: 0;
        }
        .pi-add-btn.disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }
        .pi-mat-section {
          padding: 0.75rem 1.25rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .pi-mat-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .pi-mat-add-btn {
          font-family: inherit;
          font-size: 0.75rem;
          font-weight: 600;
          color: #2a9d8f;
          background: none;
          border: 1px dashed #2a9d8f;
          border-radius: 4px;
          padding: 0.25rem 0.5rem;
          cursor: pointer;
        }
        .pi-mat-add-btn:hover { background: #e8f6f4; }
        .pi-mat-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
        }
        .pi-mat-type { width: 100px; flex-shrink: 0; }
        .pi-mat-name { flex: 1; }
        .pi-mat-detail { flex: 1; }
        .pi-mat-remove {
          background: none;
          border: none;
          color: #e05d50;
          font-size: 1rem;
          cursor: pointer;
          padding: 0.25rem;
        }
        .pi-mat-remove:hover { color: #c0392b; }
        .pi-mat-cell {
          padding: 0.375rem 0.5rem;
          max-width: 200px;
          position: relative;
        }
        .pi-mat-tag {
          font-size: 0.6875rem;
          padding: 0.15rem 0.375rem;
          border-radius: 3px;
          margin-bottom: 0.2rem;
          line-height: 1.3;
        }
        .pi-mat-tag.primary {
          background: #fde8e8;
          color: #e05d50;
        }
        .pi-mat-tag.secondary {
          background: #f5f2ef;
          color: #5c5650;
        }
        .pi-mat-empty {
          font-size: 0.6875rem;
          color: #c4bdb6;
          font-style: italic;
        }
        .pi-mat-editor {
          position: fixed;
          top: 50%;
          left: 50%;
          transform: translate(-50%, -50%);
          z-index: 9999;
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          min-width: 520px;
          padding: 0.75rem;
          background: #fffdfb;
          border: 1.5px solid #c08b30;
          border-radius: 8px;
          box-shadow: 0 8px 24px rgba(0,0,0,0.2);
        }
        .pi-mat-edit-row {
          display: flex;
          gap: 0.375rem;
          align-items: center;
        }
        .pi-mat-edit-actions {
          display: flex;
          gap: 0.375rem;
          justify-content: flex-end;
          padding-top: 0.25rem;
          border-top: 1px solid #ebe7e3;
        }
        .pi-mat-save-btn {
          font-family: inherit;
          font-size: 0.6875rem;
          font-weight: 600;
          color: white;
          background: #2a9d8f;
          border: none;
          border-radius: 4px;
          padding: 0.25rem 0.625rem;
          cursor: pointer;
        }
        .pi-mat-save-btn:hover { background: #238b7e; }
        .pi-mat-cancel-btn {
          font-family: inherit;
          font-size: 0.6875rem;
          color: #5c5650;
          background: none;
          border: 1px solid #ebe7e3;
          border-radius: 4px;
          padding: 0.25rem 0.5rem;
          cursor: pointer;
        }
        .pi-controls {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .pi-filter {
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.375rem 0.625rem;
          cursor: pointer;
          outline: none;
        }
        .pi-add-btn {
          font-family: inherit;
          font-size: 0.8125rem;
          font-weight: 600;
          color: white;
          background: #e05d50;
          border: none;
          border-radius: 6px;
          padding: 0.375rem 0.875rem;
          cursor: pointer;
          margin-left: auto;
        }
        .pi-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.8125rem;
        }
        .pi-table th {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #8a8279;
          padding: 0.625rem 0.75rem;
          text-align: left;
          border-bottom: 1px solid #ebe7e3;
          white-space: nowrap;
        }
        .pi-table td {
          padding: 0.75rem;
          border-bottom: 1px solid #f5f2ef;
          color: #1a1816;
          vertical-align: top;
          font-size: 0.8125rem;
          line-height: 1.4;
        }
        .pi-tag {
          font-size: 0.6875rem;
          font-weight: 500;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          white-space: nowrap;
        }
        .pi-tag.math {
          background: #fee2e2;
          color: #dc2626;
        }
        .pi-tag.visual {
          background: #ccfbf1;
          color: #0d9488;
        }
        .pi-tag.reading {
          background: #dcfce7;
          color: #16a34a;
        }
        .pi-tag.language {
          background: #fef9c3;
          color: #ca8a04;
        }
        .pi-tag.receptive {
          background: #fff7ed;
          color: #c2410c;
        }
        .pi-tag.requests {
          background: #fce7f3;
          color: #be185d;
        }
        .pi-tag.finemotor {
          background: #ede9fe;
          color: #7c3aed;
        }
        .pi-tag.labeling {
          background: #e0f2fe;
          color: #0369a1;
        }
        .pi-tag.grossmotor {
          background: #d1fae5;
          color: #059669;
        }
        .pi-tag.social {
          background: #e0e7ff;
          color: #4338ca;
        }
        .pi-yes {
          color: #2a9d8f;
          font-weight: 600;
        }
        .pi-no {
          color: #8a8279;
        }
        .pi-note {
          font-size: 0.75rem;
          color: #8a8279;
          font-style: italic;
        }
        .pi-note.discontinued {
          color: #e05d50;
          font-style: normal;
          font-weight: 500;
        }
        .pi-footer {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          padding: 0.875rem;
          border-top: 1px solid #ebe7e3;
        }
        .pi-range {
          font-size: 0.875rem;
          font-weight: 500;
          color: #1a1816;
        }
        /* View toggle */
        .pi-view-toggle {
          display: flex;
          gap: 2px;
          background: #f5f2ef;
          border-radius: 7px;
          padding: 2px;
        }
        .pi-view-btn {
          background: none;
          border: none;
          border-radius: 5px;
          padding: 0.3rem 0.4rem;
          cursor: pointer;
          color: #8a8279;
          display: flex;
          align-items: center;
        }
        .pi-view-btn.active {
          background: #fff;
          color: #1a1816;
          box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        }
        /* Sortable column headers */
        .pi-table th.sortable {
          cursor: pointer;
          user-select: none;
        }
        .pi-table th.sortable:hover {
          color: #1a1816;
        }
        .pi-table td.prog-name {
          font-weight: 500;
        }
        .pi-editable {
          cursor: default;
          position: relative;
        }
        .pi-editable:hover {
          background: #faf8f6;
        }
        .pi-cell-input {
          width: 100%;
          padding: 0.25rem 0.375rem;
          border: 1.5px solid #c08b30;
          border-radius: 4px;
          font-family: inherit;
          font-size: 0.8125rem;
          outline: none;
          background: #fffdfb;
          box-sizing: border-box;
        }
        .pi-cell-input.sm {
          width: 80px;
        }
        .pi-cell-input.wide {
          min-width: 160px;
        }
        .pi-cell-select {
          padding: 0.25rem 0.375rem;
          border: 1.5px solid #c08b30;
          border-radius: 4px;
          font-family: inherit;
          font-size: 0.8125rem;
          outline: none;
          background: #fffdfb;
          cursor: pointer;
        }
        .pi-cell-select.sm {
          width: 70px;
        }
        .pi-table td.pi-code {
          font-family: monospace;
          font-size: 0.8rem;
          color: #5c5650;
        }
        .pi-table td.pi-check {
          text-align: center;
          padding: 0.5rem;
        }
        .pi-table td.pi-date {
          color: #8a8279;
          white-space: nowrap;
          font-size: 0.8rem;
        }
        .pi-table td.pi-target {
          max-width: 220px;
        }
        /* Check icons */
        .check-icon {
          font-size: 0.8rem;
          font-weight: 700;
        }
        .check-icon.yes {
          color: #16a34a;
        }
        .check-icon.no {
          color: #d1d5db;
        }
        /* Discontinued row */
        .pi-table tr.discontinued-row td {
          color: #b5b0aa;
        }
        .pi-table tr.discontinued-row .pi-tag {
          opacity: 0.5;
        }
        .pi-table tr.discontinued-row .prog-name {
          text-decoration: line-through;
          color: #b5b0aa;
        }
        /* Card grid view */
        .pi-card-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
          gap: 0.875rem;
          padding: 1rem 1.25rem;
        }
        .pi-card-item {
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 10px;
          padding: 0.875rem;
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
        }
        .pi-card-item.discontinued {
          opacity: 0.55;
        }
        .pi-card-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.25rem;
        }
        .pi-card-name {
          font-weight: 600;
          font-size: 0.875rem;
          color: #1a1816;
          line-height: 1.3;
        }
        .pi-card-meta {
          display: flex;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .pi-card-code {
          font-size: 0.75rem;
          font-family: monospace;
          background: #f5f2ef;
          color: #5c5650;
          padding: 0.1rem 0.35rem;
          border-radius: 4px;
        }
        .pi-card-date {
          font-size: 0.75rem;
          color: #8a8279;
        }
        .pi-card-target {
          font-size: 0.8rem;
          color: #5c5650;
          line-height: 1.4;
          border-top: 1px solid #f5f2ef;
          padding-top: 0.375rem;
          margin-top: 0.125rem;
        }
        .pi-card-sheets {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
        }
        .sheet-badge {
          font-size: 0.6875rem;
          padding: 0.15rem 0.4rem;
          border-radius: 4px;
          font-weight: 500;
        }
        .sheet-badge.ready {
          background: #dcfce7;
          color: #16a34a;
        }
        .sheet-badge.missing {
          background: #fee2e2;
          color: #dc2626;
        }
        .pi-card-notes {
          font-size: 0.75rem;
          color: #e05d50;
          font-style: italic;
        }
        /* Color legend */
        .pi-legend {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          padding: 0.75rem 1.25rem;
          border-top: 1px solid #f5f2ef;
          background: #faf8f6;
        }
        .pi-legend-item {
          display: flex;
          align-items: center;
        }
        /* Program Index dropdowns */
        .pi-drop-wrap {
          position: relative;
        }
        .pi-drop-btn {
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.375rem 0.625rem;
          cursor: pointer;
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .pi-drop-menu {
          position: absolute;
          top: calc(100% + 4px);
          left: 0;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 8px;
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
          z-index: 30;
          min-width: 160px;
          padding: 0.25rem;
        }
        .pi-drop-item {
          display: block;
          width: 100%;
          text-align: left;
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          background: none;
          border: none;
          padding: 0.5rem 0.75rem;
          cursor: pointer;
          border-radius: 5px;
        }
        .pi-drop-item:hover {
          background: #f5f2ef;
        }
        .pi-drop-item.selected {
          color: #3b82f6;
          font-weight: 600;
        }
        /* Add Program form */
        .pi-add-form {
          padding: 1rem 1.25rem;
          background: #f5f2ef;
          border-bottom: 1px solid #ebe7e3;
        }
        .pi-add-fields {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          margin-bottom: 0.75rem;
        }
        .pi-add-group {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 130px;
        }
        .pi-add-group.wide {
          flex: 1 1 240px;
        }
        .pi-add-label {
          font-size: 0.6875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #5c5650;
        }
        .pi-add-input {
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.375rem 0.5rem;
          outline: none;
        }
        .pi-add-input:focus {
          border-color: #2a9d8f;
        }
        .pi-add-select {
          font-family: inherit;
          font-size: 0.8125rem;
          color: #1a1816;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.375rem 0.5rem;
        }
        .pi-add-actions {
          display: flex;
          justify-content: flex-end;
          gap: 0.5rem;
        }
        .pi-cancel-btn {
          font-family: inherit;
          font-size: 0.8125rem;
          color: #5c5650;
          background: #fff;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          padding: 0.375rem 0.875rem;
          cursor: pointer;
        }
        .pi-submit-btn {
          font-family: inherit;
          font-size: 0.8125rem;
          font-weight: 600;
          color: #fff;
          background: #e05d50;
          border: none;
          border-radius: 6px;
          padding: 0.375rem 0.875rem;
          cursor: pointer;
        }
        .section-name {
          font-size: 0.875rem;
          font-weight: 600;
          color: #5c5650;
        }
        .staff-count {
          font-size: 0.75rem;
          color: #8a8279;
          margin-left: auto;
        }

        /* Add Staff Form */
        .add-staff-form {
          padding: 1rem;
          background: #f4f0fa;
          border-radius: 8px;
          margin-bottom: 1rem;
          border: 1px solid #ebe0f5;
        }
        .asf-fields {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          margin-bottom: 0.75rem;
        }
        .asf-group {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 120px;
          flex: 1;
        }
        .asf-group.wide {
          flex: 2;
          min-width: 200px;
        }
        .asf-group.narrow {
          flex: 0 0 90px;
        }
        .asf-label {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #7c5fc4;
        }
        .asf-input,
        .asf-select {
          padding: 0.375rem 0.625rem;
          border: 1px solid #d4c8f0;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-family: 'Inter', system-ui, sans-serif;
          background: white;
          color: #1a1816;
          outline: none;
        }
        .asf-input:focus,
        .asf-select:focus {
          border-color: #7c5fc4;
          box-shadow: 0 0 0 2px rgba(124, 95, 196, 0.15);
        }
        .asf-actions {
          display: flex;
          justify-content: flex-end;
        }

        /* Staff grid */
        .staff-search-bar { padding: 0.75rem 0; }
        .staff-search-input {
          width: 100%; box-sizing: border-box; font-family: inherit; font-size: 0.8125rem;
          padding: 0.5rem 0.75rem; background: #faf8f6; border: 1px solid #ebe7e3;
          border-radius: 6px; color: #1a1816;
        }
        .staff-search-input::placeholder { color: #8a8279; }
        .staff-pagination {
          display: flex; align-items: center; justify-content: center;
          gap: 0.75rem; padding: 0.75rem 0;
        }
        .sp-btn {
          font-family: inherit; font-size: 0.75rem; font-weight: 600;
          color: #7c5fc4; background: none; border: 1px solid #ebe7e3;
          border-radius: 4px; padding: 0.25rem 0.625rem; cursor: pointer;
        }
        .sp-btn:disabled { opacity: 0.3; cursor: not-allowed; }
        .sp-label { font-size: 0.75rem; color: #8a8279; }
        .staff-cards-direct {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 0.875rem;
        }
        .staff-card-item {
          background: #fffdfb;
          border-radius: 10px;
          box-shadow: 0 1px 2px rgba(26, 24, 22, 0.04);
          padding: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          position: relative;
        }
        .staff-card-item.staff-new {
          background: #f9f6ff;
          border: 1px solid #ebe0f5;
        }
        .staff-del-btn {
          position: absolute;
          top: 0.5rem;
          right: 0.5rem;
          width: 20px;
          height: 20px;
          border-radius: 4px;
          border: none;
          background: transparent;
          color: #c8c2bc;
          font-size: 0.6875rem;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition:
            background 0.1s,
            color 0.1s;
        }
        .staff-del-btn:hover {
          background: #fdf0ee;
          color: #e05d50;
        }
        .sci-avatar {
          width: 44px;
          height: 44px;
          border-radius: 11px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.875rem;
          font-weight: 700;
          color: white;
        }
        .sci-avatar.teal {
          background: #2a9d8f;
        }
        .sci-avatar.purple {
          background: #7c5fc4;
        }
        .sci-avatar.coral {
          background: #e05d50;
        }
        .sci-avatar.amber {
          background: #c08b30;
        }
        .sci-name {
          display: block;
          font-size: 0.9375rem;
          font-weight: 600;
          color: #1a1816;
        }
        .sci-role {
          display: block;
          font-size: 0.75rem;
          color: #8a8279;
        }
        .sci-meta {
          display: flex;
          gap: 0.75rem;
        }
        .sci-stat {
          font-size: 0.6875rem;
          color: #5c5650;
          background: #faf8f6;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
        }
        .sci-status {
          display: inline-block;
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          align-self: flex-start;
        }
        .sci-status.Active {
          background: #e8f6f4;
          color: #2a9d8f;
        }
        .sci-status.Pending {
          background: #fdf6e8;
          color: #c08b30;
        }
        .staff-edit-btn {
          position: absolute;
          top: 0.5rem;
          right: 1.75rem;
          width: 20px;
          height: 20px;
          border-radius: 4px;
          border: none;
          background: transparent;
          color: #c8c2bc;
          font-size: 0.75rem;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition:
            background 0.1s,
            color 0.1s;
        }
        .staff-edit-btn:hover {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .staff-card-item.editing {
          background: #f9f6ff;
          border: 1px solid #d4c8f0;
        }
        .staff-edit-form {
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
        }
        .sef-row {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .sef-group {
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
          flex: 1;
          min-width: 80px;
        }
        .sef-group.wide {
          flex: 2;
          min-width: 140px;
        }
        .sef-group.narrow {
          flex: 0 0 75px;
        }
        .sef-label {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #7c5fc4;
        }
        .sef-input,
        .sef-select {
          padding: 0.3rem 0.5rem;
          border: 1px solid #d4c8f0;
          border-radius: 5px;
          font-size: 0.75rem;
          font-family: 'Inter', system-ui, sans-serif;
          background: white;
          color: #1a1816;
          outline: none;
        }
        .sef-input:focus,
        .sef-select:focus {
          border-color: #7c5fc4;
          box-shadow: 0 0 0 2px rgba(124, 95, 196, 0.15);
        }
        .sef-actions {
          display: flex;
          gap: 0.5rem;
          justify-content: flex-end;
          margin-top: 0.25rem;
        }
        .sef-actions .action-btn {
          width: auto;
          height: auto;
          padding: 0.375rem 0.875rem;
          font-size: 0.75rem;
          font-weight: 600;
          border-radius: 6px;
        }

        /* Data table */
        .data-table-wrap {
          background: #fffdfb;
          border-radius: 10px;
          box-shadow: 0 1px 2px rgba(26, 24, 22, 0.04);
          overflow: hidden;
        }
        .table-toolbar {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 0.75rem 1rem;
          border-bottom: 1px solid #f5f2ef;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .toolbar-left {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .table-filters {
          display: flex;
          gap: 0.375rem;
          flex-wrap: wrap;
        }

        /* Search input */
        .search-input {
          padding: 0.3125rem 0.625rem;
          border: 1px solid #ebe7e3;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-family: 'Inter', system-ui, sans-serif;
          background: #faf8f6;
          color: #1a1816;
          outline: none;
          width: 185px;
        }
        .search-input:focus {
          border-color: #2a9d8f;
          box-shadow: 0 0 0 2px rgba(42, 157, 143, 0.12);
        }
        .search-input::placeholder {
          color: #b0a89f;
        }

        /* Filter chips */
        .filter-chip {
          font-size: 0.6875rem;
          font-weight: 600;
          padding: 0.25rem 0.625rem;
          border-radius: 5px;
          border: 1px solid #ebe7e3;
          background: #faf8f6;
          color: #5c5650;
          cursor: pointer;
          white-space: nowrap;
        }
        .filter-chip:hover {
          border-color: #c8c2bc;
        }
        .filter-chip.active {
          background: #1a1816;
          color: white;
          border-color: #1a1816;
        }
        .filter-chip.academic.active {
          background: #fdf0ee;
          color: #e05d50;
          border-color: #e05d50;
        }
        .filter-chip.social.active {
          background: #f4f0fa;
          color: #7c5fc4;
          border-color: #7c5fc4;
        }
        .filter-chip.behavioral.active {
          background: #fdf6e8;
          color: #c08b30;
          border-color: #c08b30;
        }
        .table-btn {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.375rem 0.75rem;
          border-radius: 6px;
          font-size: 0.75rem;
          font-weight: 600;
          cursor: pointer;
          border: none;
        }
        .table-btn.primary {
          background: #2a9d8f;
          color: white;
        }
        .table-btn.cancel {
          background: #fdf0ee;
          color: #e05d50;
        }

        /* Add Row Form */
        .add-row-form {
          padding: 1rem;
          background: #f4f0fa;
          border-bottom: 1px solid #ebe0f5;
        }
        .arf-fields {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          margin-bottom: 0.75rem;
        }
        .arf-group {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 120px;
          flex: 1;
        }
        .arf-group.wide {
          flex: 2;
          min-width: 200px;
        }
        .arf-group.narrow {
          flex: 0 0 100px;
        }
        .arf-label {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #7c5fc4;
        }
        .arf-input,
        .arf-select {
          padding: 0.375rem 0.625rem;
          border: 1px solid #d4c8f0;
          border-radius: 6px;
          font-size: 0.8125rem;
          font-family: 'Inter', system-ui, sans-serif;
          background: white;
          color: #1a1816;
          outline: none;
        }
        .arf-input:focus,
        .arf-select:focus {
          border-color: #7c5fc4;
          box-shadow: 0 0 0 2px rgba(124, 95, 196, 0.15);
        }
        .arf-actions {
          display: flex;
          justify-content: flex-end;
        }

        /* Table */
        /* Sortable headers */
        .th-sortable {
          cursor: pointer;
          user-select: none;
          white-space: nowrap;
        }
        .th-sortable:hover {
          color: #2a9d8f;
        }

        .data-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.8125rem;
        }
        .data-table thead tr {
          background: #faf8f6;
        }
        .data-table th {
          padding: 0.625rem 1rem;
          text-align: left;
          font-size: 0.625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #8a8279;
          border-bottom: 1px solid #f5f2ef;
        }
        .data-table td {
          padding: 0.625rem 1rem;
          border-bottom: 1px solid #faf8f6;
          color: #1a1816;
        }
        .data-table tbody tr:last-child td {
          border-bottom: none;
        }
        .data-table tbody tr:hover td {
          background: #faf8f6;
        }
        .row-flagged td {
          background: #fdf8f4 !important;
        }
        .row-new td {
          background: #f4f0fa !important;
        }
        .td-date {
          font-size: 0.75rem;
          color: #5c5650;
          white-space: nowrap;
        }
        .td-student {
          font-weight: 500;
        }
        .type-badge {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.2rem 0.5rem;
          border-radius: 3px;
          white-space: nowrap;
        }
        .type-badge.social {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .type-badge.academic {
          background: #fdf0ee;
          color: #e05d50;
        }
        .type-badge.behavioral {
          background: #fdf6e8;
          color: #c08b30;
        }
        .score-badge {
          font-size: 0.75rem;
          font-weight: 600;
          color: #8a8279;
        }
        .score-badge.good {
          color: #2a9d8f;
        }
        .staff-pip {
          width: 26px;
          height: 26px;
          border-radius: 6px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          font-size: 0.5rem;
          font-weight: 700;
          color: white;
        }
        .staff-pip.teal {
          background: #2a9d8f;
        }
        .staff-pip.purple {
          background: #7c5fc4;
        }
        .staff-pip.coral {
          background: #e05d50;
        }
        .staff-pip.amber {
          background: #c08b30;
        }
        .table-footer {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 1rem;
          border-top: 1px solid #f5f2ef;
          background: #faf8f6;
        }
        .table-count {
          font-size: 0.75rem;
          color: #8a8279;
          margin-left: auto;
        }
        .table-showing {
          font-size: 0.75rem;
          color: #8a8279;
        }
        .obs-pagination {
          display: flex; align-items: center; gap: 0.25rem; margin-left: auto;
        }
        .obs-page-btn {
          font-family: inherit; font-size: 0.6875rem;
          color: #5c5650; background: none; border: 1px solid #ebe7e3;
          border-radius: 4px; padding: 0.2rem 0.5rem; cursor: pointer;
        }
        .obs-page-btn:disabled { opacity: 0.3; cursor: not-allowed; }
        .obs-page-num {
          font-family: inherit; font-size: 0.6875rem; font-weight: 500;
          color: #5c5650; background: none; border: 1px solid #ebe7e3;
          border-radius: 4px; padding: 0.2rem 0.4rem; cursor: pointer; min-width: 1.5rem; text-align: center;
        }
        .obs-page-num.active {
          background: #2a9d8f; color: white; border-color: #2a9d8f; font-weight: 700;
        }
        .staff-filter-select {
          font-family: inherit; font-size: 0.75rem; padding: 0.25rem 0.5rem;
          border: 1px solid #ebe7e3; border-radius: 4px; color: #1a1816; background: white;
        }
        .table-btn.danger {
          background: #fdf0ee;
          color: #e05d50;
        }
        .table-btn.danger:hover {
          background: #fbe0dc;
        }

        /* Checkbox column */
        .td-check {
          width: 36px;
          text-align: center;
          padding: 0.375rem 0.5rem;
        }

        /* Action buttons column */
        .td-actions {
          width: 76px;
          text-align: right;
          white-space: nowrap;
          padding-right: 0.5rem;
        }
        .action-btn {
          width: 24px;
          height: 24px;
          border-radius: 5px;
          border: none;
          background: transparent;
          color: #c8c2bc;
          font-size: 0.9375rem;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition:
            background 0.1s,
            color 0.1s;
        }
        .action-btn.edit:hover {
          background: #e8f6f4;
          color: #2a9d8f;
        }
        .action-btn.dup:hover {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .action-btn.save {
          color: #2a9d8f;
        }
        .action-btn.save:hover {
          background: #e8f6f4;
        }
        .action-btn.cancel-edit {
          color: #e05d50;
        }
        .action-btn.cancel-edit:hover {
          background: #fdf0ee;
        }
        .del-btn {
          width: 22px;
          height: 22px;
          border-radius: 5px;
          border: none;
          background: transparent;
          color: #c8c2bc;
          font-size: 0.75rem;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition:
            background 0.1s,
            color 0.1s;
        }
        .del-btn:hover {
          background: #fdf0ee;
          color: #e05d50;
        }

        /* Inline edit cells */
        .row-editing td {
          background: #fdfcff !important;
        }
        .cell-input {
          padding: 0.25rem 0.375rem;
          border: 1px solid #d4c8f0;
          border-radius: 4px;
          font-size: 0.8125rem;
          font-family: 'Inter', system-ui, sans-serif;
          color: #1a1816;
          outline: none;
          width: 100%;
          min-width: 60px;
          box-sizing: border-box;
        }
        .cell-input:focus {
          border-color: #7c5fc4;
          box-shadow: 0 0 0 2px rgba(124, 95, 196, 0.1);
        }
        .cell-input.narrow {
          width: 64px;
          min-width: 64px;
        }
        .cell-input.goal {
          min-width: 110px;
        }
        .cell-input.initials {
          width: 38px;
          min-width: 38px;
        }
        .cell-select {
          padding: 0.25rem 0.25rem;
          border: 1px solid #d4c8f0;
          border-radius: 4px;
          font-size: 0.75rem;
          background: white;
          color: #1a1816;
          outline: none;
        }
        .cell-select:focus {
          border-color: #7c5fc4;
        }
        .cell-select.color {
          width: 58px;
        }
        .td-staff-edit {
          display: flex;
          gap: 0.25rem;
          align-items: center;
        }

        /* Type count badges */
        .type-counts {
          display: flex;
          gap: 0.375rem;
          margin-left: auto;
          flex-wrap: wrap;
          align-items: center;
        }
        .tc-badge {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
        }
        .tc-badge.academic {
          background: #fdf0ee;
          color: #e05d50;
        }
        .tc-badge.social {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .tc-badge.behavioral {
          background: #fdf6e8;
          color: #c08b30;
        }

        /* Flag button */
        .action-btn.flag {
          font-size: 1rem;
        }
        .action-btn.flag:hover {
          background: #fdf6e8;
          color: #c08b30;
        }
        .action-btn.flag.flagged {
          color: #c08b30;
        }
        .action-btn.flag.flagged:hover {
          background: #fdf0ee;
          color: #e05d50;
        }

        /* Wider actions column to fit 4 buttons */
        .td-actions {
          width: 96px;
        }

        /* Empty state */
        .empty-cell {
          padding: 0 !important;
          border-bottom: none !important;
        }
        .empty-state {
          display: flex;
          flex-direction: column;
          align-items: center;
          padding: 3rem 1rem;
          gap: 0.5rem;
        }
        .es-icon {
          font-size: 2rem;
          line-height: 1;
        }
        .es-msg {
          font-size: 0.9375rem;
          font-weight: 600;
          color: #5c5650;
        }
        .es-sub {
          font-size: 0.8125rem;
          color: #8a8279;
        }
        .es-reset {
          margin-top: 0.5rem;
          padding: 0.375rem 0.875rem;
          border-radius: 6px;
          border: 1px solid #ebe7e3;
          background: white;
          color: #5c5650;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
        }
        .es-reset:hover {
          border-color: #2a9d8f;
          color: #2a9d8f;
        }

        /* Confirmation dialog */
        .confirm-overlay {
          position: absolute;
          inset: 0;
          background: rgba(26, 24, 22, 0.4);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9;
        }
        .confirm-dialog {
          background: white;
          border-radius: 12px;
          padding: 1.5rem;
          min-width: 280px;
          max-width: 360px;
          box-shadow: 0 8px 32px rgba(26, 24, 22, 0.18);
        }
        .confirm-msg {
          font-size: 1rem;
          font-weight: 600;
          color: #1a1816;
          margin: 0 0 1.25rem;
          text-align: center;
        }
        .confirm-btns {
          display: flex;
          gap: 0.5rem;
          justify-content: flex-end;
        }
        .confirm-btn {
          padding: 0.5rem 1.125rem;
          border-radius: 7px;
          border: none;
          font-size: 0.875rem;
          font-weight: 600;
          cursor: pointer;
          background: #f5f2ef;
          color: #5c5650;
        }
        .confirm-btn:hover {
          background: #ebe7e3;
        }
        .confirm-btn.danger {
          background: #e05d50;
          color: white;
        }
        .confirm-btn.danger:hover {
          background: #c94a3e;
        }

        /* Section add button */
        .section-add-btn {
          margin-left: auto;
          display: flex;
          align-items: center;
          gap: 0.35rem;
          background: #1a1816;
          color: #fff;
          border: none;
          border-radius: 8px;
          padding: 0.4rem 0.85rem;
          font-size: 0.75rem;
          font-weight: 600;
          cursor: pointer;
          font-family: inherit;
        }
        .section-add-btn:hover:not([disabled]) {
          background: #333;
        }
        .section-add-btn[disabled] { opacity: 0.6; cursor: wait; }
        .rebuild-staff-msg {
          margin-left: 0.5rem;
          font-size: 0.7rem;
          font-weight: 500;
        }
        .rebuild-staff-msg.is-ok { color: #2a9d8f; }
        .rebuild-staff-msg.is-error { color: #e05d50; }
        .pi-del-cell { width: 32px; text-align: center; }
        .pi-del-btn {
          background: transparent; border: none; cursor: pointer;
          color: rgba(120,120,120,0.6); padding: 0.2rem 0.45rem;
          font-size: 0.85rem; border-radius: 4px;
        }
        .pi-del-btn:hover:not([disabled]) {
          color: #e05d50; background: rgba(224,93,80,0.12);
        }
        .pi-del-btn[disabled] { opacity: 0.5; cursor: wait; }
        .pi-del-msg {
          font-size: 0.7rem; padding: 0.4rem 0.75rem; color: #2a9d8f;
        }

        /* Staff Modal */
        .staff-modal-overlay {
          position: fixed;
          inset: 0;
          background: rgba(26, 24, 22, 0.5);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9999;
        }
        .staff-modal {
          background: #fff;
          border-radius: 16px;
          width: 100%;
          max-width: 520px;
          box-shadow: 0 12px 48px rgba(26, 24, 22, 0.2);
          overflow: hidden;
        }
        .staff-modal-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 1.25rem 1.5rem;
          border-bottom: 1px solid #ebe7e3;
        }
        .staff-modal-title {
          font-size: 1.125rem;
          font-weight: 700;
          color: #1a1816;
          margin: 0;
        }
        .staff-modal-close {
          background: none;
          border: none;
          cursor: pointer;
          color: #8a8279;
          padding: 0.25rem;
          border-radius: 6px;
        }
        .staff-modal-close:hover {
          background: #f5f2ef;
          color: #1a1816;
        }
        .staff-modal-form {
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }
        .smf-row {
          display: flex;
          gap: 1rem;
        }
        .smf-group {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }
        .smf-group.full {
          flex: 1 1 100%;
        }
        .smf-label {
          font-size: 0.6875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: #8a8279;
        }
        .smf-req {
          color: #e05d50;
        }
        .smf-input {
          border: 1px solid #ebe7e3;
          border-radius: 8px;
          padding: 0.55rem 0.75rem;
          font-size: 0.875rem;
          color: #1a1816;
          font-family: inherit;
          background: #faf8f6;
        }
        .smf-input:focus {
          outline: none;
          border-color: #2a9d8f;
          background: #fff;
        }
        .smf-select {
          border: 1px solid #ebe7e3;
          border-radius: 8px;
          padding: 0.55rem 0.75rem;
          font-size: 0.875rem;
          color: #1a1816;
          font-family: inherit;
          background: #faf8f6;
        }
        .smf-select:focus {
          outline: none;
          border-color: #2a9d8f;
        }
        .smf-color-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
        }
        .smf-color-row .smf-select {
          flex: 1;
        }
        .smf-color-preview {
          width: 36px;
          height: 36px;
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.625rem;
          font-weight: 700;
          color: #fff;
          flex-shrink: 0;
        }
        .smf-color-preview.teal {
          background: #2a9d8f;
        }
        .smf-color-preview.purple {
          background: #7c5fc4;
        }
        .smf-color-preview.coral {
          background: #e05d50;
        }
        .smf-color-preview.amber {
          background: #c08b30;
        }
        .smf-actions {
          display: flex;
          gap: 0.75rem;
          justify-content: flex-end;
          padding-top: 0.5rem;
          border-top: 1px solid #ebe7e3;
          margin-top: 0.5rem;
        }
        .smf-btn {
          padding: 0.6rem 1.5rem;
          border-radius: 8px;
          border: none;
          font-size: 0.875rem;
          font-weight: 600;
          cursor: pointer;
          font-family: inherit;
        }
        .smf-btn.cancel {
          background: #f5f2ef;
          color: #5c5650;
        }
        .smf-btn.cancel:hover {
          background: #ebe7e3;
        }
        .smf-btn.save {
          background: #2a9d8f;
          color: #fff;
        }
        .smf-btn.save:hover {
          background: #228b7e;
        }
        .smf-btn.ai {
          background: #1a1816;
          color: #fff;
          display: flex;
          align-items: center;
          gap: 0.4rem;
        }
        .smf-btn.ai:hover {
          background: #333;
        }
        .smf-ai-section {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .smf-ai-label {
          font-size: 0.8125rem;
          font-weight: 600;
          color: #1a1816;
        }
        .smf-ai-textarea {
          border: 1px solid #ebe7e3;
          border-radius: 10px;
          padding: 0.75rem;
          font-size: 0.875rem;
          color: #1a1816;
          font-family: inherit;
          background: #faf8f6;
          min-height: 80px;
          resize: vertical;
        }
        .smf-ai-textarea:focus {
          outline: none;
          border-color: #2a9d8f;
          background: #fff;
        }
        .smf-ai-textarea::placeholder {
          color: #b0a99f;
        }
        .smf-ai-hint {
          font-size: 0.6875rem;
          color: #b0a99f;
        }
        .smf-analyzing {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          padding: 2.5rem 1rem;
          font-size: 0.9375rem;
          color: #5c5650;
        }
        .smf-spinner {
          width: 20px;
          height: 20px;
          border: 2px solid #ebe7e3;
          border-top-color: #2a9d8f;
          border-radius: 50%;
          animation: smf-spin 0.6s linear infinite;
        }
        @keyframes smf-spin {
          to {
            transform: rotate(360deg);
          }
        }
        .smf-preview-badge {
          font-size: 0.6875rem;
          font-weight: 600;
          color: #2a9d8f;
          background: #e8f6f4;
          padding: 0.35rem 0.75rem;
          border-radius: 6px;
          display: inline-block;
        }
        .smf-error {
          padding: 1.5rem;
          text-align: center;
          color: #e05d50;
          font-size: 0.875rem;
          font-weight: 500;
        }
      </style>
    </template>
  };

  // Fitted view
  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='dash-fitted'>
        <div class='df-badge'>Admin</div>
        <h4 class='df-title'>{{@model.title}}</h4>
        <div class='df-counts'>
          <span>{{@model.staff.length}} staff</span>
          <span>{{@model.observations.length}} obs</span>
        </div>
      </div>
      <style scoped>
        .dash-fitted {
          padding: 1rem;
          background: #fffdfb;
          border-radius: 10px;
          font-family:
            'Inter',
            system-ui,
            -apple-system,
            sans-serif;
        }
        .df-badge {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #7c5fc4;
          background: #f4f0fa;
          padding: 0.2rem 0.5rem;
          border-radius: 3px;
          display: inline-block;
          margin-bottom: 0.5rem;
        }
        .df-title {
          font-size: 0.875rem;
          font-weight: 600;
          margin: 0 0 0.625rem;
          color: #1a1816;
        }
        .df-counts {
          display: flex;
          gap: 0.75rem;
          font-size: 0.6875rem;
          color: #8a8279;
        }
      </style>
    </template>
  };

  // Embedded view
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='dash-embedded'>
        <span class='de-label'>Admin Dashboard</span>
        <strong class='de-title'>{{@model.title}}</strong>
      </div>
      <style scoped>
        .dash-embedded {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          font-family:
            'Inter',
            system-ui,
            -apple-system,
            sans-serif;
        }
        .de-label {
          font-size: 0.625rem;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .de-title {
          font-size: 0.875rem;
          color: #1a1816;
        }
      </style>
    </template>
  };
}


// touched for re-index
