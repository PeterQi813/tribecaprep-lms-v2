// ClassroomAlert — independent CardDef stored in classroom realm
// NO imports of Classroom or Student to avoid cyclic dependencies
import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import DatetimeField from 'https://cardstack.com/base/datetime';
import BooleanField from 'https://cardstack.com/base/boolean';

export class ClassroomAlert extends CardDef {
  static displayName = 'Classroom Alert';

  // Core fields
  @field alertType = contains(StringField);    // Pickup Change | Schedule | Sub Alert | Parent Note | Medical | Behavioral
  @field urgency = contains(StringField);      // Urgent | Info
  @field message = contains(StringField);      // Main text, e.g. "Jamie -> Aunt Wei @ 3:30"
  @field detail = contains(StringField);       // Extra info, e.g. "verified 8:15 AM"

  // Student association (string match, not linksTo — avoids cyclic dependency)
  @field studentName = contains(StringField);  // Empty = class-wide alert, set = student-specific

  // Lifecycle
  @field createdAt = contains(DatetimeField);
  @field expiresAt = contains(DatetimeField);  // Auto-hide after this time
  @field createdBy = contains(StringField);    // Staff name who created it
  @field verified = contains(BooleanField);    // Confirmed by front office
  @field verifiedAt = contains(StringField);   // e.g. "8:15 AM"
  @field resolved = contains(BooleanField);    // Dismissed by teacher

  @field title = contains(StringField, {
    computeVia: function (this: ClassroomAlert) {
      const type = this.alertType ?? 'Alert';
      const msg = this.message ?? '';
      return `${type}: ${msg}`.slice(0, 80);
    },
  });

  // ── Isolated View ──
  static isolated = class Isolated extends Component<typeof ClassroomAlert> {
    get typeColor() {
      switch (this.args.model?.alertType) {
        case 'Pickup Change': return '#e05d50';
        case 'Schedule': return '#2a7fd4';
        case 'Sub Alert': return '#7c5fc4';
        case 'Parent Note': return '#c08b30';
        case 'Medical': return '#e05d50';
        case 'Behavioral': return '#c08b30';
        default: return '#5c5650';
      }
    }
    get isResolved() { return this.args.model?.resolved === true; }
    get studentDisplay() { return this.args.model?.studentName || 'All Students'; }
    get createdDisplay() {
      const d = this.args.model?.createdAt;
      if (!d) return '';
      return new Date(d as any).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    }

    <template>
      <div class='alert-iso {{if this.isResolved "resolved"}}'>
        <div class='alert-header'>
          <span class='alert-type' style='color: {{this.typeColor}}'>{{@model.alertType}}</span>
          <span class='alert-urg'>{{@model.urgency}}</span>
          {{#if this.isResolved}}<span class='resolved-tag'>Resolved</span>{{/if}}
        </div>
        <p class='alert-msg'>{{@model.message}}</p>
        {{#if @model.detail}}<p class='alert-dtl'>{{@model.detail}}</p>{{/if}}
        <div class='alert-meta'>
          <span>Student: {{this.studentDisplay}}</span>
          {{#if this.createdDisplay}}<span>Created: {{this.createdDisplay}}</span>{{/if}}
          {{#if @model.createdBy}}<span>By: {{@model.createdBy}}</span>{{/if}}
          {{#if @model.verified}}<span>Verified {{@model.verifiedAt}}</span>{{/if}}
        </div>
      </div>
      <style scoped>
        .alert-iso { max-width: 500px; margin: 0 auto; padding: 1.5rem; display: flex; flex-direction: column; gap: 0.75rem; }
        .alert-iso.resolved { opacity: 0.5; }
        .alert-header { display: flex; align-items: center; gap: 0.75rem; }
        .alert-type { font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; }
        .alert-urg { font-size: 0.6875rem; color: #8a8279; }
        .resolved-tag { margin-left: auto; font-size: 0.625rem; font-weight: 700; background: rgba(42,157,143,0.1); color: #2a9d8f; padding: 0.25rem 0.5rem; border-radius: 4px; }
        .alert-msg { font-size: 1rem; font-weight: 500; color: #1a1816; margin: 0; }
        .alert-dtl { font-size: 0.875rem; color: #8a8279; margin: 0; }
        .alert-meta { display: flex; flex-wrap: wrap; gap: 0.5rem 1rem; border-top: 1px solid rgba(0,0,0,0.08); padding-top: 0.75rem; font-size: 0.6875rem; color: #8a8279; }
      </style>
    </template>
  };

  // ── Embedded View ──
  static embedded = class Embedded extends Component<typeof ClassroomAlert> {
    get typeColor() {
      switch (this.args.model?.alertType) {
        case 'Pickup Change': return '#e05d50';
        case 'Schedule': return '#2a7fd4';
        case 'Sub Alert': return '#7c5fc4';
        default: return '#c08b30';
      }
    }
    get isUrgent() { return this.args.model?.urgency === 'Urgent'; }

    <template>
      <div class='alert-emb {{if this.isUrgent "urgent"}}'>
        <span class='dot' style='background: {{this.typeColor}}'></span>
        <span class='type'>{{@model.alertType}}</span>
        <span class='msg'>{{@model.message}}</span>
        {{#if @model.detail}}<span class='dtl'>{{@model.detail}}</span>{{/if}}
      </div>
      <style scoped>
        .alert-emb { display: flex; align-items: center; gap: 0.375rem; padding: 0.5rem 0.625rem; border-radius: 8px; border: 1px solid rgba(0,0,0,0.08); background: rgba(0,0,0,0.02); flex-wrap: wrap; }
        .alert-emb.urgent { border-color: rgba(224,93,80,0.2); background: rgba(224,93,80,0.05); }
        .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
        .type { font-size: 0.625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #5c5650; }
        .msg { font-size: 0.8125rem; color: #1a1816; font-weight: 500; }
        .dtl { font-size: 0.6875rem; color: #8a8279; }
      </style>
    </template>
  };

  // ── Edit View ──
  static edit = class Edit extends Component<typeof ClassroomAlert> {
    <template>
      <div class='alert-edit'>
        <div class='row'><label>Type</label><@fields.alertType /></div>
        <div class='row'><label>Urgency</label><@fields.urgency /></div>
        <div class='row'><label>Message</label><@fields.message /></div>
        <div class='row'><label>Detail</label><@fields.detail /></div>
        <div class='row'><label>Student Name</label><@fields.studentName /></div>
        <div class='row'><label>Created By</label><@fields.createdBy /></div>
        <div class='row'><label>Verified</label><@fields.verified /></div>
        <div class='row'><label>Verified At</label><@fields.verifiedAt /></div>
        <div class='row'><label>Resolved</label><@fields.resolved /></div>
      </div>
      <style scoped>
        .alert-edit { display: flex; flex-direction: column; gap: 0.75rem; padding: 1rem; }
        .row { display: flex; flex-direction: column; gap: 0.25rem; }
        .row label { font-size: 0.6875rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}
// touched for re-index
