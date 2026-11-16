import SwiftUI

/// 로그인 이후 메인 화면
/// Figma: ui / 메인_그리드_아무것도없을경우 (246:5260)
struct HomeView: View {
    let userID: UUID
    var onSignOut: () -> Void = {}

    @State private var profile: Profile?
    @State private var layout: FolderLayout = .grid
    @State private var isShowingAccountMenu = false
    @State private var folderDialog: FolderDialog?
    @State private var invitingFolder: Folder?
    @State private var joinedFolder: Folder?

    private enum FolderDialog: Equatable {
        case create
        case join(code: String)
    }

    var body: some View {
        // TODO: 폴더 목록이 생기면 layout(.grid/.list)에 맞게 그리기
        EmptyFolderView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeHeader(
                    avatarURL: profile?.avatarURL.flatMap(URL.init(string:)),
                    onSearch: {},
                    onProfile: { isShowingAccountMenu = true }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeBottomBar(
                    layout: $layout,
                    onNotifications: {},
                    onCreateFolder: { folderDialog = .create },
                    onJoinWithCode: { folderDialog = .join(code: "") }
                )
            }
            .ignoresSafeArea(.keyboard)
            .overlay { folderDialogView }
            .animation(.snappy(duration: 0.25), value: folderDialog)
            .sheet(item: $invitingFolder) { folder in
                FolderInviteSheet(folder: folder)
            }
            .alert(
                "폴더에 참여했어요",
                isPresented: Binding(
                    get: { joinedFolder != nil },
                    set: { if !$0 { joinedFolder = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(joinedFolder?.name ?? "")
            }
            .onOpenURL { url in
                // QR / 초대 링크로 열리면 코드 입력창을 채워서 띄움
                if let code = FolderInviteLink.code(from: url) {
                    invitingFolder = nil
                    folderDialog = .join(code: code)
                }
            }
            .confirmationDialog(
                profile?.nickname ?? "내 계정",
                isPresented: $isShowingAccountMenu,
                titleVisibility: .visible
            ) {
                Button("로그아웃", role: .destructive, action: onSignOut)
            }
            .task(id: userID) {
                profile = try? await ProfileRepository.fetch(userID: userID)
            }
    }
}

private extension HomeView {
    @ViewBuilder
    var folderDialogView: some View {
        switch folderDialog {
        case .create:
            FolderInputDialog(kind: .create, onCancel: { folderDialog = nil }) { name in
                let folder = try await FolderRepository.create(name: name)
                folderDialog = nil
                invitingFolder = folder
            }
            .transition(.opacity)
        case let .join(code):
            FolderInputDialog(kind: .join, initialText: code, onCancel: { folderDialog = nil }) { code in
                let folder = try await FolderRepository.join(code: code)
                folderDialog = nil
                joinedFolder = folder
            }
            .id(code)
            .transition(.opacity)
        case nil:
            EmptyView()
        }
    }
}

/// 폴더가 하나도 없을 때 (246:5263)
struct EmptyFolderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(.otterEmpty)
                .resizable()
                .scaledToFill()
                .frame(width: 167, height: 173.37)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("아직 폴더가 비어있어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("새로운 방을 만들거나 참여하세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    HomeView(userID: UUID())
}
