import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';

export class ScheduleCard extends CardDef {
  static displayName = 'Schedule Card';

  @field schedId = contains(NumberField);
  @field name = contains(StringField);
  @field domainKey = contains(StringField);
  @field domainLabel = contains(StringField);
  @field ablls = contains(StringField);
  @field target = contains(StringField);
  @field sessions = contains(NumberField);
  @field column = contains(NumberField);
  @field muted = contains(BooleanField);
  @field note = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ScheduleCard) {
      return this.name || 'Schedule Card';
    },
  });

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='sc-row'>
        <span class='sc-name'>{{@model.name}}</span>
        <span class='sc-sessions'>{{@model.sessions}} sessions</span>
      </div>
      <style scoped>
        .sc-row { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem; font-family: 'Inter', system-ui, sans-serif; font-size: 0.8125rem; }
        .sc-name { font-weight: 500; flex: 1; }
        .sc-sessions { font-size: 0.75rem; color: #8a8279; }
      </style>
    </template>
  };
}
// touched for re-index
