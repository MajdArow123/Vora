//
//  BodyDiagramView.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import SwiftUI

/// Region geometry for the stylized front/back body figures. All
/// coordinates live in a fixed 100×220 design space; `RegionShape`
/// scales them to the rendered rect. Bilateral regions are authored
/// once for the right side and mirrored across the x = 50 axis so the
/// figures stay symmetric.
enum BodyDiagramLayout {
    static let designSize = CGSize(width: 100, height: 220)

    enum FigureSide {
        case front, back
    }

    enum RegionGeometry {
        case polygon([CGPoint])
        case ellipse(CGRect)
        case roundedRect(CGRect, CGFloat)
    }

    /// One closed area of a figure. `muscle == nil` marks silhouette
    /// filler (head, neck, hands, feet, pelvis) that is never
    /// highlighted.
    struct Region {
        let muscle: Muscle?
        let geometry: RegionGeometry
    }

    static func regions(for side: FigureSide) -> [Region] {
        switch side {
        case .front: frontRegions
        case .back: backRegions
        }
    }

    /// Muscles that have at least one region on some figure.
    static var mappedMuscles: Set<Muscle> {
        Set((frontRegions + backRegions).compactMap(\.muscle))
    }

    // MARK: - Front figure

    static let frontRegions: [Region] = {
        var regions = silhouette
        regions += mirroredPair(.frontDelts, right: [
            (63, 31), (75, 32), (78, 40), (70, 45), (63, 42),
        ])
        regions += mirroredPair(.sideDelts, right: [
            (76, 33), (84, 38), (85, 48), (79, 46), (79, 41),
        ])
        regions += mirroredPair(.chest, right: [
            (51, 33), (62, 33), (69, 46), (65, 52), (51, 53),
        ])
        regions += mirroredPair(.biceps, right: [
            (76, 50), (85, 51), (86, 73), (78, 75), (74, 62),
        ])
        regions += mirroredPair(.forearms, right: [
            (78, 78), (86, 76), (90, 98), (84, 100),
        ])
        regions.append(centered(.abs, points: [
            (43, 57), (57, 57), (56, 97), (44, 97),
        ]))
        regions += mirroredPair(.obliques, right: [
            (59, 57), (67, 55), (64, 92), (58, 95),
        ])
        regions += mirroredPair(.quads, right: [
            (52, 101), (66, 99), (69, 124), (66, 148), (56, 150), (52, 120),
        ])
        regions += mirroredPair(.calves, right: [
            (55, 160), (66, 158), (67, 178), (63, 196), (57, 196), (54, 175),
        ])
        return regions
    }()

    // MARK: - Back figure

    static let backRegions: [Region] = {
        var regions = silhouette
        regions.append(centered(.traps, points: [
            (44, 23), (56, 23), (79, 34), (76, 40), (50, 35), (24, 40), (21, 34),
        ]))
        regions += mirroredPair(.rearDelts, right: [
            (74, 34), (84, 39), (85, 49), (77, 47), (73, 41),
        ])
        regions.append(centered(.upperBack, points: [
            (37, 42), (63, 42), (60, 56), (40, 56),
        ]))
        regions += mirroredPair(.lats, right: [
            (60, 52), (72, 48), (66, 78), (57, 92),
        ])
        regions.append(centered(.lowerBack, points: [
            (44, 74), (56, 74), (57, 98), (43, 98),
        ]))
        regions += mirroredPair(.triceps, right: [
            (76, 50), (85, 51), (86, 73), (78, 75), (74, 62),
        ])
        regions += mirroredPair(nil, right: [
            (78, 78), (86, 76), (90, 98), (84, 100),
        ])
        regions += mirroredPair(.glutes, right: [
            (51, 101), (67, 101), (69, 113), (66, 127), (52, 129),
        ])
        regions += mirroredPair(.hamstrings, right: [
            (53, 133), (67, 131), (68, 158), (55, 160),
        ])
        regions += mirroredPair(.calves, right: [
            (55, 164), (66, 162), (67, 182), (62, 198), (57, 198), (54, 178),
        ])
        return regions
    }()

    // MARK: - Shared silhouette (never highlighted)

    /// Head, neck, hands, pelvis, and feet shared by both figures.
    private static let silhouette: [Region] = {
        var regions: [Region] = [
            Region(muscle: nil, geometry: .ellipse(CGRect(x: 41, y: 2, width: 18, height: 20))),
            Region(muscle: nil, geometry: .roundedRect(CGRect(x: 45, y: 22, width: 10, height: 8), 2)),
            centered(nil, points: [(42, 99), (58, 99), (60, 110), (50, 116), (40, 110)]),
        ]
        regions += mirroredPair(
            nil,
            geometry: { .ellipse(CGRect(x: $0, y: 102, width: 8, height: 12)) },
            rightX: 85
        )
        regions += mirroredPair(
            nil,
            geometry: { .roundedRect(CGRect(x: $0, y: 199, width: 13, height: 8), 3) },
            rightX: 55
        )
        return regions
    }()

    // MARK: - Mirroring helpers

    private static func centered(_ muscle: Muscle?, points: [(CGFloat, CGFloat)]) -> Region {
        Region(muscle: muscle, geometry: .polygon(points.map { CGPoint(x: $0.0, y: $0.1) }))
    }

