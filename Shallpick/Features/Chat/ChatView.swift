import SwiftUI

/// 폴더 채팅방 (폴더 화면 오른쪽 위 말풍선)
/// Figma: 채팅방/수정11/17 (234:24971) — 본인이 바로 이어 보내면 간격 4, 나중에 보내거나 다른 사람이면 20, 말풍선 최대 너비 250
struct ChatView: View {
    /// 가운데 제목(▾)을 눌렀을 때
    var onTitle: () -> Void = {}

    @State private var store: ChatStore
    @State private var draft = ""
    /// 다음 메시지에 붙일 폴더 사진 (고른 순서)
    @State private var attachments: [PhotoItem]
    @State private var isPickingPhotos = false
    @State private var viewing: PhotoViewerItem?
    /// 사진 질문: 다른 사람 질문이면 응답 화면, 내 질문이면 결과 화면
    @State private var questionRoute: QuestionRoute?
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var loadAttempt = 0
    @Environment(\.dismiss) private var dismiss

    /// attaching: 폴더 화면의 수달로 고른 사진. 첫 메시지에 붙어서 나감
    init(
        folder: Folder,
        attaching: [PhotoItem] = [],
        onTitle: @escaping () -> Void = {}
    ) {
        _store = State(initialValue: ChatStore(folder: folder))
        _attachments = State(initialValue: attaching)
        self.onTitle = onTitle
    }

    /// 테스트/미리보기용
    init(store: ChatStore, attaching: [PhotoItem] = []) {
        _store = State(initialValue: store)
        _attachments = State(initialValue: attaching)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(
                    text: $draft,
                    attachments: attachments,
                    onOtter: pickPhotos,
                    onClearAttachments: { withAnimation(.snappy(duration: 0.2)) { attachments = [] } },
                    onSend: send
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: loadAttempt) { await store.run() }
            // 수달: 폴더 사진 중에서 질문에 붙일 사진 고르기 (폴더 화면과 같은 화면)
            .fullScreenCover(isPresented: $isPickingPhotos) {
                FolderPhotoSelectView(photos: store.folderPhotos, avatarURL: myAvatarURL) { picked in
                    attachments = picked
                }
            }
            .fullScreenCover(item: $viewing) { item in
                ChatPhotoViewer(photos: item.photos)
            }
            .navigationDestination(item: $questionRoute) { route in
                switch route.kind {
                case .respond:
                    QuestionRespondView(
                        folder: store.folder,
                        message: route.message,
                        photos: route.photos,
                        sender: store.member(for: route.message.userID)
                    )
                case .result:
                    QuestionResultView(
                        folder: store.folder,
                        message: route.message,
                        photos: route.photos,
                        members: store.members,
                        myAvatarURL: myAvatarURL
                    )
                }
            }
    }

    private var myAvatarURL: URL? {
        store.myUserID.flatMap { store.member(for: $0)?.avatarURL }.flatMap(URL.init(string:))
    }

    private func pickPhotos() {
        isPickingPhotos = true
        Task { await store.reloadPhotos() }
    }

    /// 첨부 사진을 누르면: 내 사진 질문이면 결과 화면, 아니면 크게 보기
    private func openPhotos(of message: ChatMessage) {
        let photos = store.attachedPhotos(of: message).compactMap { $0 }
        guard !photos.isEmpty else { return }
        if store.isMine(message), store.isPhotoQuestion(message), store.deliveryStates[message.id] == nil {
            questionRoute = QuestionRoute(kind: .result, message: message, photos: photos)
        } else {
            viewing = PhotoViewerItem(photos: photos)
        }
    }

