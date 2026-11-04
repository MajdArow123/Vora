# Vora vs MacroFactor Workouts — Gap Analysis & Roadmap

Nov 1, 2026 · @majd arow

> **Status (updated 2026-11-03):** Prompt 0 (git) done. Prompt 1 (versioned schema) committed in `0cafae8`. Prompt 2 (stable exercise IDs) committed in `712aea5`. Prompt 3 (templates as SwiftData) done: SchemaV3 adds `WorkoutTemplate` / `TemplateExercise` (matched by `exerciseId`, custom exercises by `customName`), lightweight stage + post-open UserDefaults move, per-exercise sets / rep range / target RIR / rest (compound 120 s, isolation 90 s via the new `mechanics` field), generic "Leg Curl" hidden from the picker as legacy-only, V2 fixture from `712aea5`, 580 tests passing. Prompt 4 (units in sessions + draft recovery) done, no schema change: sessions, history, PRs, exercise history, summary and strength analytics show and take weights in `preferredUnits` (stored as kg, up to 2 decimals, lb input round-trips exactly); the active session autosaves a debounced Codable draft to Application Support and launch offers "Resume workout" / "Discard" for drafts under 12 hours, dropping finished rests and excluding interruptions over 5 minutes from the duration and HealthKit workout; unreadable drafts are logged and set aside. 612 tests passing, zero warnings in both targets. Prompt 5 (RIR logging) done: SchemaV4 replaces `SetEntry.rpe` with optional `rir` (0–5, 0 = failure, 5 = 5+) and adds optional `healthKitWorkoutID` to `WorkoutSession` and `CardioEntry`, lightweight stage, V3 fixture and v1 draft fixture from `07190d1`. The rpe check in the Prompt 5 text was replaced by evidence recorded in docs/MIGRATIONS.md, since no build ever wrote rpe. SetRow has an optional RIR picker with the template target as a placeholder only; RIR is carried through the draft (version 2; version 1 drafts still restore) into history. Prompt 6 (plate inventory + LoadCalculator) done: SchemaV5 adds an optional loading inventory to `GymProfile` (bars, plates with pair counts, dumbbell and machine steps; all in kg, lb sets converted), lightweight stage, GymProfile frozen into V1–V4, V4 fixture from `2b8a20e`. Defaults are written once units are known (end of onboarding, post-open backfill, new gyms and `applyPreset`), so changing `preferredUnits` only changes display, never a gym's plates. `LoadCalculator` is pure and takes a `LoadingInventory` value. GymProfileView edits the inventory, with "Use standard kg/lb set"; barbell and Smith SetRows show the per-side stack and open a plate calculator sheet. Smith machines are plate-loaded with their own bar (default 15 kg / 35 lb, 0 for counterbalanced), added only to gyms that have one; no library exercise uses a Smith machine yet. Prompt 7 (Smart Progression v1) done: a pure, deterministic `ProgressionEngine` (no SwiftData, clock or units) does double progression with RIR and gives a reason for every recommendation, shown in a "why" sheet from the wand on each set. Settings: Smart or Previous values, reps first or weight first. Target reps show as placeholders and are never prefilled, so logged numbers stay real. SchemaV6 adds an optional target snapshot to `ExerciseLog`, written at finish: past sessions are judged against the targets they were done under, nil (old logs) falls back to current targets, a changed range re-baselines from e1RM and can never cause a drop. Over 21 days since the exercise holds the load ("welcome back"). Set 1 retargets the remaining sets when it's 7.5% or more off the predicted e1RM, raising one load step at most, so a typo can't load the bar. On machines, cables and dumbbells any weight logged for that exercise counts as loadable alongside the step grid, so a weight you lifted is never snapped; barbell and Smith stay plate-exact. Big jumps and limits warn with one-tap fixes (extend reps, widen the range in the template, swap). Rep and e1RM PRs join heaviest-weight PRs, using logged reps only. V5 fixture and v2 draft fixture from `ec4b816`. Prompt 8 (trend weight) done, no schema change: a pure `WeightTrendCalculator` smooths weigh-ins with an EWMA (0.1 per day, gaps decay over the elapsed days, same-day readings averaged), always over all history, so Home and Progress agree and a chart range only changes what's drawn. Goal projection uses the trend's 14-day rate and says "not enough data" under 10 logged days or with no weigh-in in 14 days. Progress shows pale scale dots under a bold trend line with the weekly rate; Home shows the trend. Body-weight displays and input respect `preferredUnits` via `WeightField`, so untouched text keeps its exact kg. An optional, off-by-default Apple Health import reads body mass (read-only: the write permission is gone and the usage strings say what Vora does). Imported entries use the sample's UUID as `WeightEntry.id`, which makes re-imports no-ops without a new column; the cost is no "Apple Health" label and no removal when a sample is deleted in Health. Prompt 9 (adaptive TDEE) done: a pure `ExpenditureEstimator` takes average intake minus the least-squares weight slope × 7700 kcal/kg over the last 21 complete days (today is left out as partial), excludes days under 40% of the current estimate, needs 10 intake days and 8 weigh-ins, blends by completeness (`min(intakeDays / 21, min(1, weighIns / 14))`) and caps each update at ±150 kcal. Home offers a weekly check-in (default Monday, set in Profile, stays open until the next check-in day; "not enough data" shows on the day itself only) with old vs new expenditure, why, and proposed targets; only Apply changes targets. Floors are the formula BMR and 1,200 kcal. Skip still saves the estimate, which stays on the chart and is next week's starting point. SchemaV7 adds `ExpenditureCheckIn`, lightweight stage, V6 fixture from `5228197`. Progress shows an Expenditure chart under the weight trend. `--seed-demo` now writes 60 days at 2,600 kcal and −0.5 kg/week, which reads about 3,150 through the real service. Prompt 10 (Levels) done, no schema change: a pure `LevelsCalculator` counts each completed set as 1 for primary muscles and 0.5 for secondary, averaged over a rolling 1, 4 or 12 weeks. When training began inside the range it divides by the time since the first session (at least one week), so short histories aren't diluted and a first session isn't scaled up; layoffs after that still count. Custom exercises count only if every stored group means exactly one muscle (back, shoulders and core don't); otherwise they're left out and reported in a "Not counted" note. Progress › Strength has a Levels card opening the body map, legend, sorted muscle list and per-muscle exercises, from the list or a tap on the map. The 10–20 sets/week guideline band lives in `LevelsGuideline` and is easy to remove. Prompt 11 (smart warm-ups + set types) done: SchemaV8 adds optional set type and side to `SetEntry` and a superset group to `ExerciseLog`, lightweight stage, workout cluster frozen into V6 and V7, V7 fixture and v3 draft fixture from `0dbc46f`; draft version 4. Who counts what is one set of rules on `SetType`, explained in docs/SET_TYPES.md: warm-ups count toward nothing; drop and myo-reps count toward Levels and volume only; failure sets are working sets with RIR 0 implied on read, never stored. A left and right row are one set in Levels. A pure `WarmUpGenerator` ramps compound lifts up to the first working weight (bar × 10, 50% × 5, 70% × 3, 85% × 1) through `LoadCalculator`, skipping steps that don't climb or that reach the working weight; on by default, set under Workout suggestions; "Add Warm-Ups" in the exercise menu covers a first session with no known weight. Tap a set number to change its type or side; a bracket in the gutter links supersets. No rest timer after a warm-up, before a drop or myo set, or between superset exercises until the round is done. Superset links aren't saved to templates yet. Prompt 12 (Live Activity rest timer) done, no schema or draft change: a `VoraRestActivity` widget extension shows the next exercise and set and a self-ticking countdown on the Lock Screen and in the Dynamic Island. `restEndDate` in `ActiveSessionViewModel` is the one source of truth; a single sync sends changes to `RestActivityController` (at most one activity, updated in place) and `RestAlertService` (a local notification at the end time, never prompts for permission). Both sit behind injected protocols that default to no-ops, so only `ActiveSessionView` reaches the real ones. The rest bar gained −15 / +15 buttons; the activity itself has no buttons, since those need App Intents. A next set shows as "80 kg × 8", "180 lb × 8–12" or "Warm-up · 20 kg × 10", formatted by the app in the user's units. `Shared/` is compiled into both targets and holds the attributes and `DesignSystem`. Free provisioning: Live Activities need no capability, so the Personal Team signs the extension with its own App ID and no App Group. Without push, a suspended app can't end its activity at the end time: the stale date flips it to "Rest over" and it ends when Vora next becomes active. `willTerminate` isn't guaranteed, so leftovers are also swept at cold launch; the pending alert survives a kill because the draft's rest is still running. A failed finish save also ends the rest, since the session screen goes away with the summary; the draft stays. Prompt 13 (training-cycle programs) done: alongside weekly mode, the default and unchanged, a cycle runs the training days in order, so today's workout on Home and Train is the next day whatever the weekday. Finishing a session advances from that day, so "Start a Different Day" carries on from whichever day you did; "Skip to Next Day" is explicit, and nothing else moves it. Rest entries are optional and pass by themselves. The first switch copies the week's training days into cycle days that own their templates, so editing Day 1 never changes Monday; switching back only changes the mode, and switching again resumes the cycle and position. Who does what in each mode is one table in docs/TRAINING_CYCLES.md: the week strip becomes calendar-only, a cycle streak carries up to `max(2, longest run of rest entries)` untrained days, the missed-workout insight waits until the last session is 2 days old, and reminders name the next day. Edit Split gains a Weekly / Cycle picker and a cycle editor. Templates can now hold superset links, and sessions start with them applied. SchemaV9 adds `TrainingProgram` and `CycleDay` plus optional `TemplateExercise.supersetGroup` and `WorkoutTemplate.cycleDay`, lightweight stage, no backfill since no program row reads as weekly, template cluster frozen into V3–V8, V8 fixture and v4 draft fixture from `2517af9`; draft version 5 adds the slot's cycle day. Prompt 14 (training-aware coaching) done, no schema change; every rule and number is in docs/COACHING.md. A pure `CoachingEngine` reads a strength trend (median weekly e1RM change of up to 5 top lifts over 28 days, record-eligible sets only, RIR ignored) and the weekly check-in gains a Training section. Fat loss with strength falling for two check-ins offers +100 kcal, and losing over 1.5 × the goal rate offers +150. Gain with flat strength and weight rising over 1.25 × the goal rate offers −100. Gain or maintain with strength rising says on track, and too little data says so. An offer is an off-by-default toggle on top of the proposed targets, only when intake is within ±10% of the target, with floors and expenditure as limits, and it lasts one week. "Two check-ins" is worked out from sessions, so nothing is stored. Smart Progression knows about a deficit (intake ≥10% below the latest estimate): the "why" says holding weight is normal, and a load drop takes 3 struggling sessions instead of 2; draft version 6, v5 draft fixture from `f83582a`. Optional calorie cycling (off by default) shifts calories to training days with the same Monday–Sunday total, protein constant, floors on every day; a cycle-mode day only becomes a training day once a session starts, because the next entry is a training day on every untrained day. `--seed-demo --seed-coaching=<scenario>` triggers each rule. **Next: pick from the follow-ups and small fixes below.**
>
> Lessons applied so far (see docs/MIGRATIONS.md): freeze every model in a relationship cluster, not just the one that changes; prefer `.lightweight` stages plus an idempotent post-open backfill in `AppDataStore.load()` over custom stages; test migrations against a real fixture store generated from the previous commit; always match exercises by `exerciseId`, never by name.