    /// Builds the right-side region plus its mirror across the center
    /// axis, so both sides always match.
    private static func mirroredPair(_ muscle: Muscle?, right: [(CGFloat, CGFloat)]) -> [Region] {
        let rightPoints = right.map { CGPoint(x: $0.0, y: $0.1) }
        let leftPoints = rightPoints.map { CGPoint(x: designSize.width - $0.x, y: $0.y) }
        return [
            Region(muscle: muscle, geometry: .polygon(rightPoints)),
            Region(muscle: muscle, geometry: .polygon(leftPoints)),
        ]
    }

    /// Mirrored pair for rect-based geometry: the closure builds the
    /// right-side shape from its minX; the left side reuses it at the
    /// mirrored origin.
    private static func mirroredPair(
        _ muscle: Muscle?,
        geometry: (CGFloat) -> RegionGeometry,
        rightX: CGFloat
    ) -> [Region] {
        let right = geometry(rightX)
        let width: CGFloat = switch right {
        case .ellipse(let rect), .roundedRect(let rect, _): rect.width
        case .polygon: 0
        }
        return [
            Region(muscle: muscle, geometry: right),
            Region(muscle: muscle, geometry: geometry(designSize.width - rightX - width)),
        ]
    }
}

/// Scales one region from the 100×220 design space into the view rect.
private struct RegionShape: Shape {
    let geometry: BodyDiagramLayout.RegionGeometry

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / BodyDiagramLayout.designSize.width
        let scaleY = rect.height / BodyDiagramLayout.designSize.height
        var path = Path()
        switch geometry {
        case .polygon(let points):
            guard let first = points.first else { return path }
            path.move(to: scaled(first, rect: rect, sx: scaleX, sy: scaleY))
            for point in points.dropFirst() {
                path.addLine(to: scaled(point, rect: rect, sx: scaleX, sy: scaleY))
            }
            path.closeSubpath()
        case .ellipse(let designRect):
            path.addEllipse(in: scaled(designRect, rect: rect, sx: scaleX, sy: scaleY))
        case .roundedRect(let designRect, let radius):
            path.addRoundedRect(
                in: scaled(designRect, rect: rect, sx: scaleX, sy: scaleY),
                cornerSize: CGSize(width: radius * scaleX, height: radius * scaleY)
            )
        }
        return path
    }

    private func scaled(_ point: CGPoint, rect: CGRect, sx: CGFloat, sy: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + point.x * sx, y: rect.minY + point.y * sy)
    }

    private func scaled(_ designRect: CGRect, rect: CGRect, sx: CGFloat, sy: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + designRect.minX * sx,
            y: rect.minY + designRect.minY * sy,
            width: designRect.width * sx,
            height: designRect.height * sy
        )
    }
}

/// One stylized figure (front or back) with the given muscles
/// highlighted.
private struct BodyFigureView: View {
    let side: BodyDiagramLayout.FigureSide
    let primaryMuscles: Set<Muscle>
    let secondaryMuscles: Set<Muscle>

    var body: some View {
        ZStack {
            ForEach(Array(BodyDiagramLayout.regions(for: side).enumerated()), id: \.offset) { _, region in
                RegionShape(geometry: region.geometry)
                    .fill(fill(for: region.muscle))
            }
        }
        .aspectRatio(
            BodyDiagramLayout.designSize.width / BodyDiagramLayout.designSize.height,
            contentMode: .fit
        )
    }

    private func fill(for muscle: Muscle?) -> Color {
        guard let muscle else {
            return DesignSystem.Colors.textSecondary.opacity(0.15)
        }
        if primaryMuscles.contains(muscle) {
            return DesignSystem.Colors.accent
        }
        if secondaryMuscles.contains(muscle) {
            return DesignSystem.Colors.accent.opacity(0.35)
        }
        return DesignSystem.Colors.textSecondary.opacity(0.15)
    }
}

/// Front and back body figures side by side with primary muscles in the
/// brand accent and secondary muscles at reduced opacity. Pass empty
/// sets for a neutral (unhighlighted) diagram.
struct BodyDiagramView: View {
    let primaryMuscles: Set<Muscle>
    let secondaryMuscles: Set<Muscle>

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xl) {
            figure(.front, label: "Front")
            figure(.back, label: "Back")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func figure(_ side: BodyDiagramLayout.FigureSide, label: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            BodyFigureView(
                side: side,
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles
            )
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var accessibilityText: String {
        guard !primaryMuscles.isEmpty || !secondaryMuscles.isEmpty else {
            return "Body diagram with no muscles highlighted"
        }
        var parts: [String] = []
        if !primaryMuscles.isEmpty {
            parts.append("Primary: " + names(of: primaryMuscles))
        }
        if !secondaryMuscles.isEmpty {
            parts.append("Secondary: " + names(of: secondaryMuscles))
        }
        return "Body diagram. " + parts.joined(separator: ". ")
    }

    private func names(of muscles: Set<Muscle>) -> String {
        muscles.map(\.displayName).sorted().joined(separator: ", ")
    }
}

#Preview("Bench Press") {
    BodyDiagramView(
        primaryMuscles: [.chest],
        secondaryMuscles: [.frontDelts, .triceps]
    )
    .padding()
    .background(DesignSystem.Colors.card)
}

#Preview("Deadlift") {
    BodyDiagramView(
        primaryMuscles: [.glutes, .hamstrings, .lowerBack],
        secondaryMuscles: [.quads, .lats, .traps, .forearms]
    )
    .padding()
    .background(DesignSystem.Colors.card)
}
