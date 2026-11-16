import SwiftUI

/// 흰 원형 배경 + 그림자 아이콘 버튼 (45pt). 메인 화면의 검색/알림/추가 버튼.
/// Figma: Component 1 (120:2401 notice, 120:2402 search), Component 2 (148:12444 add)
struct CircleIconButton: View {
    let icon: ImageResource
    var iconSize: CGFloat = 24
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(Color.black800)
                .frame(width: 45, height: 45)
                .background(.white, in: Circle())
                .shallpickShadow()
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
}

#Preview {
    HStack(spacing: 8) {
        CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색") {}
        CircleIconButton(icon: .iconBell, accessibilityLabel: "알림") {}
        CircleIconButton(icon: .iconPlus, accessibilityLabel: "추가") {}
    }
    .padding(40)
    .background(Color.black50)
}
