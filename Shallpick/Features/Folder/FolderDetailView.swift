import SwiftUI

/// 폴더를 눌렀을 때 들어가는 화면: 사진 4열 그리드 + 상단(뒤로/이름/검색/채팅) + 하단(필터/수달/추가)
/// Figma: 폴더안 (246:5208)
struct FolderDetailView: View {
    let folder: Folder
    var avatarURL: URL?
    /// 사진 기능이 생기면 채웁니다.
    var photoURLs: [URL] = []
    var onSearch: () -> Void = {}
    var onChat: () -> Void = {}
    var onOtter: () -> Void = {}
    var onAddPhoto: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var filters: Set<PhotoFilter> = []
    @State private var isShowingFilterMenu = false

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
            .toolbar(.hidden, for: .navigationBar)
            .animation(.snappy(duration: 0.2), value: isShowingFilterMenu)
    }

    @ViewBuilder
    private var content: some View {
        if photoURLs.isEmpty {
            EmptyPhotoView()
        } else {
            PhotoGrid(urls: photoURLs)
        }
    }

    // MARK: - 상단 (246:5211)

    private var header: some View {
        HStack(spacing: 0) {
            CircleIconButton(icon: .iconBack, accessibilityLabel: "뒤로") { dismiss() }

            Text(folder.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black800)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색", action: onSearch)
                CircleIconButton(icon: .iconChat, accessibilityLabel: "채팅", action: onChat)
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

    // MARK: - 하단 (190:22267)

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 8) {
                filterButton
                otterButton
            }

            Spacer()

            CircleIconButton(icon: .iconPlus, accessibilityLabel: "사진 추가", action: onAddPhoto)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .background {
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
    private var filterButton: some View {
        CircleIconButton(
            icon: isShowingFilterMenu ? .iconClose : .iconFilter,
            accessibilityLabel: isShowingFilterMenu ? "필터 닫기" : "필터"
        ) {
            isShowingFilterMenu.toggle()
        }
        .overlay(alignment: .bottomLeading) {
            if isShowingFilterMenu {
                PhotoFilterMenu(selection: $filters, avatarURL: avatarURL)
                    .fixedSize()
                    .offset(y: -(45 + 12))
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .zIndex(1)
    }

    /// Component 3 (179:22169): 흰 동그라미 안에 수달
    private var otterButton: some View {
        Button(action: onOtter) {
            Image(.otterQuestion)
                .resizable()
                .scaledToFill()
                .frame(width: 53, height: 55)
                .offset(x: 1, y: 4)
                .frame(width: 45, height: 45)
                .background(.white)
                .clipShape(Circle())
                .shallpickShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("수달")
    }
}

// MARK: - 사진 그리드

/// 4열 정사각형, 간격 10 (246:5209)
private struct PhotoGrid: View {
    let urls: [URL]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    Color.blue50
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.clear
                            }
                        }
                        .clipped()
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
private struct PhotoFilterMenu: View {
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
                    AsyncImage(url: avatarURL) { phase in
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

#Preview("사진 있음") {
    NavigationStack {
        FolderDetailView(
            folder: Folder.previews[0],
            photoURLs: (1...40).compactMap { URL(string: "https://picsum.photos/seed/\($0)/200") }
        )
    }
}

#Preview("비어 있음") {
    NavigationStack {
        FolderDetailView(folder: Folder.previews[0])
    }
}
