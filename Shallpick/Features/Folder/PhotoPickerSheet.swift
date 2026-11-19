import Photos
import SwiftUI

/// 폴더 화면의 + 버튼으로 여는 갤러리: 내 보관함 사진 4열 그리드에서 폴더에 올릴 사진 여러 장 고르기
/// Figma: 갤러리 (173:21698)
struct PhotoPickerSheet: View {
    /// 고른 순서대로
    let onConfirm: ([PHAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var access: PhotoLibrary.Access?
    @State private var assets: PHFetchResult<PHAsset>?
    @State private var selectedIDs: [String] = []
    @State private var favoritesOnly = false
    @State private var isShowingFilterMenu = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isShowingFilterMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isShowingFilterMenu = false }
                }
            }
            .overlay(alignment: .topTrailing) { confirmButton }
            .safeAreaInset(edge: .top, spacing: 0) { grabber }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .background(.white)
            .animation(.snappy(duration: 0.2), value: isShowingFilterMenu)
            .task {
                let result = await PhotoLibrary.requestAccess()
                access = result
                if result != .denied { reload() }
            }
            .onChange(of: favoritesOnly) { reload() }
    }

    private func reload() {
        assets = PhotoLibrary.fetchImages(favoritesOnly: favoritesOnly)
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case nil:
            ProgressView()
        case .denied:
            deniedView
        case .allowed, .limited:
            if let assets, assets.count > 0 {
                grid(assets)
            } else {
                Text(favoritesOnly ? "즐겨찾기한 사진이 없어요" : "사진이 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black400)
            }
        }
    }

    // MARK: - 사진들 (173:21701)

    private func grid(_ assets: PHFetchResult<PHAsset>) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<assets.count, id: \.self) { index in
                    cell(assets.object(at: index))
                        .dragSelectItem(index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 25)
        }
        .scrollIndicators(.hidden)
        // 사진 위를 옆으로 쓸면 지나간 사진을 한꺼번에 고름 (위아래는 스크롤).
        // 보관함이 클 수 있어 id 목록을 만들지 않고 순번으로 다룸
        .dragToSelect(
            ids: 0..<assets.count,
            isSelected: { selectedIDs.contains(assets.object(at: $0).localIdentifier) },
            apply: { changes in
                for change in changes {
                    let id = assets.object(at: change.id).localIdentifier
                    if change.selected {
                        if !selectedIDs.contains(id) { selectedIDs.append(id) }
                    } else {
                        selectedIDs.removeAll { $0 == id }
                    }
                }
            }
        )
    }

    private func cell(_ asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        let isSelected = selectedIDs.contains(id)
        return Button {
            toggle(id)
        } label: {
            AssetThumbnail(asset: asset)
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.2)
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

    private func toggle(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    // MARK: - 위

    /// 30pt 회색 선 (173:21700)
    private var grabber: some View {
        Capsule()
            .fill(Color.black200)
            .frame(width: 30, height: 2)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .background(.white)
    }

    /// 오른쪽 위 검정 체크 (237:26902). 하나도 안 골랐으면 눌리지 않음
    private var confirmButton: some View {
        // .disabled 는 버튼을 반투명하게 만들어 뒤 사진이 비치므로 쓰지 않음
        CircleIconButton(icon: .iconCheck, style: .filled, accessibilityLabel: "올리기") {
            guard !selectedIDs.isEmpty else { return }
            onConfirm(PhotoLibrary.assets(withIdentifiers: selectedIDs))
            dismiss()
        }
        .padding(.top, 4)
        .padding(.trailing, 24)
    }

    // MARK: - 아래 (203:22896)

    private var bottomBar: some View {
        HStack {
            filterButton
            Spacer()
            CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") { dismiss() }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .padding(.top, 16)
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

    private var filterButton: some View {
        CircleIconButton(
            icon: isShowingFilterMenu ? .iconClose : .iconFilter,
            accessibilityLabel: isShowingFilterMenu ? "필터 닫기" : "필터"
        ) {
            isShowingFilterMenu.toggle()
        }
        .overlay(alignment: .bottomLeading) {
            if isShowingFilterMenu {
                GalleryFilterMenu(
                    favoritesOnly: $favoritesOnly,
                    onClearSelection: { selectedIDs.removeAll() }
                )
                .fixedSize()
                .offset(y: -(45 + 12))
                .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .zIndex(1)
    }

    // MARK: - 권한 없음

    private var deniedView: some View {
        VStack(spacing: 10) {
            Image(.otterEmpty)
                .resizable()
                .scaledToFill()
                .frame(width: 167, height: 173.37)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("사진에 접근할 수 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text("설정에서 사진 접근을 허용해 주세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .multilineTextAlignment(.center)

            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black800)
            .padding(.top, 6)
        }
    }
}

/// 사진 왼쪽 위 동그라미 (Check 237:26720). 고르면 tint 색 + 흰 체크
struct SelectionCheck: View {
    let isOn: Bool
    var tint: Color = .black800

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(tint)
                Image(.iconCheck)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.white)
            } else {
                Circle().fill(.white)
                Circle().strokeBorder(Color.black400, lineWidth: 1)
            }
        }
        .frame(width: 22, height: 22)
        .padding(2)
    }
}

/// 즐겨찾기만 보기 / 선택 모두 해제 (필터 메뉴 162:20872 와 같은 모양)
private struct GalleryFilterMenu: View {
    @Binding var favoritesOnly: Bool
    let onClearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                favoritesOnly.toggle()
            } label: {
                HStack {
                    Text("즐겨찾기")
                        .font(.system(size: 16, weight: favoritesOnly ? .semibold : .medium))
                    Spacer(minLength: 0)
                    if favoritesOnly {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])

            Divider()

            Button(action: onClearSelection) {
                Text("선택 모두 해제")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.black800)
        .padding(20)
        .frame(width: 198)
        .shadowedBackground(.white, in: RoundedRectangle(cornerRadius: 16), blur: 20)
    }
}

#Preview {
    Color.black50
        .sheet(isPresented: .constant(true)) {
            PhotoPickerSheet { _ in }
                .presentationCornerRadius(36)
                .presentationDragIndicator(.hidden)
        }
}
