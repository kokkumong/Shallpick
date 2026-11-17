import Photos
import SwiftUI

/// 폴더를 눌렀을 때 들어가는 화면: 사진 4열 그리드 + 상단(뒤로/이름/검색/채팅) + 하단(필터/수달/추가)
/// Figma: 폴더안 (246:5208)
struct FolderDetailView: View {
    let folder: Folder
    var avatarURL: URL?
    var onSearch: () -> Void = {}
    /// 수달 → "질문에 첨부할 사진 선택" 에서 → 를 누르면 불립니다 (고른 순서대로).
    /// 주면 밖에서 채팅을 열고, 없으면 이 화면에서 고른 사진을 붙여 채팅을 엽니다.
    var onAskQuestion: (([PhotoItem]) -> Void)?
    /// 채팅 버튼. 주면 밖(HomeView 의 내비게이션 경로)에서 채팅을 열고, 없으면 이 화면에서 엽니다.
    var onOpenChat: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotoItem]
    @State private var filters: Set<PhotoFilter> = []
    @State private var isShowingFilterMenu = false
    @State private var isShowingChat = false
    /// 이 화면에서 채팅을 열 때 첫 메시지에 붙일 사진
    @State private var chatAttachments: [PhotoItem] = []
    @State private var isShowingPhotoPicker = false
    @State private var isShowingQuestionPicker = false
    @State private var isShowingInvite = false
    @State private var upload: UploadProgress?
    @State private var errorMessage: String?

    private struct UploadProgress: Equatable {
        var done: Int
        let total: Int
    }

    init(
        folder: Folder,
        avatarURL: URL? = nil,
        photos: [PhotoItem] = [],
        onSearch: @escaping () -> Void = {},
        onAskQuestion: (([PhotoItem]) -> Void)? = nil,
        onOpenChat: (() -> Void)? = nil
    ) {
        self.folder = folder
        self.avatarURL = avatarURL
        self.onSearch = onSearch
        self.onAskQuestion = onAskQuestion
        self.onOpenChat = onOpenChat
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
            .animation(.snappy(duration: 0.2), value: upload)
            .navigationDestination(isPresented: $isShowingChat) {
                ChatView(folder: folder, attaching: chatAttachments)
            }
            // + : 내 보관함에서 골라 폴더에 올리기 (Figma 갤러리 173:21698)
            .sheet(isPresented: $isShowingPhotoPicker) {
                Group {
                    if DemoStore.shared.isActive {
                        DemoPhotoPicker {
                            DemoStore.shared.addSamplePhotos(to: folder.id)
                            isShowingPhotoPicker = false
                            Task { await reload() }
                        }
                    } else {
                        PhotoPickerSheet { assets in Task { await uploadPhotos(assets) } }
                    }
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
            .alert(
                "문제가 생겼어요",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty {
            EmptyPhotoView()
        } else {
            PhotoGrid(photos: photos.filtered(by: filters))
                .refreshable { await reload() }
        }
    }

    private func reload() async {
        guard DemoStore.shared.isActive || SupabaseManager.client != nil else { return }
        do {
            photos = try await PhotoRepository.fetch(folderID: folder.id)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadPhotos(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        upload = UploadProgress(done: 0, total: assets.count)
        defer { upload = nil }
        do {
            try await PhotoRepository.upload(assets, to: folder.id) { done in
                upload?.done = done
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
    }

    /// 올리는 동안 위에 뜨는 작은 알림
    @ViewBuilder
    private var uploadBanner: some View {
        if let upload {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("사진 올리는 중 \(upload.done)/\(upload.total)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black800)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(.white, in: Capsule())
            .shallpickShadow(blur: 20)
            .padding(.top, 74)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - 상단 (246:5211)

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "뒤로") { dismiss() }

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

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색", action: onSearch)
                CircleIconButton(icon: .iconChat, accessibilityLabel: "채팅") {
                    if let onOpenChat {
                        onOpenChat()
                    } else {
                        chatAttachments = []
                        isShowingChat = true
                    }
                }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background(alignment: .top) { TopFade() }
    }

    // MARK: - 하단 (190:22267)

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 8) {
                PhotoFilterButton(isOpen: $isShowingFilterMenu, selection: $filters, avatarURL: avatarURL)
                OtterButton(accessibilityLabel: "질문에 첨부할 사진 고르기") {
                    isShowingFilterMenu = false
                    isShowingQuestionPicker = true
                }
            }

            Spacer()

            CircleIconButton(icon: .iconPlus, accessibilityLabel: "사진 올리기") {
                isShowingFilterMenu = false
                isShowingPhotoPicker = true
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
                AppImage(url: photo.url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipped()
    }
}

extension [PhotoItem] {
    /// "내사진" 은 내가 올린 것만. "좋아요" 는 좋아요 기능이 생기면 적용합니다.
    func filtered(by filters: Set<PhotoFilter>) -> [PhotoItem] {
        guard filters.contains(.mine), let me = PhotoRepository.currentUserID else { return self }
        return filter { $0.uploaderID == me }
    }
}

// MARK: - 사진 그리드

/// 4열 정사각형, 간격 10 (246:5209)
private struct PhotoGrid: View {
    let photos: [PhotoItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(photos) { photo in
                    FolderPhotoCell(photo: photo)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
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
                    AppImage(url: avatarURL) { phase in
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
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shallpickShadow(blur: 20)
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
