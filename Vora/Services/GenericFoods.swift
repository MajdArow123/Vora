//
//  GenericFoods.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// Picks the OpenFoodFacts result that really is the suggested food. Results
/// come back ranked by popularity, so the first hit for "broccoli" can be a
/// quiche with broccoli in it.
nonisolated enum FoodMatcher {
    /// The share of a product's name the query has to cover. "Broccoli Florets"
    /// passes for "broccoli"; "Tomato, Broccoli & Spinach Quiche" doesn't.
    static let minimumNameCoverage = 0.4
    /// How far stated calories may sit from the macros' 4/4/9 total before the
    /// product's data isn't trusted.
    static let calorieTolerance = 0.4
    static let calorieToleranceFloor = 40.0

    static func bestMatch(for query: String, in items: [FoodItem]) -> FoodItem? {
        let queryWords = Set(words(in: query))
        guard !queryWords.isEmpty else { return nil }

        var best: (item: FoodItem, coverage: Double)?
        for item in items where hasPlausibleCalories(item) {
            let nameWords = Set(words(in: item.name))
            guard queryWords.isSubset(of: nameWords) else { continue }
            let coverage = Double(queryWords.count) / Double(nameWords.count)
            if coverage >= minimumNameCoverage, coverage > (best?.coverage ?? 0) {
                best = (item, coverage)
            }
        }
        return best?.item
    }

    private static func hasPlausibleCalories(_ item: FoodItem) -> Bool {
        let fromMacros = item.proteinPer100g * 4 + item.carbsPer100g * 4 + item.fatPer100g * 9
        let tolerance = max(calorieToleranceFloor, item.caloriesPer100g * calorieTolerance)
        return item.caloriesPer100g > 0 && abs(item.caloriesPer100g - fromMacros) <= tolerance
    }

    /// Lowercased words without a plural "s", so "eggs" finds "egg".
    static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
    }
}

/// Typical nutrition for common foods, used when no OpenFoodFacts match is
/// available. Rough reference values per 100 g as usually eaten (rice, pasta and
/// meat cooked; oats dry), always shown and logged as estimates.
enum GenericFoods {
    struct Macros: Equatable {
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    /// For a food this table doesn't know: an average mixed plate, so an
    /// unknown food can't add hundreds of phantom calories.
    static let unknown = Macros(proteinG: 10, carbsG: 15, fatG: 5)

