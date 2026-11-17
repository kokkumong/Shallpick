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
private struct FolderMiniIllustration: View {
    let folderName: String
    let photoURLs: [URL]

    /// 작은 폴더(59 × 59)가 이 그림에서 놓이는 위치
    private let folderOrigin = CGPoint(x: 13, y: 15)

    var body: some View {
        ZStack(alignment: .topLeading) {
            MiniPhotoFolder(photoURLs: photoURLs)
                .offset(x: folderOrigin.x, y: folderOrigin.y)

            Text(folderName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.folderTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72)
                .position(
                    x: folderOrigin.x + MiniPhotoFolder.frontFrame.midX,
                    y: folderOrigin.y + MiniPhotoFolder.frontFrame.maxY + 12
                )

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
