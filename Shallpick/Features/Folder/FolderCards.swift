import SwiftUI
import UniformTypeIdentifiers

/// 메인 화면 폴더 목록 (리스트)
/// 길게 눌러 끌면 순서를 바꿀 수 있음 (canReorder 일 때)
/// Figma: 메인_수정 (570:13095)
struct FolderCollectionView: View {
    let folders: [Folder]
    /// 검색 중에는 일부만 보여서 끄기
    var canReorder = false
    var onSelect: (Folder) -> Void = { _ in }
    var onInvite: (Folder) -> Void = { _ in }
    /// 끌고 있는 폴더가 다른 폴더 위에 올라가면 그 자리로 (옮길 때마다 저장)
    var onMove: (_ folderID: UUID, _ targetID: UUID) -> Void = { _, _ in }

    /// 지금 끌고 있는 폴더. 놓을 곳 밖에서 끝나면 알 수 없어서 다음에 끌 때 바뀜
    @State private var draggingID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 40) {
                ForEach(folders) { folder in
                    reorderable(folder) {
                        cell(folder) { FolderListCard(folder: folder) }
                    }
                }
            }
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // 폴더 사이 빈 곳에 놓아도 받아 줌
        .onDrop(of: [.text], isTargeted: nil) { _ in true }
    }

    @ViewBuilder
    private func reorderable(_ folder: Folder, @ViewBuilder content: () -> some View) -> some View {
        if canReorder {
            content()
                .onDrag {
                    draggingID = folder.id
                    return NSItemProvider(object: folder.id.uuidString as NSString)
                } preview: {
                    FolderListCard(folder: folder)
                }
                .onDrop(
                    of: [.text],
                    delegate: FolderDropDelegate(target: folder.id, draggingID: draggingID, onMove: onMove)
                )
        } else {
            content()
        }
    }

    private func cell(_ folder: Folder, @ViewBuilder content: () -> some View) -> some View {
        Button { onSelect(folder) } label: { content() }
            .buttonStyle(.plain)
            .contextMenu {
                Button("초대하기", systemImage: "person.badge.plus") { onInvite(folder) }
            }
            .accessibilityLabel(folder.name)
            .accessibilityValue(folder.memberSummary)
    }
}

/// 끌고 있는 폴더가 이 폴더 위로 들어오면 바로 자리를 바꿔 줌
private struct FolderDropDelegate: DropDelegate {
    let target: UUID
    let draggingID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target else { return }
        withAnimation(.snappy(duration: 0.25)) { onMove(draggingID, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool { true }
}

extension Folder {
    var memberSummary: String { memberNames.joined(separator: ", ") }
}

// MARK: - 폴더 그림 (질문 알림 카드)

/// 폴더 뒷면 (탭이 달린 모양, 148:8281)
nonisolated struct FolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Figma 원본 좌표 (150 × 130.22) 를 rect 크기에 맞춰 늘림
        let sx = rect.width / 150, sy = rect.height / 130.22
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }

