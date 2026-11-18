import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 검토 보드의 설정 화면. 닉네임 수정과 로그아웃은 기존 동작을 재사용합니다.
struct AccountSettingsView: View {
    let profile: Profile?
    let onEditNickname: () -> Void
    let onChangeAvatar: (UIImage) async throws -> Void
    let onResetAvatar: () async throws -> Void
    let onSignOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingFromLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    @State private var isImportingFile = false
    @State private var isUploadingAvatar = false
    @State private var isConfirmingAvatarReset = false
    /// 기본 이미지로 돌리는 중이면 바로 수달을 보여줌
    @State private var isResettingAvatar = false
    /// 올리는 동안 바로 보여줄 새 사진
    @State private var pendingAvatar: UIImage?
    @State private var preferences: NotificationPreferences
    @State private var isConfirmingSignOut = false
    @State private var notice: String?

    init(
        userID: UUID,
        profile: Profile?,
        onEditNickname: @escaping () -> Void,
        onChangeAvatar: @escaping (UIImage) async throws -> Void,
        onResetAvatar: @escaping () async throws -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.profile = profile
        self.onEditNickname = onEditNickname
        self.onChangeAvatar = onChangeAvatar
        self.onResetAvatar = onResetAvatar
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
        .confirmationDialog("프로필 사진을 기본 이미지로 바꿀까요?", isPresented: $isConfirmingAvatarReset, titleVisibility: .visible) {
            Button("기본 이미지로 변경", role: .destructive) { Task { await resetAvatar() } }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("로그아웃할까요?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive, action: onSignOut)
            Button("취소", role: .cancel) {}
        }
        .photosPicker(isPresented: $isPickingFromLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)
                else { notice = ProfileRepository.AvatarError.unreadableImage.errorDescription; return }
                await uploadAvatar(image)
            }
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraCapture { image in Task { await uploadAvatar(image) } }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                notice = ProfileRepository.AvatarError.unreadableImage.errorDescription
                return
            }
            Task { await uploadAvatar(image) }
        }
        .alert("안내", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .accessibilityIdentifier("account.settings")
    }

    /// iOS 기본 사진 첨부 메뉴와 같은 세 가지: 사진 보관함 / 사진 찍기 / 파일 선택
    private var avatar: some View {
        Menu {
            Button("사진 보관함", systemImage: "photo.on.rectangle") { isPickingFromLibrary = true }
            Button("사진 찍기", systemImage: "camera") { isTakingPhoto = true }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Button("파일 선택", systemImage: "folder") { isImportingFile = true }
            if profile?.avatarURL != nil {
                Section {
                    Button("기본 이미지로 변경", systemImage: "person.crop.circle", role: .destructive) {
                        isConfirmingAvatarReset = true
                    }
                }
            }
        } label: {
            avatarImage
                .frame(width: 97, height: 97)
                .clipShape(Circle())
                .overlay {
                    if isUploadingAvatar {
                        Circle().fill(.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                .floatingShadow()
                .overlay(alignment: .bottomTrailing) {
                    Image(.settingEdit).resizable().scaledToFit().frame(width: 16.5, height: 16.5)
                        .frame(width: 30, height: 30)
                        .background(Color.black50, in: Circle())
                        .floatingShadow()
                }
        }
        .buttonStyle(ShallpickPressStyle())
        .disabled(isUploadingAvatar)
        .accessibilityLabel("프로필 사진 수정")
        .accessibilityIdentifier("settings.avatar")
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let pendingAvatar {
            Image(uiImage: pendingAvatar).resizable().scaledToFill()
        } else if isResettingAvatar {
            Image(.defaultAvatar).resizable().scaledToFill()
        } else {
            AsyncImage(url: profile?.avatarURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(.defaultAvatar).resizable().scaledToFill() }
            }
        }
    }

    private func uploadAvatar(_ image: UIImage) async {
        pendingAvatar = image
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            try await onChangeAvatar(image)
            // 성공하면 고른 사진을 그대로 보여줌 (새 주소를 다시 받는 동안 기본 이미지가 깜빡이지 않게)
        } catch {
            pendingAvatar = nil
            notice = "프로필 사진을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func resetAvatar() async {
        pendingAvatar = nil
        isResettingAvatar = true
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            try await onResetAvatar()
        } catch {
            notice = "프로필 사진을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요."
        }
        isResettingAvatar = false
    }
}

/// 카메라로 한 장 찍기 (SwiftUI 에 카메라 화면이 없어 UIKit 것을 씀)
private struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
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
