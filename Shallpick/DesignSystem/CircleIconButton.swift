import SwiftUI

/// 원형 배경 + 그림자 아이콘 (45pt). Menu 라벨처럼 버튼이 아닌 곳에서도 씁니다.
/// Figma: Component 1 (120:2401 notice, 120:2402 search, 148:11998 close, 148:12732 check),
///        Component 2 (148:12444 add)
struct CircleIcon: View {
    enum Style {
        /// 흰 배경 + 검정 아이콘
        case plain
        /// 검정 배경 + 흰 아이콘 (확인 버튼)
        case filled
    }

    private var foreground: Color {
        style == .plain ? .black800 : .white
    }

    private var background: Color {
        style == .plain ? .white : .black800
    }

    let icon: ImageResource
    var iconSize: CGFloat = 24
    var style: Style = .plain

    var body: some View {
        Image(icon)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(foreground)
            .frame(width: 45, height: 45)
            .background(background, in: Circle())
            .floatingShadow()
    }
}

struct CircleIconButton: View {
    let icon: ImageResource
    var iconSize: CGFloat = 24
    var style: CircleIcon.Style = .plain
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIcon(icon: icon, iconSize: iconSize, style: style)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// Figma: DropShadow (#000000 10%, offset 0, blur 40)
    func shallpickShadow(blur: CGFloat = 40) -> some View {
        shadow(color: .black.opacity(0.1), radius: blur / 2)
    }

    /// 떠 있는 동그라미 버튼용: 퍼지는 그림자에 가까운 그림자를 더해 흰 배경 위에서도 테두리가 보이게
    func floatingShadow() -> some View {
        shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
            .shallpickShadow(blur: 24)
    }
}

#Preview {
    HStack(spacing: 8) {
        CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색") {}
        CircleIconButton(icon: .iconBell, accessibilityLabel: "알림") {}
        CircleIconButton(icon: .iconPlus, accessibilityLabel: "추가") {}
        CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") {}
        CircleIconButton(icon: .iconCheck, style: .filled, accessibilityLabel: "확인") {}
    }
    .padding(40)
    .background(Color.black50)
}
