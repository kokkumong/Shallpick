import SwiftUI

/// 폴더 채팅방 (폴더 화면 오른쪽 위 말풍선)
/// Figma: 채팅방 (246:5159) — 본인이 바로 이어 보내면 간격 4, 나중에 보내거나 다른 사람이면 20, 말풍선 최대 너비 250
struct ChatView: View {
    var onSearch: () -> Void = {}
    var onMenu: () -> Void = {}
    var onOtter: () -> Void = {}

    @State private var store: ChatStore
    @State private var draft = ""
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var loadAttempt = 0
    @Environment(\.dismiss) private var dismiss

    init(
        folder: Folder,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {},
        onOtter: @escaping () -> Void = {}
    ) {
        _store = State(initialValue: ChatStore(folder: folder))
        self.onSearch = onSearch
        self.onMenu = onMenu
        self.onOtter = onOtter
    }

    /// 테스트/미리보기용
    init(store: ChatStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(text: $draft, onOtter: onOtter, onSend: send)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: loadAttempt) { await store.run() }
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
            Group {
                if store.isMine(message) {
                    MyMessageRow(
                        message: message,
                        state: store.deliveryStates[message.id],
                        onRetry: { store.retry(message.id) }
                    )
                } else {
                    OtherMessageRow(message: message, sender: store.member(for: message.userID))
                }
            }
            .padding(.top, row.topSpacing)
        }
    }

    private func send() {
        store.send(draft)
        draft = ""
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
    }

    // MARK: - 상단 (채팅방_위 190:22286)

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "뒤로") { dismiss() }

            Text(store.folder.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black800)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색", action: onSearch)
                CircleIconButton(icon: .iconMenu, accessibilityLabel: "메뉴", action: onMenu)
            }
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
private struct ChatBubble: View {
    let text: String
    let color: Color
    /// 250 칸 안에서 붙을 쪽 (내 메시지는 오른쪽)
    var alignment: Alignment = .leading

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black800)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

/// 다른 사람 메시지: 프로필 + 이름 + 말풍선 (message 234:23785)
private struct OtherMessageRow: View {
    let message: ChatMessage
    let sender: ChatMember?

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

            ChatBubble(text: message.body, color: .blue100)
                .padding(.bottom, 3)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 내 메시지: 오른쪽 정렬 (Component 15 234:23946)
private struct MyMessageRow: View {
    let message: ChatMessage
    let state: ChatStore.DeliveryState?
    let onRetry: () -> Void

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

            ChatBubble(text: message.body, color: .black200, alignment: .trailing)
                .opacity(state == .sending ? 0.6 : 1)
                .padding(.bottom, 3)
        }
    }
}

/// 프로필 사진. 없으면 기본 수달 이미지. (small_profile 190:22499)
private struct ChatAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
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

// MARK: - 입력창 (채팅 246:5190)

private struct ChatInputBar: View {
    @Binding var text: String
    let onOtter: () -> Void
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            OtterButton(action: onOtter)

            TextField("메시지를 입력하세요", text: $text, axis: .vertical)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.black800)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(minHeight: 45)
                .background(.white, in: RoundedRectangle(cornerRadius: 22.5))
                .shallpickShadow(blur: 20)
                .onChange(of: text) { _, newValue in
                    if newValue.count > ChatRepository.maxBodyLength {
                        text = String(newValue.prefix(ChatRepository.maxBodyLength))
                    }
                }

            CircleIconButton(icon: .iconSend, iconSize: 20, style: .filled, accessibilityLabel: "보내기", action: onSend)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
                .animation(.snappy(duration: 0.15), value: canSend)
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
