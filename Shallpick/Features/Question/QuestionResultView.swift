import SwiftUI

/// 내가 보낸 사진 질문의 사진(또는 아래 확인 버튼)을 누르면 들어오는 화면
/// 좌우로 넘기며 사진마다 누가 좋아/싫어했는지, 사진 위 어느 점에 어떤 댓글을 남겼는지 봄
/// Figma 에 없는 화면이라 요청응답(540:11455)의 위/사진 배치를 따름
struct QuestionResultView: View {
    let folder: Folder
    let message: ChatMessage
    let photos: [PhotoItem]
    let members: [UUID: ChatMember]
    var myAvatarURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID?
    @State private var votes: [QuestionVoteRecord] = []
    @State private var pins: [QuestionPin] = []
    @State private var selectedPinID: UUID?
    @State private var isLoading = true
    @State private var loadFailed = false

    private var currentIndex: Int {
        photos.firstIndex { $0.id == currentID } ?? 0
    }

    private var currentPhoto: PhotoItem? {
        photos.indices.contains(currentIndex) ? photos[currentIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(
                title: folder.name,
                avatarURL: myAvatarURL,
                subtitle: "내 질문 · \(message.body)",
                onDone: { dismiss() }
            )
            .padding(.bottom, 20)

            GeometryReader { proxy in
                let photoSize = QuestionPhotoLayout.size(width: proxy.size.width - 60)
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 11) {
                            QuestionChevronButton(direction: .previous, isEnabled: currentIndex > 0) { move(-1) }
                            photoPager(size: photoSize)
                            QuestionChevronButton(direction: .next, isEnabled: currentIndex < photos.count - 1) { move(1) }
                        }

                        if photos.count > 1 {
                            Text("\(currentIndex + 1) / \(photos.count)")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.black400)
                        }

                        Group {
                            if isLoading && votes.isEmpty && pins.isEmpty {
                                ProgressView().padding(.top, 20)
                            } else if loadFailed {
                                Button("의견을 불러오지 못했어요 · 다시 시도") {
                                    Task { await load() }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black600)
                            } else if let photo = currentPhoto {
                                VStack(spacing: 24) {
                                    voteSection(photo: photo)
                                    commentSection(photo: photo)
                                }
                            }
                        }
                        .frame(width: photoSize.width)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load() }
            }
        }
        .background(Color.black50)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy(duration: 0.2), value: selectedPinID)
        .animation(.snappy(duration: 0.2), value: currentID)
        .onAppear { if currentID == nil { currentID = photos.first?.id } }
        .onChange(of: currentID) { selectedPinID = nil }
        .task { await load() }
    }

    // MARK: - 사진 (좌우로 넘기기)

    private func photoPager(size: CGSize) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(photos) { photo in
                    photoCard(photo, size: size)
                        .frame(width: size.width, height: size.height)
                        .id(photo.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func photoCard(_ photo: PhotoItem, size: CGSize) -> some View {
        let photoPins = pins.filter { $0.photoID == photo.id }
        return ZStack(alignment: .topLeading) {
            QuestionPhotoImage(url: photo.url)
                .frame(width: size.width, height: size.height)
                .onTapGesture { selectedPinID = nil }

            ForEach(photoPins) { pin in
                Button {
                    selectedPinID = selectedPinID == pin.id ? nil : pin.id
                } label: {
                    QuestionPinDot(isHighlighted: selectedPinID == pin.id)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name(of: pin.userID))님의 댓글: \(pin.body)")
                .position(x: pin.x * size.width, y: pin.y * size.height)
            }

            if let pin = photoPins.first(where: { $0.id == selectedPinID }) {
                QuestionPinBubble(point: CGPoint(x: pin.x * size.width, y: pin.y * size.height), bounds: size) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name(of: pin.userID))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.black600)
                        Text(pin.body)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black800)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    private func move(_ step: Int) {
        let next = currentIndex + step
        guard photos.indices.contains(next) else { return }
        withAnimation(.snappy) { currentID = photos[next].id }
    }

    // MARK: - 좋아 / 싫어

    private func voteSection(photo: PhotoItem) -> some View {
        let photoVotes = votes.filter { $0.photoID == photo.id }
        return VStack(spacing: 0) {
            voteRow(.like, voters: photoVotes.filter { $0.vote == .like }.map(\.userID))
            Divider().overlay(Color.black200)
            voteRow(.dislike, voters: photoVotes.filter { $0.vote == .dislike }.map(\.userID))
        }
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(.white).shallpickShadow(blur: 20)
        }
    }

    private func voteRow(_ vote: QuestionVote, voters: [UUID]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(vote == .like ? .iconLike : .iconDislike)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(vote.label)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(voters.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(voters.isEmpty ? Color.black400 : Color.brandBlue)
            }
            .foregroundStyle(Color.black800)
            .frame(width: 84, alignment: .leading)

            if voters.isEmpty {
                Text("아직 없어요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black400)
            } else {
                HStack(spacing: -6) {
                    ForEach(voters.prefix(4), id: \.self) { userID in
                        ChatAvatar(url: members[userID]?.avatarURL.flatMap(URL.init(string:)))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
                Text(voters.map(name(of:)).joined(separator: ", "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black600)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 사진 위 댓글

    private func commentSection(photo: PhotoItem) -> some View {
        let photoPins = pins.filter { $0.photoID == photo.id }
        return VStack(alignment: .leading, spacing: 14) {
            Text("사진에 남긴 댓글 \(photoPins.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black800)

            if photoPins.isEmpty {
                Text("아직 사진에 남긴 댓글이 없어요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black400)
            } else {
                ForEach(photoPins) { pin in
                    Button {
                        selectedPinID = selectedPinID == pin.id ? nil : pin.id
                    } label: {
                        commentRow(pin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("사진에서 이 댓글 자리를 보여줘요")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentRow(_ pin: QuestionPin) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ChatAvatar(url: members[pin.userID]?.avatarURL.flatMap(URL.init(string:)))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name(of: pin.userID))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black800)
                    Text(RelativeTimeText.format(pin.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black400)
                }
                Text(pin.body)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black800)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            selectedPinID == pin.id ? Color.blue100 : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func name(of userID: UUID) -> String {
        members[userID]?.nickname ?? "샬픽 사용자"
    }

    // MARK: - 불러오기

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedVotes = QuestionResponseRepository.fetchVotes(messageID: message.id)
            async let loadedPins = QuestionResponseRepository.fetchPins(messageID: message.id)
            let (voteList, pinList) = try await (loadedVotes, loadedPins)
            votes = voteList
            pins = pinList
            loadFailed = false
        } catch is CancellationError {
        } catch {
            print("[Question] 질문 결과 불러오기 실패:", error)
            loadFailed = votes.isEmpty && pins.isEmpty
        }
    }
}
