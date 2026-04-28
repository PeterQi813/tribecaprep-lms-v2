import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
export class ProgramMaterial extends FieldDef {
  static displayName = 'Program Material';
  @field materialType = contains(StringField);
  @field name = contains(StringField);
  @field detail = contains(StringField);
}

export class ProgramRecord extends CardDef {
  static displayName = 'Program Record';

  @field studentName = contains(StringField);
  @field studentId = contains(StringField);
  @field program = contains(StringField);
  @field domain = contains(StringField);
  @field domainKey = contains(StringField);
  @field abllsCode = contains(StringField);
  @field masterSheet = contains(StringField);
  @field programSheet = contains(StringField);
  @field started = contains(StringField);
  @field currentTarget = contains(StringField);
  @field active = contains(StringField);
  @field notes = contains(StringField);
  @field scheduledWeek = contains(StringField);
  @field dueDate = contains(StringField);
  @field targetMastery = contains(NumberField);   // 0-100%
  @field materials = containsMany(ProgramMaterial);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProgramRecord) {
      return this.program && this.domain
        ? `${this.program} — ${this.domain}`
        : 'Program Record';
    },
  });

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='prog-row'>
        <span class='pr-name'>{{@model.program}}</span>
        <span class='pr-domain'>{{@model.domain}}</span>
        <span class='pr-code'>{{@model.abllsCode}}</span>
      </div>
      <style scoped>
        .prog-row { display: flex; align-items: center; gap: 0.75rem; padding: 0.5rem 0.75rem; font-family: 'Inter', system-ui, sans-serif; font-size: 0.8125rem; }
        .pr-name { font-weight: 500; flex: 1; }
        .pr-domain { font-size: 0.6875rem; padding: 0.15rem 0.4rem; border-radius: 4px; background: #f5f2ef; color: #5c5650; }
        .pr-code { font-size: 0.75rem; color: #8a8279; }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get isActive() { return this.args.model.active === 'Yes'; }
    get hasNotes() { return !!(this.args.model.notes); }
    get hasMaterials() { return (this.args.model.materials || []).length > 0; }
    get isPrimary() { return (mat: any) => (mat?.materialType || '') === 'Primary'; }

    <template>
      <div class='pr-card'>
        <a class='back-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/AdminDashboard/main'>← Back to Admin Dashboard</a>
        <div class='pr-header'>
          <span class='pr-domain-tag'>{{@model.domain}}</span>
          <span class='pr-status {{if this.isActive "active" "inactive"}}'>{{if this.isActive "Active" "Discontinued"}}</span>
        </div>
        <h2 class='pr-title'>{{@model.program}}</h2>
        {{#if @model.abllsCode}}<div class='pr-code'>ABLLS: {{@model.abllsCode}}</div>{{/if}}
        {{#if @model.studentName}}<div class='pr-student'>{{@model.studentName}}</div>{{/if}}

        <div class='pr-grid'>
          <div class='pr-box'><span class='pr-label'>Master Sheet</span><span class='pr-val'>{{@model.masterSheet}}</span></div>
          <div class='pr-box'><span class='pr-label'>Program Sheet</span><span class='pr-val'>{{@model.programSheet}}</span></div>
          <div class='pr-box'><span class='pr-label'>Started</span><span class='pr-val'>{{@model.started}}</span></div>
          <div class='pr-box'><span class='pr-label'>Current Target</span><span class='pr-val'>{{@model.currentTarget}}</span></div>
          {{#if @model.dueDate}}<div class='pr-box'><span class='pr-label'>Due Date</span><span class='pr-val'>{{@model.dueDate}}</span></div>{{/if}}
          {{#if @model.targetMastery}}<div class='pr-box'><span class='pr-label'>Target Mastery</span><span class='pr-val'>{{@model.targetMastery}}%</span></div>{{/if}}
        </div>

        {{#if this.hasMaterials}}
          <div class='pr-mat-section'>
            <span class='pr-mat-title'>Instructional Materials</span>
            {{#each @model.materials as |mat|}}
              <div class='pr-mat-item {{if (this.isPrimary mat) "primary" "secondary"}}'>
                <span class='pr-mat-type'>{{mat.materialType}}</span>
                <span class='pr-mat-name'>{{mat.name}}</span>
                {{#if mat.detail}}<span class='pr-mat-detail'>{{mat.detail}}</span>{{/if}}
              </div>
            {{/each}}
          </div>
        {{/if}}

        {{#if this.hasNotes}}<div class='pr-notes'>{{@model.notes}}</div>{{/if}}
      </div>
      <style scoped>
        .back-link { display: inline-block; padding: 0.5rem 0; font-size: 0.8125rem; font-weight: 600; color: #7c5fc4; text-decoration: none; }
        .back-link:hover { text-decoration: underline; }
        .pr-card { padding: 1.5rem; background: #fffdfb; border-radius: 14px; box-shadow: 0 4px 12px rgba(26,24,22,0.06); max-width: 600px; margin: 0 auto; font-family: 'Inter', system-ui, sans-serif; display: flex; flex-direction: column; gap: 1rem; }
        .pr-header { display: flex; justify-content: space-between; align-items: center; }
        .pr-domain-tag { font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #7c5fc4; }
        .pr-status { font-size: 0.625rem; font-weight: 700; text-transform: uppercase; padding: 0.25rem 0.5rem; border-radius: 4px; }
        .pr-status.active { background: #e8f6f4; color: #2a9d8f; }
        .pr-status.inactive { background: #fdf0ee; color: #e05d50; }
        .pr-title { font-size: 1.375rem; font-weight: 600; margin: 0; color: #1a1816; }
        .pr-code { font-size: 0.8125rem; color: #8a8279; }
        .pr-student { font-size: 0.8125rem; font-weight: 600; color: #7c5fc4; padding: 0.25rem 0.625rem; background: rgba(124,95,196,0.08); border-radius: 1rem; display: inline-block; }
        .pr-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .pr-box { padding: 0.75rem; background: #faf8f6; border-radius: 6px; }
        .pr-label { display: block; font-size: 0.5625rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #8a8279; margin-bottom: 0.25rem; }
        .pr-val { font-size: 0.875rem; color: #1a1816; }
        .pr-mat-section { display: flex; flex-direction: column; gap: 0.5rem; padding-top: 0.75rem; border-top: 1px solid #ebe7e3; }
        .pr-mat-title { font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #5c5650; }
        .pr-mat-item { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 0.75rem; border-radius: 6px; }
        .pr-mat-item.primary { background: #fde8e8; }
        .pr-mat-item.secondary { background: #faf8f6; }
        .pr-mat-type { font-size: 0.625rem; font-weight: 700; text-transform: uppercase; color: #e05d50; min-width: 70px; }
        .pr-mat-item.secondary .pr-mat-type { color: #8a8279; }
        .pr-mat-name { font-size: 0.8125rem; font-weight: 600; color: #1a1816; }
        .pr-mat-detail { font-size: 0.75rem; color: #8a8279; margin-left: auto; }
        .pr-notes { padding: 0.75rem; background: #fdf6e8; border-left: 3px solid #c08b30; border-radius: 4px; font-size: 0.8125rem; color: #5c5650; }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='pr-edit'>
        <div class='pr-row'><label>Program Name</label><@fields.program /></div>
        <div class='pr-row'><label>Student</label><@fields.studentName /></div>
        <div class='pr-pair'>
          <div class='pr-row'><label>Domain</label><@fields.domain /></div>
          <div class='pr-row'><label>ABLLS Code</label><@fields.abllsCode /></div>
        </div>
        <div class='pr-pair'>
          <div class='pr-row'><label>Master Sheet</label><@fields.masterSheet /></div>
          <div class='pr-row'><label>Program Sheet</label><@fields.programSheet /></div>
        </div>
        <div class='pr-pair'>
          <div class='pr-row'><label>Started</label><@fields.started /></div>
          <div class='pr-row'><label>Due Date</label><@fields.dueDate /></div>
        </div>
        <div class='pr-row'><label>Current Target</label><@fields.currentTarget /></div>
        <div class='pr-pair'>
          <div class='pr-row'><label>Target Mastery (%)</label><@fields.targetMastery /></div>
          <div class='pr-row'><label>Active</label><@fields.active /></div>
        </div>
        <div class='pr-row'><label>Notes</label><@fields.notes /></div>
        <div class='pr-row'><label>Instructional Materials</label><@fields.materials /></div>
      </div>
      <style scoped>
        .pr-edit { display: flex; flex-direction: column; gap: 0.75rem; padding: 1rem; font-family: 'Inter', system-ui, sans-serif; }
        .pr-row { display: flex; flex-direction: column; gap: 0.25rem; }
        .pr-row label { font-size: 0.6875rem; font-weight: 600; color: #8a8279; text-transform: uppercase; letter-spacing: 0.05em; }
        .pr-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
      </style>
    </template>
  };
}
