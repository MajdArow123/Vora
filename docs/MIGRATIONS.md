# SwiftData migrations

Vora's store is versioned with `VersionedSchema` and opened through
`VoraMigrationPlan`. Every model change ships as a new schema version and
a migration stage. Never edit an existing version.

| File | Role |
|------|------|
| `Vora/Models/Schema/SchemaV1.swift` | The schema every pre-versioning store was created with |
| `Vora/Models/Schema/VoraMigrationPlan.swift` | Ordered `schemas` and `stages`; `CurrentSchema` alias |
| `Vora/Services/PersistenceController.swift` | Builds the container on `CurrentSchema` with the plan |
| `Vora/Services/AppDataStore.swift` | Opens the store at launch; failures show `DataStoreErrorView` (Retry / Export data) instead of crashing |

## Adding SchemaV2

1. **Freeze what you're about to change.** `SchemaV1` points at the live
   model classes. For each model V2 changes, copy today's class into
   `extension SchemaV1 { @Model final class WorkoutSession { … } }`
   unchanged, and point `SchemaV1.models` at `SchemaV1.WorkoutSession.self`.
   Models that V2 leaves untouched can keep being shared by both versions.
2. **Change the live model** (the top-level class) and create
   `SchemaV2.swift` listing all models, with
   `versionIdentifier = Schema.Version(2, 0, 0)`.
3. **Add the stage** to `VoraMigrationPlan`:
   - Additive changes (a new model, a new optional or defaulted property,
     a rename with `@Attribute(originalName:)`):
     `.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`
   - Anything that needs data rewritten (backfills, type changes, splits):
     `.custom(fromVersion:toVersion:willMigrate:didMigrate:)`. Read old
     values in `willMigrate` using the frozen `SchemaV1` types, and write
     the new values in `didMigrate` using `SchemaV2` types. Call
     `context.save()` and let errors throw. A thrown error leaves the
     store untouched and shows the recovery screen.
4. **Append** `SchemaV2.self` to `schemas` and move
   `typealias CurrentSchema = SchemaV2`.
5. **Test it** in `VoraTests/SchemaMigrationTests.swift`: create an
   on-disk store with the previous version, insert representative rows,
   release the container, reopen with `PersistenceController.makeContainer(url:)`,
   and assert every value survived and every backfill ran.

## Rules

- Never delete, recreate, or "reset" the store to get past a migration
  error. The recovery screen exists so users can retry or export instead.
- Persisted enum raw values never change (see `CardioType`).
- Run the full test suite before shipping any schema change.
