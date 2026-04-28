// Phase 2 — SkillCard (playbook for AI generation)
//
// A structured playbook that Phase 3's Translate Command will read via the
// `compiledPrompt` computed field (single file, single read — per the boss's
// "one big markdown for the AI" principle, avoiding N per-entry calls).
//
// Differences from the goal-tracking mockup:
//   - Removed Mac-frame chrome (Boxel provides its own card frame)
//   - Added `compiledPrompt` computed field — the whole point of this card
//   - Added `category` field ('daily-communication' / 'parent-summary')
//   - `status` string replaced with real `isActive` BooleanField
//   - "Test Generation" button is a Phase 3 placeholder

import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

const DASHBOARD_URL =
  'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main';

// ═════════════════════════════════════════════════════════
//   Nested FieldDef classes
// ═════════════════════════════════════════════════════════

export class ProhibitedTermField extends FieldDef {
  static displayName = 'Prohibited Term';
  @field badTerm = contains(StringField);
  @field goodTerm = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='pt-embed'>
        <s class='pt-bad'>{{@model.badTerm}}</s>
        <span class='pt-arrow'>→</span>
        <span class='pt-good'>"{{@model.goodTerm}}"</span>
      </span>
      <style scoped>
        .pt-embed { display: inline-flex; align-items: center; gap: 8px; font-size: 13px; }
        .pt-bad { color: #c53030; }
        .pt-arrow { color: #a0aec0; }
        .pt-good { color: #2f855a; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='pt-edit'>
        <div class='pt-edit-field'>
          <label>Forbidden word</label>
          <@fields.badTerm />
        </div>
        <div class='pt-edit-field'>
          <label>Replacement phrase</label>
          <@fields.goodTerm />
        </div>
      </div>
      <style scoped>
        .pt-edit {
          display: flex;
          flex-direction: column;
          gap: 10px;
          padding: 12px 14px;
          background: #fdf0ee;
          border-radius: 8px;
        }
        .pt-edit-field { display: flex; flex-direction: column; gap: 3px; }
        .pt-edit-field label {
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

export class VocabOverrideField extends FieldDef {
  static displayName = 'Vocabulary Override';
  @field abbreviation = contains(StringField);
  @field fullTerm = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='vo-embed'>
        <code class='vo-abbr'>{{@model.abbreviation}}</code>
        <span class='vo-arrow'>→</span>
        <span class='vo-full'>"{{@model.fullTerm}}"</span>
      </span>
      <style scoped>
        .vo-embed { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; }
        .vo-abbr { background: #edf2f7; padding: 1px 6px; border-radius: 4px; font-family: ui-monospace, monospace; font-size: 12px; color: #2d3748; }
        .vo-arrow { color: #a0aec0; }
        .vo-full { color: #4a5568; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='vo-edit'>
        <div class='vo-edit-field'>
          <label>Source term (abbreviation / jargon)</label>
          <@fields.abbreviation />
        </div>
        <div class='vo-edit-field'>
          <label>Expansion / replacement</label>
          <@fields.fullTerm />
        </div>
      </div>
      <style scoped>
        .vo-edit {
          display: flex;
          flex-direction: column;
          gap: 10px;
          padding: 12px 14px;
          background: #f4f0fa;
          border-radius: 8px;
        }
        .vo-edit-field { display: flex; flex-direction: column; gap: 3px; }
        .vo-edit-field label {
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

export class ChangelogEntryField extends FieldDef {
  static displayName = 'Changelog Entry';
  @field version = contains(StringField);
  @field text = contains(StringField);
  @field date = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='cl-embed'>
        <span class='cl-version'>{{@model.version}}</span>
        <span class='cl-text'>{{@model.text}}</span>
        <span class='cl-date'>{{@model.date}}</span>
      </div>
      <style scoped>
        .cl-embed { display: flex; align-items: baseline; gap: 12px; font-size: 13px; padding: 6px 0; }
        .cl-version { background: #ebf4ff; color: #2c5282; padding: 2px 8px; border-radius: 999px; font-family: ui-monospace, monospace; font-size: 11px; font-weight: 600; flex-shrink: 0; }
        .cl-text { flex: 1; color: #2d3748; }
        .cl-date { color: #a0aec0; font-size: 12px; flex-shrink: 0; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='cl-edit'>
        <div class='cl-edit-field'>
          <label>Version (e.g. v3.2)</label>
          <@fields.version />
        </div>
        <div class='cl-edit-field'>
          <label>Change description</label>
          <@fields.text />
        </div>
        <div class='cl-edit-field'>
          <label>Date (e.g. Feb 5)</label>
          <@fields.date />
        </div>
      </div>
      <style scoped>
        .cl-edit {
          display: flex;
          flex-direction: column;
          gap: 10px;
          padding: 12px 14px;
          background: #ebf4ff;
          border-radius: 8px;
        }
        .cl-edit-field { display: flex; flex-direction: column; gap: 3px; }
        .cl-edit-field label {
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

// ═════════════════════════════════════════════════════════
//   SkillCard — the persistent playbook
// ═════════════════════════════════════════════════════════

export class SkillCard extends CardDef {
  static displayName = 'Skill Card';

  // ── Identity ──
  @field name = contains(StringField);
  @field version = contains(StringField);
  @field category = contains(StringField);      // daily-communication | parent-summary
  @field isActive = contains(BooleanField);
  @field purpose = contains(StringField);

  // ── Optional config (metadata, not yet wired to scheduling) ──
  @field triggerTime = contains(StringField);
  @field modelSize = contains(StringField);

  // ── The playbook content ──
  @field toneGuidelines = contains(MarkdownField);
  @field prohibitedTerms = containsMany(ProhibitedTermField);
  @field vocabularyOverrides = containsMany(VocabOverrideField);

  // ── History ──
  @field changelogEntries = containsMany(ChangelogEntryField);

  // ── Computed ──
  @field lastUpdated = contains(StringField, {
    computeVia: function (this: SkillCard) {
      const entries = this.changelogEntries;
      if (!entries || entries.length === 0) return '';
      const latest = entries[0];
      return latest?.date ? `Updated ${latest.date}` : '';
    },
  });

  // Override CardDef's built-in cardTitle (not `title`). Boxel chrome reads cardTitle.
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SkillCard) {
      return this.name || 'Untitled Skill Card';
    },
  });

  // ⭐ THE KEY FIELD — Phase 3 Translate Command reads this to build its
  // system prompt. One computed string that flattens everything. This is
  // the "one big markdown, one file read" principle from the boss.
  @field compiledPrompt = contains(StringField, {
    computeVia: function (this: SkillCard) {
      const lines: string[] = [];
      const name = this.name || 'Untitled Playbook';
      const version = this.version || 'v?';
      lines.push(`You are following the "${name}" playbook (${version}).`);
      lines.push('');

      if (this.purpose) {
        lines.push(`**Purpose:** ${this.purpose}`);
        lines.push('');
      }

      // Tone guidelines (markdown block, already formatted)
      if (this.toneGuidelines) {
        lines.push('## Tone Guidelines');
        lines.push('');
        lines.push(String(this.toneGuidelines).trim());
        lines.push('');
      }

      // Prohibited terms
      const pt = this.prohibitedTerms ?? [];
      if (pt.length > 0) {
        lines.push('## Prohibited Terms');
        lines.push('');
        lines.push(
          'You MUST NOT use these words. If the source observation ' +
            'contains one, substitute the parent-friendly phrase:',
        );
        lines.push('');
        for (const term of pt) {
          const bad = term?.badTerm ?? '';
          const good = term?.goodTerm ?? '';
          if (bad && good) {
            lines.push(`- DO NOT say "${bad}" — instead say "${good}"`);
          }
        }
        lines.push('');
      }

      // Vocabulary overrides
      const vo = this.vocabularyOverrides ?? [];
      if (vo.length > 0) {
        lines.push('## Vocabulary Overrides');
        lines.push('');
        lines.push(
          'When the source observation contains these terms, expand or soften them:',
        );
        lines.push('');
        for (const v of vo) {
          const abbr = v?.abbreviation ?? '';
          const full = v?.fullTerm ?? '';
          if (abbr && full) {
            lines.push(`- "${abbr}" → "${full}"`);
          }
        }
        lines.push('');
      }

      return lines.join('\n');
    },
  });

  // ─────────────────────────────────────────────────────
  // Embedded — minimal list item
  // ─────────────────────────────────────────────────────
  static embedded = class Embedded extends Component<typeof SkillCard> {
    <template>
      <div class='sc-embed'>
        <div class='sc-embed-header'>
          <h3 class='sc-embed-title'>{{@model.name}}</h3>
          <span class='sc-embed-version'>{{@model.version}}</span>
        </div>
        <p class='sc-embed-purpose'>{{@model.purpose}}</p>
        <div class='sc-embed-meta'>
          <span class='sc-embed-category'>{{@model.category}}</span>
          {{#if @model.isActive}}
            <span class='sc-embed-badge active'>● ACTIVE</span>
          {{else}}
            <span class='sc-embed-badge inactive'>○ INACTIVE</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .sc-embed {
          padding: 14px 16px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          font-family: system-ui, sans-serif;
        }
        .sc-embed-header {
          display: flex;
          justify-content: space-between;
          align-items: baseline;
          margin-bottom: 4px;
        }
        .sc-embed-title {
          margin: 0;
          font-size: 15px;
          color: #2d3748;
        }
        .sc-embed-version {
          font-family: ui-monospace, monospace;
          font-size: 11px;
          color: #718096;
        }
        .sc-embed-purpose {
          margin: 0 0 8px;
          color: #4a5568;
          font-size: 12px;
          line-height: 1.4;
        }
        .sc-embed-meta {
          display: flex;
          gap: 8px;
          align-items: center;
        }
        .sc-embed-category {
          font-size: 11px;
          padding: 2px 8px;
          background: #edf2f7;
          border-radius: 999px;
          color: #4a5568;
          font-family: ui-monospace, monospace;
        }
        .sc-embed-badge {
          font-size: 10px;
          font-weight: 700;
          letter-spacing: 0.5px;
        }
        .sc-embed-badge.active { color: #2f855a; }
        .sc-embed-badge.inactive { color: #a0aec0; }
      </style>
    </template>
  };

  // ─────────────────────────────────────────────────────
  // Isolated — full playbook view with edit + compiled-prompt preview
  // ─────────────────────────────────────────────────────
  static isolated = class Isolated extends Component<typeof SkillCard> {
    dashboardUrl = DASHBOARD_URL;

    // NOTE: Editing uses Boxel's built-in pencil icon in the top-right chrome.
    // It auto-generates full CardDef edit with labeled inputs for every
    // field including containsMany nested items. No custom edit button.
    @tracked showCompiledPrompt = false;
    @tracked showTestHint = false;

    togglePrompt = () => { this.showCompiledPrompt = !this.showCompiledPrompt; };
    toggleTestHint = () => { this.showTestHint = !this.showTestHint; };

    <template>
      <a class='sc-back' href={{this.dashboardUrl}}>← Back to Dashboard</a>
      <article class='sc-root'>
        {{! ── Header: active status + version ── }}
        <header class='sc-header'>
          {{#if @model.isActive}}
            <div class='sc-status active'>
              <span class='status-dot'></span>ACTIVE
            </div>
          {{else}}
            <div class='sc-status inactive'>
              <span class='status-dot'></span>INACTIVE
            </div>
          {{/if}}
          <div class='sc-version-row'>
            <span class='sc-version'>{{@model.version}}</span>
            {{#if @model.lastUpdated}}
              <span class='sc-version-date'>{{@model.lastUpdated}}</span>
            {{/if}}
          </div>
        </header>

        {{! ── Title + Purpose ── }}
        <div class='sc-title-block'>
          <h1 class='sc-title'>{{@model.name}}</h1>
          <p class='sc-purpose'>{{@model.purpose}}</p>
        </div>

        {{! ── Meta row ── }}
        <div class='sc-meta'>
          <div class='sc-meta-item'>
            <span class='sc-meta-label'>CATEGORY</span>
            <span class='sc-meta-value'>{{@model.category}}</span>
          </div>
          <div class='sc-meta-item'>
            <span class='sc-meta-label'>TRIGGER</span>
            <span class='sc-meta-value'>{{@model.triggerTime}}</span>
          </div>
          <div class='sc-meta-item'>
            <span class='sc-meta-label'>MODEL</span>
            <span class='sc-meta-value mono'>{{@model.modelSize}}</span>
          </div>
        </div>

        {{! ── Tone Guidelines ── }}
        <section class='sc-section'>
          <h3 class='sc-section-title'>Tone Guidelines</h3>
          <div class='sc-markdown'>
            <@fields.toneGuidelines />
          </div>
        </section>

        {{! ── Prohibited Terms ── }}
        <section class='sc-section'>
          <h3 class='sc-section-title'>
            Prohibited Terms
            <span class='sc-section-count'>{{@model.prohibitedTerms.length}} rules</span>
          </h3>
          <div class='sc-term-list'>
            {{#each @model.prohibitedTerms as |term|}}
              <div class='sc-term-row'>
                <s class='sc-term-bad'>{{term.badTerm}}</s>
                <span class='sc-term-arrow'>→</span>
                <span class='sc-term-good'>"{{term.goodTerm}}"</span>
              </div>
            {{/each}}
          </div>
        </section>

        {{! ── Vocabulary Overrides ── }}
        <section class='sc-section'>
          <h3 class='sc-section-title'>Vocabulary Overrides</h3>
          <div class='sc-vocab-list'>
            {{#each @model.vocabularyOverrides as |v|}}
              <span class='sc-vocab-pill'>
                <code>{{v.abbreviation}}</code>
                <span class='sc-vocab-arrow'>→</span>
                "{{v.fullTerm}}"
              </span>
            {{/each}}
          </div>
        </section>

        {{! ── Change Log ── }}
        <section class='sc-section'>
          <h3 class='sc-section-title'>Change Log</h3>
          <div class='sc-changelog'>
            {{#each @model.changelogEntries as |e|}}
              <div class='sc-cl-row'>
                <span class='sc-cl-version'>{{e.version}}</span>
                <span class='sc-cl-text'>{{e.text}}</span>
                <span class='sc-cl-date'>{{e.date}}</span>
              </div>
            {{/each}}
          </div>
        </section>

        {{! ── Compiled Prompt (debug/preview, collapsible) ── }}
        <section class='sc-section'>
          <button
            type='button'
            class='sc-collapse-btn'
            {{on 'click' this.togglePrompt}}
          >
            {{if this.showCompiledPrompt '▼' '▶'}}
            View compiled prompt (what the AI will see)
          </button>
          {{#if this.showCompiledPrompt}}
            <pre class='sc-compiled'>{{@model.compiledPrompt}}</pre>
          {{/if}}
        </section>

        {{! ── Actions ── }}
        <div class='sc-actions'>
          <button
            type='button'
            class='sc-btn primary'
            {{on 'click' this.toggleTestHint}}
          >
            Test Generation
          </button>
        </div>

        {{#if this.showTestHint}}
          <div class='sc-hint'>
            <p>
              Test Generation will be wired to the Phase 3 Translate Command.
              Once that is built, this button will take a selected
              ImportSnapshot and run the full AI translation against this
              playbook, showing the generated Daily Communication inline.
            </p>
            <button type='button' class='sc-hint-close' {{on 'click' this.toggleTestHint}}>
              Dismiss
            </button>
          </div>
        {{/if}}
      </article>

      <style scoped>
        .sc-back {
          display: inline-block;
          margin: 16px auto 0;
          max-width: 720px;
          width: 100%;
          padding: 8px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 8px;
          color: #4a5568;
          font-family: system-ui, sans-serif;
          font-size: 12px;
          font-weight: 600;
          text-decoration: none;
          box-sizing: border-box;
        }
        .sc-back:hover {
          background: #faf8f6;
          border-color: #2a9d8f;
          color: #2a9d8f;
        }
        .sc-root {
          padding: 32px;
          max-width: 720px;
          margin: 0 auto;
          font-family: system-ui, -apple-system, sans-serif;
          color: #1a1816;
          background: #fffdfb;
        }
        .sc-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 16px;
        }
        .sc-status {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          font-weight: 700;
          letter-spacing: 0.5px;
        }
        .sc-status.active { color: #2a9d8f; }
        .sc-status.inactive { color: #a0aec0; }
        .status-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: currentColor;
        }
        .sc-version-row {
          display: flex;
          align-items: baseline;
          gap: 10px;
        }
        .sc-version {
          font-size: 14px;
          font-weight: 600;
          color: #4a5568;
          font-family: ui-monospace, monospace;
        }
        .sc-version-date {
          font-size: 12px;
          color: #a0aec0;
        }

        .sc-title-block {
          margin-bottom: 24px;
        }
        .sc-title {
          margin: 0 0 6px;
          font-size: 26px;
          font-weight: 700;
          color: #1a1816;
        }
        .sc-purpose {
          margin: 0;
          color: #5c5650;
          font-size: 14px;
          line-height: 1.5;
        }
        .sc-meta {
          display: flex;
          gap: 32px;
          padding: 12px 16px;
          background: #faf8f6;
          border-radius: 8px;
          margin-bottom: 28px;
          flex-wrap: wrap;
        }
        .sc-meta-item {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .sc-meta-label {
          font-size: 10px;
          font-weight: 700;
          letter-spacing: 0.5px;
          color: #8a8279;
        }
        .sc-meta-value {
          font-size: 13px;
          color: #1a1816;
        }
        .sc-meta-value.mono { font-family: ui-monospace, monospace; }

        .sc-section {
          margin-bottom: 24px;
          padding-bottom: 20px;
          border-bottom: 1px solid #f5f2ef;
        }
        .sc-section:last-of-type { border-bottom: none; }
        .sc-section-title {
          margin: 0 0 12px;
          font-size: 12px;
          font-weight: 700;
          text-transform: uppercase;
          color: #5c5650;
          letter-spacing: 0.8px;
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .sc-section-count {
          font-size: 10px;
          font-weight: 500;
          text-transform: none;
          letter-spacing: 0;
          color: #8a8279;
          background: #f5f2ef;
          padding: 2px 8px;
          border-radius: 999px;
        }

        .sc-markdown {
          color: #2d3748;
          font-size: 14px;
          line-height: 1.6;
        }
        .sc-markdown :deep(p) { margin: 0 0 10px; }
        .sc-markdown :deep(ul) { padding-left: 20px; margin: 0; }
        .sc-markdown :deep(li) { margin-bottom: 6px; }

        .sc-term-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .sc-term-row {
          display: flex;
          align-items: center;
          gap: 10px;
          padding: 8px 12px;
          background: #fdf0ee;
          border-radius: 6px;
          font-size: 13px;
        }
        .sc-term-bad { color: #c53030; }
        .sc-term-arrow { color: #a0aec0; }
        .sc-term-good { color: #2f855a; }

        .sc-vocab-list {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .sc-vocab-pill {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 6px 12px;
          background: #f4f0fa;
          border-radius: 999px;
          font-size: 12px;
          color: #4a5568;
        }
        .sc-vocab-pill code {
          background: white;
          padding: 1px 6px;
          border-radius: 4px;
          font-family: ui-monospace, monospace;
          color: #2d3748;
        }
        .sc-vocab-arrow { color: #a0aec0; }

        .sc-changelog {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }
        .sc-cl-row {
          display: flex;
          align-items: baseline;
          gap: 12px;
          padding: 8px 12px;
          background: #faf8f6;
          border-radius: 6px;
        }
        .sc-cl-version {
          background: #ebf4ff;
          color: #2c5282;
          padding: 2px 8px;
          border-radius: 999px;
          font-family: ui-monospace, monospace;
          font-size: 11px;
          font-weight: 600;
          flex-shrink: 0;
        }
        .sc-cl-text { flex: 1; color: #2d3748; font-size: 13px; }
        .sc-cl-date { color: #a0aec0; font-size: 12px; flex-shrink: 0; }

        .sc-collapse-btn {
          display: flex;
          align-items: center;
          gap: 8px;
          background: none;
          border: none;
          padding: 8px 0;
          cursor: pointer;
          font-family: inherit;
          font-size: 12px;
          font-weight: 600;
          text-transform: uppercase;
          color: #5c5650;
          letter-spacing: 0.5px;
        }
        .sc-collapse-btn:hover { color: #1a1816; }
        .sc-compiled {
          margin-top: 10px;
          padding: 16px;
          background: #1a202c;
          color: #e2e8f0;
          border-radius: 8px;
          font-family: ui-monospace, monospace;
          font-size: 11px;
          line-height: 1.6;
          white-space: pre-wrap;
          word-break: break-word;
          max-height: 500px;
          overflow-y: auto;
        }

        .sc-actions {
          display: flex;
          justify-content: flex-end;
          gap: 10px;
          padding-top: 20px;
          border-top: 1px solid #f5f2ef;
          margin-top: 20px;
        }
        .sc-btn {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 10px 18px;
          border-radius: 6px;
          font-family: inherit;
          font-size: 13px;
          font-weight: 600;
          cursor: pointer;
          border: 1px solid transparent;
        }
        .sc-btn.secondary {
          background: white;
          border-color: #e2e8f0;
          color: #4a5568;
        }
        .sc-btn.secondary:hover {
          background: #f7fafc;
        }
        .sc-btn.primary {
          background: #2a9d8f;
          color: white;
        }
        .sc-btn.primary:hover {
          background: #238077;
        }

        .sc-hint {
          margin-top: 12px;
          padding: 14px 16px;
          background: #e8f6f4;
          border: 1px solid #2a9d8f;
          border-radius: 8px;
          font-size: 13px;
          color: #1a1816;
          position: relative;
        }
        .sc-hint p { margin: 0; line-height: 1.5; padding-right: 70px; }
        .sc-hint-close {
          position: absolute;
          top: 10px;
          right: 10px;
          background: none;
          border: none;
          color: #2a9d8f;
          cursor: pointer;
          font-size: 12px;
          font-weight: 600;
        }
      </style>
    </template>
  };
}
