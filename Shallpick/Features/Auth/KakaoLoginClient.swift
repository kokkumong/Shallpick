import CryptoKit
import Foundation
import UIKit
@preconcurrency import KakaoSDKAuth
@preconcurrency import KakaoSDKCommon
@preconcurrency import KakaoSDKUser

/// 카카오 로그인 결과 중 Supabase 세션 발급에 필요한 값
struct KakaoCredential {
    let idToken: String
    let accessToken: String
    /// 해시하기 전 nonce. 카카오에는 SHA-256 해시를, Supabase 에는 원본을 보냅니다.
    let rawNonce: String
}

enum KakaoLoginError: LocalizedError {
    case missingIDToken
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingIDToken:
            "카카오 ID 토큰을 받지 못했어요. Kakao Developers 에서 OpenID Connect 를 활성화해 주세요."
        case .emptyResponse:
            "카카오 로그인 응답이 비어 있어요."
        }
    }
}

enum KakaoLoginClient {
    /// 카카오톡 앱이 있으면 카카오톡으로, 없으면 카카오계정(웹)으로 로그인합니다.
    static func login() async throws -> KakaoCredential {
        let rawNonce = randomNonce()
        let hashedNonce = sha256(rawNonce)

        let loginWithAccount = {
            try await authorize { completion in
                UserApi.shared.loginWithKakaoAccount(
                    prompts: nil, loginHint: nil, nonce: hashedNonce, completion: completion
                )
            }
        }

        let token: OAuthTokenValues
        if isKakaoTalkInstalled() {
            do {
                token = try await authorize { completion in
                    UserApi.shared.loginWithKakaoTalk(nonce: hashedNonce, completion: completion)
                }
            } catch where isTalkLaunchFailure(error) {
                // 카카오톡이 깔려 있어도 여는 데 실패하는 경우가 있어서(실기기에서 확인됨) 웹 로그인으로 이어감
                print("[Kakao] 카카오톡을 열지 못해 카카오계정 로그인으로 바꿈:", error)
                token = try await loginWithAccount()
            }
        } else {
            token = try await loginWithAccount()
        }

        let (idToken, accessToken) = token
        guard let idToken else { throw KakaoLoginError.missingIDToken }
        return KakaoCredential(idToken: idToken, accessToken: accessToken, rawNonce: rawNonce)
    }

    /// SDK 는 "loginWithKakaoTalk 호출 후 에러 처리"를 권장하지만(isKakaoTalkLoginAvailable deprecated),
    /// 카카오톡 미설치 시 Universal Link 가 에러 대신 Safari 설치 안내 페이지로 열려 버립니다.
    /// 그래서 SDK 내부와 같은 방식(LSApplicationQueriesSchemes 의 kakaokompassauth)으로 직접 확인합니다.
    private static func isKakaoTalkInstalled() -> Bool {
        UIApplication.shared.canOpenURL(URL(string: "kakaokompassauth://authorize")!)
    }

    /// 카카오톡 앱을 띄우지 못했다는 SDK 에러 (유니버설 링크·커스텀 스킴 둘 다 실패)
    private static func isTalkLaunchFailure(_ error: Error) -> Bool {
        if case .ClientFailed(reason: .NotSupported, _) = error as? SdkError { return true }
        return false
    }

    private typealias OAuthTokenValues = (idToken: String?, accessToken: String)

    private static func authorize(
        _ start: (@escaping (OAuthToken?, Error?) -> Void) -> Void
    ) async throws -> OAuthTokenValues {
        try await withCheckedThrowingContinuation { continuation in
            start { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: (token.idToken, token.accessToken))
                } else {
                    continuation.resume(throwing: KakaoLoginError.emptyResponse)
                }
            }
        }
    }

    /// 카카오 토큰 삭제 (실패해도 앱 로그아웃은 진행)
    static func logout() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UserApi.shared.logout { _ in continuation.resume() }
        }
    }

    /// 사용자가 로그인 화면을 닫은 경우 — 에러로 보여주지 않습니다.
    static func isCancellation(_ error: Error) -> Bool {
        guard let sdkError = error as? SdkError else { return false }
        switch sdkError {
        case .ClientFailed(reason: .Cancelled, _):
            return true
        case .AuthFailed(reason: .AccessDenied, _):
            return true
        default:
            return false
        }
    }

    /// 카카오 SDK 에러를 원인 코드가 보이는 문장으로 바꿉니다. (기본 문구는 "SdkError 오류 2" 뿐이라서)
    static func message(for error: Error) -> String? {
        guard let sdkError = error as? SdkError else { return nil }
        switch sdkError {
        case let .AuthFailed(reason, info):
            return "카카오 인증 실패 [\(info?.error.rawValue ?? reason.rawValue)] \(info?.errorDescription ?? "")"
        case let .ApiFailed(reason, info):
            return "카카오 API 실패 [\(reason.rawValue)] \(info?.msg ?? "")"
        case let .ClientFailed(reason, message):
            return "카카오 SDK 오류 [\(reason)] \(message ?? "")"
        case let .AppsFailed(reason, _):
            return "카카오 오류 [\(reason)]"
        }
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

