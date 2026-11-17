import SwiftUI

enum FolderLayout: CaseIterable {
    case grid
    case list
}

/// 메인 하단: Grid/List 전환 + 폴더 추가 (148:9639)
/// 알림 내역은 상단 프로필 버튼 메뉴로 옮김
struct HomeBottomBar: View {
    @Binding var layout: FolderLayout
    var onCreateFolder: () -> Void = {}
    var onJoinWithCode: () -> Void = {}
    var onJoinWithQR: () -> Void = {}

    var body: some View {
        HStack {
            FolderLayoutPicker(selection: $layout)

            Spacer()

            Menu {
                Button("새 폴더 만들기", systemImage: "folder.badge.plus", action: onCreateFolder)
                Button("코드로 참여하기", systemImage: "number", action: onJoinWithCode)
                Button("QR로 참여하기", systemImage: "qrcode.viewfinder", action: onJoinWithQR)
            } label: {
                CircleIcon(icon: .iconPlus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("폴더 추가")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 33)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black50.opacity(0), location: 0),
                    .init(color: .black50, location: 0.889),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Segment_Grid (148:9617)
struct FolderLayoutPicker: View {
    @Binding var selection: FolderLayout
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FolderLayout.allCases, id: \.self) { layout in
                Button {
                    selection = layout
                } label: {
                    VStack(spacing: 3) {
                        icon(for: layout)
                        Text(title(for: layout))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == layout ? Color.black800 : Color.black600)
                    .frame(width: 62, height: 39)
                    .background {
                        // 스위치처럼 선택한 쪽으로 동그라미가 미끄러져 감
                        if selection == layout {
                            Capsule()
                                .fill(Color.blue50)
                                .matchedGeometryEffect(id: "selected", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == layout ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white, in: Capsule())
        .floatingShadow()
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private func title(for layout: FolderLayout) -> String {
        switch layout {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    @ViewBuilder
    private func icon(for layout: FolderLayout) -> some View {
        let cell: CGFloat = 7.442
        let gap: CGFloat = 1.118
        switch layout {
        case .grid:
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow { iconCell(width: cell); iconCell(width: cell) }
                GridRow { iconCell(width: cell); iconCell(width: cell) }
            }
        case .list:
            VStack(spacing: gap) {
                iconCell(width: 16)
                iconCell(width: 16)
            }
        }
    }

    private func iconCell(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .strokeBorder(lineWidth: 1.5)
            .frame(width: width, height: 7.442)
    }
}

#Preview {
    @Previewable @State var layout: FolderLayout = .grid
    VStack {
        Spacer()
        HomeBottomBar(layout: $layout)
    }
    .background(Color.black50)
}
