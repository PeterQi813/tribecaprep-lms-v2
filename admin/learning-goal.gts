import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
// File upload will use URL strings for now (FileDef import path TBD)
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { StudentCard } from './student-card';

const LEVEL_NAMES = ['Emerging', 'Developing', 'Approaching', 'Proficient', 'Mastered'];

// ── Contained types ──────────────────────────────────────────────────

export class InstructionalMaterial extends FieldDef {
  static displayName = 'Instructional Material';
  @field materialType = contains(StringField); // "Primary" | "Secondary"
  @field name = contains(StringField);
  @field detail = contains(StringField);
  @field attachmentUrl = contains(StringField); // URL to file (Google Drive, etc.)
}

export class EvidenceEntry extends FieldDef {
  static displayName = 'Evidence Entry';
  @field score = contains(StringField);    // e.g. "18/20"
  @field text = contains(StringField);
  @field staff = contains(StringField);    // e.g. "Ms. Rivers"
  @field date = contains(StringField);     // e.g. "Today, 10:23 AM"

  @field scoreRating = contains(StringField, {
    computeVia: function (this: EvidenceEntry) {
      if (!this.score) return '';
      const m = this.score.match(/^(\d+)\/(\d+)$/);
      if (!m) return '';
      const pct = parseInt(m[1]) / parseInt(m[2]);
      if (pct >= 0.8) return 'good';
      if (pct >= 0.6) return 'ok';
      return 'low';
    },
  });
}

// ── Main CardDef ─────────────────────────────────────────────────────

export class LearningGoal extends CardDef {
  static displayName = 'Learning Goal';

  @field goalTitle = contains(StringField);
  @field description = contains(StringField);
  @field student = linksTo(StudentCard);
  @field studentName = contains(StringField); // display name for the assigned student
  @field domain = contains(StringField);
  @field priority = contains(StringField);
  @field currentMastery = contains(NumberField);
  @field targetMastery = contains(NumberField);
  @field dueDate = contains(DateField);
  @field standardAlignment = contains(StringField);
  @field materials = containsMany(InstructionalMaterial);
  @field evidence = containsMany(EvidenceEntry);

  @field progressPercent = contains(NumberField, {
    computeVia: function (this: LearningGoal) {
      // currentMastery and targetMastery are 0-100 percentages, cap at 100
      return Math.min(100, this.currentMastery ?? 0);
    },
  });

  @field daysRemaining = contains(NumberField, {
    computeVia: function (this: LearningGoal) {
      if (!this.dueDate) return 0;
      const due = new Date(this.dueDate);
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const diff = due.getTime() - today.getTime();
      return Math.ceil(diff / (1000 * 60 * 60 * 24));
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: LearningGoal) {
      return this.goalTitle || 'Untitled Goal';
    },
  });