    /// The longest name found in the food wins, then the earliest listed, so
    /// "sweet potato" isn't a potato and "chicken salad" is chicken.
    private static let table: [(name: String, macros: Macros)] = [
        ("chicken breast", Macros(proteinG: 31, carbsG: 0, fatG: 3.6)),
        ("chicken thigh", Macros(proteinG: 25, carbsG: 0, fatG: 10)),
        ("chicken", Macros(proteinG: 27, carbsG: 0, fatG: 7)),
        ("turkey", Macros(proteinG: 29, carbsG: 0, fatG: 4)),
        ("beef", Macros(proteinG: 26, carbsG: 0, fatG: 15)),
        ("steak", Macros(proteinG: 25, carbsG: 0, fatG: 12)),
        ("pork", Macros(proteinG: 27, carbsG: 0, fatG: 10)),
        ("lamb", Macros(proteinG: 25, carbsG: 0, fatG: 18)),
        ("ham", Macros(proteinG: 20, carbsG: 1, fatG: 5)),
        ("bacon", Macros(proteinG: 37, carbsG: 1, fatG: 42)),
        ("salmon", Macros(proteinG: 25, carbsG: 0, fatG: 13)),
        ("tuna", Macros(proteinG: 28, carbsG: 0, fatG: 1)),
        ("cod", Macros(proteinG: 20, carbsG: 0, fatG: 1)),
        ("shrimp", Macros(proteinG: 24, carbsG: 0, fatG: 0.5)),
        ("prawn", Macros(proteinG: 24, carbsG: 0, fatG: 0.5)),
        ("fish", Macros(proteinG: 22, carbsG: 0, fatG: 5)),
        ("egg white", Macros(proteinG: 11, carbsG: 1, fatG: 0)),
        ("egg", Macros(proteinG: 13, carbsG: 1, fatG: 11)),
        ("tofu", Macros(proteinG: 12, carbsG: 2, fatG: 7)),
        ("tempeh", Macros(proteinG: 19, carbsG: 9, fatG: 11)),
        ("whey", Macros(proteinG: 75, carbsG: 10, fatG: 7)),
        ("protein powder", Macros(proteinG: 75, carbsG: 10, fatG: 7)),
        ("green bean", Macros(proteinG: 1.8, carbsG: 7, fatG: 0.2)),
        ("lentil", Macros(proteinG: 9, carbsG: 20, fatG: 0.4)),
        ("chickpea", Macros(proteinG: 9, carbsG: 27, fatG: 3)),
        ("bean", Macros(proteinG: 9, carbsG: 23, fatG: 0.5)),
        ("hummus", Macros(proteinG: 8, carbsG: 14, fatG: 10)),
        ("rice", Macros(proteinG: 2.7, carbsG: 28, fatG: 0.3)),
        ("pasta", Macros(proteinG: 5.8, carbsG: 31, fatG: 0.9)),
        ("spaghetti", Macros(proteinG: 5.8, carbsG: 31, fatG: 0.9)),
        ("egg noodle", Macros(proteinG: 5, carbsG: 25, fatG: 1)),
        ("noodle", Macros(proteinG: 5, carbsG: 25, fatG: 1)),
        ("quinoa", Macros(proteinG: 4.4, carbsG: 21, fatG: 1.9)),
        ("couscous", Macros(proteinG: 3.8, carbsG: 23, fatG: 0.2)),
        ("oat", Macros(proteinG: 17, carbsG: 66, fatG: 7)),
        ("bread", Macros(proteinG: 9, carbsG: 49, fatG: 3)),
        ("tortilla", Macros(proteinG: 8, carbsG: 50, fatG: 7)),
        ("bagel", Macros(proteinG: 10, carbsG: 53, fatG: 1.5)),
        ("sweet potato", Macros(proteinG: 1.6, carbsG: 20, fatG: 0.1)),
        ("potato", Macros(proteinG: 2, carbsG: 20, fatG: 0.1)),
        ("broccoli", Macros(proteinG: 2.8, carbsG: 7, fatG: 0.4)),
        ("spinach", Macros(proteinG: 2.9, carbsG: 3.6, fatG: 0.4)),
        ("kale", Macros(proteinG: 2.9, carbsG: 4.4, fatG: 1.5)),
        ("lettuce", Macros(proteinG: 1.4, carbsG: 3, fatG: 0.2)),
        ("tomato", Macros(proteinG: 0.9, carbsG: 3.9, fatG: 0.2)),
        ("cucumber", Macros(proteinG: 0.7, carbsG: 3.6, fatG: 0.1)),
        ("pepper", Macros(proteinG: 1, carbsG: 6, fatG: 0.3)),
        ("onion", Macros(proteinG: 1.1, carbsG: 9, fatG: 0.1)),
        ("carrot", Macros(proteinG: 0.9, carbsG: 10, fatG: 0.2)),
        ("mushroom", Macros(proteinG: 3, carbsG: 3, fatG: 0.3)),
        ("zucchini", Macros(proteinG: 1.2, carbsG: 3, fatG: 0.3)),
        ("asparagus", Macros(proteinG: 2.2, carbsG: 3.9, fatG: 0.1)),
        ("salad", Macros(proteinG: 1.5, carbsG: 4, fatG: 0.2)),
        ("vegetable", Macros(proteinG: 2, carbsG: 7, fatG: 0.3)),
        ("avocado", Macros(proteinG: 2, carbsG: 9, fatG: 15)),
        ("banana", Macros(proteinG: 1.1, carbsG: 23, fatG: 0.3)),
        ("apple", Macros(proteinG: 0.3, carbsG: 14, fatG: 0.2)),
        ("strawberry", Macros(proteinG: 0.7, carbsG: 8, fatG: 0.3)),
        ("blueberry", Macros(proteinG: 0.7, carbsG: 14, fatG: 0.3)),
        ("berry", Macros(proteinG: 0.7, carbsG: 12, fatG: 0.3)),
        ("orange", Macros(proteinG: 0.9, carbsG: 12, fatG: 0.1)),
        ("fruit", Macros(proteinG: 0.7, carbsG: 14, fatG: 0.2)),
        ("milk", Macros(proteinG: 3.4, carbsG: 5, fatG: 3.3)),
        ("greek yogurt", Macros(proteinG: 9, carbsG: 4, fatG: 5)),
        ("yogurt", Macros(proteinG: 4, carbsG: 7, fatG: 3)),
        ("cottage cheese", Macros(proteinG: 11, carbsG: 3.4, fatG: 4)),
        ("parmesan", Macros(proteinG: 36, carbsG: 3, fatG: 26)),
        ("cheese", Macros(proteinG: 25, carbsG: 1.3, fatG: 33)),
        ("butter", Macros(proteinG: 0.9, carbsG: 0.1, fatG: 81)),
        ("peanut butter", Macros(proteinG: 25, carbsG: 20, fatG: 50)),
        ("oil", Macros(proteinG: 0, carbsG: 0, fatG: 100)),
        ("almond", Macros(proteinG: 21, carbsG: 22, fatG: 50)),
        ("walnut", Macros(proteinG: 15, carbsG: 14, fatG: 65)),
        ("nut", Macros(proteinG: 20, carbsG: 20, fatG: 50)),
        ("seed", Macros(proteinG: 20, carbsG: 25, fatG: 40)),
        ("honey", Macros(proteinG: 0.3, carbsG: 82, fatG: 0)),
        ("sauce", Macros(proteinG: 2, carbsG: 10, fatG: 3)),
    ]

