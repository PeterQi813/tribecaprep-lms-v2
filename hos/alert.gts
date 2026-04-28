import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';

const AlertTypeField = enumField(StringField, {
  options: ['Pickup Change', 'Schedule', 'Sub Alert', 'Parent Note'],
});

const UrgencyField = enumField(StringField, {
  options: ['Urgent', 'Info'],
});

export class Alert extends FieldDef {
  static displayName = 'Alert';

  @field alertType = contains(AlertTypeField);
  @field urgency = contains(UrgencyField);
  @field message = contains(StringField);
  @field detail = contains(StringField);

  static embedded = class Embedded extends Component<typeof Alert> {
    get safeType() {
      return this.args.model?.alertType ?? 'Info';
    }

    get safeMessage() {
      return this.args.model?.message ?? '';
    }

    get isUrgent() {
      return this.args.model?.urgency === 'Urgent';
    }

    get alertIcon() {
      switch (this.args.model?.alertType) {
        case 'Pickup Change': return '\u{1F697}';
        case 'Schedule': return '\u{1F4C5}';
        case 'Sub Alert': return '\u{1F465}';
        case 'Parent Note': return '\u{1F4DD}';
        default: return '\u{2139}\u{FE0F}';
      }
    }

    get bgColor() {
      if (this.isUrgent) return 'rgba(224, 93, 80, 0.08)';
      return 'rgba(138, 130, 121, 0.06)';
    }

    get borderColor() {
      if (this.isUrgent) return 'rgba(224, 93, 80, 0.2)';
      return 'rgba(138, 130, 121, 0.15)';
    }

    <template>
      <div class='alert-row' style='background: {{this.bgColor}}; border-color: {{this.borderColor}}'>
        <span class='alert-icon'>{{this.alertIcon}}</span>
        <div class='alert-content'>
          <span class='alert-type'>{{this.safeType}}</span>
          <span class='alert-message'>{{this.safeMessage}}</span>
          {{#if @model.detail}}
            <span class='alert-detail'>{{@model.detail}}</span>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .alert-row {
          display: flex;
          align-items: flex-start;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
          border-radius: 8px;
          border: 1px solid;
        }

        .alert-icon {
          font-size: 0.875rem;
          flex-shrink: 0;
          margin-top: 0.0625rem;
        }

        .alert-content {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem 0.5rem;
          align-items: baseline;
        }

        .alert-type {
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: #e05d50;
        }

        .alert-message {
          font-size: 0.8125rem;
          color: #1a1816;
          font-weight: 500;
        }

        .alert-detail {
          font-size: 0.6875rem;
          color: #8a8279;
          font-weight: 500;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof Alert> {
    <template>
      <div class='alert-edit'>
        <div class='field-row'>
          <label>Type</label>
          <@fields.alertType />
        </div>
        <div class='field-row'>
          <label>Urgency</label>
          <@fields.urgency />
        </div>
        <div class='field-row'>
          <label>Message</label>
          <@fields.message />
        </div>
        <div class='field-row'>
          <label>Detail</label>
          <@fields.detail />
        </div>
      </div>

      <style scoped>
        .alert-edit {
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

