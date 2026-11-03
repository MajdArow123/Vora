//
//  DemoSeeder.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

#if DEBUG
import Foundation
import OSLog
import SwiftData

/// Fills an empty store with realistic data for App Store screenshots.
/// Debug builds only, and only when launched with the `--seed-demo` argument
/// on a store with no profile. Food and weights are built to a known answer:
/// eating 2,600 kcal a day and losing 0.5 kg a week means an expenditure of
/// about 3,150 kcal.
enum DemoSeeder {
    static let dailyIntakeKcal = 2600.0
    static let weeklyLossKg = 0.5
    /// Food and weights both go back this far.
    static let historyDays = 60
    /// Check-ins already answered, each a week apart, before today's.
    static let pastCheckIns = 4

    static func seedIfRequested(container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-demo") else { return }
        let context = ModelContext(container)
        do {
            guard try context.fetchCount(FetchDescriptor<UserProfile>()) == 0 else { return }
        } catch {
            // Can't tell whether the store has a profile, so leave it alone.
            Logger(subsystem: "com.majdarow.Vora", category: "DemoSeeder")
                .error("Failed to check for a profile: \(String(describing: error), privacy: .public)")
            return
        }
        seed(into: context)
        guard ProcessInfo.processInfo.arguments.contains("--seed-cycle") else { return }
        do {
            try seedCycle(into: context)
        } catch {
            Logger(subsystem: "com.majdarow.Vora", category: "DemoSeeder")
                .error("Failed to seed the training cycle: \(String(describing: error), privacy: .public)")
        }
    }

    /// Switches to cycle mode and links Day 1's first two exercises, so both
    /// show up as soon as the app opens.
    static func seedCycle(into context: ModelContext) throws {
        try TrainingProgramService.setMode(.cycle, context: context)
        guard let first = try TrainingProgramService.today(context: context)?.nextTraining else { return }
        var plan = try WorkoutTemplateService.plan(for: first.slot, context: context)
        let groups = SetCounting.linkingWithNext(plan.map(\.supersetGroup), at: 0)
        for index in plan.indices { plan[index].supersetGroup = groups[index] }
        try WorkoutTemplateService.save(plan, for: first.slot, context: context)
    }

    /// Internal (not private) so tests can check what the seed writes.
    static func seed(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(UserProfile(
            name: "Alex Morgan",
            dateOfBirth: cal.date(byAdding: .year, value: -29, to: today)!,
            heightCm: 181,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .lightlyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2400,
            proteinTargetG: 165,
            carbsTargetG: 260,
            fatTargetG: 70,
            waterTargetMl: 3000,
            goalWeightKg: 78,
            preferredUnits: .metric
        ))

        for (index, template) in TrainingSplit.ppl.weeklyTemplate.enumerated() {
            context.insert(SplitDay(
                dayIndex: index,
                title: template.title,
                muscleGroups: template.muscleGroups,
                isRest: template.isRest
            ))
        }

        seedWeights(into: context, today: today, calendar: cal)
        seedFoodAndWater(into: context, today: today, calendar: cal)
        seedWorkouts(into: context, today: today, calendar: cal)
        seedFoodLibrary(into: context)
        seedSupplements(into: context, today: today, calendar: cal)

        do {
            try context.save()
            try seedCheckIns(into: context, today: today, calendar: cal)
        } catch {
            Logger(subsystem: "com.majdarow.Vora", category: "DemoSeeder")
                .error("Failed to save demo data: \(String(describing: error), privacy: .public)")
        }
    }

