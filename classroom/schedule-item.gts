import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';

const StatusField = enumField(StringField, {
  options: ['Done', 'Current', 'Upcoming'],
});

export class ScheduleItem extends FieldDef {
  static displayName = 'Schedule Item';

  @field time = contains(StringField);
  @field activity = contains(StringField);
  @field status = contains(StatusField);
  @field result = contains(StringField);
  @field goalTag = contains(StringField);

  static embedded = class Embedded extends Component<typeof ScheduleItem> {
    get safeActivity() {
      return this.args.model?.activity ?? 'Untitled';
    }

    get safeStatus() {
      return this.args.model?.status ?? 'Upcoming';
    }

    get statusDotColor() {
      switch (this.safeStatus) {
        case 'Done': return '#2a9d8f';
        case 'Current': return '#c08b30';
        case 'Upcoming': return '#8a8279';
        default: return '#8a8279';
      }
    }

    get isDone() {
      return this.safeStatus === 'Done';
    }

    get isCurrent() {
      return this.safeStatus === 'Current';
    }

    <template>
      <div class='schedule-row {{if this.isCurrent "current"}} {{if this.isDone "done"}}'>
        <span class='dot' style='background-color: {{this.statusDotColor}}'></span>
        <div class='content'>
          <span class='activity'>{{this.safeActivity}}</span>
          {{#if @model.result}}
            <span class='result'>{{@model.result}}</span>
          {{/if}}
          {{#if @model.goalTag}}
            <span class='goal-tag'>{{@model.goalTag}}</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .schedule-row {
          display: grid;
          grid-template-columns: 0.5rem 1fr;
          gap: 0.5rem;
          align-items: start;
          padding: 0.375rem 0;
        }

        .schedule-row.done {
          opacity: 0.6;
        }

        .schedule-row.current {
          background-color: rgba(192, 139, 48, 0.08);
          border-radius: 6px;
          padding: 0.375rem 0.5rem;
          margin: 0 -0.5rem;
        }

        .dot {
          width: 0.5rem;
          height: 0.5rem;
          border-radius: 50%;
          margin-top: 0.25rem;
        }

        .content {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
          align-items: baseline;
        }

        .activity {
          font-size: 0.8125rem;
          color: #1a1816;
          font-weight: 500;
        }

        .result {
          font-size: 0.6875rem;
          color: #2a9d8f;
          font-weight: 600;
          background: rgba(42, 157, 143, 0.1);
          padding: 0.125rem 0.375rem;
          border-radius: 4px;
        }

        .goal-tag {
          font-size: 0.6875rem;
          color: #7c5fc4;
          font-weight: 500;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof ScheduleItem> {
    <template>
      <div class='schedule-edit'>
        <div class='field-row'>
          <label>Activity</label>
          <@fields.activity />
        </div>
        <div class='field-row'>
          <label>Status</label>
          <@fields.status />
        </div>
        <div class='field-row'>
          <label>Result</label>
          <@fields.result />
        </div>
        <div class='field-row'>
          <label>Goal Tag</label>
          <@fields.goalTag />
        </div>
      </div>

      <style scoped>
        .schedule-edit {
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
