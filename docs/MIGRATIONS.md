# SwiftData migrations

Vora's store is versioned with `VersionedSchema` and opened through
`VoraMigrationPlan`. Every model change ships as a new schema version and
a migration stage. Never edit an existing version.

| File | Role |
|------|------|
| `Vora/Models/Schema/SchemaV1.swift` | The schema every pre-versioning store was created with; frozen copies of WorkoutSession, ExerciseLog, SetEntry, CardioEntry |
| `Vora/Models/Schema/SchemaV2.swift` | Adds `ExerciseLog.exerciseId` (lightweight stage); frozen copies of the same four models |
| `Vora/Models/Schema/ExerciseIDBackfill.swift` | Post-open fill of `exerciseId` for pre-V2 rows |
| `Vora/Models/Schema/SchemaV3.swift` | Adds the `WorkoutTemplate` and `TemplateExercise` entities (lightweight stage); frozen copies of the same four models |
| `Vora/Models/Schema/SchemaV4.swift` | Replaces `SetEntry.rpe` with the optional `SetEntry.rir`, and adds the optional `healthKitWorkoutID` to WorkoutSession and CardioEntry (lightweight stage) |
| `Vora/Models/Schema/SchemaV5.swift` | Adds GymProfile's optional loading inventory: `storedBars`, `storedPlates`, `storedDumbbellIncrementKg`, `storedMachineIncrementKg` (lightweight stage); V1–V4 each hold a frozen copy of GymProfile |
| `Vora/Models/Schema/SchemaV6.swift` | Adds ExerciseLog's optional target snapshot: `repRangeMin`, `repRangeMax`, `targetRIR`, `targetSets` (lightweight stage); V4 and V5 each hold a frozen copy of WorkoutSession, ExerciseLog and SetEntry |
| `Vora/Models/Schema/SchemaV7.swift` | Adds the `ExpenditureCheckIn` entity (lightweight stage); no existing model changes, so nothing is frozen |
| `Vora/Models/Schema/SchemaV8.swift` | Adds optional `SetEntry.setTypeRawValue` and `sideRawValue`, and `ExerciseLog.supersetGroup` (lightweight stage); nil reads as a normal, unlinked set, so nothing is backfilled. V6 and V7 each hold a frozen copy of WorkoutSession, ExerciseLog and SetEntry |
| `Vora/Models/Schema/SchemaV9.swift` | Adds the `TrainingProgram` and `CycleDay` entities, the optional `TemplateExercise.supersetGroup` and `WorkoutTemplate.cycleDay` (lightweight stage). No program row reads as weekly mode, so nothing is backfilled (see docs/TRAINING_CYCLES.md). V3–V8 each hold a frozen copy of WorkoutTemplate and TemplateExercise |
| `Vora/Models/Schema/GymInventoryBackfill.swift` | Post-open fill of unfilled gym inventories from the preset and the user's units; skips when no user profile exists yet, and runs again when onboarding completes |
| `Vora/Models/Schema/TemplateDefaultsMigration.swift` | Post-open move of the pre-V3 `vora.workoutTemplates` UserDefaults dictionary into SwiftData; removes the key only after a successful save |
| `Vora/Models/Schema/VoraMigrationPlan.swift` | Ordered `schemas` and `stages`; `CurrentSchema` alias |
| `Vora/Services/PersistenceController.swift` | Builds the container on `CurrentSchema` with the plan |
| `Vora/Services/AppDataStore.swift` | Opens the store at launch and runs post-open backfills and data moves (exercise IDs, templates, then gym inventories); failures show `DataStoreErrorView` (Retry / Export data) instead of crashing |

## Adding a schema version (SchemaV2 shown; same steps for every Vn)

1. **Freeze what you're about to change.** `SchemaV1` points at the live
   model classes. For each model V2 changes, copy today's class into
   `extension SchemaV1 { @Model final class WorkoutSession { … } }`
   unchanged, and point `SchemaV1.models` at `SchemaV1.WorkoutSession.self`.
   Also freeze every model whose relationships reference a frozen model
   (and so on transitively). Relationships name the class directly, so
   a shared `WorkoutSession` would point V1 at the live V2 `ExerciseLog`.
   Copies are verbatim, with relationships pointing at the other nested
   copies. Models outside that cluster can keep being shared.
   **Freeze into every version that lists the live class, not only the
   previous one.** V1, V2 and V3 all listed the live `CardioEntry`, and V2
   and V3 the live workout cluster, so V4 froze them into each. Missing one
   silently gives that older version the new shape.
   Schema enums are `nonisolated`, so frozen copies inside them can only use
   nonisolated members. Types a frozen copy touches (`GymPreset`,
   `EquipmentType`) must be `nonisolated` too, or the freeze adds warnings.
