import SwiftUI

/// 다른 사람의 사진 질문에서 "확인하러가기"를 누르면 들어오는 화면
/// 좋아/싫어 버튼으로 투표하고, 좌우로 넘겨 이전 답변을 검토합니다.
/// 사진의 한 점을 길게 누르면 그 자리에 댓글을 남김
/// Figma 수정할것: 요청응답 (701:25193)
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
    @State private var hasLoaded = false
    @State private var pendingVote: QuestionVote?
    @State private var showsUnanswered = false

    private struct DraftPin: Equatable {
        let photoID: UUID
        let x: Double
        let y: Double
    }

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
                    onDone: {
                        guard !isVoting else { return }
                        if isShowingDone || !hasLoaded || photos.isEmpty { dismiss() }
                        else if allVoted { cancelDraft(); isShowingDone = true }
                        else { showsUnanswered = true }
                    }
                )

                GeometryReader { proxy in
                    content(in: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.keyboard)

            if draftPin != nil {
                pinInputBar
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
        .confirmationDialog("아직 답하지 않은 사진이 있어요", isPresented: $showsUnanswered, titleVisibility: .visible) {
            Button("이어서 답하기") {
                cancelDraft()
                if let first = photos.firstIndex(where: { votes[$0.id] == nil }) { index = first }
            }
            Button("나중에 이어서 하기") { dismiss() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "문제가 생겼어요",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            if !hasLoaded { Button("다시 불러오기") { Task { await load() } } }
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 사진과 투표 버튼

    private var photoTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: CGFloat(pageStep) * 32).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func content(in available: CGSize) -> some View {
        // 기존 사진/댓글 컴포넌트는 유지하고, 아래에 투표 버튼만 배치합니다.
        let maxHeight = max(120, available.height - 122)
        let width = min(available.width, maxHeight * 3 / 4)
        let photoSize = CGSize(width: width, height: width * 4 / 3)

        return VStack(spacing: 18) {
            Spacer(minLength: 0)
            photoArea(size: photoSize)
                .overlay(alignment: .leading) {
                    QuestionChevronButton(direction: .previous, isEnabled: canPage(-1)) { page(-1) }
                        .padding(.leading, 8)
                }
                .overlay(alignment: .trailing) {
                    QuestionChevronButton(direction: .next, isEnabled: canPage(1)) { page(1) }
                        .padding(.trailing, 8)
                }
            if !isShowingDone {
                HStack(spacing: 30) {
                    voteButton(.dislike)
                    voteButton(.like)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
    }

    private func voteButton(_ choice: QuestionVote) -> some View {
        let chosen = currentPhoto.map { votes[$0.id] == choice } ?? false
        return Button {
            if let photo = currentPhoto { vote(choice, photo: photo) }
        } label: {
            ZStack {
                Image(choice == .like ? .iconLike : .iconDislike)
                    .resizable().scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(chosen ? Color.brandBlue : (choice == .like ? Color.black800 : Color.black400))
                    .opacity(isVoting && pendingVote == choice ? 0 : 1)
                if isVoting && pendingVote == choice { ProgressView() }
            }
            .frame(width: 78, height: 78)
            .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(ShallpickPressStyle())
        .disabled(!hasLoaded || isVoting || currentPhoto == nil || draftPin != nil)
        .accessibilityLabel(choice.label)
        .accessibilityValue(chosen ? "선택됨" : "선택 안 됨")
        .accessibilityIdentifier("question.vote.\(choice.rawValue)")
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

    /// 가만히 길게 누르면 댓글 자리, 움직이면 처음 방향으로 넘기기 (옆: 사진 넘기기, 위아래: 투표하지 않음)
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
                    break
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
                    break
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
        guard !isVoting, draftPin == nil else { return false }
        if step < 0 {
            return isShowingDone || index > 0
        }
        guard !isShowingDone else { return false }
        return index < photos.count - 1
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
            } else {
                index += step
            }
        }
    }

    // MARK: - 좋아/싫어

    private func vote(_ vote: QuestionVote, photo: PhotoItem) {
        guard hasLoaded, !isVoting, draftPin == nil, currentPhoto?.id == photo.id else { return }
        isVoting = true
        pendingVote = vote
        selectedPinID = nil
        let votedIndex = index
        Task {
            defer { isVoting = false; pendingVote = nil }
            do {
                try await QuestionResponseRepository.setVote(
                    vote, messageID: message.id, folderID: folder.id, photoID: photo.id
                )
                votes[photo.id] = vote
                pageStep = 1
                // 저장된 사진은 그대로 두고 다음 미응답 사진으로 이동합니다.
                // 모두 답한 뒤에는 마지막 사진을 유지하고 체크로 마무리합니다.
                let order = (1...photos.count).map { (votedIndex + $0) % photos.count }
                if let next = order.first(where: { votes[photos[$0].id] == nil }) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                        index = next
                        drag = .zero
                    }
                }
            } catch {
                errorMessage = "의견을 남기지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    // MARK: - 댓글

    private func placeDraft(at location: CGPoint, in size: CGSize, photo: PhotoItem) {
        guard size.width > 0, size.height > 0 else { return }
        selectedPinID = nil
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
        guard draftPin != nil else { return }
        draftPin = nil
        draftText = ""
        isInputFocused = false
    }

    private func sendPin() {
        let body = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = draftPin, !body.isEmpty else { return }
        let pin = QuestionPin(
            id: UUID(),
            messageID: message.id,
            photoID: draft.photoID,
            userID: myUserID ?? UUID(),
            x: draft.x,
            y: draft.y,
            body: String(body.prefix(QuestionResponseRepository.maxPinLength)),
            createdAt: .now
        )
        pins.append(pin)
        cancelDraft()
        selectedPinID = pin.id

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
                if let index = pins.firstIndex(where: { $0.id == pin.id }) { pins[index] = saved }
            } catch {
                print("[Question] 댓글 남기기 실패:", error)
                pins.removeAll { $0.id == pin.id }
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
        guard let myUserID else {
            errorMessage = "로그인 상태를 확인해 주세요."
            return
        }
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
            // 처음엔 아직 의견을 안 남긴 첫 사진부터
            if let first = photos.firstIndex(where: { votes[$0.id] == nil }), index == 0 {
                index = first
            }
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            errorMessage = "응답을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }
}
