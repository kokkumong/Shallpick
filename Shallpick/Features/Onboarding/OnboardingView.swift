import SwiftUI

/// 카카오 로그인 전에 보여주는 온보딩(스플래시) 화면.
/// Figma: ui / 온보딩(일단아주대충함) (134:5528)
struct OnboardingView: View {
    var namespace: Namespace.ID?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Color.black50

                // 캐릭터 + 로고 (화면 정중앙)
                BrandLockup()
                    .brandLockupGeometry(namespace)
                    .position(x: size.width / 2, y: size.height / 2 - 0.41)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    OnboardingView()
}
