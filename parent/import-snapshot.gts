// Phase 1 — ImportSnapshot card definition
//
// Purpose:
//   ImportSnapshot is a frozen, per-day, per-student snapshot of raw observations
//   fetched from the hero-classroom realm. Once a snapshot exists in parent-daily,
//   it is fully decoupled from hero-classroom — even if hero-classroom changes
//   or breaks, this snapshot remains usable for downstream Phase 3 (Daily
//   Communication translation by AI).
//
// Architecture intent:
//   - One JSON file per (date, student): ImportSnapshot/2026-04-07-jamie-chen.json
//   - Accumulating, never overwriting (calendar-style cardinality, per the boss spec)
//   - rawMarkdown is a computed field that flattens entriesJson into AI-friendly
//     markdown so the Phase 3 translator only needs ONE file read per snapshot
//
// Note: the actual fetch logic lives in import-snapshot-manager.gts because
// it needs `this.args.context.getCards` which is only available inside
// Component classes — not inside Command.run() bodies.

import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import DatetimeField from 'https://cardstack.com/base/datetime';

const DASHBOARD_URL =
  'https://app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/TribecaPrepDashboard/main';

// ─────────────────────────────────────────────────────────
// Internal data shape extracted from a hero-classroom ActivityEntry
// (we DO NOT preserve linksTo references — only flat string snapshots,
// because the whole point is to decouple from hero-classroom)
// ─────────────────────────────────────────────────────────
export interface FrozenEntry {
  id: string;
  content: string;
  entryType: string;
  timestamp: string;
  score: string;
  domain: string;
  reasoning: string;
  matchedBlock: string;
  suggestedGoal: string;
  flagNote: string;
  flagSeverity: string;
  authorName: string;
  studentSlug: string;
}

// ═════════════════════════════════════════════════════════
//   ImportSnapshot — the persistent card
// ═════════════════════════════════════════════════════════

export class ImportSnapshot extends CardDef {
  static displayName = 'Import Snapshot';

  @field studentSlug = contains(StringField);
  @field studentName = contains(StringField);
  @field studentGrade = contains(StringField);
  @field snapshotDate = contains(DateField);
  @field sourceRealm = contains(StringField);
  @field fetchedAt = contains(DatetimeField);
  @field entryCount = contains(NumberField);

  // Raw entries serialized as JSON. Storing the array as a string keeps the
  // schema flat (no nested FieldDef relations) and trivial to roundtrip.
  @field entriesJson = contains(StringField);
  @field scheduleJson = contains(StringField);  // DailyPlan schedule items as JSON
  @field goalsJson = contains(StringField);     // Active LearningGoals as JSON
  @field teacherName = contains(StringField);   // Head teacher name