    /// 질문 카드 버튼: 다른 사람 질문이면 확인했다고 남기고 응답 화면, 내 질문이면 결과 화면
    private func review(_ message: ChatMessage) {
        let photos = store.attachedPhotos(of: message).compactMap { $0 }
        guard !photos.isEmpty else { return }
        if store.isMine(message) {
            questionRoute = QuestionRoute(kind: .result, message: message, photos: photos)
        } else {
            store.markChecked(message)
            questionRoute = QuestionRoute(kind: .respond, message: message, photos: photos)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.messages.isEmpty {
            ProgressView()
        } else if store.loadFailed {
            ChatLoadFailedView { loadAttempt += 1 }
        } else if store.messages.isEmpty {
            EmptyChatView()
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(ChatRow.rows(for: store.messages, myUserID: store.myUserID)) { row in
                    rowView(row)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        VStack(spacing: 0) {
            if let day = row.dayHeader {
                ChatDateHeader(date: day)
                    .padding(.top, row.isFirst ? 0 : 20)
            }

            let message = row.message
            let photos = store.attachedPhotos(of: message)
            Group {
                if store.isMine(message) {
                    MyMessageRow(
                        message: message,
                        photos: photos,
                        state: store.deliveryStates[message.id],
                        footer: store.isPhotoQuestion(message) && store.deliveryStates[message.id] == nil
                            ? .checkedBy(store.checkers(of: message), onTap: { review(message) })
                            : nil,
                        onRetry: { store.retry(message.id) },
                        onOpenPhotos: { openPhotos(of: message) }
                    )
                } else {
                    OtherMessageRow(
                        message: message,
                        photos: photos,
                        sender: store.member(for: message.userID),
                        footer: store.isPhotoQuestion(message) ? .goCheck(onTap: { review(message) }) : nil,
                        onOpenPhotos: { openPhotos(of: message) }
                    )
                }
            }
            .padding(.top, row.topSpacing)
        }
    }

    private func send() {
        store.send(draft, photos: attachments)
        draft = ""
        attachments = []
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
    }

    // MARK: - 상단 (위 234:24804): 뒤로 + 가운데 제목 ▾

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "뒤로") { dismiss() }

            Button(action: onTitle) {
                HStack(spacing: 8) {
                    Text(store.folder.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black800)
                        .lineLimit(1)
                    Image(.iconChevronDown)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 7)
                        .foregroundStyle(Color.black400)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)

            // 제목이 가운데 오도록 뒤로 버튼만큼 비워 둠
            Color.clear.frame(width: 45, height: 45)
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background {
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
}

// MARK: - 줄 계산

/// 메시지 한 줄 + 위 간격 + (날짜가 바뀌면) 날짜 표시
struct ChatRow: Identifiable {
    let message: ChatMessage
    let isFirst: Bool
    let dayHeader: Date?
    let topSpacing: CGFloat

    var id: UUID { message.id }

    /// 본인이 이 시간 안에 이어서 보내면 붙여서 보여 줌
    static let groupingInterval: TimeInterval = 60

    static func rows(for messages: [ChatMessage], myUserID: UUID?, calendar: Calendar = .current) -> [ChatRow] {
        var rows: [ChatRow] = []
        rows.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let isNewDay = previous.map { !calendar.isDate($0.createdAt, inSameDayAs: message.createdAt) } ?? true
            let isMyFollowUp = previous.map {
                $0.userID == message.userID
                    && message.userID == myUserID
                    && message.createdAt.timeIntervalSince($0.createdAt) < groupingInterval
            } ?? false

            let spacing: CGFloat = isNewDay ? 20 : (isMyFollowUp ? 4 : 20)
            rows.append(
                ChatRow(
                    message: message,
                    isFirst: index == 0,
                    dayHeader: isNewDay ? message.createdAt : nil,
                    topSpacing: spacing
                )
            )
        }
        return rows
    }
}

// MARK: - 말풍선

/// 말풍선 (blue100: 다른 사람, black200: 나). 한 줄 최대 250
/// 사진 질문이면 카카오톡 알림 카드처럼 말풍선 안 아래에 꽉 찬 버튼이 붙음 (Figma 에 없는 부분)
private struct ChatBubble: View {
    let text: String
    let color: Color
    /// 250 칸 안에서 붙을 쪽 (내 메시지는 오른쪽)
    var alignment: Alignment = .leading
    /// 사진 여러 장이 붙은 질문이면 오른쪽에 > (다른 사람: brandBlue, 나: black400)
    var chevronColor: Color?
    /// 사진 질문 버튼 (확인하러가기 / 누가 확인했는지)
    var footer: QuestionFooter?
    var onTap: (() -> Void)?

    /// 버튼이 붙은 질문 카드 너비 (버튼이 꽉 차도록 고정)
    static let cardWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black800)
                if footer != nil { Spacer(minLength: 0) }
                if let chevronColor {
                    Image(.iconChevronRight)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 5, height: 10)
                        .foregroundStyle(chevronColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, footer == nil ? 0 : 4)
            .padding(.top, footer == nil ? 0 : 4)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)

