import SwiftUI

/// 다른 사람의 사진 질문에서 "확인하러가기"를 누르면 들어오는 화면
/// 좌우로 넘기며 사진을 보고, 위로 올리면 싫어 / 아래로 내리면 좋아 (사진이 날아가고 다음 사진),
/// 사진의 한 점을 길게 누르면 그 자리에 댓글을 남김
/// Figma: 요청응답 (540:11455), 요청응답_가이드 (549:11607) — "사진 답장하기" 입력창은 뺌
struct QuestionRespondView: View {
    let folder: Folder
    let message: ChatMessage
    let photos: [PhotoItem]
    /// 질문한 사람 (위 작은 프로필 + 이름)
    let sender: ChatMember?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("question.pinGuideSeen") private var pinGuideSeen = false

    @State private var index = 0
    /// 모든 사진에 좋아/싫어를 남겨서 마무리 카드를 보는 중
    @State private var isShowingDone = false
    @State private var votes: [UUID: QuestionVote] = [:]
    /// 내가 남긴 댓글
    @State private var pins: [QuestionPin] = []

    // 넘기기
    @State private var drag: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var pageStep = 1
    /// 지금 누르고 있는 손가락이 처음 닿은 곳 (새 손가락인지 가림)
    @State private var touchStart: CGPoint?
    /// 손가락이 떨어지거나 시스템이 제스처를 취소하면 false 로 돌아옴
    @GestureState private var isPressing = false
    /// 좋아/싫어로 사진이 날아가는 중
    @State private var isVoting = false
    @State private var didLongPress = false
    @State private var longPressTask: Task<Void, Never>?

    // 댓글
    @State private var draftPin: DraftPin?
    @State private var draftText = ""
    @State private var selectedPinID: UUID?
    @FocusState private var isInputFocused: Bool

    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSendingPin = false
    @State private var draftPinID = UUID()

    private struct DraftPin: Equatable {
        let photoID: UUID
        let x: Double
        let y: Double
    }

    /// 이만큼 위/아래로 넘기면 좋아/싫어
    private let voteThreshold: CGFloat = 110
    /// 이만큼 옆으로 넘기면 다음/이전 사진
    private let pageThreshold: CGFloat = 70

    private var myUserID: UUID? { PhotoRepository.currentUserID }

