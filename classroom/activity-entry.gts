import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DatetimeField from 'https://cardstack.com/base/datetime';
import enumField from 'https://cardstack.com/base/enum';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { formatDateTime } from '@cardstack/boxel-ui/helpers';
import { Staff } from './staff';
import { Student } from './student';
import { LearningGoal } from './learning-goal';

const EntryTypeField = enumField(StringField, {
  options: ['Academic', 'Social', 'Behavioral'],
});

export class ActivityEntry extends CardDef {
  static displayName = 'Activity Entry';
  static icon = FileTextIcon;

  @field author = linksTo(Staff);
  @field student = linksTo(Student);
  @field timestamp = contains(DatetimeField);
  @field content = contains(StringField);
  @field entryType = contains(EntryTypeField);
  @field goalLink = linksTo(LearningGoal);
  @field score = contains(StringField);
  @field aiTagged = contains(StringField);
  @field flagNote = contains(StringField);
  @field domain = contains(StringField);
  @field confidence = contains(NumberField);
  @field reasoning = contains(StringField);
  @field matchedBlock = contains(StringField);
  @field suggestedGoal = contains(StringField);
  @field activityDate = contains(StringField);  // yyyy-mm-dd, the date this activity belongs to
  @field highlighted = contains(StringField);   // 'true' if teacher starred it

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ActivityEntry) {
      const first = this.student?.firstName ?? '';
      const last = this.student?.lastName ?? '';
      const studentName = `${first} ${last}`.trim() || 'Unknown';
      const type = this.entryType ?? 'Note';
      const dateStr = this.timestamp
        ? new Date(this.timestamp as any).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : '';
      return `${studentName} - ${type}${dateStr ? ` (${dateStr})` : ''}`;
    },
  });

  static isolated = class Isolated extends Component<typeof ActivityEntry> {
    get safeContent() {
      return this.args.model?.content ?? '';
    }

    get safeType() {
      return this.args.model?.entryType ?? 'Note';
    }

    get typeColor() {
      switch (this.safeType) {
        case 'Academic': return '#e05d50';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        default: return '#5c5650';
      }
    }

    get isAiTagged() {
      return this.args.model?.aiTagged === 'true';
    }

    <template>
      <article class='entry-full'>
        <header class='entry-header'>
          <span class='type-badge' style='background-color: {{this.typeColor}}'>
            {{this.safeType}}
          </span>
          {{#if @model.timestamp}}
            <span class='timestamp'>
              {{formatDateTime @model.timestamp 'MMM D, YYYY h:mm A'}}
            </span>
          {{/if}}
          {{#if this.isAiTagged}}
            <span class='ai-badge'>AI Tagged</span>
          {{/if}}
        </header>

        {{#if @model.author}}
          <section class='section'>
            <h2 class='section-label'>Author</h2>
            <@fields.author @format='embedded' />
          </section>
        {{/if}}

        {{#if @model.student}}
          <section class='section'>
            <h2 class='section-label'>Student</h2>
            <@fields.student @format='embedded' />
          </section>
        {{/if}}

        <section class='section'>
          <h2 class='section-label'>Observation</h2>
          <p class='content-text'>{{this.safeContent}}</p>
        </section>

        {{#if @model.score}}
          <div class='meta-row'>
            <span class='meta-label'>Score</span>
            <span class='meta-value score'>{{@model.score}}</span>
          </div>
        {{/if}}

        {{#if @model.goalLink}}
          <section class='section'>
            <h2 class='section-label'>Linked Goal</h2>
            <@fields.goalLink @format='embedded' />
          </section>
        {{/if}}

        {{#if @model.flagNote}}
          <div class='flag-note'>{{@model.flagNote}}</div>
        {{/if}}
      </article>

      <style scoped>
        .entry-full {
          width: 100%;
          max-width: 36rem;
          margin: 0 auto;
          padding: var(--boxel-sp-xl);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: var(--boxel-border-radius-lg);
        }

        .entry-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-wrap: wrap;
        }

        .type-badge {
          padding: 0.25rem 0.75rem;
          border-radius: 1rem;
          color: white;
          font-weight: 600;
          font-size: 0.6875rem;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .timestamp {
          font-size: var(--boxel-font-size-sm);
          color: #8a8279;
        }

        .ai-badge {
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          background: rgba(42, 157, 143, 0.1);
          color: #2a9d8f;
          font-weight: 600;
          font-size: 0.6875rem;
          text-transform: uppercase;
        }

        .section {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
        }

        .section-label {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #5c5650;
          margin: 0;
        }

        .content-text {
          font-size: var(--boxel-font-size);
          color: #1a1816;
          line-height: 1.6;
          margin: 0;
        }

        .meta-row {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
        }

        .meta-label {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #5c5650;
        }

        .meta-value.score {
          font-weight: 700;
          color: #2a9d8f;
        }

        .flag-note {
          padding: 0.5rem 0.75rem;
          background: rgba(192, 139, 48, 0.08);
          border-left: 3px solid #c08b30;
          border-radius: 4px;
          font-size: var(--boxel-font-size-sm);
          color: #5c5650;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ActivityEntry> {
    get safeContent() {
      return this.args.model?.content ?? '';
    }

    get safeType() {
      return this.args.model?.entryType ?? 'Note';
    }

    get typeColor() {
      switch (this.safeType) {
        case 'Academic': return '#e05d50';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        default: return '#5c5650';
      }
    }

    get typeBgColor() {
      switch (this.safeType) {
        case 'Academic': return 'rgba(224, 93, 80, 0.1)';
        case 'Social': return 'rgba(124, 95, 196, 0.1)';
        case 'Behavioral': return 'rgba(192, 139, 48, 0.1)';
        default: return 'rgba(92, 86, 80, 0.1)';
      }
    }

    get authorName() {
      return this.args.model?.author?.name ?? 'Unknown';
    }

    get authorInitials() {
      return this.args.model?.author?.initials ?? '??';
    }

    get authorColor() {
      switch (this.args.model?.author?.color) {
        case 'coral': return '#e05d50';
        case 'teal': return '#2a9d8f';
        case 'purple': return '#7c5fc4';
        case 'amber': return '#c08b30';
        default: return '#5c5650';
      }
    }

    get isAiTagged() {
      return this.args.model?.aiTagged === 'true';
    }

    get goalName() {
      return this.args.model?.goalLink?.goalTitle ?? null;
    }

    <template>
      <div class='entry-embedded'>
        <div class='entry-top'>
          <div class='author-badge' style='background-color: {{this.authorColor}}'>
            {{this.authorInitials}}
          </div>
          <span class='author-name'>{{this.authorName}}</span>
          {{#if @model.timestamp}}
            <span class='time'>
              {{formatDateTime @model.timestamp 'h:mm A'}}
            </span>
          {{/if}}
        </div>

        <p class='entry-content'>{{this.safeContent}}</p>

        <div class='entry-tags'>
          <span class='type-pill' style='background: {{this.typeBgColor}}; color: {{this.typeColor}}'>
            {{this.safeType}}
          </span>
          {{#if this.goalName}}
            <span class='goal-ref'>&rarr; {{this.goalName}}</span>
          {{/if}}
          {{#if @model.score}}
            <span class='score-tag'>{{@model.score}}</span>
          {{/if}}
          {{#if this.isAiTagged}}
            <span class='ai-tag'>AI Tagged</span>
          {{/if}}
        </div>

        {{#if @model.flagNote}}
          <div class='flag'>{{@model.flagNote}}</div>
        {{/if}}
      </div>

      <style scoped>
        .entry-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          padding: 0.625rem;
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: 8px;
          height: 100%;
        }

        .entry-top {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }

        .author-badge {
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
        }

        .author-name {
          font-size: 0.75rem;
          font-weight: 600;
          color: #1a1816;
        }

        .time {
          margin-left: auto;
          font-size: 0.6875rem;
          color: #8a8279;
        }

        .entry-content {
          font-size: 0.8125rem;
          color: #1a1816;
          line-height: 1.5;
          margin: 0;
        }

        .entry-tags {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem;
          align-items: center;
        }

        .type-pill {
          padding: 0.125rem 0.375rem;
          border-radius: 4px;
          font-weight: 600;
          font-size: 0.625rem;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .goal-ref {
          font-size: 0.6875rem;
          color: #7c5fc4;
          font-weight: 500;
        }

        .score-tag {
          font-size: 0.6875rem;
          color: #2a9d8f;
          font-weight: 600;
        }

        .ai-tag {
          padding: 0.0625rem 0.3125rem;
          border-radius: 3px;
          background: rgba(42, 157, 143, 0.1);
          color: #2a9d8f;
          font-weight: 600;
          font-size: 0.5625rem;
          text-transform: uppercase;
        }

        .flag {
          padding: 0.3125rem 0.5rem;
          background: rgba(192, 139, 48, 0.08);
          border-left: 2px solid #c08b30;
          border-radius: 3px;
          font-size: 0.6875rem;
          color: #5c5650;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ActivityEntry> {
    get safeType() {
      return this.args.model?.entryType ?? 'Note';
    }

    get typeColor() {
      switch (this.safeType) {
        case 'Academic': return '#e05d50';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        default: return '#5c5650';
      }
    }

    get shortContent() {
      const content = this.args.model?.content ?? '';
      return content.length > 60 ? content.substring(0, 60) + '...' : content;
    }

    get authorDisplay() {
      const a = this.args.model?.author;
      if (!a) return '';
      if (a.name) return a.name;
      const f = String(a.firstName ?? '');
      const l = String(a.lastName ?? '');
      return `${f} ${l}`.trim() || '';
    }

    get studentDisplay() {
      const s = this.args.model?.student;
      if (!s) return '';
      const f = String(s.firstName ?? '');
      const l = String(s.lastName ?? '');
      return `${f} ${l}`.trim() || '';
    }

    <template>
      <div class='fitted-container'>
        <div class='tile'>
          <div class='tile-top'>
            <span class='type-dot' style='background-color: {{this.typeColor}}'></span>
            {{#if @model.timestamp}}
              <span class='time'>{{formatDateTime @model.timestamp 'MMM D, YYYY'}}</span>
            {{/if}}
          </div>
          {{#if this.studentDisplay}}
            <div class='tile-who'>
              {{#if this.authorDisplay}}
                <span class='tile-author'>{{this.authorDisplay}}</span>
                <span class='tile-arrow'>→</span>
              {{/if}}
              <span class='tile-student'>{{this.studentDisplay}}</span>
            </div>
          {{/if}}
          <span class='preview'>{{this.shortContent}}</span>
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
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          height: 100%;
        }

        .tile-top {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .type-dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
        }
        .tile-who {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.6875rem;
          flex-wrap: wrap;
        }
        .tile-author {
          font-weight: 600;
          color: var(--foreground, #1a1816);
        }
        .tile-arrow {
          color: #a0aec0;
          font-size: 0.625rem;
        }
        .tile-student {
          font-weight: 600;
          color: #2a9d8f;
        }

        .time {
          font-size: var(--boxel-font-size-xs);
          color: #8a8279;
          font-weight: 500;
        }

        .preview {
          font-size: var(--boxel-font-size-xs);
          color: #1a1816;
          line-height: 1.4;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof ActivityEntry> {
    <template>
      <div class='card-edit'>
        <div class='field-row'>
          <label>Content</label>
          <@fields.content />
        </div>
        <div class='field-row'>
          <label>Entry Type</label>
          <@fields.entryType />
        </div>
        <div class='field-row'>
          <label>Author</label>
          <@fields.author />
        </div>
        <div class='field-row'>
          <label>Student</label>
          <@fields.student />
        </div>
        <div class='field-row'>
          <label>Timestamp</label>
          <@fields.timestamp />
        </div>
        <div class='field-row'>
          <label>Linked Goal</label>
          <@fields.goalLink />
        </div>
        <div class='field-row'>
          <label>Score</label>
          <@fields.score />
        </div>
        <div class='field-row'>
          <label>AI Tagged</label>
          <@fields.aiTagged />
        </div>
        <div class='field-row'>
          <label>Flag Note</label>
          <@fields.flagNote />
        </div>
      </div>

      <style scoped>
        .card-edit {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
        }

        .field-row {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .field-row label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };
}
// touched for re-index
