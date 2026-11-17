import SwiftUI

/// 로그인 이후 메인 화면
/// Figma: 메인_그리드_아무것도없을경우 (246:5260), 메인_그리드_폴더버전 (246:5191), 메인_리스트 (246:5246)
struct HomeView: View {
    let userID: UUID
    var onSignOut: () -> Void = {}

    @State private var profile: Profile?
    @State private var isShowingAccountMenu = false
    @State private var folderDialog: FolderDialog?
    @State private var invitingFolder: Folder?
    @State private var joinedFolder: Folder?
    @State private var isShowingQRScanner = false
    /// 폴더 → 채팅 순으로 쌓이는 화면 경로
    @State private var path: [HomeRoute] = []
    @State private var questionAlerts = QuestionAlertCenter()
    @State private var notificationNotice: String?
    /// nil = 아직 불러오는 중
    @State private var folders: [Folder]?

    private enum FolderDialog: Equatable {
        case create
        case join(code: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case let .folder(folder):
                        FolderDetailView(
                            folder: folder,
                            onOpenChat: { path.append(.chat(folder)) }
                        )
                    case let .chat(folder, photos):
                        ChatView(folder: folder, attaching: photos)
                    }
                }
        }
        // 어느 화면에 있든 가운데에 뜨도록 내비게이션 바깥에 둠
        .overlay {
            QuestionAlertOverlay(center: questionAlerts) { alert in
                // 바로 응답하기: 그 폴더 → 채팅으로 바로 이동 (뒤로 가면 폴더 화면)
                path = [.folder(alert.folder), .chat(alert.folder)]
            }
        }
        // 폴더 화면에서 사진을 올리고 돌아오면 표지도 새로
        .onChange(of: path.isEmpty) { _, isBackHome in
            if isBackHome { Task { await reloadCovers() } }
        }
        .task(id: userID) { await listenForQuestions() }
        .task(id: userID) {
            if !DemoStore.shared.isActive { await LocalNotifications.requestAuthorization() }
        }
        // 앱 밖 알림을 눌러 들어오면 그 폴더 채팅으로
        .onChange(of: NotificationRouter.shared.pendingFolderID, initial: true) { _, folderID in
            guard let folderID else { return }
            Task { await openChat(folderID: folderID) }
        }
        .alert(
            "알림",
            isPresented: Binding(get: { notificationNotice != nil }, set: { if !$0 { notificationNotice = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notificationNotice ?? "")
        }
    }

    private var home: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if DemoStore.shared.isActive {
                        HStack {
                            Text("시연 모드 · 샘플 데이터")
                            Spacer()
                            Button("다시 시작") { DemoStore.shared.reset() }
                                .accessibilityIdentifier("demo.reset")
                            Button("종료", action: onSignOut)
                                .accessibilityIdentifier("demo.exit")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black600)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(Color.blue100)
                    }
                    HomeHeader(
                        onNotifications: {
                            if DemoStore.shared.isActive, let alert = DemoStore.shared.sampleQuestion() {
                                questionAlerts.present(alert)
                            } else {
                                notificationNotice = "새로운 질문은 도착하면 화면에 알려드려요."
                            }
                        },
                        onProfile: { isShowingAccountMenu = true }
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeBottomBar(
                    onCreateFolder: { folderDialog = .create },
                    onJoinWithCode: { folderDialog = .join(code: DemoStore.shared.isActive ? "DEMO26" : "") },
                    onJoinWithQR: {
                        if DemoStore.shared.isActive { folderDialog = .join(code: "DEMO26") }
                        else { isShowingQRScanner = true }
                    }
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
                if DemoStore.shared.isActive {
                    Button("샘플 질문 받아보기") {
                        if let alert = DemoStore.shared.sampleQuestion() { questionAlerts.present(alert) }
                    }
                } else {
                    Button("테스트 알림 보내기 (5초 뒤)") { Task { await sendTestNotification() } }
                }
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
                onSelect: { path.append(.folder($0)) },
                onInvite: { invitingFolder = $0 }
            )
            .refreshable { await reloadFolders() }
        }
    }

    /// 다른 멤버가 내 폴더에 보낸 새 메시지를 앱 안 알림으로 띄움.
    /// 지금 그 폴더 채팅을 보고 있으면 띄우지 않습니다.
    private func listenForQuestions() async {
        guard !DemoStore.shared.isActive else { return }
        #if DEBUG
        // 실행 인자 -demoQuestionAlert 로 알림 모양 확인
        if ProcessInfo.processInfo.arguments.contains("-demoQuestionAlert") {
            try? await Task.sleep(for: .seconds(2))
            questionAlerts.present(QuestionAlert(
                id: UUID(),
                folder: folders?.first ?? Folder.previews[0],
                askerNickname: "현서",
                question: "이 사진 인스타 스토리에 올려도 돼?",
                photoURLs: (1...3).compactMap { URL(string: "https://picsum.photos/seed/\($0)/300/400") }
            ))
        }
        #endif
        guard SupabaseManager.client != nil else { return }
        let subscription: ChatRepository.Subscription
        do {
            subscription = try await ChatRepository.subscribe(folderID: nil)
        } catch {
            if !(error is CancellationError) { print("[QuestionAlert] 구독 실패:", error) }
            return
        }

        for await message in subscription.messages {
            guard message.userID != userID, !isViewingChat(of: message.folderID) else { continue }
            if let alert = await makeAlert(for: message), !isViewingChat(of: message.folderID) {
                questionAlerts.present(alert)
            }
        }
        await subscription.close()
    }

    private func openChat(folderID: UUID) async {
        NotificationRouter.shared.pendingFolderID = nil
        if folders?.contains(where: { $0.id == folderID }) != true {
            await reloadFolders()
        }
        guard let folder = folders?.first(where: { $0.id == folderID }) else { return }
        path = [.folder(folder), .chat(folder)]
    }

    /// 계정 메뉴의 테스트 알림. 5초 안에 홈 화면으로 나가면 앱 밖 알림으로 보임
    private func sendTestNotification() async {
        guard await LocalNotifications.requestAuthorization() else {
            notificationNotice = "알림 권한이 꺼져 있어요. 설정 > Shallpick > 알림에서 켜 주세요."
            return
        }
        do {
            try await LocalNotifications.scheduleTest(folder: folders?.first)
            notificationNotice = "5초 뒤에 테스트 알림이 와요. 홈 화면으로 나가서 확인해 보세요."
        } catch {
            notificationNotice = "테스트 알림을 보내지 못했어요: \(error.localizedDescription)"
        }
    }

    private func isViewingChat(of folderID: UUID) -> Bool {
        if case let .chat(folder, _)? = path.last { return folder.id == folderID }
        return false
    }

    private func makeAlert(for message: ChatMessage) async -> QuestionAlert? {
        var folder = folders?.first { $0.id == message.folderID }
        if folder == nil {
            // 방금 참여한 폴더일 수 있음
            await reloadFolders()
            folder = folders?.first { $0.id == message.folderID }
        }
        guard let folder else { return nil }

        async let members = try? ChatRepository.fetchMembers(folderID: folder.id)
        async let photos = try? PhotoRepository.fetch(folderID: folder.id)
        let nickname = await members?.first { $0.userID == message.userID }?.nickname ?? "샬픽 사용자"
        // 질문에 붙은 사진이 있으면 그 사진, 없으면 폴더 최신 사진
        let folderPhotos = await photos ?? []
        let byID = Dictionary(folderPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let attached = message.photoIDs.compactMap { byID[$0] }
        return QuestionAlert(
            id: message.id,
            folder: folder,
            askerNickname: nickname,
            question: message.body,
            photoURLs: Array((attached.isEmpty ? folderPhotos : attached).compactMap(\.url).prefix(3))
        )
    }

    private func reloadFolders() async {
        do {
            var loaded = try await FolderRepository.fetchMine()
            // 표지 사진은 이미 받은 게 있으면 우선 그대로 보여 줌
            let previousCovers = Dictionary(
                (folders ?? []).map { ($0.id, $0.coverPhotoURLs) },
                uniquingKeysWith: { first, _ in first }
            )
            for index in loaded.indices {
                loaded[index].coverPhotoURLs = previousCovers[loaded[index].id] ?? []
            }
            withAnimation(.snappy) { folders = loaded }
            await reloadCovers()
        } catch is CancellationError {
        } catch {
            print("[Folder] 목록 불러오기 실패:", error)
            if folders == nil { folders = [] }
        }
    }

    /// 폴더 카드에 꽂힐 최신 사진들
    private func reloadCovers() async {
        guard let current = folders, !current.isEmpty else { return }
        do {
            let covers = try await PhotoRepository.fetchCovers(folderIDs: current.map(\.id))
            guard var updated = folders else { return }
            for index in updated.indices {
                updated[index].coverPhotoURLs = covers[updated[index].id] ?? []
            }
            guard updated != folders else { return }
            withAnimation(.snappy) { folders = updated }
        } catch is CancellationError {
        } catch {
            print("[Folder] 표지 사진 불러오기 실패:", error)
        }
    }
}

/// 메인 화면에서 쌓이는 화면
enum HomeRoute: Hashable {
    case folder(Folder)
    /// attaching: 폴더 화면의 수달로 고른 사진 (첫 메시지에 붙음)
    case chat(Folder, attaching: [PhotoItem] = [])
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

extension [Folder] {
    /// 폴더 이름 또는 참여자 이름에 검색어가 들어간 폴더만. 검색어가 비면 전부.
    func matching(_ query: String) -> [Folder] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return self }
        return filter { folder in
            folder.name.localizedStandardContains(query)
                || folder.memberNames.contains { $0.localizedStandardContains(query) }
        }
    }
}

/// 검색 결과가 없을 때
struct NoSearchResultView: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(.otterQuestion)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("검색 결과가 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("‘\(query)’ 이(가) 들어간 폴더나 참여자가 없어요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        // 키보드에 가리지 않게 위쪽에 둠
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
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
