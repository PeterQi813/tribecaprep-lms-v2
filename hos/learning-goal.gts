import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import enumField from 'https://cardstack.com/base/enum';
import TargetIcon from '@cardstack/boxel-icons/target';
import { Student } from './student';

const DomainField = enumField(StringField, {
  options: ['Math', 'Reading', 'Social', 'Behavioral', 'Motor', 'Communication'],
});

const PriorityField = enumField(StringField, {
  options: ['High', 'Medium', 'Low'],
});

export class LearningGoal extends CardDef {
  static displayName = 'Learning Goal';
  static icon = TargetIcon;

  @field goalTitle = contains(StringField);
  @field description = contains(StringField);
  @field domain = contains(DomainField);
  @field priority = contains(PriorityField);
  @field currentMastery = contains(NumberField);
  @field targetMastery = contains(NumberField);
  @field student = linksTo(Student);
  @field studentName = contains(StringField);  // flat name fallback for cross-realm mirrors

  @field title = contains(StringField, {
    computeVia: function (this: LearningGoal) {
      return this.goalTitle ?? 'Untitled Goal';
    },
  });

  static isolated = class Isolated extends Component<typeof LearningGoal> {
    get safeTitle() {
      return this.args.model?.goalTitle ?? 'Untitled Goal';
    }

    get safeDomain() {
      return this.args.model?.domain ?? 'Academic';
    }

    get safePriority() {
      return this.args.model?.priority ?? 'Medium';
    }

    get currentPct() {
      return this.args.model?.currentMastery ?? 0;
    }

    get targetPct() {
      return this.args.model?.targetMastery ?? 100;
    }

    get domainColor() {
      switch (this.safeDomain) {
        case 'Math': return '#e05d50';
        case 'Reading': return '#c08b30';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        case 'Motor': return '#2a9d8f';
        case 'Communication': return '#5c8fc4';
        default: return '#5c5650';
      }
    }

    get priorityColor() {
      switch (this.safePriority) {
        case 'High': return '#e05d50';
        case 'Medium': return '#c08b30';
        case 'Low': return '#2a9d8f';
        default: return '#8a8279';
      }
    }

    <template>
      <article class='goal-profile'>
        <header class='goal-header'>
          <span class='domain-badge' style='background-color: {{this.domainColor}}'>
            {{this.safeDomain}}
          </span>
          <span class='priority-badge' style='background-color: {{this.priorityColor}}'>
            {{this.safePriority}}
          </span>
        </header>

        <h1 class='goal-title'>{{this.safeTitle}}</h1>

        {{#if @model.description}}
          <p class='goal-description'>{{@model.description}}</p>
        {{/if}}

        <div class='progress-section'>
          <div class='progress-header'>
            <span class='progress-label'>Mastery Progress</span>
            <span class='progress-value'>{{this.currentPct}}%</span>
          </div>
          <div class='progress-bar'>
            <div class='progress-fill' style='width: {{this.currentPct}}%; background-color: {{this.domainColor}}'></div>
            <div class='progress-target' style='left: {{this.targetPct}}%'></div>
          </div>
          <div class='progress-footer'>
            <span>Current: {{this.currentPct}}%</span>
            <span>Target: {{this.targetPct}}%</span>
          </div>
        </div>

        {{#if @model.student}}
          <section class='section'>
            <h2 class='section-label'>Student</h2>
            <@fields.student @format='embedded' />
          </section>
        {{/if}}
      </article>

      <style scoped>
        .goal-profile {
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

        .goal-header {
          display: flex;
          gap: 0.5rem;
        }

        .domain-badge,
        .priority-badge {
          padding: 0.25rem 0.75rem;
          border-radius: 1rem;
          color: white;
          font-weight: 600;
          font-size: 0.6875rem;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .goal-title {
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          margin: 0;
          color: #1a1816;
        }

        .goal-description {
          font-size: var(--boxel-font-size);
          color: #5c5650;
          margin: 0;
          line-height: 1.5;
        }

        .progress-section {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .progress-header {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
        }

        .progress-label {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #5c5650;
        }

        .progress-value {
          font-size: 1.25rem;
          font-weight: 700;
          color: #1a1816;
        }

        .progress-bar {
          position: relative;
          height: 0.5rem;
          background: #ebe7e3;
          border-radius: 4px;
          overflow: visible;
        }

        .progress-fill {
          height: 100%;
          border-radius: 4px;
          transition: width 0.3s ease;
        }

        .progress-target {
          position: absolute;
          top: -3px;
          width: 2px;
          height: calc(100% + 6px);
          background: #1a1816;
          border-radius: 1px;
        }

        .progress-footer {
          display: flex;
          justify-content: space-between;
          font-size: 0.6875rem;
          color: #8a8279;
        }

        .section {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding-top: var(--boxel-sp);
          border-top: 1px solid var(--border);
        }

        .section-label {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #5c5650;
          margin: 0;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof LearningGoal> {
    get safeTitle() {
      return this.args.model?.goalTitle ?? 'Untitled Goal';
    }

    get safeDomain() {
      return this.args.model?.domain ?? 'Academic';
    }

    get currentPct() {
      return this.args.model?.currentMastery ?? 0;
    }

    get domainColor() {
      switch (this.safeDomain) {
        case 'Math': return '#e05d50';
        case 'Reading': return '#c08b30';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        case 'Motor': return '#2a9d8f';
        case 'Communication': return '#5c8fc4';
        default: return '#5c5650';
      }
    }

    <template>
      <div class='goal-embedded'>
        <div class='goal-top'>
          <span class='domain-pill' style='background-color: {{this.domainColor}}'>
            {{this.safeDomain}}
          </span>
          <span class='pct'>{{this.currentPct}}%</span>
        </div>
        <div class='goal-name'>{{this.safeTitle}}</div>
        <div class='bar'>
          <div class='bar-fill' style='width: {{this.currentPct}}%; background-color: {{this.domainColor}}'></div>
        </div>
      </div>

      <style scoped>
        .goal-embedded {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          padding: 0.625rem;
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: 8px;
          height: 100%;
        }

        .goal-top {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .domain-pill {
          padding: 0.125rem 0.5rem;
          border-radius: 1rem;
          color: white;
          font-weight: 700;
          font-size: 0.5625rem;
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }

        .pct {
          font-size: 0.875rem;
          font-weight: 700;
          color: #1a1816;
        }

        .goal-name {
          font-size: 0.8125rem;
          font-weight: 600;
          color: #1a1816;
          line-height: 1.3;
        }

        .bar {
          height: 4px;
          background: #ebe7e3;
          border-radius: 2px;
        }

        .bar-fill {
          height: 100%;
          border-radius: 2px;
          transition: width 0.3s ease;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof LearningGoal> {
    get safeTitle() {
      return this.args.model?.goalTitle ?? 'Goal';
    }

    get safeDomain() {
      return this.args.model?.domain ?? 'Academic';
    }

    get currentPct() {
      return this.args.model?.currentMastery ?? 0;
    }

    get domainColor() {
      switch (this.safeDomain) {
        case 'Math': return '#e05d50';
        case 'Reading': return '#c08b30';
        case 'Social': return '#7c5fc4';
        case 'Behavioral': return '#c08b30';
        case 'Motor': return '#2a9d8f';
        case 'Communication': return '#5c8fc4';
        default: return '#5c5650';
      }
    }

    <template>
      <div class='fitted-container'>
        <div class='tile' style='border-left: 3px solid {{this.domainColor}}'>
          <span class='pct'>{{this.currentPct}}%</span>
          <span class='title'>{{this.safeTitle}}</span>
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

        .pct {
          font-size: 1.5rem;
          font-weight: 700;
          color: #1a1816;
        }

        .title {
          font-size: var(--boxel-font-size-xs);
          color: #5c5650;
          text-align: center;
          line-height: 1.3;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof LearningGoal> {
    <template>
      <div class='card-edit'>
        <div class='field-row'>
          <label>Goal Title</label>
          <@fields.goalTitle />
        </div>
        <div class='field-row'>
          <label>Description</label>
          <@fields.description />
        </div>
        <div class='field-row'>
          <label>Domain</label>
          <@fields.domain />
        </div>
        <div class='field-row'>
          <label>Priority</label>
          <@fields.priority />
        </div>
        <div class='field-row'>
          <label>Current Mastery (%)</label>
          <@fields.currentMastery />
        </div>
        <div class='field-row'>
          <label>Target Mastery (%)</label>
          <@fields.targetMastery />
        </div>
        <div class='field-row'>
          <label>Student</label>
          <@fields.student />
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

