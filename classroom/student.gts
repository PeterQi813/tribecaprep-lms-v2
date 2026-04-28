// Combined Hero + Student — Merged Student (Operational Stub)
// tribecaprep base model + hero operational fields (location, schedule, alerts, supportStaff)
// + compatibility computed fields for hero dashboard templates

import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';

import { GradeLevel } from './enums';
import {
  StudentTag,
  LocationStatus,
  TribecaPrepCardInfo,
} from './shared-fields';
import { ParentInfo } from './lms-fields';
import { Staff } from './staff';
import { ScheduleItem } from './schedule-item';

import { StudentFullProfile } from './student-full-profile';

// ═══════════════════════════════════════════════════════════════════════════════
// STUDENT CARD — Merged Operational Stub
// ═══════════════════════════════════════════════════════════════════════════════

export class Student extends CardDef {
  static displayName = 'Student';

  @field cardInfo = contains(TribecaPrepCardInfo);

  // ─── LINKED FULL PROFILE ───
  @field fullProfile = linksTo(() => StudentFullProfile);

  // ─── IDENTITY (stored directly — fetched from HoS full profile) ───
  @field studentId = contains(StringField);
  @field firstName = contains(StringField);
  @field lastName = contains(StringField);
  @field preferredName = contains(StringField);
  @field dateOfBirth = contains(StringField);
  @field active = contains(BooleanField);

  // ─── STORED FIELDS (Student-only) ───
  @field gradeLevel = contains(GradeLevel);
  @field photoUrl = contains(StringField);

  // ─── OPERATIONAL (tribecaprep) ───
  @field currentLocation = contains(LocationStatus);

  // ─── FLAGS (stored — fetched from HoS full profile) ───
  @field hasIEP = contains(BooleanField);
  @field has504 = contains(BooleanField);
  @field hasAllergy = contains(BooleanField);
  @field hasMedication = contains(BooleanField);
  @field hasCustodyAlert = contains(BooleanField);

  // ─── VISUAL TAGS (tribecaprep — rich objects) ───
  @field tags = containsMany(StudentTag);

  // ─── FAMILY & CONTACTS (tribecaprep) ───
  @field primaryParent = contains(ParentInfo);
  @field secondaryParent = contains(ParentInfo);
  @field emergencyContacts = containsMany(ParentInfo);

  // ─── STAFFING (tribecaprep) ───
  @field staffingRatio = contains(NumberField);

  // ─── HERO OPERATIONAL FIELDS ───
  @field location = contains(StringField);       // 'In Classroom' | 'At Specialists' | 'Absent'
  @field locationDetail = contains(StringField);
  @field returnTime = contains(StringField);
  @field supportStaff = linksTo(Staff);
  @field schedule = containsMany(ScheduleItem);


  // ─── COMPUTED (tribecaprep) ───
  @field displayName = contains(StringField, {
    computeVia: function (this: Student) {
      const name = this.preferredName || this.firstName || '';
      const lastInitial = this.lastName ? this.lastName.charAt(0) + '.' : '';
      return `${name} ${lastInitial}`.trim() || 'Unknown Student';
    },
  });

  @field fullName = contains(StringField, {
    computeVia: function (this: Student) {
      return (
        `${this.firstName || ''} ${this.lastName || ''}`.trim() ||
        'Unknown Student'
      );
    },
  });

  @field initials = contains(StringField, {
    computeVia: function (this: Student) {
      const first = (this.firstName || '').charAt(0).toUpperCase();
      const last = (this.lastName || '').charAt(0).toUpperCase();
      return `${first}${last}` || '??';
    },
  });

  @field tagSummary = contains(StringField, {
    computeVia: function (this: Student) {
      const icons: string[] = [];
      if (this.hasIEP) icons.push('IEP');
      if (this.has504) icons.push('504');
      if (this.hasAllergy) icons.push('Allergy');
      if (this.hasMedication) icons.push('Meds');
      if (this.hasCustodyAlert) icons.push('Custody');
      return icons.join(' · ');
    },
  });

  @field sortName = contains(StringField, {
    computeVia: function (this: Student) {
      return `${this.lastName || ''}, ${this.firstName || ''}`.trim();
    },
  });

