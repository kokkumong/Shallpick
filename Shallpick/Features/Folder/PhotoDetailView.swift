import SwiftUI
import UIKit

/// 폴더 그리드에서 사진을 누르면 들어가는 화면. 옆으로 넘겨 다른 사진을 봄
/// 사진 아래: 이모지 반응 + 사진에 대한 생각(댓글), 맨 아래: 생각 남기기 입력창
/// Figma: 사진 클릭시 (540:10918)
struct PhotoDetailView: View {
    let folder: Folder
    let photos: [PhotoItem]
    var avatarURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID?
    /// 사진 id → 반응/댓글
    @State private var feedback: [UUID: PhotoFeedback] = [:]
    @State private var members: [UUID: ChatMember] = [:]
    @State private var drafts: [UUID: String] = [:]
    @State private var pendingComments: [UUID: (id: UUID, body: String)] = [:]
    @State private var sendingPhotos: Set<UUID> = []
    @AppStorage("photo.commentSharingHintSeen") private var sharingHintSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 방금 내가 남긴 댓글 (그 자리로 스크롤)
    @State private var lastSentCommentID: UUID?
    @State private var isShowingInvite = false
    @State private var isShowingQuestionCompose = false
    @State private var isSaving = false
    @State private var notice: String?
    @State private var errorMessage: String?
    /// 댓글 입력창에 키보드가 올라와 있는지
    @FocusState private var isCommentFocused: Bool

    init(folder: Folder, photos: [PhotoItem], startID: UUID, avatarURL: URL? = nil, commentID: UUID? = nil) {
        self.folder = folder
        self.photos = photos
        self.avatarURL = avatarURL
        _currentID = State(initialValue: startID)
        _lastSentCommentID = State(initialValue: commentID)
    }

    private var currentPhoto: PhotoItem? {
        photos.first { $0.id == currentID } ?? photos.first
    }

    private var myUserID: UUID? { PhotoRepository.currentUserID }

