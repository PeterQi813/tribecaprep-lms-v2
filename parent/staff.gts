import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import UserIcon from '@cardstack/boxel-icons/user';

const RoleField = enumField(StringField, {
  options: ['Lead Teacher', 'Assistant', 'Specialist', 'Aide', 'Substitute'],
});

export class Staff extends CardDef {
  static displayName = 'Staff';
  static icon = UserIcon;

  @field name = contains(StringField);
  @field role = contains(RoleField);
  @field initials = contains(StringField);
  @field color = contains(StringField);
  @field avatar = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: Staff) {
      return this.name ?? 'Unnamed Staff';
    },
  });

  static isolated = class Isolated extends Component<typeof Staff> {
    get safeName() {
      return this.args.model?.name ?? 'Unnamed Staff';
    }

    get safeInitials() {
      return this.args.model?.initials ?? '??';
    }

    get safeRole() {
      return this.args.model?.role ?? 'Staff';
    }

    get accentColor() {
      switch (this.args.model?.color) {
        case 'coral': return '#e05d50';
        case 'teal': return '#2a9d8f';
        case 'purple': return '#7c5fc4';
        case 'amber': return '#c08b30';
        default: return '#5c5650';
      }
    }

    get safeAvatar() {
      return this.args.model?.avatar;
    }

    <template>
      <article class='staff-profile'>
        <div class='profile-header'>
          {{#if this.safeAvatar}}
            <div class='avatar-large'>
              <img src={{this.safeAvatar}} alt='{{this.safeName}}' />
            </div>
          {{else}}
            <div class='initials-large' style='background-color: {{this.accentColor}}'>
              {{this.safeInitials}}
            </div>
          {{/if}}

          <div class='header-info'>
            <h1 class='staff-name'>{{this.safeName}}</h1>
            <span class='role-badge' style='background-color: {{this.accentColor}}'>
              {{this.safeRole}}
            </span>
          </div>
        </div>

        <section class='profile-details'>
          <div class='detail-row'>
            <span class='detail-label'>Name</span>
            <span class='detail-value'><@fields.name /></span>
          </div>
          <div class='detail-row'>
            <span class='detail-label'>Role</span>
            <span class='detail-value'><@fields.role /></span>
          </div>
          <div class='detail-row'>
            <span class='detail-label'>Initials</span>
            <span class='detail-value'><@fields.initials /></span>
          </div>
        </section>
      </article>

      <style scoped>
        .staff-profile {
          width: 100%;
          max-width: 32rem;
          margin: 0 auto;
          padding: var(--boxel-sp-xl);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: var(--boxel-border-radius-lg);
        }

        .profile-header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-lg);
          padding-bottom: var(--boxel-sp-lg);
          border-bottom: 2px solid var(--border);
        }

        .avatar-large {
          flex-shrink: 0;
          width: 6rem;
          height: 6rem;
          border-radius: 50%;
          overflow: hidden;
          border: 3px solid var(--border);
        }

        .avatar-large img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .initials-large {
          flex-shrink: 0;
          width: 6rem;
          height: 6rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 1.5rem;
          font-weight: 700;
          letter-spacing: 0.05em;
        }

        .header-info {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }

        .staff-name {
          font-size: var(--boxel-font-size-2xl);
          font-weight: 700;
          margin: 0;
        }

        .role-badge {
          display: inline-block;
          padding: 0.25rem 0.75rem;
          border-radius: 1rem;
          color: white;
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          width: fit-content;
        }

        .profile-details {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }

        .detail-row {
          display: grid;
          grid-template-columns: 6rem 1fr;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-sm);
          border-radius: var(--boxel-border-radius-sm);
          background-color: var(--muted);
        }

        .detail-label {
          font-weight: 600;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }

        .detail-value {
          color: var(--card-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Staff> {
    get safeName() {
      return this.args.model?.name ?? 'Unknown';
    }

    get safeInitials() {
      return this.args.model?.initials ?? '??';
    }

    get safeRole() {
      return this.args.model?.role ?? 'Staff';
    }

    get accentColor() {
      switch (this.args.model?.color) {
        case 'coral': return '#e05d50';
        case 'teal': return '#2a9d8f';
        case 'purple': return '#7c5fc4';
        case 'amber': return '#c08b30';
        default: return '#5c5650';
      }
    }

    <template>
      <div class='staff-embedded'>
        <div class='initials-badge' style='background-color: {{this.accentColor}}'>
          {{this.safeInitials}}
        </div>
        <div class='staff-info'>
          <div class='staff-name'>{{this.safeName}}</div>
          <div class='staff-role'>{{this.safeRole}}</div>
        </div>
      </div>

      <style scoped>
        .staff-embedded {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-sm);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          height: 100%;
        }

        .initials-badge {
          flex-shrink: 0;
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.05em;
        }

        .staff-info {
          min-width: 0;
        }

        .staff-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          color: var(--card-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .staff-role {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Staff> {
    get safeName() {
      return this.args.model?.name ?? 'Unknown';
    }

    get safeInitials() {
      return this.args.model?.initials ?? '??';
    }

    get accentColor() {
      switch (this.args.model?.color) {
        case 'coral': return '#e05d50';
        case 'teal': return '#2a9d8f';
        case 'purple': return '#7c5fc4';
        case 'amber': return '#c08b30';
        default: return '#5c5650';
      }
    }

    <template>
      <div class='fitted-container'>
        <div class='tile'>
          <div class='initials-circle' style='background-color: {{this.accentColor}}'>
            {{this.safeInitials}}
          </div>
          <div class='fitted-name'>{{this.safeName}}</div>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          container-type: size;
          width: 100%;
          height: 100%;
        }

        .tile {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          height: 100%;
        }

        .initials-circle {
          width: 3.5rem;
          height: 3.5rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          font-size: 1rem;
          font-weight: 700;
          letter-spacing: 0.05em;
        }

        .fitted-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          color: var(--card-foreground);
          text-align: center;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof Staff> {
    <template>
      <div class='card-edit'>
        <div class='field-row'>
          <label>Name</label>
          <@fields.name />
        </div>
        <div class='field-row'>
          <label>Role</label>
          <@fields.role />
        </div>
        <div class='field-row'>
          <label>Initials</label>
          <@fields.initials />
        </div>
        <div class='field-row'>
          <label>Color</label>
          <@fields.color />
        </div>
        <div class='field-row'>
          <label>Avatar URL</label>
          <@fields.avatar />
        </div>
      </div>

      <style scoped>
        .card-edit {
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
