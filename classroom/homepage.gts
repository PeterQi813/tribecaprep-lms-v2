import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
  getCards,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import HomeIcon from '@cardstack/boxel-icons/home';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Staff } from './staff';
import { Classroom } from './classroom';

export class Homepage extends CardDef {
  static displayName = 'Homepage';
  static icon = HomeIcon;
  static prefersWideFormat = true;

  @field schoolName = contains(StringField);
  @field greeting = contains(StringField);
  @field teacher = linksTo(Staff);
  @field classroom = linksTo(Classroom);
  @field date = contains(DateField);

  @field title = contains(StringField, {
    computeVia: function (this: Homepage) {
      return this.schoolName ?? 'Home';
    },
  });

  static isolated = class Isolated extends Component<typeof Homepage> {
    @tracked students: any[] = [];
    @tracked activityEntries: any[] = [];
    @tracked learningGoals: any[] = [];
    @tracked isLoading = true;

    constructor(owner: any, args: any) {
      super(owner, args);
      this.loadData();
    }

    async loadData() {
      try {
        this.isLoading = true;
        const realmURL = this.args.model?.[Symbol.for('realmURL')];
        const [students, entries, goals] = await Promise.all([
          getCards({ filter: { type: { module: new URL('./student', import.meta.url).href, name: 'Student' } } }, { realmURL }),
          getCards({ filter: { type: { module: new URL('./activity-entry', import.meta.url).href, name: 'ActivityEntry' } } }, { realmURL }),
          getCards({ filter: { type: { module: new URL('./learning-goal', import.meta.url).href, name: 'LearningGoal' } } }, { realmURL }),
        ]);
        this.students = students || [];
        this.activityEntries = entries || [];
        this.learningGoals = goals || [];
      } catch (error) {
        console.error('Error loading homepage data:', error);
      } finally {
        this.isLoading = false;
      }
    }

    get teacherName() { return this.args.model?.teacher?.name ?? 'Teacher'; }
    get teacherFirstName() {
      const name = this.teacherName;
      const parts = name.split(' ');
      return parts.length > 1 ? parts.slice(1).join(' ') : name;
    }
    get teacherInitials() { return this.args.model?.teacher?.initials ?? ''; }
    get teacherColor() { return this.args.model?.teacher?.color ?? '#2a9d8f'; }
    get teacherRole() { return this.args.model?.teacher?.role ?? 'Teacher'; }
    get school() { return this.args.model?.schoolName ?? 'Tribeca Prep'; }
    get classroomName() { return this.args.model?.classroom?.classroomName ?? 'Classroom'; }

    get dateDisplay() {
      const d = this.args.model?.date;
      if (!d) return { day: 'Today', full: '' };
      const date = new Date(d);
      const days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return {
        day: days[date.getDay()],
        full: `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`,
      };
    }

    get greetingText() {
      return this.args.model?.greeting ?? `Good morning, ${this.teacherFirstName}`;
    }

    get inClassroom() { return this.students.filter((s: any) => s.location === 'In Classroom'); }
    get atSpecialists() { return this.students.filter((s: any) => s.location === 'At Specialists'); }
    get absent() { return this.students.filter((s: any) => s.location === 'Absent'); }
    get presentCount() { return this.inClassroom.length + this.atSpecialists.length; }
    get totalCount() { return this.students.length; }

    get urgentAlerts() {
      const alerts: any[] = [];
      for (const student of this.students) {
        if (student.alerts) {
          for (const alert of student.alerts) {
            if (alert.urgency === 'Urgent') {
              alerts.push({ studentName: student.shortName ?? student.name, alertType: alert.alertType, message: alert.message });
            }
          }
        }
      }
      return alerts;
    }

    get allAlerts() {
      const alerts: any[] = [];
      for (const student of this.students) {
        if (student.alerts) {
          for (const alert of student.alerts) {
            alerts.push({ studentName: student.shortName ?? student.name, alertType: alert.alertType, urgency: alert.urgency, message: alert.message, detail: alert.detail });
          }
        }
      }
      return alerts;
    }

    get todayObservations() { return this.activityEntries.length; }
    get activeGoals() { return this.learningGoals.length; }

    get recentEntries() {
      return this.activityEntries
        .sort((a: any, b: any) => {
          const ta = a.timestamp ? new Date(a.timestamp).getTime() : 0;
          const tb = b.timestamp ? new Date(b.timestamp).getTime() : 0;
          return tb - ta;
        })
        .slice(0, 4);
    }

    get goalSummary() {
      if (this.learningGoals.length === 0) return [];
      return this.learningGoals.slice(0, 4);
    }

    getInitial(student: any) {
      const name = student?.shortName ?? student?.name ?? '?';
      return name.charAt(0).toUpperCase();
    }

    get classroomUrl() {
      return this.args.model?.classroom?.id ?? null;
    }

    @action openCard(cardId: string) {
      if (cardId) window.open(cardId, '_self');
    }

    @action openClassroom() {
      if (this.classroomUrl) window.open(this.classroomUrl, '_self');
    }

    <template>
      <div class='homepage'>
        <!-- Header Bar -->
        <header class='hp-header'>
          <div class='hp-brand'>
            <div class='hp-logo'>
              <svg viewBox='0 0 36 36' fill='none'>
                <rect width='36' height='36' rx='8' fill='#e05d50'/>
                <path d='M8 28V14l10-6 10 6v14H8z' fill='white'/>
                <rect x='11' y='16' width='4' height='4' fill='#e05d50'/>
                <rect x='21' y='16' width='4' height='4' fill='#e05d50'/>
                <rect x='15' y='22' width='6' height='6' fill='#e05d50'/>
              </svg>
            </div>
            <div class='hp-brand-text'>
              <span class='hp-school'>{{this.school}}</span>
              <span class='hp-subtitle'>Learning Management System</span>
            </div>
          </div>
          <div class='hp-header-right'>
            <div class='hp-date'>
              <span class='hp-day'>{{this.dateDisplay.day}}</span>
              <span class='hp-full'>{{this.dateDisplay.full}}</span>
            </div>
            <div class='hp-teacher-badge' style='background: {{this.teacherColor}}'>
              {{this.teacherInitials}}
            </div>
          </div>
        </header>

        <!-- Welcome Section -->
        <section class='hp-welcome'>
          <h1 class='hp-greeting'>{{this.greetingText}}</h1>
          <p class='hp-welcome-sub'>Here's your {{this.classroomName}} overview for today.</p>
        </section>

        {{#if this.isLoading}}
          <div class='hp-loading'>
            <span class='hp-spinner'></span>
            <span>Loading dashboard data…</span>
          </div>
        {{else}}

        <!-- Urgent Alerts Banner -->
        {{#if this.urgentAlerts.length}}
          <section class='hp-alerts-banner'>
            <div class='hp-alerts-icon'>
              <svg width='20' height='20' viewBox='0 0 20 20' fill='none' stroke='currentColor' stroke-width='1.5'>
                <path d='M10 6v4M10 13v.5'/>
                <path d='M4 16h12L10 4 4 16z'/>
              </svg>
            </div>
            <div class='hp-alerts-list'>
              {{#each this.urgentAlerts as |alert|}}
                <span class='hp-alert-item'>
                  <strong>{{alert.studentName}}</strong>: {{alert.message}}
                </span>
              {{/each}}
            </div>
          </section>
        {{/if}}

        <!-- Stats Row -->
        <section class='hp-stats'>
          <div class='stat-card attendance'>
            <div class='stat-icon'>
              <svg width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.5'>
                <circle cx='9' cy='7' r='4'/>
                <path d='M3 21v-2c0-2.2 1.8-4 4-4h4c2.2 0 4 1.8 4 4v2'/>
                <path d='M16 3.1a4 4 0 010 7.8M21 21v-2a4 4 0 00-3-3.9'/>
              </svg>
            </div>
            <div class='stat-body'>
              <span class='stat-number'>{{this.presentCount}}<span class='stat-of'>/{{this.totalCount}}</span></span>
              <span class='stat-label'>Students Present</span>
            </div>
            <div class='stat-breakdown'>
              <span class='stat-detail green'>{{this.inClassroom.length}} in room</span>
              <span class='stat-detail blue'>{{this.atSpecialists.length}} at specialists</span>
              <span class='stat-detail gray'>{{this.absent.length}} absent</span>
            </div>
          </div>

          <div class='stat-card observations'>
            <div class='stat-icon'>
              <svg width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.5'>
                <path d='M12 20h9'/>
                <path d='M16.5 3.5a2.1 2.1 0 013 3L7 19l-4 1 1-4L16.5 3.5z'/>
              </svg>
            </div>
            <div class='stat-body'>
              <span class='stat-number'>{{this.todayObservations}}</span>
              <span class='stat-label'>Observations Today</span>
            </div>
          </div>

          <div class='stat-card goals'>
            <div class='stat-icon'>
              <svg width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.5'>
                <circle cx='12' cy='12' r='10'/>
                <circle cx='12' cy='12' r='6'/>
                <circle cx='12' cy='12' r='2'/>
              </svg>
            </div>
            <div class='stat-body'>
              <span class='stat-number'>{{this.activeGoals}}</span>
              <span class='stat-label'>Active Goals</span>
            </div>
          </div>

          <div class='stat-card alerts-stat'>
            <div class='stat-icon'>
              <svg width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.5'>
                <path d='M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9'/>
                <path d='M13.7 21a2 2 0 01-3.4 0'/>
              </svg>
            </div>
            <div class='stat-body'>
              <span class='stat-number'>{{this.allAlerts.length}}</span>
              <span class='stat-label'>Active Alerts</span>
            </div>
          </div>
        </section>

        <!-- Main Content Grid -->
        <div class='hp-grid'>
          <!-- Left Column: Quick Actions + Alerts -->
          <div class='hp-col-left'>
            <section class='hp-section'>
              <h2 class='hp-section-title'>
                <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'>
                  <rect x='2' y='2' width='5' height='5' rx='1'/>
                  <rect x='9' y='2' width='5' height='5' rx='1'/>
                  <rect x='2' y='9' width='5' height='5' rx='1'/>
                  <rect x='9' y='9' width='5' height='5' rx='1'/>
                </svg>
                Quick Actions
              </h2>
              <div class='hp-actions'>
                <div class='action-tile primary' role='button' {{on "click" this.openClassroom}}>
                  <div class='action-icon'>
                    <svg width='28' height='28' viewBox='0 0 28 28' fill='none' stroke='currentColor' stroke-width='1.5'>
                      <rect x='3' y='4' width='22' height='20' rx='2'/>
                      <path d='M3 10h22'/>
                      <path d='M10 4v20'/>
                    </svg>
                  </div>
                  <span class='action-label'>Open Classroom Dashboard</span>
                  <span class='action-desc'>Full 3-column view with roster, student detail, and activity feed</span>
                </div>
                <div class='action-tile' role='button' {{on "click" this.openClassroom}}>
                  <div class='action-icon coral'>
                    <svg width='28' height='28' viewBox='0 0 28 28' fill='none' stroke='currentColor' stroke-width='1.5'>
                      <path d='M14 22h9'/>
                      <path d='M18.5 5.5a2.1 2.1 0 013 3L9 21l-4 1 1-4L18.5 5.5z'/>
                    </svg>
                  </div>
                  <span class='action-label'>Quick Observation</span>
                  <span class='action-desc'>Log a note about a student with AI-assisted tagging</span>
                </div>
                <div class='action-tile' role='button' {{on "click" this.openClassroom}}>
                  <div class='action-icon purple'>
                    <svg width='28' height='28' viewBox='0 0 28 28' fill='none' stroke='currentColor' stroke-width='1.5'>
                      <circle cx='14' cy='14' r='10'/>
                      <circle cx='14' cy='14' r='6'/>
                      <circle cx='14' cy='14' r='2'/>
                    </svg>
                  </div>
                  <span class='action-label'>Goal Progress</span>
                  <span class='action-desc'>Review IEP and learning goals with mastery tracking</span>
                </div>
                <div class='action-tile' role='button' {{on "click" this.openClassroom}}>
                  <div class='action-icon amber'>
                    <svg width='28' height='28' viewBox='0 0 28 28' fill='none' stroke='currentColor' stroke-width='1.5'>
                      <circle cx='10' cy='10' r='5'/>
                      <circle cx='18' cy='10' r='5'/>
                      <path d='M3 24c2-4 4-6 7-6s5 2 5 2 2-2 5-2 5 2 7 6'/>
                    </svg>
                  </div>
                  <span class='action-label'>Student Roster</span>
                  <span class='action-desc'>View all students, status, and staff assignments</span>
                </div>
              </div>
            </section>

            <!-- Today's Alerts -->
            {{#if this.allAlerts.length}}
              <section class='hp-section'>
                <h2 class='hp-section-title'>
                  <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'>
                    <path d='M14 8A6 6 0 002 8c0 5-2 7-2 7h16s-2-2-2-7'/>
                    <path d='M9.7 15a2 2 0 01-3.4 0'/>
                  </svg>
                  Today's Alerts
                </h2>
                <div class='hp-alert-list'>
                  {{#each this.allAlerts as |alert|}}
                    <div class='hp-alert-row {{if (eq alert.urgency "Urgent") "urgent" "info"}}'>
                      <span class='hp-alert-badge {{if (eq alert.urgency "Urgent") "urgent" "info"}}'>{{alert.alertType}}</span>
                      <div class='hp-alert-body'>
                        <span class='hp-alert-student'>{{alert.studentName}}</span>
                        <span class='hp-alert-msg'>{{alert.message}}</span>
                      </div>
                    </div>
                  {{/each}}
                </div>
              </section>
            {{/if}}
          </div>

          <!-- Right Column: Recent Activity + Goals -->
          <div class='hp-col-right'>
            <section class='hp-section'>
              <h2 class='hp-section-title'>
                <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'>
                  <circle cx='8' cy='8' r='6'/>
                  <path d='M8 5v3l2 2'/>
                </svg>
                Recent Activity
              </h2>
              <div class='hp-activity-list'>
                {{#each this.recentEntries as |entry|}}
                  <article class='hp-entry' role='button' {{on "click" (fn this.openCard entry.id)}}>
                    <div class='hp-entry-header'>
                      <span class='hp-entry-author'>
                        <span class='hp-author-dot' style='background: {{if entry.author entry.author.color "#888"}}'></span>
                        {{if entry.author entry.author.name "Staff"}}
                      </span>
                      <span class='hp-entry-type {{entry.entryType}}'>{{entry.entryType}}</span>
                    </div>
                    <div class='hp-entry-body'>
                      <span class='hp-entry-student'>{{if entry.student entry.student.shortName "Student"}}</span>
                      <p class='hp-entry-text'>{{entry.content}}</p>
                    </div>
                    {{#if entry.score}}
                      <span class='hp-entry-score'>{{entry.score}}</span>
                    {{/if}}
                    {{#if (eq entry.aiTagged "true")}}
                      <span class='hp-ai-badge'>
                        <svg width='10' height='10' viewBox='0 0 10 10' fill='currentColor'>
                          <circle cx='5' cy='5' r='4'/>
                        </svg>
                        AI Tagged
                      </span>
                    {{/if}}
                  </article>
                {{/each}}
                {{#unless this.recentEntries.length}}
                  <div class='hp-empty'>No observations recorded yet today.</div>
                {{/unless}}
              </div>
            </section>

            <section class='hp-section'>
              <h2 class='hp-section-title'>
                <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'>
                  <circle cx='8' cy='8' r='6'/>
                  <circle cx='8' cy='8' r='3'/>
                  <circle cx='8' cy='8' r='1' fill='currentColor'/>
                </svg>
                Goal Tracking
              </h2>
              <div class='hp-goals-list'>
                {{#each this.goalSummary as |goal|}}
                  <div class='hp-goal' role='button' {{on "click" (fn this.openCard goal.id)}}>
                    <div class='hp-goal-header'>
                      <span class='hp-goal-domain {{goal.domain}}'>{{goal.domain}}</span>
                      <span class='hp-goal-student'>{{if goal.student goal.student.shortName "Student"}}</span>
                    </div>
                    <span class='hp-goal-title'>{{goal.goalTitle}}</span>
                    <div class='hp-goal-progress'>
                      <div class='hp-goal-bar'>
                        <div class='hp-goal-fill' style='width: {{goal.currentMastery}}%'></div>
                      </div>
                      <span class='hp-goal-pct'>{{goal.currentMastery}}%</span>
                    </div>
                  </div>
                {{/each}}
                {{#unless this.goalSummary.length}}
                  <div class='hp-empty'>No active goals to display.</div>
                {{/unless}}
              </div>
            </section>

            <!-- Student Roster Quick View -->
            <section class='hp-section'>
              <h2 class='hp-section-title'>
                <svg width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'>
                  <circle cx='6' cy='5' r='3'/>
                  <circle cx='12' cy='5' r='2'/>
                  <path d='M1 14c1-3 2.5-4.5 5-4.5s4 1.5 5 4.5'/>
                  <path d='M10 13c0.5-2 1.5-3 3-3s2 1 2.5 3'/>
                </svg>
                Student Roster
              </h2>
              <div class='hp-roster'>
                {{#each this.students as |student|}}
                  <div class='hp-roster-row' role='button' {{on "click" (fn this.openCard student.id)}}>
                    <div class='hp-roster-avatar'>
                      {{#if student.avatar}}
                        <img class='hp-roster-img' src={{student.avatar}} alt={{student.name}} />
                      {{else}}
                        <span class='hp-roster-initial'>{{this.getInitial student}}</span>
                      {{/if}}
                      <span class='hp-roster-status {{if (eq student.location "In Classroom") "present" (if (eq student.location "At Specialists") "specialist" "absent")}}'></span>
                    </div>
                    <div class='hp-roster-info'>
                      <span class='hp-roster-name'>{{student.name}}</span>
                      <span class='hp-roster-loc'>{{student.location}}{{#if student.locationDetail}} · {{student.locationDetail}}{{/if}}</span>
                    </div>
                    <div class='hp-roster-tags'>
                      {{#each student.tags as |tag|}}
                        <span class='hp-roster-tag {{if (eq tag.label "IEP") "purple" (if (eq tag.label "Allergy") "coral" (if (eq tag.label "504") "teal" ""))}}'>{{tag.label}}</span>
                      {{/each}}
                    </div>
                  </div>
                {{/each}}
              </div>
            </section>
          </div>
        </div>

        {{/if}}
      </div>
      <style scoped>
        /* ═══════════════════════════════════════════
           HOMEPAGE — Warm Editorial Palette
           ═══════════════════════════════════════════ */
        .homepage {
          --surface-0: #fffdfb;
          --surface-1: #faf8f6;
          --surface-2: #f5f2ef;
          --surface-3: #ebe7e3;
          --text-1: #1a1816;
          --text-2: #5c5650;
          --text-3: #8a8279;
          --coral: #e05d50;
          --coral-soft: #fdf0ee;
          --amber: #c08b30;
          --amber-soft: #fdf6e8;
          --purple: #7c5fc4;
          --purple-soft: #f4f0fa;
          --teal: #2a9d8f;
          --teal-soft: #edf8f6;
          --green: #4a8c5c;
          --green-soft: #edf6f0;
          --blue: #4a7cc4;
          --blue-soft: #edf2fa;
          --border: #e8e4e0;
          --card: #ffffff;
          --radius: 12px;
          --radius-sm: 8px;

          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: var(--surface-1);
          color: var(--text-1);
          min-height: 100vh;
          padding: 0;
          margin: 0;
        }

        /* ── Header ── */
        .hp-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 16px 32px;
          background: var(--card);
          border-bottom: 1px solid var(--border);
        }
        .hp-brand {
          display: flex;
          align-items: center;
          gap: 12px;
        }
        .hp-logo svg {
          width: 36px;
          height: 36px;
        }
        .hp-brand-text {
          display: flex;
          flex-direction: column;
        }
        .hp-school {
          font-size: 16px;
          font-weight: 700;
          color: var(--text-1);
          letter-spacing: -0.01em;
        }
        .hp-subtitle {
          font-size: 11px;
          color: var(--text-3);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .hp-header-right {
          display: flex;
          align-items: center;
          gap: 16px;
        }
        .hp-date {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
        }
        .hp-day {
          font-size: 13px;
          font-weight: 600;
          color: var(--text-1);
        }
        .hp-full {
          font-size: 12px;
          color: var(--text-3);
        }
        .hp-teacher-badge {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 13px;
          font-weight: 700;
          letter-spacing: 0.02em;
        }

        /* ── Welcome ── */
        .hp-welcome {
          padding: 32px 32px 0;
        }
        .hp-greeting {
          font-size: 28px;
          font-weight: 700;
          color: var(--text-1);
          margin: 0 0 6px;
          letter-spacing: -0.02em;
        }
        .hp-welcome-sub {
          font-size: 15px;
          color: var(--text-2);
          margin: 0;
        }

        /* ── Loading ── */
        .hp-loading {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          padding: 60px 0;
          color: var(--text-3);
          font-size: 14px;
        }
        .hp-spinner {
          width: 18px;
          height: 18px;
          border: 2px solid var(--border);
          border-top-color: var(--teal);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* ── Urgent Alerts Banner ── */
        .hp-alerts-banner {
          display: flex;
          align-items: flex-start;
          gap: 12px;
          margin: 20px 32px 0;
          padding: 14px 18px;
          background: var(--amber-soft);
          border: 1px solid #e8d5a8;
          border-radius: var(--radius-sm);
        }
        .hp-alerts-icon {
          color: var(--amber);
          flex-shrink: 0;
          margin-top: 1px;
        }
        .hp-alerts-list {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .hp-alert-item {
          font-size: 13px;
          color: var(--text-1);
          line-height: 1.4;
        }
        .hp-alert-item strong {
          font-weight: 600;
        }

        /* ── Stats Row ── */
        .hp-stats {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 16px;
          padding: 24px 32px;
        }
        .stat-card {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 20px;
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .stat-icon {
          color: var(--text-3);
        }
        .stat-card.attendance .stat-icon { color: var(--teal); }
        .stat-card.observations .stat-icon { color: var(--coral); }
        .stat-card.goals .stat-icon { color: var(--purple); }
        .stat-card.alerts-stat .stat-icon { color: var(--amber); }

        .stat-body {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .stat-number {
          font-size: 32px;
          font-weight: 700;
          color: var(--text-1);
          line-height: 1;
          letter-spacing: -0.02em;
        }
        .stat-of {
          font-size: 18px;
          font-weight: 400;
          color: var(--text-3);
        }
        .stat-label {
          font-size: 12px;
          color: var(--text-3);
          text-transform: uppercase;
          letter-spacing: 0.04em;
          font-weight: 600;
        }
        .stat-breakdown {
          display: flex;
          gap: 10px;
          margin-top: 4px;
        }
        .stat-detail {
          font-size: 11px;
          font-weight: 500;
        }
        .stat-detail.green { color: var(--green); }
        .stat-detail.blue { color: var(--blue); }
        .stat-detail.gray { color: var(--text-3); }

        /* ── Main Grid ── */
        .hp-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 24px;
          padding: 0 32px 32px;
        }

        /* ── Sections ── */
        .hp-section {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 20px;
          margin-bottom: 0;
        }
        .hp-col-left, .hp-col-right {
          display: flex;
          flex-direction: column;
          gap: 20px;
        }
        .hp-section-title {
          display: flex;
          align-items: center;
          gap: 8px;
          font-size: 13px;
          font-weight: 700;
          color: var(--text-2);
          text-transform: uppercase;
          letter-spacing: 0.04em;
          margin: 0 0 16px;
        }
        .hp-section-title svg {
          color: var(--text-3);
        }

        /* ── Quick Actions ── */
        .hp-actions {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 12px;
        }
        .action-tile {
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          padding: 16px;
          display: flex;
          flex-direction: column;
          gap: 6px;
          cursor: pointer;
          transition: border-color 0.15s, box-shadow 0.15s;
        }
        .action-tile:hover {
          border-color: var(--teal);
          box-shadow: 0 2px 8px rgba(42,157,143,0.1);
        }
        .action-tile.primary {
          grid-column: 1 / -1;
          background: var(--teal-soft);
          border-color: rgba(42,157,143,0.3);
        }
        .action-tile.primary:hover {
          border-color: var(--teal);
        }
        .action-icon {
          color: var(--teal);
        }
        .action-icon.coral { color: var(--coral); }
        .action-icon.purple { color: var(--purple); }
        .action-icon.amber { color: var(--amber); }
        .action-label {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-1);
        }
        .action-desc {
          font-size: 12px;
          color: var(--text-3);
          line-height: 1.4;
        }

        /* ── Today's Alerts ── */
        .hp-alert-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .hp-alert-row {
          display: flex;
          align-items: flex-start;
          gap: 10px;
          padding: 10px 12px;
          border-radius: var(--radius-sm);
          background: var(--surface-1);
        }
        .hp-alert-row.urgent {
          background: var(--amber-soft);
        }
        .hp-alert-badge {
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 3px 8px;
          border-radius: 4px;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .hp-alert-badge.urgent {
          background: var(--amber);
          color: white;
        }
        .hp-alert-badge.info {
          background: var(--surface-3);
          color: var(--text-2);
        }
        .hp-alert-body {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .hp-alert-student {
          font-size: 13px;
          font-weight: 600;
          color: var(--text-1);
        }
        .hp-alert-msg {
          font-size: 12px;
          color: var(--text-2);
          line-height: 1.4;
        }

        /* ── Recent Activity ── */
        .hp-activity-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }
        .hp-entry {
          padding: 12px;
          background: var(--surface-1);
          border-radius: var(--radius-sm);
          cursor: pointer;
          transition: background 0.15s;
        }
        .hp-entry:hover { background: var(--surface-2); }
        .hp-entry-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 6px;
        }
        .hp-entry-author {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 12px;
          font-weight: 600;
          color: var(--text-2);
        }
        .hp-author-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
        }
        .hp-entry-type {
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 2px 6px;
          border-radius: 4px;
        }
        .hp-entry-type.Academic { background: var(--teal-soft); color: var(--teal); }
        .hp-entry-type.Social { background: var(--purple-soft); color: var(--purple); }
        .hp-entry-type.Behavioral { background: var(--coral-soft); color: var(--coral); }

        .hp-entry-body {
          display: flex;
          flex-direction: column;
          gap: 3px;
        }
        .hp-entry-student {
          font-size: 12px;
          font-weight: 600;
          color: var(--text-1);
        }
        .hp-entry-text {
          font-size: 13px;
          color: var(--text-2);
          margin: 0;
          line-height: 1.45;
        }
        .hp-entry-score {
          display: inline-block;
          margin-top: 6px;
          font-size: 11px;
          font-weight: 600;
          color: var(--teal);
          background: var(--teal-soft);
          padding: 2px 8px;
          border-radius: 4px;
        }
        .hp-ai-badge {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          margin-top: 6px;
          margin-left: 6px;
          font-size: 10px;
          font-weight: 600;
          color: var(--purple);
          background: var(--purple-soft);
          padding: 2px 8px;
          border-radius: 4px;
        }
        .hp-ai-badge svg { color: var(--purple); }

        /* ── Goal Tracking ── */
        .hp-goals-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }
        .hp-goal {
          padding: 12px;
          background: var(--surface-1);
          border-radius: var(--radius-sm);
          cursor: pointer;
          transition: background 0.15s;
        }
        .hp-goal:hover { background: var(--surface-2); }
        .hp-goal-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 4px;
        }
        .hp-goal-domain {
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 2px 6px;
          border-radius: 4px;
        }
        .hp-goal-domain.Math { background: var(--teal-soft); color: var(--teal); }
        .hp-goal-domain.Reading { background: var(--blue-soft); color: var(--blue); }
        .hp-goal-domain.Social { background: var(--purple-soft); color: var(--purple); }
        .hp-goal-domain.Behavioral { background: var(--coral-soft); color: var(--coral); }
        .hp-goal-domain.Motor { background: var(--amber-soft); color: var(--amber); }
        .hp-goal-domain.Communication { background: var(--green-soft); color: var(--green); }

        .hp-goal-student {
          font-size: 11px;
          color: var(--text-3);
          font-weight: 500;
        }
        .hp-goal-title {
          font-size: 13px;
          font-weight: 600;
          color: var(--text-1);
          display: block;
          margin-bottom: 8px;
        }
        .hp-goal-progress {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .hp-goal-bar {
          flex: 1;
          height: 6px;
          background: var(--surface-3);
          border-radius: 3px;
          overflow: hidden;
        }
        .hp-goal-fill {
          height: 100%;
          background: var(--teal);
          border-radius: 3px;
          transition: width 0.3s ease;
        }
        .hp-goal-pct {
          font-size: 13px;
          font-weight: 700;
          color: var(--text-1);
          min-width: 36px;
          text-align: right;
        }

        /* ── Student Roster ── */
        .hp-roster {
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .hp-roster-row {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 8px 10px;
          border-radius: var(--radius-sm);
          background: var(--surface-1);
          cursor: pointer;
          transition: background 0.15s;
        }
        .hp-roster-row:hover { background: var(--surface-2); }
        .hp-roster-avatar {
          position: relative;
          width: 32px;
          height: 32px;
          border-radius: 50%;
          background: var(--surface-3);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .hp-roster-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          border-radius: 50%;
        }
        .hp-roster-initial {
          font-size: 12px;
          font-weight: 700;
          color: var(--text-2);
        }
        .hp-roster-status {
          position: absolute;
          bottom: -1px;
          right: -1px;
          width: 10px;
          height: 10px;
          border-radius: 50%;
          border: 2px solid var(--card);
        }
        .hp-roster-status.present { background: var(--green); }
        .hp-roster-status.specialist { background: var(--blue); }
        .hp-roster-status.absent { background: var(--text-3); }

        .hp-roster-info {
          flex: 1;
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .hp-roster-name {
          font-size: 13px;
          font-weight: 600;
          color: var(--text-1);
        }
        .hp-roster-loc {
          font-size: 11px;
          color: var(--text-3);
        }
        .hp-roster-tags {
          display: flex;
          gap: 4px;
        }
        .hp-roster-tag {
          font-size: 9px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 2px 5px;
          border-radius: 3px;
          background: var(--surface-3);
          color: var(--text-3);
        }
        .hp-roster-tag.purple { background: var(--purple-soft); color: var(--purple); }
        .hp-roster-tag.coral { background: var(--coral-soft); color: var(--coral); }
        .hp-roster-tag.teal { background: var(--teal-soft); color: var(--teal); }

        /* ── Empty State ── */
        .hp-empty {
          text-align: center;
          padding: 20px;
          font-size: 13px;
          color: var(--text-3);
        }

        /* ── Responsive ── */
        @container (max-width: 800px) {
          .hp-stats { grid-template-columns: repeat(2, 1fr); }
          .hp-grid { grid-template-columns: 1fr; }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Homepage> {
    get safeName() { return this.args.model?.schoolName ?? 'Homepage'; }
    get teacherName() { return this.args.model?.teacher?.name ?? 'Teacher'; }
    <template>
      <div class='embedded-container'>
        <div class='hp-logo'>
          <svg viewBox='0 0 36 36' fill='none'>
            <rect width='36' height='36' rx='8' fill='#e05d50'/>
            <path d='M8 28V14l10-6 10 6v14H8z' fill='white'/>
            <rect x='11' y='16' width='4' height='4' fill='#e05d50'/>
            <rect x='21' y='16' width='4' height='4' fill='#e05d50'/>
            <rect x='15' y='22' width='6' height='6' fill='#e05d50'/>
          </svg>
        </div>
        <div class='info'>
          <span class='name'>{{this.safeName}}</span>
          <span class='teacher'>{{this.teacherName}}</span>
        </div>
      </div>
      <style scoped>
        .embedded-container { display: flex; align-items: center; gap: 12px; padding: 12px; }
        .hp-logo svg { width: 32px; height: 32px; }
        .info { display: flex; flex-direction: column; }
        .name { font-size: 14px; font-weight: 600; color: #1a1816; }
        .teacher { font-size: 12px; color: #8a8279; }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Homepage> {
    get safeName() { return this.args.model?.schoolName ?? 'Homepage'; }
    <template>
      <div class='fitted-container'>
        <div class='hp-logo'>
          <svg viewBox='0 0 36 36' fill='none'>
            <rect width='36' height='36' rx='8' fill='#e05d50'/>
            <path d='M8 28V14l10-6 10 6v14H8z' fill='white'/>
            <rect x='11' y='16' width='4' height='4' fill='#e05d50'/>
            <rect x='21' y='16' width='4' height='4' fill='#e05d50'/>
            <rect x='15' y='22' width='6' height='6' fill='#e05d50'/>
          </svg>
        </div>
        <span class='tile-name'>{{this.safeName}}</span>
      </div>
      <style scoped>
        .fitted-container { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; padding: 16px; height: 100%; container-type: size; }
        .hp-logo svg { width: 40px; height: 40px; }
        .tile-name { font-size: 14px; font-weight: 700; color: #1a1816; text-align: center; }
      </style>
    </template>
  };
}
