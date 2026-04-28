import {
  CardDef,
  field,
  contains,
  containsMany,
  linksTo,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import enumField from 'https://cardstack.com/base/enum';
import TargetIcon from '@cardstack/boxel-icons/target';
import { Student } from './student';
import { EvidenceEntry } from './evidence-entry';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

const DomainField = enumField(StringField, {
  options: ['Math', 'Reading', 'Social', 'Behavioral', 'Motor', 'Communication', 'Receptive Language', 'Language', 'Fine Motor', 'Gross Motor', 'Visual Performance', 'Labeling', 'Requests'],
});

const PriorityField = enumField(StringField, {
  options: ['High', 'Medium', 'Low'],
});

const LEVEL_NAMES = ['Emerging', 'Developing', 'Approaching', 'Proficient', 'Mastered'];

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
  @field studentName = contains(StringField);
  @field startedDate = contains(StringField);
  @field standardAlignment = contains(StringField);
  @field dueDate = contains(DateField);

  @field evidenceEntries = containsMany(EvidenceEntry);

  @field progressPercent = contains(NumberField, {
    computeVia: function (this: LearningGoal) {
      const entries = this.evidenceEntries ?? [];
      if (entries.length === 0) return Math.min(100, this.currentMastery ?? 0);
      let totalPct = 0;
      let count = 0;
      for (const e of entries) {
        const denom = (e as any).scoreDenominator;
        const numer = (e as any).scoreNumerator;
        if (denom && denom > 0) {
          totalPct += (numer ?? 0) / denom * 100;
          count++;
        }
      }
      if (count === 0) return Math.min(100, this.currentMastery ?? 0);
      return Math.min(100, Math.round(totalPct / count));
    },
  });

  @field masteryLevel = contains(StringField, {
    computeVia: function (this: LearningGoal) {
      const pct = (this as any).progressPercent ?? 0;
      if (pct >= 90) return 'Mastered';
      if (pct >= 75) return 'Proficient';
      if (pct >= 55) return 'Approaching';
      if (pct >= 30) return 'Developing';
      return 'Emerging';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: LearningGoal) {
      return this.goalTitle || 'Untitled Goal';
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

  // ── Isolated View (matches mockup) ──
  static isolated = class Isolated extends Component<typeof LearningGoal> {
    // Live evidence from ActivityEntries (not stale copies)
    @tracked liveEntries: any[] = [];
    @tracked _loaded = false;

    constructor(owner: any, args: any) {
      super(owner, args);
      this._loadLiveEvidence();
    }

    async _loadLiveEvidence() {
      try {
        const ctx = (this.args as any).context;
        const getCards = ctx?.getCards ?? ctx?.actions?.getCards;
        if (!getCards) { this._loaded = true; return; }

        const aeModule = new URL('./activity-entry', import.meta.url).href;
        const res = getCards(this, () => ({
          filter: { type: { module: aeModule, name: 'ActivityEntry' } },
        }));

        // Unwrap resource
        const t0 = Date.now();
        let entries: any[] = [];
        while (Date.now() - t0 < 8000) {
          const arr = Array.isArray(res?.instances) ? res.instances : (Array.isArray(res?.value) ? res.value : null);
          if (arr !== null && !res?.isLoading) { entries = arr; break; }
          await new Promise((r) => setTimeout(r, 100));
        }

        const goalTitle = String(this.args.model?.goalTitle ?? '');
        this.liveEntries = entries
          .filter((ae: any) => String(ae?.suggestedGoal ?? '') === goalTitle && String(ae?.aiTagged ?? '') === 'true')
          .map((ae: any) => {
            const score = String(ae?.score ?? '');
            const parts = score.split('/');
            const numer = Number(parts[0]) || 0;
            const denom = Number(parts[1]) || 1;
            const pct = denom > 0 ? numer / denom : 0;
            return {
              score,
              scoreNumerator: numer,
              scoreDenominator: Number(parts[1]) || 0,
              text: String(ae?.content ?? '').slice(0, 200),
              author: String(ae?.author?.name ?? ae?.author ?? ''),
              date: ae?.timestamp ? new Date(ae.timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '',
              scoreRating: pct >= 0.8 ? 'good' : (pct >= 0.6 ? 'ok' : 'needs-improvement'),
            };
          });
        this._loaded = true;
      } catch (e) {
        console.warn('[LearningGoal] live evidence load failed:', e);
        this._loaded = true;
      }
    }

    get domainColor() {
      const d = this.args.model.domain || '';
      if (d.includes('Math')) return 'coral';
      if (d.includes('Reading')) return 'teal';
      if (d.includes('Language') || d.includes('Receptive')) return 'amber';
      if (d.includes('Social')) return 'purple';
      if (d.includes('Motor')) return 'green';
      if (d.includes('Behavior')) return 'orange';
      return 'teal';
    }

    get isHighPriority() { return this.args.model.priority === 'High'; }
    get isMediumPriority() { return this.args.model.priority === 'Medium'; }

    get currentLevel(): number {
      const pct = this.args.model.progressPercent ?? 0;
      if (pct >= 90) return 5;
      if (pct >= 75) return 4;
      if (pct >= 55) return 3;
      if (pct >= 30) return 2;
      return 1;
    }

    get targetLevel(): number {
      const t = this.args.model.targetMastery ?? 80;
      // Convert 0-100% to 1-5 level
      if (t >= 90) return 5;
      if (t >= 75) return 4;
      if (t >= 55) return 3;
      if (t >= 30) return 2;
      return 1;
    }

    get masteryLevels() {
      const current = this._loaded ? this.liveCurrentLevel : this.currentLevel;
      const target = this.targetLevel;
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
      return htmlSafe(`width: ${this.liveProgressPercent}%`);
    }

    get targetLevelName() {
      const t = this.targetLevel;
      return LEVEL_NAMES[t - 1] || '';
    }

    get formattedDueDate() {
      const d = this.args.model.dueDate;
      if (!d) return '';
      const date = new Date(d);
      return date.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    }

    get evidenceSource() {
      // Use live entries from ActivityEntries if loaded AND has results
      // Fallback to embedded evidenceEntries if live load returned nothing
      if (this._loaded) {
        if (this.liveEntries.length > 0) return this.liveEntries;
        // Live loaded but empty — could mean entries were deleted, show embedded as fallback
        const embedded = this.args.model.evidenceEntries || [];
        return embedded.length > 0 ? embedded : [];
      }
      // Not loaded yet — show embedded temporarily
      return this.args.model.evidenceEntries || [];
    }
    get hasEvidence() { return this.evidenceSource.length > 0; }
    get evidenceCount() { return this.evidenceSource.length; }

    get liveProgressPercent() {
      const entries = this.evidenceSource;
      if (entries.length === 0) return this.args.model.progressPercent ?? 0;
      let total = 0;
      let count = 0;
      for (const ev of entries) {
        const d = ev.scoreDenominator ?? 0;
        const n = ev.scoreNumerator ?? 0;
        if (d > 0) { total += (n / d) * 100; count++; }
      }
      return count > 0 ? Math.min(100, Math.round(total / count)) : (this.args.model.progressPercent ?? 0);
    }

    get liveCurrentLevel(): number {
      const pct = this.liveProgressPercent;
      if (pct >= 90) return 5;
      if (pct >= 75) return 4;
      if (pct >= 55) return 3;
      if (pct >= 30) return 2;
      return 1;
    }

    @tracked showAllEvidence = false;

    get evidencePreview() {
      const all = this.evidenceSource;
      return this.showAllEvidence ? all : all.slice(0, 3);
    }

    get hasMoreEvidence() { return this.evidenceCount > 3; }

    toggleAllEvidence = () => { this.showAllEvidence = !this.showAllEvidence; };

    <template>
      <div class='goal-card'>
        <a class='back-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/Classroom/classroom-2a'>← Back to Classroom</a>

        {{!-- Domain + Priority --}}
        <div class='goal-header'>
          <div class='goal-domain {{this.domainColor}}'>{{@model.domain}}</div>
          {{#if this.isHighPriority}}
            <div class='goal-priority high'>★ High Priority</div>
          {{else if this.isMediumPriority}}
            <div class='goal-priority medium'>★ Medium Priority</div>
          {{/if}}
        </div>

        <h2 class='goal-title'>{{@model.goalTitle}}</h2>
        {{#if @model.description}}
          <p class='goal-desc'>{{@model.description}}</p>
        {{/if}}

        {{!-- Student --}}
        {{#if @model.student}}
          <div class='student-section'>
            <div class='section-label-text'>LINKED STUDENT</div>
            <@fields.student @format='embedded' />
          </div>
        {{/if}}

        {{!-- Mastery Level Boxes --}}
        <div class='mastery-section'>
          <div class='mastery-header'>
            <span class='mastery-label'>Mastery Level</span>
            <span class='mastery-target-label'>Target: {{this.targetLevel}} ({{this.targetLevelName}})</span>
          </div>
          <div class='mastery-boxes'>
            {{#each this.masteryLevels as |level|}}
              <div class='mastery-box {{level.cls}}'>
                <span class='box-num'>{{level.num}}</span>
                <span class='box-name'>{{level.name}}</span>
                {{#if level.isCurrent}}<span class='box-indicator current-ind'>Current</span>{{/if}}
                {{#if level.isTarget}}<span class='box-indicator target-ind'>Target</span>{{/if}}
              </div>
            {{/each}}
          </div>
          <div class='progress-row'>
            <div class='progress-track'>
              <div class='progress-fill' style={{this.progressWidth}}><div class='progress-dot'></div></div>
            </div>
            <span class='progress-pct'>{{this.liveProgressPercent}}%</span>
          </div>
        </div>

        {{!-- Standard Alignment + Due Date --}}
        <div class='meta-grid'>
          {{#if @model.standardAlignment}}
            <div class='meta-box'>
              <span class='meta-box-label'>Standard Alignment</span>
              <div class='meta-box-value'>{{@model.standardAlignment}}</div>
            </div>
          {{/if}}
          {{#if @model.dueDate}}
            <div class='meta-box'>
              <span class='meta-box-label'>Due Date</span>
              <div class='meta-box-value'>{{this.formattedDueDate}} {{#if @model.daysRemaining}}<span class='days-badge'>{{@model.daysRemaining}} days</span>{{/if}}</div>
            </div>
          {{/if}}
        </div>

        {{!-- Linked Evidence --}}
        <div class='evidence-section'>
          <div class='section-header-row'>
            <span class='section-header-text'>Linked Evidence</span>
            <span class='evidence-count'>{{this.evidenceCount}} entries</span>
          </div>
          {{#if this.hasEvidence}}
            <div class='ev-list'>
              {{#each this.evidencePreview as |ev|}}
                <div class='ev-item'>
                  <div class='ev-score {{ev.scoreRating}}'>{{ev.score}}</div>
                  <div class='ev-body'>
                    <span class='ev-text'>{{ev.text}}</span>
                    <span class='ev-meta'>{{ev.author}} · {{ev.date}}</span>
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
            <div class='empty-hint'>No evidence yet. Scores will appear here after teachers record activities.</div>
          {{/if}}
        </div>

        {{!-- Actions --}}
        <div class='goal-actions'>
          <a class='action-btn edit-btn' href='{{@model.id}}'>Edit Goal</a>
          <button class='action-btn add-obs-btn' type='button'>+ Add Observation</button>
        </div>
      </div>

      <style scoped>
        .back-link { display: inline-block; padding: 0.5rem 0; font-size: 0.8125rem; font-weight: 600; color: #7c5fc4; text-decoration: none; }
        .back-link:hover { text-decoration: underline; }
        .goal-card { padding: 2rem; background: #fffdfb; border-radius: 14px; box-shadow: 0 4px 12px rgba(26,24,22,0.06); max-width: 800px; margin: 0 auto; font-family: 'Inter', system-ui, sans-serif; display: flex; flex-direction: column; gap: 1.25rem; }
        .goal-header { display: flex; justify-content: space-between; align-items: center; }
        .goal-domain { display: flex; align-items: center; gap: 0.375rem; font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; }
        .goal-domain.coral { color: #e05d50; } .goal-domain.teal { color: #2a9d8f; } .goal-domain.amber { color: #c08b30; } .goal-domain.purple { color: #7c5fc4; } .goal-domain.green { color: #059669; } .goal-domain.orange { color: #d97706; }
        .goal-priority { display: flex; align-items: center; gap: 0.3rem; font-size: 0.625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; padding: 0.3rem 0.625rem; border-radius: 4px; }
        .goal-priority.high { background: #fdf6e8; color: #c08b30; }
        .goal-priority.medium { background: #f0f4ff; color: #5b7bc0; }
        .goal-title { font-size: 1.5rem; font-weight: 600; margin: 0; color: #1a1816; line-height: 1.3; }
        .goal-desc { font-size: 0.9375rem; color: #5c5650; line-height: 1.6; margin: 0; }
        .student-section { display: flex; flex-direction: column; gap: 0.5rem; }
        .section-label-text { font-size: 0.625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: #8a8279; }

        /* Mastery Level Boxes */
        .mastery-section { display: flex; flex-direction: column; gap: 0.75rem; }
        .mastery-header { display: flex; justify-content: space-between; align-items: center; }
        .mastery-label { font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: #5c5650; }
        .mastery-target-label { font-size: 0.6875rem; color: #5c5650; }
        .mastery-boxes { display: flex; gap: 0.25rem; }
        .mastery-box { flex: 1; padding: 0.75rem 0.375rem 0.5rem; background: #f5f2ef; border-radius: 8px; text-align: center; position: relative; }
        .mastery-box.filled { background: #e8f6f4; }
        .mastery-box.current { background: #2a9d8f; color: white; }
        .mastery-box.target { border: 2px dashed #c08b30; background: #fdf6e8; }
        .box-num { display: block; font-size: 1.125rem; font-weight: 700; }
        .box-name { display: block; font-size: 0.5rem; text-transform: uppercase; letter-spacing: 0.04em; margin-top: 0.125rem; }
        .box-indicator { display: block; font-size: 0.5rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; margin-top: 0.375rem; }
        .current-ind { color: #2a9d8f; }
        .mastery-box.current .current-ind { color: white; }
        .target-ind { color: #c08b30; }
        .progress-row { display: flex; align-items: center; gap: 0.75rem; }
        .progress-track { flex: 1; height: 8px; background: #ebe7e3; border-radius: 4px; position: relative; overflow: visible; }
        .progress-fill { height: 100%; background: #2a9d8f; border-radius: 4px; position: relative; transition: width 0.3s; min-width: 0; }
        .progress-dot { position: absolute; right: -5px; top: -2px; width: 12px; height: 12px; border-radius: 50%; background: #2a9d8f; border: 2px solid white; box-shadow: 0 1px 3px rgba(0,0,0,0.2); }
        .progress-pct { font-size: 1.125rem; font-weight: 700; color: #2a9d8f; min-width: 48px; text-align: right; }

        /* Meta Grid */
        .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .meta-box { padding: 0.75rem; background: #faf8f6; border-radius: 6px; }
        .meta-box-label { display: block; font-size: 0.5625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #8a8279; margin-bottom: 0.25rem; }
        .meta-box-value { font-size: 0.875rem; color: #1a1816; }
        .days-badge { font-size: 0.6875rem; color: #8a8279; margin-left: 0.5rem; }

        /* Evidence */
        .evidence-section { display: flex; flex-direction: column; gap: 0.75rem; padding-top: 1rem; border-top: 1px solid #ebe7e3; }
        .section-header-row { display: flex; justify-content: space-between; align-items: center; }
        .section-header-text { font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: #5c5650; }
        .evidence-count { font-size: 0.75rem; color: #8a8279; }
        .ev-list { display: flex; flex-direction: column; gap: 0.5rem; }
        .ev-item { display: flex; gap: 0.75rem; padding: 0.625rem 0.75rem; background: #faf8f6; border-radius: 6px; }
        .ev-score { font-size: 0.75rem; font-weight: 700; padding: 0.25rem 0.5rem; border-radius: 4px; background: #f5f2ef; color: #5c5650; flex-shrink: 0; min-width: 48px; text-align: center; }
        .ev-score.good { background: #e8f6f4; color: #2a9d8f; }
        .ev-score.ok { background: #fdf6e8; color: #c08b30; }
        .ev-score.needs-improvement { background: #fdeceb; color: #e05d50; }
        .ev-body { flex: 1; }
        .ev-text { display: block; font-size: 0.8125rem; color: #1a1816; line-height: 1.4; }
        .ev-meta { font-size: 0.6875rem; color: #8a8279; }
        .ev-more-btn { background: #faf8f6; border: 1px solid #ebe7e3; border-radius: 6px; padding: 0.5rem; font-family: inherit; font-size: 0.8125rem; color: #5c5650; cursor: pointer; text-align: center; }
        .ev-more-btn:hover { background: #f0ece8; }
        .empty-hint { font-size: 0.8125rem; color: #8a8279; font-style: italic; padding: 0.5rem 0; }

        /* Actions */
        .goal-actions { display: flex; justify-content: flex-end; gap: 0.75rem; padding-top: 1rem; border-top: 1px solid #ebe7e3; }
        .action-btn { font-family: inherit; font-size: 0.8125rem; font-weight: 600; padding: 0.5rem 1rem; border-radius: 6px; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 0.375rem; }
        .edit-btn { background: white; border: 1px solid #ebe7e3; color: #5c5650; }
        .edit-btn:hover { background: #faf8f6; }
        .add-obs-btn { background: #e05d50; border: none; color: white; }
        .add-obs-btn:hover { background: #d04a3e; }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof LearningGoal> {
    get safeTitle() { return this.args.model?.goalTitle ?? 'Untitled Goal'; }
    get safeDomain() { return this.args.model?.domain ?? 'Academic'; }
    get currentPct() { return this.args.model?.progressPercent ?? this.args.model?.currentMastery ?? 0; }
    get domainColor() {
      switch (this.safeDomain) {
        case 'Math': return '#e05d50'; case 'Reading': return '#c08b30';
        case 'Social': return '#7c5fc4'; case 'Behavioral': return '#c08b30';
        case 'Motor': case 'Gross Motor': return '#2a9d8f';
        case 'Fine Motor': return '#059669';
        case 'Communication': case 'Language': case 'Receptive Language': return '#5c8fc4';
        default: return '#5c5650';
      }
    }
    <template>
      <div class='goal-embedded'>
        <div class='goal-top'>
          <span class='domain-pill' style='background-color: {{this.domainColor}}'>{{this.safeDomain}}</span>
          <span class='pct'>{{this.currentPct}}%</span>
        </div>
        <div class='goal-name'>{{this.safeTitle}}</div>
        <div class='bar'><div class='bar-fill' style='width: {{this.currentPct}}%; background-color: {{this.domainColor}}'></div></div>
      </div>
      <style scoped>
        .goal-embedded { display: flex; flex-direction: column; gap: 0.375rem; padding: 0.625rem; background-color: var(--card); border: 1px solid var(--border); border-radius: 8px; height: 100%; }
        .goal-top { display: flex; justify-content: space-between; align-items: center; }
        .domain-pill { padding: 0.125rem 0.5rem; border-radius: 1rem; color: white; font-weight: 700; font-size: 0.5625rem; text-transform: uppercase; letter-spacing: 0.06em; }
        .pct { font-size: 0.875rem; font-weight: 700; color: #1a1816; }
        .goal-name { font-size: 0.8125rem; font-weight: 600; color: #1a1816; line-height: 1.3; }
        .bar { height: 4px; background: #ebe7e3; border-radius: 2px; }
        .bar-fill { height: 100%; border-radius: 2px; transition: width 0.3s ease; }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof LearningGoal> {
    get safeTitle() { return this.args.model?.goalTitle ?? 'Goal'; }
    get safeDomain() { return this.args.model?.domain ?? 'Academic'; }
    get currentPct() { return this.args.model?.progressPercent ?? this.args.model?.currentMastery ?? 0; }
    get domainColor() {
      switch (this.safeDomain) {
        case 'Math': return '#e05d50'; case 'Reading': return '#c08b30';
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
        .fitted-container { container-type: size; width: 100%; height: 100%; }
        .tile { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--boxel-sp-xs); padding: var(--boxel-sp); background-color: var(--card); border: 1px solid var(--border); border-radius: var(--boxel-border-radius); height: 100%; }
        .pct { font-size: 1.5rem; font-weight: 700; color: #1a1816; }
        .title { font-size: var(--boxel-font-size-xs); color: #5c5650; text-align: center; line-height: 1.3; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof LearningGoal> {
    <template>
      <div class='card-edit'>
        <div class='field-row'><label>Goal Title</label><@fields.goalTitle /></div>
        <div class='field-row'><label>Description</label><@fields.description /></div>
        <div class='field-row'><label>Domain</label><@fields.domain /></div>
        <div class='field-row'><label>Priority</label><@fields.priority /></div>
        <div class='field-pair'>
          <div class='field-row'><label>Current Mastery</label><@fields.currentMastery /></div>
          <div class='field-row'><label>Target Mastery (1-5)</label><@fields.targetMastery /></div>
        </div>
        <div class='field-row'><label>Standard Alignment</label><@fields.standardAlignment /></div>
        <div class='field-row'><label>Due Date</label><@fields.dueDate /></div>
        <div class='field-row'><label>Student</label><@fields.student /></div>
      </div>
      <style scoped>
        .card-edit { display: flex; flex-direction: column; gap: var(--boxel-sp-sm); padding: var(--boxel-sp-sm); border: 1px solid var(--border); border-radius: var(--boxel-border-radius); }
        .field-row { display: flex; flex-direction: column; gap: 0.25rem; }
        .field-row label { font-size: var(--boxel-font-size-xs); font-weight: 600; color: var(--muted-foreground); text-transform: uppercase; letter-spacing: 0.05em; }
        .field-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
      </style>
    </template>
  };
}
// touched for re-index