  // Override CardDef's built-in cardTitle. Boxel chrome reads cardTitle, not `title`.
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ImportSnapshot) {
      const date = this.snapshotDate
        ? (typeof this.snapshotDate === 'string'
          ? this.snapshotDate
          : (() => { const dt = new Date(this.snapshotDate as any); return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; })())
        : '?';
      const rawName = this.studentName || this.studentSlug || 'unknown';
      // Convert slug-form to display
      const name = rawName && !/\s/.test(rawName) && rawName.includes('-')
        ? rawName
            .split('-')
            .map((w: string) => (w ? w.charAt(0).toUpperCase() + w.slice(1) : ''))
            .join(' ')
        : rawName;
      return `Snapshot ${date} - ${name}`;
    },
  });

  // ─── KEY PERFORMANCE OPTIMIZATION ───
  // Computed markdown that flattens entriesJson into a single string the AI
  // can consume in one read.
  @field rawMarkdown = contains(StringField, {
    computeVia: function (this: ImportSnapshot) {
      const date =
        typeof this.snapshotDate === 'string'
          ? this.snapshotDate
          : this.snapshotDate
            ? (() => { const dt = new Date(this.snapshotDate as any); return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`; })()
            : '(no date)';

      const header =
        `# Daily Observation Snapshot\n` +
        `\n` +
        `**Student:** ${this.studentName || '(unknown)'}` +
        (this.studentGrade ? ` (${this.studentGrade} grade)` : '') +
        `\n` +
        `**Date:** ${date}\n` +
        `**Source:** ${this.sourceRealm || '(unknown realm)'}\n` +
        `**Total observations:** ${this.entryCount ?? 0}\n` +
        `\n---\n\n`;

      let entries: FrozenEntry[] = [];
      try {
        if (this.entriesJson) {
          const parsed = JSON.parse(this.entriesJson);
          if (Array.isArray(parsed)) entries = parsed;
        }
      } catch (_) {
        return header + `_(entriesJson failed to parse)_\n`;
      }

      if (entries.length === 0) {
        return header + `_(no observations recorded for this day)_\n`;
      }

      entries.sort((a, b) =>
        (a.timestamp || '').localeCompare(b.timestamp || ''),
      );

      const body = entries
        .map((e, i) => {
          const time = e.timestamp
            ? new Date(e.timestamp).toLocaleTimeString('en-US', {
                hour: 'numeric',
                minute: '2-digit',
              })
            : '?';
          const lines: string[] = [];
          lines.push(`## Observation ${i + 1} - ${time}`);
          if (e.entryType) lines.push(`**Type:** ${e.entryType}`);
          if (e.domain) lines.push(`**Domain:** ${e.domain}`);
          if (e.matchedBlock)
            lines.push(`**Schedule block:** ${e.matchedBlock}`);
          if (e.authorName) lines.push(`**Recorded by:** ${e.authorName}`);
          if (e.score) lines.push(`**Score:** ${e.score}`);
          if (e.flagNote)
            lines.push(
              `**Flag (${e.flagSeverity || 'info'}):** ${e.flagNote}`,
            );
          if (e.suggestedGoal)
            lines.push(`**Linked goal:** ${e.suggestedGoal}`);
          lines.push('');
          lines.push(`> ${e.content || '(no observation text)'}`);
          if (e.reasoning) {
            lines.push('');
            lines.push(`_AI reasoning: ${e.reasoning}_`);
          }
          return lines.join('\n');
        })
        .join('\n\n---\n\n');

      // Add schedule timeline if available
      let scheduleSection = '';
      try {
        if (this.scheduleJson) {
          const items = JSON.parse(this.scheduleJson);
          if (Array.isArray(items) && items.length > 0) {
            scheduleSection = '\n\n---\n\n# Today\'s Schedule (from Daily Plan)\n\n';
            scheduleSection += items.map((item: any) => {
              const status = typeof item.status === 'object' ? (item.status?.value ?? '') : String(item.status ?? '');
              const check = status === 'Done' ? ' ✓' : '';
              const result = item.result ? ` [${item.result}]` : '';
              const goal = item.goalTag ? ` → ${item.goalTag}` : '';
              return `- **${item.time || '?'}** ${item.activity || '?'}${check}${result}${goal}`;
            }).join('\n');
          }
        }
      } catch (_) {}

      // Add active goals if available
      let goalsSection = '';
      try {
        if (this.goalsJson) {
          const goals = JSON.parse(this.goalsJson);
          if (Array.isArray(goals) && goals.length > 0) {
            goalsSection = '\n\n---\n\n# Active Learning Goals\n\n';
            goalsSection += goals.map((g: any) =>
              `- **${g.goalTitle}** (${g.domain}) — Target: ${g.targetMastery}%, Current progress: ${g.progressPercent ?? 0}%`
            ).join('\n');
          }
        }
      } catch (_) {}

      // Add teacher info
      let teacherSection = '';
      if (this.teacherName) {
        teacherSection = `\n\n---\n\n**Head Teacher:** ${this.teacherName}\n`;
      }

      return header + body + scheduleSection + goalsSection + teacherSection + '\n';
    },
  });

  static embedded = class Embedded extends Component<typeof ImportSnapshot> {
    <template>
      <div class='snap-embed'>
        <div class='snap-row'>
          <span class='snap-date'>{{@model.snapshotDate}}</span>
          <span class='snap-name'>{{@model.studentName}}</span>
          <span class='snap-count'>{{@model.entryCount}} entries</span>
        </div>
      </div>
      <style scoped>
        .snap-embed {
          padding: 10px 14px;
          background: white;
          border: 1px solid #e2e8f0;
          border-radius: 6px;
          font-family: system-ui, sans-serif;
          font-size: 13px;
        }
        .snap-row {
          display: flex;
          align-items: center;
          gap: 12px;
        }
        .snap-date {
          font-family: ui-monospace, monospace;
          color: #718096;
        }
        .snap-name {
          font-weight: 600;
          color: #2d3748;
          flex: 1;
        }
        .snap-count {
          font-size: 11px;
          padding: 2px 8px;
          background: #edf2f7;
          border-radius: 999px;
          color: #4a5568;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof ImportSnapshot> {
    dashboardUrl = DASHBOARD_URL;

    <template>
      <a class='snap-back' href={{this.dashboardUrl}}>← Back to Dashboard</a>
      <div class='snap-iso'>
        <header>
          <h1>{{@model.title}}</h1>
          <div class='meta'>
            <span><strong>Student:</strong> {{@model.studentName}} ({{@model.studentGrade}})</span>
            <span><strong>Date:</strong> {{@model.snapshotDate}}</span>
            <span><strong>Source:</strong> {{@model.sourceRealm}}</span>
            <span><strong>Fetched at:</strong> {{@model.fetchedAt}}</span>
            <span><strong>Entry count:</strong> {{@model.entryCount}}</span>
          </div>
        </header>
        <section class='markdown-section'>
          <h2>rawMarkdown (computed) - what the Phase 3 AI translator will read</h2>
          <pre class='markdown-box'>{{@model.rawMarkdown}}</pre>
        </section>
      </div>
      <style scoped>
        .snap-back {
          display: inline-block;
          margin: 16px auto 0;
          max-width: 900px;
          width: calc(100% - 48px);
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
        .snap-back:hover {
          background: #faf8f6;
          border-color: #2a9d8f;
          color: #2a9d8f;
        }
        .snap-iso {
          padding: 24px;
          font-family: system-ui, sans-serif;
          max-width: 900px;
          margin: 0 auto;
          color: #1a202c;
        }
        h1 {
          margin: 0 0 12px;
          color: #2c5282;
          font-size: 22px;
        }
        .meta {
          display: flex;
          flex-direction: column;
          gap: 4px;
          font-size: 13px;
          color: #4a5568;
          margin-bottom: 20px;
          padding: 12px 16px;
          background: #f7fafc;
          border-left: 4px solid #319795;
          border-radius: 4px;
        }
        .markdown-section h2 {
          font-size: 14px;
          color: #4a5568;
          margin: 0 0 8px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .markdown-box {
          background: #1a202c;
          color: #e2e8f0;
          padding: 16px;
          border-radius: 6px;
          font-family: ui-monospace, monospace;
          font-size: 12px;
          line-height: 1.6;
          white-space: pre-wrap;
          word-break: break-word;
          max-height: 600px;
          overflow-y: auto;
        }
      </style>
    </template>
  };
}
