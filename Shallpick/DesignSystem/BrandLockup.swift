import SwiftUI

/// 수달 캐릭터 + Shallpick 로고 묶음. 온보딩/로그인 화면에서 같이 씁니다.
/// Figma: 134:5564 (온보딩), 148:12413 (로그인)
struct BrandLockup: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(.otterMascot)
                .resizable()
                .scaledToFill()
                .frame(width: 188, height: 195.18)
                .clipped()
                .accessibilityHidden(true)

            Image(.shallpickLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 147.36, height: 34)
                .accessibilityLabel("Shallpick")
        }
    }
}

extension View {
    /// 온보딩 → 로그인 전환 시 BrandLockup 이 제자리에서 이동하도록 연결합니다.
    @ViewBuilder
    func brandLockupGeometry(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "brandLockup", in: namespace)
        } else {
            self
        }
    }
}

#Preview {
    BrandLockup()
}
