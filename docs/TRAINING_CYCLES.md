# Training cycles

How schedules work and what each part of the app does in each mode. The rules live in `CycleEngine` (`Vora/Utilities/CycleEngine.swift`), and `TrainingProgramService` applies them to the store.

## Modes

**Weekly** is the default: seven `SplitDay` rows, and today's workout comes from the weekday. **Cycle** is an ordered list of days, and today's workout is the next one, whatever the weekday, so a missed day just waits.

No `TrainingProgram` row means weekly, so nothing changes for anyone until they switch.

## What moves the cycle

| Event | Result |
|---|---|
| Finish a session for the next day | Advances to the day after it, wrapping at the end |
| Finish a different day ("Start a Different Day") | Next day is the one after the day you finished |
| Finish a second session the same day | Advances again |
| "Skip to Next Day" | Advances one; no session is logged |
| Start a session, then discard it | Doesn't move |
| Finish with no training sets (nothing done, or warm-ups only) | Doesn't move; the session is still saved |
| The session's save fails | Doesn't move; the draft stays |
| Delete a session from History | Doesn't rewind; "Set as Next Day" in the editor can fix it |
| Finish in weekly mode, or for a day since removed | Doesn't move; the session is still saved |
| Remove the next day | The day after it becomes next |
| Reorder or add days | Next day stays the same |

The position is a day's ID rather than an index, which is why edits can't change which day is next. It's saved together with the session, so a resumed draft or a retried save can't advance twice.

## Rest entries

The cycle has none by default, since rest is the user's choice. An optional rest entry gives a fixed rhythm, and it applies to one calendar day: tomorrow if you reached it by finishing a session, since today was a training day, or today if you skipped to it. Once its day has passed, the cycle moves on by itself, one entry per elapsed day, stopping at the first training day. You can skip one, or train through it, which starts the next training day.

A cycle needs at least one training day, so the editor won't remove the last one.

## Numbering

"Day N" counts training days only, so adding a rest entry doesn't renumber anything. A day reads "Day 2 · Pull", or "Day 2" with a blank title. Sessions take the same name.

## Switching modes

Switching to cycle the first time copies each training day of the week, in order, Monday first, with what that weekday would start today, including built-in defaults. A split with no training days starts with one empty Day 1.

They're copies: cycle days own their templates, so editing Day 1 never changes Monday, and the other way round. Switching back only changes the mode, so the weekly plan is exactly as you left it. Switching to cycle again resumes the same cycle and position. "Rebuild from Weekly Split" replaces it after a confirmation.

Changing the split in Profile only changes weekly slots. The profile says so while cycle mode is on.

## Who does what in each mode

| Consumer | Weekly | Cycle |
|---|---|---|
| Home card | The weekday's `SplitDay` | The next day. Reads "Up Next" once you've trained today. A rest entry shows the rest card |
| Train card | The weekday's `SplitDay` | The next day, "Day 2 of 4", "Skip to Next Day", "Start a Different Day" |
| Week strip | Done, today, upcoming, missed, rest | Calendar only: done, today, upcoming, or blank for a past untrained day. Never missed or rest, and no workout names |
| Streak | Every scheduled day trained; rest days carry | Untrained days carry up to `max(2, longest run of rest entries)`; one more breaks it |
| Week dots | Session dates | Session dates |
| `missedWorkout` insight | Any untrained training day | The next entry is a training day, you haven't trained today, and your last session was at least 2 days ago |
| Workout reminder | Training weekdays, named after that weekday's day | Any day, except today on a rest entry; names the next training day |
| Weekly review | "N training days planned" | "Next up: Day 2 · Pull" |
| Widen-range fix | Saves to the weekday's template | Saves to the cycle day's template |
| Levels, PRs, progression, volume, History | Read sessions only | Same |
| Weekly check-in day | A calendar setting | Same; it's about nutrition, not training |
| Calorie cycling | Planned `SplitDay`s are training days | A day with a started or finished session; the next entry alone doesn't count (see docs/COACHING.md) |

## Why

- **The streak can't follow scheduled days,** because a cycle has none, and counting only trained days would punish the rest it leaves to you. The allowance covers ordinary rest, and following the cycle's own rest entries can never break it. Carried days count only with a session before them, so rest alone can't build a streak. Today stays a grace day, as in weekly mode.
- **The insight waits two days** because asking on every untrained day would nag through that same rest.
- **The week strip stops saying "missed"** because nothing was scheduled, so nothing could be missed. The cycle's own progress is on the Train card.
- **Sessions don't record their cycle day.** Nothing here needs it, and the position is explicit state, not derived from history. That's also why deleting a session doesn't rewind.

Deload weeks and multi-week periodization are follow-ups (see docs/ROADMAP.md).
