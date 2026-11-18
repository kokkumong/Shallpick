import SwiftUI

/// 메인 상단: 로고 + 검색 + 프로필 (148:9614)
/// 검색 버튼을 누르면 로고가 사라지고 그 자리에 검색창이 펼쳐집니다.
struct HomeHeader: View {
    var avatarURL: URL?
    @Binding var searchText: String
    @Binding var isSearching: Bool
    var onProfile: () -> Void = {}

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .trailing) {
                if isSearching {
                    searchField
                        .transition(reduceMotion ? .opacity :
                            .asymmetric(
                                insertion: .scale(scale: 0.96, anchor: .trailing).combined(with: .opacity),
                                removal: .scale(scale: 0.96, anchor: .trailing).combined(with: .opacity)
                            )
                        )
                } else {
                    // 온보딩 로고와 같은 모양, 메인에서는 black800 (134:5272)
                    Image(.shallpickLogo)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.black800)
                        .frame(width: 125, height: 28.84)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Shallpick")
                        .accessibilityAddTraits(.isHeader)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -12)))
                }
            }
            .frame(maxWidth: .infinity)

            CircleIconButton(
                icon: isSearching ? .iconClose : .iconSearch,
                iconSize: isSearching ? 24 : 27,
                accessibilityLabel: isSearching ? "검색 닫기" : "검색",
                action: toggleSearch
            )

            Button(action: onProfile) {
                ProfileAvatar(url: avatarURL)
                    .frame(width: 45, height: 45)
                    .clipShape(Circle())
                    .floatingShadow()
            }
            .buttonStyle(ShallpickPressStyle())
            .accessibilityLabel("내 계정")
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

extension HomeHeader {
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(.iconSearch)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.black400)
                .accessibilityHidden(true)

            TextField("폴더 이름, 참여자 검색", text: $searchText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black800)
                .focused($isFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { isFieldFocused = false }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.black400)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 45)
        .background(.white, in: Capsule())
        .shallpickShadow(blur: 20)
        .onAppear { isFieldFocused = true }
    }

    private func toggleSearch() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            if isSearching {
                searchText = ""
                isFieldFocused = false
            }
            isSearching.toggle()
        }
    }
}

/// 프로필 사진. 없으면 기본 수달 이미지.
private struct ProfileAvatar: View {
    let url: URL?

    var body: some View {
        AppImage(url: url) { phase in
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
    @Previewable @State var text = ""
    @Previewable @State var isSearching = false
    VStack {
        HomeHeader(searchText: $text, isSearching: $isSearching)
        Spacer()
    }
    .background(Color.black50)
}
