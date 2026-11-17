import SwiftUI

/// 메인 화면 폴더 목록 (그리드 / 리스트)
/// Figma: 메인_그리드_폴더버전 (246:5191), 메인_리스트 (246:5246)
struct FolderCollectionView: View {
    let folders: [Folder]
    let layout: FolderLayout
    var onSelect: (Folder) -> Void = { _ in }
    var onInvite: (Folder) -> Void = { _ in }

    var body: some View {
        ScrollView {
            Group {
                switch layout {
                case .grid: grid
                case .list: list
                }
            }
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    /// 2열, 마지막 한 개는 가운데 (246:5204)
    private var grid: some View {
        LazyVStack(spacing: 40) {
            ForEach(rows, id: \.first!.id) { row in
                HStack(spacing: 30) {
                    ForEach(row) { folder in
                        cell(folder) { FolderGridCard(folder: folder) }
                    }
                }
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 40) {
            ForEach(folders) { folder in
                cell(folder) { FolderListCard(folder: folder) }
            }
        }
    }

    private var rows: [[Folder]] {
        stride(from: 0, to: folders.count, by: 2).map {
            Array(folders[$0 ..< min($0 + 2, folders.count)])
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

extension Folder {
    var memberSummary: String { memberNames.joined(separator: ", ") }
}

// MARK: - 그리드 카드

/// 파란 폴더에 사진 3장이 꽂힌 모양 (148:8314, 150 × 165)
struct FolderGridCard: View {
    let folder: Folder

    private let photoSize = CGSize(width: 73.87, height: 98.49)

    var body: some View {
        ZStack(alignment: .topLeading) {
            FolderBackShape()
                .fill(Color.brandBlue)
                .frame(width: 150, height: 130.22)
                .shallpickShadow()
                .offset(y: 35)

            photo(0, rotation: -4, center: CGPoint(x: 50.28, y: 62.7))
            photo(1, rotation: 4, center: CGPoint(x: 99.28, y: 51.7))
            photo(2, rotation: 0, center: CGPoint(x: 74.5, y: 84.28))

            // 폴더 앞면 (148:8282)
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.folderTitle)
                Text(folder.memberSummary)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.folderSubtitle)
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.top, 55)
            .frame(width: 150, height: 89, alignment: .topLeading)
            .background(
                LinearGradient(colors: [.brandBlue, .folderBlueBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .shadow(color: .black.opacity(0.25), radius: 5)
            .offset(y: 76)
        }
        .frame(width: 150, height: 165.22, alignment: .topLeading)
    }

    private func photo(_ index: Int, rotation: Double, center: CGPoint) -> some View {
        FolderPhoto(url: folder.coverPhotoURLs[safe: index], cornerRadius: 8)
            .frame(width: photoSize.width, height: photoSize.height)
            .rotationEffect(.degrees(rotation))
            .position(center)
    }
}

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
                    AppImage(url: url) { image in
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
/// 메인 화면 그리드 카드(FolderGridCard)를 59/150 배로 줄인 배치. 질문 알림 / 채팅 첨부에 씀
/// Figma: 채팅 Component 14·17 (234:23864), 응답요청알람 (237:27204)
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

#Preview("그리드") {
    FolderCollectionView(folders: Folder.previews, layout: .grid)
        .background(Color.black50)
}

#Preview("리스트") {
    FolderCollectionView(folders: Folder.previews, layout: .list)
        .background(Color.black50)
}
