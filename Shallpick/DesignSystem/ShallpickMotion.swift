import SwiftUI

/// 기존 버튼 모양은 유지하고, 눌렀을 때만 짧게 반응합니다.
struct ShallpickPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}

/// 사진 셀에서 상세 화면으로 이어지는 시스템 확대 전환.
struct PhotoZoomTransition: ViewModifier {
    let photoID: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content.navigationTransition(.automatic)
        } else {
            content.navigationTransition(.zoom(sourceID: photoID, in: namespace))
        }
    }
}
