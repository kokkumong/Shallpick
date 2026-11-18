import SwiftUI

/// 폴더 화면 선택 모드에서 수달을 누르면 뜨는 "질문 보내기"
/// 고른 사진 + 질문 + 받을 사람 → 폴더 채팅에 질문 메시지로 올라가고, 받을 사람에게 질문 알림이 뜹니다.
/// Figma: 3 (512:10261)
struct QuestionComposeView: View {
    let folder: Folder
    /// 사진 보기에서 휴지통으로 뺀 사진 (폴더 화면의 선택에서도 빼도록)
    var onRemovePhoto: (PhotoItem) -> Void = { _ in }
    /// 보내고 나면 불림 (닫기는 이 화면이 함)
    var onSent: () -> Void = {}

    init(
        folder: Folder,
        photos: [PhotoItem],
        onRemovePhoto: @escaping (PhotoItem) -> Void = { _ in },
        onSent: @escaping () -> Void = {}
    ) {
        self.folder = folder
        self.onRemovePhoto = onRemovePhoto
        self.onSent = onSent
        _photos = State(initialValue: photos)
    }

    @Environment(\.dismiss) private var dismiss
    /// 고른 사진 (화면 순서). 앞의 3장이 위 그림에 꽂힘
    @State private var photos: [PhotoItem]
    /// 사진 묶음을 눌렀을 때 크게 보기 (Figma 사진묶음 눌렀을 때 512:10294)
    @State private var isShowingViewer = false
    @State private var question = ""
    /// nil = 아직 불러오는 중
    @State private var members: [ChatMember]?
    @State private var recipients: Set<UUID> = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isQuestionFocused: Bool
    /// 수달이 살펴본 사진 특징 (사진 id 별, 한 번 본 사진은 다시 안 봄)
    @State private var signals: [UUID: PhotoSignal] = [:]
    /// 수달의 제안과, 그때 사진 순서 (사진이 바뀌면 다시 계산)
    @State private var pick: (order: [UUID], value: OtterPick)?
    /// 수달 제안대로 추리기 전 사진 (되돌리기용). nil 이면 아직 안 추림
    @State private var photosBeforePick: [PhotoItem]?
    @State private var isShowingPick = false

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedQuestion.isEmpty && !recipients.isEmpty && !isSending
    }

    /// 아래 "질문 보내기" 줄 높이 (위 24 + 버튼 48 + 아래 33)
    private let sendBarHeight: CGFloat = 105

    var body: some View {
        // 키보드가 올라와도 "질문 보내기" 는 아래에 그대로 둠 (키보드에 가려짐).
        // 입력칸이 화면 위쪽이라 내용도 키보드를 피하지 않아도 가리지 않음
        ZStack(alignment: .bottom) {
            content
            sendBar
        }
        .ignoresSafeArea(.keyboard)
        .background(Color.black50)
        .alert(
            "질문을 보내지 못했어요",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if isShowingViewer {
                QuestionPhotoViewer(
                    photos: photos,
                    onRemove: remove,
                    onClose: { isShowingViewer = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: isShowingViewer)
        .sheet(isPresented: $isShowingPick) {
            if let pick = currentPick {
                OtterPickSheet(photos: photos, pick: pick, onApply: applyPick)
                    .presentationDetents([.large])
                    .presentationCornerRadius(36)
                    .presentationDragIndicator(.hidden)
            }
        }
        .task { await loadMembers() }
        .task(id: photos.map(\.id)) { await analyzePhotos() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 26) {
                Button {
                    isQuestionFocused = false
                    isShowingViewer = true
                } label: {
                    PhotoStack(urls: photos.prefix(3).map(\.url))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("고른 사진 \(photos.count)장 크게 보기")
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 20) {
                    if let otterPhase {
                        OtterPickCard(
                            state: otterPhase,
                            onOpen: {
                                isQuestionFocused = false
                                isShowingPick = true
                            },
                            onUndo: undoPick
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    questionField
                    recipientList
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
            // 키보드가 올라와 있을 때 입력칸 밖을 누르면 내림
            .contentShape(Rectangle())
            .onTapGesture { isQuestionFocused = false }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        // 아래 "질문 보내기" 에 가리지 않게
        .safeAreaPadding(.bottom, sendBarHeight)
    }

    /// 사진 보기의 휴지통: 고른 사진에서 빼고, 다 빠지면 질문도 닫음
    private func remove(_ photo: PhotoItem) {
        withAnimation(.snappy(duration: 0.25)) {
            photos.removeAll { $0.id == photo.id }
        }
        // 직접 뺀 사진은 되돌리기로도 돌아오지 않게
        photosBeforePick?.removeAll { $0.id == photo.id }
        onRemovePhoto(photo)
        if photos.isEmpty {
            isShowingViewer = false
            dismiss()
        }
    }

    // MARK: - 수달이 추려 주기 (OtterPicker)

    /// 지금 사진 순서에 맞는 제안 (사진이 바뀐 직후 다시 계산 전이면 nil)
    private var currentPick: OtterPick? {
        guard let pick, pick.order == photos.map(\.id) else { return nil }
        return pick.value
    }

    private var otterPhase: OtterPickCard.Phase? {
        if let before = photosBeforePick {
            return .applied(kept: photos.count, before: before.count)
        }
        guard photos.count >= OtterPicker.minPhotos else { return nil }
        guard let pick = currentPick else { return .analyzing }
        guard pick.removableCount > 0 else { return .nothing }
        return .suggest(
            groups: pick.similarGroups.count,
            total: photos.count,
            keep: photos.count - pick.removableCount
        )
    }

    /// 아직 안 본 사진만 살펴보고 제안을 다시 만듦
    private func analyzePhotos() async {
        guard photos.count >= OtterPicker.minPhotos else { return }
        let missing = photos.filter { signals[$0.id] == nil }
        if !missing.isEmpty {
            let found = await OtterPicker.analyze(missing)
            guard !Task.isCancelled else { return }
            signals.merge(found) { _, new in new }
        }
        let order = photos.map(\.id)
        let value = OtterPicker.suggest(for: order, signals: signals)
        withAnimation(.snappy(duration: 0.25)) {
            pick = (order, value)
        }
    }

    private func applyPick(_ kept: [PhotoItem]) {
        guard !kept.isEmpty, kept.count < photos.count || photosBeforePick != nil else { return }
        let before = photosBeforePick ?? photos
        withAnimation(.snappy(duration: 0.3)) {
            photos = kept
            photosBeforePick = before
        }
    }

    private func undoPick() {
        guard let before = photosBeforePick else { return }
        withAnimation(.snappy(duration: 0.3)) {
            photos = before
            photosBeforePick = nil
        }
    }

    // MARK: - 상단: 닫기 / 질문 보내기 (보내기는 아래 버튼으로만)

    private var header: some View {
        HStack {
            CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") { dismiss() }
            Spacer()
        }
        .overlay {
            Text("질문 보내기")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black800)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
        .padding(.top, 11)
        .padding(.bottom, 16)
        .background(alignment: .top) { TopFade() }
    }

    // MARK: - 질문입력

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("질문입력")
            TextField(
                "",
                text: $question,
                prompt: Text("질문할 내용을 입력하세요").foregroundStyle(Color.black400),
                axis: .vertical
            )
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.black800)
            .lineLimit(1...4)
            .focused($isQuestionFocused)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(minHeight: 52)
            .background(Color.black50, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isQuestionFocused ? Color.black400 : Color.black200, lineWidth: 1)
            }
            .onChange(of: question) { _, newValue in
                if newValue.count > ChatRepository.maxBodyLength {
                    question = String(newValue.prefix(ChatRepository.maxBodyLength))
                }
            }
        }
    }

    // MARK: - 보낼 사람 선택

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("보낼 사람 선택")
            switch members {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 52)
            case let members? where members.isEmpty:
                Text("아직 폴더에 다른 사람이 없어요.\n폴더 이름을 눌러 친구를 초대해 보세요.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black400)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            case let members?:
                VStack(spacing: 8) {
                    ForEach(members, id: \.userID) { member in
                        RecipientRow(member: member, isSelected: recipients.contains(member.userID)) {
                            isQuestionFocused = false
                            if recipients.contains(member.userID) {
                                recipients.remove(member.userID)
                            } else {
                                recipients.insert(member.userID)
                            }
                        }
                    }
                }
                .animation(.snappy(duration: 0.15), value: recipients)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.black800)
    }

    // MARK: - 하단: 질문 보내기

    private var sendBar: some View {
        Button {
            Task { await send() }
        } label: {
            ZStack {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("질문 보내기")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.black800.opacity(canSend || isSending ? 1 : 0.3), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 33)
        .background { BottomFade() }
    }

    // MARK: - 데이터

    private func loadMembers() async {
        guard DemoStore.shared.isActive || SupabaseManager.client != nil else {
            members = []
            return
        }
        do {
            let me = PhotoRepository.currentUserID
            members = try await ChatRepository.fetchMembers(folderID: folder.id)
                .filter { $0.userID != me }
                .sorted { $0.nickname < $1.nickname }
        } catch is CancellationError {
        } catch {
            members = []
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await ChatRepository.send(
                id: UUID(),
                folderID: folder.id,
                body: String(trimmedQuestion.prefix(ChatRepository.maxBodyLength)),
                photoIDs: Array(photos.map(\.id).prefix(ChatRepository.maxPhotos)),
                recipientIDs: Array(recipients)
            )
            onSent()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 사진 묶음을 누르면 뜨는 크게 보기. 옆으로 넘기며 한 장씩 보고,
/// 사진을 위로 올리면 아래에 휴지통이 나와서 고른 사진에서 뺄 수 있음.
/// Figma: 사진묶음 눌렀을 때 (512:10294) — 흰 90% 덮개 + 가로 꽉 찬 3:4 사진 (모서리 20)
///
/// 옆으로 넘기기(바깥 가로 스크롤)와 위로 올리기(장마다 세로 스크롤)를 둘 다 스크롤로 두어
/// 방향 구분은 시스템이 해 줌.
private struct QuestionPhotoViewer: View {
    let photos: [PhotoItem]
    let onRemove: (PhotoItem) -> Void
    let onClose: () -> Void

    @State private var currentID: UUID?

    var body: some View {
        ZStack {
            Color.white.opacity(0.9)
                .ignoresSafeArea()

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(photos) { photo in
                        RaisablePhotoPage(
                            photo: photo,
                            isCurrent: (currentID ?? photos.first?.id) == photo.id,
                            onRemove: { onRemove(photo) },
                            onClose: onClose
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
    }
}

/// 크게 보기 한 장. 위로 밀면 사진이 올라가며 아래에 휴지통이 나옴
private struct RaisablePhotoPage: View {
    let photo: PhotoItem
    /// 지금 보고 있는 장인지 (다른 장으로 넘어가면 내려놓음)
    let isCurrent: Bool
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var position = ScrollPosition(edge: .top)
    /// 위로 올라간 만큼 (0 ~ raise)
    @State private var lift: CGFloat = 0

    /// 사진이 올라가는 높이 (휴지통 자리)
    private let raise: CGFloat = 104
    private let trashSize: CGFloat = 52

    private var progress: CGFloat { min(1, max(0, lift / raise)) }

    var body: some View {
        GeometryReader { proxy in
            let photoHeight = proxy.size.width * 4 / 3
            let topSpace = max(0, (proxy.size.height - photoHeight) / 2)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // 사진 밖(위·아래 여백)을 누르면 닫힘
                    closeArea.frame(height: topSpace)

                    FolderPhoto(url: photo.url, cornerRadius: 20)
                        .frame(width: proxy.size.width, height: photoHeight)
                        .onTapGesture {
                            // 올려 둔 사진을 누르면 내려놓음
                            if lift > 1 { lower() }
                        }
                        .accessibilityLabel("사진")
                        .accessibilityAction(named: "고른 사진에서 빼기", onRemove)

                    ZStack(alignment: .top) {
                        closeArea
                        trashButton
                            .padding(.top, (raise - trashSize) / 2)
                            .opacity(progress)
                            .scaleEffect(0.7 + 0.3 * progress)
                            .allowsHitTesting(progress > 0.9)
                    }
                    .frame(height: topSpace + raise)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollTargetBehavior(RaiseSnap(raise: raise))
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                lift = y
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lift >= raise - 1) { _, raised in raised }
        .onChange(of: isCurrent) { _, current in
            if !current { lower(animated: false) }
        }
    }

    private var closeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }

    private var trashButton: some View {
        Button(action: onRemove) {
            Image(.iconDelete)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.black800)
                .frame(width: trashSize, height: trashSize)
                .background(.white, in: Circle())
                .overlay { Circle().strokeBorder(Color.black800, lineWidth: 1.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("고른 사진에서 빼기")
    }

    private func lower(animated: Bool = true) {
        if animated {
            withAnimation(.snappy(duration: 0.25)) { position.scrollTo(y: 0) }
        } else {
            position.scrollTo(y: 0)
        }
    }
}

/// 세로로 밀다 놓으면 제자리(0) 또는 올린 자리(raise) 둘 중 하나로 멈춤
private struct RaiseSnap: ScrollTargetBehavior {
    let raise: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.minY
        target.rect.origin.y = y > raise / 2 ? raise : 0
    }
}

/// 고른 사진 3장을 겹쳐 꽂은 그림 (Figma folder 138:6731, 이름 없이)
private struct PhotoStack: View {
    let urls: [URL?]

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo(1, size: CGSize(width: 93.7, height: 119.7), at: CGPoint(x: 56, y: 0), rotation: 6)
            photo(0, size: CGSize(width: 93.7, height: 119.7), at: CGPoint(x: 0, y: 13), rotation: -6)
            photo(2, size: CGSize(width: 86, height: 114), at: CGPoint(x: 32, y: 41), rotation: 0)
        }
        .frame(width: 150, height: 155, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("고른 사진")
    }

    @ViewBuilder
    private func photo(_ index: Int, size: CGSize, at origin: CGPoint, rotation: Double) -> some View {
        // 사진이 1~2장이면 앞쪽부터 채우고 남는 자리는 비워 둠
        let order = [2, 0, 1]
        if let slot = order.firstIndex(of: index), slot < max(urls.count, 1) {
            FolderPhoto(url: urls[safe: slot] ?? nil, cornerRadius: 10)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(rotation))
                .offset(x: origin.x, y: origin.y)
        }
    }
}

/// 보낼 사람 한 줄 (사람선택_선택안함 512:10375 / 사람선택_선택함 512:10374)
private struct RecipientRow: View {
    let member: ChatMember
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AppImage(url: member.avatarURL.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(.defaultAvatar).resizable().scaledToFill()
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                Text(member.nickname)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black800)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(.iconCheck)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.black400)
                        .transition(.opacity)
                }
            }
            .padding(10)
            .background(isSelected ? Color.black100 : .white, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    QuestionComposeView(folder: Folder.previews[0], photos: [])
}
