import CoreImage
import PhotosUI
import SwiftUI
import Vision
import VisionKit

/// QR로 참여하기: 카메라로 초대 QR 을 찍거나, 사진(캡처)에서 QR 을 불러옵니다.
/// 코드를 찾으면 onFound 로 넘기고, 화면은 호출한 쪽에서 닫습니다.
struct QRJoinScanner: View {
    var onCancel: () -> Void
    var onFound: (String) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var message: String?
    /// 같은 QR 을 여러 번 인식해도 한 번만 처리
    @State private var didFind = false

    private var canUseCamera: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if canUseCamera {
                QRCameraScanner(onScan: handle)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                Spacer()
                guide
                Spacer()
                photoButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 33)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readPhoto(item) }
        }
        .animation(.snappy(duration: 0.2), value: message)
    }

    private var header: some View {
        ZStack {
            Text("QR로 참여하기")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            HStack {
                CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기", action: onCancel)
                Spacer()
            }
        }
        .frame(height: 52)
        .padding(.top, 11)
    }

    private var guide: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 240, height: 240)
                .overlay {
                    if !canUseCamera {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .accessibilityHidden(true)

            Text(message ?? (canUseCamera
                ? "초대 QR 코드를 네모 안에 비춰주세요"
                : "이 기기에서는 카메라로 찍을 수 없어요.\n받은 QR 사진을 불러와 주세요."))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(message == nil ? .white : Color(hex: 0xFF8A80))
                .multilineTextAlignment(.center)
        }
    }

    private var photoButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("사진에서 QR 불러오기", systemImage: "photo")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black800)
                .padding(.horizontal, 28)
                .frame(height: 52)
                .background(.white, in: Capsule())
        }
    }

    private func handle(_ text: String) {
        guard !didFind else { return }
        guard let code = FolderInviteLink.code(fromScanned: text) else {
            message = "Shallpick 초대 QR이 아니에요"
            return
        }
        didFind = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFound(code)
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = CIImage(data: data)
        else {
            message = "사진을 불러오지 못했어요"
            return
        }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let texts = (detector?.features(in: image) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        guard let text = texts.first(where: { FolderInviteLink.code(fromScanned: $0) != nil }) ?? texts.first else {
            message = "사진에서 QR 코드를 찾지 못했어요"
            return
        }
        handle(text)
    }
}

/// VisionKit 카메라 스캐너 (QR 만 인식)
private struct QRCameraScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let text = barcode.payloadStringValue {
                    onScan(text)
                    return
                }
            }
        }
    }
}

#Preview {
    QRJoinScanner(onCancel: {}, onFound: { _ in })
}
