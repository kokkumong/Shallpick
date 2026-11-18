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
struct QuestionPhotoImage: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(LinearGradient(colors: [.white, .blue50], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.black400)
                    } else {
                        ProgressView()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("사진")
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
/// 위치는 꼬리 끝이 point 에 오도록 놓음
struct QuestionPinBubble<Content: View>: View {
    /// 사진 안에서 꼬리 끝이 가리킬 점
    let point: CGPoint
    /// 사진 크기 (말풍선이 밖으로 나가지 않게)
    let bounds: CGSize
    @ViewBuilder var content: Content

    private let maxWidth: CGFloat = 220
    private let maxHeight: CGFloat = 160

    var body: some View {
        // 말풍선을 놓을 칸: 너비 maxWidth, 사진 안쪽으로 밀어 넣고 꼬리만 점을 가리킴
        let half = min(maxWidth, bounds.width) / 2
        let centerX = min(max(point.x, half + 6), bounds.width - half - 6)
        let tailOffset = point.x - centerX

        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black50, in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .bottom) {
                    BubbleTail()
                        .fill(Color.black50)
                        .frame(width: 8, height: 10)
                        .offset(x: tailOffset, y: 9.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .frame(width: half * 2, height: maxHeight)
        .position(x: centerX, y: point.y - 18 - maxHeight / 2)
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