  @field age = contains(NumberField, {
    computeVia: function (this: Student) {
      if (!this.dateOfBirth) return 0;
      const dob = new Date(this.dateOfBirth);
      const now = new Date();
      let age = now.getFullYear() - dob.getFullYear();
      const m = now.getMonth() - dob.getMonth();
      if (m < 0 || (m === 0 && now.getDate() < dob.getDate())) age--;
      return age;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullName || 'Student';
    },
  });

  // ─── COMPATIBILITY COMPUTED FIELDS (hero templates use these) ───
  @field name = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullName || 'Unknown Student';
    },
  });

  @field shortName = contains(StringField, {
    computeVia: function (this: Student) {
      return this.displayName || 'Unknown';
    },
  });

  @field grade = contains(StringField, {
    computeVia: function (this: Student) {
      const val = this.gradeLevel?.value;
      return val ? `${val} Grade` : '';
    },
  });

  @field avatar = contains(StringField, {
    computeVia: function (this: Student) {
      return this.photoUrl || '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullName || 'Unnamed Student';
    },
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // ISOLATED FORMAT — Full student view
  // ═══════════════════════════════════════════════════════════════════════════════

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='student-isolated'>
        <header class='student-header'>
          <div class='student-avatar'>
            {{#if @model.photoUrl}}
              <img
                src={{@model.photoUrl}}
                alt={{@model.displayName}}
                class='photo'
              />
            {{else}}
              <div class='avatar-placeholder'>
                <span class='avatar-initials'>{{@model.initials}}</span>
              </div>
            {{/if}}
          </div>

          <div class='student-identity'>
            <div class='name-fields'>
              <div class='field-col'><span class='field-label'>First Name</span><@fields.firstName /></div>
              <div class='field-col'><span class='field-label'>Last Name</span><@fields.lastName /></div>
            </div>
            <div class='field-col'><span class='field-label'>Preferred Name</span><@fields.preferredName /></div>
            <div class='meta-fields'>
              <div class='field-col'><span class='field-label'>Grade</span><@fields.gradeLevel /></div>
              <div class='field-col'><span class='field-label'>Student ID</span><@fields.studentId /></div>
              <div class='field-col'><span class='field-label'>Date of Birth</span><@fields.dateOfBirth /></div>
            </div>
          </div>
        </header>

        <section class='student-section'>
          <h2 class='section-label'>Photo & Status</h2>
          <div class='fields-row'>
            <div class='field-col'><span class='field-label'>Photo URL</span><@fields.photoUrl /></div>
            <div class='field-col'><span class='field-label'>Active</span><@fields.active /></div>
            <div class='field-col'><span class='field-label'>Staffing Ratio</span><@fields.staffingRatio /></div>
          </div>
        </section>

        <section class='student-section'>
          <h2 class='section-label'>Location & Schedule</h2>
          <div class='fields-row'>
            <div class='field-col'><span class='field-label'>Location</span><@fields.location /></div>
            <div class='field-col'><span class='field-label'>Detail</span><@fields.locationDetail /></div>
            <div class='field-col'><span class='field-label'>Return Time</span><@fields.returnTime /></div>
          </div>
          {{#if @model.supportStaff}}
            <div class='field-col'><span class='field-label'>Support Staff</span><@fields.supportStaff @format='embedded' /></div>
          {{/if}}
        </section>

        <section class='student-section'>
          <h2 class='section-label'>Flags</h2>
          <div class='flags-grid'>
            <div class='field-col'><span class='field-label'>IEP</span><@fields.hasIEP /></div>
            <div class='field-col'><span class='field-label'>504 Plan</span><@fields.has504 /></div>
            <div class='field-col'><span class='field-label'>Allergy</span><@fields.hasAllergy /></div>
            <div class='field-col'><span class='field-label'>Medication</span><@fields.hasMedication /></div>
            <div class='field-col'><span class='field-label'>Custody Alert</span><@fields.hasCustodyAlert /></div>
          </div>
        </section>

        <section class='student-section'>
          <h2 class='section-label'>Tags</h2>
          <@fields.tags @format='embedded' />
        </section>

        {{#if @model.schedule.length}}
          <section class='student-section'>
            <h2 class='section-label'>Schedule</h2>
            <@fields.schedule />
          </section>
        {{/if}}


        <section class='student-section'>
          <h2 class='section-label'>Primary Parent</h2>
          <@fields.primaryParent @format='embedded' />
        </section>

        <section class='student-section'>
          <h2 class='section-label'>Secondary Parent</h2>
          <@fields.secondaryParent @format='embedded' />
        </section>

        <section class='student-section'>
          <h2 class='section-label'>Emergency Contacts</h2>
          <@fields.emergencyContacts @format='embedded' />
        </section>
      </article>

      <style scoped>
        .student-isolated {
          max-width: 800px;
          margin: 0 auto;
          padding: 1.5rem;
          font-family: var(--font-sans, 'Plus Jakarta Sans', system-ui, sans-serif);
          color: var(--foreground, #000);
          background: var(--background, #fff);
        }

        .student-header {
          display: flex;
          gap: 1.5rem;
          align-items: flex-start;
          padding-bottom: 1.5rem;
          border-bottom: 1px solid var(--border, #e2e8f0);
          margin-bottom: 1.5rem;
        }

        .student-avatar {
          width: 80px;
          height: 80px;
          flex-shrink: 0;
        }
        .student-avatar .photo {
          width: 80px;
          height: 80px;
          border-radius: 0.625rem;
          object-fit: cover;
        }
        .avatar-placeholder {
          width: 80px;
          height: 80px;
          background: var(--secondary, #a278ff);
          border-radius: 0.625rem;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-initials {
          color: #fff;
          font-size: 1.5rem;
          font-weight: 600;
        }

        .student-identity {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        .name-fields {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1rem;
        }

        .meta-fields {
          display: grid;
          grid-template-columns: auto auto 1fr;
          gap: 1rem;
        }

        .student-section {
          margin-bottom: 1.5rem;
          padding: 1rem;
          background: var(--muted, #f8f8f8);
          border-radius: 0.625rem;
        }

        .section-label {
          font-size: 0.6875rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground, #6c6a81);
          margin: 0 0 0.75rem 0;
        }

        .fields-row {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
          gap: 1rem;
        }

        .flags-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
          gap: 0.75rem;
        }

        .field-col {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .field-label {
          font-size: 0.625rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--muted-foreground, #8a8279);
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EMBEDDED FORMAT — Compact card for lists (hero-compatible)
  // ═══════════════════════════════════════════════════════════════════════════════

  static embedded = class Embedded extends Component<typeof this> {
    get safeName() {
      return this.args.model?.shortName ?? this.args.model?.name ?? 'Unknown';
    }

    get safeAvatar() {
      return this.args.model?.avatar ?? '';
    }

    get safeTags() {
      return this.args.model?.tags ?? [];
    }

    get safeLocation() {
      return this.args.model?.location ?? 'In Classroom';
    }

    get locationColor() {
      switch (this.safeLocation) {
        case 'In Classroom': return '#2a9d8f';
        case 'At Specialists': return '#c08b30';
        case 'Absent': return '#e05d50';
        default: return '#8a8279';
      }
    }

    get staffInitials() {
      return this.args.model?.supportStaff?.initials ?? null;
    }

    get staffColor() {
      switch (this.args.model?.supportStaff?.color) {
        case 'coral': return '#e05d50';
        case 'teal': return '#2a9d8f';
        case 'purple': return '#7c5fc4';
        case 'amber': return '#c08b30';
        default: return '#5c5650';
      }
    }

    <template>
      <div class='student-embedded'>
        <div class='avatar-wrapper'>
          {{#if this.safeAvatar}}
            <img src={{this.safeAvatar}} alt='{{this.safeName}}' />
          {{else}}
            <div class='avatar-placeholder'>
              <span class='avatar-initials'>{{@model.initials}}</span>
            </div>
          {{/if}}
          <span class='status-dot' style='background-color: {{this.locationColor}}'></span>
        </div>
        <div class='info'>
          <div class='name'>{{this.safeName}}</div>
          <div class='badges'>
            {{#each this.safeTags as |tag|}}
              <span class='tag'>{{tag.label}}</span>
            {{/each}}
          </div>
        </div>
        {{#if this.staffInitials}}
          <div class='staff-mini' style='background-color: {{this.staffColor}}'>
            {{this.staffInitials}}
          </div>
        {{/if}}
      </div>

      <style scoped>
        .student-embedded {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem;
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          height: 100%;
        }

        .avatar-wrapper {
          position: relative;
          flex-shrink: 0;
          width: 2.25rem;
          height: 2.25rem;
        }

        .avatar-wrapper img {
          width: 100%;
          height: 100%;
          border-radius: 50%;
          object-fit: cover;
        }

        .avatar-placeholder {
          width: 100%;
          height: 100%;
          background: linear-gradient(135deg, #e8e4f0 0%, #d4cce8 100%);
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-initials {
          color: var(--secondary, #a278ff);
          font-size: 0.75rem;
          font-weight: 700;
        }

        .status-dot {
          position: absolute;
          bottom: -1px;
          right: -1px;
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 50%;
          border: 2px solid var(--card);
        }

        .info {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }

        .name {
          font-weight: 700;
          font-size: 0.8125rem;
          color: var(--card-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .badges {
          display: flex;
          gap: 0.25rem;
        }

        .tag {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.0625rem 0.3125rem;
          border-radius: 3px;
          background: rgba(224, 93, 80, 0.1);
          color: #e05d50;
        }

        .staff-mini {
          flex-shrink: 0;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 0.5rem;
          font-weight: 700;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // FITTED FORMAT — Compact tile for grids/rosters
  // ═══════════════════════════════════════════════════════════════════════════════

  static fitted = class Fitted extends Component<typeof this> {
    get safeName() {
      return this.args.model?.shortName ?? this.args.model?.name ?? 'Unknown';
    }

    get safeAvatar() {
      return this.args.model?.avatar ?? '';
    }

    get safeLocation() {
      return this.args.model?.location ?? 'In Classroom';
    }

    get locationColor() {
      switch (this.safeLocation) {
        case 'In Classroom': return '#2a9d8f';
        case 'At Specialists': return '#c08b30';
        case 'Absent': return '#e05d50';
        default: return '#8a8279';
      }
    }

    <template>
      <div class='fitted-container'>
        <div class='tile'>
          <div class='avatar-fitted'>
            {{#if this.safeAvatar}}
              <img src={{this.safeAvatar}} alt='{{this.safeName}}' />
            {{else}}
              <div class='avatar-placeholder'>
                <span class='avatar-initials'>{{@model.initials}}</span>
              </div>
            {{/if}}
          </div>
          <div class='fitted-name'>{{this.safeName}}</div>
          <span class='location-dot' style='background-color: {{this.locationColor}}'></span>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          container-type: size;
          width: 100%;
          height: 100%;
        }

        .tile {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          height: 100%;
        }

        .avatar-fitted {
          width: 4rem;
          height: 4rem;
          border-radius: 50%;
          overflow: hidden;
        }

        .avatar-fitted img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .avatar-placeholder {
          width: 100%;
          height: 100%;
          background: linear-gradient(135deg, #e8e4f0 0%, #d4cce8 100%);
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-initials {
          color: var(--secondary, #a278ff);
          font-size: 1.25rem;
          font-weight: 700;
        }

        .fitted-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          color: var(--card-foreground);
          text-align: center;
        }

        .location-dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EDIT FORMAT
  // ═══════════════════════════════════════════════════════════════════════════════

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='student-edit'>
        <h2 class='edit-section-title'>Linked Full Profile</h2>
        <@fields.fullProfile />

        <h2 class='edit-section-title'>Identity (synced from Full Profile)</h2>
        <div class='synced-notice'>These fields update automatically from the linked Full Profile.</div>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>First Name</label><@fields.firstName /></div>
          <div class='edit-field'><label class='edit-label'>Last Name</label><@fields.lastName /></div>
        </div>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>Preferred Name</label><@fields.preferredName /></div>
          <div class='edit-field'><label class='edit-label'>Student ID</label><@fields.studentId /></div>
        </div>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>Date of Birth</label><@fields.dateOfBirth /></div>
          <div class='edit-field'><label class='edit-label'>Active</label><@fields.active /></div>
        </div>

        <h2 class='edit-section-title'>Student-Specific Fields</h2>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>Grade Level</label><@fields.gradeLevel /></div>
          <div class='edit-field'><label class='edit-label'>Photo URL</label><@fields.photoUrl /></div>
        </div>

        <h2 class='edit-section-title'>Location & Schedule</h2>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>Location</label><@fields.location /></div>
          <div class='edit-field'><label class='edit-label'>Detail</label><@fields.locationDetail /></div>
          <div class='edit-field'><label class='edit-label'>Return Time</label><@fields.returnTime /></div>
        </div>
        <div class='edit-field'><label class='edit-label'>Support Staff</label><@fields.supportStaff /></div>
        <div class='edit-field'><label class='edit-label'>Schedule</label><@fields.schedule /></div>


        <h2 class='edit-section-title'>Flags (synced from Full Profile)</h2>
        <div class='synced-notice'>These flags update automatically from the linked Full Profile.</div>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>IEP</label><@fields.hasIEP /></div>
          <div class='edit-field'><label class='edit-label'>504 Plan</label><@fields.has504 /></div>
          <div class='edit-field'><label class='edit-label'>Allergy</label><@fields.hasAllergy /></div>
        </div>
        <div class='edit-row'>
          <div class='edit-field'><label class='edit-label'>Medication</label><@fields.hasMedication /></div>
          <div class='edit-field'><label class='edit-label'>Custody Alert</label><@fields.hasCustodyAlert /></div>
        </div>

        <h2 class='edit-section-title'>Tags</h2>
        <@fields.tags />

        <h2 class='edit-section-title'>Staffing</h2>
        <div class='edit-field'><label class='edit-label'>Staffing Ratio</label><@fields.staffingRatio /></div>

        <h2 class='edit-section-title'>Primary Parent</h2>
        <@fields.primaryParent />

        <h2 class='edit-section-title'>Secondary Parent</h2>
        <@fields.secondaryParent />

        <h2 class='edit-section-title'>Emergency Contacts</h2>
        <@fields.emergencyContacts />
      </div>

      <style scoped>
        .student-edit {
          padding: 1.5rem;
          font-family: var(--font-sans, 'Plus Jakarta Sans', system-ui, sans-serif);
          max-width: 700px;
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
        .synced-notice {
          font-size: 0.6875rem;
          color: #2a9d8f;
          font-style: italic;
          margin-bottom: 0.75rem;
        }
        .edit-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 1rem;
          margin-bottom: 0.75rem;
        }
        .edit-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .edit-label {
          font-size: 0.6875rem;
          font-weight: 500;
          color: #5c5650;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // ATOM FORMAT
  // ═══════════════════════════════════════════════════════════════════════════════

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='student-atom'>
        <span class='atom-avatar'>
          {{#if @model.photoUrl}}
            <img src={{@model.photoUrl}} alt='' class='atom-photo' />
          {{else}}
            <span class='atom-initials'>{{@model.initials}}</span>
          {{/if}}
        </span>
        <span class='atom-name'><@fields.firstName /> <@fields.lastName /></span>
      </span>

      <style scoped>
        .student-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          padding: 0.125rem 0.375rem 0.125rem 0.125rem;
          background: #f4f0fa;
          border-radius: 4px;
          font-family: var(--font-sans, 'Inter', system-ui, sans-serif);
          vertical-align: baseline;
        }
        .atom-avatar {
          width: 18px;
          height: 18px;
          border-radius: 4px;
          overflow: hidden;
          flex-shrink: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          background: #7c5fc4;
        }
        .atom-photo {
          width: 18px;
          height: 18px;
          object-fit: cover;
        }
        .atom-initials {
          color: white;
          font-size: 0.5rem;
          font-weight: 700;
        }
        .atom-name {
          font-size: 0.8125rem;
          font-weight: 500;
          color: #7c5fc4;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

// touched for re-index