## Summary

The biggest gap is still **Smart Progression**, but the 2026-11-01 code audit shows Vora isn't ready for it yet. Sets store only weight and reps, templates are name lists in UserDefaults, exercises are linked by name string, and there's no versioned schema. A bad migration would crash the app with `fatalError`. Fix those foundations first (Phase 0), then build progression.

- **Put Vora in git before anything else.** The audit found no git repository in the project folder.
- **Already done:** muscle diagrams and technique cues exist (66 exercises with primary/secondary muscles and cues), so the old Improvement 13 is mostly finished. Tests: 487 passing at the audit; both targets now build with zero warnings.
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
| Next-set weight/rep recommendations | Smart Progression, with explanations | Done (Prompt 7): rule-based, with a "why" for every set and one-tap fixes | Small (fatigue model) |
| Template targets (sets, rep range, RIR) | Yes | Exercise names only in UserDefaults; fixed 4 sets | Large (foundation) |
| Stable exercise identity | Yes | Matched by `exerciseName.lowercased()` | Medium (foundation) |
| RIR / effort logging | Yes, also feeds progression | Done (Prompts 5 and 7): optional per-set RIR, feeds progression | None |
| Units in workouts | kg/lb | Done (Prompt 4) | None |
| Plate calculator | Per gym profile's plates and bars | Done (Prompt 6): per-gym bars and plates, per-side stack from barbell sets | None |
| Gym profiles + equipment filtering | Yes | Done | None |
| Muscle diagrams + technique cues | 900+ exercises, videos | Done for 66 exercises | Small (add more exercises) |
| Weekly sets per muscle ("Levels") | Body map, with contributing lifts | Done (Prompt 10): body map, sets per muscle, contributing exercises | None |
| Rest timer | Customizable, Live Activity | Done (Prompt 12): per-exercise, ±15 s, Live Activity, rest-over alert | None |
| Session crash recovery | Not documented | Done (Prompt 4): draft autosaved, resume on launch | None |
| Smart warm-ups | Yes | Done (Prompt 11): ramp from the first working weight and the gym's loads | None |
| Advanced set types | Drop, myo, failure, partials, supersets, L/R | Done (Prompts 11 and 13): drop, myo, failure, supersets (also in templates), L/R; no partials | Small (partials) |
| PRs | Weight, reps, e1RM | Done (Prompt 7): weight, reps at a weight, e1RM | None |
| Trend weight | Core feature | Done (Prompt 8): smoothed trend, trend-based goal projection | None |
| Adaptive TDEE | Core feature, in a separate app | Done (Prompt 9): weekly estimate from intake and weight slope, targets applied by choice | None |
| Programs on training cycles | Yes | Done (Prompt 13): weekly or cycle, skip, any day, cycle editor; no deloads or periodization | Small (deload weeks, periodization) |
| HealthKit | Writes workouts | Writes workouts; optional weight import (Prompt 8) | None |
| Nutrition and training in one app | No, two apps | Yes | **Vora's advantage** |
| Training-aware coaching | No shared coaching | Done (Prompt 14): check-in rules from strength and weight rate, deficit-aware progression, optional calorie cycling | **Vora's advantage** |

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
9. **Adaptive TDEE.** Weekly expenditure estimate from intake and trend weight.

