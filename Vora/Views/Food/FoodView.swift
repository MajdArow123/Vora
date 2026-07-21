//
//  FoodView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct FoodView: View {
    var body: some View {
        FoodDiaryView()
    }
}

#Preview {
    FoodView()
        .modelContainer(for: [UserProfile.self, FoodEntry.self, WaterEntry.self, CustomFood.self], inMemory: true)
}
