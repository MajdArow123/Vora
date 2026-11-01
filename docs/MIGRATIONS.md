# SwiftData migrations

Vora's store is versioned with `VersionedSchema` and opened through
`VoraMigrationPlan`. Every model change ships as a new schema version and
a migration stage. Never edit an existing version.

| File | Role |
|------|------|
| `Vora/Models/Schema/SchemaV1.swift` | The schema every pre-versioning store was created with; frozen copies of WorkoutSession, ExerciseLog, SetEntry |
| `Vora/Models/Schema/SchemaV2.swift` | Adds `ExerciseLog.exerciseId` (lightweight stage) |
| `Vora/Models/Schema/ExerciseIDBackfill.swift` | Post-open fill of `exerciseId` for pre-V2 rows |
| `Vora/Models/Schema/VoraMigrationPlan.swift` | Ordered `schemas` and `stages`; `CurrentSchema` alias |
| `Vora/Services/PersistenceController.swift` | Builds the container on `CurrentSchema` with the plan |
| `Vora/Services/AppDataStore.swift` | Opens the store at launch and runs post-open backfills; failures show `DataStoreErrorView` (Retry / Export data) instead of crashing |

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
     current plan. `v1-fixture.store` was generated from commit 0cafae8.

## Rules

- Never delete, recreate, or "reset" the store to get past a migration
  error. The recovery screen exists so users can retry or export instead.
- Persisted enum raw values never change (see `CardioType`).
- Run the full test suite before shipping any schema change.