**Phase 3: depth and polish**

10. **Levels.** Weekly sets per muscle on your existing `BodyDiagramView`, using library primary/secondary muscles via exercise ID.
11. **Smart warm-ups**, then **advanced set types** (drop, myo, failure, supersets, unilateral).
12. **Live Activity rest timer.** Needs a new widget extension target.
13. **Training-cycle programs.**
14. **Training-aware coaching**, the differentiator.

Follow-ups to Prompt 13: **deload weeks** and **multi-week periodization**.

Later or never: auto-generated programs, spreadsheet import.

**Small fixes** (any time)

- The README (iOS 26.5, not 17+; RPE not recorded).
- ~~Body-weight displays (HomeView weight card, Progress weight tab) still show kg only; route them through `preferredUnits` like workout weights.~~ Done in Prompt 8.
- Cardio speed and distance ignore `preferredUnits` (km/h and km even in imperial mode).
- ~~The PR card's "Peak strength" is an estimated 1RM (Epley), not the weight lifted; label it clearly (e.g. "Est. 1RM"). Revisit in Prompt 7.~~ Done: labeled "Est. 1RM"; the card now shows the best estimate across all sets.
- Pluralization: "1 exercises" in History and elsewhere.
- Duration format "1:48" is ambiguous; show "1m 48s" / "1h 12m".
- ~~No way to delete a test or accidental session: History and the session detail have no delete action for workouts or cardio, and nothing in the app deletes a `WorkoutSession`.~~ Done: swipe to delete in History and Delete buttons in the session detail, with a confirmation alert, for workouts and cardio. No schema change. The HealthKit workout is removed by its stored `healthKitWorkoutID` (SchemaV4). Rows without an ID fall back to matching and remove it when exactly one fits; otherwise it's logged and the local delete still happens.
- Long exercise names wrap ("Barbell / Bench Press") when the muscle tag sits beside them in TemplateEditorView.
- Free provisioning: the app expires on the iPhone after 7 days until I join the Apple Developer Program.
- ~~The plate caption under every barbell set may be noisy; consider showing it only on the next uncompleted set.~~ Done: it shows on the next incomplete set of each exercise, and on a set whose weight you tap.
- Dragging an exercise into the middle of a superset breaks it instead of joining.
- ~~With kg display and lb plates (or the reverse), most weights say "Can't load this weight"; show the nearest loadable weights there instead.~~ Done: the set caption and plate sheet show the nearest loadable weights on either side.
- Custom exercises have no muscle group: the picker and template prefill save them with `muscleGroups: []`, so Levels always lists them under "Not counted". Let the user pick a group when adding one.
- The Train card in cycle mode repeats the position in "Day 1 · Push" and "Day 1 of 6"; show it once.
- Fixed sleeps left in tests: `discardClearsTheDraftAndStopsAutosave` (300 ms, could pass without proving anything; check `pendingDraftSave == nil` after the edit instead) and `FoodSearchViewModelTests.swift:161` (50 ms, not yet assessed).
- Verify the `GenericFoods` values against USDA FoodData Central and cite an FDC ID for each entry; they were written from memory.
- Replace the " (estimated)" name suffix on logged meal-suggestion foods with a real `FoodEntry` field at the next schema change.

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