            if let footer {
                QuestionFooterButton(footer: footer)
            }
        }
        .padding(.horizontal, footer == nil ? 12 : 8)
        .padding(.top, footer == nil ? 10 : 8)
        .padding(.bottom, footer == nil ? 10 : 8)
        .frame(width: footer == nil ? nil : Self.cardWidth, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button("복사", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = text
            }
        }
        .frame(maxWidth: 250, alignment: alignment)
    }
}

/// 말풍선 + (있으면) 위에 첨부 사진. 말풍선이 사진 아래를 덮음 (1장 20pt, 여러 장 25pt)
/// Figma: Component 13·16 (사진 1장), 540:11179 (여러 장 → 겹친 사진 + >)
private struct MessageContent: View {
    let message: ChatMessage
    let photos: [PhotoItem?]
    let color: Color
    let chevronColor: Color
    let alignment: HorizontalAlignment
    var footer: QuestionFooter?
    let onOpenPhotos: () -> Void

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if !photos.isEmpty {
                ChatAttachment(photos: photos)
                    .padding(.bottom, photos.count == 1 ? -20 : -25)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenPhotos)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("사진 \(photos.count)장")
                    .accessibilityAddTraits(.isButton)
            }
            ChatBubble(
                text: message.body,
                color: color,
                alignment: alignment == .trailing ? .trailing : .leading,
                chevronColor: photos.count > 1 ? chevronColor : nil,
                footer: footer,
                onTap: photos.isEmpty ? nil : onOpenPhotos
            )
        }
        .padding(.bottom, 3)
    }
}

// MARK: - 사진 질문 버튼

enum QuestionFooter {
    /// 다른 사람이 보낸 질문: 확인하러가기
    case goCheck(onTap: () -> Void)
    /// 내가 보낸 질문: 누가 확인했는지 (확인한 순서)
    case checkedBy([ChatMember], onTap: () -> Void)

    /// "정규호님이 확인했어요" / "정규호, 김승완님이 확인했어요" / "정규호님 외 2명이 확인했어요"
    static func checkedText(_ names: [String]) -> String {
        switch names.count {
        case 0: "아직 아무도 확인하지 않았어요"
        case 1: "\(names[0])님이 확인했어요"
        case 2: "\(names[0]), \(names[1])님이 확인했어요"
        default: "\(names[0])님 외 \(names.count - 1)명이 확인했어요"
        }
    }
}

/// 질문 카드 안 아래의 꽉 찬 흰 버튼 (카카오톡 알림 카드 버튼처럼)
private struct QuestionFooterButton: View {
    let footer: QuestionFooter

