import ImageIO
import SwiftUI

// 사진 질문 응답/결과 화면이 같이 쓰는 조각들
// Figma: 요청응답 (540:11455), 요청응답_가이드 (549:11607)

/// 사진 크기: 가로 342 × 세로 457 (Rectangle 115). 화면이 작으면 같은 비율로 줄임
enum QuestionPhotoLayout {
    static let designSize = CGSize(width: 342, height: 457)

    /// width: 사진에 쓸 수 있는 가로, maxHeight: 사진에 쓸 수 있는 세로
    static func size(width: CGFloat, maxHeight: CGFloat = .infinity) -> CGSize {
        let ratio = designSize.height / designSize.width
        var size = CGSize(width: min(designSize.width, width), height: 0)
        size.height = size.width * ratio
        if size.height > maxHeight, maxHeight > 0 {
            size = CGSize(width: maxHeight / ratio, height: maxHeight)
        }
        return size
    }
}

/// 위: 폴더 이름(B20) + 작은 프로필과 이름(M12), 오른쪽: 검정 체크 (Figma 위 549:11581)
struct QuestionHeader: View {
    let title: String
    let avatarURL: URL?
    let subtitle: String
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.black800)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ChatAvatar(url: avatarURL)
                        .frame(width: 18, height: 18)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black400)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            CircleIconButton(icon: .iconCheck, style: .filled, accessibilityLabel: "완료", action: onDone)
        }
        .frame(height: 45)
        .padding(.horizontal, 29)
        .padding(.top, 11)
    }
}

/// 사진 위 "싫어", 아래 "좋아" (아이콘 26 + M12, 간격 6). 넘기는 쪽으로 커지고 진해짐
struct QuestionVoteLabel: View {
    let vote: QuestionVote
    /// 0 ~ 1: 그쪽으로 얼마나 넘겼는지
    var emphasis: CGFloat = 0
    /// 이미 이쪽으로 남겼으면 파랗게
    var isChosen = false

    private var color: Color {
        isChosen ? .brandBlue : (emphasis > 0.6 ? .black800 : .black600)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(vote == .like ? .iconLike : .iconDislike)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text(vote.label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .frame(width: 40, height: 46)
        .scaleEffect(1 + emphasis * 0.35)
        .animation(.snappy(duration: 0.15), value: emphasis > 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// 사진 양옆 < > (8 × 17, black400)
struct QuestionChevronButton: View {
    enum Direction { case previous, next }

    let direction: Direction
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.iconChevronRight)
                .resizable()
                .scaledToFit()
                .frame(width: 8, height: 17)
                .rotationEffect(.degrees(direction == .previous ? 180 : 0))
                .foregroundStyle(Color.black400)
                .frame(width: 8, height: 44)
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0)
        .disabled(!isEnabled)
        .accessibilityLabel(direction == .previous ? "이전 사진" : "다음 사진")
    }
}

/// 질문 사진 (모서리 20, 꽉 채움)
/// 미리 받아 둔 사진이면 첫 화면부터 바로 그려서, 넘길 때 빈칸·끊김이 없게 함
struct QuestionPhotoImage: View {
    let url: URL?

    @State private var loaded: UIImage?
    @State private var didFail = false

