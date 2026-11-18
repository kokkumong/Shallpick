import SwiftUI

/// 메인 하단 오른쪽: 알림 버튼 위에 폴더 추가 버튼 (Figma: 메인_수정 570:13364)
struct HomeBottomBar: View {
    /// 알림 내역에 새로 쌓인 게 있으면 알림 버튼 오른쪽 위에 빨간 점
    var hasNewNotifications = false
    var onNotifications: () -> Void = {}
    var onCreateFolder: () -> Void = {}
    var onJoinWithCode: () -> Void = {}
    var onJoinWithQR: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            CircleIconButton(icon: .iconBell, accessibilityLabel: "알림", action: onNotifications)
                .overlay(alignment: .topTrailing) {
                    if hasNewNotifications {
                        NotificationDot()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.25), value: hasNewNotifications)
                .accessibilityValue(hasNewNotifications ? "새 알림 있음" : "")

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
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 33)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black50.opacity(0), location: 0),
                    .init(color: .black50, location: 0.889),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// 새 알림 표시 (인스타그램처럼 작은 빨간 점)
struct NotificationDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 11, height: 11)
            .overlay { Circle().stroke(.white, lineWidth: 2) }
    }
}

#Preview {
    VStack {
        Spacer()
        HomeBottomBar(hasNewNotifications: true)
    }
    .background(Color.black50)
}
