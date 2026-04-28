import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

export class StudentCard extends CardDef {
  static displayName = 'Student Card';

  @field name = contains(StringField);
  @field grade = contains(StringField);
  @field status = contains(StringField); // "IEP" | "504" | "General"
  @field mood = contains(StringField); // "good" | "ok" | "needs"
  @field moodLabel = contains(StringField); // "Great day" | "Mixed" | "Needs support"
  @field goalProgress = contains(StringField); // e.g. "2/4"
  @field observationCount = contains(NumberField);
  @field allergyInfo = contains(StringField);
  @field assignedStaff = contains(StringField);
  @field age = contains(NumberField);
  @field className = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: StudentCard) {
      return this.name || 'Untitled Student';
    },
  });

  // Fitted view — compact card for roster/grid
  static fitted = class Fitted extends Component<typeof this> {
    get initial() {
      return (this.args.model.name || '?')[0];
    }

    get moodIcon() {
      let mood = this.args.model.mood;
      if (mood === 'good') return '\u2600';
      if (mood === 'ok') return '\u25D0';
      if (mood === 'needs') return '\u25D1';
      return '';
    }

    <template>
      <div class='student-fitted'>
        <div class='sf-avatar'>
          <div class='sf-avatar-placeholder'>
            <span class='sf-initial'>{{this.initial}}</span>
          </div>
          <span class='sf-status'></span>
        </div>
        <div class='sf-info'>
          <span class='sf-name'>{{@model.name}}</span>
          <span class='sf-meta'>{{@model.grade}} · {{@model.status}}</span>
        </div>
        <div class='sf-quick'>
          <span class='sf-mood {{@model.mood}}' title={{@model.moodLabel}}>{{this.moodIcon}}</span>
          <span class='sf-progress'>{{@model.goalProgress}}</span>
        </div>
      </div>
      <style scoped>
        .student-fitted {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.875rem;
          background: #fffdfb;
          border-radius: 10px;
          box-shadow: 0 1px 2px rgba(26,24,22,0.04);
          cursor: pointer;
          transition: box-shadow 0.15s, transform 0.1s;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .student-fitted:hover {
          box-shadow: 0 4px 12px rgba(26,24,22,0.06);
          transform: translateY(-1px);
        }
        .sf-avatar {
          width: 40px;
          height: 40px;
          border-radius: 10px;
          overflow: hidden;
          flex-shrink: 0;
          position: relative;
        }
        .sf-avatar-placeholder {
          width: 100%;
          height: 100%;
          background: #f5e6d3;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .sf-initial {
          font-size: 1.125rem;
          font-weight: 700;
          color: #3d2314;
        }
        .sf-status {
          position: absolute;
          bottom: -2px;
          right: -2px;
          width: 10px;
          height: 10px;
          border-radius: 50%;
          background: #2a9d8f;
          border: 2px solid #fffdfb;
        }
        .sf-info {
          flex: 1;
          min-width: 0;
        }
        .sf-name {
          display: block;
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .sf-meta {
          display: block;
          font-size: 0.6875rem;
          color: #8a8279;
        }
        .sf-quick {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.25rem;
        }
        .sf-mood { font-size: 0.875rem; }
        .sf-mood.good { color: #2a9d8f; }
        .sf-mood.ok { color: #c08b30; }
        .sf-mood.needs { color: #e05d50; }
        .sf-progress {
          font-size: 0.6875rem;
          font-weight: 600;
          color: #5c5650;
        }
      </style>
    </template>
  };

  // Embedded view — inline compact row
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='student-embedded'>
        <span class='se-name'>{{@model.name}}</span>
        <span class='se-grade'>{{@model.grade}}</span>
        {{#if @model.status}}
          <span class='se-tag'>{{@model.status}}</span>
        {{/if}}
        {{#if @model.allergyInfo}}
          <span class='se-tag allergy'>{{@model.allergyInfo}}</span>
        {{/if}}
      </div>
      <style scoped>
        .student-embedded {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .se-name {
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
        }
        .se-grade {
          font-size: 0.75rem;
          color: #8a8279;
        }
        .se-tag {
          font-size: 0.625rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.125rem 0.375rem;
          border-radius: 3px;
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .se-tag.allergy {
          background: #fdf0ee;
          color: #e05d50;
        }
      </style>
    </template>
  };

  // Isolated view — full student profile card (narrow format)
  static isolated = class Isolated extends Component<typeof this> {
    get initial() {
      return (this.args.model.name || '?')[0];
    }

    get moodIcon() {
      let mood = this.args.model.mood;
      if (mood === 'good') return '\u2600';
      if (mood === 'ok') return '\u25D0';
      if (mood === 'needs') return '\u25D1';
      return '';
    }

    <template>
      <div class='student-profile'>
        <header class='sp-header'>
          <div class='sp-identity'>
            <div class='sp-avatar'>
              <span class='sp-initial'>{{this.initial}}</span>
            </div>
            <div class='sp-info'>
              <h1 class='sp-name'>{{@model.name}}</h1>
              <p class='sp-meta'>{{@model.grade}} · {{@model.className}} · Age {{@model.age}}</p>
              <div class='sp-tags'>
                {{#if @model.status}}
                  <span class='sp-tag purple'>{{@model.status}} Active</span>
                {{/if}}
                {{#if @model.allergyInfo}}
                  <span class='sp-tag coral'>{{@model.allergyInfo}}</span>
                {{/if}}
              </div>
            </div>
          </div>
        </header>

        <div class='sp-grid'>
          <div class='sp-section'>
            <h3 class='sp-section-title'>Today's Summary</h3>
            <div class='sp-stats'>
              <div class='sp-stat'>
                <span class='sp-stat-value'>{{@model.goalProgress}}</span>
                <span class='sp-stat-label'>Objectives</span>
              </div>
              <div class='sp-stat'>
                <span class='sp-stat-value'>{{@model.observationCount}}</span>
                <span class='sp-stat-label'>Observations</span>
              </div>
              <div class='sp-stat'>
                <span class='sp-stat-value good'>{{@model.moodLabel}}</span>
                <span class='sp-stat-label'>Overall Mood</span>
              </div>
            </div>
          </div>

          {{#if @model.assignedStaff}}
            <div class='sp-section'>
              <h3 class='sp-section-title'>Team</h3>
              <p class='sp-team-text'>{{@model.assignedStaff}}</p>
            </div>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .student-profile {
          background: #fffdfb;
          border-radius: 14px;
          box-shadow: 0 4px 12px rgba(26,24,22,0.06);
          overflow: hidden;
          max-width: 800px;
          margin: 0 auto;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .sp-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          padding: 1.5rem;
          border-bottom: 1px solid #f5f2ef;
        }
        .sp-identity {
          display: flex;
          gap: 1.25rem;
        }
        .sp-avatar {
          width: 64px;
          height: 64px;
          border-radius: 16px;
          background: #f5e6d3;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }
        .sp-initial {
          font-size: 1.75rem;
          font-weight: 700;
          color: #3d2314;
        }
        .sp-name {
          font-size: 1.5rem;
          font-weight: 600;
          margin: 0;
          letter-spacing: -0.02em;
          color: #1a1816;
        }
        .sp-info .sp-meta {
          font-size: 0.875rem;
          color: #5c5650;
          margin: 0.25rem 0 0;
        }
        .sp-tags {
          display: flex;
          gap: 0.375rem;
          margin-top: 0.625rem;
          flex-wrap: wrap;
        }
        .sp-tag {
          font-size: 0.625rem;
          font-weight: 600;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          padding: 0.25rem 0.5rem;
          border-radius: 4px;
        }
        .sp-tag.purple {
          background: #f4f0fa;
          color: #7c5fc4;
        }
        .sp-tag.coral {
          background: #fdf0ee;
          color: #e05d50;
        }
        .sp-grid {
          padding: 1.5rem;
        }
        .sp-section {
          margin-bottom: 1.5rem;
        }
        .sp-section-title {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #8a8279;
          margin: 0 0 0.75rem;
        }
        .sp-stats {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 1rem;
        }
        .sp-stat {
          text-align: center;
          padding: 1rem;
          background: #faf8f6;
          border-radius: 10px;
        }
        .sp-stat-value {
          display: block;
          font-size: 1.25rem;
          font-weight: 700;
          color: #1a1816;
        }
        .sp-stat-value.good { color: #2a9d8f; }
        .sp-stat-label {
          display: block;
          font-size: 0.6875rem;
          color: #8a8279;
          margin-top: 0.25rem;
        }
        .sp-team-text {
          font-size: 0.875rem;
          color: #5c5650;
          margin: 0;
        }
      </style>
    </template>
  };
}
// touched for re-index
