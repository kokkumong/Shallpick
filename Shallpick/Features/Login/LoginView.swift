import SwiftUI

/// Figma: ui / 로그인_만들어야함 (148:12413)
struct LoginView: View {
    var isLoading = false
    var namespace: Namespace.ID?
    var onKakaoLogin: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Color.black50

                // 캐릭터 + 로고 (화면 중앙에서 64pt 위)
                BrandLockup()
                    .brandLockupGeometry(namespace)
                    .position(x: size.width / 2, y: size.height / 2 - 64.41)

                // 카카오 로그인 버튼 (화면 아래에서 96pt 위)
                if !DemoStore.isAvailable {
                Button(action: onKakaoLogin) {
                    Image(.kakaoLoginButton)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 344, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            if isLoading {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.15))
                                ProgressView()
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel("카카오 로그인")
                .position(x: size.width / 2, y: size.height - 96 - 26)
                } else {
                    VStack(spacing: 14) {
                        Button("로그인 없이 둘러보기") { DemoStore.shared.begin() }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.black800, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("demo.start")
                        Text("시연 모드 · 샘플 사진과 대화로 시작해요")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black600)
                    }
                    .padding(.horizontal, 28)
                    .position(x: size.width / 2, y: size.height - 122)
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LoginView()
}
