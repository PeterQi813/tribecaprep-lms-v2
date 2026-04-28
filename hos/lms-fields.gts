import {
  FieldDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';

// ─── Relationship wrapper ───
export class RelationshipType extends FieldDef {
  static displayName = 'Relationship Type';
  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

// ─── Address ───
export class Address extends FieldDef {
  static displayName = 'Address';

  @field street1 = contains(StringField);
  @field street2 = contains(StringField);
  @field city = contains(StringField);
  @field state = contains(StringField);
  @field zipCode = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='address'>
        <div class='addr-row'><span class='addr-label'>Street</span><@fields.street1 /></div>
        <div class='addr-row'><span class='addr-label'>Street 2</span><@fields.street2 /></div>
        <div class='addr-inline'>
          <div class='addr-row'><span class='addr-label'>City</span><@fields.city /></div>
          <div class='addr-row'><span class='addr-label'>State</span><@fields.state /></div>
          <div class='addr-row'><span class='addr-label'>Zip</span><@fields.zipCode /></div>
        </div>
      </div>
      <style scoped>
        .address { display: flex; flex-direction: column; gap: 0.375rem; font-size: 0.8125rem; color: var(--foreground, #1a1816); }
        .addr-row { display: flex; flex-direction: column; gap: 0.125rem; }
        .addr-inline { display: grid; grid-template-columns: 1fr auto auto; gap: 0.75rem; }
        .addr-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

// ─── ParentInfo ───
export class ParentInfo extends FieldDef {
  static displayName = 'Parent Info';

  @field firstName = contains(StringField);
  @field lastName = contains(StringField);
  @field relationship = contains(RelationshipType);
  @field email = contains(StringField);
  @field phone = contains(StringField);
  @field phoneAlt = contains(StringField);
  @field workPhone = contains(StringField);
  @field employer = contains(StringField);
  @field address = contains(Address);
  @field isPrimaryContact = contains(BooleanField);
  @field portalAccess = contains(BooleanField);
  @field receivesReports = contains(BooleanField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='parent'>
        <div class='parent-row-inline'>
          <div class='field-col'><span class='field-label'>First Name</span><@fields.firstName /></div>
          <div class='field-col'><span class='field-label'>Last Name</span><@fields.lastName /></div>
        </div>
        <div class='field-col'><span class='field-label'>Relationship</span><@fields.relationship /></div>
        <div class='parent-row-inline'>
          <div class='field-col'><span class='field-label'>Phone</span><@fields.phone /></div>
          <div class='field-col'><span class='field-label'>Alt Phone</span><@fields.phoneAlt /></div>
          <div class='field-col'><span class='field-label'>Work Phone</span><@fields.workPhone /></div>
        </div>
        <div class='field-col'><span class='field-label'>Email</span><@fields.email /></div>
        <div class='field-col'><span class='field-label'>Employer</span><@fields.employer /></div>
        <div class='field-col'><span class='field-label'>Address</span><@fields.address /></div>
        <div class='parent-row-inline'>
          <div class='field-col'><span class='field-label'>Primary Contact</span><@fields.isPrimaryContact /></div>
          <div class='field-col'><span class='field-label'>Portal Access</span><@fields.portalAccess /></div>
          <div class='field-col'><span class='field-label'>Receives Reports</span><@fields.receivesReports /></div>
        </div>
      </div>
      <style scoped>
        .parent { display: flex; flex-direction: column; gap: 0.5rem; padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; }
        .parent-row-inline { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}
// touched for re-index
