# Tribeca Prep LMS — Final v2.0

## Contents

5 Boxel workspaces, full snapshot (excluding `.boxel-history` CLI metadata).

| Folder    | Boxel realm                                                    | Purpose                                |
|-----------|----------------------------------------------------------------|----------------------------------------|
| classroom/| `app.boxel.ai/itp_project/tribecaprep-lms-v2-classroom/`      | Teacher dashboard (real-time)          |
| admin/    | `app.boxel.ai/itp_project/tribecaprep-lms-v2-admin/`          | Admin observation records + programs   |
| parent/   | `app.boxel.ai/itp_project/tribecaprep-lms-v2-parent/`         | Parent reports (daily snapshots + AI)  |
| hos/      | `app.boxel.ai/itp_project/tribecaprep-lms-v2-hos/`            | Head of School oversight               |
| test/     | `app.boxel.ai/itp_project/tribecaprep-lms-v2-test/`           | Isolated test cards (Edge 8/9/11)      |

## What changed since v0 (Approach C: pull → push)

This sprint converted cross-realm data flow from **pull-based fetch** to **push-based sync**:

- 3 sync edges implemented + tested (3/3 each):
  - **Edge #8**: Classroom `ClassroomAlert` → HoS mirror
  - **Edge #9**: Classroom `Student.location` → HoS mirror
  - **Edge #11**: Classroom AE/Plan/Goals → Parent Daily `ImportSnapshot`
- ~700 lines of legacy fetch code removed:
  - HoS `fetchAllData` (~392 lines)
  - Parent Daily `handleFetch` + `handleBatchFetch` (~307 lines)
- Classroom dashboard added 3 manual rebuild buttons:
  - `⇪ Rebuild Admin` (existing)
  - `⇪ Rebuild HoS` (new — pushes all AE/Goal/Alert/Location to HoS mirrors)
  - `⇪ Publish Snapshot` (new — pushes selected (student, date) snapshot to Parent Daily)

## How to use the test workspace (`test/`)

The `test/` folder mirrors the `bug-tests` Boxel realm. It contains 3 isolated test cards that exercise each push-based helper end-to-end with `[TEST-...]` prefixed data so cleanup is unambiguous.

### Open in Boxel UI

1. `https://app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncAlertToHos/main`
2. `https://app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncStudentLocationToHos/main`
3. `https://app.boxel.ai/itp_project/tribecaprep-lms-v2-test/TestSyncSnapshotToParent/main`

### Test flow (each card)

Click the 3 buttons in order:

1. **Setup** — creates / picks the test fixture
2. **Run All Tests** — runs each scenario sequentially; ✅ / ❌ shows per-test result
3. **Cleanup** — restores any modified production data + deletes test cards

### Cleanup is mandatory for `TestSyncStudentLocationToHos`

It mutates a real student's `location` / `locationDetail` / `returnTime` to `[TEST-LOC] ...`. Forgetting Cleanup leaves real production data with the test prefix. The other two tests only create new `[TEST-ALERT]` / `ImportSnapshot` cards (cleanup nice-to-have, not required).

### What each test verifies

| Card                          | Tests                                                                                             |
|-------------------------------|---------------------------------------------------------------------------------------------------|
| `TestSyncAlertToHos`          | upsert creates HoS mirror; second upsert updates same mirror (no duplicate)                       |
| `TestSyncStudentLocationToHos`| push updates HoS mirror; no-op push returns `unchanged`; missing profile returns `skipped-no-profile` |
| `TestSyncSnapshotToParent`    | first call creates `ImportSnapshot`; second call updates same (no duplicate); fake slug returns `skipped-no-student` |

## Known limitations carried forward

- **Goals dedup uses `goalTitle + studentName`** — not stable across renames or empty `studentName`. Adding a `sourceGoalId` field on HoS `LearningGoal` triggered a Boxel platform `prerender-card 404` bug; reverted. To be retried after Boxel fix.
- **Cross-realm DELETE from helper** — Classroom→HoS `fetch DELETE` silently no-ops (returns 200 but doesn't delete). Not an issue today because production code never invokes the `delete` helper path (alert dismissal uses `upsert` with `resolved=true`).
