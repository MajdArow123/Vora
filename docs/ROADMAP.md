# Vora vs MacroFactor Workouts — Gap Analysis & Roadmap

Nov 1, 2026 · @majd arow

> **Status (updated 2026-11-01):** Prompt 0 (git) done. Prompt 1 (versioned schema) committed in `0cafae8`. Prompt 2 (stable exercise IDs) done: library IDs, SchemaV2, lightweight stage + post-open backfill, legacy alias map, 68-exercise library, 536 tests passing. **Next: Prompt 3.**
>
> Lessons applied so far (see docs/MIGRATIONS.md): freeze every model in a relationship cluster, not just the one that changes; prefer `.lightweight` stages plus an idempotent post-open backfill in `AppDataStore.load()` over custom stages; test migrations against a real fixture store generated from the previous commit; always match exercises by `exerciseId`, never by name.

## Summary

The biggest gap is still **Smart Progression**, but the 2026-11-01 code audit shows Vora isn't ready for it yet. Sets store only weight and reps, templates are name lists in UserDefaults, exercises are linked by name string, and there's no versioned schema. A bad migration would crash the app with `fatalError`. Fix those foundations first (Phase 0), then build progression.

- **Put Vora in git before anything else.** The audit found no git repository in the project folder.
- **Already done:** muscle diagrams and technique cues exist (66 exercises with primary/secondary muscles and cues), so the old Improvement 13 is mostly finished. Tests: 487 passing; the app target has zero warnings and the test target has 6 warnings.
- **Vora's real edge is that it's one app.** MacroFactor sells nutrition and workouts as two separate apps, with no shared coaching between them at launch. Training-aware nutrition is something they don't offer.
- **Skip for now:** AI program generation, spreadsheet import and licensed program imports.

## What MacroFactor Workouts does

It launched in January 2026 and was on version 1.4.1 by October 2026. It costs $11.99/month or $71.99/year, with a $89.99/year bundle with the nutrition app. Everything below comes from their public site, help center and newsletters.

- **Smart Progression.** Rule-based, not generative AI. It adjusts weight and reps from your logged performance, RIR targets and rep ranges. A "wand" icon explains *why* each recommendation was made. When equipment limits make a target impossible, it offers one-tap fixes. It can widen a rep range, and you can choose reps-first or weight-first progression. It also accounts for fatigue within a session.
- **Logging.** RIR, drop sets, failure sets, partials, myo-reps, supersets, left/right sides separately, notes, custom exercises.
- **Session tools.** Customizable rest timers, a plate calculator based on your own plates and bars, smart warm-up suggestions, smart exercise swaps, Live Activities (in beta).
- **Gym profiles.** Several locations, each with its own equipment, bar types, plate sizes and machines. Programs adapt to the profile.
- **Programs.** Generated from goal, schedule, experience and equipment, or built by hand. They run on *training cycles*, not a calendar, so missed days don't break the program.
- **Analytics.** "Levels": a front/back body map of average weekly sets per muscle, with the lifts that contribute to each. Also volume charts (resistance vs bodyweight), PRs, exercise performance over time and a customizable dashboard.
- **Library.** 900+ exercises with tips and cues, plus technique videos.
- **Nutrition link.** Shares weight, trend weight, body metrics and photos with the nutrition app, but no shared coaching at launch. The nutrition app's core is trend weight plus an adaptive expenditure (TDEE) algorithm: calories in minus change in stored energy equals calories out.

## Gap table

Vora already covers gym profiles, swaps, muscle diagrams, cues and a broad nutrition side. The gaps are coaching logic plus the data model underneath it. The "Vora today" column comes from the 2026-11-01 audit.

| Feature | MacroFactor | Vora today | Gap |
| --- | --- | --- | --- |
| Next-set weight/rep recommendations | Smart Progression, with explanations | Copies last session's weight; reps left blank | Large |
| Template targets (sets, rep range, RIR) | Yes | Exercise names only in UserDefaults; fixed 4 sets | Large (foundation) |
| Stable exercise identity | Yes | Matched by `exerciseName.lowercased()` | Medium (foundation) |
| RIR / effort logging | Yes, also feeds progression | `rpe` field exists but is never set | Small |
| Units in workouts | kg/lb | kg only in session; `%.1f` rounding | Small |
| Plate calculator | Per gym profile's plates and bars | None; GymProfile holds equipment only | Small |
| Gym profiles + equipment filtering | Yes | Done | None |
| Muscle diagrams + technique cues | 900+ exercises, videos | Done for 66 exercises | Small (add more exercises) |
| Weekly sets per muscle ("Levels") | Body map, with contributing lifts | Total kg per week only | Medium |
| Rest timer | Customizable, Live Activity | Fixed 90 s, foreground only | Small |
| Session crash recovery | Not documented | Drafts in memory only; lost if app killed | Medium |
| Smart warm-ups | Yes | None | Small |
| Advanced set types | Drop, myo, failure, partials, supersets, L/R | None | Medium |
| PRs | Weight, reps, e1RM | Heaviest weight only | Small |
| Trend weight | Core feature | 14-day straight-line projection | Small |
| Adaptive TDEE | Core feature, in a separate app | Static Mifflin-St Jeor at onboarding | Medium |
| Programs on training cycles | Yes | Repeating 7-day split | Medium |
| HealthKit | Writes workouts | Writes workouts (no calories); never reads weight | Small |
| Nutrition and training in one app | No, two apps | Yes | **Vora's advantage** |

