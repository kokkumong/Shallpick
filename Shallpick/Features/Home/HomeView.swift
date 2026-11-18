import SwiftUI

/// 로그인 이후 메인 화면
/// Figma: 메인_그리드_아무것도없을경우 (246:5260), 메인_그리드_폴더버전 (246:5191), 메인_리스트 (246:5246)
struct HomeView: View {
    let userID: UUID
    var onSignOut: () -> Void = {}

    @State private var profile: Profile?
    /// 지금 펼쳐진 메뉴 (알림 내역 / 프로필)
    @State private var popover: HomePopover?
    @State private var folderDialog: FolderDialog?
    @State private var invitingFolder: Folder?
    @State private var joinedFolder: Folder?
    @State private var isShowingQRScanner = false
    @State private var isSearching = false
    @State private var searchText = ""
    /// 폴더 → 채팅 순으로 쌓이는 화면 경로
    @State private var path: [HomeRoute] = []
    @State private var questionAlerts = QuestionAlertCenter()
    /// 프로필 메뉴의 알림 내역. nil = 불러오는 중
    @State private var notifications: [NotificationItem]?
    @State private var didFailNotifications = false
    /// 프로필 메뉴를 마지막으로 연 뒤에 새 알림이 쌓였는지 (프로필 버튼의 빨간 점)
    @State private var hasNewNotifications = false
    /// nil = 아직 불러오는 중
    @State private var folders: [Folder]?

    private enum FolderDialog: Equatable {
        case create
        case join(code: String)
        case editNickname(current: String)
    }

    fileprivate enum HomePopover {
        case notifications
        case account
    }

    private var isShowingNotifications: Bool { popover == .notifications }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case let .folder(folder):
                        FolderDetailView(
                            folder: folder,
                            avatarURL: profile?.avatarURL.flatMap(URL.init(string:)),
                            onAskQuestion: { photos in path.append(.chat(folder, attaching: photos)) },
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
        .onChange(of: path) { old, new in updateReadState(from: old, to: new) }
        .task(id: userID) { await listenForMessages() }
        #if DEBUG
        .task(id: userID) { await simulateIncomingAfterBackground() }
        #endif
        .task(id: userID) { await LocalNotifications.requestAuthorization() }
        // 앱 밖 알림을 눌러 들어오면 그 폴더 채팅으로
        .onChange(of: NotificationRouter.shared.pendingFolderID, initial: true) { _, folderID in
            guard let folderID else { return }
            Task { await openChat(folderID: folderID) }
        }
    }

    private var home: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeHeader(
                    avatarURL: profile?.avatarURL.flatMap(URL.init(string:)),
                    searchText: $searchText,
                    isSearching: $isSearching,
                    onProfile: { toggle(.account) }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeBottomBar(
                    hasNewNotifications: hasNewNotifications,
                    onNotifications: { toggle(.notifications) },
                    onCreateFolder: { folderDialog = .create },
                    onJoinWithCode: { folderDialog = .join(code: "") },
                    onJoinWithQR: { isShowingQRScanner = true }
                )
            }
            .ignoresSafeArea(.keyboard)
            .overlay { popoverView }
            .animation(.snappy(duration: 0.25), value: popover)
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
            .task(id: isShowingNotifications) {
                guard isShowingNotifications else { return }
                // 메뉴를 열면 빨간 점은 사라지고, 안 읽은 내역은 채팅을 볼 때까지 남음
                readState.markMenuSeen()
                hasNewNotifications = false
                await reloadNotifications()
            }
            .task(id: userID) {
                profile = try? await ProfileRepository.fetch(userID: userID)
            }
            .task(id: userID) {
                await reloadFolders()
                await reloadNotifications()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch folders {
        case nil:
            ProgressView()
        case let folders? where folders.isEmpty:
            EmptyFolderView()
        case let folders?:
            let results = folders.matching(searchText)
            // 결과가 없어도 목록(ScrollView)은 그대로 둬야 입력 중 키보드가 내려가지 않음
            FolderCollectionView(
                folders: results,
                onSelect: { path.append(.folder($0)) },
                onInvite: { invitingFolder = $0 }
            )
            .refreshable { await reloadFolders() }
            .overlay {
                if results.isEmpty {
                    NoSearchResultView(query: searchText)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.25), value: searchText)
        }
    }

