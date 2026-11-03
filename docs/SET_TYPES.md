# Set types

What each kind of set counts toward. The rules live on `SetType` (`Vora/Models/SetType.swift`), so every consumer asks the same place.

| | PRs | Progression | Levels | Volume | Set counts shown | PREVIOUS column |
|---|---|---|---|---|---|---|
| Normal | Yes | Yes | Yes | Yes | Yes | Yes |
| Failure | Yes | Yes, with RIR 0 implied | Yes | Yes | Yes | Yes |
| Drop | No | No | Yes | Yes | Yes | No |
| Myo-reps | No | No | Yes | Yes | Yes | No |
| Warm-up | No | No | No | No | No | No |

## Why

- **Warm-ups** prepare for the work and aren't part of it, so they count toward nothing. Finishing still counts them, so a session with only warm-ups isn't lost.
- **Drop and myo-rep sets** are real training stimulus, so they count toward Levels and volume. They follow incomplete rest, so they say nothing about what you can lift fresh, and progression and PRs ignore them. A myo-rep row may also hold a whole cluster's reps, which would fake a rep or e1RM record.
- **Failure sets** are straight sets taken further, so they count as working sets. Without that, their implied RIR would have nothing to act on.

## Implied RIR

A failure set with no logged RIR reads as RIR 0 through `effectiveRIR`. It's never written to `rir`, so nil still means "not logged". A logged value always wins.

## Sides

A left and a right row together are one set in Levels (`unsided + max(left, right)`), so logging sides doesn't double a muscle's sets. A lone side counts as one. Volume adds both sides, because that load was moved. PRs and progression treat each row as a set, so a weaker side holds progress back.

## Warm-up generation

`WarmUpGenerator` builds a ramp for compound lifts only: bar × 10 on bar-loaded equipment, then 50% × 5, 70% × 3 and 85% × 1 of the first working weight. Each step rounds to the nearest load the gym can make, on the bar that can make the working weight. A step is skipped if it isn't heavier than the last, or isn't lighter than the working weight, so light lifts collapse to fewer sets or none.

Warm-ups are generated when an exercise enters the session and don't follow later weight changes, since they may have been edited. Delete them and use "Add Warm-Ups" to rebuild them. Their reps are filled in, unlike working sets, because they count toward nothing and should take one tap.

## Rest timer

No rest starts after a warm-up, before a drop or myo-rep set, or in a superset while a later exercise in it still has sets to do.

## Supersets

`ExerciseLog.supersetGroup` links consecutive exercises. Groups are renumbered after every move, removal or link, and again at finish after exercises with nothing completed are dropped, so a group is always consecutive with at least two exercises. Moving an exercise into the middle of a superset breaks it. Links belong to the session and aren't saved to templates.