## Ranked roadmap

Phase 0 makes the data model safe to change. Phase 1 builds the progression loop, and everything after that builds on it. Commit after every step.

**Phase 0: foundations (no visible features, but they prevent crashes and data loss)**

0. **Git baseline.** `git init`, a `.gitignore` that excludes `build/`, a first commit, then push to GitHub.
1. **Versioned schema.** Freeze the current 18 models as `SchemaV1`, add a `SchemaMigrationPlan`, and replace the `fatalError` with a recovery path.
2. **Stable exercise IDs.** Add `exerciseId` to library entries and `ExerciseLog`, backfill by name, and switch history, PRs and pre-fill to match on ID. Fetch with predicates instead of scanning all sessions.
3. **Templates as SwiftData.** `WorkoutTemplate` → `TemplateExercise` (sets, rep range, target RIR, rest seconds), migrated from the UserDefaults dictionary. This also removes the fixed 4 sets and 90 s rest.
4. **Unit-aware weights + session draft persistence.** Respect `preferredUnits` in sessions, fix the rounding, and save the draft so a killed app can resume the workout.

**Phase 1: the progression loop**

5. **RIR logging.** Replace the unused `rpe` field with `rir: Int?`, add a per-set picker, and set target RIR per template exercise.
6. **Plate & bar inventory + `LoadCalculator`.** Extends GymProfile.
7. **Smart Progression v1.** Rule-based double progression with RIR, plus a "why" sheet and fix suggestions. Also add rep PRs and e1RM PRs.

**Phase 2: nutrition intelligence**

8. **Trend weight.** Exponentially weighted moving average; replaces the straight-line projection.
9. **Adaptive TDEE.** Weekly expenditure estimate from intake and trend weight. Also read weight from HealthKit, so smart-scale weigh-ins come in automatically.

**Phase 3: depth and polish**

10. **Levels.** Weekly sets per muscle on your existing `BodyDiagramView`, using library primary/secondary muscles via exercise ID.
11. **Smart warm-ups**, then **advanced set types** (drop, myo, failure, supersets, unilateral).
12. **Live Activity rest timer.** Needs a new widget extension target.
13. **Training-cycle programs**, then the **training-aware coaching** differentiator.

Later or never: auto-generated programs, spreadsheet import. Small fix any time: the 6 test warnings and the README (iOS 26.5, not 17+; RPE not recorded).

## Claude Code prompts

Run them in order, one per Claude Code session, in plan mode first, and review the plan before it writes code. Paste the **Vora rules** block at the end of every prompt. Commit after each one passes.

**Vora rules (append to every prompt)**

```
Rules: production quality, no TODOs/placeholders. DesignSystem constants only (Vora/Utilities/DesignSystem.swift), no hardcoded hex. No unjustified force unwraps, no print(). Replace try?/assertionFailure with explicit error handling in any code you touch. Zero warnings in app AND test targets. Swift Testing (@Test) unit tests for every model, migration and service change, using in-memory containers like the existing tests. Run the full suite and report pass/fail totals. Do not commit; summarize changed files so I can review.
```

**Prompt 0 — Git baseline** (run in Terminal yourself, not Claude Code)

```
cd ~/Desktop/Vora
git init
printf "build/\nDerivedData/\n*.xcuserstate\nxcuserdata/\n.DS_Store\n" > .gitignore
git add . && git commit -m "Baseline before progression work"
```

Then push it to github.com/MajdArow123/Vora. If that repo already has history, ask me first so we don't overwrite it.

**Prompt 1 — Versioned schema + safe container**