    var body: some View {
        switch footer {
        case let .goCheck(onTap):
            Button(action: onTap) {
                Text("확인하러가기")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black800)
                    .cardButtonStyle()
            }
            .buttonStyle(.plain)
            .accessibilityHint("사진을 보고 반응이나 생각을 남겨요")

        case let .checkedBy(members, onTap):
            let text = QuestionFooter.checkedText(members.map(\.nickname))
            Button(action: onTap) {
                HStack(spacing: 6) {
                    if !members.isEmpty {
                        CheckerAvatars(members: Array(members.prefix(3)))
                    }
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(members.isEmpty ? Color.black400 : Color.black600)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .cardButtonStyle()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityHint("사진에 남긴 반응과 생각을 봐요")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// 확인한 사람 프로필을 조금씩 겹쳐서 (최대 3명)
private struct CheckerAvatars: View {
    let members: [ChatMember]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(members, id: \.userID) { member in
                ChatAvatar(url: member.avatarURL.flatMap(URL.init(string:)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            }
        }
    }
}

private extension View {
    /// 카드 너비에 꽉 찬 흰 버튼 (높이 40)
    func cardButtonStyle() -> some View {
        padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// 첨부 사진: 1장이면 사진(58 × 78), 여러 장이면 최대 3장을 겹쳐 놓은 묶음
private struct ChatAttachment: View {
    let photos: [PhotoItem?]

    var body: some View {
        if photos.count == 1 {
            FolderPhoto(url: photos[0]?.url, cornerRadius: 8)
                .frame(width: 58, height: 78)
        } else {
            ChatPhotoStack(photoURLs: photos.prefix(3).map { $0?.url })
        }
    }
}

/// 사진 묶음 (Figma Group 40 540:11121, 63 × 65): 뒤 오른쪽 +4°, 뒤 왼쪽 -4°, 앞 가운데
private struct ChatPhotoStack: View {
    let photoURLs: [URL?]

    private let photoSize = CGSize(width: 35.97, height: 47.96)

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo(1, rotation: 4, center: CGPoint(x: 43.48, y: 25.18))
            photo(0, rotation: -4, center: CGPoint(x: 19.62, y: 30.5))
            photo(2, rotation: 0, center: CGPoint(x: 31.41, y: 41.04))
        }
        .frame(width: 63.09, height: 65.02, alignment: .topLeading)
    }

    @ViewBuilder
    private func photo(_ index: Int, rotation: Double, center: CGPoint) -> some View {
        if index < photoURLs.count {
            FolderPhoto(url: photoURLs[index], cornerRadius: 4)
                .frame(width: photoSize.width, height: photoSize.height)
                .rotationEffect(.degrees(rotation))
                .position(center)
        }
    }
}

/// 다른 사람 메시지: 프로필 + 이름 + 말풍선 (message 234:23785)
private struct OtherMessageRow: View {
    let message: ChatMessage
    let photos: [PhotoItem?]
    let sender: ChatMember?
    var footer: QuestionFooter?
    let onOpenPhotos: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(spacing: 3) {
                ChatAvatar(url: sender?.avatarURL.flatMap(URL.init(string:)))
                    .frame(width: 32, height: 32)
                Text(sender?.nickname ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.black600)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 40)
            }
            .frame(width: 32)

            MessageContent(
                message: message,
                photos: photos,
                color: .blue100,
                chevronColor: .brandBlue,
                alignment: .leading,
                footer: footer,
                onOpenPhotos: onOpenPhotos
            )

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 내 메시지: 오른쪽 정렬 (Component 15 234:23946)
private struct MyMessageRow: View {
    let message: ChatMessage
    let photos: [PhotoItem?]
    let state: ChatStore.DeliveryState?
    var footer: QuestionFooter?
    let onRetry: () -> Void
    let onOpenPhotos: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 0)

            if state == .failed {
                Button(action: onRetry) {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다시 보내기")
                .padding(.bottom, 6)
            }

            MessageContent(
                message: message,
                photos: photos,
                color: .black200,
                chevronColor: .black400,
                alignment: .trailing,
                footer: footer,
                onOpenPhotos: onOpenPhotos
            )
            .opacity(state == .sending ? 0.6 : 1)
        }
    }
}

/// 프로필 사진. 없으면 기본 수달 이미지. (small_profile 190:22499)
struct ChatAvatar: View {
    let url: URL?

    var body: some View {
        AppImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(.defaultAvatar).resizable().scaledToFill()
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// 날짜 구분 "11월 15일 (일)"
private struct ChatDateHeader: View {
    let date: Date

    var body: some View {
        Text(Self.format(date))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.black400)
            .frame(maxWidth: .infinity)
    }

    static func format(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        var korean = calendar
        korean.locale = Locale(identifier: "ko_KR")
        let weekday = korean.shortWeekdaySymbols[parts.weekday! - 1]
        let dayText = "\(parts.month!)월 \(parts.day!)일 (\(weekday))"
        return calendar.isDate(date, equalTo: now, toGranularity: .year) ? dayText : "\(parts.year!)년 \(dayText)"
    }
}

// MARK: - 입력창 (채팅 234:25317)

private struct ChatInputBar: View {
    @Binding var text: String
    let attachments: [PhotoItem]
    let onOtter: () -> Void
    let onClearAttachments: () -> Void
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black50.opacity(0), location: 0),
                    .init(color: .black50, location: 0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            // 폴더 화면에서 사진을 골라 들어오면 바로 질문을 쓰게
            if !attachments.isEmpty { isFocused = true }
        }
        .onChange(of: attachments.map(\.id)) { _, ids in
            if !ids.isEmpty { isFocused = true }
        }
    }

    /// 보낼 메시지에 붙을 사진 (Figma 에 없는 부분 — 작은 사진 + 장수 + X)
    private var attachmentStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: -12) {
                ForEach(attachments.prefix(3)) { photo in
                    FolderPhoto(url: photo.url, cornerRadius: 4)
                        .frame(width: 27, height: 36)
                }
            }
            Text("사진 \(attachments.count)장을 함께 보내요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black600)
            Spacer(minLength: 0)
            Button(action: onClearAttachments) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black400)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("첨부한 사진 빼기")
        }
        .padding(.leading, 45 + 8 + 10)
        .padding(.trailing, 6)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            OtterButton(accessibilityLabel: "질문에 첨부할 사진 고르기", action: onOtter)

            // 입력칸 안 오른쪽에 전송 버튼 (채팅창(new) 401:5041)
            HStack(alignment: .bottom, spacing: 8) {
                TextField(attachments.isEmpty ? "메시지를 입력하세요" : "사진에 대해 물어보세요", text: $text, axis: .vertical)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.black800)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .frame(minHeight: 30)
                    .padding(.leading, 12)
                    .onChange(of: text) { _, newValue in
                        if newValue.count > ChatRepository.maxBodyLength {
                            text = String(newValue.prefix(ChatRepository.maxBodyLength))
                        }
                    }

                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .frame(minHeight: 45)
            .background(.white, in: RoundedRectangle(cornerRadius: 22.5))
            .shallpickShadow(blur: 20)
        }
    }

    /// 44x30 알약. 비어 있으면 회색, 보낼 수 있으면 검정
    private var sendButton: some View {
        Button(action: onSend) {
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
        .animation(.snappy(duration: 0.15), value: canSend)
        .accessibilityLabel("보내기")
    }
}

