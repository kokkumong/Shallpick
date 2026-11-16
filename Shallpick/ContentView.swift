import SwiftUI

struct ContentView: View {
    @State private var auth = AuthStore()
    @State private var isOnboardingFinished = false
    @Namespace private var brandNamespace

    /// 온보딩 화면을 최소한 보여줄 시간
    private let onboardingMinimumDuration: Duration = .seconds(1.5)

    var body: some View {
        Group {
            if !isOnboardingFinished || auth.state == .loading {
                OnboardingView(namespace: brandNamespace)
            } else {
                switch auth.state {
                case .loading:
                    EmptyView()
                case .signedOut:
                    LoginView(isLoading: auth.isSigningIn, namespace: brandNamespace) {
                        Task { await auth.signInWithKakao() }
                    }
                case let .signedIn(user):
                    HomeView(user: user) {
                        Task { await auth.signOut() }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(duration: 0.6), value: isOnboardingFinished)
        .animation(.spring(duration: 0.6), value: auth.state)
        .task { await auth.observeSession() }
        .task {
            try? await Task.sleep(for: onboardingMinimumDuration)
            isOnboardingFinished = true
        }
        .alert(
            "로그인하지 못했어요",
            isPresented: Binding(
                get: { auth.errorMessage != nil },
                set: { if !$0 { auth.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
}
