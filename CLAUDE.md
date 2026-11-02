# Vora

SwiftUI + SwiftData iOS app (iOS 26.5, Swift Testing). Scheme `Vora`, targets `Vora` and `VoraTests`.

## Vora rules

- Production quality, no TODOs or placeholders.
- DesignSystem constants only (`Vora/Utilities/DesignSystem.swift`), no hardcoded hex.
- No unjustified force unwraps, no `print()`.
- Replace `try?` / `assertionFailure` with explicit error handling in any code you touch.
- Zero warnings in the app AND test targets.
- Swift Testing (`@Test`) unit tests for every model, migration and service change, using in-memory containers like the existing tests.
- Unit tests must never reach real HealthKit — always inject a stub.
- Run the full suite and report pass/fail totals.
- Do not commit unless asked; summarize changed files for review.

## SwiftData

- **Never use `makeContainer(...).mainContext` inline.** Keep the `ModelContainer` alive in a stored property (e.g. a test struct's `init() throws`) and take `container.mainContext` from it. A context whose container has been released traps inside SwiftData, which takes down the whole test host and fails every test at 0.000 s. This crashed the test host twice (Prompt 2 and Prompt 3).
- **Match exercises by `exerciseId`, never by name.** Library exercises are identified by their permanent slug (`ExerciseLibrary`); custom exercises have a nil ID and are matched by `ExerciseIdentity.key`. Resolve legacy or stored names through `ExerciseLibrary.legacyDefinition(lowercasedName:)` so aliases apply.

## Migrations

Full guide: [docs/MIGRATIONS.md](docs/MIGRATIONS.md). Summary:

- Every model change is a new `VersionedSchema` (`Vora/Models/Schema/SchemaVn.swift`) plus a stage in `VoraMigrationPlan`; never edit a shipped version. Move `CurrentSchema` to the new version.
- Freeze what changes: copy the old class verbatim into the previous schema, together with every model in its relationship cluster. New models alone are additive and need no freezing.
- Prefer `.lightweight` stages. Data fills and data moved in from outside the store (e.g. UserDefaults) run as idempotent post-open steps in `AppDataStore.load()`: they log, never block launch, and the app works for rows they haven't processed yet. Delete source data only after a successful save.
- Use `.custom` stages only when lightweight can't express the change.
- Test with frozen types and with a real fixture store generated from the previous commit (`VoraTests/Fixtures/`; process in MIGRATIONS.md). Inject inputs such as a test `UserDefaults` suite; never touch the host app's real `UserDefaults.standard` in tests.
- Never delete, recreate or "reset" a store to get past a migration error.

## Devices

- **Back up the iPhone app data container to `~/VoraBackups/<yyyy-MM-dd-HHmm>/` before any device install**, e.g. `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.majdarow.Vora --source / --destination ~/VoraBackups/<timestamp>`, and check the copy is not empty.
