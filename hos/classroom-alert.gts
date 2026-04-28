// ClassroomAlert — mirror card in HoS realm
// Simplified from Classroom's version: flat fields, no cross-realm linksTo
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

  @field alertType = contains(StringField);    // Pickup Change | Schedule | Sub Alert | Parent Note | Medical | Behavioral
  @field urgency = contains(StringField);      // Urgent | Info
  @field message = contains(StringField);
  @field detail = contains(StringField);
  @field studentName = contains(StringField);  // empty = class-wide
  @field createdAt = contains(DatetimeField);
  @field expiresAt = contains(DatetimeField);
  @field createdBy = contains(StringField);
  @field verified = contains(BooleanField);
  @field verifiedAt = contains(StringField);
  @field resolved = contains(BooleanField);
  @field sourceAlertId = contains(StringField);  // URL of source ClassroomAlert in Classroom realm

  @field title = contains(StringField, {
    computeVia: function (this: ClassroomAlert) {
      return `${this.alertType ?? 'Alert'}: ${this.message ?? ''}`.slice(0, 80);
    },
  });

  static embedded = class Embedded extends Component<typeof ClassroomAlert> {
    get typeColor() {
      switch (this.args.model?.alertType) {
        case 'Pickup Change': return '#e05d50';
        case 'Schedule': return '#2a7fd4';
        case 'Sub Alert': return '#7c5fc4';
        default: return '#c08b30';
      }
    }
    <template>
      <div class='alert-row'>
        <span class='dot' style='background: {{this.typeColor}}'></span>
        <div class='body'>
          <span class='type'>{{@model.alertType}}</span>
          <span class='msg'>{{@model.message}}</span>
          {{#if @model.detail}}<span class='dtl'>{{@model.detail}}</span>{{/if}}
        </div>
      </div>
      <style scoped>
        .alert-row { display: flex; gap: 0.5rem; padding: 0.5rem; align-items: center; border-radius: 6px; }
        .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
        .body { display: flex; flex-direction: column; gap: 0.125rem; }
        .type { font-size: 0.625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: rgba(255,255,255,0.6); }
        .msg { font-size: 0.8125rem; color: white; font-weight: 500; }
        .dtl { font-size: 0.6875rem; color: rgba(255,255,255,0.5); }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof ClassroomAlert> {
    <template>
      <div class='edit'>
        <div class='row'><label>Alert Type</label><@fields.alertType /></div>
        <div class='row'><label>Urgency</label><@fields.urgency /></div>
        <div class='row'><label>Message</label><@fields.message /></div>
        <div class='row'><label>Detail</label><@fields.detail /></div>
        <div class='row'><label>Student Name</label><@fields.studentName /></div>
        <div class='row'><label>Resolved</label><@fields.resolved /></div>
      </div>
      <style scoped>
        .edit { display: flex; flex-direction: column; gap: 0.75rem; padding: 1rem; }
        .row { display: flex; flex-direction: column; gap: 0.25rem; }
        .row label { font-size: 0.6875rem; font-weight: 600; text-transform: uppercase; color: #8a8279; }
      </style>
    </template>
  };
}
// touched for re-index