  // ── Isolated View ──────────────────────────────────────────────────
  static isolated = class Isolated extends Component<typeof this> {
    get domainColor() {
      const d = this.args.model.domain || '';
      if (d.includes('Math')) return 'coral';
      if (d.includes('Reading')) return 'teal';
      if (d.includes('Language')) return 'amber';
      if (d.includes('Receptive')) return 'amber';
      if (d.includes('Social')) return 'purple';
      if (d.includes('Behavior')) return 'orange';
      if (d.includes('Fine Motor')) return 'green';
      return 'teal';
    }

    get isHighPriority() { return this.args.model.priority === 'High'; }
    get isMediumPriority() { return this.args.model.priority === 'Medium'; }

    get masteryLevels() {
      const current = this.args.model.currentMastery || 0;
      const target = this.args.model.targetMastery || 4;
      const levels = [];
      for (let i = 1; i <= 5; i++) {
        let cls = '';
        if (i < current) cls = 'filled';
        else if (i === current) cls = 'current';
        else if (i === target) cls = 'target';
        levels.push({ num: i, name: LEVEL_NAMES[i - 1], cls, isCurrent: i === current, isTarget: i === target });
      }
      return levels;
    }

    get progressWidth() {
      return htmlSafe(`width: ${this.args.model.progressPercent || 0}%`);
    }

    get targetLevelName() {
      const t = this.args.model.targetMastery || 4;
      return LEVEL_NAMES[t - 1] || '';
    }

    get formattedDueDate() {
      const d = this.args.model.dueDate;
      if (!d) return '';
      const date = new Date(d);
      return date.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    }

    get hasMaterials() {
      return (this.args.model.materials || []).length > 0;
    }

    get hasEvidence() {
      return (this.args.model.evidence || []).length > 0;
    }

    get evidenceCount() {
      return (this.args.model.evidence || []).length;
    }

    get evidencePreview() {
      return (this.args.model.evidence || []).slice(0, 3);
    }

    get scoreColor() {
      return (score: string) => {
        if (!score) return '';
        const m = score.match(/^(\d+)\/(\d+)$/);
        if (!m) return '';
        const pct = parseInt(m[1]) / parseInt(m[2]);
        if (pct >= 0.85) return 'score-high';
        if (pct >= 0.7) return 'score-mid';
        return 'score-low';
      };
    }

    isPrimary = (mat: any) => (mat.materialType || '').toLowerCase() === 'primary';

    @tracked showAllEvidence = false;

    get hasMoreEvidence() {
      return (this.args.model.evidence || []).length > 3;
    }

    get evidencePreview() {
      const all = this.args.model.evidence || [];
      return this.showAllEvidence ? all : all.slice(0, 3);
    }

    toggleAllEvidence = () => { this.showAllEvidence = !this.showAllEvidence; };

    <template>
      <div class='goal-card'>
        <a class='back-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/AdminDashboard/main'>← Back to Admin Dashboard</a>

        {{!-- Domain + Priority row --}}
        <div class='goal-header'>
          <div class='goal-domain {{this.domainColor}}'>
            <svg class='domain-icon' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='8' r='6'/><line x1='8' y1='5' x2='8' y2='11'/><line x1='5' y1='8' x2='11' y2='8'/></svg>
            {{@model.domain}}
          </div>
          {{#if this.isHighPriority}}
            <div class='goal-priority high'>
              <svg class='priority-star' viewBox='0 0 12 12' fill='currentColor'><polygon points='6,1 7.5,4.5 11,5 8.5,7.5 9,11 6,9.5 3,11 3.5,7.5 1,5 4.5,4.5'/></svg>
              High Priority
            </div>
          {{else if this.isMediumPriority}}
            <div class='goal-priority medium'>
              <svg class='priority-star' viewBox='0 0 12 12' fill='currentColor'><polygon points='6,1 7.5,4.5 11,5 8.5,7.5 9,11 6,9.5 3,11 3.5,7.5 1,5 4.5,4.5'/></svg>
              Medium Priority
            </div>
          {{/if}}
        </div>

        {{!-- Title + Description --}}
        <h2 class='goal-title'>{{@model.goalTitle}}</h2>
        {{#if @model.studentName}}
          <div class='goal-student-badge'>
            <svg viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='1.5' width='14' height='14'><circle cx='7' cy='5' r='3'/><path d='M2 13c0-3 2-5 5-5s5 2 5 5'/></svg>
            {{@model.studentName}}
          </div>
        {{/if}}
        {{#if @model.description}}
          <p class='goal-desc'>{{@model.description}}</p>
        {{/if}}

        {{!-- Linked Student Card --}}
        {{#if @model.student}}
          <div class='student-section'>
            <div class='section-label-row'>
              <svg class='section-icon' viewBox='0 0 14 14' fill='none' stroke='#8a8279' stroke-width='1.5'><path d='M6 8a3 3 0 004 1l1-1a3 3 0 000-4l-1-1a3 3 0 00-4 0'/><path d='M8 6a3 3 0 00-4-1L3 6a3 3 0 000 4l1 1a3 3 0 004 0'/></svg>
              <span class='section-label-text'>Linked Student</span>
            </div>
            <@fields.student @format='embedded' />
          </div>
        {{/if}}

        {{!-- Mastery Level --}}
        <div class='mastery-section'>
          <div class='mastery-header'>
            <span class='mastery-label'>Mastery Level</span>
            <span class='mastery-target-label'>Target: {{@model.targetMastery}} ({{this.targetLevelName}})</span>
          </div>
          <div class='mastery-boxes'>
            {{#each this.masteryLevels as |level|}}
              <div class='mastery-box {{level.cls}}'>
                <span class='box-num'>{{level.num}}</span>
                <span class='box-name'>{{level.name}}</span>
                {{#if level.isCurrent}}
                  <span class='box-indicator current-ind'>Current</span>
                {{/if}}
                {{#if level.isTarget}}
                  <span class='box-indicator target-ind'>Target</span>
                {{/if}}
              </div>
            {{/each}}
          </div>

          <div class='progress-row'>
            <div class='progress-track'>
              <div class='progress-fill' style={{this.progressWidth}}>
                <div class='progress-dot'></div>
              </div>
            </div>
            <span class='progress-pct'>{{@model.progressPercent}}%</span>
          </div>
        </div>

        {{!-- Standard Alignment + Due Date --}}
        <div class='meta-grid'>
          {{#if @model.standardAlignment}}
            <div class='meta-box'>
              <span class='meta-box-label'>Standard Alignment</span>
              <div class='meta-box-value standard-val'>
                <svg class='meta-check' viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='1.5'><rect x='2' y='2' width='10' height='10' rx='2'/><polyline points='4.5 7 6.5 9 9.5 5'/></svg>
                {{@model.standardAlignment}}
              </div>
            </div>
          {{/if}}
          <div class='meta-box'>
            <span class='meta-box-label'>Due Date</span>
            <div class='meta-box-value date-val'>
              {{this.formattedDueDate}}
              {{#if @model.daysRemaining}}
                <span class='days-badge'>{{@model.daysRemaining}} days</span>
              {{/if}}
            </div>
          </div>
        </div>

        {{!-- Instructional Materials --}}
        <div class='materials-section'>
          <div class='section-header-row'>
            <div class='section-header-left'>
              <svg class='section-icon' viewBox='0 0 16 16' fill='none' stroke='#5c5650' stroke-width='1.5'><rect x='2' y='2' width='12' height='12' rx='2'/><line x1='5' y1='6' x2='11' y2='6'/><line x1='5' y1='9' x2='9' y2='9'/></svg>
              <span class='section-header-text'>Instructional Materials</span>
            </div>
            <span class='section-badge'>containsMany</span>
          </div>
          {{#if this.hasMaterials}}
            <div class='mat-list'>
              {{#each @model.materials as |mat|}}
                <div class='mat-item {{if (this.isPrimary mat) "primary"}}'>
                  <span class='mat-type-tag {{if (this.isPrimary mat) "primary" "secondary"}}'>
                    {{#if (this.isPrimary mat)}}Primary{{else}}Secondary{{/if}}
                  </span>
                  <span class='mat-name'>{{mat.name}}</span>
                  {{#if mat.detail}}<span class='mat-detail'>{{mat.detail}}</span>{{/if}}
                </div>
              {{/each}}
            </div>
          {{else}}
            <div class='empty-hint'>No materials added yet. Use the pencil icon to edit.</div>
          {{/if}}
        </div>

        {{!-- Linked Evidence --}}
        <div class='evidence-section'>
          <div class='section-header-row'>
            <div class='section-header-left'>
              <svg class='section-icon' viewBox='0 0 16 16' fill='none' stroke='#5c5650' stroke-width='1.5'><line x1='3' y1='4' x2='13' y2='4'/><line x1='3' y1='8' x2='13' y2='8'/><line x1='3' y1='12' x2='13' y2='12'/></svg>
              <span class='section-header-text'>Linked Evidence</span>
            </div>
            <span class='evidence-count'>{{this.evidenceCount}} entries</span>
          </div>
          {{#if this.hasEvidence}}
            <div class='ev-list'>
              {{#each this.evidencePreview as |ev|}}
                <div class='ev-item'>
                  <div class='ev-score {{ev.scoreRating}}'>{{ev.score}}</div>
                  <div class='ev-body'>
                    <span class='ev-text'>{{ev.text}}</span>
                    <span class='ev-meta'>{{ev.staff}} · {{ev.date}}</span>
                  </div>
                </div>
              {{/each}}
            </div>
            {{#if this.hasMoreEvidence}}
              <button class='ev-more-btn' type='button' {{on 'click' this.toggleAllEvidence}}>
                {{#if this.showAllEvidence}}Show less{{else}}View all {{this.evidenceCount}} entries{{/if}}
              </button>
            {{/if}}
          {{else}}
            <div class='empty-hint'>No evidence yet. Scores will appear here after teachers record activities in the classroom.</div>
          {{/if}}
        </div>

        {{!-- Actions --}}
        <div class='goal-actions'>
          <a class='action-btn edit-btn' href='{{@model.id}}'>
            <svg viewBox='0 0 14 14' fill='none' stroke='currentColor' stroke-width='1.5' width='14' height='14'><path d='M10 2l2 2-7 7H3V9l7-7z'/></svg>
            Edit Goal
          </a>
        </div>
      </div>

      <style scoped>
        .back-link {
          display: inline-block;
          padding: 0.5rem 0;
          font-size: 0.8125rem;
          font-weight: 600;
          color: #7c5fc4;
          text-decoration: none;
        }
        .back-link:hover { text-decoration: underline; }
        .goal-card {
          padding: 2rem;
          background: #fffdfb;
          border-radius: 14px;
          box-shadow: 0 4px 12px rgba(26,24,22,0.06);
          max-width: 800px;
          margin: 0 auto;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }

        /* ── Header ── */
        .goal-header { display: flex; justify-content: space-between; align-items: center; }
        .goal-domain {
          display: flex; align-items: center; gap: 0.375rem;
          font-size: 0.6875rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.06em;
        }
        .domain-icon { width: 14px; height: 14px; }
        .goal-domain.coral { color: #e05d50; }
        .goal-domain.purple { color: #7c5fc4; }
        .goal-domain.teal { color: #2a9d8f; }
        .goal-domain.amber { color: #c08b30; }
        .goal-domain.orange { color: #d97706; }
        .goal-domain.green { color: #059669; }
        .goal-priority {
          display: flex; align-items: center; gap: 0.3rem;
          font-size: 0.625rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.04em;
          padding: 0.3rem 0.625rem; border-radius: 4px;
        }
        .priority-star { width: 10px; height: 10px; }
        .goal-priority.high { background: #fdf6e8; color: #c08b30; }
        .goal-priority.medium { background: #f0f4ff; color: #5b7bc0; }

        /* ── Title / Description ── */
        .goal-title {
          font-size: 1.5rem; font-weight: 600; margin: 0;
          letter-spacing: -0.01em; color: #1a1816; line-height: 1.3;
        }
        .goal-student-badge {
          display: inline-flex; align-items: center; gap: 0.375rem;
          font-size: 0.8125rem; font-weight: 600; color: #7c5fc4;
          padding: 0.25rem 0.625rem; background: rgba(124,95,196,0.08);
          border-radius: 1rem; margin-top: 0.25rem;
        }
        .goal-desc {
          font-size: 0.9375rem; color: #5c5650;
          line-height: 1.6; margin: 0;
        }

        /* ── Student ── */
        .student-section { display: flex; flex-direction: column; gap: 0.5rem; }
        .section-label-row {
          display: flex; align-items: center; gap: 0.375rem;
          font-size: 0.625rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.08em; color: #8a8279;
        }
        .section-icon { width: 14px; height: 14px; flex-shrink: 0; }

        /* ── Mastery Level ── */
        .mastery-section { display: flex; flex-direction: column; gap: 0.75rem; }
        .mastery-header { display: flex; justify-content: space-between; align-items: center; }
        .mastery-label {
          font-size: 0.6875rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.08em; color: #5c5650;
        }
        .mastery-target-label { font-size: 0.6875rem; color: #5c5650; }
        .mastery-boxes { display: flex; gap: 0.25rem; }
        .mastery-box {
          flex: 1; padding: 0.75rem 0.375rem 0.5rem;
          background: #f5f2ef; border-radius: 8px;
          text-align: center; position: relative;
        }
        .mastery-box.filled { background: #e8f6f4; }
        .mastery-box.current { background: #2a9d8f; color: white; }
        .mastery-box.target { border: 2px dashed #c08b30; background: #fdf6e8; }
        .box-num { display: block; font-size: 1.125rem; font-weight: 700; }
        .box-name {
          display: block; font-size: 0.5rem;
          text-transform: uppercase; letter-spacing: 0.04em; margin-top: 0.125rem;
        }
        .box-indicator {
          display: block; font-size: 0.5rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.04em; margin-top: 0.375rem;
        }
        .current-ind { color: #2a9d8f; }
        .mastery-box.current .current-ind { color: white; }
        .target-ind { color: #c08b30; }

        /* ── Progress Bar ── */
        .progress-row { display: flex; align-items: center; gap: 0.75rem; }
        .progress-track {
          flex: 1; height: 10px; background: #f5f2ef;
          border-radius: 5px; position: relative; overflow: visible;
        }
        .progress-fill {
          height: 100%; background: #2a9d8f; border-radius: 5px;
          position: relative; min-width: 10px; transition: width 0.3s;
        }
        .progress-dot {
          position: absolute; right: -6px; top: -4px;
          width: 18px; height: 18px; border-radius: 50%;
          background: #2a9d8f; border: 3px solid white;
          box-shadow: 0 1px 3px rgba(0,0,0,0.15);
        }
        .progress-pct {
          font-size: 1.375rem; font-weight: 700; color: #2a9d8f;
          min-width: 3.5rem; text-align: right;
        }

        /* ── Meta Grid ── */
        .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
        .meta-box {
          padding: 1rem; background: #faf8f6; border-radius: 8px;
          display: flex; flex-direction: column; gap: 0.375rem;
        }
        .meta-box-label {
          font-size: 0.5625rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.08em; color: #8a8279;
        }
        .meta-box-value { font-size: 0.9375rem; color: #1a1816; }
        .standard-val {
          color: #7c5fc4; font-weight: 600;
          display: flex; align-items: center; gap: 0.375rem;
        }
        .meta-check { width: 14px; height: 14px; flex-shrink: 0; }
        .date-val {
          font-size: 1.0625rem; font-weight: 600;
          display: flex; align-items: baseline; gap: 0.5rem;
        }
        .days-badge { font-size: 0.8125rem; font-weight: 400; color: #8a8279; }

        /* ── Instructional Materials ── */
        .materials-section { display: flex; flex-direction: column; gap: 0.75rem; border-top: 1px solid #f5f2ef; padding-top: 1.25rem; }
        .section-header-row { display: flex; justify-content: space-between; align-items: center; }
        .section-header-left { display: flex; align-items: center; gap: 0.375rem; }
        .section-header-text {
          font-size: 0.6875rem; font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.08em; color: #5c5650;
        }
        .section-badge {
          font-size: 0.5rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.04em; padding: 0.15rem 0.5rem; border-radius: 3px;
        }
        .section-badge.purple { background: #f4f0fa; color: #7c5fc4; }
        /* ── Materials list ── */
        .mat-list { display: flex; flex-direction: column; gap: 0.5rem; }
        .mat-item {
          display: flex; align-items: center; gap: 0.75rem;
          padding: 0.875rem 1rem; border-radius: 8px;
          background: #fffdfb; border: 1px solid #f5f2ef;
        }
        .mat-item.primary { background: #fdf8f4; border-color: #f0e2d0; }
        .mat-type-tag {
          font-size: 0.5625rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.04em; padding: 0.15rem 0.4rem; border-radius: 3px;
          flex-shrink: 0;
        }
        .mat-type-tag.primary { background: #fdf0ee; color: #e05d50; }
        .mat-type-tag.secondary { background: #f5f2ef; color: #8a8279; }
        .mat-name { font-size: 0.9375rem; font-weight: 600; color: #1a1816; flex: 1; }
        .mat-detail { font-size: 0.8125rem; color: #8a8279; flex-shrink: 0; }
        .empty-hint { font-size: 0.8125rem; color: #8a8279; font-style: italic; }

        /* ── Linked Evidence ── */
        .evidence-section { display: flex; flex-direction: column; gap: 0.75rem; border-top: 1px solid #f5f2ef; padding-top: 1.25rem; }
        .evidence-count { font-size: 0.75rem; font-weight: 600; color: #2a9d8f; }
        .ev-list { display: flex; flex-direction: column; gap: 0.5rem; }
        .ev-item {
          display: flex; align-items: flex-start; gap: 0.875rem;
          padding: 0.875rem 1rem; border-radius: 8px;
          background: #fffdfb; border: 1px solid #f5f2ef;
        }
        .ev-score {
          font-size: 0.9375rem; font-weight: 700; flex-shrink: 0;
          min-width: 3.5rem; text-align: center;
          padding: 0.25rem 0.5rem; border-radius: 6px;
        }
        .ev-score.good { background: #e8f6f4; color: #2a9d8f; }
        .ev-score.ok { background: #fdf6e8; color: #c08b30; }
        .ev-score.low { background: #fdeceb; color: #e05d50; }
        .ev-body { flex: 1; display: flex; flex-direction: column; gap: 0.25rem; }
        .ev-text { font-size: 0.9375rem; color: #1a1816; line-height: 1.5; }
        .ev-meta { font-size: 0.8125rem; color: #8a8279; }
        .ev-more-btn {
          text-align: center; padding: 0.75rem;
          border: 1px dashed #e5e2df; border-radius: 8px;
          font-size: 0.8125rem; color: #8a8279;
          cursor: pointer; background: none; font-family: inherit; width: 100%;
        }
        .ev-more-btn:hover { background: #faf8f6; }

        /* ── Actions ── */
        .goal-actions {
          display: flex; justify-content: flex-end; gap: 0.75rem;
          border-top: 1px solid #f5f2ef; padding-top: 1.25rem;
        }
        .action-btn {
          display: inline-flex; align-items: center; gap: 0.375rem;
          padding: 0.625rem 1.25rem; border-radius: 8px;
          font-size: 0.875rem; font-weight: 600;
          cursor: pointer; font-family: inherit; border: none;
          text-decoration: none;
          transition: background 0.15s, box-shadow 0.15s;
        }
        .edit-btn {
          background: white; color: #1a1816;
          border: 1px solid #e5e2df;
        }
        .btn-edit-goal:hover { background: #faf8f6; box-shadow: 0 2px 6px rgba(0,0,0,0.05); }
        .btn-add-obs {
          background: #e05d50; color: white;
        }
        .btn-add-obs:hover { background: #cc4f43; }
      </style>
    </template>
  };

  // ── Fitted View ────────────────────────────────────────────────────
  static fitted = class Fitted extends Component<typeof this> {
    get domainColor() {
      const d = this.args.model.domain || '';
      if (d.includes('Math')) return 'coral';
      if (d.includes('Reading')) return 'teal';
      if (d.includes('Language') || d.includes('Receptive')) return 'amber';
      if (d.includes('Social')) return 'purple';
      return 'teal';
    }

    get isHighPriority() { return this.args.model.priority === 'High'; }

    <template>
      <div class='goal-fitted {{if this.isHighPriority "priority"}}'>
        {{#if this.isHighPriority}}
          <div class='gf-priority-badge'>High</div>
        {{/if}}
        <div class='gf-domain {{this.domainColor}}'>{{@model.domain}}</div>
        <h4 class='gf-title'>{{@model.goalTitle}}</h4>
        <div class='gf-mastery'>
          <div class='gf-track'>
            <div class='gf-fill' style='width:{{@model.progressPercent}}%'></div>
          </div>
          <span class='gf-pct'>{{@model.progressPercent}}%</span>
        </div>
      </div>
      <style scoped>
        .goal-fitted {
          padding: 1rem; background: #fffdfb; border-radius: 10px;
          box-shadow: 0 1px 2px rgba(26,24,22,0.04); position: relative;
          cursor: pointer; transition: box-shadow 0.15s, transform 0.1s;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .goal-fitted:hover { box-shadow: 0 4px 12px rgba(26,24,22,0.06); transform: translateY(-1px); }
        .goal-fitted.priority { background: #fdf6e8; }
        .gf-priority-badge {
          position: absolute; top: 0.75rem; right: 0.75rem;
          font-size: 0.5rem; font-weight: 700; text-transform: uppercase;
          letter-spacing: 0.04em; padding: 0.125rem 0.375rem; border-radius: 3px;
          background: #fdf6e8; color: #c08b30;
        }
        .gf-domain {
          font-size: 0.625rem; font-weight: 600; text-transform: uppercase;
          letter-spacing: 0.04em; margin-bottom: 0.5rem;
        }
        .gf-domain.coral { color: #e05d50; }
        .gf-domain.purple { color: #7c5fc4; }
        .gf-domain.teal { color: #2a9d8f; }
        .gf-domain.amber { color: #c08b30; }
        .gf-title { font-size: 0.875rem; font-weight: 600; margin: 0 0 0.75rem; line-height: 1.3; color: #1a1816; }
        .gf-mastery { display: flex; align-items: center; gap: 0.5rem; }
        .gf-track { flex: 1; height: 6px; background: #f5f2ef; border-radius: 3px; overflow: hidden; }
        .gf-fill { height: 100%; background: #2a9d8f; border-radius: 3px; }
        .gf-pct { font-size: 0.75rem; font-weight: 700; color: #2a9d8f; }
      </style>
    </template>
  };

  // ── Embedded View ──────────────────────────────────────────────────
  static embedded = class Embedded extends Component<typeof this> {
    get domainColor() {
      const d = this.args.model.domain || '';
      if (d.includes('Math')) return 'coral';
      if (d.includes('Reading')) return 'teal';
      if (d.includes('Language') || d.includes('Receptive')) return 'amber';
      if (d.includes('Social')) return 'purple';
      return 'teal';
    }

    <template>
      <div class='goal-embedded'>
        <span class='ge-domain {{this.domainColor}}'>{{@model.domain}}</span>
        <span class='ge-title'>{{@model.goalTitle}}</span>
        <span class='ge-mastery'>Level {{@model.currentMastery}} / {{@model.targetMastery}} &middot; {{@model.progressPercent}}%</span>
      </div>
      <style scoped>
        .goal-embedded { display: flex; align-items: center; gap: 0.5rem; padding: 0.75rem; font-family: 'Inter', system-ui, -apple-system, sans-serif; }
        .ge-domain { font-size: 0.5625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; flex-shrink: 0; }
        .ge-domain.coral { color: #e05d50; }
        .ge-domain.purple { color: #7c5fc4; }
        .ge-domain.teal { color: #2a9d8f; }
        .ge-domain.amber { color: #c08b30; }
        .ge-title { font-size: 0.875rem; font-weight: 500; color: #1a1816; flex: 1; }
        .ge-mastery { font-size: 0.6875rem; color: #8a8279; flex-shrink: 0; }
      </style>
    </template>
  };

  // ── Edit View ──────────────────────────────────────────────────────
  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='goal-edit'>
        <div class='field-row'><label>Goal Title</label><@fields.goalTitle /></div>
        <div class='field-row'><label>Description</label><@fields.description /></div>
        <div class='field-row'><label>Student</label><@fields.student /></div>
        <div class='field-row'><label>Domain</label><@fields.domain /></div>
        <div class='field-row'><label>Priority</label><@fields.priority /></div>
        <div class='field-row-pair'>
          <div class='field-row'><label>Current Mastery (1-5)</label><@fields.currentMastery /></div>
          <div class='field-row'><label>Target Mastery (1-5)</label><@fields.targetMastery /></div>
        </div>
        <div class='field-row'><label>Due Date</label><@fields.dueDate /></div>
        <div class='field-row'><label>Standard Alignment</label><@fields.standardAlignment /></div>
        <div class='field-row'><label>Instructional Materials</label><@fields.materials /></div>
        <div class='field-row'><label>Linked Evidence</label><@fields.evidence /></div>
      </div>
      <style scoped>
        .goal-edit { display: flex; flex-direction: column; gap: var(--boxel-sp-sm); padding: var(--boxel-sp); font-family: 'Inter', system-ui, sans-serif; }
        .field-row { display: flex; flex-direction: column; gap: 0.25rem; }
        .field-row label { font-size: 0.6875rem; font-weight: 600; color: #8a8279; text-transform: uppercase; letter-spacing: 0.05em; }
        .field-row-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
      </style>
    </template>
  };
}
// touched for re-index
