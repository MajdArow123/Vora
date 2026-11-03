//
//  SetLabel.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

extension SetType {
    /// Tells set types apart at a glance in a set list.
    var tint: Color {
        switch self {
        case .normal: DesignSystem.Colors.textSecondary
        case .warmUp: DesignSystem.Colors.macroFat
        case .drop: DesignSystem.Colors.macroCarbs
        case .failure: DesignSystem.Colors.negative
        case .myoRep: DesignSystem.Colors.accent
        }
    }
}

/// A set's number or type letter, with a small side badge. The badge overlays
/// the corner, so a set's column stays the same width.
struct SetLabel: View {
    let text: String
    let type: SetType
    var side: SetSide?

    var body: some View {
        Text(text)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(type.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay(alignment: .topTrailing) {
                if let side {
                    Text(side.badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .offset(x: 8, y: -4)
                }
            }
    }

    /// For VoiceOver: "Warm-up", "Set 2, left side".
    static func spokenText(label: String, type: SetType, side: SetSide?) -> String {
        let name = type == .normal ? "Set \(label)" : type.displayName
        return side.map { "\(name), \($0.displayName.lowercased()) side" } ?? name
    }
}
