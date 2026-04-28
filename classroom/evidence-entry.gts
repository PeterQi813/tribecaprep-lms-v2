// Phase 0 - EvidenceEntry FieldDef
//
// Nested in LearningGoal.evidenceEntries. One EvidenceEntry represents a
// single observation/score that contributes to a goal's progress.
//
// Auto-appended by the Activity Entry Composer flow (Phase 3) when a teacher
// creates an ActivityEntry linked to a LearningGoal. Can also be added
// manually via the Learning Goal manager (Phase 4).

import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

export class EvidenceEntry extends FieldDef {
  static displayName = 'Evidence Entry';

  // Teacher fills these (directly or via Phase 3 AI composer)
  @field scoreNumerator = contains(NumberField);
  @field scoreDenominator = contains(NumberField);
  @field text = contains(StringField);
  @field author = contains(StringField);
  @field date = contains(StringField);
  @field sourceActivityEntryId = contains(StringField); // optional back-link

  // ---- Computed ----
  @field score = contains(StringField, {
    computeVia: function (this: EvidenceEntry) {
      if (this.scoreNumerator == null || this.scoreDenominator == null) return '';
      return `${this.scoreNumerator}/${this.scoreDenominator}`;
    },
  });

  @field scorePercent = contains(NumberField, {
    computeVia: function (this: EvidenceEntry) {
      if (!this.scoreDenominator || this.scoreDenominator === 0) return 0;
      return Math.round(((this.scoreNumerator ?? 0) / this.scoreDenominator) * 100);
    },
  });

  @field scoreRating = contains(StringField, {
    computeVia: function (this: EvidenceEntry) {
      if (!this.scoreDenominator || this.scoreDenominator === 0) return '';
      const pct = ((this.scoreNumerator ?? 0) / this.scoreDenominator) * 100;
      if (pct >= 80) return 'good';
      if (pct >= 60) return 'ok';
      return 'needs-improvement';
    },
  });

  // ---- Embedded view (used inside LearningGoal listing) ----
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ev-row'>
        <div class='ev-score ev-{{@model.scoreRating}}'>{{@model.score}}</div>
        <div class='ev-body'>
          <span class='ev-text'>{{@model.text}}</span>
          <span class='ev-meta'>{{@model.author}} · {{@model.date}}</span>
        </div>
      </div>
      <style scoped>
        .ev-row {
          display: flex;
          gap: 10px;
          padding: 10px 12px;
          background: #faf8f6;
          border-radius: 6px;
          font-family: system-ui, sans-serif;
        }
        .ev-score {
          font-size: 12px;
          font-weight: 700;
          padding: 4px 8px;
          border-radius: 4px;
          background: #f5f2ef;
          color: #5c5650;
          flex-shrink: 0;
          min-width: 48px;
          text-align: center;
        }
        .ev-score.ev-good { background: #e8f6f4; color: #2a9d8f; }
        .ev-score.ev-ok { background: #fdf6e8; color: #c08b30; }
        .ev-score.ev-needs-improvement { background: #fdeceb; color: #e05d50; }
        .ev-body { flex: 1; min-width: 0; }
        .ev-text {
          display: block;
          font-size: 13px;
          color: #1a1816;
          line-height: 1.4;
          margin-bottom: 2px;
        }
        .ev-meta {
          font-size: 11px;
          color: #8a8279;
        }
      </style>
    </template>
  };

  // ---- Edit view (used in containsMany editor) ----
  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='ev-edit'>
        <div class='ev-edit-row'>
          <div class='ev-edit-field'>
            <label>Score numerator</label>
            <@fields.scoreNumerator />
          </div>
          <div class='ev-edit-field'>
            <label>Score denominator</label>
            <@fields.scoreDenominator />
          </div>
        </div>
        <div class='ev-edit-field'>
          <label>Observation text</label>
          <@fields.text />
        </div>
        <div class='ev-edit-row'>
          <div class='ev-edit-field'>
            <label>Author</label>
            <@fields.author />
          </div>
          <div class='ev-edit-field'>
            <label>Date</label>
            <@fields.date />
          </div>
        </div>
      </div>
      <style scoped>
        .ev-edit {
          display: flex;
          flex-direction: column;
          gap: 10px;
          padding: 12px 14px;
          background: #faf8f6;
          border-radius: 8px;
        }
        .ev-edit-row { display: flex; gap: 12px; }
        .ev-edit-field {
          display: flex;
          flex-direction: column;
          gap: 3px;
          flex: 1;
        }
        .ev-edit-field label {
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          color: #718096;
          letter-spacing: 0.5px;
        }
      </style>
    </template>
  };
}
// touched for re-index
