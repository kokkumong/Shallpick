import SwiftUI

/// 상단 프로필 버튼을 누르면 펼쳐지는 메뉴: 알림 내역 → 구분선 → 로그아웃하기
struct AccountMenu: View {
    /// nil = 불러오는 중
    var items: [NotificationItem]?
    var didFail = false
    var onSelect: (NotificationItem) -> Void = { _ in }
    var onSignOut: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Text("알림")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black800)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            notifications

            Rectangle()
                .fill(Color.black200)
                .frame(height: 1)
                .padding(.horizontal, 16)

            Button(action: onSignOut) {
                Text("로그아웃하기")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300)
        // 그림자는 카드 모양에만 (글자에 번지지 않게)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .shallpickShadow(blur: 30)
        }
    }

    @ViewBuilder
    private var notifications: some View {
        if let items, !items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            NotificationRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Group {
                if items == nil, !didFail {
                    ProgressView()
                } else {
                    Text(didFail ? "알림을 불러오지 못했어요" : "아직 받은 알림이 없어요")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black400)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // "[폴더 이름] 새 메세지 12개" / "[폴더 이름] 현서님이 사진 3장에 대한 질문을 올렸어요! …"
            Text("\(Text("[\(item.folder.name)]").fontWeight(.semibold)) \(item.text)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(item.isUnread ? Color.black800 : Color.black400)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.createdAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black400)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let folders = Folder.previews
    AccountMenu(items: [
        NotificationItem(
            id: "q1", folder: folders[0],
            kind: .question(text: "현서님이 사진 3장에 대한 질문을 올렸어요! 확인해주세요:)"),
            createdAt: .now.addingTimeInterval(-120), isUnread: true
        ),
        NotificationItem(
            id: "c1", folder: folders[1], kind: .unreadChats(count: 12),
            createdAt: .now.addingTimeInterval(-600), isUnread: true
        ),
        NotificationItem(
            id: "c2", folder: folders[2], kind: .unreadChats(count: 240),
            createdAt: .now.addingTimeInterval(-3600), isUnread: true
        ),
        NotificationItem(
            id: "q2", folder: folders[3],
            kind: .question(text: "승완님의 질문: 이거 인스타에 올려도 돼?"),
            createdAt: .now.addingTimeInterval(-86_400), isUnread: false
        ),
    ])
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black50)
}
