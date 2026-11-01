//
//  DataStoreErrorView.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import OSLog
import SwiftUI
import UIKit

/// Shown instead of the app when the data store fails to open. Offers a
/// retry and a raw export of the store files; never deletes anything.
struct DataStoreErrorView: View {
    let details: String
    let onRetry: () -> Void
    var storeURL: URL = PersistenceController.defaultStoreURL

    @State private var export: ExportFile?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.warning.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .accessibilityHidden(true)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("We couldn't open your data")
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Nothing has been deleted. Try again, or export a copy of your data to keep it safe.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: DesignSystem.Spacing.sm) {
                    PrimaryButton(title: "Retry", action: onRetry)
                        .accessibilityHint("Tries to open your data again")
                    GhostButton(title: "Export data", action: makeExport)
                        .accessibilityHint("Creates a copy of your data you can save or share")
                }

                if let exportError {
                    Text(exportError)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .multilineTextAlignment(.center)
                }

                DisclosureGroup("Technical details") {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.sm)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .tint(DesignSystem.Colors.textSecondary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .sheet(item: $export) { file in
            ActivityShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func makeExport() {
        exportError = nil
        do {
            export = ExportFile(url: try StoreExporter.makeArchive(storeURL: storeURL))
        } catch {
            PersistenceController.logger.error(
                "Data export failed: \(String(describing: error), privacy: .public)"
            )
            exportError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't create the export file. Please try again."
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// System share sheet, presented as soon as the export file exists so
/// exporting is a single tap.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    DataStoreErrorView(
        details: "SwiftDataError(_error: SwiftData.SwiftDataError._Error.loadIssueModelContainer)",
        onRetry: {}
    )
}
