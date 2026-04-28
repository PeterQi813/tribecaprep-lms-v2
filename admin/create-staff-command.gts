import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/commands/send-request-via-proxy';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { StaffMember } from './staff-member';
import { ProgramRecord } from './program-record';
import { LearningGoal } from './learning-goal';

// ── AI Analysis ─────────────────────────────────────────────────────

class AnalyzeStaffInput extends CardDef {
  static displayName = 'Analyze Staff Input';
  @field rawText = contains(StringField);
}

class AnalyzeStaffResult extends CardDef {
  static displayName = 'Analyze Staff Result';
  @field name = contains(StringField);
  @field role = contains(StringField);
  @field initials = contains(StringField);
  @field avatarColor = contains(StringField);
  @field studentCount = contains(NumberField);
  @field weeklyObservations = contains(NumberField);
  @field email = contains(StringField);
}

export class AnalyzeStaffCommand extends Command<
  typeof AnalyzeStaffInput,
  typeof AnalyzeStaffResult
> {
  static actionVerb = 'Analyze Staff';

  async getInputType() {
    return AnalyzeStaffInput;
  }

  protected async run(input: AnalyzeStaffInput): Promise<AnalyzeStaffResult> {
    if (!input.rawText?.trim()) {
      throw new Error('Staff description is required');
    }

    const prompt = `You are a staff data extractor for a school admin system. Parse the following text and extract staff member information.

TEXT:
"""
${input.rawText}
"""

Extract these fields:
- name: Full name of the person
- role: MUST be exactly one of these strings: "Lead Teacher", "1:1 Aide", "OT Specialist", "Speech", "Administrator". Use fuzzy matching — map abbreviations and partial words to the closest role:
  * "aide", "1:1", "one to one", "1-1" → "1:1 Aide"
  * "OT", "occupational", "occupational therapist" → "OT Specialist"
  * "speech", "SLP", "speech therapist", "speech pathologist" → "Speech"
  * "teacher", "lead", "lead teacher", "classroom teacher" → "Lead Teacher"
  * "admin", "administrator", "principal", "director" → "Administrator"
  If unclear, default to "Lead Teacher".
- initials: First letter of each name part, uppercase, max 2-3 chars (e.g. "Dana Rivers" → "DR")
- avatarColor: Randomly pick one of: "teal", "purple", "coral", "amber"
- studentCount: Number of students if mentioned, otherwise 0
- weeklyObservations: Number of observations per week if mentioned, otherwise 0
- email: Email address if mentioned, otherwise ""

Respond ONLY with a valid JSON object. No markdown, no explanation.

{
  "name": "string",
  "role": "string",
  "initials": "string",
  "avatarColor": "string",
  "studentCount": 0,
  "weeklyObservations": 0,
  "email": "string"
}`;

    const response = await new SendRequestViaProxyCommand(
      this.commandContext,
    ).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      requestBody: JSON.stringify({
        model: 'google/gemini-2.5-flash',
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.1,
        max_tokens: 512,
      }),
      headers: {
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://app.boxel.ai',
        'X-Title': 'Admin Dashboard Staff Creator',
      },
    });

    if (!response.response.ok) {
      throw new Error(`AI request failed: ${response.response.status}`);
    }

    const data = await response.response.json();
    const raw: string = data.choices?.[0]?.message?.content ?? '';
    const clean = raw
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/```\s*$/i, '')
      .trim();

    let parsed: any;
    try {
      parsed = JSON.parse(clean);
    } catch (e) {
      throw new Error(`Failed to parse AI response: ${e}`);
    }

    const validRoles = ['Lead Teacher', '1:1 Aide', 'OT Specialist', 'Speech', 'Administrator'];
    const validColors = ['teal', 'purple', 'coral', 'amber'];

    const result = new AnalyzeStaffResult();
    result.name = parsed.name || input.rawText.split(',')[0]?.trim() || '';
    result.role = validRoles.includes(parsed.role) ? parsed.role : 'Lead Teacher';
    result.initials = parsed.initials || result.name.split(' ').map((w: string) => w[0]).join('').substring(0, 2).toUpperCase();
    result.avatarColor = validColors.includes(parsed.avatarColor) ? parsed.avatarColor : validColors[Math.floor(Math.random() * validColors.length)];
    result.studentCount = parseInt(parsed.studentCount) || 0;
    result.weeklyObservations = parseInt(parsed.weeklyObservations) || 0;
    result.email = parsed.email || '';

    return result;
  }
}

// ── Card Creation ───────────────────────────────────────────────────

class CreateStaffInput extends CardDef {
  static displayName = 'Create Staff Input';
  @field name = contains(StringField);
  @field role = contains(StringField);
  @field initials = contains(StringField);
  @field avatarColor = contains(StringField);
  @field studentCount = contains(NumberField);
  @field weeklyObservations = contains(NumberField);
  @field email = contains(StringField);
  @field realmUrl = contains(StringField);
}

class CreateStaffResult extends CardDef {
  static displayName = 'Create Staff Result';
  @field savedCardId = contains(StringField);
}

export class CreateStaffCommand extends Command<
  typeof CreateStaffInput,
  typeof CreateStaffResult
> {
  static actionVerb = 'Create Staff';

  async getInputType() {
    return CreateStaffInput;
  }

  protected async run(input: CreateStaffInput): Promise<CreateStaffResult> {
    if (!input.name?.trim()) throw new Error('Staff name is required');
    if (!input.realmUrl?.trim()) throw new Error('Realm URL is required');

    const realmUrl = input.realmUrl.endsWith('/') ? input.realmUrl : input.realmUrl + '/';

    const staff = new StaffMember();
    staff.name = input.name;
    staff.role = input.role || 'Lead Teacher';
    staff.initials = input.initials || input.name.split(' ').map((w: string) => w[0]).join('').substring(0, 2).toUpperCase();
    staff.avatarColor = input.avatarColor || 'teal';
    staff.studentCount = input.studentCount || 0;
    staff.weeklyObservations = input.weeklyObservations || 0;
    staff.status = 'Active';
    staff.email = input.email || '';

    // ✅ FIX: Pass realm as string, not new URL()
    await new SaveCardCommand(this.commandContext).execute({
      card: staff,
      realm: realmUrl,
    });

    const result = new CreateStaffResult();
    result.savedCardId = staff.id || '';
    return result;
  }
}

// ── Program Creation ────────────────────────────────────────────────

class CreateProgramInput extends CardDef {
  static displayName = 'Create Program Input';
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
  @field realmUrl = contains(StringField);
}

export class CreateProgramCommand extends Command<
  typeof CreateProgramInput,
  typeof CreateStaffResult
> {
  static actionVerb = 'Create Program';

  async getInputType() {
    return CreateProgramInput;
  }

  protected async run(input: CreateProgramInput): Promise<CreateStaffResult> {
    if (!input.program?.trim()) throw new Error('Program name is required');
    if (!input.realmUrl?.trim()) throw new Error('Realm URL is required');

    const realmUrl = input.realmUrl.endsWith('/') ? input.realmUrl : input.realmUrl + '/';

    const prog = new ProgramRecord();
    prog.program = input.program;
    prog.domain = input.domain || '';
    prog.domainKey = input.domainKey || '';
    prog.abllsCode = input.abllsCode || '';
    prog.masterSheet = input.masterSheet || 'Yes';
    prog.programSheet = input.programSheet || 'Yes';
    prog.started = input.started || '';
    prog.currentTarget = input.currentTarget || '';
    prog.active = input.active || 'Yes';
    prog.notes = input.notes || '';

    // ✅ FIX: Pass realm as string, not new URL()
    await new SaveCardCommand(this.commandContext).execute({
      card: prog,
      realm: realmUrl,
    });

    const result = new CreateStaffResult();
    result.savedCardId = prog.id || '';
    return result;
  }
}

// ── Learning Goal Creation ─────────────────────────────────────────

class CreateGoalInput extends CardDef {
  static displayName = 'Create Goal Input';
  @field goalTitle = contains(StringField);
  @field description = contains(StringField);
  @field domain = contains(StringField);
  @field priority = contains(StringField);
  @field currentMastery = contains(NumberField);
  @field targetMastery = contains(NumberField);
  @field dueDate = contains(StringField);
  @field standardAlignment = contains(StringField);
  @field studentCardId = contains(StringField);
  @field realmUrl = contains(StringField);
}

export class CreateLearningGoalCommand extends Command<
  typeof CreateGoalInput,
  typeof CreateStaffResult
> {
  static actionVerb = 'Create Learning Goal';

  async getInputType() {
    return CreateGoalInput;
  }

  protected async run(input: CreateGoalInput): Promise<CreateStaffResult> {
    if (!input.goalTitle?.trim()) throw new Error('Goal title is required');
    if (!input.realmUrl?.trim()) throw new Error('Realm URL is required');

    const realmUrl = input.realmUrl.endsWith('/') ? input.realmUrl : input.realmUrl + '/';

    const goal = new LearningGoal();
    goal.goalTitle = input.goalTitle;
    goal.description = input.description || '';
    goal.domain = input.domain || 'Mathematics';
    goal.priority = input.priority || 'Medium';
    goal.currentMastery = input.currentMastery || 0;
    goal.targetMastery = input.targetMastery || 80;
    // DateField requires a valid Date object, not empty string
    if (input.dueDate && input.dueDate.trim()) {
      const parts = input.dueDate.split('-');
      if (parts.length === 3) {
        goal.dueDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
      }
    }
    goal.standardAlignment = input.standardAlignment || '';
    // Store student name from the dropdown selection
    if (input.studentCardId) {
      (goal as any).studentName = input.studentCardId;
    }

    await new SaveCardCommand(this.commandContext).execute({
      card: goal,
      realm: realmUrl,
    });

    const result = new CreateStaffResult();
    result.savedCardId = goal.id || '';
    return result;
  }
}
// touched for re-index
