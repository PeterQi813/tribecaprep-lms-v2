import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';

// ─── TagType wrapper ───
export class TagType extends FieldDef {
  static displayName = 'Tag Type';
  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

// ─── LocationStatusEnum wrapper ───
export class LocationStatusEnum extends FieldDef {
  static displayName = 'Location Status Enum';
  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

// ─── StudentTag ───
export class StudentTag extends FieldDef {
  static displayName = 'Student Tag';

  @field label = contains(StringField);
  @field color = contains(StringField);
  @field tagType = contains(TagType);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='tag' style='background: {{@model.color}}20; color: {{@model.color}};'>
        <span class='tag-label'><@fields.label /></span>
      </div>
      <div class='tag-meta'>
        <label class='meta-row'><span class='meta-label'>Color</span><@fields.color /></label>
        <label class='meta-row'><span class='meta-label'>Type</span><@fields.tagType /></label>
      </div>
      <style scoped>
        .tag {
          display: inline-flex;
          align-items: center;
          padding: 0.1875rem 0.5rem;
          font-size: 0.6875rem;
          font-weight: 600;
          border-radius: 4px;
          letter-spacing: 0.02em;
        }
        .tag-meta {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          margin-top: 0.375rem;
        }
        .meta-row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.75rem;
        }
        .meta-label {
          font-size: 0.625rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #8a8279;
          min-width: 3rem;
        }
      </style>
    </template>
  };
}

// ─── LocationStatus ───
export class LocationStatus extends FieldDef {
  static displayName = 'Location Status';

  @field location = contains(StringField);
  @field status = contains(LocationStatusEnum);
  @field since = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='location'>
        <span class='status-dot'></span>
        <span class='location-text'><@fields.location /></span>
      </div>
      <div class='location-details'>
        <label class='detail-row'><span class='detail-label'>Status</span><@fields.status /></label>
        <label class='detail-row'><span class='detail-label'>Since</span><@fields.since /></label>
      </div>
      <style scoped>
        .location {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
        }
        .status-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--accent, #00e7ca);
        }
        .location-text { color: var(--foreground, #1a1816); }
        .location-details {
          display: flex;
          gap: 1rem;
          margin-top: 0.375rem;
        }
        .detail-row {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.75rem;
        }
        .detail-label {
          font-size: 0.625rem;
          font-weight: 500;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: #8a8279;
        }
      </style>
    </template>
  };
}

// ─── TribecaPrepCardInfo ───
export class TribecaPrepCardInfo extends FieldDef {
  static displayName = 'Tribeca Prep Card Info';

  @field title = contains(StringField);
  @field description = contains(StringField);
  @field thumbnailURL = contains(StringField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='card-info'>
        <div class='info-row'><span class='info-label'>Title</span><span class='info-title'><@fields.title /></span></div>
        <div class='info-row'><span class='info-label'>Description</span><span class='info-desc'><@fields.description /></span></div>
        <div class='info-row'><span class='info-label'>Thumbnail</span><@fields.thumbnailURL /></div>
        <div class='info-row'><span class='info-label'>Notes</span><@fields.notes /></div>
      </div>
      <style scoped>
        .card-info { display: flex; flex-direction: column; gap: 0.375rem; }
        .info-row { display: flex; flex-direction: column; gap: 0.125rem; }
        .info-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
        .info-title { font-weight: 600; font-size: 0.875rem; }
        .info-desc { font-size: 0.75rem; color: var(--muted-foreground, #6c6a81); }
      </style>
    </template>
  };
}
// touched for re-index