        var path = Path()
        path.move(to: p(68.893, 0))
        path.addCurve(to: p(73.502, 2.1592), control1: p(70.673, 0), control2: p(72.362, 0.7912))
        path.addLine(to: p(84.414, 15.2533))
        path.addCurve(to: p(90.56, 18.1318), control1: p(85.934, 17.0773), control2: p(88.185, 18.1318))
        path.addLine(to: p(142, 18.1318))
        path.addCurve(to: p(150, 26.1318), control1: p(146.418, 18.1318), control2: p(150, 21.7136))
        path.addLine(to: p(150, 122.22))
        path.addCurve(to: p(142, 130.22), control1: p(150, 126.638), control2: p(146.418, 130.22))
        path.addLine(to: p(8, 130.22))
        path.addCurve(to: p(0, 122.22), control1: p(3.5817, 130.22), control2: p(0, 126.638))
        path.addLine(to: p(0, 6))
        path.addCurve(to: p(6, 0), control1: p(0, 2.6863), control2: p(2.6863, 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - 리스트 카드

/// 사진 4장이 부채꼴로 겹친 모양 + 이름 (148:9198, 폭 339)
struct FolderListCard: View {
    let folder: Folder

    private let photoSize = CGSize(width: 108.34, height: 144.45)

    var body: some View {
        VStack(spacing: 18) {
            // 아래 두 장(0, 2) 위에 두 장(1, 3)이 겹침
            ZStack(alignment: .topLeading) {
                photo(0, rotation: 4, center: CGPoint(x: 59.07, y: 86.83))
                photo(2, rotation: 4, center: CGPoint(x: 209.37, y: 86.83))
                photo(1, rotation: -4, center: CGPoint(x: 130.07, y: 75.83))
                photo(3, rotation: -4, center: CGPoint(x: 280.37, y: 75.83))
            }
            .frame(width: 339.45, height: 162.65)

            VStack(spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text(folder.memberSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black400)
            }
            .lineLimit(1)
            .frame(width: 339.45)
        }
    }

    private func photo(_ index: Int, rotation: Double, center: CGPoint) -> some View {
        FolderPhoto(url: folder.coverPhotoURLs[safe: index], cornerRadius: 10)
            .frame(width: photoSize.width, height: photoSize.height)
            .rotationEffect(.degrees(rotation))
            .position(center)
    }
}

// MARK: - 사진 한 장

/// 표지 사진. 사진이 없으면 빈 카드. (Figma: photo 3:4, DropShadow_photo)
struct FolderPhoto: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(colors: [.white, .blue50], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.25), radius: 5)
    }
}

/// 사진 3장이 꽂힌 작은 폴더 (59 × 59, 앞면이 아래로 3pt 넘침)
/// 예전 메인 화면 그리드 카드(150 × 165)를 59/150 배로 줄인 배치. 질문 알림 카드에 씀
/// Figma: 응답요청알람 (237:27204)
struct MiniPhotoFolder: View {
    let photoURLs: [URL?]

    init(photoURLs: [URL?]) {
        self.photoURLs = photoURLs
    }

    init(photoURLs: [URL]) {
        self.photoURLs = photoURLs.map(Optional.some)
    }

    static let size = CGSize(width: 59, height: 59)
    static let frontFrame = CGRect(x: 0, y: 27, width: 59, height: 35)

    private let scale: CGFloat = 59 / 150
    /// 그리드 카드 좌표 (0, 0) 이 이 그림에서 놓이는 위치
    private let origin = CGPoint(x: 0, y: -2.96)
    private let photoSize = CGSize(width: 29.16, height: 38.88)

    var body: some View {
        ZStack(alignment: .topLeading) {
            FolderBackShape()
                .fill(Color.brandBlue)
                .frame(width: 59.21, height: 51.4)
                .shallpickShadow(blur: 20)
                .offset(y: 10.82)

            photo(1, rotation: 4, gridCenter: CGPoint(x: 99.28, y: 51.7))
            photo(0, rotation: -4, gridCenter: CGPoint(x: 50.28, y: 62.7))
            photo(2, rotation: 0, gridCenter: CGPoint(x: 74.5, y: 84.28))

            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.brandBlue, .folderBlueBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: Self.frontFrame.width, height: Self.frontFrame.height)
                .shadow(color: .black.opacity(0.25), radius: 5)
                .offset(x: Self.frontFrame.minX, y: Self.frontFrame.minY)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func photo(_ index: Int, rotation: Double, gridCenter: CGPoint) -> some View {
        FolderPhoto(url: photoURLs[safe: index] ?? nil, cornerRadius: 4)
            .frame(width: photoSize.width, height: photoSize.height)
            .rotationEffect(.degrees(rotation))
            .position(x: origin.x + gridCenter.x * scale, y: origin.y + gridCenter.y * scale)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

extension Folder {
    static let previews: [Folder] = (1...5).map { i in
        Folder(
            id: UUID(), name: "HCI팀플모임 \(i)", ownerID: UUID(), inviteCode: "K7QX2M",
            memberNames: ["김승완", "신지원", "정규호", "차현서"]
        )
    }
}

#Preview {
    FolderCollectionView(folders: Folder.previews)
        .background(Color.black50)
}