```
Vora currently uses one flat Schema([...]) of 18 models in VoraApp.swift with no VersionedSchema, and fatalError if the ModelContainer fails.

1. Create SchemaV1: VersionedSchema containing exactly the current 18 models as they are today (no property changes).
2. Create VoraMigrationPlan: SchemaMigrationPlan with schemas [SchemaV1] and no stages yet, structured so future versions add a stage.
3. Use the plan when building the ModelContainer in VoraApp.swift.
4. Replace fatalError with a recovery flow: log the error, show a DesignSystem-styled error screen with "Retry" and "Export data" options. Never silently delete the store.
5. Add a short docs/MIGRATIONS.md explaining how to add SchemaV2 with a stage.
6. Tests: container builds with the plan in memory; existing data from the current flat schema opens without loss (create a store with the old setup, reopen with the plan).
```

**Prompt 2 — Stable exercise IDs**

```
Exercises are matched by exerciseName.lowercased() for history, PRs and prefill. Make identity stable.

1. Add a stable `id: String` slug to every ExerciseDefinition in Utilities/ExerciseLibrary.swift (e.g. "barbell-bench-press"); keep `name` for display. Add a lookup by id and a legacy lookup by lowercased name.
2. Add SchemaV2 with `exerciseId: String?` on ExerciseLog. Migration stage: backfill exerciseId from the name via the legacy lookup; leave nil for unknown or custom names.
3. Switch ActiveSessionViewModel.prefill / previousSets, WorkoutHomeViewModel.computePersonalRecords, the PR check in finish(), and ExerciseHistoryView to match on exerciseId (falling back to name only when nil).
4. Replace the fetch-all-sessions scans with FetchDescriptor predicates and fetchLimit (most recent session containing the exercise).
5. Tests: backfill, rename-safety (changing a display name keeps history), fallback for nil ids, the predicate-based previousSets.
```

**Prompt 3 — Templates as SwiftData models**

```
Templates are [String: [String]] in UserDefaults ("vora.workoutTemplates", keyed "split.dayIndex"), handled by WorkoutTemplateStore, and every session starts with a hardcoded 4 sets and @AppStorage restTimerSeconds = 90.

1. SchemaV3: add WorkoutTemplate (id, splitDayIndex, name, exercises cascade) and TemplateExercise (id, exerciseId, orderIndex, targetSets default 3, repRangeMin default 8, repRangeMax default 12, targetRIR: Int? default 2, restSeconds default 120 compounds / 90 isolation by library muscle group, parent).
2. One-time migration from the UserDefaults dictionary on first launch after update; remove the key only after a successful save; idempotent.
3. Replace WorkoutTemplateStore usage. Update TemplateEditorView to edit sets, rep range, target RIR and rest per exercise (steppers, DesignSystem styling).
4. ActiveSessionViewModel.prefill uses targetSets and restSeconds from the template instead of the constants; show the rep range in each SetRow as a placeholder.
5. Tests: UserDefaults migration (including empty/malformed data), defaults, prefill counts.
```

**Prompt 4 — Units in sessions + draft recovery**

```
1. ActiveSessionView and SetRow ignore preferredUnits and weightString uses %.1f (breaks 1.25 kg steps). Store kg internally; display and input in the user's unit via UnitConversion; format with up to 2 decimals, trimming trailing zeros. Apply the same to history and PR displays.
2. Draft sets are in-memory DraftSet values lost if the app is killed. Persist the active session draft (Codable snapshot in Application Support, written on every set change, debounced) and, on launch, offer "Resume workout" if a draft under 12 hours old exists. Clear it on finish or discard.
3. Tests: unit round-trips, formatting, draft save/restore/expiry.
```

**Prompt 5 — RIR logging**

```
SetEntry has `rpe: Int` (0 = unset) that the UI never sets. SchemaV4: add `rir: Int?` to SetEntry (0–5; 0 means failure) and remove rpe (all values are 0, so no data is lost; confirm with a check in the migration stage). Add a compact RIR picker to SetRow (0, 1, 2, 3, 4, 5+), optional, never blocking completion, pre-filled with the template's targetRIR as a placeholder only. Carry rir through DraftSet into finish(). Show RIR in WorkoutSessionDetailView and ExerciseHistoryView. Fix the README's RPE claim. Tests for the migration and the save path.
```

**Prompt 6 — Plate inventory + LoadCalculator**

