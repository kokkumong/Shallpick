import SwiftUI

/// 폴더 추가와 참여만 하단에 둡니다. 목록은 리스트로 고정합니다.
struct HomeBottomBar: View {
    var onCreateFolder: () -> Void = {}
    var onJoinWithCode: () -> Void = {}
    var onJoinWithQR: () -> Void = {}

    var body: some View {
        HStack {
            Spacer()
            Menu {
                Button("새 폴더 만들기", systemImage: "folder.badge.plus", action: onCreateFolder)
                Button("코드로 참여하기", systemImage: "number", action: onJoinWithCode)
                Button("QR로 참여하기", systemImage: "qrcode.viewfinder", action: onJoinWithQR)
            } label: {
                CircleIcon(icon: .iconPlus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("폴더 추가")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .background { BottomFade() }
    }
}

#Preview {
    VStack {
        Spacer()
        HomeBottomBar()
    }
    .background(Color.black50)
}