    private var currentPhoto: PhotoItem? {
        guard !isShowingDone, photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    private var allVoted: Bool {
        !photos.isEmpty && photos.allSatisfy { votes[$0.id] != nil }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                QuestionHeader(
                    title: folder.name,
                    avatarURL: sender?.avatarURL.flatMap(URL.init(string:)),
                    subtitle: sender?.nickname ?? "",
                    onDone: { if !isVoting && !isSendingPin { dismiss() } }
                )

                GeometryReader { proxy in
                    content(in: proxy.size)
                        .allowsHitTesting(!isLoading && !loadFailed && !isSendingPin)
                        .overlay {
                            if isLoading || isVoting { ProgressView(isVoting ? "의견 저장 중" : "불러오는 중").padding().background(.regularMaterial, in: Capsule()) }
                            else if loadFailed { Button("답변 불러오기 다시 시도") { Task { await load() } }
                                .padding().background(.regularMaterial, in: Capsule()) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.keyboard)

            if draftPin != nil {
                pinInputBar.disabled(isSendingPin)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black50)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy(duration: 0.2), value: draftPin)
        .sensoryFeedback(.impact(weight: .light), trigger: votes)
        .sensoryFeedback(.impact(weight: .medium), trigger: draftPin) { _, new in new != nil }
        .task { await load() }
        .onDisappear { longPressTask?.cancel() }
        // 제스처가 끝나지 못하고 취소돼도 상태를 되돌림
        .onChange(of: isPressing) { _, pressing in
            guard !pressing else { return }
            longPressTask?.cancel()
            touchStart = nil
            dragAxis = nil
            if !isVoting, drag != .zero {
                withAnimation(.snappy) { drag = .zero }
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
    }

    // MARK: - 가운데: 싫어 / 사진 / 좋아

    private var photoTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: CGFloat(pageStep) * 32).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func content(in available: CGSize) -> some View {
        // 위아래 라벨(46) + 간격(20) 두 번, 아래 여백 24
        let photoSize = QuestionPhotoLayout.size(
            width: available.width - 60,
            maxHeight: available.height - 2 * (46 + 20) - 24
        )
        let progress = drag.height / voteThreshold

        return VStack(spacing: 20) {
            QuestionVoteLabel(
                vote: .dislike,
                emphasis: min(max(-progress, 0), 1),
                isChosen: currentPhoto.map { votes[$0.id] == .dislike } ?? false
            )

            HStack(spacing: 11) {
                QuestionChevronButton(direction: .previous, isEnabled: canPage(-1)) { page(-1) }
                photoArea(size: photoSize)
                QuestionChevronButton(direction: .next, isEnabled: canPage(1)) { page(1) }
            }

            QuestionVoteLabel(
                vote: .like,
                emphasis: min(max(progress, 0), 1),
                isChosen: currentPhoto.map { votes[$0.id] == .like } ?? false
            )
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func photoArea(size: CGSize) -> some View {
        ZStack {
            if let photo = currentPhoto {
                photoCard(photo, size: size)
                    .id(photo.id)
                    .transition(photoTransition)
            } else if isShowingDone {
                doneCard
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func photoCard(_ photo: PhotoItem, size: CGSize) -> some View {
        let photoPins = pins.filter { $0.photoID == photo.id }
        let flyDistance = abs(drag.height)

        return ZStack(alignment: .topLeading) {
            QuestionPhotoImage(url: photo.url)
                .frame(width: size.width, height: size.height)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .gesture(photoGesture(photo: photo, size: size))
                .accessibilityAction(named: "좋아") { vote(.like, photo: photo) }
                .accessibilityAction(named: "싫어") { vote(.dislike, photo: photo) }

            if let vote = votes[photo.id] {
                voteBadge(vote)
                    .padding(14)
                    .allowsHitTesting(false)
            }

            ForEach(photoPins) { pin in
                pinDot(pin)
                    .position(x: pin.x * size.width, y: pin.y * size.height)
            }

            if let draftPin, draftPin.photoID == photo.id {
                QuestionPinDot(isHighlighted: true)
                    .position(x: draftPin.x * size.width, y: draftPin.y * size.height)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }

            if let pin = photoPins.first(where: { $0.id == selectedPinID }) {
                QuestionPinBubble(point: CGPoint(x: pin.x * size.width, y: pin.y * size.height), bounds: size) {
                    Text(pin.body)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black800)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // 처음 들어왔을 때만: 길게 눌러 댓글 남기기 안내 (요청응답_가이드)
            if !pinGuideSeen, draftPin == nil, photoPins.isEmpty, drag == .zero {
                pinGuide(size: size)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(reduceMotion ? .zero : drag)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 100), anchor: .bottom)
        .opacity(1 - min(flyDistance / 700, 1) * 0.9)
        .animation(.snappy(duration: 0.2), value: selectedPinID)
    }

    private func voteBadge(_ vote: QuestionVote) -> some View {
        HStack(spacing: 4) {
            Image(vote == .like ? .iconLike : .iconDislike)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text(vote.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.black800)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.white.opacity(0.92), in: Capsule())
        .accessibilityLabel("내가 남긴 의견: \(vote.label)")
    }

    private func pinDot(_ pin: QuestionPin) -> some View {
        Button {
            selectedPinID = selectedPinID == pin.id ? nil : pin.id
        } label: {
            QuestionPinDot(isHighlighted: selectedPinID == pin.id)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("내 댓글: \(pin.body)")
        .contextMenu {
            Button("댓글 지우기", systemImage: "trash", role: .destructive) {
                Task { await deletePin(pin) }
            }
        }
    }

    /// "사진을 길게 눌러서 댓글을 남겨보세요" + 점 (가이드: 사진 아래쪽 가운데)
    private func pinGuide(size: CGSize) -> some View {
        let point = CGPoint(x: size.width / 2, y: size.height * 0.86)
        return ZStack {
            QuestionPinDot()
                .position(point)
            QuestionPinBubble(point: CGPoint(x: point.x, y: point.y - 14), bounds: size) {
                Text("사진을 길게 눌러서 댓글을 남겨보세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black800)
                    .fixedSize()
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 모든 사진에 의견을 남기면 나오는 카드
    private var doneCard: some View {
        VStack(spacing: 14) {
            Image(.otterMascot)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("모든 사진에 의견을 남겼어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("체크를 눌러 마무리하거나\n사진을 다시 넘겨 의견을 바꿀 수 있어요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 그림자는 바탕에만 (글자에 번지지 않게)
            RoundedRectangle(cornerRadius: 20).fill(.white).shallpickShadow(blur: 20)
        }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.width > pageThreshold { page(-1) }
            }
        )
    }

    // MARK: - 댓글 입력 (길게 눌렀을 때만)

    private var pinInputBar: some View {
        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            Button(action: cancelDraft) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black400)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 취소")

            TextField("이 자리에 남길 댓글을 입력하세요", text: $draftText, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black800)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .frame(minHeight: 30)
                .onChange(of: draftText) { _, newValue in
                    if newValue.count > QuestionResponseRepository.maxPinLength {
                        draftText = String(newValue.prefix(QuestionResponseRepository.maxPinLength))
                    }
                }
                .onSubmit(sendPin)

            Button(action: sendPin) {
                Image(.iconArrowUp)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 16)
                    .foregroundStyle(canSend ? Color.white : Color.black400)
                    .frame(width: 44, height: 30)
                    .background(canSend ? Color.black800 : Color.black200, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("댓글 남기기")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .frame(minHeight: 45)
        .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 22.5), blur: 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    // MARK: - 손가락

    /// 가만히 길게 누르면 댓글 자리, 움직이면 처음 방향으로 넘기기 (옆: 사진 넘기기, 위아래: 좋아/싫어)
    private func photoGesture(photo: PhotoItem, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressing) { _, pressing, _ in pressing = true }
            .onChanged { value in
                guard !isVoting else { return }
                if touchStart != value.startLocation {
                    touchStart = value.startLocation
                    didLongPress = false
                    dragAxis = nil
                    let location = value.startLocation
                    longPressTask = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        didLongPress = true
                        placeDraft(at: location, in: size, photo: photo)
                    }
                }
                guard !didLongPress else { return }

                let translation = value.translation
                if dragAxis == nil {
                    guard hypot(translation.width, translation.height) > 10 else { return }
                    longPressTask?.cancel()
                    // 댓글을 쓰는 중에는 넘기지 않음
                    guard draftPin == nil else { return }
                    dragAxis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
                    selectedPinID = nil
                }
                switch dragAxis {
                case .horizontal:
                    let step = translation.width < 0 ? 1 : -1
                    // 더 넘길 사진이 없으면 고무줄처럼 조금만
                    drag = CGSize(width: translation.width * (canPage(step) ? 1 : 0.25), height: 0)
                case .vertical:
                    drag = CGSize(width: 0, height: translation.height)
                case nil:
                    break
                }
            }
            .onEnded { value in
                longPressTask?.cancel()
                touchStart = nil
                let axis = dragAxis
                dragAxis = nil
                if didLongPress {
                    didLongPress = false
                    return
                }

                switch axis {
                case .vertical:
                    let distance = value.translation.height
                    let predicted = value.predictedEndTranslation.height
                    if distance < -voteThreshold || predicted < -voteThreshold * 2 {
                        vote(.dislike, photo: photo)
                    } else if distance > voteThreshold || predicted > voteThreshold * 2 {
                        vote(.like, photo: photo)
                    } else {
                        withAnimation(.snappy) { drag = .zero }
                    }
                case .horizontal:
                    let distance = value.translation.width
                    if distance < -pageThreshold, canPage(1) {
                        page(1)
                    } else if distance > pageThreshold, canPage(-1) {
                        page(-1)
                    } else {
                        withAnimation(.snappy) { drag = .zero }
                    }
                case nil:
                    // 짧게 톡: 쓰던 댓글이나 열린 댓글을 닫음
                    if draftPin != nil {
                        cancelDraft()
                    } else {
                        selectedPinID = nil
                    }
                }
            }
    }

    private func canPage(_ step: Int) -> Bool {
        guard !isVoting, !isLoading, !loadFailed, !isSendingPin else { return false }
        if step < 0 {
            return isShowingDone || index > 0
        }
        guard !isShowingDone else { return false }
        return index < photos.count - 1 || allVoted
    }

    private func page(_ step: Int) {
        guard canPage(step) else { return }
        selectedPinID = nil
        cancelDraft()
        pageStep = step
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)) {
            drag = .zero
            if isShowingDone {
                isShowingDone = false
                index = photos.count - 1
            } else if step > 0, index == photos.count - 1 {
                isShowingDone = true
            } else {
                index += step
            }
        }
    }

    // MARK: - 좋아/싫어

    private func vote(_ vote: QuestionVote, photo: PhotoItem) {
        guard !isVoting, !isLoading, !loadFailed, !isSendingPin, currentPhoto?.id == photo.id else { return }
        isVoting = true
        cancelDraft()
        selectedPinID = nil
        pageStep = 1
        let votedIndex = index
        let previous = votes[photo.id]

        Task {
            do {
                try await QuestionResponseRepository.setVote(
                    vote,
                    messageID: message.id,
                    folderID: folder.id,
                    photoID: photo.id
                )
                votes[photo.id] = vote
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                    drag = reduceMotion ? .zero : CGSize(width: 0, height: vote == .dislike ? -900 : 900)
                } completion: {
                    showNextUnvoted(after: votedIndex)
                }
            } catch {
                print("[Question] 좋아/싫어 남기기 실패:", error)
                votes[photo.id] = previous
                isVoting = false
                withAnimation(.snappy) { drag = .zero }
                errorMessage = "의견을 남기지 못했어요. 다시 시도해 주세요."
            }
        }


    }

    /// 아직 의견을 안 남긴 다음 사진으로. 다 남겼으면 마무리 카드
    private func showNextUnvoted(after current: Int) {
        let order = (1...max(photos.count, 1)).map { (current + $0) % max(photos.count, 1) }
        let next = order.first { photos.indices.contains($0) && votes[photos[$0].id] == nil }
        isVoting = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)) {
            drag = .zero
            if let next {
                index = next
            } else {
                isShowingDone = true
            }
        }
    }

    // MARK: - 댓글

    private func placeDraft(at location: CGPoint, in size: CGSize, photo: PhotoItem) {
        guard size.width > 0, size.height > 0 else { return }
        selectedPinID = nil
        draftPinID = UUID()
        withAnimation(.snappy(duration: 0.2)) {
            drag = .zero
            draftPin = DraftPin(
                photoID: photo.id,
                x: min(max(location.x / size.width, 0), 1),
                y: min(max(location.y / size.height, 0), 1)
            )
        }
        pinGuideSeen = true
        isInputFocused = true
    }

    private func cancelDraft() {
        guard draftPin != nil, !isSendingPin else { return }
        draftPin = nil
        draftText = ""
        isInputFocused = false
    }

    private func sendPin() {
        let body = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = draftPin, !body.isEmpty, !isSendingPin else { return }
        isSendingPin = true
        let pin = QuestionPin(
            id: draftPinID,
            messageID: message.id,
            photoID: draft.photoID,
            userID: myUserID ?? UUID(),
            x: draft.x,
            y: draft.y,
            body: String(body.prefix(QuestionResponseRepository.maxPinLength)),
            createdAt: .now
        )


        Task {
            do {
                let saved = try await QuestionResponseRepository.addPin(
                    id: pin.id,
                    messageID: pin.messageID,
                    folderID: folder.id,
                    photoID: pin.photoID,
                    x: pin.x,
                    y: pin.y,
                    body: pin.body
                )
                pins.removeAll { $0.id == saved.id }
                pins.append(saved)
                isSendingPin = false
                cancelDraft()
                selectedPinID = saved.id
            } catch {
                print("[Question] 댓글 남기기 실패:", error)
                isSendingPin = false
                errorMessage = "댓글을 남기지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    private func deletePin(_ pin: QuestionPin) async {
        pins.removeAll { $0.id == pin.id }
        if selectedPinID == pin.id { selectedPinID = nil }
        do {
            try await QuestionResponseRepository.deletePin(id: pin.id)
        } catch {
            print("[Question] 댓글 지우기 실패:", error)
            pins.append(pin)
            pins.sort { $0.createdAt < $1.createdAt }
            errorMessage = "댓글을 지우지 못했어요."
        }
    }

    // MARK: - 불러오기

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        guard let myUserID else { loadFailed = true; return }
        do {
            async let loadedVotes = QuestionResponseRepository.fetchVotes(messageID: message.id, userID: myUserID)
            async let loadedPins = QuestionResponseRepository.fetchPins(messageID: message.id, userID: myUserID)
            let (voteList, pinList) = try await (loadedVotes, loadedPins)
            // 불러오는 사이에 남긴 것은 그대로 둠
            for record in voteList where votes[record.photoID] == nil {
                votes[record.photoID] = record.vote
            }
            let known = Set(pins.map(\.id))
            pins = (pinList.filter { !known.contains($0.id) } + pins).sorted { $0.createdAt < $1.createdAt }
            isShowingDone = allVoted
            // 처음엔 아직 의견을 안 남긴 첫 사진부터
            if let first = photos.firstIndex(where: { votes[$0.id] == nil }), index == 0 {
                index = first
            }
        } catch is CancellationError {
        } catch {
            loadFailed = true
        }
    }
}
