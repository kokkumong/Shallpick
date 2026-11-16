import SwiftUI

enum FolderLayout: CaseIterable {
    case grid
    case list
}

/// 메인 하단: Grid/List 전환 + 알림 + 폴더 추가 (148:9639)
struct HomeBottomBar: View {
    @Binding var layout: FolderLayout
    var onNotifications: () -> Void = {}
    var onCreateFolder: () -> Void = {}
    var onJoinWithCode: () -> Void = {}

    var body: some View {
        HStack {
            FolderLayoutPicker(selection: $layout)

            Spacer()

            HStack(spacing: 8) {
                CircleIconButton(icon: .iconBell, accessibilityLabel: "알림", action: onNotifications)
                Menu {
                    Button("새 폴더 만들기", systemImage: "folder.badge.plus", action: onCreateFolder)
                    Button("코드로 참여하기", systemImage: "number", action: onJoinWithCode)
                } label: {
                    CircleIcon(icon: .iconPlus)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("폴더 추가")
            }
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
                    .foregroundStyle(Color.black800)
                    .frame(width: 62, height: 39)
                    .background(selection == layout ? Color.blue50 : .white, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == layout ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white, in: Capsule())
        .shallpickShadow(blur: 20)
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