**Prompt 8 — Trend weight**

```
Goal: replace noisy day-to-day scale weight with a smoothed trend, the foundation for adaptive TDEE (Prompt 9).

1. Pure WeightTrendCalculator (Utilities/, no SwiftData, no Date inside — take day offsets as plain values): exponentially weighted moving average, smoothing factor ~0.1 per day as a documented constant. Gaps decay over the elapsed days (don't assume missing days equal the last value), multiple weigh-ins on one day are averaged first, a single entry is its own trend. Output per-day trend values plus current trend and 7-day / 30-day trend change (kg).
2. Replace ProgressViewModel.projectGoal's 14-day straight line with a projection from the trend's recent rate; show "not enough data" under ~10 days of entries instead of a misleading date.
3. Progress weight chart (Swift Charts): pale scale-weight dots + bold trend line, current trend and weekly rate. Home's weight card shows the trend, not the last raw entry.
4. Fold in the ROADMAP small fix: body-weight displays (Home, Progress weight tab, goal weight, log sheet) respect preferredUnits; store kg, convert at display/input via UnitConversion, no drift.
5. Optional HealthKit read of body mass (smart scales): read-only, deduplicated against Vora's own entries, behind an injected protocol stub per CLAUDE.md. If adding it needs a schema change (e.g. a source/ID field on WeightEntry), stop and tell me before adding SchemaV7.
6. Tests: gaps, same-day duplicates, single entry, outlier damping, rate/projection, kg/lb round-trips, HealthKit dedup with the stub.
Simulator check with seeded weights; no device install unless there's a schema change.
```

