// Tribeca Prep LMS — Student (Operational Stub)
// The projection/stub visible to teaching staff
// Full profile lives in Sensitive Realm — this shows only what's needed daily

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
import { StudentFullProfile } from './student-full-profile';

// ═══════════════════════════════════════════════════════════════════════════════
// STUDENT CARD — Operational Stub/Projection
// ═══════════════════════════════════════════════════════════════════════════════

export class Student extends CardDef {
  static displayName = 'Student';

  @field cardInfo = contains(TribecaPrepCardInfo);

  // ─── LINKED FULL PROFILE ───
  // Arrow function defers resolution, breaking circular import with student-full-profile.gts
  @field fullProfile = linksTo(() => StudentFullProfile);

  // ─── IDENTITY (computed from fullProfile) ───
  @field studentId = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.studentId ?? '';
    },
  });
  @field firstName = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.firstName ?? '';
    },
  });
  @field lastName = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.lastName ?? '';
    },
  });
  @field preferredName = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.preferredName ?? '';
    },
  });
  @field dateOfBirth = contains(StringField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.dateOfBirth ?? '';
    },
  });
  @field active = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.identity?.active ?? false;
    },
  });

  // ─── STORED FIELDS (Student-only) ───
  @field gradeLevel = contains(GradeLevel);
  @field photoUrl = contains(StringField);

  // ─── OPERATIONAL ───
  @field currentLocation = contains(LocationStatus);

  // ─── FLAGS (computed from fullProfile sections) ───
  @field hasIEP = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.iep?.hasIEP ?? false;
    },
  });
  @field has504 = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.iep?.has504 ?? false;
    },
  });
  @field hasAllergy = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.medical?.hasAllergy ?? false;
    },
  });
  @field hasMedication = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.medical?.hasMedication ?? false;
    },
  });
  @field hasCustodyAlert = contains(BooleanField, {
    computeVia: function (this: Student) {
      return this.fullProfile?.custody?.hasCustodyAlert ?? false;
    },
  });

  // ─── VISUAL TAGS ───
  @field tags = containsMany(StudentTag);

  // ─── FAMILY & CONTACTS ───
  @field primaryParent = contains(ParentInfo);
  @field secondaryParent = contains(ParentInfo);
  @field emergencyContacts = containsMany(ParentInfo);

  // ─── STAFFING ───
  @field staffingRatio = contains(NumberField);

  // ─── COMPUTED ───
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

  // ═══════════════════════════════════════════════════════════════════════════════
  // ISOLATED FORMAT — Full student view (all fields editable)
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
          <h2 class='section-label'>Current Location</h2>
          <@fields.currentLocation />
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
  // EMBEDDED FORMAT — Compact card for lists
  // ═══════════════════════════════════════════════════════════════════════════════

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='student-embedded'>
        <div class='avatar-wrapper'>
          {{#if @model.photoUrl}}
            <img
              src={{@model.photoUrl}}
              alt={{@model.displayName}}
              class='avatar-img'
            />
          {{else}}
            <div class='avatar-placeholder'>
              <span class='avatar-initials'>{{@model.initials}}</span>
            </div>
          {{/if}}
        </div>

        <div class='student-info'>
          <div class='info-row'>
            <span class='field-label'>Name</span>
            <div class='name-inline'><@fields.firstName /> <@fields.lastName /></div>
          </div>
          <div class='info-row'>
            <span class='field-label'>Grade</span>
            <@fields.gradeLevel />
          </div>
          <div class='flags-row'>
            <div class='flag-item'><span class='flag-label'>IEP</span><@fields.hasIEP /></div>
            <div class='flag-item'><span class='flag-label'>504</span><@fields.has504 /></div>
            <div class='flag-item'><span class='flag-label'>Allergy</span><@fields.hasAllergy /></div>
            <div class='flag-item'><span class='flag-label'>Meds</span><@fields.hasMedication /></div>
            <div class='flag-item'><span class='flag-label'>Custody</span><@fields.hasCustodyAlert /></div>
          </div>
        </div>
      </div>

      <style scoped>
        .student-embedded {
          display: flex;
          align-items: flex-start;
          gap: 0.875rem;
          padding: 0.875rem;
          font-family: var(--font-sans, 'Plus Jakarta Sans', system-ui, sans-serif);
          background: var(--card, #fff);
          border-radius: 0.625rem;
        }

        .avatar-wrapper {
          width: 48px;
          height: 48px;
          flex-shrink: 0;
        }
        .avatar-img {
          width: 48px;
          height: 48px;
          border-radius: 10px;
          object-fit: cover;
        }
        .avatar-placeholder {
          width: 48px;
          height: 48px;
          background: linear-gradient(135deg, #e8e4f0 0%, #d4cce8 100%);
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-initials {
          color: var(--secondary, #a278ff);
          font-size: 1.125rem;
          font-weight: 700;
        }

        .student-info {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
        }

        .info-row {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }

        .name-inline {
          font-size: 0.9375rem;
          font-weight: 600;
          color: var(--foreground, #1a1816);
        }

        .field-label {
          font-size: 0.5625rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #8a8279;
        }

        .flags-row {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          margin-top: 0.25rem;
        }

        .flag-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.125rem;
        }

        .flag-label {
          font-size: 0.5rem;
          font-weight: 500;
          text-transform: uppercase;
          color: #8a8279;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // FITTED FORMAT — Compact tile for grids/rosters
  // ═══════════════════════════════════════════════════════════════════════════════

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='student-fitted'>
        <div class='avatar-wrapper'>
          {{#if @model.photoUrl}}
            <img
              src={{@model.photoUrl}}
              alt={{@model.displayName}}
              class='avatar-img'
            />
          {{else}}
            <div class='avatar-placeholder'>
              <span class='avatar-initials'>{{@model.initials}}</span>
            </div>
          {{/if}}
        </div>

        <div class='fitted-content'>
          <div class='name-inline'><@fields.firstName /> <@fields.lastName /></div>
          <div class='fitted-meta'>
            <@fields.gradeLevel />
          </div>
        </div>
      </div>

      <style scoped>
        .student-fitted {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.5rem 0.75rem;
          height: 100%;
          width: 100%;
          font-family: var(--font-sans, 'Plus Jakarta Sans', system-ui, sans-serif);
          background: var(--card, #fff);
          box-sizing: border-box;
        }

        .avatar-wrapper {
          width: 36px;
          height: 36px;
          flex-shrink: 0;
        }
        .avatar-img {
          width: 36px;
          height: 36px;
          border-radius: 8px;
          object-fit: cover;
        }
        .avatar-placeholder {
          width: 36px;
          height: 36px;
          background: linear-gradient(135deg, #e8e4f0 0%, #d4cce8 100%);
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-initials {
          color: var(--secondary, #a278ff);
          font-size: 0.875rem;
          font-weight: 700;
        }

        .fitted-content {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }

        .name-inline {
          font-size: 0.8125rem;
          font-weight: 600;
          color: var(--foreground, #1a1816);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .fitted-meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground, #5c5650);
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EDIT FORMAT — Form layout for editing all fields
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

        <h2 class='edit-section-title'>Current Location</h2>
        <@fields.currentLocation />

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
  // ATOM FORMAT — Inline mention for rich text
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