    /// Table values for these are cooked weights, while a recipe may mean dry,
    /// so their estimates say which was assumed.
    private static let cookedWeightFoods: Set<String> = ["rice", "pasta", "spaghetti", "noodle", "egg noodle"]
    /// A name saying one of these already states its own basis.
    private static let preparationWords: Set<String> = ["cooked", "boiled", "steamed", "dry", "uncooked", "raw"]

    /// Per-100 g macros for a food's name, `unknown` when nothing matches.
    static func macros(for name: String) -> Macros {
        entry(for: name)?.macros ?? unknown
    }

    /// The name to show for an estimate of this food.
    static func estimateName(for name: String) -> String {
        let display = name.capitalized
        guard let entry = entry(for: name),
              cookedWeightFoods.contains(entry.name),
              preparationWords.isDisjoint(with: FoodMatcher.words(in: name))
        else { return display }
        return display + ", cooked"
    }

    private static func entry(for name: String) -> (name: String, macros: Macros)? {
        let words = FoodMatcher.words(in: name)
        var best: (entry: (name: String, macros: Macros), length: Int)?
        for entry in table {
            let entryWords = FoodMatcher.words(in: entry.name)
            let found = words.count >= entryWords.count && (0...(words.count - entryWords.count)).contains {
                Array(words[$0..<($0 + entryWords.count)]) == entryWords
            }
            if found, entryWords.count > (best?.length ?? 0) {
                best = (entry, entryWords.count)
            }
        }
        return best?.entry
    }

    /// Calories derived 4/4/9. Shared by the sheet's display and the logged
    /// draft, so the two can never diverge.
    static func nutrition(for name: String, grams: Double) -> FoodItem.Nutrition {
        let macros = macros(for: name)
        let proteinG = macros.proteinG * grams / 100
        let carbsG = macros.carbsG * grams / 100
        let fatG = macros.fatG * grams / 100
        return FoodItem.Nutrition(
            calories: proteinG * 4 + carbsG * 4 + fatG * 9,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fibreG: 0,
            sugarG: 0,
            sodiumMg: 0
        )
    }
}