**Prompt 9 — Adaptive TDEE**

```
Goal: estimate the user's real daily expenditure from what they eat and how their weight trends, and update calorie/macro targets weekly — replacing the one-time Mifflin-St Jeor targets from onboarding.

1. Pure ExpenditureEstimator (Utilities/, no SwiftData, no Date — day offsets as plain values):
   - Inputs: daily intake kcal (nil = not logged), daily scale weights, the current formula TDEE (Mifflin-St Jeor × activity) as the starting prior, and the previous estimate.
   - Weight change rate: least-squares slope of scale weights over the window (default 21 days, documented), NOT the EWMA trend's difference — the trend lags ~35% early on, which would bias expenditure. Keep the trend for display only.
   - Energy density: one documented constant (7700 kcal/kg) — note it's an approximation and early water shifts are why the estimate is smoothed.
   - Raw estimate = average intake on logged days − (slope × energy density).
   - Data quality: exclude unlogged days; treat days under 40% of the current estimate as likely incomplete and exclude them (configurable constant, tested). Require at least 10 logged intake days and 8 weigh-ins in the window; otherwise return the prior unchanged with a reason.
   - Smoothing: blend toward the raw estimate by data completeness, and cap the change at ±150 kcal per weekly update so one odd week can't swing targets.
   - Output: estimate, raw estimate, confidence/reason (enum with data, explained in plain English at display time), days used, slope.
2. Weekly check-in:
   - On a check-in day (default Monday, setting stored like ProgressionSettings), Home offers "Weekly check-in": old vs new expenditure, why it changed (intake avg, trend rate, days logged), and the proposed new calorie + macro targets. User taps Apply or Skip — never silently change targets.
   - New targets = estimate × the existing goal multipliers (fat loss ×0.8, maintain ×1.0, gain ×1.12); protein g/kg from the current trend weight (not a single scale reading); fat 25%, carbs the rest — reuse CalorieCalculator logic. Floors: never below the user's formula BMR, and never below 1,200 kcal.
   - Until there's enough data, the check-in explains how many more days of logging are needed.
3. Persistence: a new ExpenditureCheckIn @Model (date, estimateKcal, rawEstimateKcal, avgIntakeKcal, slopeKgPerDay, daysUsed, applied Bool, appliedCalories/macros). New model only → SchemaV7, lightweight stage, nothing frozen unless an existing model changes. Generate a real V6 fixture from the latest commit.
4. Progress: an "Expenditure" chart (estimate over time from check-ins) next to the weight trend.
5. Tests: steady loss/gain/maintenance scenarios with known answers, missing days, incomplete-day exclusion, too-little-data fallback, the ±150 cap, floors, goal multipliers, kg/lb display, check-in apply/skip persistence, the V6 → V7 migration.
6. Verify in the simulator with --seed-demo extended to ~60 days of food + weights that produce a known expenditure (e.g. intake 2,600, losing 0.5 kg/week → ~3,150). Schema change, so back up and install on my iPhone before committing.
```

