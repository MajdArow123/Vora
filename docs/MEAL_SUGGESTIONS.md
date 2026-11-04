# Meal suggestions

The AI meal suggestion on Home and in the Food sheet. The meal comes from the ProTracker backend (`MealSuggestionService`); everything deciding what to ask for, and what gets logged, is in the app. No schema change: the cache is in UserDefaults.

## Backend token

The backend requires a shared token in `X-App-Token`. It's never committed: copy `Secrets.example.xcconfig` to `Secrets.xcconfig` (gitignored) and fill it in. `Base.xcconfig` includes that file if it exists, and `SupportFiles/Info.plist` carries the value as `MealSuggestionAppToken`. Without a token the app makes no request and says meal suggestions aren't configured.

Anyone with a build can read this token out of it, so it's a stopgap for personal builds. ROADMAP has what's required before TestFlight.

## What a meal asks for

`MealAllocation.remaining`: the meal's target minus what's logged in that slot, and never more than what's left of the day, per macro.

| Slot | Training day | Rest day |
|---|---|---|
| Breakfast, lunch, dinner | 25% | 29.4% |
| Post-workout | 15% | 15%, only if chosen |
| Snack | 10% | 11.8% |

- **A training day** has a session today, or is a training day under calorie cycling. Otherwise the post-workout share goes to the other meals, so following the suggestions still reaches the target.
- **Closing the day:** from 6 pm, dinner and snacks may take up to 40% of the daily target, so the protein tip's gap can actually be filled. The 40% stops a big gap turning into one enormous meal.
- Under 100 kcal left in the slot counts as hit, and within 200 kcal of the daily target as done. Neither calls the backend.

## Which meal

`MealSuggestionContext.mealType`: the first meal not yet logged, in an order that suits the clock. The sheet's menu overrides it.

| Hour | Order |
|---|---|
| Before 10 | Breakfast, post-workout if trained, lunch |
| 10–13 | Post-workout if trained, lunch, snack |
| 13–17 | Lunch, post-workout if trained, snack, dinner |
| 17–21 | Dinner, snack |
| From 21 | Snack |

`hasTrainedToday` doesn't say when, so a morning session with nothing logged as post-workout can still suggest one in the afternoon.

## Cache

One suggestion per meal per day. Each meal shows only its own, another day never shows today's, and logging a meal forgets it so it isn't offered again. A slower older request can't replace a newer one on screen, though its result is still cached for its own meal. A cancelled request restores what was showing.

## Nutrition

Suggestions name foods and grams but no macros, so `MealSuggestionViewModel.enrich` looks each one up in OpenFoodFacts, once more after a second if the search fails, since it often answers 503.

**`FoodMatcher`** picks the result that really is the food, because results are ranked by popularity. The query's words must all be in the name and cover at least 40% of it, so "Broccoli Florets" passes for "broccoli" and a quiche with broccoli in it doesn't. Calories have to roughly match the macros' 4/4/9 total.

**`GenericFoods`** covers the rest: typical values for common foods, as usually eaten, and a modest average for anything unknown. These are rough and not yet checked against a source (see ROADMAP). They're marked "~" in the sheet, and logged with " (estimated)" in the food's name, since `FoodEntry` has no field for it.

## Cooked or dry

Rice, pasta, spaghetti, noodles, quinoa and couscous are about 2.5× apart in calories between cooked and dry, so each one has a state, from `GenericFoods.state`:

1. What its name says ("dry", "dried", "uncooked", "raw"; "cooked", "boiled", "steamed").
2. Otherwise the suggestion's `state` on that food, if the backend sends it.
3. Otherwise cooked.

- **The name shows it**, on estimates and real products alike: "Basmati Rice, cooked", unless the name already says.
- **Estimates use that state's values.**
- **A product must fit the state:** its kcal/100 g must be within 0.67–1.5× of the typical value (`plausibleCalorieRatio`), or it's rejected and the estimate is used. A dry "Rice Basmati" at 351 can't be logged for a cooked weight. Other foods have no such check, since they vary too much for one number.

## Logging

`SuggestedFoodsLogger.log` is all or nothing: a failed save removes what it inserted, and the sheet says nothing was logged. Logging a food from a row's search button removes that row, so Log all can't add it twice.
