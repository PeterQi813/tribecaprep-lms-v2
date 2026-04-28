import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

export class StaffMember extends CardDef {
  static displayName = 'Staff Member';

  @field name = contains(StringField);
  @field role = contains(StringField); // "Lead Teacher" | "1:1 Aide" | "OT Specialist" | "Speech"
  @field initials = contains(StringField); // e.g. "DP", "DR", "JN"
  @field avatarColor = contains(StringField); // "teal" | "purple" | "coral" | "amber"
  @field studentCount = contains(NumberField);
  @field weeklyObservations = contains(NumberField);
  @field status = contains(StringField); // "Active" | "Pending"
  @field email = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: StaffMember) {
      return this.name || 'Untitled Staff';
    },
  });

  // Fitted view — compact staff card for grid
  static fitted = class Fitted extends Component<typeof this> {
    get isActive() {
      return (this.args.model.status || 'Active') === 'Active';
    }

    <template>
      <div class='staff-fitted'>
        <div class='sf-avatar {{@model.avatarColor}}'>{{@model.initials}}</div>
        <div class='sf-info'>
          <span class='sf-name'>{{@model.name}}</span>
          <span class='sf-role'>{{@model.role}}</span>
        </div>
        <span class='sf-status {{if this.isActive "active" "pending"}}'>
          {{@model.status}}
        </span>
      </div>
      <style scoped>
        .staff-fitted {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.875rem;
          background: #fffdfb;
          border-radius: 10px;
          box-shadow: 0 1px 2px rgba(26,24,22,0.04);
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .sf-avatar {
          width: 40px;
          height: 40px;
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.75rem;
          font-weight: 700;
          color: white;
          flex-shrink: 0;
        }
        .sf-avatar.teal { background: #2a9d8f; }
        .sf-avatar.purple { background: #7c5fc4; }
        .sf-avatar.coral { background: #e05d50; }
        .sf-avatar.amber { background: #c08b30; }
        .sf-info { flex: 1; min-width: 0; }
        .sf-name {
          display: block;
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .sf-role {
          display: block;
          font-size: 0.6875rem;
          color: #8a8279;
        }
        .sf-status {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          flex-shrink: 0;
        }
        .sf-status.active { background: #e8f6f4; color: #2a9d8f; }
        .sf-status.pending { background: #fdf6e8; color: #c08b30; }
      </style>
    </template>
  };

  // Embedded view — inline staff row
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='staff-embedded'>
        <div class='se-avatar {{@model.avatarColor}}'>{{@model.initials}}</div>
        <span class='se-name'>{{@model.name}}</span>
        <span class='se-role'>{{@model.role}}</span>
        <span class='se-count'>{{@model.studentCount}} students</span>
      </div>
      <style scoped>
        .staff-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.5rem 0.75rem;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .se-avatar {
          width: 28px;
          height: 28px;
          border-radius: 7px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.5625rem;
          font-weight: 700;
          color: white;
          flex-shrink: 0;
        }
        .se-avatar.teal { background: #2a9d8f; }
        .se-avatar.purple { background: #7c5fc4; }
        .se-avatar.coral { background: #e05d50; }
        .se-avatar.amber { background: #c08b30; }
        .se-name {
          font-size: 0.875rem;
          font-weight: 600;
          color: #1a1816;
        }
        .se-role {
          font-size: 0.75rem;
          color: #8a8279;
          flex: 1;
        }
        .se-count {
          font-size: 0.6875rem;
          color: #5c5650;
        }
      </style>
    </template>
  };

  // Isolated view — full staff profile card
  static isolated = class Isolated extends Component<typeof this> {
    get isActive() {
      return (this.args.model.status || 'Active') === 'Active';
    }

    <template>
      <div class='staff-card'>
        <a class='back-link' href='https://app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/AdminDashboard/main'>← Back to Admin Dashboard</a>
        <div class='sc-header'>
          <div class='sc-avatar-wrap'>
            <div class='sc-avatar {{@model.avatarColor}}'>{{@model.initials}}</div>
          </div>
          <div class='sc-identity'>
            <h1 class='sc-name'>{{@model.name}}</h1>
            <span class='sc-role'>{{@model.role}}</span>
            {{#if @model.email}}
              <span class='sc-email'>{{@model.email}}</span>
            {{/if}}
          </div>
          <span class='sc-status {{if this.isActive "active" "pending"}}'>
            {{@model.status}}
          </span>
        </div>

        <div class='sc-stats'>
          <div class='sc-stat'>
            <span class='sc-stat-value'>{{@model.studentCount}}</span>
            <span class='sc-stat-label'>Students</span>
          </div>
          <div class='sc-divider'></div>
          <div class='sc-stat'>
            <span class='sc-stat-value'>{{@model.weeklyObservations}}</span>
            <span class='sc-stat-label'>Obs / week</span>
          </div>
        </div>
      </div>
      <style scoped>
        .back-link {
          display: inline-block;
          padding: 0.5rem 0;
          font-size: 0.8125rem;
          font-weight: 600;
          color: #7c5fc4;
          text-decoration: none;
        }
        .back-link:hover { text-decoration: underline; }
        .staff-card {
          background: #fffdfb;
          border-radius: 14px;
          box-shadow: 0 4px 12px rgba(26,24,22,0.06);
          max-width: 480px;
          margin: 0 auto;
          overflow: hidden;
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
        }
        .sc-header {
          display: flex;
          align-items: flex-start;
          gap: 1rem;
          padding: 1.5rem;
          border-bottom: 1px solid #f5f2ef;
        }
        .sc-avatar {
          width: 56px;
          height: 56px;
          border-radius: 14px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 1rem;
          font-weight: 700;
          color: white;
          flex-shrink: 0;
        }
        .sc-avatar.teal { background: #2a9d8f; }
        .sc-avatar.purple { background: #7c5fc4; }
        .sc-avatar.coral { background: #e05d50; }
        .sc-avatar.amber { background: #c08b30; }
        .sc-identity { flex: 1; }
        .sc-name {
          font-size: 1.25rem;
          font-weight: 600;
          margin: 0 0 0.25rem;
          color: #1a1816;
        }
        .sc-role {
          display: block;
          font-size: 0.875rem;
          color: #5c5650;
        }
        .sc-email {
          display: block;
          font-size: 0.75rem;
          color: #8a8279;
          margin-top: 0.25rem;
        }
        .sc-status {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.25rem 0.625rem;
          border-radius: 4px;
        }
        .sc-status.active { background: #e8f6f4; color: #2a9d8f; }
        .sc-status.pending { background: #fdf6e8; color: #c08b30; }
        .sc-stats {
          display: flex;
          align-items: center;
          padding: 1.25rem 1.5rem;
        }
        .sc-stat { flex: 1; text-align: center; }
        .sc-stat-value {
          display: block;
          font-size: 1.75rem;
          font-weight: 700;
          color: #1a1816;
          letter-spacing: -0.02em;
        }
        .sc-stat-label {
          display: block;
          font-size: 0.6875rem;
          color: #8a8279;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          margin-top: 0.25rem;
        }
        .sc-divider {
          width: 1px;
          height: 40px;
          background: #f5f2ef;
        }
      </style>
    </template>
  };
}
// touched for re-index
