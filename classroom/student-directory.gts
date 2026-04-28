// Tribeca Prep LMS — Student Directory
// Browse and search all students — AppCard style, queries Student cards

import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { Student } from './student';
import { TribecaPrepCardInfo } from './shared-fields';

// ═══════════════════════════════════════════════════════════════════════════════
// STUDENT DIRECTORY — Browse & Search AppCard
// ═══════════════════════════════════════════════════════════════════════════════

export class StudentDirectory extends CardDef {
  static displayName = 'Student Directory';
  static prefersWideFormat = true;

  // ─── CARD INFO ─── // ²⁶ Use TribecaPrepCardInfo for org branding
  @field cardInfo = contains(TribecaPrepCardInfo);

  // ─── STUDENTS (query-backed: auto-fetches all Students in realm) ─── // ⁷
  @field students = linksToMany(() => Student, {
    query: {
      filter: {
        type: {
          module: `${new URL('./student', import.meta.url).href}`,
          name: 'Student',
        },
      },
      sort: [
        { by: 'lastName', direction: 'asc' },
        { by: 'firstName', direction: 'asc' },
      ],
    },
  });

  // ─── COMPUTED ───
  @field studentCount = contains(NumberField, {
    computeVia: function (this: StudentDirectory) {
      return this.students?.length ?? 0;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: StudentDirectory) {
      return 'Student Directory';
    },
  });

  // ═══════════════════════════════════════════════════════════════════════════════
  // ISOLATED FORMAT — Full directory with search and grid
  // ═══════════════════════════════════════════════════════════════════════════════

