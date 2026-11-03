# Coaching

How training and nutrition inform each other. Every rule lives in `CoachingEngine` (`Vora/Utilities/CoachingEngine.swift`) and `CalorieCycling` (`Vora/Utilities/CalorieCycling.swift`), both pure. `CoachingService` and `CalorieCyclingService` read the store for them. Nothing changes targets without the user asking, and nothing here is stored: there's no schema change, and calorie cycling's setting is in UserDefaults.

## Strength trend

The check-in's Training section starts from one number: how the user's top lifts are moving.

| What | Value | Why |
|---|---|---|
| Window | 28 days, today left out | Sees past one bad session; today may be partial |
| Sets | Record-eligible only (`SetType.countsTowardRecords`), weight over 0, up to 15 reps | Over 15 reps Epley gets unreliable, and moving to high-rep work would fake a trend. docs/SET_TYPES.md says why drop and myo-rep sets don't count |
| Per session | Best e1RM (Epley on weight and reps) | One back-off set shouldn't move it |
| RIR | Ignored, as in records | Otherwise starting to log RIR would look like getting stronger |
| A lift counts with | 3+ sessions spanning 14+ days | Too little to draw a line through otherwise. In a 28-day window this also means the last session is at most 13 days old, so a dropped lift stops counting by itself |
| Per lift | Least-squares slope, as % per week of the lift's average | Same method as the expenditure slope |
| Top lifts | The 5 with the most sessions; ties by volume, then key | The lifts done most say the most |
| Overall | Median of the top lifts; needs at least 2 | One lift could be a niggle or a technique change |
| Falling or rising | ±0.5% a week or more; between is flat | About one rep at 8 reps over the window. Less is noise |

Lifts match by `ExerciseLog.matchKey`, never by name.

"Falling for two check-ins" compares the trend as of yesterday with the trend as of 7 days before. It's worked out from sessions each time, so skipped check-ins still count and deleting a session corrects it. Falling now with too little data last week isn't consecutive.

## Check-in rules

Only a check-in with enough data to propose targets has a Training section. There's one result per check-in, and adjustments never add together.

| Goal | When | Result |
|---|---|---|
| Fat loss | Falling for two check-ins | Ease +100 kcal |
| Fat loss | Losing more than 1.5 × the goal rate | Ease +150 kcal, also when strength is falling too (both reasons shown) |
| Muscle gain | Strength flat and gaining more than 1.25 × the goal rate | Trim −100 kcal |
| Muscle gain or maintain | Strength rising | "On track" |
| Any | Too little training data, and no rule above fired | Says so, and what's missing |
| Anything else | | No change |

**Goal rate** isn't stored, so it's derived: `expenditure × (goal multiplier − 1) × 7 / 7700`. At 3,000 kcal that's about −0.55 kg a week on fat loss and +0.33 on gain. **Weight rate** is the estimator's least-squares slope, the same number the sheet shows above it.

**Losing too fast still fires with too little training data,** since it only needs weight and intake; the section also says strength couldn't be judged. Rules that depend on strength never fire without it. Gaining fast with falling strength offers no trim: the rule is about flat strength, and cutting calories wouldn't help falling strength.

### Intake gates the suggestion

An adjustment is only offered when the 21-day average intake is within ±10% of the current target. Changing a target the user isn't eating to wouldn't change what's on the plate.

| Intake | Fat loss signal | Gain signal |
|---|---|---|
| Under target | "Eat up to your target first" | "Lowering it wouldn't touch this" |
| On target | Offers the adjustment | Offers the adjustment |
| Over target | "The target isn't what's behind this" | "Try eating closer to your target first" |

**This shapes when losing too fast offers calories.** Once the estimate has caught up with reality, losing 1.5 × the goal rate means eating about 12.5% under target (at a 20% deficit, 30% below expenditure is 87.5% of 80%), which is past the gate. So the +150 is mainly offered while the estimate is still catching up, when eating on target really is too little: the capped case, where the estimate lags and `--seed-coaching=lossTooFast` lives. Otherwise the user gets the "eat up to your target" note, which is the same advice in a form that can work: their target already holds the right number.

### Limits on an adjustment

`CalorieCalculator.adjusted`:

- It sits on top of the proposed targets, so the goal multiplier has already applied.
- Protein stays constant; carbs and fat follow the calories.
- The floors still apply: the formula BMR and 1,200 kcal.
- Easing stops at expenditure, so a deficit can't become a surplus. Trimming stops at expenditure, so a surplus can't become a deficit.
- If those limits leave no change, the rule still explains itself and offers nothing.