// MARK: - 첨부 사진 크게 보기

private struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}

/// 사진 질문으로 여는 화면 (사진은 1장 이상)
private struct QuestionRoute: Hashable {
    enum Kind { case respond, result }

    let kind: Kind
    let message: ChatMessage
    let photos: [PhotoItem]
}

/// 말풍선의 사진 / 작은 폴더 / > 를 누르면 뜨는 화면. 옆으로 넘겨 봄
private struct ChatPhotoViewer: View {
    let photos: [PhotoItem]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    private var index: Int {
        photos.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(photos) { photo in
                AppImage(url: photo.url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.black400)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(Optional(photo.id))
                .accessibilityLabel("사진")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            HStack {
                CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") { dismiss() }
                Spacer()
                if photos.count > 1 {
                    Text("\(index + 1) / \(photos.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 11)
        }
        .onAppear { selection = photos.first?.id }
    }
}

// MARK: - 빈 화면 / 실패

private struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(.otterEmpty)
                .resizable()
                .scaledToFill()
                .frame(width: 167, height: 173.37)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("아직 대화가 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("첫 메시지를 보내보세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .multilineTextAlignment(.center)
        }
    }
}

private struct ChatLoadFailedView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("메시지를 불러오지 못했어요")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black800)
            Button("다시 시도", action: onRetry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black800)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
                .shallpickShadow(blur: 20)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(store: .preview)
    }
}

extension ChatStore {
    static var preview: ChatStore {
        let me = UUID()
        let store = ChatStore(folder: Folder.previews[0], myUserID: me)
        store.loadPreview(me: me)
        return store
    }
}
