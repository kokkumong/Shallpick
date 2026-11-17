import SwiftUI

/// 로고와 우측 알림, 계정 설정. Figma 댓글: 487:4030.
struct HomeHeader: View {
    var onNotifications: () -> Void = {}
    var onProfile: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(.shallpickLogo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.black800)
                .frame(width: 125, height: 28.84)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Shallpick")
                .accessibilityAddTraits(.isHeader)

            CircleIconButton(icon: .iconBell, accessibilityLabel: "알림", action: onNotifications)
                .accessibilityIdentifier("home.notifications")

            Button(action: onProfile) {
                CircleIcon(systemName: "gearshape", iconSize: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
            .accessibilityHint("계정 메뉴를 열어요")
            .accessibilityIdentifier("home.settings")
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background { TopFade() }
    }
}

#Preview {
    VStack {
        HomeHeader()
        Spacer()
    }
    .background(Color.black50)
}