  static isolated = class Isolated extends Component<typeof this> {
    // ⁸ Tracked filter state (client-side only, not persisted)
    @tracked searchQuery = '';
    @tracked filterGrade = '';
    @tracked filterActiveOnly = true;

    // ⁹ Filtered students getter — filters the query results
    get filteredStudents() {
      let students = this.args.model?.students ?? [];

      // Filter by search query
      if (this.searchQuery) {
        const query = this.searchQuery.toLowerCase();
        students = students.filter(
          (s) =>
            s.firstName?.toLowerCase().includes(query) ||
            s.lastName?.toLowerCase().includes(query) ||
            s.studentId?.toLowerCase().includes(query),
        );
      }

      // Filter by grade
      if (this.filterGrade) {
        students = students.filter(
          (s) => s.gradeLevel?.value === this.filterGrade,
        );
      }

      // Filter by active status
      if (this.filterActiveOnly) {
        students = students.filter((s) => s.active);
      }

      return students;
    }

    get filteredCount() {
      return this.filteredStudents.length;
    }

    // ¹⁰ Event handlers (fat arrow for proper binding)
    updateSearch = (event: Event) => {
      this.searchQuery = (event.target as HTMLInputElement).value;
    };

    updateGradeFilter = (event: Event) => {
      this.filterGrade = (event.target as HTMLSelectElement).value;
    };

    toggleActiveFilter = (event: Event) => {
      this.filterActiveOnly = (event.target as HTMLInputElement).checked;
    };

    // ¹⁴ Navigate to student card using viewCard API
    viewStudent = (student: Student) => {
      this.args.viewCard(student, 'isolated');
    };

    <template>
      <article class='directory'>
        <header class='directory-header'>
          <div class='header-title'>
            <h1 class='title'>Student Directory</h1>
            <span class='count'>{{this.filteredCount}}
              of
              {{@model.studentCount}}
              students</span>
          </div>
          <button class='add-btn' type='button'>
            <span class='add-icon'>+</span>
            Add Student
          </button>
        </header>

        <div class='directory-filters'>
          <div class='search-box'>
            <svg
              class='search-icon'
              width='16'
              height='16'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            >
              <circle cx='11' cy='11' r='8' />
              <path d='m21 21-4.35-4.35' />
            </svg>
            <input
              type='text'
              class='search-input'
              placeholder='Search students...'
              value={{this.searchQuery}}
              {{on 'input' this.updateSearch}}
            />
          </div>
          <div class='filter-group'>
            <select
              class='filter-select'
              {{on 'change' this.updateGradeFilter}}
            >
              <option value=''>All Grades</option>
              <option value='Pre-K'>Pre-K</option>
              <option value='K'>K</option>
              <option value='1st'>1st</option>
              <option value='2nd'>2nd</option>
              <option value='3rd'>3rd</option>
              <option value='4th'>4th</option>
              <option value='5th'>5th</option>
            </select>
            <label class='filter-toggle'>
              <input
                type='checkbox'
                checked={{this.filterActiveOnly}}
                {{on 'change' this.toggleActiveFilter}}
              />
              <span>Active only</span>
            </label>
          </div>
        </div>

        <div class='directory-grid'>
          {{#each this.filteredStudents as |student|}}
            <div
              class='student-card'
              role='button'
              tabindex='0'
              {{on 'click' (fn this.viewStudent student)}}
            >
              <div class='sc-avatar'>
                {{#if student.photoUrl}}
                  <img src={{student.photoUrl}} alt={{student.displayName}} />
                {{else}}
                  <div class='avatar-placeholder'>
                    <span>{{student.initials}}</span>
                  </div>
                {{/if}}
                {{#if student.active}}
                  <span class='sc-status active'></span>
                {{/if}}
              </div>
              <div class='sc-info'>
                <span class='sc-name'>{{student.displayName}}</span>
                <span class='sc-meta'>
                  {{#if student.gradeLevel}}
                    {{student.gradeLevel.value}}
                  {{/if}}
                </span>
              </div>
              <div class='sc-tags'>
                {{#if student.hasIEP}}
                  <span class='sc-tag' title='IEP'>
                    <svg
                      width='12'
                      height='12'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path
                        d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'
                      />
                      <polyline points='14 2 14 8 20 8' />
                      <line x1='16' y1='13' x2='8' y2='13' />
                      <line x1='16' y1='17' x2='8' y2='17' />
                    </svg>
                  </span>
                {{/if}}
                {{#if student.hasAllergy}}
                  <span class='sc-tag allergy' title='Allergy'>
                    <svg
                      width='12'
                      height='12'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path
                        d='m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z'
                      />
                      <line x1='12' y1='9' x2='12' y2='13' />
                      <line x1='12' y1='17' x2='12.01' y2='17' />
                    </svg>
                  </span>
                {{/if}}
                {{#if student.hasMedication}}
                  <span class='sc-tag' title='Medication'>
                    <svg
                      width='12'
                      height='12'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <path
                        d='m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7Z'
                      />
                      <path d='m8.5 8.5 7 7' />
                    </svg>
                  </span>
                {{/if}}
                {{#if student.hasCustodyAlert}}
                  <span class='sc-tag custody' title='Custody Alert'>
                    <svg
                      width='12'
                      height='12'
                      viewBox='0 0 24 24'
                      fill='none'
                      stroke='currentColor'
                      stroke-width='2'
                    >
                      <circle cx='12' cy='12' r='10' />
                      <line x1='12' y1='8' x2='12' y2='12' />
                      <line x1='12' y1='16' x2='12.01' y2='16' />
                    </svg>
                  </span>
                {{/if}}
              </div>
            </div>
          {{else}}
            <div class='empty-state'>
              <svg
                class='empty-icon'
                width='48'
                height='48'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
              >
                <path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' />
                <circle cx='9' cy='7' r='4' />
                <path d='M23 21v-2a4 4 0 0 0-3-3.87' />
                <path d='M16 3.13a4 4 0 0 1 0 7.75' />
              </svg>
              <span class='empty-text'>No students found</span>
              <span class='empty-hint'>Add students or adjust your filters</span>
            </div>
          {{/each}}
        </div>
      </article>

      <style scoped>
        /* ¹¹ Base styles */
        .directory {
          min-height: 100%;
          font-family: var(
            --font-sans,
            'Plus Jakarta Sans',
            system-ui,
            sans-serif
          );
          color: var(--foreground, #000);
          background: var(--background, #fff);
        }

        .directory-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 1.5rem 2rem;
          border-bottom: 1px solid var(--border, #e2e8f0);
        }
        .header-title {
          display: flex;
          align-items: baseline;
          gap: 0.75rem;
        }
        .title {
          margin: 0;
          font-size: 1.5rem;
          font-weight: 600;
        }
        .count {
          font-size: 0.875rem;
          color: var(--muted-foreground, #6c6a81);
        }
        .add-btn {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.625rem 1rem;
          background: var(--primary, #ff2c4e);
          color: var(--primary-foreground, #fff);
          border: none;
          border-radius: var(--radius, 0.625rem);
          font-size: 0.875rem;
          font-weight: 500;
          cursor: pointer;
          transition: opacity 0.15s;
        }
        .add-btn:hover {
          opacity: 0.9;
        }
        .add-icon {
          font-size: 1.125rem;
          font-weight: 300;
        }

        .directory-filters {
          display: flex;
          gap: 1rem;
          padding: 1rem 2rem;
          background: var(--muted, #f0f0f2);
          border-bottom: 1px solid var(--border, #e2e8f0);
        }
        .search-box {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex: 1;
          max-width: 320px;
          padding: 0.5rem 0.75rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e2e8f0);
          border-radius: var(--radius, 0.625rem);
        }
        .search-icon {
          opacity: 0.5;
          flex-shrink: 0;
        }
        .search-input {
          flex: 1;
          border: none;
          background: transparent;
          font-size: 0.875rem;
          color: var(--foreground, #000);
        }
        .search-input:focus {
          outline: none;
        }
        .search-input::placeholder {
          color: var(--muted-foreground, #6c6a81);
        }

        .filter-group {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .filter-select {
          padding: 0.5rem 0.75rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e2e8f0);
          border-radius: var(--radius, 0.625rem);
          font-size: 0.875rem;
          color: var(--foreground, #000);
          cursor: pointer;
        }
        .filter-toggle {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.875rem;
          color: var(--muted-foreground, #6c6a81);
          cursor: pointer;
        }

        /* ¹² Grid layout */
        .directory-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
          gap: 1rem;
          padding: 1.5rem 2rem;
        }

        .student-card {
          display: flex;
          flex-direction: column;
          align-items: center;
          padding: 1rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e2e8f0);
          border-radius: var(--radius, 0.625rem);
          cursor: pointer;
          transition:
            box-shadow 0.15s,
            border-color 0.15s;
        }
        .student-card:hover {
          border-color: var(--secondary, #a278ff);
          box-shadow: var(--shadow-md, 0 4px 6px -1px rgb(0 0 0 / 0.1));
        }

        .sc-avatar {
          position: relative;
          width: 56px;
          height: 56px;
          margin-bottom: 0.625rem;
        }
        .sc-avatar img {
          width: 56px;
          height: 56px;
          border-radius: 14px;
          object-fit: cover;
        }
        .avatar-placeholder {
          width: 56px;
          height: 56px;
          background: var(--secondary, #a278ff);
          border-radius: 14px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .avatar-placeholder span {
          color: var(--secondary-foreground, #fff);
          font-size: 1.125rem;
          font-weight: 600;
        }
        .sc-status {
          position: absolute;
          bottom: 0;
          right: 0;
          width: 12px;
          height: 12px;
          border-radius: 50%;
          border: 2px solid var(--card, #fff);
        }
        .sc-status.active {
          background: var(--accent, #00e7ca); /* ²⁷ Brand accent for active */
        }

        .sc-info {
          text-align: center;
        }
        .sc-name {
          display: block;
          font-size: 0.9375rem;
          font-weight: 500;
          color: var(--foreground, #000);
          line-height: 1.3;
        }
        .sc-meta {
          display: block;
          font-size: 0.75rem;
          color: var(--muted-foreground, #6c6a81);
          margin-top: 0.125rem;
        }

        .sc-tags {
          display: flex;
          gap: 0.25rem;
          margin-top: 0.5rem;
        }
        .sc-tag {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 20px;
          height: 20px;
          border-radius: 4px;
          background: var(--muted, #f0f0f2);
          color: var(--muted-foreground, #6c6a81);
        }
        .sc-tag.allergy {
          background: #fef3c7;
          color: #b45309;
        }
        .sc-tag.custody {
          background: #fee2e2;
          color: #dc2626;
        }

        .empty-state {
          grid-column: 1 / -1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 4rem 2rem;
          text-align: center;
        }
        .empty-icon {
          opacity: 0.4;
          margin-bottom: 1rem;
          color: var(--muted-foreground, #6c6a81);
        }
        .empty-text {
          font-size: 1.125rem;
          font-weight: 500;
          color: var(--foreground, #000);
        }
        .empty-hint {
          font-size: 0.875rem;
          color: var(--muted-foreground, #6c6a81);
          margin-top: 0.25rem;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // EMBEDDED FORMAT — Compact student picker
  // ═══════════════════════════════════════════════════════════════════════════════

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='directory-embedded'>
        <div class='de-header'>
          <svg
            class='de-icon'
            width='20'
            height='20'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' />
            <circle cx='9' cy='7' r='4' />
            <path d='M23 21v-2a4 4 0 0 0-3-3.87' />
            <path d='M16 3.13a4 4 0 0 1 0 7.75' />
          </svg>
          <span class='de-title'>Student Directory</span>
          <span class='de-count'>{{@model.studentCount}}</span>
        </div>
        <div class='de-preview'>
          {{#each @model.students as |student|}}
            <div class='de-avatar' title={{student.displayName}}>
              {{#if student.photoUrl}}
                <img src={{student.photoUrl}} alt='' />
              {{else}}
                <span class='de-initials'>{{student.initials}}</span>
              {{/if}}
            </div>
          {{/each}}
        </div>
      </div>

      <style scoped>
        .directory-embedded {
          padding: 0.75rem;
          background: var(--card, #fff);
          border: 1px solid var(--border, #e2e8f0);
          border-radius: var(--radius, 0.625rem);
          font-family: var(
            --font-sans,
            'Plus Jakarta Sans',
            system-ui,
            sans-serif
          );
        }
        .de-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 0.625rem;
        }
        .de-icon {
          color: var(--primary, #ff2c4e);
        }
        .de-title {
          flex: 1;
          font-weight: 500;
          color: var(--foreground, #000);
        }
        .de-count {
          padding: 0.125rem 0.5rem;
          background: var(--muted, #f0f0f2);
          color: var(--muted-foreground, #6c6a81);
          font-size: 0.75rem;
          font-weight: 500;
          border-radius: 4px;
        }
        .de-preview {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem;
        }
        .de-avatar {
          width: 28px;
          height: 28px;
          border-radius: 6px;
          overflow: hidden;
          background: var(--secondary, #a278ff);
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .de-avatar img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        .de-initials {
          color: var(--secondary-foreground, #fff);
          font-size: 0.625rem;
          font-weight: 600;
        }
      </style>
    </template>
  };

  // ═══════════════════════════════════════════════════════════════════════════════
  // FITTED FORMAT — Summary for dashboards
  // ═══════════════════════════════════════════════════════════════════════════════

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='directory-fitted'>
        <svg
          class='df-icon'
          width='24'
          height='24'
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='2'
        >
          <path d='M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2' />
          <circle cx='9' cy='7' r='4' />
          <path d='M23 21v-2a4 4 0 0 0-3-3.87' />
          <path d='M16 3.13a4 4 0 0 1 0 7.75' />
        </svg>
        <span class='df-count'>{{@model.studentCount}}</span>
        <span class='df-label'>Students</span>
      </div>

      <style scoped>
        .directory-fitted {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          padding: 0.75rem;
          text-align: center;
          font-family: var(
            --font-sans,
            'Plus Jakarta Sans',
            system-ui,
            sans-serif
          );
          background: var(--card, #fff);
        }
        .df-icon {
          color: var(--primary, #ff2c4e);
          margin-bottom: 0.25rem;
        }
        .df-count {
          font-size: 1.5rem;
          font-weight: 700;
          color: var(--primary, #ff2c4e);
          line-height: 1;
        }
        .df-label {
          font-size: 0.6875rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--muted-foreground, #6c6a81);
          margin-top: 0.125rem;
        }
      </style>
    </template>
  };
}
// touched for re-index
