import CoreImage.CIFilterBuiltins
import SwiftUI

/// 폴더 초대: QR + 폴더 이름 + 초대 버튼
/// Figma: 초대 (246:5294)
struct FolderInviteSheet: View {
    let folder: Folder

    static let height: CGFloat = 300

    var body: some View {
        VStack(spacing: 40) {
            // 드래그 표시 (246:5297)
            Capsule()
                .fill(Color(hex: 0xE6E6E6))
                .frame(width: 30, height: 2)

            FolderInviteContent(folder: folder)
                .padding(.horizontal, 10)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.white)
    }
}

/// 폴더 화면의 사람 초대 버튼: 어두운 배경 위 가운데 카드. 바깥을 누르면 닫힘
struct FolderInvitePopup: View {
    let folder: Folder
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("닫기")
                .transition(.opacity)

            FolderInviteContent(folder: folder)
                .padding(.horizontal, 30)
                .padding(.vertical, 32)
                .frame(maxWidth: 300)
                .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 24))
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// QR + 폴더 이름 + 참여 코드 + 초대하기 (시트와 가운데 카드가 같이 씀)
struct FolderInviteContent: View {
    let folder: Folder

    private var inviteURL: URL { FolderInviteLink.url(code: folder.inviteCode) }

    private var shareMessage: String {
        "Shallpick '\(folder.name)' 폴더에 초대했어요!\n참여 코드: \(folder.inviteCode)\n\(inviteURL.absoluteString)"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                QRCodeView(content: inviteURL.absoluteString)
                    .frame(width: 109, height: 109)
                    .accessibilityLabel("초대 QR 코드")

                VStack(spacing: 4) {
                    Text(folder.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black800)
                        .lineLimit(1)

                    Text("참여 코드 \(folder.inviteCode)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black400)
                        .textSelection(.enabled)
                }
            }

            ShareLink(item: shareMessage) {
                Text("초대하기")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .frame(height: 45)
                    .background(Color.black800, in: Capsule())
            }
        }
    }
}

/// CoreImage 로 만든 QR 코드 (black800)
private struct QRCodeView: View {
    let content: String

    var body: some View {
        if let image = Self.makeImage(content) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle().strokeBorder(Color.black800)
        }
    }

    private static func makeImage(_ content: String) -> CGImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(content.utf8)
        qr.correctionLevel = "M"

        let color = CIFilter.falseColor()
        color.inputImage = qr.outputImage
        color.color0 = CIColor(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
        color.color1 = CIColor.white

        guard let output = color.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

#Preview("가운데 카드") {
    Color.black50
        .overlay {
            FolderInvitePopup(folder: Folder(
                id: UUID(), name: "HCI팀플모임", ownerID: UUID(), inviteCode: "K7QX2M"
            )) {}
        }
}

#Preview("시트") {
    Color.black50
        .sheet(isPresented: .constant(true)) {
            FolderInviteSheet(folder: Folder(
                id: UUID(), name: "HCI팀플모임", ownerID: UUID(), inviteCode: "K7QX2M"
            ))
        }
}
