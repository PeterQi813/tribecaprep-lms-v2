// Tribeca Prep LMS — StudentFullProfile (Sensitive Realm)
// Complete student record — HoS + Front Desk only
// Contains all medical, financial, legal, and family information

import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';

import { TribecaPrepCardInfo } from './shared-fields';
import { Student } from './student';
import { syncStudentsToClassroom } from './sync-students-to-classroom';
import { syncFullProfileToAdmin } from './sync-full-profile-to-admin';

import {
  IdentitySection,
  MedicalSection,
  FamilySection,
  CustodySection,
  FinancialSection,
  IEPSection,
} from './profile-sections';

// ═══════════════════════════════════════════════════════════════════════════════
// STUDENT FULL PROFILE — Complete Sensitive Record with Section Navigation
// ═══════════════════════════════════════════════════════════════════════════════

export class StudentFullProfile extends CardDef {
  // ¹²
  static displayName = 'Student Full Profile';
  static prefersWideFormat = true; // ⁶¹ Enable wide layout for left nav

  // ─── CARD INFO ─── // ¹³
  @field cardInfo = contains(TribecaPrepCardInfo);

  // ─── SECTIONS ─── // ⁶² Replace flat fields with section contains
  @field identity = contains(IdentitySection);
  @field medical = contains(MedicalSection);
  @field family = contains(FamilySection);
  @field custody = contains(CustodySection);
  @field financial = contains(FinancialSection);
  @field iep = contains(IEPSection);

  // ─── LINKED STUDENT STUB ─── // ¹⁴
  // ¹⁰³ Arrow function for forward reference
  @field studentStub = linksTo(() => Student);

  // ─── COMPUTED (from sections) ─── // ⁶³ Pass-through from identity section
  @field displayName = contains(StringField, {
    computeVia: function (this: StudentFullProfile) {
      return this.identity?.displayName || 'Unknown Student';
    },
  });

  @field initials = contains(StringField, {
    computeVia: function (this: StudentFullProfile) {
      return this.identity?.initials || '??';
    },
  });

  @field age = contains(NumberField, {
    computeVia: function (this: StudentFullProfile) {
      return this.identity?.age || 0;
    },
  });

  @field hasAllergy = contains(BooleanField, {
    computeVia: function (this: StudentFullProfile) {
      return this.medical?.hasAllergy || false;
    },
  });

  @field hasMedication = contains(BooleanField, {
    computeVia: function (this: StudentFullProfile) {
      return this.medical?.hasMedication || false;
    },
  });

