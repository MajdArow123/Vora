//
//  BarcodeScannerView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData
import AVFoundation

/// Where a scanned product's data came from — the live database, or a
/// previously saved food matched by barcode while offline.
enum BarcodeLookupSource {
    case online
    case offlineFallback
}

/// Barcode scanning sheet: camera preview when available, with a manual
/// entry fallback (also the only path on the simulator, which has no
/// camera).
struct BarcodeScannerView: View {
    let onFound: (FoodItem, BarcodeLookupSource) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var isLookingUp = false
    @State private var failure: LookupFailure?
    @State private var lastScannedBarcode: String?
    @State private var cameraAuthorized: Bool?
    @FocusState private var manualFieldFocused: Bool

    private enum LookupFailure {
        case network
        case notFound(String)
    }

    private let client = OpenFoodFactsClient()

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    cameraSection
                    manualEntrySection
                    switch failure {
                    case .network:
                        networkErrorCard
                    case .notFound(let message):
                        Text(message)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.negative)
                            .multilineTextAlignment(.center)
                    case nil:
                        EmptyView()
                    }
                    Spacer()
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .task {
            await requestCameraAccess()
        }
    }

    // MARK: - Camera

    @ViewBuilder
    private var cameraSection: some View {
        if cameraAuthorized == true, CameraPreview.isCameraAvailable {
            CameraPreview { code in
                Task { await lookUp(code) }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .strokeBorder(DesignSystem.Colors.accent.opacity(0.4), lineWidth: 2)
            )
            .overlay {
                if isLookingUp {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(.black.opacity(0.45))
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            SwiftUI.ProgressView()
                                .tint(.white)
                            Text("Looking up…")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "camera.fill")
                    .font(.title)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                    .accessibilityHidden(true)
                Text(cameraAuthorized == false ? "Camera access denied" : "Camera unavailable")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Enter the barcode number below instead.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        }
    }

    private func requestCameraAccess() async {
        guard CameraPreview.isCameraAvailable else {
            cameraAuthorized = false
            return
        }
        cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Manual entry

    private var manualEntrySection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TextField("Barcode number", text: $manualCode)
                .keyboardType(.numberPad)
                .focused($manualFieldFocused)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

            Button {
                Task { await lookUp(manualCode) }
            } label: {
                if isLookingUp {
                    SwiftUI.ProgressView()
                        .tint(.white)
                        .frame(width: 80, height: 48)
                } else {
                    Text("Look Up")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 48)
                }
            }
            .background(DesignSystem.Colors.accent.opacity(manualCode.isEmpty ? 0.4 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .disabled(manualCode.isEmpty || isLookingUp)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Errors & offline fallback

    private var networkErrorCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.warning)
                .accessibilityHidden(true)
            Text("Cannot reach food database")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("Check your internet connection and try again, or enter the barcode number manually.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    Task { await lookUp(lastScannedBarcode ?? manualCode) }
                } label: {
                    Text("Retry")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .disabled(isLookingUp)

                Button {
                    if manualCode.isEmpty, let lastScannedBarcode {
                        manualCode = lastScannedBarcode
                    }
                    manualFieldFocused = true
                } label: {
                    Text("Enter manually")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func lookUp(_ code: String) async {
        guard !isLookingUp else { return }
        isLookingUp = true
        failure = nil
        lastScannedBarcode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { isLookingUp = false }

        do {
            let item = try await client.product(barcode: code)
            onFound(item, .online)
        } catch OpenFoodFactsError.productNotFound {
            failure = .notFound(OpenFoodFactsError.productNotFound.localizedDescription)
        } catch OpenFoodFactsError.invalidURL {
            failure = .notFound(OpenFoodFactsError.invalidURL.localizedDescription)
        } catch {
            // Connectivity-shaped failure (offline, timeout, bad response):
            // fall back to foods this barcode was saved under before.
            if let code = lastScannedBarcode, let item = offlineMatch(for: code) {
                onFound(item, .offlineFallback)
            } else {
                failure = .network
            }
        }
    }

    /// A previously saved food carrying this barcode: custom foods first,
    /// then the most recent diary entry logged from a scan of it.
    private func offlineMatch(for code: String) -> FoodItem? {
        var customDescriptor = FetchDescriptor<CustomFood>(
            predicate: #Predicate { $0.barcode == code }
        )
        customDescriptor.fetchLimit = 1
        if let custom = (try? modelContext.fetch(customDescriptor))?.first {
            return FoodItem(customFood: custom)
        }

        var entryDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.barcode == code },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        entryDescriptor.fetchLimit = 1
        guard let entry = (try? modelContext.fetch(entryDescriptor))?.first else { return nil }
        return FoodItem(entry: entry)
    }
}

// MARK: - AVFoundation preview

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        view.onCode = { code in
            DispatchQueue.main.async { onCode(code) }
        }
        view.start()
        return view
    }

    func updateUIView(_ uiView: ScannerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: ScannerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class ScannerUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastCode: String?

    func start() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              code != lastCode
        else { return }
        lastCode = code
        onCode?(code)
    }
}

#Preview {
    BarcodeScannerView { _, _ in }
}
