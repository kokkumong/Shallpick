import Foundation
import Supabase

/// 카카오 id_token 으로 Supabase 세션을 발급받습니다.
///
/// supabase-swift 2.55.x 의 `OpenIDConnectCredentials.Provider` 에는 아직 `.kakao` 가 없어서
/// (서버는 지원) Auth REST 엔드포인트를 직접 호출한 뒤 `setSession` 으로 세션을 넣습니다.
/// TODO: SDK 에 `.kakao` 가 릴리스되면 `client.auth.signInWithIdToken(credentials:)` 로 교체
enum SupabaseKakaoSignIn {
    enum SignInError: LocalizedError {
        case server(status: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case let .server(status, message):
                "Supabase 로그인 실패 (\(status)): \(message ?? "알 수 없는 오류")"
            }
        }
    }

    static func signIn(
        with credential: KakaoCredential,
        client: SupabaseClient,
        supabaseURL: URL,
        supabaseKey: String
    ) async throws {
        var components = URLComponents(
            url: supabaseURL.appending(path: "auth/v1/token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                provider: "kakao",
                idToken: credential.idToken,
                accessToken: credential.accessToken,
                nonce: credential.rawNonce
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw SignInError.server(status: status, message: body?.message)
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        _ = try await client.auth.setSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
    }
}

private nonisolated struct RequestBody: Encodable {
    let provider: String
    let idToken: String
    let accessToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case accessToken = "access_token"
        case nonce
    }
}

private nonisolated struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private nonisolated struct ErrorBody: Decodable {
    let msg: String?
    let errorDescription: String?
    let message_: String?

    var message: String? { errorDescription ?? msg ?? message_ }

    enum CodingKeys: String, CodingKey {
        case msg
        case errorDescription = "error_description"
        case message_ = "message"
    }
}
