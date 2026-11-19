import SwiftUI

/// A demonstration only: never invokes the response view's gesture or vote actions.
struct SwipeGuideView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var direction = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("사진을 위아래로 넘겨 답해요")
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("↑ 싫어")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(direction == -1 ? Color.brandBlue : Color.black600)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.blue50)
                Image(systemName: "photo")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.black600)
            }
            .frame(width: 82, height: 100)
            .offset(y: reduceMotion ? 0 : CGFloat(direction) * 22)
            .padding(.vertical, 22)
            .accessibilityHidden(true)
            Text("↓ 좋아")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(direction == 1 ? Color.brandBlue : Color.black600)
            Text("예시예요. 답변은 전송되지 않아요.")
                .font(.system(size: 11))
                .foregroundStyle(Color.black600)
                .multilineTextAlignment(.center)
            Button("건너뛰기", action: onFinish)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 80, minHeight: 44)
                .accessibilityIdentifier("question.swipeGuide.skip")
        }
        .foregroundStyle(Color.black800)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("question.swipeGuide")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            do {
                direction = 0
                try await Task.sleep(for: .milliseconds(350))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { direction = -1 }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { direction = 0 }
                try await Task.sleep(for: .milliseconds(350))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { direction = 1 }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { direction = 0 }
                try await Task.sleep(for: .milliseconds(1500))
                onFinish()
            } catch { /* Leaving the view cancels the demonstration without recording completion. */ }
        }
    }
}