```
GymProfile stores only an equipment set. SchemaV5: add loading inventory to GymProfile — bars [(name, weightKg)], plates [(weightKg, pairCount)], dumbbellIncrementKg, machineIncrementKg (Codable value arrays with defaults based on GymPreset; lb gyms get lb plate sets stored in kg).

Create a pure LoadCalculator in Utilities/:
- achievableLoads(equipment:, profile:) -> [Double]
- nearestAchievable(targetKg:, equipment:, profile:, rounding: .down | .nearest) -> Double
- plateBreakdown(totalKg:, bar:, profile:) -> [PlateCount]? (per side, respects pair counts, nil if impossible)

UI: plate inventory editor in GymProfileView; a plate calculator sheet from barbell SetRows showing the per-side stack. Exhaustive tests: impossible loads, limited counts, kg and lb gyms, 1.25 kg microplates.
```

**Prompt 7 — Smart Progression v1**

```
Build a deterministic, rule-based ProgressionEngine (pure struct in Utilities/, no SwiftData inside; input plain value types). No AI/LLM calls. Propose the design before coding.

Input: exerciseId, TemplateExercise targets (sets, repRangeMin/Max, targetRIR), last 1–3 sessions' completed SetEntry values (weightKg, reps, rir), active GymProfile + LoadCalculator, setting progressionMode (.weightFirst | .repsFirst).
Output per working set: Recommendation { weightKg, targetReps, reason: ProgressionReason, warnings: [ProgressionWarning], fixes: [ProgressionFix] }.

Rules (double progression with RIR):
- e1RM per set with the existing Epley in StrengthProgression, using reps + rir as reps-to-failure (when rir is nil, assume targetRIR).
- All sets at the top of the range with rir >= targetRIR -> next achievable load (LoadCalculator, .nearest above), reps reset to repRangeMin.
- Within the range -> same load, +1 rep target.
- Below repRangeMin or rir < targetRIR - 1 on most sets -> hold, or drop ~5–10% rounded to achievable.
- No achievable load fits the range (big dumbbell jumps) -> warning plus fixes: extend reps past the range, widen the range, or swap equipment.
- In session: if set 1 deviates strongly from the predicted e1RM, retarget the remaining sets.
- No history -> no recommendation (keep the current prefill behavior).

Integration: ActiveSessionViewModel.prefill uses the engine when enabled (Settings: "Smart" vs "Previous values"). SetRow shows SF Symbol wand.and.stars on adjusted sets; tapping it opens a sheet with the reason in plain English. Warnings use a yellow DesignSystem state with one-tap fixes.
Also extend PRs: add rep PRs at a given weight and e1RM PRs alongside the existing heaviest-weight PR.

Tests: every rule and boundary, nil RIR, plate-limited loads, first session, both progression modes, PR types.
```

I'll write the Phase 2–3 prompts once Phase 1 is in, using whatever the code looks like then.

## How to study MacroFactor legally

Use the 7-day free trial as a hands-on teardown. Study the behavior, never the code. Don't decompile the app or copy its assets or text.

- [ ] Log 3–4 real sessions and screen-record each one
- [ ] Note when Smart Progression raises, holds or lowers weight, and what the "why" sheet says each time
- [ ] Log a set far off target and watch how the remaining sets re-adjust
- [ ] Set up a dumbbell-only gym profile and look for the "impossible load" warnings and fixes
- [ ] Time how many taps it takes to log one set, and compare with Vora
- [ ] Screenshot Levels, the warm-up suggestions and the plate calculator to use as UX references
- [ ] Read the help-center articles on Smart Progression and Levels (linked below)
- [ ] Cancel before day 7

## Sources

- [MacroFactor Workouts — official page](https://macrofactor.com/workouts/)
- [Understanding and using Smart Progression](https://help.macrofactorapp.com/en/articles/305-understanding-and-using-smart-progressions)
- [What the Smart Progression wand means](https://help.macrofactorapp.com/en/articles/391-what-does-the-smart-progression-wand-mean)
- [Understanding Levels](https://help.macrofactorapp.com/en/articles/342-understanding-levels)
- [Missed workouts and training cycles](https://help.macrofactorapp.com/en/articles/382-what-happens-to-my-program-if-i-miss-workouts-or-take-time-off)
- [January 2026 newsletter (launch, progression updates)](https://macrofactor.com/mm-jan-2026/)
- [April 2026 newsletter (Levels, reps-first setting, Live Activities)](https://macrofactor.com/mm-april-2026/)
- [October 2025 newsletter (fatigue estimation, smart swaps)](https://macrofactor.com/mm-oct-2025/)
- [Weight Trend explained](https://help.macrofactorapp.com/dashboard/weight_trend/)
- [Dynamic energy expenditure calculator](https://macrofactorapp.com/?p=4961)
- [Expenditure algorithm V3](https://macrofactor.com/expenditure-v3/)
- [Press kit (pricing)](https://macrofactor.com/press-kit/)
