// Phase 0 - DailyPlan CardDef
//
// Accumulating history of daily schedules, one per (student, date).
// Filename convention: DailyPlan/<date>-<student-slug>.json
//   e.g. DailyPlan/2026-04-09-jamie-chen.json
//
// Never overwrites. Each day a new DailyPlan card is created (manually
// or via the Phase 2 AI generator). Old plans stay as historical record.
//
// Populated by:
//   - Phase 2 AI generator (generatedBy = 'ai')
//   - Manual teacher edit via Boxel's built-in pencil (generatedBy = 'manual')

import {
  CardDef,
  field,
  contains,
  containsMany,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DateField from 'https://cardstack.com/base/date';
import DatetimeField from 'https://cardstack.com/base/datetime';
import enumField from 'https://cardstack.com/base/enum';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Student } from './student';
import { Classroom } from './classroom';
import { ScheduleItem } from './schedule-item';

// Fixed-options fields use enumField so Boxel renders them as dropdowns,
// not free-text inputs.
const StatusField = enumField(StringField, {
  options: ['draft', 'committed', 'archived'],
});
const GeneratedByField = enumField(StringField, {
  options: ['manual', 'ai'],
});

export class DailyPlan extends CardDef {
  static displayName = 'Daily Plan';

  // ---- Identity / traceability ----
  @field student = linksTo(() => Student);
  @field classroom = linksTo(() => Classroom);
  @field planDate = contains(DateField);

  // ---- Content ----
  @field scheduleItems = containsMany(ScheduleItem);
  @field notes = contains(StringField);

  // ---- Metadata ----
  @field status = contains(StatusField);       // dropdown: draft / committed / archived
  @field generatedBy = contains(GeneratedByField); // dropdown: manual / ai
  @field generatedAt = contains(DatetimeField);
  @field aiModelUsed = contains(StringField);  // e.g. 'google/gemini-2.0-flash-001'

