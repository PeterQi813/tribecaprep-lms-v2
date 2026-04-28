// Tribeca Prep LMS — Shared Enums
// All stored as { "value": "string" } in JSON
// Used across Student Profile, LearningGoal, Observation, DailyReport, etc.

import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

// ─── Grade Level ───
// Values: Pre-K, K, 1st, 2nd, 3rd, 4th, 5th, 6th, 7th, 8th, 9th, 10th, 11th, 12th
export class GradeLevel extends FieldDef {
  static displayName = 'Grade Level';

  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='grade'><@fields.value /></span>
      <style scoped>
        .grade {
          font-size: 0.875rem;
          font-weight: 500;
          color: var(--muted-foreground, #6c6a81);
        }
      </style>
    </template>
  };
}

// ─── Mastery Level ───
// 5-point scale used by LearningGoal, Observation, Progress Charts
// Values: emerging, developing, approaching, meeting, mastered
export class MasteryLevel extends FieldDef {
  static displayName = 'Mastery Level';

  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    get levelNum(): number {
      const map: Record<string, number> = {
        emerging: 1,
        developing: 2,
        approaching: 3,
        meeting: 4,
        mastered: 5,
      };
      return map[this.args.model.value?.toLowerCase() ?? ''] ?? 0;
    }

    get colorClass(): string {
      const n = this.levelNum;
      if (n >= 5) return 'mastered';
      if (n >= 4) return 'meeting';
      if (n >= 3) return 'approaching';
      if (n >= 2) return 'developing';
      return 'emerging';
    }

    <template>
      <span class='mastery {{this.colorClass}}'>
        <span class='mastery-dot'></span>
        <@fields.value />
      </span>
      <style scoped>
        .mastery {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          padding: 0.1875rem 0.5rem;
          font-size: 0.6875rem;
          font-weight: 600;
          border-radius: 4px;
          text-transform: capitalize;
        }
        .mastery-dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
        }
        .mastery.emerging { background: #fdf0ee; color: #e05d50; }
        .mastery.emerging .mastery-dot { background: #e05d50; }
        .mastery.developing { background: #fdf6e8; color: #c08b30; }
        .mastery.developing .mastery-dot { background: #c08b30; }
        .mastery.approaching { background: #f4f0fa; color: #7c5fc4; }
        .mastery.approaching .mastery-dot { background: #7c5fc4; }
        .mastery.meeting { background: #e8f6f4; color: #2a9d8f; }
        .mastery.meeting .mastery-dot { background: #2a9d8f; }
        .mastery.mastered { background: #e8f6f4; color: #1a7a6e; }
        .mastery.mastered .mastery-dot { background: #1a7a6e; }
      </style>
    </template>
  };
}

// ─── Subject / Domain ───
// Values: mathematics, ela, science, social-studies, art, music, pe, social-emotional, other
export class Subject extends FieldDef {
  static displayName = 'Subject';

  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    get colorClass(): string {
      const map: Record<string, string> = {
        mathematics: 'coral',
        ela: 'purple',
        reading: 'purple',
        science: 'teal',
        'social-studies': 'amber',
        art: 'purple',
        music: 'teal',
        pe: 'amber',
        'social-emotional': 'purple',
      };
      return map[this.args.model.value?.toLowerCase() ?? ''] ?? 'neutral';
    }

    <template>
      <span class='subject {{this.colorClass}}'><@fields.value /></span>
      <style scoped>
        .subject {
          display: inline-flex;
          padding: 0.1875rem 0.5rem;
          font-size: 0.6875rem;
          font-weight: 600;
          border-radius: 4px;
          text-transform: capitalize;
        }
        .subject.coral { background: #fdf0ee; color: #e05d50; }
        .subject.purple { background: #f4f0fa; color: #7c5fc4; }
        .subject.teal { background: #e8f6f4; color: #2a9d8f; }
        .subject.amber { background: #fdf6e8; color: #c08b30; }
        .subject.neutral { background: #f5f2ef; color: #5c5650; }
      </style>
    </template>
  };
}

// ─── Observation Category ───
// Values: academic, social-emotional, physical, communication, behavioral, adaptive
export class ObservationCategory extends FieldDef {
  static displayName = 'Observation Category';

  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='obs-cat'><@fields.value /></span>
      <style scoped>
        .obs-cat {
          font-size: 0.75rem;
          font-weight: 500;
          color: #5c5650;
          text-transform: capitalize;
        }
      </style>
    </template>
  };
}

// ─── Priority ───
// Values: low, medium, high, critical
export class Priority extends FieldDef {
  static displayName = 'Priority';

  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    get colorClass(): string {
      const map: Record<string, string> = {
        critical: 'critical',
        high: 'high',
        medium: 'medium',
        low: 'low',
      };
      return map[this.args.model.value?.toLowerCase() ?? ''] ?? 'low';
    }

    <template>
      <span class='priority {{this.colorClass}}'><@fields.value /></span>
      <style scoped>
        .priority {
          display: inline-flex;
          padding: 0.125rem 0.375rem;
          font-size: 0.625rem;
          font-weight: 600;
          border-radius: 3px;
          text-transform: uppercase;
          letter-spacing: 0.03em;
        }
        .priority.critical { background: #fdf0ee; color: #e05d50; }
        .priority.high { background: #fdf6e8; color: #c08b30; }
        .priority.medium { background: #f4f0fa; color: #7c5fc4; }
        .priority.low { background: #f5f2ef; color: #8a8279; }
      </style>
    </template>
  };
}
// touched for re-index
