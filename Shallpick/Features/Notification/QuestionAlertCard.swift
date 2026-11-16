import SwiftUI

/// 앱을 쓰는 중에 화면 가운데 뜨는 질문 알림
/// Figma: 응답요청알람_앱내부 (237:27235, 273 × 358)
struct QuestionAlertCard: View {
    let alert: QuestionAlert
    var onRespond: () -> Void = {}
    var onLater: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                FolderMiniIllustration(folderName: alert.folder.name, photoURLs: alert.photoURLs)

                VStack(spacing: 4) {
                    Text(alert.headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black400)
                        .lineLimit(1)
                    Text(alert.question)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black800)
                        .lineLimit(3)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 8) {
                Button(action: onRespond) {
                    Text("바로 응답하기")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(Color.black800, in: Capsule())
                        .contentShape(Capsule())
                }
                Button(action: onLater) {
                    Text("나중에!")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black800)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(Color.black50, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.black200, lineWidth: 1) }
                        .contentShape(Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 273)
        // 그림자는 배경에만 (글자·버튼에 번지지 않게)
        .background {
            RoundedRectangle(cornerRadius: 36)
                .fill(.white)
                .shallpickShadow()
        }
    }
}

/// 사진이 꽂힌 작은 폴더 + 폴더 이름 + 가리키는 수달 (237:27204, 167 × 153)
/// 메인 화면 그리드 카드(FolderGridCard)를 0.3933 배로 줄인 배치와 같습니다.
private struct FolderMiniIllustration: View {
    let folderName: String
    let photoURLs: [URL]

    private let scale: CGFloat = 59 / 150
    /// 그리드 카드 좌표 (0, 0) 이 이 그림에서 놓이는 위치
    private let origin = CGPoint(x: 13, y: 12.04)
    private let photoSize = CGSize(width: 29.16, height: 38.88)
    private let frontFrame = CGRect(x: 13, y: 42, width: 59, height: 35)

    var body: some View {
        ZStack(alignment: .topLeading) {
            FolderBackShape()
                .fill(Color.brandBlue)
                .frame(width: 59.21, height: 51.4)
                .shallpickShadow(blur: 20)
                .offset(x: 13, y: 25.82)

            photo(1, rotation: 4, gridCenter: CGPoint(x: 99.28, y: 51.7))
            photo(0, rotation: -4, gridCenter: CGPoint(x: 50.28, y: 62.7))
            photo(2, rotation: 0, gridCenter: CGPoint(x: 74.5, y: 84.28))

            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.brandBlue, .folderBlueBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: frontFrame.width, height: frontFrame.height)
                .shadow(color: .black.opacity(0.25), radius: 5)
                .offset(x: frontFrame.minX, y: frontFrame.minY)

            Text(folderName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.folderTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72)
                .position(x: frontFrame.midX, y: frontFrame.maxY + 12)

            Image(.otterPoint)
                .resizable()
                .scaledToFill()
                .frame(width: 113, height: 118)
                .offset(x: 60, y: 30)
                .accessibilityHidden(true)
        }
        .frame(width: 167, height: 153, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folderName) 폴더")
    }

    private func photo(_ index: Int, rotation: Double, gridCenter: CGPoint) -> some View {
        FolderPhoto(url: photoURLs[safe: index], cornerRadius: 4)
            .frame(width: photoSize.width, height: photoSize.height)
            .rotationEffect(.degrees(rotation))
            .position(x: origin.x + gridCenter.x * scale, y: origin.y + gridCenter.y * scale)
    }
}

/// 화면 전체를 어둡게 덮고 가운데 알림 카드를 띄움
struct QuestionAlertOverlay: View {
    let center: QuestionAlertCenter
    var onRespond: (QuestionAlert) -> Void

    var body: some View {
        ZStack {
            if let alert = center.current {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                QuestionAlertCard(
                    alert: alert,
                    onRespond: {
                        center.dismissCurrent()
                        onRespond(alert)
                    },
                    onLater: { center.dismissCurrent() }
                )
                .id(alert.id)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.snappy(duration: 0.25), value: center.current?.id)
    }
}

#Preview {
    QuestionAlertCard(
        alert: QuestionAlert(
            id: UUID(),
            folder: Folder.previews[0],
            askerNickname: "현서",
            question: "이 사진 인스타 스토리에 올려도 돼?",
            photoURLs: (1...3).compactMap { URL(string: "https://picsum.photos/seed/\($0)/300/400") }
        )
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.4))
}
