import SwiftUI

/// 폴더 화면의 수달 버튼으로 여는 화면: 폴더 사진 중에서 질문에 첨부할 사진 고르기
/// Figma: 질문버튼클릭시 (328:4864)
struct FolderPhotoSelectView: View {
    let photos: [PhotoItem]
    var avatarURL: URL?
    /// → 를 누르면 고른 순서대로
    let onNext: ([PhotoItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: [UUID] = []
    @State private var filters: Set<PhotoFilter> = []
    @State private var isShowingFilterMenu = false
    @State private var likedIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black50)
            .overlay {
                if isShowingFilterMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isShowingFilterMenu = false }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .animation(.snappy(duration: 0.2), value: isShowingFilterMenu)
            .task {
                do { likedIDs = try await PhotoFeedbackRepository.likedPhotoIDs(in: photos) }
                catch { errorMessage = "좋아요 목록을 불러오지 못했어요. 다시 열어 주세요." }
            }
            .alert("사진 선택", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        let visible = photos.filtered(by: filters, likedIDs: likedIDs)
        if visible.isEmpty {
            VStack(spacing: 10) {
                Image(.otterEmpty)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 167, height: 173.37)
                    .clipped()
                    .accessibilityHidden(true)
                Text(photos.isEmpty ? "폴더에 아직 사진이 없어요" : "조건에 맞는 사진이 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visible) { photo in
                        cell(photo)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func cell(_ photo: PhotoItem) -> some View {
        let isSelected = selectedIDs.contains(photo.id)
        return Button {
            if let index = selectedIDs.firstIndex(of: photo.id) {
                selectedIDs.remove(at: index)
            } else {
                guard selectedIDs.count < ChatRepository.maxPhotos else { errorMessage = "사진은 30장까지 고를 수 있어요"; return }
                selectedIDs.append(photo.id)
            }
        } label: {
            FolderPhotoCell(photo: photo)
                .overlay {
                    if isSelected {
                        Rectangle().strokeBorder(Color.black800, lineWidth: 4)
                    }
                }
                .overlay(alignment: .topLeading) {
                    SelectionCheck(isOn: isSelected)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("사진")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 위 (질문사진선택_위 328:5553)

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") { dismiss() }

            Text("질문에 첨부할 사진 선택")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black800)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            // 선택이 없을 때는 다음 단계로 넘어가지 않음
            CircleIconButton(icon: .iconNext, style: .filled, accessibilityLabel: "다음") {
                let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
                let selected = selectedIDs.compactMap { byID[$0] }
                guard !selected.isEmpty else { return }
                onNext(selected)
                dismiss()
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background(alignment: .top) { TopFade() }
    }

    // MARK: - 아래 (질문선택시 328:5554)

    private var bottomBar: some View {
        HStack {
            PhotoFilterButton(isOpen: $isShowingFilterMenu, selection: $filters, avatarURL: avatarURL)
            Spacer()
            Text("\(selectedIDs.count) / 30장").font(.system(size: 13)).foregroundStyle(Color.black600)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .background { BottomFade() }
    }
}

#Preview {
    FolderPhotoSelectView(photos: PhotoItem.previews) { _ in }
}
