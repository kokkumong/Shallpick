import SwiftUI

/// 검토 보드의 설정 화면. 닉네임 수정과 로그아웃은 기존 동작을 재사용합니다.
struct AccountSettingsView: View {
    let profile: Profile?
    let onEditNickname: () -> Void
    let onSignOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preferences: NotificationPreferences
    @State private var isConfirmingSignOut = false
    @State private var notice: String?

    init(userID: UUID, profile: Profile?, onEditNickname: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.profile = profile
        self.onEditNickname = onEditNickname
        self.onSignOut = onSignOut
        _preferences = State(initialValue: NotificationPreferences(userID: userID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                avatar

                Button(action: onEditNickname) {
                    HStack {
                        Text(profile?.nickname ?? "샬픽 사용자")
                            .font(.system(size: 18, weight: .medium))
                        Spacer()
                        Image(.settingEdit).resizable().scaledToFit().frame(width: 16.5, height: 16.5)
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 52)
                    .background(Color.black100, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(ShallpickPressStyle())
                .accessibilityLabel("닉네임 수정")

                VStack(alignment: .leading, spacing: 12) {
                    Text("알림")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black600)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(NotificationPreferences.Kind.allCases) { kind in
                            Toggle(isOn: Binding(
                                get: { preferences.isEnabled(kind) },
                                set: { preferences.set($0, for: kind) }
                            )) {
                                HStack(spacing: 12) {
                                    Image(kind.image).resizable().scaledToFit().frame(width: 24, height: 24)
                                    Text(kind.title).font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .tint(Color.black800)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .accessibilityIdentifier("settings.\(kind.rawValue)")
                        }
                    }
                    .background(Color.black50, in: RoundedRectangle(cornerRadius: 20))
                }

                Button { isConfirmingSignOut = true } label: {
                    HStack(spacing: 12) {
                        Image(.settingLogout).resizable().scaledToFit().frame(width: 24, height: 24)
                        Text("로그아웃").font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Color.black50, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(ShallpickPressStyle())

                Button("회원탈퇴") {
                    notice = "회원 탈퇴 기능은 준비 중이에요. 지금은 계정이 삭제되지 않아요."
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.red)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 29)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.black800)
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "설정 닫기") { dismiss() }
                .padding(.leading, 24)
                .padding(.top, 11)
        }
        .confirmationDialog("로그아웃할까요?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive, action: onSignOut)
            Button("취소", role: .cancel) {}
        }
        .alert("안내", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .accessibilityIdentifier("account.settings")
    }

    private var avatar: some View {
        Button { notice = "프로필 사진 변경 기능은 준비 중이에요." } label: {
            AsyncImage(url: profile?.avatarURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(.defaultAvatar).resizable().scaledToFill() }
            }
            .frame(width: 97, height: 97)
            .clipShape(Circle())
            .floatingShadow()
            .overlay(alignment: .bottomTrailing) {
                Image(.settingEdit).resizable().scaledToFit().frame(width: 16.5, height: 16.5)
                    .frame(width: 30, height: 30)
                    .background(Color.black50, in: Circle())
                    .floatingShadow()
            }
        }
        .buttonStyle(ShallpickPressStyle())
        .accessibilityLabel("프로필 사진 수정")
    }
}

private extension NotificationPreferences.Kind {
    var image: ImageResource {
        switch self {
        case .photos: .settingPhoto
        case .comments: .settingComment
        case .reactions: .settingReaction
        case .messages: .settingMessage
        case .requests: .settingRequest
        }
    }
}
