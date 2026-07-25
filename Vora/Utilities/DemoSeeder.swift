//
//  DemoSeeder.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

#if DEBUG
import Foundation
import SwiftData

/// Fills an empty store with a realistic month of data for App Store
/// screenshots. Debug builds only, and only when launched with the
/// `--seed-demo` argument on a store with no profile.
enum DemoSeeder {
    static func seedIfRequested(container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-demo") else { return }
        let context = ModelContext(container)
        let existing = (try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0
        guard existing == 0 else { return }
        seed(into: context)
    }

    private static func seed(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(UserProfile(
            name: "Alex Morgan",
            dateOfBirth: cal.date(byAdding: .year, value: -29, to: today)!,
            heightCm: 181,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .veryActive,
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

        try? context.save()
    }

    /// 90 days trending 84 → ~80.5 kg with mild noise; the last three
    /// days descend strictly so the weight-trend insight fires.
    private static func seedWeights(into context: ModelContext, today: Date, calendar: Calendar) {
        for dayOffset in 0..<90 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let base = 80.5 + Double(dayOffset) * 0.04
            let wiggle = dayOffset < 3 ? 0 : Double((dayOffset * 7) % 5) * 0.08 - 0.16
            context.insert(WeightEntry(
                date: day.addingTimeInterval(7 * 3600 + 20 * 60),
                weightKg: (base + wiggle).rounded(toPlaces: 1)
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

        for dayOffset in 0..<30 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            for meal in meals {
                context.insert(FoodEntry(
                    date: day.addingTimeInterval(meal.hour * 3600),
                    mealSlot: meal.slot,
                    foodName: meal.name,
                    servingGrams: meal.grams,
                    calories: meal.kcal,
                    proteinG: meal.p,
                    carbsG: meal.c,
                    fatG: meal.f,
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
            case "Push": exercises = [("Bench Press", 85, ["chest"]), ("Overhead Press", 52.5, ["shoulders"]), ("Incline Dumbbell Press", 30, ["chest"]), ("Cable Fly", 17.5, ["chest"]), ("Triceps Pushdown", 27.5, ["triceps"])]
            case "Pull": exercises = [("Deadlift", 150, ["back"]), ("Pull-Up", 10, ["back"]), ("Barbell Row", 75, ["back"]), ("Face Pull", 20, ["shoulders"]), ("Barbell Curl", 32.5, ["biceps"])]
            default: exercises = [("Back Squat", 120, ["quads"]), ("Romanian Deadlift", 95, ["hamstrings"]), ("Leg Press", 180, ["quads"]), ("Seated Calf Raise", 45, ["calves"]), ("Leg Curl", 40, ["hamstrings"])]
            }

            var totalVolume = 0.0
            let logs = exercises.enumerated().map { index, exercise in
                let sets = (1...3).map { setNumber in
                    SetEntry(setNumber: setNumber, weightKg: exercise.1, reps: 8, isCompleted: true)
                }
                totalVolume += exercise.1 * 8 * 3
                return ExerciseLog(
                    exerciseName: exercise.0,
                    muscleGroups: exercise.2,
                    orderIndex: index,
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

        context.insert(CardioEntry(
            date: calendar.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(8 * 3600),
            type: .treadmill,
            durationSeconds: 1800,
            estimatedCalories: CardioCalculator.calories(
                type: .treadmill,
                inputs: CardioInputs(speedKmh: 8.5, inclinePercent: 2),
                weightKg: 75,
                durationSeconds: 1800
            ),
            speedKmh: 8.5,
            inclinePercent: 2,
            distanceKm: CardioCalculator.distanceKm(speedKmh: 8.5, durationSeconds: 1800)
        ))
        context.insert(CardioEntry(
            date: calendar.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(8 * 3600),
            type: .run,
            durationSeconds: 1860,
            estimatedCalories: CardioCalculator.calories(
                type: .run,
                inputs: CardioInputs(speedKmh: 10),
                weightKg: 75,
                durationSeconds: 1860
            ),
            speedKmh: 10,
            distanceKm: CardioCalculator.distanceKm(speedKmh: 10, durationSeconds: 1860),
            pace: CardioCalculator.pace(fromSpeedKmh: 10)
        ))
        context.insert(CardioEntry(
            date: calendar.date(byAdding: .day, value: -4, to: today)!.addingTimeInterval(9 * 3600),
            type: .stairClimber,
            durationSeconds: 1200,
            estimatedCalories: CardioCalculator.calories(
                type: .stairClimber,
                inputs: CardioInputs(stepsPerMinute: 85),
                weightKg: 75,
                durationSeconds: 1200
            ),
            stepsPerMinute: 85
        ))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
#endif
