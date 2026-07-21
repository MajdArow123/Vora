# Vora

**Track. Train. Transform.**

Vora is a premium iOS fitness tracking app that brings nutrition, training, and body progress together in one place. Log meals in seconds with OpenFoodFacts search and barcode scanning, track workouts around your training split, watch your weight trend over time, and let science-based calorie and macro targets — computed from your own stats and goal — guide every day. Built natively with SwiftUI and SwiftData for a fast, offline-first experience.

![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white)
![SwiftData](https://img.shields.io/badge/SwiftData-persistence-4B8BBE)
![HealthKit](https://img.shields.io/badge/HealthKit-integrated-FF2D55?logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17%2B-black?logo=apple&logoColor=white)

## Features

### Nutrition
- Daily food diary with five meal slots (Breakfast, Post-Workout, Lunch, Dinner, Snacks)
- Calorie ring with remaining counter and animated macro progress bars
- Food search powered by OpenFoodFacts with debounced async results
- Barcode scanner (EAN-13/8, UPC-E, Code 128) with manual-entry fallback
- Food detail with full nutrition panel and live macro recalculation at any serving size
- Custom food creator with per-100 g macro control
- Recent foods for under-5-second re-logging
- Water tracking with glass counter and litre progress toward a daily target
- Nutrient breakdown (fibre, sugar, sodium) and one-tap copy of the previous day
- Day-by-day navigation with swipe or arrows

### Workout *(in development)*
- Session logging built around your training split (Upper/Lower, Push Pull Legs, Full Body, Custom)
- Exercise and set tracking: weight, reps, RPE, completion
- Session volume and duration tracking

### Progress *(in development)*
- Weight logging with trend visualization
- Body fat percentage tracking
- Progress insights across nutrition and training

### Profile
- Guided onboarding: units, biological sex, height, weight, goal, activity level, training split
- Science-based calorie and macro suggestions (Mifflin-St Jeor), fully editable
- Inline profile editing with unit-aware inputs (metric / imperial)
- HealthKit integration: weight, active energy, steps, and workouts (fully optional)

## Build Progress

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Foundation — project structure, design system, data models, tab shell | ✅ Complete |
| 1 | Onboarding & Profile | ✅ Complete |
| 2 | Nutrition Module — diary, search, barcode, water | ✅ Complete |
| 3 | Workout Module | 🚧 In progress |
| 4 | Progress & Analytics | 🚧 In progress |
| 5 | Home Dashboard & Polish | 🚧 In progress |

## Screenshots

*Coming soon.*

## Getting Started

### Requirements
- Xcode 16 or later
- iOS 17+ simulator or device

### Run locally
1. Clone the repository:
   ```bash
   git clone https://github.com/MajdArow123/Vora.git
   cd Vora
   ```
2. Open `Vora.xcodeproj` in Xcode.
3. Select the **Vora** scheme and an iOS 17+ simulator (or your device).
4. Build and run (`⌘R`).

No API keys or configuration are required — food search uses the public [OpenFoodFacts](https://world.openfoodfacts.org) API. HealthKit and camera (barcode) permissions are requested in-app and the app is fully functional if declined. Barcode scanning via camera requires a physical device; the simulator falls back to manual barcode entry.