    /// Answers past check-ins through the real service, so the chart climbs
    /// from the formula toward the known answer and today's check-in is
    /// still open.
    private static func seedCheckIns(into context: ModelContext, today: Date, calendar: Calendar) throws {
        guard let latest = ExpenditureCheckInService.checkInDay(for: .monday, now: today, calendar: calendar) else { return }
        for weeksAgo in stride(from: pastCheckIns, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: latest) else { continue }
            let state = try ExpenditureCheckInService.state(context: context, weekday: .monday, now: day, calendar: calendar)
            if case .ready(let proposal) = state {
                try ExpenditureCheckInService.apply(proposal, context: context)
            }
        }
    }

    /// Three supplements with three weeks of full logs; today the evening
    /// one is still untaken so the Home checklist reads 2 of 3.
    private static func seedSupplements(into context: ModelContext, today: Date, calendar: Calendar) {
        let createdAt = calendar.date(byAdding: .day, value: -21, to: today)!
        let supplements = [
            Supplement(name: "Creatine", dose: "5g", timing: .morning,
                       reminderEnabled: true, reminderMinutes: 480, orderIndex: 0, createdAt: createdAt),
            Supplement(name: "Vitamin D", dose: "2000IU", timing: .morning,
                       orderIndex: 1, createdAt: createdAt),
            Supplement(name: "Magnesium", dose: "400mg", timing: .evening,
                       orderIndex: 2, createdAt: createdAt),
        ]
        supplements.forEach { context.insert($0) }

        for dayOffset in 0...21 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            for supplement in supplements {
                // Evening supplement not yet taken today.
                if dayOffset == 0 && supplement.timing == .evening { continue }
                context.insert(SupplementLog(
                    supplementID: supplement.id,
                    supplementName: supplement.name,
                    dose: supplement.dose,
                    date: day,
                    takenAt: day.addingTimeInterval(supplement.timing == .evening ? 21 * 3600 : 8 * 3600)
                ))
            }
        }
    }

    /// Custom foods, a saved meal, and a recipe so the food-search tabs
    /// have content to show.
    private static func seedFoodLibrary(into context: ModelContext) {
        context.insert(CustomFood(
            name: "Overnight Oats",
            defaultServingGrams: 250,
            caloriesPer100g: 145,
            proteinPer100g: 6,
            carbsPer100g: 20,
            fatPer100g: 4,
            fibrePer100g: 3,
            sugarPer100g: 7,
            sodiumMgPer100g: 40
        ))
        context.insert(CustomFood(
            name: "Chicken & Rice Bowl",
            defaultServingGrams: 400,
            caloriesPer100g: 132,
            proteinPer100g: 12,
            carbsPer100g: 15,
            fatPer100g: 2.5,
            fibrePer100g: 1,
            sugarPer100g: 1,
            sodiumMgPer100g: 210
        ))

        context.insert(SavedMeal(name: "Typical Breakfast", items: [
            SavedMealItem(foodName: "Overnight Oats", servingGrams: 250, calories: 363,
                          proteinG: 15, carbsG: 50, fatG: 10, orderIndex: 0),
            SavedMealItem(foodName: "Greek Yogurt", servingGrams: 170, calories: 165,
                          proteinG: 15, carbsG: 7, fatG: 8, orderIndex: 1),
            SavedMealItem(foodName: "Banana", servingGrams: 120, calories: 107,
                          proteinG: 1, carbsG: 27, fatG: 0, orderIndex: 2),
        ]))

        context.insert(Recipe(name: "Protein Pancakes", servings: 4, ingredients: [
            RecipeIngredient(foodName: "Rolled Oats", servingGrams: 200, calories: 750,
                             proteinG: 26, carbsG: 135, fatG: 14, orderIndex: 0),
            RecipeIngredient(foodName: "Whey Protein", servingGrams: 60, calories: 240,
                             proteinG: 48, carbsG: 6, fatG: 3, orderIndex: 1),
            RecipeIngredient(foodName: "Eggs", servingGrams: 150, calories: 215,
                             proteinG: 19, carbsG: 1, fatG: 15, orderIndex: 2),
        ]))
    }

    /// Sixty days down to 80.5 kg at `weeklyLossKg`, with mild noise; the
    /// last three days descend strictly so the weight-trend insight fires.
    private static func seedWeights(into context: ModelContext, today: Date, calendar: Calendar) {
        for dayOffset in 0..<historyDays {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let base = 80.5 + Double(dayOffset) * weeklyLossKg / 7
            let wiggle = dayOffset < 3 ? 0 : Double((dayOffset * 7) % 5) * 0.08 - 0.16
            context.insert(WeightEntry(
                date: day.addingTimeInterval(7 * 3600 + 20 * 60),
                weightKg: (base + wiggle).rounded(toPlaces: 2)
            ))
        }
    }

    private static func seedFoodAndWater(into context: ModelContext, today: Date, calendar: Calendar) {
        struct Meal {
            let slot: MealSlot
            let name: String
            let grams: Double
            let kcal: Double
            let p: Double
            let c: Double
            let f: Double
            let hour: Double
        }
        let meals = [
            Meal(slot: .breakfast, name: "Oats with Blueberries & Almond Butter", grams: 320, kcal: 430, p: 18, c: 58, f: 14, hour: 7.5),
            Meal(slot: .lunch, name: "Grilled Chicken & Rice Bowl", grams: 420, kcal: 640, p: 52, c: 68, f: 16, hour: 12.5),
            Meal(slot: .snack, name: "Greek Yogurt with Honey", grams: 200, kcal: 180, p: 17, c: 20, f: 4, hour: 15.5),
            Meal(slot: .dinner, name: "Salmon, Potatoes & Greens", grams: 450, kcal: 590, p: 42, c: 44, f: 24, hour: 19),
        ]

        // The meals scale up to the known daily intake.
        let mealScale = dailyIntakeKcal / meals.reduce(0) { $0 + $1.kcal }

        for dayOffset in 0..<historyDays {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            // Deterministic ±6% day-to-day variation so trend charts have
            // texture. It sums to zero over any 7 days, so the average holds.
            let dayFactor = (1 + Double((dayOffset * 13) % 7 - 3) * 0.02) * mealScale
            for meal in meals {
                context.insert(FoodEntry(
                    date: day.addingTimeInterval(meal.hour * 3600),
                    mealSlot: meal.slot,
                    foodName: meal.name,
                    servingGrams: (meal.grams * mealScale).rounded(),
                    calories: (meal.kcal * dayFactor).rounded(),
                    proteinG: (meal.p * dayFactor).rounded(),
                    carbsG: (meal.c * dayFactor).rounded(),
                    fatG: (meal.f * dayFactor).rounded(),
                    fibreG: 6,
                    sugarG: 9,
                    sodiumMg: 320
                ))
            }
            for glass in 0..<6 {
                context.insert(WaterEntry(
                    date: day.addingTimeInterval(Double(9 + glass * 2) * 3600),
                    amountMl: 250
                ))
            }
        }
    }

    /// Sessions on every scheduled day of the trailing month except 13
    /// days ago, so the streak reads 12 and history looks lived-in.
    /// Today stays untrained so Home shows the Start Session button.
    private static func seedWorkouts(into context: ModelContext, today: Date, calendar: Calendar) {
        let template = TrainingSplit.ppl.weeklyTemplate

        for dayOffset in 1...30 {
            guard dayOffset != 13 else { continue }
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let dayIndex = (calendar.component(.weekday, from: day) + 5) % 7
            let plan = template[dayIndex]
            guard !plan.isRest else { continue }

            let exercises: [(String, Double, [String])]
            switch plan.title {
            case "Push": exercises = [("Barbell Bench Press", 85, ["chest"]), ("Overhead Press", 52.5, ["shoulders"]), ("Incline Dumbbell Press", 30, ["chest"]), ("Cable Fly", 17.5, ["chest"]), ("Triceps Pushdown", 27.5, ["triceps"])]
            case "Pull": exercises = [("Deadlift", 150, ["back"]), ("Pull-Up", 10, ["back"]), ("Barbell Row", 75, ["back"]), ("Face Pull", 20, ["shoulders"]), ("Barbell Curl", 32.5, ["biceps"])]
            default: exercises = [("Back Squat", 120, ["quads"]), ("Romanian Deadlift", 95, ["hamstrings"]), ("Leg Press", 180, ["quads"]), ("Seated Calf Raise", 45, ["calves"]), ("Leg Curl", 40, ["hamstrings"])]
            }

            // Older sessions lift lighter (~2% per week, nearest 2.5 kg)
            // so progression charts show real growth over the month.
            let progressFactor = 1 - 0.02 * Double(dayOffset / 7)
            var totalVolume = 0.0
            let logs = exercises.enumerated().map { index, exercise in
                let progressed = Swift.max((exercise.1 * progressFactor / 2.5).rounded() * 2.5, 2.5)
                var sets = (1...3).map { setNumber in
                    SetEntry(setNumber: setNumber, weightKg: progressed, reps: 8, isCompleted: true)
                }
                totalVolume += progressed * 8 * 3
                // One of each set type per session, so history shows them all.
                switch index {
                case 0:
                    sets.insert(contentsOf: [
                        SetEntry(setNumber: -1, weightKg: progressed * 0.5, reps: 5, isCompleted: true, setType: .warmUp),
                        SetEntry(setNumber: 0, weightKg: progressed * 0.7, reps: 3, isCompleted: true, setType: .warmUp),
                    ], at: 0)
                case 2:
                    sets[0].sideRawValue = SetSide.left.rawValue
                    sets[1].sideRawValue = SetSide.right.rawValue
                case 3:
                    sets[2].setTypeRawValue = SetType.failure.rawValue
                case 4:
                    let dropKg = progressed * 0.7
                    sets.append(SetEntry(setNumber: 4, weightKg: dropKg, reps: 10, isCompleted: true, setType: .drop))
                    totalVolume += dropKg * 10
                default:
                    break
                }
                return ExerciseLog(
                    exerciseName: exercise.0,
                    exerciseId: ExerciseIdentity.libraryID(forName: exercise.0),
                    muscleGroups: exercise.2,
                    orderIndex: index,
                    supersetGroup: index >= 3 ? 1 : nil,
                    sets: sets
                )
            }

            context.insert(WorkoutSession(
                date: day.addingTimeInterval(17.5 * 3600),
                sessionName: plan.title,
                durationSeconds: 3480 + dayOffset * 30,
                totalVolumeKg: totalVolume,
                exercises: logs
            ))
        }

        // Roughly two cardio entries per week across the month so the
        // weekly cardio trend chart has several bars.
        for (index, dayOffset) in [1, 2, 4, 8, 11, 15, 18, 22, 25, 29].enumerated() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
                .addingTimeInterval(8 * 3600)
            let duration = 1500 + (index % 3) * 300

            switch index % 3 {
            case 0:
                context.insert(CardioEntry(
                    date: date,
                    type: .treadmill,
                    durationSeconds: duration,
                    estimatedCalories: CardioCalculator.calories(
                        type: .treadmill,
                        inputs: CardioInputs(speedKmh: 8.5, inclinePercent: 2),
                        weightKg: 75,
                        durationSeconds: duration
                    ),
                    speedKmh: 8.5,
                    inclinePercent: 2,
                    distanceKm: CardioCalculator.distanceKm(speedKmh: 8.5, durationSeconds: duration)
                ))
            case 1:
                context.insert(CardioEntry(
                    date: date,
                    type: .run,
                    durationSeconds: duration,
                    estimatedCalories: CardioCalculator.calories(
                        type: .run,
                        inputs: CardioInputs(speedKmh: 10),
                        weightKg: 75,
                        durationSeconds: duration
                    ),
                    speedKmh: 10,
                    distanceKm: CardioCalculator.distanceKm(speedKmh: 10, durationSeconds: duration),
                    pace: CardioCalculator.pace(fromSpeedKmh: 10)
                ))
            default:
                context.insert(CardioEntry(
                    date: date,
                    type: .stairClimber,
                    durationSeconds: duration,
                    estimatedCalories: CardioCalculator.calories(
                        type: .stairClimber,
                        inputs: CardioInputs(stepsPerMinute: 85),
                        weightKg: 75,
                        durationSeconds: duration
                    ),
                    stepsPerMinute: 85
                ))
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
#endif
