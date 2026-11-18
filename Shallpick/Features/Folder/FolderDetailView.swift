import Photos
import SwiftUI

/// 폴더를 눌렀을 때 들어가는 화면: 사진 4열 그리드 + 상단(뒤로/이름/검색/채팅) + 하단(필터/수달/추가)
/// Figma: 폴더안 (246:5208)
struct FolderDetailView: View {
    let folder: Folder
    var avatarURL: URL?
    var unreadCount = 0
    var onSearch: () -> Void = {}
    /// 수달 → "질문에 첨부할 사진 선택" 에서 → 를 누르면 불립니다 (고른 순서대로).
    /// 주면 밖에서 채팅을 열고, 없으면 이 화면에서 고른 사진을 붙여 채팅을 엽니다.
    var onAskQuestion: (([PhotoItem]) -> Void)?
    /// 채팅 버튼. 주면 밖(HomeView 의 내비게이션 경로)에서 채팅을 열고, 없으면 이 화면에서 엽니다.
    var onOpenChat: (() -> Void)?
    var onQuestionSent: ((ChatMessage) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Namespace private var photoNamespace
    @State private var photos: [PhotoItem]
    @State private var filters: Set<PhotoFilter> = []
    @State private var isShowingFilterMenu = false
    @State private var isShowingChat = false
    /// 이 화면에서 채팅을 열 때 첫 메시지에 붙일 사진
    @State private var chatAttachments: [PhotoItem] = []
    @State private var isShowingPhotoPicker = false
    @State private var isShowingQuestionPicker = false
    @State private var isShowingInvite = false
    /// 그리드에서 누른 사진 → 사진 크게 보기 (Figma 사진 클릭시 540:10918)
    @State private var openedPhoto: PhotoItem?
    /// 선택 모드의 수달 → 고른 사진으로 질문 보내기 (Figma 3, 512:10261)
    @State private var isShowingQuestionCompose = false
    /// 사진을 꾹 누르면 선택 모드 (nil 이면 보통 화면). 고른 사진 id
    @State private var selection: Set<UUID>?
    /// 올리기 / 저장하기 진행 상황 (위에 작은 알림)
    @State private var progress: BusyProgress?
    /// 잠깐 떴다 사라지는 알림 (예: 저장했어요)
    @State private var notice: String?
    /// 삭제 확인을 기다리는 사진
    @State private var pendingDelete: [PhotoItem]?
    @State private var errorMessage: String?
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var memberNames: [UUID: String] = [:]
    @State private var likedIDs: Set<UUID> = []
    @State private var likesFailed = false
    @State private var pendingUploads: [(asset: PHAsset, id: UUID)] = []
    @State private var failedSaves: [PhotoItem] = []
    @State private var sentQuestionID: UUID?
    @State private var sentQuestion: ChatMessage?

    private var visiblePhotos: [PhotoItem] {
        let filtered = photos.filtered(by: filters, likedIDs: likedIDs)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return filtered }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return filtered.filter { photo in
            let date = formatter.string(from: photo.createdAt)
            let korean = photo.createdAt.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).year().month().day())
            return [memberNames[photo.uploaderID] ?? "", date, date.replacingOccurrences(of: "-", with: "."), korean]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private struct BusyProgress: Equatable {
        let title: String
        var done: Int
        let total: Int
    }

    /// 선택한 사진 (화면 순서)
    private var selectedPhotos: [PhotoItem] {
        guard let selection else { return [] }
        return photos.filter { selection.contains($0.id) }
    }