2. **Change the live model** (the top-level class) and create
   `SchemaV2.swift` listing all models, with
   `versionIdentifier = Schema.Version(2, 0, 0)`.
3. **Add the stage** to `VoraMigrationPlan`. Prefer lightweight:
   - Additive changes (a new model, a new optional or defaulted property,
     a rename with `@Attribute(originalName:)`):
     `.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`
   - **Data fills** (deriving a new column from existing data): keep the
     stage lightweight and add an idempotent post-open backfill, like
     `ExerciseIDBackfill`, called from `AppDataStore.load()` after the
     container opens and before the app shows. It must log and continue
     on error (never block launch), and code must keep working for rows
     it hasn't filled yet.
   - Use `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` only
     when lightweight can't express the change (type changes, splitting
     or merging entities, removing data that must be transformed first).
     Read old values with the frozen types in `willMigrate` and write new
     ones in `didMigrate`; let errors throw, which leaves the store
     untouched and shows the recovery screen.
4. **Append** `SchemaV2.self` to `schemas` and move
   `typealias CurrentSchema = SchemaV2`.
5. **Test it** in `VoraTests/SchemaMigrationTests.swift`:
   - Frozen-type test: create an on-disk store from the previous
     version's `models`, insert representative rows, release the
     container, reopen with `PersistenceController.makeContainer(url:)`,
     and assert every value survived and every backfill ran.
   - Real-store fixture: generate a store with the previous release's
     actual code (check that commit out in a temporary worktree and run a
     throwaway test that writes the store), add it under
     `VoraTests/Fixtures/`, and open a temp copy of it through the
     current plan. `v1-fixture.store` was generated from commit 0cafae8;
     `v2-fixture.store` and `v2-fixture-templates.plist` (the UserDefaults
     domain written by the shipped `WorkoutTemplateStore`) from commit
     712aea5; `v3-fixture.store` and `v1-session-draft.json` (a version 1
     `ActiveSessionDraft`) from commit 07190d1; `v4-fixture.store` from commit
     2b8a20e; `v5-fixture.store` and `v2-session-draft.json` (a version 2
     `ActiveSessionDraft`) from commit ec4b816; `v6-fixture.store` from commit
     5228197; `v7-fixture.store` and `v3-session-draft.json` (a version 3
     `ActiveSessionDraft`) from commit 0dbc46f; `v8-fixture.store` and
     `v4-session-draft.json` (a version 4 `ActiveSessionDraft`) from commit
     2517af9. When data outside the store
     moves into it (UserDefaults, files), fixture that data too and test
     the move against it.
   - Read fixtures only through a copy, including with `sqlite3`. Opening a
     WAL store in place rewrites its `-shm` sidecar, which dirties the repo.
   - Post-open moves and backfills run through `AppDataStore` with their
     inputs injected (e.g. a test `UserDefaults` suite), never the host
     app's real `UserDefaults.standard`.

## Why gym inventories are written, not resolved on read

The V5 columns are optional only so the stage stays lightweight. Default plates
depend on the user's units, which a fresh install doesn't have when it seeds
"My Gym" (before onboarding), so `nil` means "not filled yet". Defaults are
written once units are known: at the end of onboarding, by the post-open
backfill for existing users, and immediately for new gyms and `applyPreset`.
After that, changing `preferredUnits` only changes how weights are displayed,
never which plates a gym has. Code treats a nil inventory as an empty gym.

## Why target snapshots aren't backfilled

The V6 columns record the targets a session was done under, and nothing can
recover those for older logs: today's template may have changed since. So old
rows stay nil, and `ProgressionEngine` judges them by the current targets.
Filling them with today's targets would make that guess look like a record.

## Why removing `SetEntry.rpe` lost no data

V4 drops `rpe` in a lightweight stage, without reading the column first,
because no build ever wrote a non-zero value. Evidence, as of commit 07190d1:

- `git log --all -p -G'rpe' -- Vora` shows only three kinds of line across
  every commit: the declaration (`var rpe: Int`), the init default
  (`rpe: Int = 0`) and the init assignment (`self.rpe = rpe`). No call site
  ever passed a value and nothing assigned the property elsewhere.
- Every `ZRPE` value is 0 in all three fixture stores: 10 of 10 rows in
  `v1-fixture.store`, 12 of 12 in `v2-fixture.store`, and 8 of 8 in
  `v3-fixture.store`.

## Rules

- Oldest supported store: SchemaV1 (Nov 2026). Stores from before GymProfile
  (pre-Improvement 12) can't be migrated and show the recovery screen —
  acceptable because no build before SchemaV1 was ever distributed.
- Never delete, recreate, or "reset" the store to get past a migration
  error. The recovery screen exists so users can retry or export instead.
- Persisted enum raw values never change (see `CardioType`).
- Run the full test suite before shipping any schema change.
