import Supabase
import SwiftUI

/// 로그인 이후 임시 화면 (메인 화면 디자인이 나오면 교체)
struct HomeView: View {
    let user: User
    var onSignOut: () -> Void = {}

    @State private var profile: Profile?

    var body: some View {
        VStack(spacing: 16) {
            Text("\(profile?.nickname ?? "샬픽 사용자")님, 반가워요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.black800)

            Button("로그아웃", action: onSignOut)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black50)
        .task(id: user.id) {
            profile = try? await ProfileRepository.fetch(userID: user.id)
        }
    }
}