    init(
        folder: Folder,
        avatarURL: URL? = nil,
        unreadCount: Int = 0,
        photos: [PhotoItem] = [],
        onSearch: @escaping () -> Void = {},
        onAskQuestion: (([PhotoItem]) -> Void)? = nil,
        onOpenChat: (() -> Void)? = nil,
        onQuestionSent: ((ChatMessage) -> Void)? = nil
    ) {
        self.folder = folder
        self.avatarURL = avatarURL
        self.unreadCount = unreadCount
        self.onSearch = onSearch
        self.onAskQuestion = onAskQuestion
        self.onOpenChat = onOpenChat
        self.onQuestionSent = onQuestionSent
        _photos = State(initialValue: photos)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .overlay {
                // 필터 메뉴 바깥을 누르면 닫힘
                if isShowingFilterMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isShowingFilterMenu = false }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay(alignment: .top) { uploadBanner }
            // 사람 초대: 위아래 버튼까지 덮고 가운데에 QR + 참여 코드
            .overlay {
                if isShowingInvite {
                    FolderInvitePopup(folder: folder) { isShowingInvite = false }
                }
            }
            .animation(.snappy(duration: 0.25), value: isShowingInvite)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.snappy(duration: 0.2), value: isShowingFilterMenu)
            .animation(.snappy(duration: 0.2), value: progress)
            .animation(.snappy(duration: 0.2), value: notice)
            .animation(.snappy(duration: 0.2), value: selection == nil)
            .sensoryFeedback(.impact(weight: .medium), trigger: selection == nil) { wasNormal, _ in wasNormal }
            .navigationDestination(isPresented: $isShowingChat) {
                ChatView(folder: folder, attaching: chatAttachments, focusMessageID: sentQuestionID)
            }
            .navigationDestination(item: $openedPhoto) { photo in
                PhotoDetailView(
                    folder: folder,
                    photos: visiblePhotos,
                    startID: photo.id,
                    avatarURL: avatarURL,
                    onQuestionSent: onQuestionSent
                )
                .modifier(PhotoZoomTransition(photoID: photo.id, namespace: photoNamespace))
            }
            // + : 내 보관함에서 골라 폴더에 올리기 (Figma 갤러리 173:21698)
            .sheet(isPresented: $isShowingPhotoPicker) {
                PhotoPickerSheet { assets in
                    Task { await uploadPhotos(assets) }
                }
                .presentationDetents([.large])
                .presentationCornerRadius(36)
                .presentationDragIndicator(.hidden)
            }
            // 수달 : 폴더 사진 중에서 질문에 첨부할 사진 고르기 (Figma 328:4864)
            .fullScreenCover(isPresented: $isShowingQuestionPicker) {
                FolderPhotoSelectView(photos: photos, avatarURL: avatarURL) { picked in
                    if let onAskQuestion {
                        onAskQuestion(picked)
                    } else {
                        chatAttachments = picked
                        isShowingChat = true
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingQuestionCompose, onDismiss: {
                if let sentQuestion, let onQuestionSent { onQuestionSent(sentQuestion) }
                else if sentQuestionID != nil { chatAttachments = []; isShowingChat = true }
            }) {
                QuestionComposeView(
                    folder: folder,
                    photos: selectedPhotos,
                    onRemovePhoto: { photo in selection?.remove(photo.id) },
                    onSent: { message in
                        sentQuestion = message
                        sentQuestionID = message.id
                        selection = nil
                        showNotice("질문을 보냈어요")
                    }
                )
            }
            .alert(
                deleteAlertTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { targets in
                if deletableCount(targets) > 0 {
                    Button("취소", role: .cancel) {}
                    Button("삭제", role: .destructive) {
                        Task { await deletePhotos(targets) }
                    }
                } else {
                    Button("확인", role: .cancel) {}
                }
            } message: { targets in
                Text(deleteAlertMessage(targets))
            }
            .alert(
                "문제가 생겼어요",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                if !pendingUploads.isEmpty {
                    Button("실패한 사진 다시 올리기") { Task { await retryUploads() } }
                }
                if !failedSaves.isEmpty {
                    Button("실패한 사진 다시 저장") { Task { await savePhotos(failedSaves) } }
                }
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await reload() }
            .onChange(of: openedPhoto) { _, photo in
                if photo == nil { Task { await reloadLikes() } }
            }
            .onChange(of: filters) { _, _ in Task { await reloadLikes() } }
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty {
            EmptyPhotoView()
        } else if visiblePhotos.isEmpty {
            VStack(spacing: 14) {
                Text(likesFailed && filters.contains(.liked) ? "좋아요를 불러오지 못했어요" : "조건에 맞는 사진이 없어요")
                Button("검색과 필터 해제") { searchText = ""; filters = [] }
                if likesFailed { Button("다시 시도") { Task { await reloadLikes() } } }
            }.foregroundStyle(Color.black600)
        } else {
            PhotoGrid(
                photos: visiblePhotos,
                namespace: photoNamespace,
                selection: selection,
                onLongPress: { photo in
                    isShowingFilterMenu = false
                    selection = [photo.id]
                },
                onToggle: { photo in
                    guard var current = selection else { return }
                    if current.contains(photo.id) { current.remove(photo.id) } else { current.insert(photo.id) }
                    selection = current
                },
                onOpen: { photo in
                    isShowingFilterMenu = false
                    openedPhoto = photo
                }
            )
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        guard SupabaseManager.client != nil else { return }
        do {
            photos = try await PhotoRepository.fetch(folderID: folder.id)
            let members = try await ChatRepository.fetchMembers(folderID: folder.id)
            memberNames = Dictionary(members.map { ($0.userID, $0.nickname) }, uniquingKeysWith: { _, new in new })
            await reloadLikes()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadLikes() async {
        do { likedIDs = try await PhotoFeedbackRepository.likedPhotoIDs(in: photos); likesFailed = false }
        catch { likesFailed = true; likedIDs = [] }
    }

    private func uploadPhotos(_ assets: [PHAsset]) async {
        guard progress == nil else { return }
        let existing = Set(pendingUploads.map { $0.asset.localIdentifier })
        pendingUploads += assets.filter { !existing.contains($0.localIdentifier) }.map { ($0, UUID()) }
        await retryUploads()
    }

    private func retryUploads() async {
        guard progress == nil, !pendingUploads.isEmpty else { return }
        let targets = pendingUploads
        progress = BusyProgress(title: "사진 올리는 중", done: 0, total: targets.count)
        defer { progress = nil }
        for (index, item) in targets.enumerated() {
            do {
                try await PhotoRepository.uploadOne(item.asset, id: item.id, folderID: folder.id)
                pendingUploads.removeAll { $0.id == item.id }
            } catch { /* Keep this item and its stable id for retry. */ }
            progress?.done = index + 1
        }
        await reload()
        if pendingUploads.isEmpty { showNotice("사진 \(targets.count)장을 올렸어요") }
        else { errorMessage = "\(targets.count - pendingUploads.count)장 완료, \(pendingUploads.count)장 실패. 실패한 사진만 다시 올릴 수 있어요." }
    }

    private func saveSelected() async { await savePhotos(selectedPhotos) }

    private func savePhotos(_ targets: [PhotoItem]) async {
        guard !targets.isEmpty, progress == nil else { return }
        progress = BusyProgress(title: "사진 저장 중", done: 0, total: targets.count)
        defer { progress = nil }
        do {
            let result = try await PhotoExport.save(targets) { progress?.done = $0 }
            failedSaves = result.failed
            selection = result.failed.isEmpty ? nil : Set(result.failed.map(\.id))
            if result.failed.isEmpty { showNotice("사진 \(result.succeeded.count)장을 저장했어요") }
            else { errorMessage = "\(result.succeeded.count)장 저장, \(result.failed.count)장 실패. 실패한 사진만 다시 저장할 수 있어요." }
        } catch { errorMessage = error.localizedDescription }
    }

    private func deletableCount(_ targets: [PhotoItem]) -> Int {
        let me = PhotoRepository.currentUserID
        return targets.count { $0.uploaderID == me }
    }

    private var deleteAlertTitle: String {
        guard let pendingDelete else { return "" }
        let count = deletableCount(pendingDelete)
        return count > 0 ? "사진 \(count)장을 삭제할까요?" : "삭제할 수 없어요"
    }

    private func deleteAlertMessage(_ targets: [PhotoItem]) -> String {
        let count = deletableCount(targets)
        let others = targets.count - count
        if count == 0 { return "다른 사람이 올린 사진은 삭제할 수 없어요." }
        let base = "폴더의 모든 사람에게서 사라지고 되돌릴 수 없어요."
        return others > 0 ? base + "\n다른 사람이 올린 사진 \(others)장은 삭제되지 않아요." : base
    }

    private func deletePhotos(_ targets: [PhotoItem]) async {
        do {
            try await PhotoRepository.delete(targets)
            let me = PhotoRepository.currentUserID
            let removed = Set(targets.filter { $0.uploaderID == me }.map(\.id))
            photos.removeAll { removed.contains($0.id) }
            selection = nil
            showNotice("사진 \(removed.count)장을 삭제했어요")
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
    }

    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if notice == text { notice = nil }
        }
    }

    /// 올리기·저장 중이거나 방금 끝났을 때 위에 뜨는 작은 알림
    @ViewBuilder
    private var uploadBanner: some View {
        if progress != nil || notice != nil {
            HStack(spacing: 8) {
                if let progress {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(progress.title) \(progress.done)/\(progress.total)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black800)
                        .monospacedDigit()
                } else if let notice {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.black800)
                    Text(notice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black800)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .shadowedBackground(.white, in: Capsule(), blur: 20)
            .padding(.top, 74)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - 상단 (246:5211)

    private var header: some View {
        VStack(spacing: 0) {
            if isSearching {
                HStack {
                    TextField("올린 사람, 업로드 날짜", text: $searchText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("닫기") { isSearching = false; searchText = "" }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
            headerButtons
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 0) {
            // 선택 모드에서는 뒤로 = 선택 끝내기
            CircleIconButton(icon: .iconBack, accessibilityLabel: selection == nil ? "뒤로" : "선택 끝내기") {
                if selection != nil { selection = nil } else { dismiss() }
            }

            // 제목 + ⌄ : 누르면 초대 QR / 참여 코드
            Button { isShowingInvite = true } label: {
                HStack(spacing: 4) {
                    Text(folder.name)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.black800)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(folder.name)
            .accessibilityHint("초대 QR 코드와 참여 코드를 보여줘요")
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            if selection != nil {
                // 꾹 눌렀을 때 (396:4657): 저장 / 삭제
                HStack(spacing: 8) {
                    CircleIconButton(icon: .iconDownload, accessibilityLabel: "저장") {
                        Task { await saveSelected() }
                    }
                    CircleIconButton(icon: .iconDelete, accessibilityLabel: "삭제") {
                        let targets = selectedPhotos
                        if !targets.isEmpty { pendingDelete = targets }
                    }
                }
                // 고른 사진이 없거나 저장 중이면 누를 수 없음
                .disabled(selectedPhotos.isEmpty || progress != nil)
                .opacity(selectedPhotos.isEmpty ? 0.4 : 1)
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색", action: { isSearching.toggle(); onSearch() })
                    CircleIconButton(icon: .iconChat, accessibilityLabel: "채팅") {
                        if let onOpenChat {
                            onOpenChat()
                        } else {
                            chatAttachments = []
                            isShowingChat = true
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if unreadCount > 0 {
                            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 19, minHeight: 19)
                                .background(Color.red, in: Capsule())
                                .offset(x: 4, y: -4)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityValue(unreadCount > 0 ? "읽지 않은 글 \(unreadCount)개" : "읽지 않은 글 없음")
                }
                .transition(.opacity)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background(alignment: .top) { TopFade() }
    }

    // MARK: - 하단 (190:22267)

    /// 보통 화면: 필터 ... + / 선택 모드 (397:4908): 필터 ... 수달. 필터는 늘 같은 자리
    private var bottomBar: some View {
        HStack {
            PhotoFilterButton(isOpen: $isShowingFilterMenu, selection: $filters, avatarURL: avatarURL)

            Spacer()

            // 오른쪽 아래 자리: + 와 수달이 서로 바뀜
            ZStack {
                if selection == nil {
                    CircleIconButton(icon: .iconPlus, accessibilityLabel: "사진 올리기") {
                        isShowingFilterMenu = false
                        isShowingPhotoPicker = true
                    }
                    .transition(.opacity)
                } else {
                    OtterButton(accessibilityLabel: "고른 사진으로 질문 보내기") {
                        guard !selectedPhotos.isEmpty else { return }
                        isShowingFilterMenu = false
                        sentQuestion = nil
                    sentQuestionID = nil
                    isShowingQuestionCompose = true
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .background { BottomFade() }
    }
}

// MARK: - 공용 조각 (폴더 화면 / 사진 고르기 화면)

/// 위쪽: black50 에서 투명으로
struct TopFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black50, location: 0.279),
                .init(color: .black50.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
    }
}

/// 아래쪽: 투명에서 black50 으로
struct BottomFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black50.opacity(0), location: 0),
                .init(color: .black50, location: 0.889),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

/// 열려 있으면 X, 닫혀 있으면 필터 아이콘. 메뉴는 버튼 12pt 위에 뜸 (162:20993)
struct PhotoFilterButton: View {
    @Binding var isOpen: Bool
    @Binding var selection: Set<PhotoFilter>
    var avatarURL: URL?

    var body: some View {
        CircleIconButton(
            icon: isOpen ? .iconClose : .iconFilter,
            accessibilityLabel: isOpen ? "필터 닫기" : "필터"
        ) {
            isOpen.toggle()
        }
        .overlay(alignment: .bottomLeading) {
            if isOpen {
                PhotoFilterMenu(selection: $selection, avatarURL: avatarURL)
                    .fixedSize()
                    .offset(y: -(45 + 12))
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .zIndex(1)
    }
}

/// 폴더 사진 한 칸 (정사각형)
struct FolderPhotoCell: View {
    let photo: PhotoItem

    var body: some View {
        Color.blue50
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: photo.url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipped()
    }
}

extension [PhotoItem] {
    /// 내 업로드와 내가 남긴 하트. 질문의 좋아/싫어 답변과는 별개.
    func filtered(by filters: Set<PhotoFilter>, likedIDs: Set<UUID> = []) -> [PhotoItem] {
        return filter { photo in
            (!filters.contains(.mine) || photo.uploaderID == PhotoRepository.currentUserID) &&
            (!filters.contains(.liked) || likedIDs.contains(photo.id))
        }
    }
}

// MARK: - 사진 그리드

/// 기본 4열. 두 손가락 확대/축소로 2~6열 사이에서 사진 크기를 바꿉니다.
private struct PhotoGrid: View {
    let photos: [PhotoItem]
    let namespace: Namespace.ID
    /// nil 이면 보통 모드
    var selection: Set<UUID>?
    var onLongPress: (PhotoItem) -> Void = { _ in }
    var onToggle: (PhotoItem) -> Void = { _ in }
    /// 보통 모드에서 사진을 누르면 크게 보기
    var onOpen: (PhotoItem) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("folder.photoGrid.columns") private var columnCount = 4
    @State private var visiblePhotoID: UUID?
    @GestureState private var magnification: CGFloat = 1

    // 손을 뗄 때만 기준 열 수를 저장합니다. 조절 중 레이아웃이 바뀌어도
    // 같은 핀치의 시작 기준이 달라지지 않게 합니다.
    private var displayedColumns: Int {
        min(max(Int((CGFloat(columnCount) / max(magnification, 0.1)).rounded()), 2), 6)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: displayedColumns)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(photos) { photo in
                    cell(photo)
                        .id(photo.id)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: displayedColumns)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visiblePhotoID, anchor: .top)
        .simultaneousGesture(
            MagnifyGesture()
                .updating($magnification) { value, scale, _ in scale = value.magnification }
                .onEnded { value in
                    setColumns(Int((CGFloat(columnCount) / max(value.magnification, 0.1)).rounded()))
                }
        )
        .sensoryFeedback(.selection, trigger: displayedColumns)
        .accessibilityIdentifier("folder.photoGrid")
        .accessibilityValue("\(displayedColumns)열")
        .accessibilityHint("두 손가락으로 확대하거나 축소해 사진 크기를 바꿀 수 있어요")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setColumns(columnCount - 1)
            case .decrement: setColumns(columnCount + 1)
            @unknown default: break
            }
        }
    }

    private func setColumns(_ count: Int) { columnCount = min(max(count, 2), 6) }

    /// 보통: 꾹 누르면 선택 모드. 선택 모드: 누를 때마다 체크 (왼쪽 위 동그라미, 237:26720)
    /// 모드가 바뀌어도 같은 칸을 유지해야 사진을 다시 받지 않음 (체크·테두리만 얹음)
    private func cell(_ photo: PhotoItem) -> some View {
        let isSelecting = selection != nil
        let isSelected = selection?.contains(photo.id) == true
        return FolderPhotoCell(photo: photo)
            .matchedTransitionSource(id: photo.id, in: namespace)
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Color.black800, lineWidth: 4)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    SelectionCheck(isOn: isSelected)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            // 꾹 누르기를 탭보다 먼저 달아야 0.4초에 바로 켜짐 (탭 뒤에 달면 약 0.65초로 늦어짐)
            .onLongPressGesture(minimumDuration: 0.4) {
                if !isSelecting { onLongPress(photo) }
            }
            .onTapGesture {
                if isSelecting { onToggle(photo) } else { onOpen(photo) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("사진")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { if isSelecting { onToggle(photo) } else { onOpen(photo) } }
            .accessibilityAction(named: "선택") { if !isSelecting { onLongPress(photo) } }
    }
}

/// 사진이 하나도 없을 때
private struct EmptyPhotoView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(.otterEmpty)
                .resizable()
                .scaledToFill()
                .frame(width: 167, height: 173.37)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("아직 사진이 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("+ 버튼을 눌러 사진을 올려보세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .multilineTextAlignment(.center)
        }
    }
}

// MARK: - 필터 메뉴

enum PhotoFilter: Hashable {
    case liked
    case mine
}

/// 좋아요 / 내사진 / 필터 모두 삭제 (162:20872)
struct PhotoFilterMenu: View {
    @Binding var selection: Set<PhotoFilter>
    var avatarURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(.liked) {
                Text("좋아요")
            }
            Divider()
            row(.mine) {
                HStack(spacing: 8) {
                    AsyncImage(url: avatarURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(.defaultAvatar).resizable().scaledToFill()
                        }
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    Text("내사진")
                }
            }
            Divider()
            Button {
                selection.removeAll()
            } label: {
                Text("필터 모두 삭제")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.black800)
        .padding(20)
        .frame(width: 198)
        .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 16), blur: 20)
    }

    /// 선택된 항목은 굵게 + 체크 (filter_d_check)
    private func row(_ filter: PhotoFilter, @ViewBuilder label: () -> some View) -> some View {
        let isOn = selection.contains(filter)
        return Button {
            if isOn { selection.remove(filter) } else { selection.insert(filter) }
        } label: {
            HStack {
                label()
                    .font(.system(size: 16, weight: isOn ? .semibold : .medium))
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Preview

extension PhotoItem {
    static let previews: [PhotoItem] = (1...40).map { index in
        let folderID = Folder.previews[0].id
        return PhotoItem(
            id: UUID(),
            folderID: folderID,
            uploaderID: UUID(),
            storagePath: "\(folderID)/\(index).jpg",
            createdAt: .now,
            url: URL(string: "https://picsum.photos/seed/\(index)/200")
        )
    }
}

#Preview("사진 있음") {
    NavigationStack {
        FolderDetailView(folder: Folder.previews[0], photos: PhotoItem.previews)
    }
}

#Preview("비어 있음") {
    NavigationStack {
        FolderDetailView(folder: Folder.previews[0])
    }
}