  @field hasCustodyAlert = contains(BooleanField, {
    computeVia: function (this: StudentFullProfile) {
      return this.custody?.hasCustodyAlert || false;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: StudentFullProfile) {
      return this.displayName || 'Student Full Profile';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: StudentFullProfile) {
      const first = this.identity?.firstName || '';
      const last = this.identity?.lastName || '';
      return `${first} ${last}`.trim() || 'Student Full Profile';
    },
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // ISOLATED FORMAT — Section-based navigation layout
  // ═══════════════════════════════════════════════════════════════════════════════

  static isolated = class Isolated extends Component<typeof this> {
    // ⁶⁴
    @tracked activeSection = 'identity'; // ⁶⁵ Track active section for highlighting
    @tracked syncing = false;
    @tracked syncErrorMsg: string | null = null;

    HOS_DASHBOARD_URL = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/HoSDashboard/main';

    // ⁶⁶ Navigation items
    sections = [
      { id: 'identity', label: 'Overview', icon: 'user' },
      { id: 'medical', label: 'Medical', icon: 'medical' },
      { id: 'family', label: 'Family', icon: 'family' },
      { id: 'custody', label: 'Custody', icon: 'shield' },
      { id: 'financial', label: 'Financial', icon: 'card' },
      { id: 'iep', label: 'IEP/504', icon: 'document' },
    ];

    // ⁶⁷ Scroll to section handler
    scrollToSection = (sectionId: string) => {
      this.activeSection = sectionId;
      const element = document.getElementById(`section-${sectionId}`);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    };

    get hostGetCards(): any {
      const a = this.args as any;
      return a.context?.getCards ?? a.context?.actions?.getCards ?? null;
    }
    get hostCommandContext(): any {
      const a = this.args as any;
      return a.context?.commandContext ?? a.context?.actions?.commandContext ?? null;
    }

    // Minimal unwrapResource — same as in hos-dashboard, polls the resource until ready.
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

    // Sync this profile to all downstream realms, then navigate back to HoS Dashboard.
    handleBackAndSync = async () => {
      this.syncing = true;
      this.syncErrorMsg = null;
      const ctx = this.hostCommandContext;
      const getCards = this.hostGetCards;
      const profile = this.args.model;
      if (!ctx || !getCards || !profile) {
        // Context unavailable — just navigate
        window.location.href = this.HOS_DASHBOARD_URL;
        return;
      }
      const errs: string[] = [];
      try {
        const r = await syncStudentsToClassroom({
          profiles: [profile], ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        if (r.failed > 0) {
          console.warn('[FullProfile-Classroom] sync failed:', r.errors);
          errs.push(`Classroom: ${r.errors[0]?.error ?? 'unknown'}`);
        } else {
          console.log(`[FullProfile-Classroom] synced (${r.created} new, ${r.updated} updated, ${r.skipped} skipped)`);
        }
      } catch (e: any) {
        console.warn('[FullProfile-Classroom] sync exception:', e);
        errs.push(`Classroom: ${e?.message ?? String(e)}`);
      }

      try {
        const r = await syncFullProfileToAdmin({
          profiles: [profile], ctx, getCards, host: this,
          unwrapResource: this.unwrapResource,
        });
        if (r.failed > 0) {
          console.warn('[FullProfile-Admin] sync failed:', r.errors);
          errs.push(`Admin: ${r.errors[0]?.error ?? 'unknown'}`);
        } else {
          console.log(`[FullProfile-Admin] synced (${r.created} new, ${r.updated} updated, ${r.skipped} skipped)`);
        }
      } catch (e: any) {
        console.warn('[FullProfile-Admin] sync exception:', e);
        errs.push(`Admin: ${e?.message ?? String(e)}`);
      }

      if (errs.length > 0) {
        this.syncErrorMsg = errs.join(' | ');
        this.syncing = false;
        return;
      }
      window.location.href = this.HOS_DASHBOARD_URL;
    };

    <template>
      <article class='profile'>
        <button
          class='back-link'
          type='button'
          disabled={{this.syncing}}
          {{on 'click' this.handleBackAndSync}}
        >
          {{#if this.syncing}}Saving and syncing…{{else}}← Back to HoS Dashboard (save){{/if}}
        </button>
        {{#if this.syncErrorMsg}}
          <div class='back-link-err'>{{this.syncErrorMsg}}</div>
        {{/if}}
        {{! ⁷⁰ Sensitive Banner }}
        <div class='sensitive-banner'>
          <svg
            class='lock-icon'
            width='14'
            height='14'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <rect x='3' y='11' width='18' height='11' rx='2' />
            <path d='M7 11V7a5 5 0 0 1 10 0v4' />
          </svg>
          <span>SENSITIVE RECORD — Authorized Personnel Only</span>
        </div>

        <div class='profile-layout'>
          {{! ⁷¹ Left Navigation Rail }}
          <nav class='profile-nav'>
            <div class='nav-header'>
              <div class='nav-avatar'>{{@model.initials}}</div>
              <div class='nav-info'>
                <span class='nav-name'><@fields.identity.firstName /> <@fields.identity.lastName /></span>
                <span class='nav-id'><@fields.identity.studentId /></span>
              </div>
            </div>

            <div class='nav-sections'>
              {{#each this.sections as |section|}}
                <button
                  class='nav-btn
                    {{if (eq this.activeSection section.id) "active"}}'
                  type='button'
                  {{on 'click' (fn this.scrollToSection section.id)}}
                >
                  {{#if (eq section.icon 'user')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <circle cx='12' cy='8' r='4' /><path
                        d='M4 20c0-4 4-6 8-6s8 2 8 6'
                      />
                    </svg>
                  {{else if (eq section.icon 'medical')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path d='M3 9h18v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9z' />
                      <path d='M12 12v6M9 15h6' />
                    </svg>
                  {{else if (eq section.icon 'family')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <circle cx='9' cy='7' r='3' /><circle
                        cx='15'
                        cy='7'
                        r='3'
                      />
                      <path d='M3 21c0-4 3-6 6-6' /><path
                        d='M15 15c3 0 6 2 6 6'
                      />
                    </svg>
                  {{else if (eq section.icon 'shield')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path d='M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z' />
                    </svg>
                  {{else if (eq section.icon 'card')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <rect x='2' y='4' width='20' height='16' rx='2' />
                      <path d='M12 10v4M10 12h4' />
                    </svg>
                  {{else if (eq section.icon 'document')}}
                    <svg
                      width='16'
                      height='16'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path
                        d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'
                      />
                      <path d='M14 2v6h6' />
                    </svg>
                  {{/if}}
                  <span>{{section.label}}</span>
                </button>
              {{/each}}
            </div>

            {{! ⁷² Quick badges in nav }}
            <div class='nav-badges'>
              {{#if @model.iep.hasIEP}}
                <span class='nav-badge iep'>IEP</span>
              {{/if}}
              {{#if @model.iep.has504}}
                <span class='nav-badge plan'>504</span>
              {{/if}}
              {{#if @model.hasAllergy}}
                <span class='nav-badge allergy'>Allergy</span>
              {{/if}}
              {{#if @model.hasMedication}}
                <span class='nav-badge medication'>Meds</span>
              {{/if}}
              {{#if @model.hasCustodyAlert}}
                <span class='nav-badge custody'>Custody</span>
              {{/if}}
            </div>

            {{! ⁷³ Linked stub preview }}
            {{#if @model.studentStub}}
              <div class='nav-stub'>
                <span class='stub-label'>Public Record</span>
                <div class='stub-preview'>
                  <@fields.studentStub @format='fitted' />
                </div>
              </div>
            {{/if}}
          </nav>

          {{! ⁷⁴ Main Content Area with Sections }}
          <main class='profile-main'>
            {{! ⁷⁵ Header with key info }}
            <header class='profile-header'>
              <div class='header-identity'>
                <div class='header-avatar'>{{@model.initials}}</div>
                <div class='header-info'>
                  <div class='header-name-row'>
                    <div class='header-field'><span class='field-label'>First Name</span><@fields.identity.firstName /></div>
                    <div class='header-field'><span class='field-label'>Last Name</span><@fields.identity.lastName /></div>
                  </div>
                  <div class='header-field'><span class='field-label'>Preferred Name</span><@fields.identity.preferredName /></div>
                  <div class='header-meta'>
                    <div class='header-field'>
                      <span class='field-label'>ID</span>
                      <span class='meta-value mono'><@fields.identity.studentId /></span>
                    </div>
                    <div class='header-field'>
                      <span class='field-label'>Grade</span>
                      <@fields.identity.gradeLevel />
                    </div>
                    <div class='header-field'>
                      <span class='field-label'>DOB</span>
                      <@fields.identity.dateOfBirth />
                    </div>
                    <div class='header-field'>
                      <span class='field-label'>Active</span>
                      <@fields.identity.active />
                    </div>
                  </div>
                </div>
              </div>
            </header>

            {{! ⁷⁶ All sections rendered via embedded templates }}
            <div class='sections-container'>
              <@fields.identity @format='embedded' />
              <@fields.medical @format='embedded' />
              <@fields.family @format='embedded' />
              <@fields.custody @format='embedded' />
              <@fields.financial @format='embedded' />
              <@fields.iep @format='embedded' />
            </div>
          </main>
        </div>
      </article>

      <style scoped>
        /* ⁷⁷ Design tokens from mockup */
        .profile {
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
          --teal-soft: #e8f6f4;
          --radius-sm: 6px;
          --radius-md: 10px;
          --radius-lg: 14px;

          font-family: 'Inter', var(--font-sans, system-ui, sans-serif);
          background: var(--surface-1);
          color: var(--text-1);
          min-height: 100%;
        }

        /* ⁷⁸ Sensitive banner */
        .back-link {
          display: inline-block;
          padding: 0.5rem 0;
          font-size: 0.8125rem;
          font-weight: 600;
          color: #7c5fc4;
          text-decoration: none;
          background: transparent;
          border: none;
          cursor: pointer;
        }
        .back-link:hover:not([disabled]) { text-decoration: underline; }
        .back-link[disabled] { opacity: 0.6; cursor: wait; }
        .back-link-err {
          font-size: 0.75rem;
          color: #c44545;
          padding: 0.25rem 0.5rem;
          margin: 0.25rem 0;
        }
        .sensitive-banner {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 0.625rem;
          background: var(--coral);
          color: white;
          font-size: 0.6875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.1em;
        }

        .lock-icon {
          flex-shrink: 0;
        }

        /* ⁷⁹ Main layout grid */
        .profile-layout {
          display: grid;
          grid-template-columns: 220px 1fr;
          min-height: calc(100vh - 40px);
        }

        /* ⁸⁰ Left navigation rail */
        .profile-nav {
          position: sticky;
          top: 0;
          height: 100vh;
          overflow-y: auto;
          padding: 1.25rem;
          background: var(--surface-0);
          border-right: 1px solid var(--surface-2);
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }

        .nav-header {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding-bottom: 1rem;
          border-bottom: 1px solid var(--surface-2);
        }

        .nav-photo,
        .nav-avatar {
          width: 40px;
          height: 40px;
          border-radius: var(--radius-sm);
          flex-shrink: 0;
        }

        .nav-photo {
          object-fit: cover;
        }

        .nav-avatar {
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--purple);
          color: white;
          font-weight: 600;
          font-size: 0.875rem;
        }

        .nav-info {
          overflow: hidden;
        }

        .nav-name {
          display: block;
          font-weight: 600;
          font-size: 0.875rem;
          color: var(--text-1);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .nav-id {
          display: block;
          font-size: 0.6875rem;
          color: var(--text-3);
          font-family: var(--font-mono, ui-monospace, monospace);
        }

        .nav-sections {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .nav-btn {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          border: none;
          border-radius: var(--radius-sm);
          background: transparent;
          color: var(--text-2);
          font-family: inherit;
          font-size: 0.8125rem;
          font-weight: 500;
          cursor: pointer;
          transition:
            background 0.15s,
            color 0.15s;
          text-align: left;
        }

        .nav-btn:hover {
          background: var(--surface-1);
          color: var(--text-1);
        }

        .nav-btn.active {
          background: var(--coral-soft);
          color: var(--coral);
          font-weight: 600;
        }

        .nav-btn svg {
          flex-shrink: 0;
        }

        .nav-badges {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
          padding-top: 0.75rem;
          border-top: 1px solid var(--surface-2);
        }

        .nav-badge {
          padding: 0.125rem 0.375rem;
          font-size: 0.5625rem;
          font-weight: 600;
          text-transform: uppercase;
          border-radius: 3px;
        }

        .nav-badge.iep {
          background: var(--purple-soft);
          color: var(--purple);
        }

        .nav-badge.plan {
          background: var(--teal-soft);
          color: var(--teal);
        }

        .nav-badge.allergy {
          background: var(--amber-soft);
          color: var(--amber);
        }

        .nav-badge.medication {
          background: var(--teal-soft);
          color: var(--teal);
        }

        .nav-badge.custody {
          background: var(--coral-soft);
          color: var(--coral);
        }

        .nav-stub {
          margin-top: auto;
          padding-top: 1rem;
          border-top: 1px solid var(--surface-2);
        }

        .stub-label {
          display: block;
          font-size: 0.5625rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--text-3);
          margin-bottom: 0.5rem;
        }

        .stub-preview {
          width: 100%;
          height: 100px;
          border-radius: var(--radius-sm);
          overflow: hidden;
          border: 1px solid var(--surface-2);
        }

        /* ⁸¹ Main content area */
        .profile-main {
          padding: 2rem 2.5rem;
          overflow-y: auto;
          scroll-behavior: smooth;
        }

        .profile-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 1.5rem;
          padding: 1.5rem 1.75rem;
          margin-bottom: 2rem;
          background: var(--surface-0);
          border-radius: var(--radius-lg);
          border: 1px solid var(--surface-2);
          box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
        }

        .header-identity {
          display: flex;
          align-items: center;
          gap: 1rem;
        }

        .header-photo,
        .header-avatar {
          width: 72px;
          height: 72px;
          border-radius: var(--radius-md);
          flex-shrink: 0;
        }

        .header-photo {
          object-fit: cover;
        }

        .header-avatar {
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--purple);
          color: white;
          font-weight: 600;
          font-size: 1.5rem;
        }

        .header-info {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .header-name-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1rem;
        }

        .header-field {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }

        .field-label {
          font-size: 0.625rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--text-3);
        }

        .header-meta {
          display: flex;
          gap: 1.25rem;
          margin-top: 0.375rem;
        }

        .meta-item {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.8125rem;
        }

        .meta-label {
          color: var(--text-3);
        }

        .meta-value {
          font-weight: 500;
          color: var(--text-1);
        }

        .meta-value.mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-size: 0.75rem;
        }

        .header-badges {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
          justify-content: flex-end;
        }

        .header-badge {
          padding: 0.25rem 0.625rem;
          font-size: 0.625rem;
          font-weight: 600;
          text-transform: uppercase;
          border-radius: var(--radius-sm);
        }

        .header-badge.active {
          background: var(--teal-soft);
          color: var(--teal);
        }

        .header-badge.inactive {
          background: var(--surface-2);
          color: var(--text-3);
        }

        .header-badge.iep {
          background: var(--purple-soft);
          color: var(--purple);
        }

        .header-badge.plan {
          background: var(--teal-soft);
          color: var(--teal);
        }

        .header-badge.allergy {
          background: var(--amber-soft);
          color: var(--amber);
        }

        .header-badge.medication {
          background: var(--teal-soft);
          color: var(--teal);
        }

        .header-badge.custody {
          background: var(--coral-soft);
          color: var(--coral);
        }

        /* ⁸² Sections container */
        .sections-container {
          display: flex;
          flex-direction: column;
          gap: 2rem;
        }

        /* ⁸³ Responsive layout */
        @media (max-width: 900px) {
          .profile-layout {
            grid-template-columns: 1fr;
          }

          .profile-nav {
            position: static;
            height: auto;
            flex-direction: row;
            flex-wrap: wrap;
            border-right: none;
            border-bottom: 1px solid var(--surface-2);
            padding: 1rem;
          }

          .nav-header {
            flex: 1;
            min-width: 200px;
            border-bottom: none;
            padding-bottom: 0;
          }

          .nav-sections {
            flex-direction: row;
            flex-wrap: wrap;
            flex: 1;
          }

          .nav-badges {
            border-top: none;
            padding-top: 0;
          }

          .nav-stub {
            display: none;
          }

          .profile-main {
            padding: 1rem;
          }
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EDIT FORMAT — Form layout for editing all sections
  // ═══════════════════════════════════════════════════════════════════════════════

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='profile-edit'>
        <h2 class='edit-section-title'>Identity</h2>
        <@fields.identity />

        <h2 class='edit-section-title'>Medical</h2>
        <@fields.medical />

        <h2 class='edit-section-title'>Family</h2>
        <@fields.family />

        <h2 class='edit-section-title'>Custody</h2>
        <@fields.custody />

        <h2 class='edit-section-title'>Financial</h2>
        <@fields.financial />

        <h2 class='edit-section-title'>IEP / 504</h2>
        <@fields.iep />

        <h2 class='edit-section-title'>Linked Student Stub</h2>
        <@fields.studentStub />
      </div>

      <style scoped>
        .profile-edit {
          padding: 1.5rem;
          font-family: 'Inter', var(--font-sans, system-ui, sans-serif);
          max-width: 800px;
        }
        .edit-section-title {
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #8a8279;
          margin: 1.5rem 0 0.75rem 0;
          padding-bottom: 0.375rem;
          border-bottom: 1px solid #ebe7e3;
        }
        .edit-section-title:first-child {
          margin-top: 0;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EMBEDDED FORMAT — Compact sensitive view
  // ═══════════════════════════════════════════════════════════════════════════════

  static embedded = class Embedded extends Component<typeof this> {
    // ⁸⁴
    <template>
      <div class='profile-embedded'>
        <div class='sensitive-indicator'>
          <svg
            width='14'
            height='14'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <rect x='3' y='11' width='18' height='11' rx='2' />
            <path d='M7 11V7a5 5 0 0 1 10 0v4' />
          </svg>
        </div>
        <div class='profile-avatar'>
          <div class='avatar-placeholder'>{{@model.initials}}</div>
        </div>
        <div class='profile-info'>
          <span class='profile-name'><@fields.identity.firstName /> <@fields.identity.lastName /></span>
          <span class='profile-id'><@fields.identity.studentId /></span>
        </div>
      </div>

      <style scoped>
        .profile-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.5rem;
          background: #fdf0ee;
          border: 1px solid #fbd5d0;
          border-radius: 10px;
          font-family: var(--font-sans, 'Inter', system-ui, sans-serif);
        }

        .sensitive-indicator {
          color: #e05d50;
        }

        .profile-avatar {
          width: 36px;
          height: 36px;
          flex-shrink: 0;
        }

        .profile-avatar img {
          width: 36px;
          height: 36px;
          border-radius: 8px;
          object-fit: cover;
        }

        .avatar-placeholder {
          width: 36px;
          height: 36px;
          background: #7c5fc4;
          color: white;
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .profile-info {
          flex: 1;
          min-width: 0;
        }

        .profile-name {
          display: block;
          font-weight: 500;
          color: #1a1816;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .profile-id {
          display: block;
          font-size: 0.75rem;
          color: #8a8279;
          font-family: var(--font-mono, ui-monospace, monospace);
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // FITTED FORMAT — Minimal sensitive indicator
  // ═══════════════════════════════════════════════════════════════════════════════

  static fitted = class Fitted extends Component<typeof this> {
    // ⁸⁵
    <template>
      <div class='profile-fitted'>
        <svg
          class='fitted-lock'
          width='16'
          height='16'
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='2'
        >
          <rect x='3' y='11' width='18' height='11' rx='2' />
          <path d='M7 11V7a5 5 0 0 1 10 0v4' />
        </svg>
        <div class='fitted-avatar'>
          <div class='avatar-placeholder'>{{@model.initials}}</div>
        </div>
        <span class='fitted-name'><@fields.identity.firstName /> <@fields.identity.lastName /></span>
        <span class='fitted-label'>Full Profile</span>
      </div>

      <style scoped>
        .profile-fitted {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          padding: 0.75rem;
          background: linear-gradient(135deg, #fdf0ee 0%, #fffdfb 100%);
          border: 1px solid #fbd5d0;
          text-align: center;
          font-family: var(--font-sans, 'Inter', system-ui, sans-serif);
        }

        .fitted-lock {
          color: #e05d50;
          margin-bottom: 0.375rem;
        }

        .fitted-avatar {
          width: 44px;
          height: 44px;
          margin-bottom: 0.375rem;
        }

        .fitted-avatar img {
          width: 44px;
          height: 44px;
          border-radius: 10px;
          object-fit: cover;
        }

        .avatar-placeholder {
          width: 44px;
          height: 44px;
          background: #7c5fc4;
          color: white;
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.875rem;
          font-weight: 600;
        }

        .fitted-name {
          font-size: 0.8125rem;
          font-weight: 500;
          color: #1a1816;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 100%;
        }

        .fitted-label {
          font-size: 0.625rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #e05d50;
          margin-top: 0.125rem;
        }
      </style>
    </template>
  };
}


