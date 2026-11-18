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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availablePhotos: [PhotoItem] = []
    @State private var isExporting = false
    @State private var savedIDs: Set<UUID> = []
    @State private var shareFiles: PhotoShareFiles?
    @State private var pendingCleanup: PhotoShareFiles?
    @State private var notice: String?
    @State private var isReasking = false

    private var approval: QuestionApproval {
        QuestionApproval(messageID: message.id, recipientIDs: message.recipientIDs,
                         photoIDs: message.photoIDs, votes: votes)
    }
    private var approvedPhotos: [PhotoItem] {
        let ids = Set(approval.approvedPhotoIDs)
        let byID = Dictionary(uniqueKeysWithValues: availablePhotos.map { ($0.id, $0) })
        return message.photoIDs.filter { ids.contains($0) }.compactMap { byID[$0] }
    }
    private var unsavedPhotos: [PhotoItem] { approvedPhotos.filter { !savedIDs.contains($0.id) } }


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
        .safeAreaInset(edge: .bottom, spacing: 0) { exportBar }
        .background(Color.black50)
        .toolbar(.hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedPinID)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: currentID)
        .onAppear { if currentID == nil { currentID = photos.first?.id } }
        .onChange(of: currentID) { selectedPinID = nil }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if !isExporting { await load() }
            }
        }
        .sheet(item: $shareFiles, onDismiss: cleanupShare) { files in
            PhotoShareSheet(files: files) { shareFiles = nil }
        }
        .fullScreenCover(isPresented: $isReasking) {
            QuestionComposeView(folder: folder, photos: availablePhotos, initialQuestion: message.body) { _ in
                notice = "받을 사람을 지정해 새 질문을 보냈어요. 채팅에서 확인할 수 있어요."
            }
        }
        .alert("사진 공유", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(notice ?? "") }
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
        withAnimation(reduceMotion ? nil : .snappy) { currentID = photos[next].id }
    }

    // MARK: - 좋아 / 싫어

    private func voteSection(photo: PhotoItem) -> some View {
        let photoVotes = votes.filter { $0.photoID == photo.id && (message.recipientIDs.isEmpty || approval.recipientIDs.contains($0.userID)) }
        return VStack(spacing: 0) {
            voteRow(.like, voters: photoVotes.filter { $0.vote == .like }.map(\.userID))
            Divider().overlay(Color.black200)
            voteRow(.dislike, voters: photoVotes.filter { $0.vote == .dislike }.map(\.userID))
            if !message.recipientIDs.isEmpty {
                Divider().overlay(Color.black200)
                let waiting = approval.pending(for: photo.id).sorted { name(of: $0) < name(of: $1) }
                Text(waiting.isEmpty ? "모두 답변했어요" : "답변 대기: " + waiting.map(name(of:)).joined(separator: ", "))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.black600)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
            }
            if !availablePhotos.contains(where: { $0.id == photo.id }) {
                Text("이 사진은 삭제되었거나 더 이상 볼 수 없어요")
                    .font(.system(size: 13)).foregroundStyle(Color.black600).padding(.bottom, 12)
            }
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

    private var exportBar: some View {
        VStack(spacing: 10) {
            if !isLoading && !loadFailed && availablePhotos.count < message.photoIDs.count {
                Text("요청한 사진 중 \(message.photoIDs.count - availablePhotos.count)장은 더 이상 볼 수 없어요")
                    .font(.system(size: 12)).foregroundStyle(Color.black600)
            }
            if message.recipientIDs.isEmpty {
                Button("받을 사람을 정해 다시 요청하기") { isReasking = true }
                    .font(.system(size: 14, weight: .semibold))
                    .disabled(availablePhotos.isEmpty || isLoading || loadFailed)
                Text("이 질문에는 받을 사람이 지정되지 않았어요")
                    .font(.system(size: 12)).foregroundStyle(Color.black600)
            } else {
                Text(loadFailed ? "최신 답변을 확인한 뒤 저장할 수 있어요" : approvedPhotos.isEmpty ? "모두 ‘좋아’라고 답한 사진을 기다리고 있어요" : "모두 좋아요 \(approvedPhotos.count)장")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.black600)
                HStack(spacing: 12) {
                    Button { Task { await export(share: false) } } label: {
                        HStack(spacing: 8) {
                            if isExporting { ProgressView().tint(.white) }
                            Text(!approvedPhotos.isEmpty && unsavedPhotos.isEmpty ? "저장 완료" : "\(unsavedPhotos.count)장 저장")
                        }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.black800, in: Capsule())
                    }
                    .buttonStyle(ShallpickPressStyle())
                    .disabled(unsavedPhotos.isEmpty || isLoading || loadFailed || isExporting)
                    .opacity(unsavedPhotos.isEmpty || loadFailed ? 0.4 : 1)
                    Button { Task { await export(share: true) } } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .medium))
                            .frame(width: 48, height: 48).background(.white, in: Circle())
                    }
                    .buttonStyle(ShallpickPressStyle()).accessibilityLabel("모두 동의한 사진 공유")
                    .disabled(approvedPhotos.isEmpty || isLoading || loadFailed || isExporting)
                    .opacity(approvedPhotos.isEmpty || loadFailed ? 0.4 : 1)
                }
            }
        }
        .foregroundStyle(Color.black800).padding(.horizontal, 24).padding(.vertical, 12)
        .background { BottomFade() }
    }

    private func cleanupShare() {
        pendingCleanup?.cleanup()
        pendingCleanup = nil
    }

    private func export(share: Bool) async {
        guard !isExporting, !isLoading, !loadFailed else { return }
        let previouslyApproved = approvedPhotos.map(\.id)
        isExporting = true
        defer { isExporting = false }
        do {
            guard try await ChatRepository.fetchMessage(id: message.id, folderID: folder.id) != nil else {
                notice = "질문이 삭제되었거나 접근할 수 없어요."
                loadFailed = true
                return
            }
            async let freshVotes = QuestionResponseRepository.fetchVotes(messageID: message.id)
            async let freshPhotos = PhotoRepository.fetch(folderID: folder.id)
            let (records, items) = try await (freshVotes, freshPhotos)
            votes = records
            availablePhotos = items.filter { message.photoIDs.contains($0.id) }
            guard previouslyApproved == approvedPhotos.map(\.id) else {
                notice = "답변 또는 사진이 바뀌었어요. 변경된 대상을 확인하고 다시 눌러 주세요."
                return
            }
            let targets = share ? approvedPhotos : unsavedPhotos
            guard !targets.isEmpty else { return }
            if share {
                let files = try await PhotoExport.prepareShare(targets)
                pendingCleanup = files
                shareFiles = files
            } else {
                let result = try await PhotoExport.save(targets)
                savedIDs.formUnion(result.succeeded)
                notice = result.failed.isEmpty ? "사진 \(result.succeeded.count)장을 저장했어요" : "\(result.succeeded.count)장 저장, \(result.failed.count)장 실패. 저장 버튼을 누르면 남은 사진만 다시 시도해요."
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: - 불러오기

    private func load() async {
        guard !isExporting else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedVotes = QuestionResponseRepository.fetchVotes(messageID: message.id)
            async let loadedPins = QuestionResponseRepository.fetchPins(messageID: message.id)
            async let loadedPhotos = PhotoRepository.fetch(folderID: folder.id)
            let (voteList, pinList) = try await (loadedVotes, loadedPins)
            availablePhotos = try await loadedPhotos.filter { message.photoIDs.contains($0.id) }
            votes = voteList
            pins = pinList
            loadFailed = false
        } catch is CancellationError {
        } catch {
            print("[Question] 질문 결과 불러오기 실패:", error)
            loadFailed = true
        }
    }
}