### What Apply does

The sheet's toggle is off until the user taps it, and the targets card follows it. Apply writes the targets on screen, and `appliedCalories` and the rest record them. Skip writes nothing, as before. `estimateKcal` never includes an adjustment.

**An adjustment lasts one week.** Next week's proposal starts again from expenditure × goal, so it stays only if the rule fires again, and targets can step back down when it doesn't. Carrying it forward would need stored state or inferring it from `appliedCalories`.

## Deficit-aware progression

A **meaningful deficit** is intake at least 10% below expenditure: the last 7 complete days (at least 4 usable, leaving out days under 40% of the estimate, like the estimator) against the latest check-in's estimate, which must be at most 28 days old. A skipped check-in still has an estimate. It reads what the user eats, not their goal. Without an estimate there's no deficit context, so it never guesses.

In a deficit:

- **The "why" explains it.** Same-weight and add-a-rep reasons add that holding weight is normal, and how far below expenditure the user is.
- **A load drop takes 3 struggling sessions instead of 2.** A poor session in a deficit is more likely recovery than lost strength, and keeping the load is what protects muscle. It still drops at the third, so it can't hold forever. The second session reads `holdForDeficit`. A session under a different rep range never counts, as before.

Load raises don't change: a deficit never holds back progress someone has earned. Retargets within a session don't change either. `Recommendation.deficitPercent` carries it into the draft (version 6).

## Calorie cycling

Off by default (Profile › Preferences). Training days get more and rest days fewer, with the same weekly total. The profile always keeps the base targets, and everything that reads a weekly average (Progress, the check-in's adherence) stays on the base, since that's the right comparison. Home, the diary and meal suggestions use the day's targets.

**The week** runs Monday to Sunday. Each day shares out what's left of it:

```
rest day     = (budget left − expected training days left × gap) / days left
training day = rest day + gap
```

Values round to 10 kcal and the last day takes the remainder, so a full week adds up exactly. The gap is 10% of the base (`CalorieCycling.dayGapFraction`), which is 250 kcal on a 2,500 base: enough to feel on the plate, small enough not to strain rest days. With 0 or 7 training days, every day equals the base.

**Macros:** protein constant; carbs and fat scale by the calories that aren't protein.

**Floors apply on every day.** When the rest number would go under the floor, rest days sit on it and the gap shrinks. If rounding leaves the last days just short of the floor (a base close to it with unexpected training days), the floor wins and the week runs a few kcal over. A base already at or below the floor doesn't cycle, since cycling could only lower it. With no weigh-in the floor isn't known, so cycling stays off.

### What counts as a training day

| Mode | Training day | Expected training days |
|---|---|---|
| Weekly | The planned `SplitDay`, whatever was actually done | The plan's count |
| Cycle | A day with a session that has a training set, or today with a session in progress | Sessions per week over the 4 weeks before this week, rounded |

**A cycle's next entry doesn't make a training day.** A missed day doesn't move the cycle, and cycles have no rest entries by default, so "the next entry is a training day" is true on every untrained day. Every day would get the high target and the week couldn't add up. So a cycle day starts as a rest day, with "Train today and this becomes X", and starting a session moves it up; discarding moves it back, including from the launch "Resume workout?" dialog (`LaunchDraftViewModel` reloads Home). Warm-ups alone don't count, the same as for advancing the cycle.

Future days have no plan in cycle mode, so they stay on the base in the diary.

**Known costs:**

- A cycle-mode week with far less training than usual pushes the remainder onto its last days, since earlier rest days were lowered expecting more training. Keeping the total exact requires it.
- Past days are worked out again from sessions, so turning cycling on mid-week, or changing the base mid-week, recalculates the earlier days as if it had always been that way.

## Trying each rule

`--seed-demo --seed-coaching=<scenario>` on an empty store:

| Scenario | Triggers |
|---|---|
| `strengthFalling` | Ease +100 for falling strength |
| `lossTooFast` | Ease +150 for losing too fast |
| `gainTooFast` | Trim −100 |
| `gainOnTrack` | "On track" |
| `notEnoughTraining` | Not enough training data |
| `deficitHold` | Start a session: same weight because of the deficit, on the second hard session |

Add `-vora.calorieCycling YES` for calorie cycling, and `--seed-cycle` for cycle mode.
