import Foundation

/// Config/Secrets.xcconfig → Config/Info.plist 로 주입된 값
enum AppConfig {
    static var kakaoNativeAppKey: String? { value(for: "KAKAO_NATIVE_APP_KEY") }
    static var supabaseKey: String? { value(for: "SUPABASE_KEY") }
    static var supabaseURL: URL? { value(for: "SUPABASE_URL").flatMap(URL.init(string:)) }

    static var isConfigured: Bool {
        kakaoNativeAppKey != nil && supabaseKey != nil && supabaseURL != nil
    }

    private static func value(for key: String) -> String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            case let value = raw.trimmingCharacters(in: .whitespaces),
            !value.isEmpty,
            !value.contains("your"),  // Secrets.example.xcconfig 의 플레이스홀더
            !value.contains("$(")
        else { return nil }
        return value
    }
}
