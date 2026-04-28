import {
  FieldDef,
  field,
  contains,
  containsMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';

import { GradeLevel } from './enums';

// ═══════════════════════════════════════════════════════════════════════════════
// Enum wrapper FieldDefs — stored as { "value": "string" } in JSON
// ═══════════════════════════════════════════════════════════════════════════════

class SeverityLevel extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

class AdminLocation extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

class CustodyType extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

class AidStatus extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

class PaymentStatus extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

class RelationshipType extends FieldDef {
  @field value = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template><span><@fields.value /></span></template>
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sub-fields used within sections
// ═══════════════════════════════════════════════════════════════════════════════

export class Address extends FieldDef {
  static displayName = 'Address';
  @field street1 = contains(StringField);
  @field street2 = contains(StringField);
  @field city = contains(StringField);
  @field state = contains(StringField);
  @field zipCode = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='addr'>
        <div class='addr-row'><span class='addr-label'>Street</span><@fields.street1 /></div>
        <div class='addr-row'><span class='addr-label'>Street 2</span><@fields.street2 /></div>
        <div class='addr-inline'>
          <div class='addr-row'><span class='addr-label'>City</span><@fields.city /></div>
          <div class='addr-row'><span class='addr-label'>State</span><@fields.state /></div>
          <div class='addr-row'><span class='addr-label'>Zip</span><@fields.zipCode /></div>
        </div>
      </div>
      <style scoped>
        .addr { display: flex; flex-direction: column; gap: 0.375rem; font-size: 0.8125rem; }
        .addr-row { display: flex; flex-direction: column; gap: 0.125rem; }
        .addr-inline { display: grid; grid-template-columns: 1fr auto auto; gap: 0.75rem; }
        .addr-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class AllergyEntry extends FieldDef {
  static displayName = 'Allergy Entry';
  @field allergen = contains(StringField);
  @field severity = contains(SeverityLevel);
  @field reaction = contains(StringField);
  @field treatment = contains(StringField);
  @field epiPenRequired = contains(BooleanField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='allergy'>
        <div class='allergy-row-inline'>
          <div class='field-col'><span class='field-label'>Allergen</span><@fields.allergen /></div>
          <div class='field-col'><span class='field-label'>Severity</span><@fields.severity /></div>
        </div>
        <div class='field-col'><span class='field-label'>Reaction</span><@fields.reaction /></div>
        <div class='field-col'><span class='field-label'>Treatment</span><@fields.treatment /></div>
        <div class='allergy-row-inline'>
          <div class='field-col'><span class='field-label'>EpiPen Required</span><@fields.epiPenRequired /></div>
          <div class='field-col'><span class='field-label'>Notes</span><@fields.notes /></div>
        </div>
      </div>
      <style scoped>
        .allergy { padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; margin-bottom: 0.5rem; display: flex; flex-direction: column; gap: 0.5rem; }
        .allergy-row-inline { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class MedicationEntry extends FieldDef {
  static displayName = 'Medication Entry';
  @field medicationName = contains(StringField);
  @field dosage = contains(StringField);
  @field frequency = contains(StringField);
  @field administeredAt = contains(AdminLocation);
  @field prescribingDoctor = contains(StringField);
  @field startDate = contains(StringField);
  @field endDate = contains(StringField);
  @field sideEffects = contains(StringField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='med'>
        <div class='field-col'><span class='field-label'>Medication</span><@fields.medicationName /></div>
        <div class='med-row-inline'>
          <div class='field-col'><span class='field-label'>Dosage</span><@fields.dosage /></div>
          <div class='field-col'><span class='field-label'>Frequency</span><@fields.frequency /></div>
          <div class='field-col'><span class='field-label'>Administered At</span><@fields.administeredAt /></div>
        </div>
        <div class='field-col'><span class='field-label'>Prescribing Doctor</span><@fields.prescribingDoctor /></div>
        <div class='med-row-inline'>
          <div class='field-col'><span class='field-label'>Start Date</span><@fields.startDate /></div>
          <div class='field-col'><span class='field-label'>End Date</span><@fields.endDate /></div>
        </div>
        <div class='field-col'><span class='field-label'>Side Effects</span><@fields.sideEffects /></div>
        <div class='field-col'><span class='field-label'>Notes</span><@fields.notes /></div>
      </div>
      <style scoped>
        .med { display: flex; flex-direction: column; gap: 0.5rem; padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; margin-bottom: 0.5rem; }
        .med-row-inline { display: grid; grid-template-columns: repeat(auto-fit, minmax(100px, 1fr)); gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class PhysicianInfo extends FieldDef {
  static displayName = 'Physician Info';
  @field name = contains(StringField);
  @field phone = contains(StringField);
  @field fax = contains(StringField);
  @field email = contains(StringField);
  @field address = contains(Address);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='physician'>
        <div class='field-col'><span class='field-label'>Name</span><@fields.name /></div>
        <div class='ph-row-inline'>
          <div class='field-col'><span class='field-label'>Phone</span><@fields.phone /></div>
          <div class='field-col'><span class='field-label'>Fax</span><@fields.fax /></div>
        </div>
        <div class='field-col'><span class='field-label'>Email</span><@fields.email /></div>
        <div class='field-col'><span class='field-label'>Address</span><@fields.address /></div>
      </div>
      <style scoped>
        .physician { display: flex; flex-direction: column; gap: 0.5rem; padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; }
        .ph-row-inline { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class ParentContact extends FieldDef {
  static displayName = 'Parent Contact';
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
        .parent { padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; display: flex; flex-direction: column; gap: 0.5rem; }
        .parent-row-inline { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class EmergencyContact extends FieldDef {
  static displayName = 'Emergency Contact';
  @field name = contains(StringField);
  @field relationship = contains(StringField);
  @field phone = contains(StringField);
  @field phoneAlt = contains(StringField);
  @field priority = contains(NumberField);
  @field authorizedPickup = contains(BooleanField);
  @field hasKey = contains(BooleanField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ec'>
        <div class='ec-row-inline'>
          <div class='field-col'><span class='field-label'>Name</span><@fields.name /></div>
          <div class='field-col'><span class='field-label'>Relationship</span><@fields.relationship /></div>
        </div>
        <div class='ec-row-inline'>
          <div class='field-col'><span class='field-label'>Phone</span><@fields.phone /></div>
          <div class='field-col'><span class='field-label'>Alt Phone</span><@fields.phoneAlt /></div>
        </div>
        <div class='ec-row-inline'>
          <div class='field-col'><span class='field-label'>Priority</span><@fields.priority /></div>
          <div class='field-col'><span class='field-label'>Authorized Pickup</span><@fields.authorizedPickup /></div>
          <div class='field-col'><span class='field-label'>Has Key</span><@fields.hasKey /></div>
        </div>
        <div class='field-col'><span class='field-label'>Notes</span><@fields.notes /></div>
      </div>
      <style scoped>
        .ec { display: flex; flex-direction: column; gap: 0.5rem; padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; margin-bottom: 0.5rem; }
        .ec-row-inline { display: grid; grid-template-columns: repeat(auto-fit, minmax(100px, 1fr)); gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class AuthorizedPickup extends FieldDef {
  static displayName = 'Authorized Pickup';
  @field name = contains(StringField);
  @field relationship = contains(StringField);
  @field phone = contains(StringField);
  @field photoIdRequired = contains(BooleanField);
  @field validUntil = contains(StringField);
  @field notes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ap'>
        <div class='ap-row-inline'>
          <div class='field-col'><span class='field-label'>Name</span><@fields.name /></div>
          <div class='field-col'><span class='field-label'>Relationship</span><@fields.relationship /></div>
        </div>
        <div class='ap-row-inline'>
          <div class='field-col'><span class='field-label'>Phone</span><@fields.phone /></div>
          <div class='field-col'><span class='field-label'>Valid Until</span><@fields.validUntil /></div>
        </div>
        <div class='ap-row-inline'>
          <div class='field-col'><span class='field-label'>Photo ID Required</span><@fields.photoIdRequired /></div>
        </div>
        <div class='field-col'><span class='field-label'>Notes</span><@fields.notes /></div>
      </div>
      <style scoped>
        .ap { display: flex; flex-direction: column; gap: 0.5rem; padding: 0.75rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 10px; margin-bottom: 0.5rem; }
        .ap-row-inline { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

export class RestrictedPerson extends FieldDef {
  static displayName = 'Restricted Person';
  @field name = contains(StringField);
  @field relationship = contains(StringField);
  @field description = contains(StringField);
  @field courtOrderOnFile = contains(BooleanField);
  @field actionIfAppears = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='rp'>
        <div class='rp-row-inline'>
          <div class='field-col'><span class='field-label'>Name</span><@fields.name /></div>
          <div class='field-col'><span class='field-label'>Relationship</span><@fields.relationship /></div>
        </div>
        <div class='field-col'><span class='field-label'>Description</span><@fields.description /></div>
        <div class='field-col'><span class='field-label'>Court Order on File</span><@fields.courtOrderOnFile /></div>
        <div class='field-col'><span class='field-label'>Action If Appears</span><@fields.actionIfAppears /></div>
      </div>
      <style scoped>
        .rp { padding: 0.75rem; background: #fdf0ee; border: 1px solid #fbd5d0; border-radius: 10px; margin-bottom: 0.5rem; display: flex; flex-direction: column; gap: 0.5rem; }
        .rp-row-inline { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .field-col { display: flex; flex-direction: column; gap: 0.125rem; }
        .field-label { font-size: 0.625rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
      </style>
    </template>
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION FIELD DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════════

export class IdentitySection extends FieldDef {
  static displayName = 'Identity Section';

  @field studentId = contains(StringField);
  @field firstName = contains(StringField);
  @field lastName = contains(StringField);
  @field preferredName = contains(StringField);
  @field dateOfBirth = contains(StringField);
  @field gradeLevel = contains(GradeLevel);
  @field enrollmentDate = contains(StringField);
  @field withdrawalDate = contains(StringField);
  @field active = contains(BooleanField);
  @field photoUrl = contains(StringField);

  @field displayName = contains(StringField, {
    computeVia: function (this: IdentitySection) {
      const name = this.preferredName || this.firstName || '';
      const last = this.lastName || '';
      return `${name} ${last}`.trim() || 'Unknown Student';
    },
  });

  @field fullName = contains(StringField, {
    computeVia: function (this: IdentitySection) {
      return `${this.firstName || ''} ${this.lastName || ''}`.trim() || 'Unknown Student';
    },
  });

  @field initials = contains(StringField, {
    computeVia: function (this: IdentitySection) {
      const first = (this.firstName || '').charAt(0).toUpperCase();
      const last = (this.lastName || '').charAt(0).toUpperCase();
      return `${first}${last}` || '??';
    },
  });

  @field age = contains(NumberField, {
    computeVia: function (this: IdentitySection) {
      if (!this.dateOfBirth) return 0;
      const dob = new Date(this.dateOfBirth);
      const now = new Date();
      let age = now.getFullYear() - dob.getFullYear();
      const m = now.getMonth() - dob.getMonth();
      if (m < 0 || (m === 0 && now.getDate() < dob.getDate())) age--;
      return age;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-identity' class='section'>
        <h2 class='section-title'>Overview</h2>
        <div class='fields-grid'>
          <div class='field-item'>
            <span class='field-label'>Student ID</span>
            <span class='field-value mono'><@fields.studentId /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>First Name</span>
            <span class='field-value'><@fields.firstName /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Last Name</span>
            <span class='field-value'><@fields.lastName /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Preferred Name</span>
            <span class='field-value'><@fields.preferredName /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Date of Birth</span>
            <span class='field-value'><@fields.dateOfBirth /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Grade</span>
            <@fields.gradeLevel />
          </div>
          <div class='field-item'>
            <span class='field-label'>Enrollment Date</span>
            <span class='field-value'><@fields.enrollmentDate /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Withdrawal Date</span>
            <span class='field-value'><@fields.withdrawalDate /></span>
          </div>
          <div class='field-item'>
            <span class='field-label'>Status</span>
            <@fields.active />
          </div>
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .fields-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
        .field-item { display: flex; flex-direction: column; gap: 0.25rem; }
        .field-label { font-size: 0.6875rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
        .field-value { font-size: 0.875rem; color: #1a1816; }
        .field-value.mono { font-family: ui-monospace, monospace; font-size: 0.8125rem; }
      </style>
    </template>
  };
}

export class MedicalSection extends FieldDef {
  static displayName = 'Medical Section';

  @field medicalConditions = contains(StringField);
  @field allergies = containsMany(AllergyEntry);
  @field medications = containsMany(MedicationEntry);
  @field dietaryRestrictions = contains(StringField);
  @field primaryPhysician = contains(PhysicianInfo);
  @field medicalNotes = contains(StringField);

  @field hasAllergy = contains(BooleanField, {
    computeVia: function (this: MedicalSection) {
      return (this.allergies?.length ?? 0) > 0;
    },
  });

  @field hasMedication = contains(BooleanField, {
    computeVia: function (this: MedicalSection) {
      return (this.medications?.length ?? 0) > 0;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-medical' class='section'>
        <h2 class='section-title'>Medical</h2>
        <div class='subsection'>
          <h3 class='subsection-title'>Conditions</h3>
          <@fields.medicalConditions />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Allergies</h3>
          <@fields.allergies @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Medications</h3>
          <@fields.medications @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Dietary Restrictions</h3>
          <@fields.dietaryRestrictions />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Primary Physician</h3>
          <@fields.primaryPhysician @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Medical Notes</h3>
          <@fields.medicalNotes />
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .subsection { margin-bottom: 1rem; }
        .subsection-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; margin: 0 0 0.5rem; }
      </style>
    </template>
  };
}

export class FamilySection extends FieldDef {
  static displayName = 'Family Section';

  @field primaryParent = contains(ParentContact);
  @field secondaryParent = contains(ParentContact);
  @field emergencyContacts = containsMany(EmergencyContact);
  @field householdNotes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-family' class='section'>
        <h2 class='section-title'>Family</h2>
        <div class='subsection'>
          <h3 class='subsection-title'>Primary Parent/Guardian</h3>
          <@fields.primaryParent @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Secondary Parent/Guardian</h3>
          <@fields.secondaryParent @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Emergency Contacts</h3>
          <@fields.emergencyContacts @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Household Notes</h3>
          <@fields.householdNotes />
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .subsection { margin-bottom: 1rem; }
        .subsection-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; margin: 0 0 0.5rem; }
      </style>
    </template>
  };
}

export class CustodySection extends FieldDef {
  static displayName = 'Custody Section';

  @field custodyArrangement = contains(CustodyType);
  @field custodyNotes = contains(StringField);
  @field authorizedPickups = containsMany(AuthorizedPickup);
  @field restrictedPersons = containsMany(RestrictedPerson);
  @field legalDocuments = contains(StringField);

  @field hasCustodyAlert = contains(BooleanField, {
    computeVia: function (this: CustodySection) {
      return (this.restrictedPersons?.length ?? 0) > 0;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-custody' class='section'>
        <h2 class='section-title'>Custody</h2>
        <div class='subsection'>
          <h3 class='subsection-title'>Arrangement</h3>
          <@fields.custodyArrangement />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Notes</h3>
          <@fields.custodyNotes />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Authorized Pickups</h3>
          <@fields.authorizedPickups @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Restricted Persons</h3>
          <@fields.restrictedPersons @format='embedded' />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Legal Documents</h3>
          <@fields.legalDocuments />
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .subsection { margin-bottom: 1rem; }
        .subsection-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; margin: 0 0 0.5rem; }
      </style>
    </template>
  };
}

export class FinancialSection extends FieldDef {
  static displayName = 'Financial Section';

  @field financialAidStatus = contains(AidStatus);
  @field scholarshipPercent = contains(NumberField);
  @field paymentStatus = contains(PaymentStatus);
  @field billingNotes = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-financial' class='section'>
        <h2 class='section-title'>Financial</h2>
        <div class='fields-grid'>
          <div class='field-item'>
            <span class='field-label'>Financial Aid</span>
            <@fields.financialAidStatus />
          </div>
          <div class='field-item'>
            <span class='field-label'>Scholarship %</span>
            <@fields.scholarshipPercent />
          </div>
          <div class='field-item'>
            <span class='field-label'>Payment Status</span>
            <@fields.paymentStatus />
          </div>
        </div>
        <div class='notes'>
          <h3 class='subsection-title'>Billing Notes</h3>
          <@fields.billingNotes />
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .fields-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 1rem; }
        .field-item { display: flex; flex-direction: column; gap: 0.25rem; }
        .field-label { font-size: 0.6875rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
        .notes { margin-top: 1rem; }
        .subsection-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; margin: 0 0 0.5rem; }
      </style>
    </template>
  };
}

export class IEPSection extends FieldDef {
  static displayName = 'IEP/504 Section';

  @field hasIEP = contains(BooleanField);
  @field iepDate = contains(StringField);
  @field iepSummary = contains(StringField);
  @field has504 = contains(BooleanField);
  @field accommodations = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <section id='section-iep' class='section'>
        <h2 class='section-title'>IEP / 504</h2>
        <div class='fields-grid'>
          <div class='field-item'>
            <span class='field-label'>Has IEP</span>
            <@fields.hasIEP />
          </div>
          <div class='field-item'>
            <span class='field-label'>Has 504</span>
            <@fields.has504 />
          </div>
          <div class='field-item'>
            <span class='field-label'>IEP Date</span>
            <@fields.iepDate />
          </div>
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Summary</h3>
          <@fields.iepSummary />
        </div>
        <div class='subsection'>
          <h3 class='subsection-title'>Accommodations</h3>
          <@fields.accommodations />
        </div>
      </section>
      <style scoped>
        .section { padding: 1.5rem; background: #fffdfb; border: 1px solid #ebe7e3; border-radius: 14px; }
        .section-title { margin: 0 0 1rem; font-size: 1rem; font-weight: 600; color: #1a1816; }
        .fields-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 1rem; margin-bottom: 1rem; }
        .field-item { display: flex; flex-direction: column; gap: 0.25rem; }
        .field-label { font-size: 0.6875rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; }
        .subsection { margin-bottom: 1rem; }
        .subsection-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #8a8279; margin: 0 0 0.5rem; }
      </style>
    </template>
  };
}

