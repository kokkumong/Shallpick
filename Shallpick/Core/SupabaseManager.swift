import Foundation
import Supabase

enum SupabaseManager {
    /// 키가 설정되지 않았으면 nil (Config/Secrets.xcconfig 확인)
    static let client: SupabaseClient? = {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseKey else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}