    private var image: UIImage? {
        loaded ?? url.flatMap(QuestionPhotoLoader.shared.cachedImage(for:))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(LinearGradient(colors: [.white, .blue50], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if didFail {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.black400)
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("사진")
            .task(id: url) {
                guard let url else { return }
                didFail = false
                loaded = await QuestionPhotoLoader.shared.image(for: url)
                didFail = loaded == nil
            }
    }
}

/// 질문 화면 사진을 화면 크기에 맞게 줄여서 미리 풀어 둠.
/// 원본(수 MB)을 넘기는 순간 화면에서 풀면 애니메이션이 끊겨서, 다음 사진들은 뒤에서 먼저 준비합니다.
final class QuestionPhotoLoader {
    static let shared = QuestionPhotoLoader()

    /// 사진 칸(최대 342 × 457pt)을 3배 화면에서 채울 만큼
    nonisolated private static let maxPixelSize: CGFloat = 1400

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 30
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        let task: Task<UIImage?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            task = Task { await Self.decode(url) }
            inFlight[url] = task
        }
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// 곧 보게 될 사진들을 미리 받아서 풀어 둠
    func prefetch(_ urls: [URL]) {
        for url in urls where cachedImage(for: url) == nil && inFlight[url] == nil {
            Task { _ = await image(for: url) }
        }
    }

    @concurrent
    nonisolated private static func decode(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 여기(백그라운드)에서 다 풀어 둬야 화면에 그릴 때 안 멈춤
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// 사진 위 댓글 자리 (Figma Group 53: 27 → 20.25 → 13.5 흰 원)
struct QuestionPinDot: View {
    var isHighlighted = false

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(isHighlighted ? 0.45 : 0.2)).frame(width: 27, height: 27)
            Circle().fill(.white.opacity(isHighlighted ? 0.45 : 0.2)).frame(width: 20.25, height: 20.25)
            Circle().fill(.white).frame(width: 13.5, height: 13.5)
                .shadow(color: .black.opacity(0.25), radius: 2)
        }
        .scaleEffect(isHighlighted ? 1.2 : 1)
        .animation(.snappy(duration: 0.2), value: isHighlighted)
    }
}

/// 꼬리가 아래로 달린 말풍선 (Figma Union 549:11692: 모서리 16, #FAFAFA, M12)
/// 꼬리는 점 바로 위를 가리키고, 말풍선은 실제 글자 폭만큼만 차지하면서 사진 안으로 밀려 들어옴
struct QuestionPinBubble<Content: View>: View {
    /// 사진 안에서 꼬리가 가리킬 점
    let point: CGPoint
    /// 사진 크기 (말풍선이 밖으로 나가지 않게)
    let bounds: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        PinBubbleLayout(point: point) {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black50))
            BubbleTail()
                .fill(Color.black50)
        }
        // 말풍선과 꼬리를 한 덩어리로 그려서 그림자가 이음새 없이 하나로 (글자에는 안 번짐)
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .frame(width: bounds.width, height: bounds.height)
    }

    /// 말풍선의 실제 크기를 재서 놓고, 꼬리는 그 말풍선 아래 테두리에 붙여서 점 쪽으로 놓음
    /// (예전엔 220 폭 칸 기준으로 꼬리를 옮겨서, 글자가 짧으면 꼬리만 멀리 떨어져 보였음)
    private struct PinBubbleLayout: Layout {
        let point: CGPoint
        let maxWidth: CGFloat = 220
        let tailSize = CGSize(width: 8, height: 10)
        /// 꼬리 끝과 점 가운데 사이
        let tipGap: CGFloat = 8.5
        /// 둥근 모서리에 꼬리가 걸리지 않게 (모서리 16 + 꼬리 반 폭)
        let tailInset: CGFloat = 20

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard subviews.count == 2 else { return }
            let bubble = subviews[0].sizeThatFits(ProposedViewSize(width: min(maxWidth, bounds.width), height: nil))

            let pointX = bounds.minX + point.x
            let tipY = bounds.minY + point.y - tipGap
            // 꼬리 위쪽 0.5 를 말풍선에 겹쳐서 틈이 안 보이게
            let bubbleBottom = tipY - tailSize.height + 0.5

            let maxOriginX = max(bounds.minX, bounds.maxX - bubble.width)
            let originX = min(max(pointX - bubble.width / 2, bounds.minX), maxOriginX)
            subviews[0].place(
                at: CGPoint(x: originX, y: bubbleBottom - bubble.height),
                proposal: ProposedViewSize(bubble)
            )

            let low = originX + tailInset
            let high = originX + bubble.width - tailInset
            let tailX = low <= high ? min(max(pointX, low), high) : originX + bubble.width / 2
            subviews[1].place(
                at: CGPoint(x: tailX, y: bubbleBottom - 0.5),
                anchor: .top,
                proposal: ProposedViewSize(tailSize)
            )
        }
    }

    nonisolated private struct BubbleTail: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.midX + 1, y: rect.maxY - 2)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control: CGPoint(x: rect.midX - 1, y: rect.maxY - 2)
            )
            return path
        }
    }
}
