//
//  SwipeToRemoveRow.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-28.
//

import SwiftUI

/// Swipe-to-remove for rows living inside a ScrollView card, where List's
/// .swipeActions isn't available. Dragging left reveals a trash button;
/// the drag only engages when clearly horizontal so vertical scrolling
/// through the card stays untouched.
struct SwipeToRemoveRow<Content: View>: View {
    /// VoiceOver can't discover the swipe, so the remove action is also
    /// exposed as a named accessibility action with this label.
    let removeLabel: String
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false

    private static var revealWidth: CGFloat { 72 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onRemove()
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: Self.revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(DesignSystem.Colors.negative)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
            .buttonStyle(.plain)
            .opacity(offsetX < -1 ? 1 : 0)
            .accessibilityHidden(true)

            content()
                .background(DesignSystem.Colors.card)
                .offset(x: offsetX)
                .gesture(drag)
                .onTapGesture {
                    guard isOpen else { return }
                    setOpen(false)
                }
        }
        .clipped()
        .accessibilityAction(named: removeLabel, onRemove)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isOpen ? -Self.revealWidth : 0
                let proposed = base + value.translation.width
                // Only leftward reveal; rubber-band past the trash width.
                offsetX = min(0, max(proposed, -Self.revealWidth * 1.3))
            }
            .onEnded { _ in
                setOpen(offsetX < -Self.revealWidth * 0.6)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            isOpen = open
            offsetX = open ? -Self.revealWidth : 0
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        SwipeToRemoveRow(removeLabel: "Remove chicken breast", onRemove: {}) {
            HStack {
                Text("Chicken breast")
                Spacer()
                Text("180g")
            }
            .padding()
        }
    }
    .padding()
    .background(DesignSystem.Colors.card)
}
