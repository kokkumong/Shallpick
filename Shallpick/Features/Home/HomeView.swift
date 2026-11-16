import SwiftUI

/// 로그인 이후 메인 화면
/// Figma: 메인_그리드_아무것도없을경우 (246:5260), 메인_그리드_폴더버전 (246:5191), 메인_리스트 (246:5246)
struct HomeView: View {
    let userID: UUID
    var onSignOut: () -> Void = {}

    @State private var profile: Profile?
    @State private var layout: FolderLayout = .grid
    @State private var isShowingAccountMenu = false
    @State private var folderDialog: FolderDialog?
    @State private var invitingFolder: Folder?
    @State private var joinedFolder: Folder?
    @State private var isShowingQRScanner = false
    @State private var openedFolder: Folder?
    /// nil = 아직 불러오는 중
    @State private var folders: [Folder]?

    private enum FolderDialog: Equatable {
        case create
        case join(code: String)
    }

    var body: some View {
        NavigationStack {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $openedFolder) { folder in
                    FolderDetailView(
                        folder: folder,
                        avatarURL: profile?.avatarURL.flatMap(URL.init(string:))
                    )
                }
        }
    }

    private var home: some View {
        content
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
                    onJoinWithCode: { folderDialog = .join(code: "") },
                    onJoinWithQR: { isShowingQRScanner = true }
                )
            }
            .ignoresSafeArea(.keyboard)
            .overlay { folderDialogView }
            .animation(.snappy(duration: 0.25), value: folderDialog)
            .fullScreenCover(isPresented: $isShowingQRScanner) {
                QRJoinScanner(onCancel: { isShowingQRScanner = false }) { code in
                    // 찾은 코드를 코드 입력창에 채워서 확인받고 참여
                    isShowingQRScanner = false
                    folderDialog = .join(code: code)
                }
            }
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
            .task(id: userID) { await reloadFolders() }
    }

    @ViewBuilder
    private var content: some View {
        switch folders {
        case nil:
            ProgressView()
        case let folders? where folders.isEmpty:
            EmptyFolderView()
        case let folders?:
            FolderCollectionView(
                folders: folders,
                layout: layout,
                onSelect: { openedFolder = $0 },
                onInvite: { invitingFolder = $0 }
            )
            .refreshable { await reloadFolders() }
            .animation(.snappy(duration: 0.3), value: layout)
        }
    }

    private func reloadFolders() async {
        do {
            let loaded = try await FolderRepository.fetchMine()
            withAnimation(.snappy) { folders = loaded }
        } catch is CancellationError {
        } catch {
            print("[Folder] 목록 불러오기 실패:", error)
            if folders == nil { folders = [] }
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
                await reloadFolders()
            }
            .transition(.opacity)
        case let .join(code):
            FolderInputDialog(kind: .join, initialText: code, onCancel: { folderDialog = nil }) { code in
                let folder = try await FolderRepository.join(code: code)
                folderDialog = nil
                joinedFolder = folder
                await reloadFolders()
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
