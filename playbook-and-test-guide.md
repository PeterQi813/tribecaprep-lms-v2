# Tribeca Prep LMS — Playbook & Test Guide

A single reference for **how the AI playbooks work** and **how the test workspace exercises the push-based sync helpers**.

---

## Part 1 — Playbooks (= SkillCards)

### Concept

A Playbook is a **versioned, structured prompt** that turns an AI command into a reusable, UI-triggered step. Instead of a teacher typing a long prompt every time, they right-click a card and "enchant" — the playbook inflates the click into a fully-formed instruction (with tone, vocabulary, schedule constraints, etc.) and sends it to the model.

In Boxel terms, a Playbook is a `SkillCard`. The card lives in the realm where the action runs (e.g., a daily-plan playbook lives in the Classroom realm, a parent-report playbook lives in the Parent Daily realm). The teacher's UI button reads the active playbook of the right `category`, builds the system prompt from its fields, and calls the model.

### Schema

Every SkillCard has the same shape:

| Field                | Purpose                                                                                |
|----------------------|----------------------------------------------------------------------------------------|
| `name`               | Human title — shown in dropdowns                                                       |
| `version`            | `v0.1`, `v0.2`, ... — bump on every meaningful prompt change                           |
| `category`           | Discriminator (`daily-plan` / `daily-communication` / `parent-summary`) — UI filters by this |
| `isActive`           | Only one active card per category drives the live UI                                   |
| `purpose`            | One-line description (shown on the picker)                                             |
| `triggerTime`        | When the playbook fires — manual now, scheduled later                                  |
| `modelSize`          | Model id (e.g., `google/gemini-2.0-flash-001`)                                         |
| `toneGuidelines`     | The bulk of the prompt — markdown, embedded into the system message                    |
| `prohibitedTerms`    | Array of `{badTerm, goodTerm}` — strict substitution rules the model must follow       |
| `vocabularyOverrides`| Array of `{abbreviation, fullTerm}` — expansions / domain glossary                     |
| `changelogEntries`   | `{version, text, date}` — audit trail of prompt edits                                  |

### Live playbooks in this LMS (v2)

| Realm           | File                                                  | Category               | What it does                                                                  |
|-----------------|-------------------------------------------------------|------------------------|-------------------------------------------------------------------------------|
| hero-classroom  | `SkillCard/daily-plan-generator.json`                 | `daily-plan`           | Generates a teacher-facing schedule from active goals + recent committed plans |
| parent-daily    | `SkillCard/daily-communication-generator.json`        | `daily-communication`  | Turns clinical observations into a warm, first-person parent report           |
| parent-daily    | `SkillCard/parent-summary-generator.json`             | `parent-summary`       | Higher-level rollup for the weekly/period parent summary                      |

### Why playbooks matter

- **Editable without touching code** — you change the prompt by editing the card, not redeploying.
- **Versioned** — `version` + `changelogEntries` make rollback explicit.
- **Composable** — multiple categories can chain (Classroom plan → AE → Parent report each uses its own playbook).
- **Discoverable** — the UI picker shows all active playbooks per category; teachers see what's currently driving the AI.

### How to add a new playbook

1. Open the realm where the action runs (e.g., Classroom for a teaching playbook).
2. Create a new `SkillCard` instance.
3. Fill in `name`, `category`, `purpose`, `toneGuidelines` (the actual prompt body).
4. Set `isActive: true` — this is what the picker reads.
5. Bump `version` and add a `changelogEntries` row whenever you edit the prompt body.

If a playbook needs new substitution rules, append to `prohibitedTerms` / `vocabularyOverrides` rather than burying them inside `toneGuidelines` — they're surfaced to the model separately and easier to audit.

---

## Part 2 — Test workspace (`bug-tests`)

### Why this exists

Every push-based sync helper (Classroom → HoS, Classroom → Parent) was previously verified by clicking around in production dashboards. That's slow and pollutes real data. The `bug-tests` realm hosts isolated cards that drive each helper end-to-end with `[TEST-...]` prefixed fixtures, so:

