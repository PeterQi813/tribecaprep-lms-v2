// HoS Dashboard — Head of School 75" TV Display
// Aggregates Students, Staff, ActivityEntries, LearningGoals

import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Student } from './student';
import { Staff } from './staff';
import { ActivityEntry } from './activity-entry';
import { LearningGoal } from './learning-goal';
import { syncStudentsToClassroom } from './sync-students-to-classroom';
import { syncFullProfileToAdmin } from './sync-full-profile-to-admin';

function formatTime(dt: any): string {
  if (!dt) return '';
  const d = new Date(dt);
  const h = d.getHours();
  const m = d.getMinutes();
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${String(m).padStart(2, '0')} ${ampm}`;
}

export class HoSDashboard extends CardDef {
  static displayName = 'HoS Dashboard';
  static prefersWideFormat = true;
  @field schoolName = contains(StringField);
  @field date = contains(DateField);
  @field students = linksToMany(Student);
  @field staff = linksToMany(Staff);
  @field activities = linksToMany(ActivityEntry);
  @field goals = linksToMany(LearningGoal);

  @field title = contains(StringField, {
    computeVia: function (this: HoSDashboard) {
      return `${this.schoolName ?? 'School'} — HoS Dashboard`;
    },
  });

  // ═══════════════════════════════════════════════════════════════════
  // ISOLATED — Full TV Display
  // ═══════════════════════════════════════════════════════════════════

  static isolated = class Isolated extends Component<typeof HoSDashboard> {
    @tracked currentPanel = 0;
    @tracked syncState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked syncMessage: string | null = null;
    @tracked pushAdminState: 'idle' | 'running' | 'success' | 'error' = 'idle';
    @tracked pushAdminMsg: string | null = null;

    classroomUrl = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/Classroom/classroom-2a';
    parentReportUrl = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main';

    constructor(owner: any, args: any) {
      super(owner, args);
      this.startRotation();
      this.loadProfiles();
      this.loadLocalCaches();  // load mirrored data from HoS realm (so UI shows data on refresh)
    }

    // Load previously-fetched data from HoS realm into tracked caches
    // Called on mount — ensures data persists across page refreshes
    async loadLocalCaches() {
      const getCards = this.hostGetCards;
      if (!getCards) return;
      try {
        const hosRealm = new URL('./', import.meta.url).href;
        const staffRes = getCards(this, () => ({ filter: { type: { module: `${hosRealm}staff`, name: 'Staff' } } }));
        this.fetchedStaff = await this.unwrapResource(staffRes, 10000);

        const actRes = getCards(this, () => ({ filter: { type: { module: `${hosRealm}activity-entry`, name: 'ActivityEntry' } } }));
        this.fetchedActivities = await this.unwrapResource(actRes, 10000);

        const goalRes = getCards(this, () => ({ filter: { type: { module: `${hosRealm}learning-goal`, name: 'LearningGoal' } } }));
        this.fetchedGoals = await this.unwrapResource(goalRes, 10000);

        const alertRes = getCards(this, () => ({ filter: { type: { module: `${hosRealm}classroom-alert`, name: 'ClassroomAlert' } } }));
        this.fetchedAlerts = await this.unwrapResource(alertRes, 10000);

        const stuRes = getCards(this, () => ({ filter: { type: { module: `${hosRealm}student`, name: 'Student' } } }));
        this.fetchedStudents = await this.unwrapResource(stuRes, 10000);
        console.log(`[HoS] loaded from local cache — staff:${this.fetchedStaff.length}, activities:${this.fetchedActivities.length}, goals:${this.fetchedGoals.length}, alerts:${this.fetchedAlerts.length}, students:${this.fetchedStudents.length}`);
      } catch (e) {
        console.warn('[HoS] loadLocalCaches failed:', e);
      }
    }

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

    // ── Push StudentFullProfile basic fields TO hero-classroom Student cards ──
    // Direction: HoS (校长) → hero-classroom (老师)
    // When HoS edits a StudentFullProfile (name change, grade change, new enrollment),
    // this button pushes the basic fields to the corresponding Student card in
    // hero-classroom. If no matching Student exists, it CREATES one (enrollment).
    handlePushToClassroom = async () => {
      this.syncState = 'running';
      this.syncMessage = 'Loading profiles...';
      try {
        const getCards = this.hostGetCards;
        const ctx = this.hostCommandContext;
        if (!getCards || !ctx) throw new Error('Context unavailable');

        const heroRealm = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';

        // 1. Load local StudentFullProfiles (source of truth for HoS)
        const profRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./student-full-profile', import.meta.url).href}`, name: 'StudentFullProfile' } },
        }));
        const profiles = await this.unwrapResource(profRes);

        // 2. Load hero-classroom Students (cross-realm, to find existing ones)
        const studRes = getCards(this, () => ({
          filter: { type: { module: `${heroRealm}student`, name: 'Student' } },
        }), () => [heroRealm]);
        const heroStudents = await this.unwrapResource(studRes);

        this.syncMessage = `Pushing ${profiles.length} profiles to classroom...`;

        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        // CRITICAL: Import Student from hero-classroom realm, NOT from local HoS realm
        // SaveCardCommand saves to heroRealm, so the card class must match the target realm
        const heroStudentModule = await import(`${heroRealm}student`);
        const Student = heroStudentModule.Student;

        let updated = 0;
        let created = 0;
        let skipped = 0;

        for (let i = 0; i < profiles.length; i++) {
          const profile = profiles[i];
          const ident = profile?.identity;
          console.log(`[HoS Push] profile ${i}:`, JSON.stringify({
            hasIdent: !!ident,
            firstName: ident?.firstName,
            lastName: ident?.lastName,
            studentId: ident?.studentId,
            keys: ident ? Object.keys(ident) : 'null',
            profileKeys: profile ? Object.keys(profile).slice(0, 10) : 'null',
          }));
          if (!ident) { skipped++; continue; }

          const profId = String(ident.studentId ?? '').trim();
          const profFirst = String(ident.firstName ?? '');
          const profLast = String(ident.lastName ?? '');
          const profGrade = String(ident.gradeLevel?.value ?? ident.gradeLevel ?? '');
          const profName = `${profFirst} ${profLast}`.trim();

          this.syncMessage = `${i + 1}/${profiles.length}: ${profName}...`;

          // Find existing hero-classroom Student
          let heroStudent = heroStudents.find((s: any) => {
            const hId = String(s?.studentId ?? '').trim();
            return hId && hId === profId;
          });

          // Fallback: match by name
          if (!heroStudent) {
            heroStudent = heroStudents.find((s: any) => {
              const hFirst = String(s?.firstName ?? '').toLowerCase();
              const hLast = String(s?.lastName ?? '').toLowerCase();
              return hFirst === profFirst.toLowerCase() && hLast === profLast.toLowerCase();
            });
          }

          try {
            if (heroStudent) {
              // UPDATE existing Student in hero-classroom
              (heroStudent as any).firstName = profFirst;
              (heroStudent as any).lastName = profLast;
              if (profId) (heroStudent as any).studentId = profId;
              // gradeLevel is an enum — set as string, Boxel handles coercion
              if (profGrade) (heroStudent as any).gradeLevel = profGrade;
              await new SaveCardCommand(ctx).execute({ card: heroStudent, realm: heroRealm });
              updated++;
            } else {
              // CREATE new Student in hero-classroom (enrollment!)
              const newStudent = new Student();
              (newStudent as any).firstName = profFirst;
              (newStudent as any).lastName = profLast;
              if (profId) (newStudent as any).studentId = profId;
              if (profGrade) (newStudent as any).gradeLevel = profGrade;
              (newStudent as any).active = true;
              (newStudent as any).location = 'In Classroom';
              await new SaveCardCommand(ctx).execute({ card: newStudent, realm: heroRealm });
              created++;
              console.log(`[HoS] enrolled new student "${profName}" to hero-classroom`);
            }
          } catch (e: any) {
            const errMsg = e?.message ?? String(e);
            console.warn(`[HoS Push] failed for ${profName}:`, errMsg, e);
            this.syncMessage = `Error: ${profName} — ${errMsg}`;
            skipped++;
          }
        }

        this.syncState = 'success';
        this.syncMessage = `Pushed: ${updated} updated, ${created} new enrolled${skipped > 0 ? `, ${skipped} skipped` : ''}`;
      } catch (e: any) {
        this.syncState = 'error';
        this.syncMessage = e?.message ?? String(e);
      }
    };

    // Manual bulk push: HoS StudentFullProfile -> Admin StudentFullProfile mirror.
    // Replaces Admin's old fetchProfilesFromHoS button (push semantics, source-driven).
    handlePushProfilesToAdmin = async () => {
      this.pushAdminState = 'running';
      this.pushAdminMsg = 'Loading profiles...';
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.pushAdminState = 'error';
        this.pushAdminMsg = 'Context unavailable';
        return;
      }
      try {
        const profRes = getCards(this, () => ({
          filter: { type: { module: `${new URL('./student-full-profile', import.meta.url).href}`, name: 'StudentFullProfile' } },
        }));
        const profiles = await this.unwrapResource(profRes);
        if (profiles.length === 0) {
          this.pushAdminState = 'success';
          this.pushAdminMsg = 'No profiles to push';
          return;
        }
        this.pushAdminMsg = `Pushing ${profiles.length} profiles to Admin...`;
        const r = await syncFullProfileToAdmin({
          profiles,
          ctx,
          getCards,
          host: this,
          unwrapResource: this.unwrapResource.bind(this),
          onProgress: (i, total, name) => { this.pushAdminMsg = `${i}/${total}: ${name}...`; },
        });
        this.pushAdminState = r.failed > 0 ? 'error' : 'success';
        this.pushAdminMsg = `Done: ${r.created} new, ${r.updated} updated, ${r.skipped} unchanged${r.failed > 0 ? `, ${r.failed} failed` : ''} (of ${r.total})`;
      } catch (e: any) {
        this.pushAdminState = 'error';
        this.pushAdminMsg = `Failed: ${e?.message ?? String(e)}`;
      }
    };

    // ── Fetched data (live from Admin + Classroom) ──
    @tracked fetchedStaff: any[] = [];
    @tracked fetchedActivities: any[] = [];
    @tracked fetchedGoals: any[] = [];
    @tracked fetchedAlerts: any[] = [];
    @tracked fetchedStudents: any[] = [];

    get activityEntries(): any[] { return this.fetchedActivities.length > 0 ? this.fetchedActivities : (this.args.model?.activities ?? []); }
    get learningGoals(): any[] { return this.fetchedGoals.length > 0 ? this.fetchedGoals : (this.args.model?.goals ?? []); }

    // Resolve linksTo id with fallback to raw relationships (for lazy cross-realm loads)
    _resolveLinkedId(card: any, field: string): string {
      const direct = String(card?.[field]?.id ?? '');
      if (direct) return direct;
      const rel = (card as any)?.relationships?.[field]?.links?.self;
      return rel ? String(rel) : '';
    }


    // Helper: check if an AE is from "today" (prefers activityDate, falls back to timestamp)
    _isEntryToday(ae: any, todayStr: string): boolean {
      const ad = String(ae?.activityDate ?? '');
      if (ad) return ad === todayStr;
      const ts = ae?.timestamp;
      if (!ts) return false;
      try {
        const d = new Date(ts);
        return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}` === todayStr;
      } catch (_) { return false; }
    }

    get _todayStr(): string {
      const n = new Date();
      return `${n.getFullYear()}-${String(n.getMonth()+1).padStart(2,'0')}-${String(n.getDate()).padStart(2,'0')}`;
    }

    // Staff with today's post count (reads flat authorName from mirrored AE)
    get staffOverview(): any[] {
      const todayStr = this._todayStr;
      const postsByStaff = new Map<string, number>();
      for (const ae of this.activityEntries) {
        if (!this._isEntryToday(ae, todayStr)) continue;
        const name = String(ae?.authorName ?? ae?.author?.name ?? '').trim();
        if (!name) continue;
        postsByStaff.set(name.toLowerCase(), (postsByStaff.get(name.toLowerCase()) || 0) + 1);
      }
      return this.fetchedStaff.map((s: any) => {
        const name = String(s?.name ?? '');
        const initials = String(s?.initials ?? '');
        const color = String(s?.avatarColor ?? s?.color ?? 'teal');
        const status = String(s?.status ?? 'Active');
        const posts = postsByStaff.get(name.toLowerCase()) || 0;
        return { name, initials, color, status, posts, reported: posts > 0 };
      });
    }

    get staffActiveCount() { return this.fetchedStaff.length; }
    get staffReportedCount() { return this.staffOverview.filter((s: any) => s.reported).length; }

    // Today's observations by category
    get todayObservations() {
      const todayStr = this._todayStr;
      const today = this.activityEntries.filter((ae: any) => this._isEntryToday(ae, todayStr));
      return {
        total: today.length,
        academic: today.filter((e: any) => String(e?.entryType?.value ?? e?.entryType ?? '') === 'Academic').length,
        social: today.filter((e: any) => String(e?.entryType?.value ?? e?.entryType ?? '') === 'Social').length,
        behavioral: today.filter((e: any) => String(e?.entryType?.value ?? e?.entryType ?? '') === 'Behavioral').length,
      };
    }

    // Live activity feed (latest 6)
    get liveActivityFeed(): any[] {
      return [...this.activityEntries]
        .sort((a: any, b: any) => {
          const ta = a?.timestamp ? new Date(a.timestamp).getTime() : 0;
          const tb = b?.timestamp ? new Date(b.timestamp).getTime() : 0;
          return tb - ta;
        })
        .slice(0, 6)
        .map((ae: any) => ({
          time: formatTime(ae?.timestamp),
          content: String(ae?.content ?? '').slice(0, 80),
          author: String(ae?.author?.name ?? ae?.author?.initials ?? ''),
          type: String(ae?.entryType?.value ?? ae?.entryType ?? ''),
          score: String(ae?.score ?? ''),
        }));
    }

    // ── Add Student Form state ──
    @tracked showAddStudent = false;
    @tracked newStudentFirst = '';
    @tracked newStudentLast = '';
    @tracked newStudentId = '';
    @tracked studentSaving = false;
    @tracked studentSaveMsg = '';
    @tracked studentSaveMsgClass = '';
    @tracked deletingProfileUrl = '';
    @tracked deleteMsg = '';
    @tracked deleteError = '';
    @tracked localProfiles: Array<{ displayName: string; grade: string; studentId: string; cardUrl: string; initials: string }> = [];
    @tracked profilesLoading = true;

    toggleAddStudentForm = () => { this.showAddStudent = !this.showAddStudent; this.studentSaveMsg = ''; };
    setNewStudentFirst = (e: Event) => { this.newStudentFirst = (e.target as HTMLInputElement).value; };
    setNewStudentLast = (e: Event) => { this.newStudentLast = (e.target as HTMLInputElement).value; };
    setNewStudentId = (e: Event) => { this.newStudentId = (e.target as HTMLInputElement).value; };

    loadProfiles = async () => {
      const getCards = this.hostGetCards;
      if (!getCards) { this.profilesLoading = false; return; }
      const profModule = new URL('./student-full-profile', import.meta.url).href;
      const res = getCards(this, () => ({
        filter: { type: { module: profModule, name: 'StudentFullProfile' } },
      }));
      const profiles = await this.unwrapResource(res);
      this.localProfiles = profiles.map((p: any) => {
        const ident = p?.identity;
        const first = String(ident?.firstName ?? '');
        const last = String(ident?.lastName ?? '');
        return {
          displayName: `${first} ${last}`.trim() || 'Unknown',
          grade: String(typeof ident?.gradeLevel === 'object' ? (ident.gradeLevel?.value ?? ident.gradeLevel?.label ?? '') : (ident?.gradeLevel ?? '')),
          studentId: String(ident?.studentId ?? ''),
          cardUrl: String(p?.id ?? ''),
          initials: (first.charAt(0) + last.charAt(0)).toUpperCase() || '??',
        };
      });
      this.profilesLoading = false;
    };

    saveNewStudent = async () => {
      if (!this.newStudentFirst.trim() || !this.newStudentLast.trim() || !this.newStudentId.trim()) {
        this.studentSaveMsg = 'Student ID, First name, and Last name are all required';
        this.studentSaveMsgClass = 'msg-error';
        return;
      }
      const ctx = this.hostCommandContext;
      if (!ctx) { this.studentSaveMsg = 'No command context'; this.studentSaveMsgClass = 'msg-error'; return; }
      this.studentSaving = true;
      this.studentSaveMsg = '';
      const firstSnap = this.newStudentFirst;
      const lastSnap = this.newStudentLast;
      const idSnap = this.newStudentId;
      try {
        const { StudentFullProfile } = await import('./student-full-profile');
        const { IdentitySection } = await import('./profile-sections');
        const { default: SaveCardCommand } = await import('@cardstack/boxel-host/commands/save-card');
        const realmUrl = new URL('./', import.meta.url).href;

        const profile = new StudentFullProfile();
        const ident = new IdentitySection();
        (ident as any).firstName = firstSnap;
        (ident as any).lastName = lastSnap;
        (ident as any).studentId = idSnap;
        (ident as any).active = true;
        (profile as any).identity = ident;

        const result = await new SaveCardCommand(ctx).execute({ card: profile, realm: realmUrl });

        // Auto-push new profile to Classroom — AWAIT before clearing form so console logs survive
        const savedProfile = result?.savedCard ?? profile;
        this.studentSaveMsg = `Saved. Pushing to Classroom...`;
        this.studentSaveMsgClass = 'msg-success';

        const targetSummary: string[] = [];
        const targetErrors: string[] = [];
        try {
          const r = await syncStudentsToClassroom({
            profiles: [savedProfile],
            ctx,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (r.failed > 0) {
            targetErrors.push(`Classroom: ${r.errors[0]?.error ?? 'unknown'}`);
            console.warn(`[HoS-Classroom] failed:`, r.errors);
          } else {
            targetSummary.push(`Classroom (${r.created}+${r.updated})`);
            console.log(`[HoS-Classroom] auto-enrolled "${firstSnap} ${lastSnap}" (id=${idSnap}, ${r.created} new, ${r.updated} updated)`);
          }
        } catch (e: any) {
          targetErrors.push(`Classroom threw: ${e?.message ?? String(e)}`);
          console.warn('[HoS-Classroom] exception:', e);
        }

        try {
          const r = await syncFullProfileToAdmin({
            profiles: [savedProfile],
            ctx,
            getCards: this.hostGetCards,
            host: this,
            unwrapResource: this.unwrapResource.bind(this),
          });
          if (r.failed > 0) {
            targetErrors.push(`Admin: ${r.errors[0]?.error ?? 'unknown'}`);
            console.warn(`[HoS-Admin] failed:`, r.errors);
          } else {
            targetSummary.push(`Admin (${r.created}+${r.updated})`);
            console.log(`[HoS-Admin] auto-pushed "${firstSnap} ${lastSnap}" (id=${idSnap}, ${r.created} new, ${r.updated} updated)`);
          }
        } catch (e: any) {
          targetErrors.push(`Admin threw: ${e?.message ?? String(e)}`);
          console.warn('[HoS-Admin] exception:', e);
        }

        if (targetErrors.length === 0) {
          this.studentSaveMsg = `Created "${firstSnap} ${lastSnap}" and pushed to: ${targetSummary.join(', ')}. Click Edit to add full details.`;
        } else {
          this.studentSaveMsg = `Created. Push results — OK: ${targetSummary.join(', ') || 'none'}; Failed: ${targetErrors.join('; ')}`;
          this.studentSaveMsgClass = 'msg-error';
        }

        this.newStudentFirst = '';
        this.newStudentLast = '';
        this.newStudentId = '';
        await this.loadProfiles();
      } catch (e: any) {
        this.studentSaveMsg = `Failed: ${e?.message ?? String(e)}`;
        this.studentSaveMsgClass = 'msg-error';
      }
      this.studentSaving = false;
    };

    // ── Delete student profile + propagate to Classroom + Admin ──
    handleDeleteProfile = async (prof: any) => {
      const cardUrl = String(prof?.cardUrl ?? '');
      const displayName = String(prof?.displayName ?? 'this student');
      if (!cardUrl) return;

      const ok = window.confirm(
        `Delete "${displayName}" from HoS, Classroom, and Admin?\n\nThis cannot be undone.`,
      );
      if (!ok) return;

      this.deletingProfileUrl = cardUrl;
      this.deleteMsg = `Deleting "${displayName}"...`;
      this.deleteError = '';

      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      if (!ctx || !getCards) {
        this.deleteError = 'Context unavailable';
        this.deletingProfileUrl = '';
        this.deleteMsg = '';
        return;
      }

      const studentId = String(prof?.studentId ?? '').trim();
      const fullNameLower = String(displayName).toLowerCase();
      const errs: string[] = [];

      // 1. Delete matching Student in Classroom realm
      try {
        const heroRealm = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/';
        const studRes = getCards(this, () => ({
          filter: { type: { module: `${heroRealm}student`, name: 'Student' } },
        }), () => [heroRealm]);
        const heroStudents = await this.unwrapResource(studRes, 8000);
        const target = heroStudents.find((s: any) => {
          const sid = String(s?.studentId ?? '').trim();
          if (sid && studentId && sid === studentId) return true;
          const fn = String(s?.firstName ?? '').toLowerCase();
          const ln = String(s?.lastName ?? '').toLowerCase();
          return `${fn} ${ln}`.trim() === fullNameLower;
        });
        if (target?.id) {
          await fetch(target.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          console.log(`[HoS-Classroom] deleted Student "${displayName}":`, target.id);
        } else {
          console.log(`[HoS-Classroom] no matching Student to delete for "${displayName}"`);
        }
      } catch (e: any) {
        errs.push(`Classroom: ${e?.message ?? String(e)}`);
        console.warn('[HoS-Classroom] delete failed:', e);
      }

      // 2. Delete matching FullProfile in Admin realm
      try {
        const adminRealm = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/';
        const adminProfRes = getCards(this, () => ({
          filter: { type: { module: `${adminRealm}student-full-profile`, name: 'StudentFullProfile' } },
        }), () => [adminRealm]);
        const adminProfs = await this.unwrapResource(adminProfRes, 15000);
        const target = adminProfs.find((p: any) => {
          const sid = String(p?.identity?.studentId ?? '').trim();
          if (sid && studentId && sid === studentId) return true;
          const fn = String(p?.identity?.firstName ?? '').toLowerCase();
          const ln = String(p?.identity?.lastName ?? '').toLowerCase();
          return `${fn} ${ln}`.trim() === fullNameLower;
        });
        if (target?.id) {
          await fetch(target.id, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
          console.log(`[HoS-Admin] deleted FullProfile "${displayName}":`, target.id);
        } else {
          console.log(`[HoS-Admin] no matching FullProfile to delete for "${displayName}"`);
        }
      } catch (e: any) {
        errs.push(`Admin: ${e?.message ?? String(e)}`);
        console.warn('[HoS-Admin] delete failed:', e);
      }

      // 3. Delete the HoS profile itself (last — needed identity above)
      try {
        await fetch(cardUrl, { method: 'DELETE', headers: { Accept: 'application/vnd.card+json' } });
        console.log(`[HoS] deleted local FullProfile "${displayName}":`, cardUrl);
      } catch (e: any) {
        errs.push(`HoS: ${e?.message ?? String(e)}`);
        console.warn('[HoS] delete failed:', e);
      }

      await this.loadProfiles();
      this.deletingProfileUrl = '';
      if (errs.length > 0) {
        this.deleteError = errs.join(' | ');
        this.deleteMsg = '';
      } else {
        this.deleteMsg = `Deleted "${displayName}" from HoS, Classroom, Admin.`;
        this.deleteError = '';
        setTimeout(() => { this.deleteMsg = ''; }, 4000);
      }
    };

    _timer: any = null;
    startRotation() {
      this._timer = setInterval(() => {
        this.currentPanel = (this.currentPanel + 1) % 4;
      }, 15000);
    }
    willDestroy() {
      super.willDestroy();
      if (this._timer) clearInterval(this._timer);
    }
    setPanel = (idx: number) => { this.currentPanel = idx; };

    get panelDots() {
      return [{ idx: 0 }, { idx: 1 }, { idx: 2 }, { idx: 3 }];
    }

    // ─── Computed Getters ───
    get safeStudents() {
      // Prefer HoS local Student mirror (has location from Classroom sync)
      return this.fetchedStudents.length > 0 ? this.fetchedStudents : (this.args.model?.students ?? []);
    }
    get safeStaff() { return this.fetchedStaff.length > 0 ? this.fetchedStaff : (this.args.model?.staff ?? []); }
    get totalStudents() { return this.safeStudents.length; }
    get presentCount() {
      return this.safeStudents.filter((s: any) => String(s?.location ?? 'In Classroom') === 'In Classroom').length;
    }
    get specialistCount() {
      return this.safeStudents.filter((s: any) => String(s?.location ?? '') === 'At Specialists').length;
    }
    get tardyCount() {
      return this.safeStudents.filter((s: any) => String(s?.location ?? '') === 'Tardy').length;
    }
    get absentCount() {
      return this.safeStudents.filter((s: any) => String(s?.location ?? '') === 'Absent').length;
    }
    get attendancePercent() {
      if (this.totalStudents === 0) return 0;
      const nonAbsent = this.totalStudents - this.absentCount;
      return Math.round((nonAbsent / this.totalStudents) * 100);
    }
    get observationCount() {
      // Today's observations only
      return this.activityEntries.filter((ae: any) => this._isEntryToday(ae, this._todayStr)).length;
    }
    _entryTypeValue(e: any): string {
      const t = e?.entryType;
      return typeof t === 'object' ? String(t?.value ?? '') : String(t ?? '');
    }
    get academicCount() {
      const today = this._todayStr;
      return this.activityEntries.filter((e: any) => this._isEntryToday(e, today) && this._entryTypeValue(e) === 'Academic').length;
    }
    get socialCount() {
      const today = this._todayStr;
      return this.activityEntries.filter((e: any) => this._isEntryToday(e, today) && this._entryTypeValue(e) === 'Social').length;
    }
    get behavioralCount() {
      const today = this._todayStr;
      return this.activityEntries.filter((e: any) => this._isEntryToday(e, today) && this._entryTypeValue(e) === 'Behavioral').length;
    }
    get activeStaffCount() { return this.safeStaff.length; }
    get totalStaffCount() { return this.safeStaff.length; }

    get staffWithColors(): any[] {
      return this.safeStaff.map((s: any) => {
        let c = '#5c5650';
        switch (s?.color) {
          case 'coral': c = '#e05d50'; break;
          case 'teal': c = '#2a9d8f'; break;
          case 'purple': c = '#7c5fc4'; break;
          case 'amber': c = '#c08b30'; break;
        }
        return { initials: s?.initials ?? '??', bgColor: c };
      });
    }

    get alerts(): any[] {
      // Read from fetched ClassroomAlert mirrors, filter out resolved + expired
      const now = Date.now();
      return this.fetchedAlerts.filter((ca: any) => {
        if (ca?.resolved === true) return false;
        if (ca?.expiresAt) {
          try { if (new Date(ca.expiresAt).getTime() < now) return false; } catch (_) {}
        }
        return true;
      }).map((ca: any) => ({
        alertType: String(ca?.alertType ?? ''),
        urgency: String(ca?.urgency ?? ''),
        message: String(ca?.message ?? ''),
        detail: String(ca?.detail ?? ''),
        studentName: String(ca?.studentName ?? ''),
        verified: ca?.verified === true,
        verifiedAt: String(ca?.verifiedAt ?? ''),
      })).sort((a: any, b: any) => {
        // Urgent first
        if (a.urgency === 'Urgent' && b.urgency !== 'Urgent') return -1;
        if (a.urgency !== 'Urgent' && b.urgency === 'Urgent') return 1;
        return 0;
      });
    }
    get alertCount() { return this.alerts.length; }

    get recentActivity(): any[] {
      let sorted = [...this.activityEntries].sort((a: any, b: any) => {
        const ta = a?.timestamp ? new Date(a.timestamp).getTime() : 0;
        const tb = b?.timestamp ? new Date(b.timestamp).getTime() : 0;
        return tb - ta;
      });
      return sorted.slice(0, 6).map((e: any) => {
        let dotColor = '#5c5650';
        switch (e?.entryType) {
          case 'Academic': dotColor = '#e05d50'; break;
          case 'Social': dotColor = '#7c5fc4'; break;
          case 'Behavioral': dotColor = '#c08b30'; break;
        }
        return {
          content: e?.content ?? '',
          authorName: e?.author?.name ?? 'Unknown',
          timeStr: formatTime(e?.timestamp),
          dotColor,
        };
      });
    }

    get goalProgressData(): any[] {
      let data: any[] = [];
      for (let s of this.safeStudents) {
        let sGoals = this.learningGoals.filter((g: any) => {
          return g?.student?.id === s?.id;
        });
        let avgMastery = 0;
        if (sGoals.length > 0) {
          let sum = sGoals.reduce((acc: number, g: any) => acc + (g?.currentMastery ?? 0), 0);
          avgMastery = Math.round(sum / sGoals.length);
        }
        data.push({
          name: s?.displayName ?? s?.name ?? '??',
          initials: s?.initials ?? '??',
          mastery: avgMastery,
          goalCount: sGoals.length,
        });
      }
      return data;
    }

    // SVG chart helpers
    get chartPolylinePoints(): string {
      let data = this.goalProgressData;
      if (data.length === 0) return '0,100';
      let step = 280 / Math.max(data.length - 1, 1);
      return data.map((d: any, i: number) => {
        let x = 10 + i * step;
        let y = 100 - d.mastery;
        return `${x},${y}`;
      }).join(' ');
    }

    get chartDots(): any[] {
      let data = this.goalProgressData;
      let step = 280 / Math.max(data.length - 1, 1);
      return data.map((d: any, i: number) => ({
        cx: 10 + i * step,
        cy: 100 - d.mastery,
        initials: d.initials,
        labelX: 10 + i * step,
      }));
    }

    get maxObservation(): number {
      return Math.max(this.academicCount, this.socialCount, this.behavioralCount, 1);
    }
    get academicBarH(): number { return Math.round((this.academicCount / this.maxObservation) * 60); }
    get socialBarH(): number { return Math.round((this.socialCount / this.maxObservation) * 60); }
    get behavioralBarH(): number { return Math.round((this.behavioralCount / this.maxObservation) * 60); }

    // ── Spark card: multi-select + search + pagination ──
    @tracked selectedSparkSlugs: Set<string> = new Set();
    @tracked sparkSearch = '';
    @tracked sparkPage = 0;
    sparkPageSize = 6;
    MAX_SPARK_SELECTED = 10;

    setSparkSearch = (e: Event) => { this.sparkSearch = (e.target as HTMLInputElement).value; this.sparkPage = 0; };
    prevSparkPage = () => { if (this.sparkPage > 0) this.sparkPage--; };
    nextSparkPage = () => { if ((this.sparkPage + 1) * this.sparkPageSize < this.filteredSparkProfiles.length) this.sparkPage++; };

    toggleSparkStudent = (slug: string) => {
      const next = new Set(this.selectedSparkSlugs);
      if (next.has(slug)) {
        next.delete(slug);
      } else {
        if (next.size >= this.MAX_SPARK_SELECTED) return;  // cap at 10
        next.add(slug);
      }
      this.selectedSparkSlugs = next;
    };

    isSparkSelected = (slug: string): boolean => {
      return this.selectedSparkSlugs.has(slug);
    };

    isSparkDisabled = (slug: string): boolean => {
      // Cap reached + this card is not currently selected
      return this.sparkSelectedFull && !this.selectedSparkSlugs.has(slug);
    };

    // ── Build student progress data from mirrored ActivityEntries ──
    // Returns Map<slug|name, { name, dailyScores: Array<{ date, cumulativePercent }>, trend: 'up'|'down'|'flat', changePercent, todayObs, latestPercent }>
    get studentWeekProgress(): Map<string, any> {
      const map = new Map<string, any>();
      const monday = this._startOfWeekMonday();
      const weekDates: string[] = [];
      for (let i = 0; i < 5; i++) {
        const d = new Date(monday);
        d.setDate(monday.getDate() + i);
        weekDates.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`);
      }

      // Group this-week AEs by studentName
      const byStudent = new Map<string, any[]>();
      for (const ae of this.activityEntries) {
        const ad = String(ae?.activityDate ?? '');
        if (!weekDates.includes(ad)) continue;
        const name = String(ae?.studentName ?? '').trim();
        if (!name) continue;
        if (!byStudent.has(name)) byStudent.set(name, []);
        byStudent.get(name)!.push(ae);
      }

      for (const [name, aes] of byStudent) {
        const dailyScores: Array<{ date: string; cumulativePercent: number }> = [];
        let cumNum = 0;
        let cumDen = 0;
        for (const date of weekDates) {
          // Add all AEs for this student on or before this date
          const onDate = aes.filter((ae: any) => String(ae?.activityDate ?? '') === date);
          for (const ae of onDate) {
            const score = String(ae?.score ?? '');
            const parts = score.split('/');
            const n = Number(parts[0]) || 0;
            const d = Number(parts[1]) || 0;
            if (d > 0) { cumNum += n; cumDen += d; }
          }
          dailyScores.push({ date, cumulativePercent: cumDen > 0 ? Math.round((cumNum / cumDen) * 100) : 0 });
        }

        const firstNonZero = dailyScores.find(d => d.cumulativePercent > 0)?.cumulativePercent ?? 0;
        const last = dailyScores[dailyScores.length - 1].cumulativePercent;
        const changePercent = last - firstNonZero;
        let trend: 'up' | 'down' | 'flat' = 'flat';
        if (changePercent > 3) trend = 'up';
        else if (changePercent < -3) trend = 'down';

        const todayStr = this._todayStr;
        const todayObs = aes.filter((ae: any) => String(ae?.activityDate ?? '') === todayStr).length;

        map.set(name.toLowerCase(), { name, dailyScores, trend, changePercent, todayObs, latestPercent: last });
      }
      return map;
    }

    _startOfWeekMonday(): Date {
      const now = new Date();
      const day = now.getDay();  // 0 Sun, 1 Mon, ... 6 Sat
      const diff = day === 0 ? -6 : 1 - day;  // back to Monday
      const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + diff);
      return monday;
    }

    // ── Spark card data list ──
    get allSparkProfiles(): Array<{ slug: string; name: string; initials: string; trend: string; changePercent: number; todayObs: number; latestPercent: number; sparkPath: string; targetGap: number }> {
      const weekProgress = this.studentWeekProgress;
      return this.localProfiles.map((p: any) => {
        const prog = weekProgress.get(String(p.displayName ?? '').toLowerCase());
        const dailyScores = prog?.dailyScores ?? [{date: '', cumulativePercent: 0}];
        // Build SVG polyline path for mini spark (normalized to viewbox 0-100 x 0-30)
        const maxY = 100;
        const count = dailyScores.length;
        const sparkPoints = dailyScores.map((d: any, i: number) => {
          const x = count > 1 ? (i / (count - 1)) * 100 : 50;
          const y = 30 - (d.cumulativePercent / maxY) * 30;
          return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');
        const slug = String(p.cardUrl ?? p.studentId ?? p.displayName ?? '').split('/').pop() ?? p.displayName;
        return {
          slug,
          name: p.displayName,
          initials: p.initials,
          trend: prog?.trend ?? 'flat',
          changePercent: prog?.changePercent ?? 0,
          todayObs: prog?.todayObs ?? 0,
          latestPercent: prog?.latestPercent ?? 0,
          sparkPath: sparkPoints,
          targetGap: Math.max(0, 80 - (prog?.latestPercent ?? 0)),
        };
      });
    }

    get filteredSparkProfiles() {
      const q = this.sparkSearch.toLowerCase().trim();
      if (!q) return this.allSparkProfiles;
      return this.allSparkProfiles.filter(p => p.name.toLowerCase().includes(q));
    }

    get pagedSparkProfiles() {
      const start = this.sparkPage * this.sparkPageSize;
      return this.filteredSparkProfiles.slice(start, start + this.sparkPageSize);
    }
    get showSparkPagination() { return this.filteredSparkProfiles.length > this.sparkPageSize; }
    get sparkTotalPages() { return Math.max(1, Math.ceil(this.filteredSparkProfiles.length / this.sparkPageSize)); }
    get sparkPageLabel() { return `${this.sparkPage + 1} / ${this.sparkTotalPages}`; }
    get cantPrevSparkPage() { return this.sparkPage === 0; }
    get cantNextSparkPage() { return (this.sparkPage + 1) * this.sparkPageSize >= this.filteredSparkProfiles.length; }
    get sparkSelectedCount() { return this.selectedSparkSlugs.size; }
    get sparkSelectedFull() { return this.selectedSparkSlugs.size >= this.MAX_SPARK_SELECTED; }

    // ── Build the big chart lines from selected students ──
    get bigChartLines(): Array<{ slug: string; name: string; color: string; points: string; dots: Array<{ cx: number; cy: number }> }> {
      const weekProgress = this.studentWeekProgress;
      const lines: any[] = [];
      // X positions for Mon-Fri (chart area x=50 to x=490, y=20 to y=180)
      const xs = [80, 170, 260, 350, 440];
      for (const profile of this.allSparkProfiles) {
        if (!this.selectedSparkSlugs.has(profile.slug)) continue;
        const prog = weekProgress.get(profile.name.toLowerCase());
        if (!prog) continue;
        const scores = prog.dailyScores as Array<{ cumulativePercent: number }>;
        // color based on trend
        let color = '#c08b30'; // flat amber
        if (prog.trend === 'up') color = '#2a9d8f';
        else if (prog.trend === 'down') color = '#e05d50';
        const pointsArr: string[] = [];
        const dots: Array<{ cx: number; cy: number }> = [];
        for (let i = 0; i < scores.length; i++) {
          const x = xs[i];
          const y = 180 - (scores[i].cumulativePercent / 100) * 160;
          pointsArr.push(`${x},${y.toFixed(1)}`);
          dots.push({ cx: x, cy: parseFloat(y.toFixed(1)) });
        }
        lines.push({ slug: profile.slug, name: profile.name, color, points: pointsArr.join(' '), dots });
      }
      return lines;
    }

    get hasSelectedSparks() { return this.selectedSparkSlugs.size > 0; }

    // ═══════════════════════════════════════════════════════════════
    // Ticker (bottom scrolling bar)
    // ═══════════════════════════════════════════════════════════════
    get tickerItems(): Array<{ category: 'alert' | 'weekly' | 'highlight' | 'reminder'; icon: string; text: string }> {
      const items: Array<{ category: 'alert' | 'weekly' | 'highlight' | 'reminder'; icon: string; text: string }> = [];
      const profiles = this.allSparkProfiles;

      // 🚨 ALERTS: students below 50% this week
      const lowPerforming = profiles.filter(p => p.latestPercent > 0 && p.latestPercent < 50);
      for (const p of lowPerforming) {
        items.push({ category: 'alert', icon: '⚠', text: `${p.name} at ${p.latestPercent}% — review scheduled` });
      }
      // Also include students with declining trend (big drops)
      const declining = profiles.filter(p => p.trend === 'down' && p.changePercent <= -10);
      for (const p of declining) {
        if (!lowPerforming.find(lp => lp.slug === p.slug)) {
          items.push({ category: 'alert', icon: '⚠', text: `${p.name} dropped ${Math.abs(p.changePercent)}% this week` });
        }
      }

      // 📊 WEEKLY REPORT: class-wide stats
      const withData = profiles.filter(p => p.latestPercent > 0);
      if (withData.length > 0) {
        const classAvg = Math.round(withData.reduce((s, p) => s + p.latestPercent, 0) / withData.length);
        items.push({ category: 'weekly', icon: '📊', text: `Weekly Report: ${classAvg}% average progress across ${withData.length} students` });
      }
      const todayObs = this.observationCount;
      if (todayObs > 0) {
        items.push({ category: 'weekly', icon: '📝', text: `${todayObs} observations recorded today` });
      }

      // 🌟 HIGHLIGHTS: students who reached mastery (>= 80%)
      const mastered = profiles.filter(p => p.latestPercent >= 80);
      if (mastered.length > 0) {
        items.push({ category: 'highlight', icon: '🌟', text: `${mastered.length} student${mastered.length > 1 ? 's' : ''} reached mastery this week` });
      }
      // Top performers
      const topClimbers = profiles.filter(p => p.trend === 'up' && p.changePercent >= 10)
        .sort((a, b) => b.changePercent - a.changePercent)
        .slice(0, 2);
      for (const p of topClimbers) {
        items.push({ category: 'highlight', icon: '✨', text: `${p.name} improved ${p.changePercent}% this week` });
      }

      // 💡 REMINDERS: from ClassroomAlert type=Schedule + hardcoded fallback
      const scheduleAlerts = this.fetchedAlerts.filter((ca: any) =>
        String(ca?.alertType ?? '') === 'Schedule' && !ca?.resolved
      );
      for (const a of scheduleAlerts) {
        items.push({ category: 'reminder', icon: '💡', text: String(a?.message ?? '') });
      }

      // If no reminders from alerts, show hardcoded defaults
      if (scheduleAlerts.length === 0) {
        items.push({ category: 'reminder', icon: '💡', text: 'Check Classroom for today\'s schedule updates' });
        items.push({ category: 'reminder', icon: '📅', text: 'Weekly staff meeting Friday 3:00 PM' });
      }

      // Fallback if no items at all
      if (items.length === 0) {
        items.push({ category: 'reminder', icon: 'ℹ', text: 'Click "Fetch All" to load school data' });
      }

      return items;
    }

    // ── Legacy (kept for compatibility with any remaining template refs) ──
    @tracked selectedSparkIndex = 0;
    selectStudent = (idx: number) => { this.selectedSparkIndex = idx; };

    get selectedStudentName() {
      const profs = this.localProfiles;
      if (profs.length === 0) return '';
      return profs[this.selectedSparkIndex]?.displayName ?? '';
    }

    // ── Student Profiles search + pagination ──
    @tracked profileSearch = '';
    @tracked profilePage = 0;
    profilePageSize = 5;

    setProfileSearch = (e: Event) => { this.profileSearch = (e.target as HTMLInputElement).value; this.profilePage = 0; };
    nextProfilePage = () => { if ((this.profilePage + 1) * this.profilePageSize < this.filteredProfiles.length) this.profilePage++; };
    prevProfilePage = () => { if (this.profilePage > 0) this.profilePage--; };

    get filteredProfiles() {
      const q = this.profileSearch.toLowerCase().trim();
      if (!q) return this.localProfiles;
      return this.localProfiles.filter((p: any) =>
        (p.displayName ?? '').toLowerCase().includes(q) ||
        (p.studentId ?? '').toLowerCase().includes(q)
      );
    }

    get pagedProfiles() {
      const start = this.profilePage * this.profilePageSize;
      return this.filteredProfiles.slice(start, start + this.profilePageSize);
    }

    get profileTotalPages() {
      return Math.ceil(this.filteredProfiles.length / this.profilePageSize);
    }

    get profilePageLabel() {
      return `${this.profilePage + 1} / ${this.profileTotalPages || 1}`;
    }

    get canNextProfilePage() { return (this.profilePage + 1) * this.profilePageSize < this.filteredProfiles.length; }
    get canPrevProfilePage() { return this.profilePage > 0; }
    get cantNextProfilePage() { return !this.canNextProfilePage; }
    get cantPrevProfilePage() { return !this.canPrevProfilePage; }
    get showProfilePagination() { return this.filteredProfiles.length > this.profilePageSize; }


    get formattedDate(): string {
      const d = this.args.model?.date;
      if (!d) return '';
      const dt = new Date(d);
      return dt.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    }

    <template>
      <div class='hos-dashboard'>

        {{!-- TOP BAR --}}
        <header class='top-bar'>
          <div class='top-left'>
            <span class='school-name'>{{@model.schoolName}}</span>
            <span class='top-date'>{{this.formattedDate}}</span>
          </div>
          <div class='panel-dots'>
            {{#each this.panelDots as |dot|}}
              <button
                class='dot {{if (eq this.currentPanel dot.idx) "dot-active"}}'
                type='button'
                {{on "click" (fn this.setPanel dot.idx)}}
              ></button>
            {{/each}}
          </div>
          <div class='top-right'>
            <a class='hos-nav-link' href={{this.classroomUrl}}>← Classroom</a>
            <a class='hos-nav-link' href={{this.parentReportUrl}}>Parent Report</a>
<button class='fetch-all-btn' type='button' {{on 'click' this.handlePushProfilesToAdmin}} disabled={{eq this.pushAdminState 'running'}} title='Push every Student profile to Admin (covers profile edits made via Boxel UI)'>
              {{#if (eq this.pushAdminState 'running')}}Pushing...{{else}}⇪ Push Profiles to Admin{{/if}}
            </button>
            {{#if this.pushAdminMsg}}
              <span class='fetch-msg {{if (eq this.pushAdminState "success") "msg-ok" "msg-err"}}'>{{this.pushAdminMsg}}</span>
            {{/if}}
            {{#if this.alertCount}}
              <span class='alert-badge'>{{this.alertCount}} Alerts</span>
            {{/if}}
          </div>
        </header>

        {{!-- MAIN GRID --}}
        <div class='main-grid'>

          {{!-- LEFT COLUMN — Key Metrics --}}
          <div class='col col-left'>

            {{!-- Attendance Card --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>ATTENDANCE</span>
                <span class='pct-badge'>{{this.attendancePercent}}%</span>
              </div>
              <div class='attendance-row'>
                <div class='att-stat'>
                  <span class='att-dot att-present'></span>
                  <span class='att-num'>{{this.presentCount}}</span>
                  <span class='att-lbl'>Present</span>
                </div>
                <div class='att-stat'>
                  <span class='att-dot att-absent'></span>
                  <span class='att-num'>{{this.absentCount}}</span>
                  <span class='att-lbl'>Absent</span>
                </div>
                <div class='att-stat'>
                  <span class='att-dot att-tardy'></span>
                  <span class='att-num'>{{this.specialistCount}}</span>
                  <span class='att-lbl'>Specialist</span>
                </div>
              </div>
            </div>

            {{!-- Observations Card --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>OBSERVATIONS</span>
                <span class='metric-big'>{{this.observationCount}}</span>
              </div>
              <div class='obs-bars'>
                <div class='obs-bar-group'>
                  <div class='obs-bar-track'>
                    <div class='obs-bar-fill obs-academic' style='height: {{this.academicBarH}}px'></div>
                  </div>
                  <span class='obs-bar-count'>{{this.academicCount}}</span>
                  <span class='obs-bar-label'>Acad</span>
                </div>
                <div class='obs-bar-group'>
                  <div class='obs-bar-track'>
                    <div class='obs-bar-fill obs-social' style='height: {{this.socialBarH}}px'></div>
                  </div>
                  <span class='obs-bar-count'>{{this.socialCount}}</span>
                  <span class='obs-bar-label'>Soc</span>
                </div>
                <div class='obs-bar-group'>
                  <div class='obs-bar-track'>
                    <div class='obs-bar-fill obs-behavioral' style='height: {{this.behavioralBarH}}px'></div>
                  </div>
                  <span class='obs-bar-count'>{{this.behavioralCount}}</span>
                  <span class='obs-bar-label'>Bhv</span>
                </div>
              </div>
            </div>

            {{!-- Staff Card --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>STAFF ACTIVE</span>
                <span class='metric-big'>{{this.staffReportedCount}}/{{this.staffActiveCount}}</span>
              </div>
              <div class='staff-list-compact'>
                {{#each this.staffOverview as |member|}}
                  <div class='staff-row {{if member.reported "reported" "absent"}}'>
                    <span class='staff-dot-sm' style='background-color: {{if member.reported "#2a9d8f" "#e05d50"}}'>{{member.initials}}</span>
                    <span class='staff-row-name'>{{member.name}}</span>
                    {{#if member.reported}}
                      <span class='staff-row-posts'>{{member.posts}} posts</span>
                    {{else}}
                      <span class='staff-row-absent'>no posts</span>
                    {{/if}}
                  </div>
                {{/each}}
                {{#unless this.staffOverview.length}}
                  <div class='staff-empty'>Click "Fetch All" to load staff data</div>
                {{/unless}}
              </div>
            </div>
          </div>

          {{!-- CENTER COLUMN — Charts + Student Cards --}}
          <div class='col col-center'>

            {{!-- Goal Progress This Week --}}
            <div class='tv-chart-card large'>
              <div class='tv-chart-header'>
                <h3 class='tv-chart-title'>Goal Progress This Week</h3>
                <div class='tv-chart-legend'>
                  <span class='tv-legend-item'><span class='tv-legend-dot teal'></span> On Track</span>
                  <span class='tv-legend-item'><span class='tv-legend-dot coral'></span> Needs Attention</span>
                  <span class='tv-legend-item'><span class='tv-legend-dot' style='background: #c08b30'></span> Flat</span>
                </div>
              </div>
              <div class='tv-line-chart'>
                <svg viewBox='0 0 500 200' preserveAspectRatio='none'>
                  <line x1='50' y1='20' x2='50' y2='180' stroke='rgba(255,255,255,0.1)' stroke-width='1'/>
                  <line x1='50' y1='50' x2='490' y2='50' stroke='rgba(255,255,255,0.1)' stroke-width='1'/>
                  <line x1='50' y1='100' x2='490' y2='100' stroke='rgba(255,255,255,0.1)' stroke-width='1'/>
                  <line x1='50' y1='150' x2='490' y2='150' stroke='rgba(255,255,255,0.1)' stroke-width='1'/>
                  <text x='40' y='25' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='end'>100%</text>
                  <text x='40' y='55' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='end'>75%</text>
                  <text x='40' y='105' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='end'>50%</text>
                  <text x='40' y='155' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='end'>25%</text>
                  <text x='80' y='195' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='middle'>Mon</text>
                  <text x='170' y='195' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='middle'>Tue</text>
                  <text x='260' y='195' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='middle'>Wed</text>
                  <text x='350' y='195' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='middle'>Thu</text>
                  <text x='440' y='195' fill='rgba(255,255,255,0.5)' font-size='10' text-anchor='middle'>Fri</text>
                  {{#if this.hasSelectedSparks}}
                    {{#each this.bigChartLines as |line|}}
                      <polyline points='{{line.points}}' fill='none' stroke='{{line.color}}' stroke-width='2'/>
                      {{#each line.dots as |dot|}}
                        <circle cx='{{dot.cx}}' cy='{{dot.cy}}' r='3' fill='{{line.color}}'/>
                      {{/each}}
                    {{/each}}
                  {{else}}
                    <text x='270' y='105' fill='rgba(255,255,255,0.3)' font-size='13' text-anchor='middle'>Click student cards below to chart their progress</text>
                  {{/if}}
                </svg>
              </div>
              {{#if this.hasSelectedSparks}}
                <div class='tv-chart-active-list'>
                  {{#each this.bigChartLines as |line|}}
                    <span class='tv-chart-active-pill' style='border-color: {{line.color}}; color: {{line.color}}'>● {{line.name}}</span>
                  {{/each}}
                </div>
              {{/if}}
            </div>

            {{!-- Student Sparkline Cards with search + pagination --}}
            <div class='tv-sparklines-controls'>
              <input class='tv-sparklines-search' type='text' placeholder='Search students...' value={{this.sparkSearch}} {{on 'input' this.setSparkSearch}} />
              <span class='tv-sparklines-count'>{{this.sparkSelectedCount}}/10 selected</span>
            </div>
            <div class='tv-sparklines-row'>
              {{#each this.pagedSparkProfiles as |prof|}}
                <button
                  class='tv-spark-card {{if (this.isSparkSelected prof.slug) "selected"}} {{if (this.isSparkDisabled prof.slug) "disabled"}}'
                  type='button'
                  {{on 'click' (fn this.toggleSparkStudent prof.slug)}}
                >
                  <div class='tv-spark-header'>
                    <div class='tv-spark-student'>
                      <div class='tv-spark-avatar'>{{prof.initials}}</div>
                      <span>{{prof.name}}</span>
                    </div>
                    <span class='tv-spark-trend {{prof.trend}}'>
                      {{#if (eq prof.trend "up")}}↑{{else if (eq prof.trend "down")}}↓{{else}}—{{/if}}
                      {{prof.changePercent}}%
                    </span>
                  </div>
                  <svg class='tv-spark-line' viewBox='0 0 100 30' preserveAspectRatio='none'>
                    <line x1='0' y1='15' x2='100' y2='15' stroke='rgba(255,255,255,0.15)' stroke-width='1' stroke-dasharray='4'/>
                    {{#if prof.sparkPath}}
                      <polyline points='{{prof.sparkPath}}' fill='none' stroke='{{if (eq prof.trend "up") "#2a9d8f" (if (eq prof.trend "down") "#e05d50" "#c08b30")}}' stroke-width='1.5'/>
                    {{/if}}
                  </svg>
                  <div class='tv-spark-footer'>
                    <span>{{prof.todayObs}} obs today</span>
                    <span class='tv-spark-target'>{{prof.latestPercent}}%</span>
                  </div>
                </button>
              {{/each}}
              {{#unless this.filteredSparkProfiles.length}}
                <div class='tv-spark-empty'>{{#if this.sparkSearch}}No matches{{else}}No students yet{{/if}}</div>
              {{/unless}}
            </div>
            {{#if this.showSparkPagination}}
              <div class='tv-sparklines-pagination'>
                <button class='page-btn' type='button' disabled={{this.cantPrevSparkPage}} {{on 'click' this.prevSparkPage}}>Prev</button>
                <span class='page-label'>{{this.sparkPageLabel}}</span>
                <button class='page-btn' type='button' disabled={{this.cantNextSparkPage}} {{on 'click' this.nextSparkPage}}>Next</button>
              </div>
            {{/if}}
          </div>

          {{!-- RIGHT COLUMN — Alerts & Activity --}}
          <div class='col col-right'>

            {{!-- Student Management --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>STUDENT PROFILES</span>
                <button class='hos-add-btn' type='button' {{on 'click' this.toggleAddStudentForm}}>
                  {{#if this.showAddStudent}}Cancel{{else}}+ Add Student{{/if}}
                </button>
              </div>
              {{#if this.showAddStudent}}
                <div class='add-student-form'>
                  <p class='asf-hint'>Enter Student ID, First and Last name. The profile will auto-push to Classroom. Click Edit afterward to fill in full details.</p>
                  <div class='asf-row'>
                    <div class='asf-field'>
                      <label>Student ID *</label>
                      <input type='text' placeholder='e.g. TPS-2026-1234' value={{this.newStudentId}} {{on 'input' this.setNewStudentId}} />
                    </div>
                  </div>
                  <div class='asf-row'>
                    <div class='asf-field'>
                      <label>First Name *</label>
                      <input type='text' placeholder='First name' value={{this.newStudentFirst}} {{on 'input' this.setNewStudentFirst}} />
                    </div>
                    <div class='asf-field'>
                      <label>Last Name *</label>
                      <input type='text' placeholder='Last name' value={{this.newStudentLast}} {{on 'input' this.setNewStudentLast}} />
                    </div>
                  </div>
                  <div class='asf-actions'>
                    <button class='asf-save-btn' type='button' {{on 'click' this.saveNewStudent}} disabled={{this.studentSaving}}>
                      {{#if this.studentSaving}}Creating...{{else}}Create Student{{/if}}
                    </button>
                  </div>
                  {{#if this.studentSaveMsg}}
                    <div class='asf-msg {{this.studentSaveMsgClass}}'>{{this.studentSaveMsg}}</div>
                  {{/if}}
                </div>
              {{/if}}
              <div class='profile-search-bar'>
                <input class='profile-search-input' type='text' placeholder='Search by name or ID...' value={{this.profileSearch}} {{on 'input' this.setProfileSearch}} />
              </div>
              {{#if this.deleteMsg}}
                <div class='delete-msg-ok'>{{this.deleteMsg}}</div>
              {{/if}}
              {{#if this.deleteError}}
                <div class='delete-msg-err'>Delete error: {{this.deleteError}}</div>
              {{/if}}
              <div class='student-list'>
                {{#each this.pagedProfiles as |prof|}}
                  <div class='profile-row'>
                    <a class='profile-row-link' href={{prof.cardUrl}}>
                      <span class='profile-name'>{{prof.displayName}}</span>
                      <span class='profile-grade'>{{prof.grade}}</span>
                      <span class='profile-id'>{{prof.studentId}}</span>
                      <span class='profile-edit-link'>Edit</span>
                    </a>
                    <button
                      class='profile-delete-btn'
                      type='button'
                      title='Delete from HoS, Classroom, Admin'
                      disabled={{eq this.deletingProfileUrl prof.cardUrl}}
                      {{on 'click' (fn this.handleDeleteProfile prof)}}
                    >
                      {{#if (eq this.deletingProfileUrl prof.cardUrl)}}…{{else}}✕{{/if}}
                    </button>
                  </div>
                {{/each}}
                {{#if this.profilesLoading}}
                  <div class='empty-state'>Loading profiles...</div>
                {{else}}
                  {{#unless this.filteredProfiles.length}}
                    <div class='empty-state'>{{#if this.profileSearch}}No matches{{else}}No student profiles yet{{/if}}</div>
                  {{/unless}}
                {{/if}}
              </div>
              {{#if this.showProfilePagination}}
                <div class='profile-pagination'>
                  <button class='page-btn' type='button' disabled={{this.cantPrevProfilePage}} {{on 'click' this.prevProfilePage}}>Prev</button>
                  <span class='page-label'>{{this.profilePageLabel}}</span>
                  <button class='page-btn' type='button' disabled={{this.cantNextProfilePage}} {{on 'click' this.nextProfilePage}}>Next</button>
                </div>
              {{/if}}
            </div>

            {{!-- Active Alerts --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>ACTIVE ALERTS</span>
                {{#if this.alertCount}}
                  <span class='alert-count-badge'>{{this.alertCount}}</span>
                {{/if}}
              </div>
              <div class='alerts-list'>
                {{#each this.alerts as |alert|}}
                  <div class='alert-item {{if (eq alert.urgency "Urgent") "alert-urgent"}}'>
                    <div class='alert-item-top'>
                      <span class='alert-type-label'>{{alert.alertType}}</span>
                      {{#if (eq alert.urgency "Urgent")}}
                        <span class='urgency-dot'></span>
                      {{/if}}
                    </div>
                    <div class='alert-msg'>{{alert.message}}</div>
                    <div class='alert-student-name'>{{alert.studentName}}</div>
                  </div>
                {{/each}}
                {{#unless this.alerts.length}}
                  <div class='empty-state'>No active alerts</div>
                {{/unless}}
              </div>
            </div>

            {{!-- Live Activity Feed --}}
            <div class='metric-card'>
              <div class='metric-header'>
                <span class='metric-label'>LIVE ACTIVITY</span>
              </div>
              <div class='activity-feed'>
                {{#each this.liveActivityFeed as |entry|}}
                  <div class='feed-item'>
                    <span class='feed-time'>{{entry.time}}</span>
                    <span class='feed-dot {{entry.type}}'></span>
                    <div class='feed-body'>
                      <span class='feed-text'>{{entry.content}}</span>
                      {{#if entry.score}}<span class='feed-score'>{{entry.score}}</span>{{/if}}
                      <span class='feed-author'>{{entry.author}}</span>
                    </div>
                  </div>
                {{/each}}
                {{#unless this.liveActivityFeed.length}}
                  <div class='empty-state'>Click "Fetch All" to load activity data</div>
                {{/unless}}
              </div>
            </div>
          </div>
        </div>

        {{!-- BOTTOM TICKER BAR --}}
        <div class='ticker-bar'>
          <div class='ticker-track'>
            {{#each this.tickerItems as |item|}}
              <span class='ticker-item ticker-{{item.category}}'>
                <span class='ticker-icon'>{{item.icon}}</span>
                <span class='ticker-text'>{{item.text}}</span>
              </span>
              <span class='ticker-sep'>·</span>
            {{/each}}
            {{!-- Duplicate for seamless loop --}}
            {{#each this.tickerItems as |item|}}
              <span class='ticker-item ticker-{{item.category}}'>
                <span class='ticker-icon'>{{item.icon}}</span>
                <span class='ticker-text'>{{item.text}}</span>
              </span>
              <span class='ticker-sep'>·</span>
            {{/each}}
          </div>
        </div>
      </div>

      <style scoped>
        /* ═══ Design Tokens ═══ */
        .hos-dashboard {
          --bg-dark: #0f1419;
          --bg-card: #1a2332;
          --bg-card-hover: #1e2a3a;
          --border-subtle: rgba(255,255,255,0.08);
          --text-primary: #e8edf2;
          --text-secondary: rgba(255,255,255,0.6);
          --text-muted: rgba(255,255,255,0.35);
          --coral: #e05d50;
          --teal: #2a9d8f;
          --purple: #7c5fc4;
          --amber: #c08b30;
          --green: #34d399;

          background: var(--bg-dark);
          color: var(--text-primary);
          font-family: 'Plus Jakarta Sans', 'Inter', system-ui, sans-serif;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          padding: 1rem 1.25rem;
          gap: 0.75rem;
          box-sizing: border-box;
        }

        /* ═══ Top Bar ═══ */
        .top-bar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.5rem 0;
        }
        .top-left {
          display: flex;
          align-items: baseline;
          gap: 1rem;
        }
        .school-name {
          font-size: 1.375rem;
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        .top-date {
          font-size: 0.8125rem;
          color: var(--text-secondary);
        }
        .panel-dots {
          display: flex;
          gap: 0.5rem;
        }
        .dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--text-muted);
          border: none;
          cursor: pointer;
          padding: 0;
          transition: background 0.2s;
        }
        .dot-active {
          background: var(--teal);
          box-shadow: 0 0 6px rgba(42, 157, 143, 0.5);
        }
        .hos-nav-link {
          font-size: 0.6875rem;
          color: rgba(255,255,255,0.6);
          text-decoration: none;
          padding: 0.125rem 0.5rem;
          border: 1px solid rgba(255,255,255,0.2);
          border-radius: 4px;
        }
        .hos-nav-link:hover {
          color: white;
          border-color: rgba(255,255,255,0.5);
        }
        .hos-sync-btn {
          padding: 0.25rem 0.75rem;
          background: #2a9d8f;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.6875rem;
          font-weight: 700;
          cursor: pointer;
          font-family: inherit;
        }
        .hos-sync-btn:disabled { opacity: 0.6; cursor: wait; }
        .hos-sync-btn:not(:disabled):hover { background: #238077; }
        .hos-sync-ok {
          font-size: 0.625rem;
          color: #68d391;
        }
        .hos-sync-err {
          font-size: 0.625rem;
          color: #fc8181;
        }
        .top-right {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .alert-badge {
          background: var(--coral);
          color: white;
          padding: 0.25rem 0.625rem;
          border-radius: 1rem;
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.03em;
        }
        .hos-add-btn {
          font-family: inherit; font-size: 0.6875rem; font-weight: 600;
          background: var(--teal); color: white; border: none;
          border-radius: 4px; padding: 0.25rem 0.625rem; cursor: pointer;
        }
        .add-student-form {
          padding: 0.75rem; display: flex; flex-direction: column; gap: 0.5rem;
          border-top: 1px solid var(--border-subtle);
        }
        .asf-row { display: flex; gap: 0.5rem; }
        .asf-field { flex: 1; display: flex; flex-direction: column; gap: 0.2rem; }
        .asf-field.wide { flex: 2; }
        .asf-field label {
          font-size: 0.5625rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.05em; color: var(--text-secondary);
        }
        .asf-field input, .asf-field select {
          font-family: inherit; font-size: 0.75rem; padding: 0.375rem 0.5rem;
          background: var(--bg-dark); color: var(--text-primary);
          border: 1px solid var(--border-subtle); border-radius: 4px;
        }
        .asf-actions { display: flex; justify-content: flex-end; padding-top: 0.25rem; }
        .asf-save-btn {
          font-family: inherit; font-size: 0.75rem; font-weight: 600;
          background: var(--teal); color: white; border: none;
          border-radius: 6px; padding: 0.5rem 1rem; cursor: pointer;
        }
        .asf-save-btn:disabled { opacity: 0.5; cursor: wait; }
        .asf-msg { font-size: 0.6875rem; padding: 0.375rem 0.5rem; border-radius: 4px; }
        .asf-msg.msg-success { background: rgba(42,157,143,0.15); color: var(--teal); }
        .asf-msg.msg-error { background: rgba(224,93,80,0.15); color: var(--coral); }
        .student-list { max-height: 200px; overflow-y: auto; }
        .profile-row {
          display: flex; align-items: center;
          border-top: 1px solid var(--border-subtle);
          font-size: 0.75rem;
        }
        .profile-row-link {
          display: flex; align-items: center; gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          flex: 1;
          text-decoration: none;
          cursor: pointer;
        }
        .profile-row-link:hover { background: var(--bg-card-hover); }
        .profile-name { color: var(--text-primary); font-weight: 600; flex: 1; }
        .profile-grade { color: var(--text-secondary); font-size: 0.6875rem; }
        .profile-id { color: var(--text-muted); font-size: 0.625rem; }
        .profile-edit-link { color: var(--teal); font-size: 0.625rem; font-weight: 600; margin-left: auto; }
        .profile-delete-btn {
          background: transparent;
          border: none;
          cursor: pointer;
          color: rgba(255,255,255,0.35);
          padding: 0.25rem 0.6rem;
          margin-right: 0.25rem;
          font-size: 0.85rem;
          border-radius: 4px;
        }
        .profile-delete-btn:hover:not([disabled]) {
          color: #ff8e8e;
          background: rgba(255,142,142,0.12);
        }
        .profile-delete-btn[disabled] { opacity: 0.5; cursor: wait; }
        .delete-msg-ok {
          font-size: 0.6875rem; color: #8de38d;
          padding: 0.4rem 0.75rem; border-top: 1px solid var(--border-subtle);
        }
        .delete-msg-err {
          font-size: 0.6875rem; color: #ff8e8e;
          padding: 0.4rem 0.75rem; border-top: 1px solid var(--border-subtle);
        }
        .asf-hint { font-size: 0.6875rem; color: var(--text-secondary); margin: 0; line-height: 1.4; }
        .profile-search-bar { padding: 0.5rem 0.75rem; border-top: 1px solid var(--border-subtle); }
        .profile-search-input {
          width: 100%; box-sizing: border-box;
          font-family: inherit; font-size: 0.75rem; padding: 0.375rem 0.5rem;
          background: var(--bg-dark); color: var(--text-primary);
          border: 1px solid var(--border-subtle); border-radius: 4px;
        }
        .profile-search-input::placeholder { color: var(--text-muted); }
        .profile-pagination {
          display: flex; align-items: center; justify-content: center;
          gap: 0.75rem; padding: 0.5rem; border-top: 1px solid var(--border-subtle);
        }
        .page-btn {
          font-family: inherit; font-size: 0.625rem; font-weight: 600;
          color: var(--teal); background: none; border: 1px solid var(--border-subtle);
          border-radius: 4px; padding: 0.25rem 0.5rem; cursor: pointer;
        }
        .page-btn:disabled { opacity: 0.3; cursor: not-allowed; }
        .page-label { font-size: 0.625rem; color: var(--text-muted); }
        .loading-indicator {
          font-size: 0.6875rem;
          color: var(--text-muted);
        }

        /* ═══ Main Grid ═══ */
        .main-grid {
          flex: 1;
          display: grid;
          grid-template-columns: 1fr 1.3fr 1fr;
          gap: 0.75rem;
          min-height: 0;
        }
        .col {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          min-height: 0;
        }

        /* ═══ Metric Cards ═══ */
        .metric-card {
          background: var(--bg-card);
          border: 1px solid var(--border-subtle);
          border-radius: 0.75rem;
          padding: 1rem;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .metric-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .metric-label {
          font-size: 0.625rem;
          font-weight: 700;
          letter-spacing: 0.1em;
          color: var(--text-muted);
        }
        .metric-big {
          font-size: 1.25rem;
          font-weight: 700;
          color: var(--text-primary);
        }

        /* ═══ Attendance ═══ */
        .pct-badge {
          font-size: 1.75rem;
          font-weight: 800;
          color: var(--teal);
          line-height: 1;
        }
        .attendance-row {
          display: flex;
          gap: 1.5rem;
        }
        .att-stat {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .att-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
        }
        .att-present { background: var(--teal); }
        .att-absent { background: var(--coral); }
        .att-tardy { background: var(--amber); }
        .att-num {
          font-size: 1rem;
          font-weight: 700;
        }
        .att-lbl {
          font-size: 0.6875rem;
          color: var(--text-muted);
        }

        /* ═══ Observations Bars ═══ */
        .obs-bars {
          display: flex;
          gap: 1.5rem;
          align-items: flex-end;
          padding-top: 0.25rem;
        }
        .obs-bar-group {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.25rem;
        }
        .obs-bar-track {
          width: 28px;
          height: 60px;
          background: rgba(255,255,255,0.04);
          border-radius: 4px;
          display: flex;
          align-items: flex-end;
          overflow: hidden;
        }
        .obs-bar-fill {
          width: 100%;
          border-radius: 4px 4px 0 0;
          transition: height 0.4s ease;
        }
        .obs-academic { background: var(--coral); }
        .obs-social { background: var(--purple); }
        .obs-behavioral { background: var(--amber); }
        .obs-bar-count {
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .obs-bar-label {
          font-size: 0.5625rem;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        /* ═══ Staff Dots ═══ */
        .staff-dots {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .staff-dot {
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 0.5625rem;
          font-weight: 700;
          letter-spacing: 0.04em;
        }

        .staff-list-compact { display: flex; flex-direction: column; gap: 0.375rem; max-height: 160px; overflow-y: auto; }
        .staff-row { display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; }
        .staff-dot-sm { width: 1.5rem; height: 1.5rem; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-size: 0.5rem; font-weight: 700; flex-shrink: 0; }
        .staff-row-name { font-size: 0.6875rem; color: var(--text-primary); flex: 1; }
        .staff-row-posts { font-size: 0.625rem; color: #2a9d8f; font-weight: 600; }
        .staff-row-absent { font-size: 0.625rem; color: #e05d50; font-style: italic; }
        .staff-empty { font-size: 0.6875rem; color: var(--text-muted); font-style: italic; }
        .fetch-all-btn {
          font-family: inherit; font-size: 0.6875rem; font-weight: 600;
          background: #2a9d8f; color: white; border: none; border-radius: 4px;
          padding: 0.3rem 0.75rem; cursor: pointer;
        }
        .fetch-all-btn:disabled { opacity: 0.5; cursor: wait; }
        .fetch-all-btn:hover:not(:disabled) { background: #239083; }
        .fetch-msg { font-size: 0.5625rem; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .fetch-msg.msg-ok { color: #2a9d8f; }
        .fetch-msg.msg-err { color: #e05d50; }
        .feed-dot.Academic { background-color: #e05d50 !important; }
        .feed-dot.Social { background-color: #7c5fc4 !important; }
        .feed-dot.Behavioral { background-color: #c08b30 !important; }
        .feed-score { font-size: 0.625rem; font-weight: 600; color: #2a9d8f; margin-left: 0.25rem; }

        /* ═══ Chart ═══ */
        .chart-card {
          flex: 1;
        }
        .chart-wrapper {
          flex: 1;
          min-height: 0;
        }
        .chart-svg {
          width: 100%;
          height: auto;
          max-height: 140px;
        }

        /* ═══ Sparkline Grid ═══ */
        /* ═══ Chart Card (from mockup) ═══ */
        .tv-chart-card {
          background: rgba(255,255,255,0.03);
          border-radius: 8px;
          padding: 1rem;
          border: 1px solid rgba(255,255,255,0.06);
        }
        .tv-chart-card.large { flex: 1; }
        .tv-chart-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.75rem;
        }
        .tv-chart-title {
          font-size: 0.875rem;
          font-weight: 600;
          color: white;
          margin: 0;
        }
        .tv-chart-legend { display: flex; gap: 1rem; }
        .tv-legend-item {
          display: flex; align-items: center; gap: 0.375rem;
          font-size: 0.625rem; color: rgba(255,255,255,0.5);
        }
        .tv-legend-dot { width: 8px; height: 8px; border-radius: 50%; }
        .tv-legend-dot.teal { background: var(--teal); }
        .tv-legend-dot.coral { background: var(--coral); }
        .tv-line-chart { position: relative; }
        .tv-line-chart svg { width: 100%; height: 180px; }

        /* ═══ Sparkline Cards Row (from mockup) ═══ */
        .tv-sparklines-controls {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-top: 0.5rem;
          margin-bottom: 0.375rem;
        }
        .tv-sparklines-search {
          flex: 1;
          font-family: inherit;
          font-size: 0.6875rem;
          padding: 0.375rem 0.5rem;
          background: rgba(0,0,0,0.3);
          color: white;
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 4px;
          outline: none;
        }
        .tv-sparklines-search::placeholder { color: rgba(255,255,255,0.3); }
        .tv-sparklines-count {
          font-size: 0.625rem;
          color: rgba(255,255,255,0.5);
          font-weight: 600;
        }
        .tv-sparklines-pagination {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 0.5rem;
        }
        .tv-spark-card.disabled { opacity: 0.35; cursor: not-allowed; }
        .tv-chart-active-list {
          display: flex; flex-wrap: wrap; gap: 0.375rem; padding-top: 0.5rem;
        }
        .tv-chart-active-pill {
          font-size: 0.625rem;
          padding: 0.125rem 0.5rem;
          border: 1px solid;
          border-radius: 999px;
          font-weight: 600;
        }
        .tv-spark-trend.up { color: #2a9d8f; }
        .tv-spark-trend.down { color: #e05d50; }
        .tv-spark-trend.flat { color: #c08b30; }
        .tv-sparklines-row {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
          gap: 0.625rem;
        }
        .tv-spark-card {
          background: rgba(255,255,255,0.03);
          border-radius: 8px;
          padding: 0.75rem;
          border: 1px solid rgba(255,255,255,0.06);
          cursor: pointer;
          font-family: inherit;
          color: var(--text-primary);
          text-align: left;
          transition: border-color 0.15s, box-shadow 0.15s;
        }
        .tv-spark-card:hover { border-color: rgba(255,255,255,0.2); }
        .tv-spark-card.selected {
          border-color: var(--teal);
          box-shadow: 0 0 0 1px var(--teal), 0 4px 12px rgba(42,157,143,0.15);
          background: rgba(42,157,143,0.06);
        }
        .tv-spark-card.alert {
          border-color: rgba(224, 93, 80, 0.3);
          background: rgba(224, 93, 80, 0.05);
        }
        .tv-spark-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }
        .tv-spark-student {
          display: flex; align-items: center; gap: 0.375rem;
        }
        .tv-spark-avatar {
          width: 24px; height: 24px; border-radius: 6px;
          background: var(--purple); color: white;
          font-size: 0.5rem; font-weight: 700;
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .tv-spark-student span {
          font-size: 0.75rem; font-weight: 600; color: white;
        }
        .tv-spark-trend { font-size: 0.75rem; font-weight: 700; }
        .tv-spark-trend.up { color: var(--teal); }
        .tv-spark-trend.down { color: var(--coral); }
        .tv-spark-trend.flat { color: var(--amber); }
        .tv-spark-line { width: 100%; height: 30px; margin-bottom: 0.375rem; }
        .tv-spark-footer {
          display: flex; justify-content: space-between;
          font-size: 0.625rem; color: rgba(255,255,255,0.4);
        }
        .tv-spark-target.alert { color: var(--coral); font-weight: 600; }
        .tv-spark-empty {
          grid-column: 1 / -1;
          text-align: center;
          padding: 1.5rem;
          color: rgba(255,255,255,0.3);
          font-size: 0.75rem;
        }

        /* ═══ Alerts ═══ */
        .alert-count-badge {
          background: var(--coral);
          color: white;
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.625rem;
          font-weight: 700;
        }
        .alerts-list {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          max-height: 260px;
          overflow-y: auto;
        }
        .alert-item {
          padding: 0.5rem 0.625rem;
          background: rgba(255,255,255,0.02);
          border-radius: 6px;
          border-left: 3px solid var(--text-muted);
        }
        .alert-urgent {
          border-left-color: var(--coral);
          background: rgba(224, 93, 80, 0.06);
        }
        .alert-item-top {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-bottom: 0.125rem;
        }
        .alert-type-label {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--text-secondary);
        }
        .urgency-dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: var(--coral);
        }
        .alert-msg {
          font-size: 0.75rem;
          font-weight: 500;
          line-height: 1.4;
        }
        .alert-student-name {
          font-size: 0.625rem;
          color: var(--text-muted);
          margin-top: 0.125rem;
        }

        /* ═══ Activity Feed ═══ */
        .activity-feed {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          max-height: 320px;
          overflow-y: auto;
        }
        .feed-item {
          display: flex;
          gap: 0.5rem;
          align-items: flex-start;
          padding: 0.375rem 0;
          border-bottom: 1px solid var(--border-subtle);
        }
        .feed-item:last-child {
          border-bottom: none;
        }
        .feed-time {
          font-size: 0.625rem;
          color: var(--text-muted);
          min-width: 3.5rem;
          flex-shrink: 0;
          padding-top: 0.125rem;
        }
        .feed-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
          margin-top: 0.25rem;
        }
        .feed-body {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .feed-text {
          font-size: 0.6875rem;
          line-height: 1.4;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .feed-author {
          font-size: 0.5625rem;
          color: var(--text-muted);
        }

        /* ═══ Empty State ═══ */
        .empty-state {
          font-size: 0.75rem;
          color: var(--text-muted);
          text-align: center;
          padding: 1rem;
        }

        /* ═══ Scrollbar ═══ */
        .alerts-list::-webkit-scrollbar,
        .activity-feed::-webkit-scrollbar {
          width: 4px;
        }
        .alerts-list::-webkit-scrollbar-thumb,
        .activity-feed::-webkit-scrollbar-thumb {
          background: rgba(255,255,255,0.1);
          border-radius: 2px;
        }

        /* ═══ Bottom Ticker Bar ═══ */
        .ticker-bar {
          background: rgba(0,0,0,0.4);
          border-top: 1px solid rgba(255,255,255,0.08);
          overflow: hidden;
          padding: 0.625rem 0;
          position: relative;
          margin-top: 0.5rem;
          flex-shrink: 0;
        }
        .ticker-track {
          display: inline-flex;
          align-items: center;
          white-space: nowrap;
          animation: ticker-scroll 60s linear infinite;
          gap: 0.75rem;
        }
        .ticker-bar:hover .ticker-track {
          animation-play-state: paused;
        }
        @keyframes ticker-scroll {
          from { transform: translateX(0); }
          to { transform: translateX(-50%); }
        }
        .ticker-item {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.25rem 0.625rem;
          border-radius: 999px;
          font-size: 0.75rem;
          font-weight: 600;
        }
        .ticker-icon { font-size: 0.875rem; }
        .ticker-text { color: rgba(255,255,255,0.85); font-weight: 500; }
        .ticker-sep {
          font-size: 1rem;
          color: rgba(255,255,255,0.3);
          padding: 0 0.25rem;
          flex-shrink: 0;
        }
        .ticker-alert { background: rgba(224,93,80,0.18); color: #f0a8a0; }
        .ticker-alert .ticker-text { color: #f0a8a0; }
        .ticker-weekly { background: rgba(42,127,212,0.18); color: #94c5f5; }
        .ticker-weekly .ticker-text { color: #c8dff7; }
        .ticker-highlight { background: rgba(192,139,48,0.18); color: #e8c97a; }
        .ticker-highlight .ticker-text { color: #f0d99c; }
        .ticker-reminder { background: rgba(124,95,196,0.15); color: #c4b5e8; }
        .ticker-reminder .ticker-text { color: #d8cdf0; }
      </style>
    </template>

  };

  // ═══════════════════════════════════════════════════════════════════
  // EMBEDDED — Simple card preview
  // ═══════════════════════════════════════════════════════════════════

  static embedded = class Embedded extends Component<typeof HoSDashboard> {
    get alertCount() {
      let count = 0;
      for (let s of (this.args.model?.students ?? [])) {
        count += s?.alerts?.length ?? 0;
      }
      return count;
    }

    <template>
      <div class='hos-embedded'>
        <div class='emb-title'>{{@model.schoolName}}</div>
        <div class='emb-sub'>HoS Dashboard</div>
        {{#if this.alertCount}}
          <span class='emb-alerts'>{{this.alertCount}} alerts</span>
        {{/if}}
      </div>

      <style scoped>
        .hos-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          padding: 0.75rem;
          background: #1a2332;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 8px;
          color: #e8edf2;
          height: 100%;
        }
        .emb-title {
          font-weight: 700;
          font-size: 0.875rem;
        }
        .emb-sub {
          font-size: 0.6875rem;
          color: rgba(255,255,255,0.5);
        }
        .emb-alerts {
          margin-top: auto;
          font-size: 0.625rem;
          font-weight: 700;
          color: #e05d50;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════
  // FITTED — Compact tile
  // ═══════════════════════════════════════════════════════════════════

  static fitted = class Fitted extends Component<typeof HoSDashboard> {
    get attendancePercent() {
      let students = this.args.model?.students ?? [];
      let total = students.length;
      if (total === 0) return 0;
      let present = students.filter((s: any) =>
        s?.currentLocation?.status?.value === 'in-class'
      ).length;
      return Math.round((present / total) * 100);
    }

    <template>
      <div class='hos-fitted'>
        <span class='fitted-pct'>{{this.attendancePercent}}%</span>
        <span class='fitted-label'>{{@model.schoolName}}</span>
      </div>

      <style scoped>
        .hos-fitted {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.25rem;
          padding: 0.75rem;
          background: #1a2332;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 8px;
          color: #e8edf2;
          height: 100%;
        }
        .fitted-pct {
          font-size: 2rem;
          font-weight: 800;
          color: #2a9d8f;
          line-height: 1;
        }
        .fitted-label {
          font-size: 0.625rem;
          color: rgba(255,255,255,0.5);
          text-align: center;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════
  // EDIT FORMAT
  // ═══════════════════════════════════════════════════════════════════

  static edit = class Edit extends Component<typeof HoSDashboard> {
    <template>
      <div class='hos-edit'>
        <div class='field-row'>
          <label>School Name</label>
          <@fields.schoolName />
        </div>
        <div class='field-row'>
          <label>Date</label>
          <@fields.date />
        </div>
        <div class='field-row'>
          <label>Students</label>
          <@fields.students />
        </div>
        <div class='field-row'>
          <label>Staff</label>
          <@fields.staff />
        </div>
        <div class='field-row'>
          <label>Activity Entries</label>
          <@fields.activities />
        </div>
        <div class='field-row'>
          <label>Learning Goals</label>
          <@fields.goals />
        </div>
      </div>

      <style scoped>
        .hos-edit {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          padding: 1.5rem;
          max-width: 700px;
        }
        .field-row {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .field-row label {
          font-size: 0.6875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #8a8279;
        }
      </style>
    </template>
  };
}