    /// 다른 멤버가 보낸 채팅·질문을 알림으로 띄움. 지금 그 폴더 채팅을 보고 있으면 띄우지 않습니다.
    /// - 백그라운드에서 방금 받은 것: 채팅과 나에게 온 질문을 앱 밖 알림으로 ([폴더] 닉네임 / 내용)
    /// - 그 밖 (앱을 보고 있을 때, 또는 앱이 멈춰 있는 동안 쌓였다가 다시 열 때 들어온 것):
    ///   나에게 온 질문만 가운데 카드로. 늦게 온 것을 앱 밖 알림으로 띄우면 앱을 열 때 알림이 울림
    /// 질문은 받을 사람으로 고른 멤버에게만 알립니다.
    /// (앱이 멈추거나 꺼져 있을 때 바로 받으려면 서버 푸시가 있어야 해서 아직 안 옴)
    private func listenForMessages() async {
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
            await handleIncoming(message)
        }
        await subscription.close()
    }

    private func handleIncoming(_ message: ChatMessage) async {
        guard message.userID != userID, !isViewingChat(of: message.folderID) else { return }
        // 다른 멤버에게 보낸 질문은 알리지 않음
        if message.isQuestion, !message.recipientIDs.contains(userID) { return }
        // 프로필 메뉴의 내역·빨간 점
        if isShowingNotifications {
            Task { await reloadNotifications() }
        } else {
            hasNewNotifications = true
        }

        if UIApplication.shared.applicationState != .active, LocalNotifications.isFresh(message) {
            guard let folder = await folder(id: message.folderID) else { return }
            let nickname = await nickname(of: message.userID, in: folder.id)
            await LocalNotifications.presentMessage(message, folder: folder, senderNickname: nickname)
        } else {
            // 앱 안에서는 질문만 카드로 (보통 채팅은 채팅방에서 확인)
            guard message.isQuestion,
                  let alert = await makeAlert(for: message),
                  !isViewingChat(of: message.folderID)
            else { return }
            questionAlerts.present(alert)
        }
    }

    #if DEBUG
    /// 실행 인자 -demoIncomingAfterBackground: 홈 화면으로 나간 뒤 15초, 60초에 다른 멤버의 사진 질문이 온 것처럼 흉내
    /// 15초: 앱이 아직 깨어 있어 앱 밖 알림 / 60초: 앱이 멈춰 있어 다시 열 때 들어오므로 가운데 카드
    private func simulateIncomingAfterBackground() async {
        guard ProcessInfo.processInfo.arguments.contains("-demoIncomingAfterBackground") else { return }
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
            guard let folder = folders?.first else { continue }
            for delay in [15, 60] {
                // 서버에 저장된 시각 = 보낸 시각. 앱이 멈춰 있으면 받는 건 그보다 늦어짐
                let sentAt = Date.now.addingTimeInterval(TimeInterval(delay))
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    await handleIncoming(ChatMessage(
                        id: UUID(), folderID: folder.id, userID: UUID(), body: "\(delay)초 테스트",
                        createdAt: sentAt, photoIDs: [UUID(), UUID()], recipientIDs: [userID]
                    ))
                }
            }
        }
    }
    #endif

    private func openChat(folderID: UUID) async {
        NotificationRouter.shared.pendingFolderID = nil
        if folders?.contains(where: { $0.id == folderID }) != true {
            await reloadFolders()
        }
        guard let folder = folders?.first(where: { $0.id == folderID }) else { return }
        path = [.folder(folder), .chat(folder)]
    }

    /// 이 기기에 저장한 읽음 기록
    private var readState: NotificationReadState { NotificationReadState(userID: userID) }

    /// 알림 내역을 새로 불러오고 프로필의 빨간 점을 맞춤. 이미 받은 내역은 불러오는 동안에도 그대로 보여 줌
    private func reloadNotifications() async {
        #if DEBUG
        // 실행 인자 -demoNotifications 로 내역·빨간 점 모양 확인
        if ProcessInfo.processInfo.arguments.contains("-demoNotifications") {
            let demoFolders = folders?.isEmpty == false ? folders! : Folder.previews
            func folder(_ index: Int) -> Folder { demoFolders[index % demoFolders.count] }
            notifications = [
                NotificationItem(
                    id: "q1", folder: folder(0),
                    kind: .question(text: "현서님이 사진 3장에 대한 질문을 올렸어요! 확인해주세요:)"),
                    createdAt: .now.addingTimeInterval(-90), isUnread: true
                ),
                NotificationItem(
                    id: "c1", folder: folder(1), kind: .unreadChats(count: 12),
                    createdAt: .now.addingTimeInterval(-1_800), isUnread: true
                ),
                NotificationItem(
                    id: "c2", folder: folder(2), kind: .unreadChats(count: 128),
                    createdAt: .now.addingTimeInterval(-7_200), isUnread: true
                ),
                NotificationItem(
                    id: "q2", folder: folder(3),
                    kind: .question(text: "승완님의 질문: 이거 인스타에 올려도 돼?"),
                    createdAt: .now.addingTimeInterval(-86_400), isUnread: false
                ),
            ]
            hasNewNotifications = !isShowingNotifications
            return
        }
        #endif
        guard let folders else { return }
        do {
            let items = try await NotificationHistory.fetch(folders: folders, userID: userID)
            notifications = items
            didFailNotifications = false
            hasNewNotifications = !isShowingNotifications && readState.hasNew(in: items)
        } catch is CancellationError {
        } catch {
            print("[Notification] 내역 불러오기 실패:", error)
            didFailNotifications = notifications == nil
        }
    }

    /// 채팅방에 들어가거나 나올 때 그 폴더를 읽음으로. 나오면 내역도 새로
    private func updateReadState(from old: [HomeRoute], to new: [HomeRoute]) {
        var changed = false
        for route in [old.last, new.last] {
            if case let .chat(folder, _)? = route {
                readState.markRead(folderID: folder.id)
                changed = true
            }
        }
        if changed { Task { await reloadNotifications() } }
    }

    private func isViewingChat(of folderID: UUID) -> Bool {
        if case let .chat(folder, _)? = path.last { return folder.id == folderID }
        return false
    }

    private func folder(id folderID: UUID) async -> Folder? {
        if let folder = folders?.first(where: { $0.id == folderID }) { return folder }
        // 방금 참여한 폴더일 수 있음
        await reloadFolders()
        return folders?.first { $0.id == folderID }
    }

    private func nickname(of memberID: UUID, in folderID: UUID) async -> String {
        let members = try? await ChatRepository.fetchMembers(folderID: folderID)
        return members?.first { $0.userID == memberID }?.nickname ?? "샬픽 사용자"
    }

    private func makeAlert(for message: ChatMessage) async -> QuestionAlert? {
        guard let folder = await folder(id: message.folderID) else { return nil }

        async let nickname = nickname(of: message.userID, in: folder.id)
        async let photos = try? PhotoRepository.fetch(folderID: folder.id)
        // 질문에 붙은 사진이 있으면 그 사진, 없으면 폴더 최신 사진
        let folderPhotos = await photos ?? []
        let byID = Dictionary(folderPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let attached = message.photoIDs.compactMap { byID[$0] }
        return await QuestionAlert(
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
    func toggle(_ target: HomePopover) {
        popover = popover == target ? nil : target
    }

    /// 프로필 메뉴는 프로필 버튼 아래, 알림 내역은 알림 버튼 위에 펼쳐짐. 바깥을 누르면 닫힘
    var popoverView: some View {
        ZStack {
            if popover != nil {
                Color.black.opacity(0.06)
                    .ignoresSafeArea()
                    .onTapGesture { popover = nil }
                    .accessibilityLabel("메뉴 닫기")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            }

            if popover == .account {
                AccountMenu(
                    onEditProfile: {
                        popover = nil
                        folderDialog = .editNickname(current: profile?.nickname ?? "")
                    },
                    onSignOut: {
                        popover = nil
                        onSignOut()
                    }
                )
                // 헤더(위 여백 11 + 높이 52) 바로 아래, 프로필 버튼 오른쪽 끝에 맞춤
                .padding(.top, 71)
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }

            if popover == .notifications {
                NotificationPanel(
                    items: notifications,
                    didFail: didFailNotifications,
                    onSelect: { item in
                        popover = nil
                        // 메뉴 닫힘 애니메이션과 같은 순간에 바꾸면 채팅까지 쌓이지 않아서 다음 차례에
                        Task { path = [.folder(item.folder), .chat(item.folder)] }
                    }
                )
                // 하단 버튼(아래 여백 33 + 추가 45 + 간격 8 + 알림 45) 바로 위
                .padding(.bottom, 141)
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
    }

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
        case let .editNickname(current):
            FolderInputDialog(kind: .nickname, initialText: current, onCancel: { folderDialog = nil }) { nickname in
                profile = try await ProfileRepository.updateNickname(nickname, userID: userID)
                folderDialog = nil
            }
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
