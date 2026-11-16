import Foundation
import Observation
import Supabase

/// 앱 전체 로그인 상태. Supabase 세션 변화를 구독합니다.
@Observable
final class AuthStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    private(set) var isSigningIn = false
    var errorMessage: String?

    /// 세션 변화를 계속 구독합니다. 뷰의 `.task` 에서 호출하세요.
    func observeSession() async {
        guard let client = SupabaseManager.client else {
            state = .signedOut
            return
        }
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                state = session.map { .signedIn($0.user) } ?? .signedOut
            case .signedOut, .userDeleted:
                state = .signedOut
            default:
                break
            }
        }
    }

    func signInWithKakao() async {
        guard !isSigningIn else { return }
        guard
            AppConfig.kakaoNativeAppKey != nil,
            let client = SupabaseManager.client,
            let url = AppConfig.supabaseURL,
            let key = AppConfig.supabaseKey
        else {
            errorMessage = "앱 키가 설정되지 않았어요. Config/Secrets.xcconfig 를 확인해 주세요."
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let credential = try await KakaoLoginClient.login()
            try await SupabaseKakaoSignIn.signIn(
                with: credential, client: client, supabaseURL: url, supabaseKey: key
            )
        } catch where KakaoLoginClient.isCancellation(error) {
            // 사용자가 취소함
        } catch {
            errorMessage = KakaoLoginClient.message(for: error) ?? error.localizedDescription
        }
    }

    func signOut() async {
        try? await SupabaseManager.client?.auth.signOut()
        await KakaoLoginClient.logout()
    }
}
