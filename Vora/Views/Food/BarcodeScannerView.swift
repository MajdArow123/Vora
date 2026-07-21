//
//  BarcodeScannerView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import AVFoundation

/// Barcode scanning sheet: camera preview when available, with a manual
/// entry fallback (also the only path on the simulator, which has no
/// camera).
struct BarcodeScannerView: View {
    let onFound: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var cameraAuthorized: Bool?

    private let client = OpenFoodFactsClient()

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    cameraSection
                    manualEntrySection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
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

    private func lookUp(_ code: String) async {
        guard !isLookingUp else { return }
        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }

        do {
            let item = try await client.product(barcode: code)
            onFound(item)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    BarcodeScannerView { _ in }
}