    var body: some View {
        pager
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            // 키보드 바깥을 누르면 키보드 내림 (사진 두 번 탭·스크롤은 그대로)
            .simultaneousGesture(TapGesture().onEnded { isCommentFocused = false })
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .simultaneousGesture(TapGesture().onEnded { isCommentFocused = false })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .overlay(alignment: .top) { noticeBanner }
            .overlay {
                if isShowingInvite {
                    FolderInvitePopup(folder: folder) { isShowingInvite = false }
                }
            }
            .animation(.snappy(duration: 0.25), value: isShowingInvite)
            .animation(.snappy(duration: 0.2), value: notice)
            .animation(.snappy(duration: 0.2), value: isSaving)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isShowingQuestionCompose) {
                if let currentPhoto {
                    QuestionComposeView(folder: folder, photos: [currentPhoto], onSent: {
                        showNotice("질문을 보냈어요")
                    })
                }
            }
            .alert(
                "문제가 생겼어요",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await loadMembers() }
            .task(id: currentID) {
                if let currentID { await loadFeedback(photoID: currentID) }
            }
            .onChange(of: currentID) { _, _ in isCommentFocused = false }
    }

    private var commentDraft: Binding<String> {
        Binding(
            get: { currentPhoto.flatMap { drafts[$0.id] } ?? "" },
            set: { if let id = currentPhoto?.id { drafts[id] = $0 } }
        )
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !sharingHintSeen, isCommentFocused {
                HStack {
                    Text("댓글은 폴더 채팅에도 공유돼요")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black600)
                    Spacer(minLength: 0)
                    Button("확인") { sharingHintSeen = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black800)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .background(.regularMaterial, in: Capsule())
            }
            HStack(alignment: .bottom, spacing: 12) {
                PhotoCommentInputBar(
                    text: commentDraft, isFocused: $isCommentFocused,
                    isSending: currentPhoto.map { sendingPhotos.contains($0.id) } ?? false,
                    onSend: sendComment
                )
                OtterButton(accessibilityLabel: "이 사진으로 질문 보내기") {
                    guard currentPhoto != nil else { return }
                    isCommentFocused = false
                    isShowingQuestionCompose = true
                }
                .accessibilityIdentifier("photoDetail.ask")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, isCommentFocused ? 10 : 33)
        .background { BottomFade() }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isCommentFocused)
    }

    // MARK: - 사진 넘기기

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(photos) { photo in
                    PhotoDetailPage(
                        photo: photo,
                        feedback: feedback[photo.id] ?? PhotoFeedback(),
                        members: members,
                        myUserID: myUserID,
                        scrollToCommentID: lastSentCommentID,
                        onDoubleTap: { toggleReaction(PhotoFeedbackRepository.heart, on: photo) },
                        onToggleReaction: { emoji in toggleReaction(emoji, on: photo) },
                        onDeleteComment: { comment in deleteComment(comment) }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(photo.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        // 위아래로 늘어난 댓글이 머리/입력창 그라데이션 밑으로 보이게
        .scrollClipDisabled()
    }

    // MARK: - 상단: 뒤로 / 폴더 이름 ⌄ / 저장

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "뒤로") { dismiss() }

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

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconDownload, accessibilityLabel: "사진 저장") {
                    Task { await saveCurrent() }
                }
                .disabled(isSaving)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background(alignment: .top) { TopFade() }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if isSaving || notice != nil {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text("사진 저장 중")
                } else if let notice {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                    Text(notice)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black800)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .shadowedBackground(.white, in: Capsule(), blur: 20)
            .padding(.top, 74)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if notice == text { notice = nil }
        }
    }

    // MARK: - 불러오기

    private func loadMembers() async {
        guard DemoStore.shared.isActive || SupabaseManager.client != nil else { return }
        do {
            let list = try await ChatRepository.fetchMembers(folderID: folder.id)
            members = Dictionary(list.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            // 이름을 못 불러와도 댓글은 "샬픽 사용자" 로 보임
        }
    }

    private func loadFeedback(photoID: UUID) async {
        guard DemoStore.shared.isActive || SupabaseManager.client != nil else { return }
        do {
            async let reactions = PhotoFeedbackRepository.fetchReactions(photoID: photoID)
            async let comments = PhotoFeedbackRepository.fetchComments(photoID: photoID)
            let loaded = PhotoFeedback(reactions: try await reactions, comments: try await comments, isLoaded: true)
            feedback[photoID] = loaded
        } catch is CancellationError {
        } catch {
            if feedback[photoID]?.isLoaded != true {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 반응

    /// 반응 칩 / 이모지 고르기 / 사진 두 번 누르기(하트): 내가 남겼으면 지우고, 아니면 남김
    private func toggleReaction(_ emoji: String, on photo: PhotoItem) {
        guard let me = myUserID else { return }
        let isMine = feedback[photo.id]?.reactions.contains { $0.userID == me && $0.emoji == emoji } == true
        setReaction(emoji, on: photo, isOn: !isMine)
    }

    /// 화면에 먼저 반영하고 저장. 실패하면 되돌림
    private func setReaction(_ emoji: String, on photo: PhotoItem, isOn: Bool) {
        guard let me = myUserID else { return }
        let before = feedback[photo.id] ?? PhotoFeedback()
        var after = before
        if isOn {
            after.reactions.append(PhotoReaction(photoID: photo.id, userID: me, emoji: emoji, createdAt: .now))
        } else {
            after.reactions.removeAll { $0.userID == me && $0.emoji == emoji }
        }
        withAnimation(.snappy(duration: 0.2)) { feedback[photo.id] = after }

        Task {
            do {
                if isOn {
                    try await PhotoFeedbackRepository.addReaction(photoID: photo.id, emoji: emoji)
                } else {
                    try await PhotoFeedbackRepository.removeReaction(photoID: photo.id, emoji: emoji)
                }
            } catch {
                withAnimation(.snappy(duration: 0.2)) { feedback[photo.id] = before }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 댓글

    private func sendComment() {
        guard let photo = currentPhoto, let me = myUserID else { return }
        guard !sendingPhotos.contains(photo.id) else { return }
        let text = drafts[photo.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        // Reuse the request ID, but send the text currently shown in the field.
        let pending = (id: pendingComments[photo.id]?.id ?? UUID(), body: text)
        guard !pending.body.isEmpty else { return }
        pendingComments[photo.id] = pending
        sendingPhotos.insert(photo.id)

        Task {
            defer { sendingPhotos.remove(photo.id) }
            do {
                let saved = try await PhotoFeedbackRepository.addComment(id: pending.id, photoID: photo.id, body: pending.body)
                guard saved.userID == me else { return }
                if !feedback[photo.id, default: PhotoFeedback()].comments.contains(where: { $0.id == saved.id }) {
                    feedback[photo.id, default: PhotoFeedback()].comments.append(saved)
                }
                if drafts[photo.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) == saved.body {
                    drafts[photo.id] = ""
                }
                if saved.body != pending.body {
                    showNotice("이전 댓글은 저장됐어요. 수정한 내용은 입력창에 남겨뒀어요.")
                }
                pendingComments[photo.id] = nil
                sharingHintSeen = true
                if currentPhoto?.id == photo.id { lastSentCommentID = saved.id }
            } catch {
                errorMessage = "댓글을 저장하지 못했어요. 입력은 유지했어요. 전송 버튼을 눌러 다시 시도해 주세요."
            }
        }
    }

    private func deleteComment(_ comment: PhotoComment) {
        guard comment.userID == myUserID else { return }
        let before = feedback[comment.photoID]
        withAnimation(.snappy(duration: 0.2)) {
            feedback[comment.photoID]?.comments.removeAll { $0.id == comment.id }
        }
        Task {
            do {
                try await PhotoFeedbackRepository.deleteComment(id: comment.id)
            } catch {
                withAnimation(.snappy(duration: 0.2)) { feedback[comment.photoID] = before }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 저장

    private func saveCurrent() async {
        guard let photo = currentPhoto, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoRepository.saveToLibrary([photo])
            isSaving = false
            showNotice("사진을 저장했어요")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 사진 한 장에 남은 반응과 댓글
struct PhotoFeedback: Equatable {
    var reactions: [PhotoReaction] = []
    var comments: [PhotoComment] = []
    var isLoaded = false

    /// 이모지별 묶음 (처음 남긴 순)
    struct ReactionGroup: Identifiable, Equatable {
        let emoji: String
        var userIDs: [UUID]
        var id: String { emoji }
    }

    var reactionGroups: [ReactionGroup] {
        var groups: [ReactionGroup] = []
        for reaction in reactions {
            if let index = groups.firstIndex(where: { $0.emoji == reaction.emoji }) {
                groups[index].userIDs.append(reaction.userID)
            } else {
                groups.append(ReactionGroup(emoji: reaction.emoji, userIDs: [reaction.userID]))
            }
        }
        return groups
    }
}

// MARK: - 한 장

private struct PhotoDetailPage: View {
    let photo: PhotoItem
    let feedback: PhotoFeedback
    let members: [UUID: ChatMember]
    let myUserID: UUID?
    let scrollToCommentID: UUID?
    /// 하트 켜고 끄기
    let onDoubleTap: () -> Void
    let onToggleReaction: (String) -> Void
    let onDeleteComment: (PhotoComment) -> Void

    /// 두 번 눌렀을 때 가운데 크게 떴다 사라지는 하트
    @State private var heartBurst = 0
    @State private var isShowingHeart = false
    /// 머리와 입력창 사이에 보이는 높이, 사진 높이 (사진을 가운데 두려고 잼)
    @State private var visibleHeight: CGFloat = 0
    @State private var photoHeight: CGFloat = 0
    /// 사진이 가운데에서 얼마나 올라갔는지 (위로 민 거리)
    @State private var scrolledUp: CGFloat = 0

    private struct CommentScrollRequest: Equatable {
        let id: UUID?
        let commentIDs: [UUID]
        let photoHeight: CGFloat
        let visibleHeight: CGFloat
    }

    private var commentScrollRequest: CommentScrollRequest {
        CommentScrollRequest(id: scrollToCommentID, commentIDs: feedback.comments.map(\.id),
                             photoHeight: photoHeight, visibleHeight: visibleHeight)
    }

    /// 0 = 사진이 가운데 (댓글은 흐리게), 1 = 사진이 맨 위로 올라감 (댓글 또렷하게)
    private var commentReveal: CGFloat {
        guard topSpace > 0 else { return 1 }
        return min(max(scrolledUp / topSpace, 0), 1)
    }

    /// 사진은 늘 보이는 칸 가운데에서 시작
    private var topSpace: CGFloat {
        guard photoHeight > 0 else { return 0 }
        return max(0, (visibleHeight - photoHeight) / 2)
    }

    /// 댓글이 있으면 짧아도 사진이 맨 위까지 올라갈 만큼 아래 칸을 채움 (20 은 맨 아래 여백)
    private var belowPhotoMinHeight: CGFloat {
        guard !feedback.comments.isEmpty, photoHeight > 0 else { return 0 }
        return max(0, visibleHeight - photoHeight - 20)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photoView
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { photoHeight = $0 }
                        .padding(.top, topSpace)

                    VStack(alignment: .leading, spacing: 0) {
                        // 사진 아래 끝에 살짝 걸침 (540:10933)
                        PhotoReactionRow(
                            groups: feedback.reactionGroups,
                            myUserID: myUserID,
                            members: members,
                            onToggle: onToggleReaction
                        )
                        .padding(.horizontal, 21)
                        .padding(.top, -14)

                        PhotoCommentList(
                            comments: feedback.comments,
                            members: members,
                            myUserID: myUserID,
                            onDelete: onDeleteComment
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        // 사진이 가운데 있을 땐 아래로 갈수록 흐려지고 살짝 번져서 사진에 눈이 가게,
                        // 위로 밀수록 또렷해짐
                        .blur(radius: (1 - commentReveal) * 2.5)
                        .mask { CommentRevealMask(reveal: commentReveal) }
                    }
                    .frame(minHeight: belowPhotoMinHeight, alignment: .top)
                }
                // Keep the last comment above the floating input, including when
                // opening a comment directly from chat.
                .padding(.bottom, feedback.comments.isEmpty ? 20 : 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollClipDisabled()
            // 머리와 입력창은 안전 영역으로 빠져 있어서 containerSize 가 그 사이 높이
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                visibleHeight = height
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrolledUp = offset
            }
            .animation(.snappy(duration: 0.35), value: feedback.comments.isEmpty)
            .task(id: commentScrollRequest) {
                guard let id = scrollToCommentID, photoHeight > 0, visibleHeight > 0,
                      feedback.comments.contains(where: { $0.id == id }) else { return }
                // The remote photo and lazy comment rows finish layout after the
                // data arrives. A layout change cancels and reschedules this task.
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var photoView: some View {
        DetailPhotoImage(url: photo.url)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12)
                    .scaleEffect(isShowingHeart ? 1 : 0.4)
                    .opacity(isShowingHeart ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // 하트를 남길 때만 가운데에 크게 띄우고, 지울 때는 바로 숨김
                let wasHearted = isHearted
                onDoubleTap()
                if wasHearted { hideHeart() } else { showHeart() }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: heartBurst)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("사진")
            .accessibilityAction(named: isHearted ? "하트 지우기" : "하트 남기기") { onDoubleTap() }
    }

    private var isHearted: Bool {
        guard let myUserID else { return false }
        return feedback.reactions.contains { $0.userID == myUserID && $0.emoji == PhotoFeedbackRepository.heart }
    }

    private func hideHeart() {
        heartBurst += 1
        withAnimation(.easeOut(duration: 0.15)) { isShowingHeart = false }
    }

    private func showHeart() {
        heartBurst += 1
        let burst = heartBurst
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { isShowingHeart = true }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            guard burst == heartBurst else { return }
            withAnimation(.easeOut(duration: 0.25)) { isShowingHeart = false }
        }
    }
}

/// 댓글 목록에 씌우는 가림막. reveal 0 이면 위는 반쯤 보이고 아래로 갈수록 사라지며, 1 이면 전부 보임
private struct CommentRevealMask: View {
    let reveal: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.55 + 0.45 * reveal), .black.opacity(reveal)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            Color.black.opacity(reveal)
        }
    }
}

/// 화면 너비에 맞춘 사진 (모서리 30). 세로는 사진 비율대로 하되 4:3 ~ 3:4 사이로 맞춤
private struct DetailPhotoImage: View {
    let url: URL?

    @State private var image: UIImage?

    private var aspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return 3 / 4 }
        return min(max(image.size.width / image.size.height, 3 / 4), 4 / 3)
    }

    var body: some View {
        Color.blue50
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .task(id: url) {
                guard let url, image == nil else { return }
                if url.scheme == "demo-asset" { image = UIImage(named: url.lastPathComponent); return }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let loaded = await Self.decode(data)
                else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        UIImage(data: data)?.preparingForDisplay()
    }
}

// MARK: - 반응 (540:10933)

private struct PhotoReactionRow: View {
    let groups: [PhotoFeedback.ReactionGroup]
    let myUserID: UUID?
    let members: [UUID: ChatMember]
    let onToggle: (String) -> Void

    @State private var isPicking = false

    var body: some View {
        FlowLayout(spacing: 2) {
            ForEach(groups) { group in
                chip(group)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            addButton
        }
    }

    private func chip(_ group: PhotoFeedback.ReactionGroup) -> some View {
        let isMine = myUserID.map(group.userIDs.contains) ?? false
        return Button { onToggle(group.emoji) } label: {
            HStack(spacing: 6) {
                Text(group.emoji)
                Text("\(group.userIDs.count)")
                    .foregroundStyle(Color.black800)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 9)
            .frame(minWidth: 48, minHeight: 36)
            .background(isMine ? Color.blue100 : Color.black200, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.black50, lineWidth: 3) }
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(group.userIDs, id: \.self) { userID in
                Text(members[userID]?.nickname ?? "샬픽 사용자")
            }
        }
        .accessibilityLabel("\(group.emoji) \(group.userIDs.count)명")
        .accessibilityAddTraits(isMine ? .isSelected : [])
        .accessibilityHint(isMine ? "누르면 내 반응을 지워요" : "누르면 같은 반응을 남겨요")
    }

    /// 이모지 추가 (540:11053)
    private var addButton: some View {
        Button { isPicking = true } label: {
            Image(.iconEmojiAdd)
                .resizable()
                .scaledToFit()
                .frame(width: 19.5, height: 20.75)
                .foregroundStyle(Color.black800)
                .frame(width: 48, height: 36)
                .background(Color.black200, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.black50, lineWidth: 3) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("반응 남기기")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            EmojiPalette(
                selected: Set(groups.filter { group in myUserID.map(group.userIDs.contains) ?? false }.map(\.emoji))
            ) { emoji in
                isPicking = false
                onToggle(emoji)
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// 이모지 추가 버튼을 누르면 뜨는 고르기 (Figma 에 없는 부분)
private struct EmojiPalette: View {
    let selected: Set<String>
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PhotoFeedbackRepository.palette, id: \.self) { emoji in
                let isOn = selected.contains(emoji)
                Button { onPick(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 40, height: 40)
                        .background(isOn ? Color.blue100 : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// 줄이 넘치면 다음 줄로 (반응이 많을 때)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = row.indices.isEmpty ? size.width : spacing + size.width
            if !row.indices.isEmpty, row.width + extra > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width += row.indices.isEmpty ? size.width : spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - 댓글 (인스타그램 댓글 참고: 프로필 / 이름 + 글 / 남긴 시간, 구분선)

private struct PhotoCommentList: View {
    let comments: [PhotoComment]
    let members: [UUID: ChatMember]
    let myUserID: UUID?
    let onDelete: (PhotoComment) -> Void

    var body: some View {
        // 시간 글자("n분 전")가 저절로 바뀌게 1분마다 다시 그림
        TimelineView(.everyMinute) { context in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                    if index > 0 {
                        Divider().overlay(Color.black200)
                    }
                    PhotoCommentRow(
                        comment: comment,
                        member: members[comment.userID],
                        now: context.date
                    )
                    .id(comment.id)
                    .contextMenu {
                        if comment.userID == myUserID {
                            Button("삭제", systemImage: "trash", role: .destructive) { onDelete(comment) }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct PhotoCommentRow: View {
    let comment: PhotoComment
    let member: ChatMember?
    let now: Date

    private var nickname: String { member?.nickname ?? "샬픽 사용자" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppImage(url: member?.avatarURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(.defaultAvatar).resizable().scaledToFill()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(nickname).fontWeight(.semibold))  \(comment.body)")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black800)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RelativeTimeText.format(comment.createdAt, now: max(now, comment.createdAt)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photoComment.\(comment.id.uuidString)")
    }
}

// MARK: - 입력창 (채팅창(new) 512:8424)

private struct PhotoCommentInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("댓글 남기기", text: $text, axis: .vertical)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.black800)
                .lineLimit(1...5)
                .frame(minHeight: 30)
                .padding(.leading, 12)
                .padding(.vertical, 7.5)
                .focused(isFocused)
                .disabled(isSending)
                .accessibilityIdentifier("photoDetail.commentInput")
                .onChange(of: text) { _, newValue in
                    if newValue.count > PhotoFeedbackRepository.maxCommentLength {
                        text = String(newValue.prefix(PhotoFeedbackRepository.maxCommentLength))
                    }
                }

            Button(action: onSend) {
                Image(systemName: isSending ? "ellipsis" : "arrow.up")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 16)
                    .foregroundStyle(canSend ? Color.white : Color.black400)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.black800 : Color.black200, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.snappy(duration: 0.15), value: canSend)
            .accessibilityLabel(isSending ? "댓글 저장 중" : "댓글 남기기")
            .accessibilityIdentifier("photoDetail.sendComment")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0.5)
        .frame(minHeight: 45)
        .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 22.5), blur: 20)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PhotoDetailView(
            folder: Folder.previews[0],
            photos: PhotoItem.previews,
            startID: PhotoItem.previews[2].id
        )
    }
}