- A failing assertion shows up as a red ❌ in the same UI panel that ran the test.
- Cleanup buttons remove every `[TEST-...]` artifact so production stays clean.
- The same test card can run multiple times — repeatable regression check.

This pattern was suggested by Chris: **always validate sync logic in `bug-tests` before testing in production**.

### Test cards in v2

| Card URL                                                                        | Helper under test                          | Scenarios                                                                                       |
|---------------------------------------------------------------------------------|--------------------------------------------|-------------------------------------------------------------------------------------------------|
| `app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncAlertToHos/main`                         | `syncAlertToHos` (Classroom → HoS Alert)   | (1) upsert creates HoS mirror; (2) upsert updates same mirror (no dup)                          |
| `app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncStudentLocationToHos/main`               | `syncStudentLocationToHos`                 | (1) push updates HoS mirror; (2) no-op push returns `unchanged`; (3) missing profile → `skipped-no-profile` |
| `app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncSnapshotToParent/main`                   | `syncSnapshotToParent`                     | (1) first call creates ImportSnapshot; (2) second call updates same; (3) fake slug → `skipped-no-student` |

(Two earlier cards `TestSyncAeToHos` and `TestCascadeDelete` exist from prior sprints and still live in the workspace.)

### How to run a test

Each card has 3 buttons. Click them in order:

1. **Setup** — creates / picks the test fixture (e.g., creates a `[TEST-ALERT]` alert in Classroom; picks a real `(student, date)` pair with the most observations for the snapshot test).
2. **Run All Tests** — runs each scenario sequentially. Each row turns green ✅ or red ❌ with a short detail string. Full timeline goes to the Log panel below.
3. **Cleanup** — deletes test artifacts and **restores any production data the test mutated** (only `TestSyncStudentLocationToHos` mutates real data — see warning below).

### Mandatory cleanup: `TestSyncStudentLocationToHos`

This test temporarily writes `[TEST-LOC] Nurse` / `[TEST-LOC] seen @ 2pm` / `[TEST-LOC] 3:00 PM` to a real Classroom Student's `location` / `locationDetail` / `returnTime` (the test snapshots originals first, so Cleanup can restore them). **If you skip Cleanup, that real student keeps the test prefix on the live dashboard until you fix it manually.**

The other two tests only create new `[TEST-ALERT]` alerts or extra `ImportSnapshot` cards — Cleanup is nice-to-have, not safety-critical.

### Reading test output

Each row in the results grid:
- ✅ green — `success` field true and the assertion (e.g., "1 mirror exists, op='updated'") passed.
- ❌ red — short `detail` shows `op=...`, `err=...`, `mirror=true/false`. The Log panel has the full helper return value (JSON).
- ○ grey — not yet run.

If a test reports ❌ but the helper returned `success: true`, suspect a **timing race** in the assertion (e.g., HoS indexer hasn't caught up before the test re-queries 2 s later) before suspecting a real helper bug. Open the mirror URL directly in a new tab — if it returns 404, the helper succeeded and the test bailed early.

### Adding a new test card

1. Create a new file in `test/` like `test-sync-XYZ.gts` extending `CardDef` with `static isolated = class Isolated ...`.
2. Mirror an existing test card's structure: `@tracked t1/t2/t3` for results, `handleSetup` / `handleRunTests` / `handleCleanup` for the 3 buttons, an `unwrapResource` helper, and a `findHosMirror`-style query helper for assertions.
3. Add a card instance: `test/TestSyncXYZ/main.json` adopting from the new module.
4. Push: `boxel push bug-tests-fresh https://app.boxel.ai/itp_project/tribecaprep-lms-v2-test/`.
5. Open `app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncXYZ/main` and run.

### How playbooks and tests relate

- Tests verify **structural sync helpers** (data flowing between realms) — these are deterministic and should always pass.
- Playbooks drive **AI generation** (prompt → model output) — outputs are non-deterministic, so they aren't covered by these tests. Validate playbook quality by spot-checking real generation output and bumping `version` / `changelogEntries` as you tune the prompt.

If a sync helper changes shape (e.g., new dedup field), update the corresponding test card's assertions so the regression test stays meaningful.