**Prompt 10 — Levels**

```
Goal: show how much training volume each muscle gets per week, on the existing BodyDiagramView — MacroFactor's "Levels".

1. Pure LevelsCalculator (Utilities/, no SwiftData, no Date — plain values in):
   - Input: completed sets with exerciseId (or custom name + stored muscle groups), day offset, and the library's primary/secondary muscles per exercise.
   - Counting: each completed set = 1 set for each primary muscle and 0.5 for each secondary muscle (documented constants). Custom exercises without library data count toward their stored coarse muscle group's muscles as primary; if that mapping is ambiguous, exclude them and report the count excluded.
   - Output per muscle: average sets per week over the chosen range (1W, 4W, 12W), and the contributing exercises with their set counts.
2. UI — a "Levels" card/screen reachable from Progress:
   - Front/back body map (reuse BodyDiagramView) colored by weekly sets, with a clear legend (DesignSystem colors only), and a sorted list of muscles with sets/week.
   - Optional reference band per muscle as documented constants (e.g. ~10–20 sets/week as a common hypertrophy guideline) — phrase it as a guideline, not a prescription, and make it easy to remove.
   - Tap a muscle → its contributing exercises and sets.
   - Empty state when there's no training in the range.
3. No schema change expected — stop and tell me before adding one.
4. Tests: primary/secondary weighting, multi-muscle exercises, range averaging (partial first week handled sensibly), custom exercises, deleted sessions excluded, aliases via exerciseId.
5. Verify in the simulator with --seed-demo (light and dark, kg/lb doesn't matter here). No device install needed without a schema change.
```

**Prompts 11–14 (outlines)**

These are outlines only. I'll write each full prompt when it comes up, using whatever the code looks like then.

- **Prompt 11 — Smart warm-ups + advanced set types.** Warm-up suggestions from the first working weight and the gym's loadable weights, then drop, myo, failure, superset and unilateral sets. Together because a warm-up is a set type. Likely a schema change: a set type on `SetEntry`, plus a superset grouping. Levels, PRs and Smart Progression must each decide how to count the new types; warm-ups shouldn't count as working sets.
- **Prompt 12 — Live Activity rest timer.** The rest timer on the Lock Screen and in the Dynamic Island, including with the app in the background. Needs a new widget extension target and shared activity attributes. No schema change expected. Check what free provisioning allows on the iPhone.
- **Prompt 13 — Training-cycle programs.** Programs that advance through a cycle of training days instead of a fixed 7-day week, so a missed day doesn't break the program. Likely a schema change: a program model with cycle position, built on `WorkoutTemplate`. Existing splits need a migration path.
- **Prompt 14 — Training-aware coaching.** Vora's advantage: connecting training and nutrition, which MacroFactor keeps in two apps. For example, calorie targets that respond to training load, and using diet phase to set progression expectations. Depends on adaptive TDEE (Prompt 9), Levels (Prompt 10) and programs (Prompt 13). Schema depends on the design; propose it before coding.

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
