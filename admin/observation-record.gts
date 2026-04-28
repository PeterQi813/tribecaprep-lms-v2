import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

export class ObservationRecord extends CardDef {
  static displayName = 'Observation Record';

  @field date = contains(StringField);        // e.g. "Feb 5, 10:23"
  @field studentName = contains(StringField);
  @field category = contains(StringField);    // "Academic" | "Social" | "Behavioral"
  @field linkedGoal = contains(StringField);  // goal title or "—"
  @field score = contains(StringField);       // e.g. "18/20" or "4/5" or "—"
  @field staffInitials = contains(StringField); // e.g. "RM"
  @field staffColor = contains(StringField);  // "teal" | "purple" | "coral" | "amber"
  @field flagged = contains(StringField);     // "true" | "false"
  @field notes = contains(StringField);
  @field sourceEntryId = contains(StringField); // ActivityEntry card ID for dedup

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ObservationRecord) {
      return this.studentName && this.category
        ? `${this.studentName} — ${this.category}`
        : 'Observation Record';
    },
  });

  get categoryLower() {
    return (this.category || '').toLowerCase();
  }

  get isGoodScore() {
    // score like "18/20", "4/5" — if numerator >= 80% of denominator
    let s = this.score || '';
    let m = s.match(/^(\d+)\/(\d+)$/);
    if (m) return parseInt(m[1]) / parseInt(m[2]) >= 0.8;
    return false;
  }

  // Fitted view — data table row
  static fitted = class Fitted extends Component<typeof this> {
    get categoryLower() {
      return (this.args.model.category || '').toLowerCase();
    }

    get isGoodScore() {
      let s = this.args.model.score || '';
      let m = s.match(/^(\d+)\/(\d+)$/);
      if (m) return parseInt(m[1]) / parseInt(m[2]) >= 0.8;
      return false;
    }

    get isFlagged() {
      return this.args.model.flagged === 'true';
    }

    <template>
      <div class='obs-row {{if this.isFlagged "flagged"}}'>
        <span class='or-date'>{{@model.date}}</span>
        <span class='or-student'>{{@model.studentName}}</span>
        <span class='or-type {{this.categoryLower}}'>{{@model.category}}</span>
        <span class='or-goal'>{{@model.linkedGoal}}</span>
        <span class='or-score {{if this.isGoodScore "good"}}'>{{@model.score}}</span>
        <div class='or-staff {{@model.staffColor}}'>{{@model.staffInitials}}</div>
      </div>
      <style scoped>
        .obs-row {
          display: grid;
          grid-template-columns: 100px 90px 90px 1fr 60px 32px;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          background: #fffdfb;
          border-radius: 6px;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
          font-size: 0.8125rem;
          color: #1a1816;
        }
        .obs-row.flagged { background: #fdf8f6; }
        .or-date { font-size: 0.75rem; color: #5c5650; }
        .or-student { font-weight: 500; }
        .or-type {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          display: inline-block;
        }
        .or-type.social { background: #f4f0fa; color: #7c5fc4; }
        .or-type.academic { background: #fdf0ee; color: #e05d50; }
        .or-type.behavioral { background: #fdf6e8; color: #c08b30; }
        .or-goal { font-size: 0.75rem; color: #5c5650; }
        .or-score {
          font-size: 0.75rem;
          font-weight: 600;
          color: #8a8279;
          text-align: center;
        }
        .or-score.good { color: #2a9d8f; }
        .or-staff {
          width: 28px;
          height: 28px;
          border-radius: 7px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.5rem;
          font-weight: 700;
          color: white;
        }
        .or-staff.teal { background: #2a9d8f; }
        .or-staff.purple { background: #7c5fc4; }
        .or-staff.coral { background: #e05d50; }
        .or-staff.amber { background: #c08b30; }
      </style>
    </template>
  };

  // Embedded view — compact inline row
  static embedded = class Embedded extends Component<typeof this> {
    get categoryLower() {
      return (this.args.model.category || '').toLowerCase();
    }

    <template>
      <div class='obs-embedded'>
        <span class='oe-type {{this.categoryLower}}'>{{@model.category}}</span>
        <span class='oe-student'>{{@model.studentName}}</span>
        <span class='oe-goal'>{{@model.linkedGoal}}</span>
        <span class='oe-date'>{{@model.date}}</span>
      </div>
      <style scoped>
        .obs-embedded {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .oe-type {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.125rem 0.375rem;
          border-radius: 3px;
          flex-shrink: 0;
        }
        .oe-type.social { background: #f4f0fa; color: #7c5fc4; }
        .oe-type.academic { background: #fdf0ee; color: #e05d50; }
        .oe-type.behavioral { background: #fdf6e8; color: #c08b30; }
        .oe-student {
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
          flex-shrink: 0;
        }
        .oe-goal {
          font-size: 0.75rem;
          color: #5c5650;
          flex: 1;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .oe-date {
          font-size: 0.6875rem;
          color: #8a8279;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  // Isolated view — full record detail
  static isolated = class Isolated extends Component<typeof this> {
    get categoryLower() {
      return (this.args.model.category || '').toLowerCase();
    }

    get isFlagged() {
      return this.args.model.flagged === 'true';
    }

    get isGoodScore() {
      let s = this.args.model.score || '';
      let m = s.match(/^(\d+)\/(\d+)$/);
      if (m) return parseInt(m[1]) / parseInt(m[2]) >= 0.8;
      return false;
    }

    <template>
      <div class='obs-detail'>
        <div class='od-header'>
          <div class='od-meta'>
            <span class='od-type {{this.categoryLower}}'>{{@model.category}}</span>
            {{#if this.isFlagged}}
              <span class='od-flag'>⚑ Flagged</span>
            {{/if}}
          </div>
          <span class='od-date'>{{@model.date}}</span>
        </div>

        <div class='od-body'>
          <div class='od-row'>
            <span class='od-label'>Student</span>
            <span class='od-value'>{{@model.studentName}}</span>
          </div>
          <div class='od-row'>
            <span class='od-label'>Goal</span>
            <span class='od-value'>{{@model.linkedGoal}}</span>
          </div>
          <div class='od-row'>
            <span class='od-label'>Score</span>
            <span class='od-value score {{if this.isGoodScore "good"}}'>
              {{@model.score}}
            </span>
          </div>
          {{#if @model.notes}}
            <div class='od-row notes'>
              <span class='od-label'>Notes</span>
              <span class='od-value'>{{@model.notes}}</span>
            </div>
          {{/if}}
        </div>

        <div class='od-footer'>
          <div class='od-staff-badge {{@model.staffColor}}'>{{@model.staffInitials}}</div>
          <span class='od-staff-label'>Recorded by staff</span>
        </div>
      </div>
      <style scoped>
        .obs-detail {
          background: #fffdfb;
          border-radius: 14px;
          box-shadow: 0 4px 12px rgba(26,24,22,0.06);
          max-width: 540px;
          margin: 0 auto;
          overflow: hidden;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .od-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 1rem 1.25rem;
          border-bottom: 1px solid #f5f2ef;
        }
        .od-meta { display: flex; align-items: center; gap: 0.5rem; }
        .od-type {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.25rem 0.625rem;
          border-radius: 4px;
        }
        .od-type.social { background: #f4f0fa; color: #7c5fc4; }
        .od-type.academic { background: #fdf0ee; color: #e05d50; }
        .od-type.behavioral { background: #fdf6e8; color: #c08b30; }
        .od-flag {
          font-size: 0.625rem;
          font-weight: 600;
          color: #c08b30;
        }
        .od-date { font-size: 0.75rem; color: #8a8279; }
        .od-body { padding: 1rem 1.25rem; display: flex; flex-direction: column; gap: 0.75rem; }
        .od-row {
          display: flex;
          gap: 1rem;
          align-items: baseline;
        }
        .od-label {
          font-size: 0.625rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #8a8279;
          min-width: 60px;
          flex-shrink: 0;
        }
        .od-value {
          font-size: 0.875rem;
          color: #1a1816;
        }
        .od-value.score { font-weight: 700; color: #8a8279; }
        .od-value.score.good { color: #2a9d8f; }
        .od-row.notes .od-value { font-size: 0.8125rem; color: #5c5650; line-height: 1.5; }
        .od-footer {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.875rem 1.25rem;
          border-top: 1px solid #f5f2ef;
          background: #faf8f6;
        }
        .od-staff-badge {
          width: 28px;
          height: 28px;
          border-radius: 7px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.5625rem;
          font-weight: 700;
          color: white;
        }
        .od-staff-badge.teal { background: #2a9d8f; }
        .od-staff-badge.purple { background: #7c5fc4; }
        .od-staff-badge.coral { background: #e05d50; }
        .od-staff-badge.amber { background: #c08b30; }
        .od-staff-label { font-size: 0.75rem; color: #8a8279; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='or-edit'>
        <div class='or-row'><label>Date</label><@fields.date /></div>
        <div class='or-row'><label>Student Name</label><@fields.studentName /></div>
        <div class='or-row'><label>Category</label><@fields.category /></div>
        <div class='or-row'><label>Linked Goal</label><@fields.linkedGoal /></div>
        <div class='or-row'><label>Score</label><@fields.score /></div>
        <div class='or-pair'>
          <div class='or-row'><label>Staff Initials</label><@fields.staffInitials /></div>
          <div class='or-row'><label>Staff Color</label><@fields.staffColor /></div>
        </div>
        <div class='or-row'><label>Flagged</label><@fields.flagged /></div>
        <div class='or-row'><label>Notes</label><@fields.notes /></div>
      </div>
      <style scoped>
        .or-edit { display: flex; flex-direction: column; gap: 0.75rem; padding: 1rem; font-family: 'Inter', system-ui, sans-serif; }
        .or-row { display: flex; flex-direction: column; gap: 0.25rem; }
        .or-row label { font-size: 0.6875rem; font-weight: 600; color: #8a8279; text-transform: uppercase; letter-spacing: 0.05em; }
        .or-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
      </style>
    </template>
  };
}
// touched for re-index
