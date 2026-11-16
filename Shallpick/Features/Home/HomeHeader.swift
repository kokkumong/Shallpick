import SwiftUI

/// 메인 상단: 로고 + 검색 + 프로필 (148:9614)
struct HomeHeader: View {
    var avatarURL: URL?
    var onSearch: () -> Void = {}
    var onProfile: () -> Void = {}

    var body: some View {
        HStack {
            // 온보딩 로고와 같은 모양, 메인에서는 black800 (134:5272)
            Image(.shallpickLogo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.black800)
                .frame(width: 125, height: 28.84)
                .accessibilityLabel("Shallpick")
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconSearch, iconSize: 27, accessibilityLabel: "검색", action: onSearch)

                Button(action: onProfile) {
                    ProfileAvatar(url: avatarURL)
                        .frame(width: 45, height: 45)
                        .clipShape(Circle())
                        .shallpickShadow(blur: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("내 계정")
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 35)
        .background {
            // 위는 배경색, 아래로 갈수록 투명해져 스크롤 콘텐츠가 자연스럽게 가려짐
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
}

/// 프로필 사진. 없으면 기본 수달 이미지.
private struct ProfileAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(.defaultAvatar).resizable().scaledToFill()
            }
        }
        .background(.white)
    }
}

#Preview {
    VStack {
        HomeHeader()
        Spacer()
    }
    .background(Color.black50)
}