  // ---- Computed ----
  @field cardTitle = contains(StringField, {
    computeVia: function (this: DailyPlan) {
      // Display name from linked student (not cross-realm, so safe)
      const first = this.student?.firstName ?? '';
      const last = this.student?.lastName ?? '';
      const nameRaw = `${first} ${last}`.trim() || 'Unknown';
      // Slug fallback
      const name = nameRaw || 'Student';

      let dateStr = '';
      if (this.planDate) {
        try {
          const d = new Date(this.planDate as any);
          dateStr = d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          });
        } catch (_) {
          dateStr = '';
        }
      }
      return dateStr ? `${name} - ${dateStr}` : `${name} Daily Plan`;
    },
  });

  // ---- Embedded view (for list cards on dashboard) ----
  static embedded = class Embedded extends Component<typeof DailyPlan> {
    get displayDate() {
      if (!this.args.model?.planDate) return '';
      try {
        return new Date(this.args.model.planDate as any).toLocaleDateString('en-US', {
          weekday: 'short',
          month: 'short',
          day: 'numeric',
        });
      } catch (_) {
        return '';
      }
    }

    get itemCount() {
      return this.args.model?.scheduleItems?.length ?? 0;
    }

    <template>
      <div class='dp-embed'>
        <div class='dp-embed-top'>
          <span class='dp-embed-name'>
            {{@model.student.firstName}}
            {{@model.student.lastName}}
          </span>
          <span class='dp-embed-date'>{{this.displayDate}}</span>
        </div>
        <div class='dp-embed-meta'>
          {{#if (eq @model.status 'draft')}}
            <span class='dp-status dp-status-draft'>DRAFT</span>
          {{else if (eq @model.status 'committed')}}
            <span class='dp-status dp-status-committed'>COMMITTED</span>
          {{else if (eq @model.status 'archived')}}
            <span class='dp-status dp-status-archived'>ARCHIVED</span>
          {{/if}}
          <span class='dp-count'>{{this.itemCount}} items</span>
          {{#if (eq @model.generatedBy 'ai')}}
            <span class='dp-ai'>AI</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .dp-embed {
          padding: 12px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          font-family: system-ui, sans-serif;
        }
        .dp-embed-top {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
          margin-bottom: 4px;
        }
        .dp-embed-name {
          font-weight: 600;
          color: #1a1816;
          font-size: 14px;
        }
        .dp-embed-date {
          font-size: 11px;
          color: #8a8279;
          font-family: ui-monospace, monospace;
        }
        .dp-embed-meta {
          display: flex;
          gap: 8px;
          align-items: center;
        }
        .dp-status {
          font-size: 9px;
          padding: 2px 6px;
          border-radius: 999px;
          text-transform: uppercase;
          font-weight: 700;
          letter-spacing: 0.5px;
        }
        .dp-status-draft { background: #fef5e7; color: #975a16; }
        .dp-status-committed { background: #e8f6f4; color: #2a9d8f; }
        .dp-status-archived { background: #edf2f7; color: #718096; }
        .dp-count {
          font-size: 11px;
          color: #5c5650;
        }
        .dp-ai {
          font-size: 9px;
          padding: 2px 6px;
          background: #f1ebfb;
          color: #553c9a;
          border-radius: 4px;
          font-weight: 700;
        }
      </style>
    </template>
  };

  // ---- Isolated view (full schedule timeline) ----
  static isolated = class Isolated extends Component<typeof DailyPlan> {
    classroomUrl = 'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/Classroom/classroom-2a';

    get displayDate() {
      if (!this.args.model?.planDate) return '';
      try {
        return new Date(this.args.model.planDate as any).toLocaleDateString('en-US', {
          weekday: 'long',
          month: 'long',
          day: 'numeric',
          year: 'numeric',
        });
      } catch (_) {
        return '';
      }
    }

    <template>
      <a class='dp-back' href={{this.classroomUrl}}>← Back to Classroom</a>
      <article class='dp-root'>
        <header class='dp-header'>
          <div class='dp-header-left'>
            <span class='dp-brand'>TRIBECA PREP · DAILY PLAN</span>
            <h1 class='dp-title'>
              {{@model.student.firstName}}
              {{@model.student.lastName}}
            </h1>
            <p class='dp-date'>{{this.displayDate}}</p>
          </div>
          <div class='dp-header-right'>
            {{#if @model.status}}
              <span class='dp-chip dp-chip-{{@model.status}}'>{{@model.status}}</span>
            {{/if}}
            {{#if @model.generatedBy}}
              <span class='dp-gen'>by {{@model.generatedBy}}</span>
            {{/if}}
          </div>
        </header>

        <section class='dp-section'>
          <h2 class='dp-section-title'>Schedule</h2>
          <div class='dp-schedule'>
            {{#if @model.scheduleItems.length}}
              <@fields.scheduleItems />
            {{else}}
              <p class='dp-empty'>
                No schedule items yet. Use Boxel's edit (pencil icon at top right)
                to add items, or trigger the Phase 2 AI generator.
              </p>
            {{/if}}
          </div>
        </section>

        {{#if @model.notes}}
          <section class='dp-section'>
            <h2 class='dp-section-title'>Notes</h2>
            <p class='dp-notes'>{{@model.notes}}</p>
          </section>
        {{/if}}

        <footer class='dp-footer'>
          <details>
            <summary>Metadata</summary>
            <dl>
              <dt>Generated at</dt><dd>{{@model.generatedAt}}</dd>
              <dt>Generated by</dt><dd>{{@model.generatedBy}}</dd>
              {{#if @model.aiModelUsed}}
                <dt>AI model</dt><dd class='mono'>{{@model.aiModelUsed}}</dd>
              {{/if}}
              <dt>Classroom</dt><dd>{{@model.classroom.classroomName}}</dd>
            </dl>
          </details>
        </footer>
      </article>

      <style scoped>
        .dp-back {
          display: inline-block;
          max-width: 720px;
          margin: 16px auto 12px;
          padding: 8px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          color: #4a5568;
          font-family: system-ui, sans-serif;
          font-size: 12px;
          font-weight: 600;
          text-decoration: none;
        }
        .dp-back:hover {
          background: #faf8f6;
          border-color: #2a9d8f;
          color: #2a9d8f;
        }
        .dp-root {
          max-width: 720px;
          margin: 0 auto;
          padding: 24px;
          background: white;
          font-family: system-ui, sans-serif;
          color: #1a1816;
        }
        .dp-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          padding-bottom: 18px;
          border-bottom: 2px solid #f5f2ef;
          margin-bottom: 24px;
        }
        .dp-brand {
          font-size: 10px;
          font-weight: 700;
          color: #e05d50;
          letter-spacing: 0.8px;
          display: block;
          margin-bottom: 6px;
        }
        .dp-title {
          margin: 0 0 4px;
          font-size: 24px;
          font-weight: 700;
          color: #1a1816;
        }
        .dp-date {
          margin: 0;
          color: #8a8279;
          font-size: 13px;
        }
        .dp-header-right {
          display: flex;
          flex-direction: column;
          gap: 6px;
          align-items: flex-end;
        }
        .dp-chip {
          font-size: 10px;
          font-weight: 700;
          padding: 4px 10px;
          border-radius: 999px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .dp-chip-draft { background: #fef5e7; color: #975a16; }
        .dp-chip-committed { background: #e8f6f4; color: #2a9d8f; }
        .dp-chip-archived { background: #edf2f7; color: #718096; }
        .dp-gen {
          font-size: 10px;
          color: #8a8279;
        }
        .dp-section {
          margin-bottom: 24px;
        }
        .dp-section-title {
          margin: 0 0 10px;
          font-size: 11px;
          font-weight: 700;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.6px;
        }
        .dp-schedule {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .dp-empty {
          padding: 16px;
          background: #faf8f6;
          border: 1px dashed #e2e8f0;
          border-radius: 8px;
          color: #a0aec0;
          font-style: italic;
          font-size: 13px;
          margin: 0;
        }
        .dp-notes {
          padding: 12px 14px;
          background: #faf8f6;
          border-radius: 8px;
          color: #2d3748;
          font-size: 13px;
          line-height: 1.5;
          margin: 0;
        }
        .dp-footer {
          margin-top: 24px;
          padding-top: 16px;
          border-top: 1px solid #f5f2ef;
          font-size: 11px;
          color: #8a8279;
        }
        .dp-footer details summary {
          cursor: pointer;
          font-weight: 600;
        }
        .dp-footer dl {
          margin: 8px 0 0;
          display: grid;
          grid-template-columns: 110px 1fr;
          gap: 4px 12px;
        }
        .dp-footer dt { color: #8a8279; }
        .dp-footer dd { margin: 0; color: #2d3748; }
        .dp-footer dd.mono { font-family: ui-monospace, monospace; }
      </style>
    </template>
  };
}

// touched for re-index
