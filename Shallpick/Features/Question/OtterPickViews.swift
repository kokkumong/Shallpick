import SwiftUI

/// 질문 보내기 화면의 수달 한 줄: 살펴보는 중 / 추려 볼까요? / 겹치는 사진 없음 / 추린 사진으로 물어봐요
/// 보낼 사람 선택 줄(RecipientRow)과 같은 흰 바탕 · 모서리 16
struct OtterPickCard: View {
    enum Phase: Equatable {
        case analyzing
        /// 비슷한 묶음 수, 지금 장수, 추리면 남는 장수
        case suggest(groups: Int, total: Int, keep: Int)
        case nothing
        /// 추린 뒤 남은 장수, 추리기 전 장수
        case applied(kept: Int, before: Int)
    }

    let state: Phase
    var onOpen: () -> Void = {}
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            otter

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black400)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)

            trailing
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if case .suggest = state { onOpen() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: actionName) {
            switch state {
            case .suggest: onOpen()
            case .applied: onUndo()
            default: break
            }
        }
        .animation(.snappy(duration: 0.25), value: state)
    }

    private var otterImage: ImageResource {
        switch state {
        case .analyzing: .otterThinking
        case .suggest: .otterPresent
        case .nothing, .applied: .otterMascot
        }
    }

    /// 흰 동그라미 수달 (OtterButton 과 같은 잘림)
    private var otter: some View {
        Image(otterImage)
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 54)
            .offset(x: 1, y: 5)
            .frame(width: 44, height: 44)
            .background(Color.blue50)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var title: String {
        switch state {
        case .analyzing: "수달이 사진을 살펴보고 있어요"
        case let .suggest(groups, _, _): "비슷한 사진이 \(groups)묶음 있어요"
        case .nothing: "겹치는 사진이 없어요"
        case let .applied(kept, _): "수달이 고른 \(kept)장으로 물어봐요"
        }
    }

    private var subtitle: String {
        switch state {
        case .analyzing: "비슷한 사진이 있는지 찾는 중"
        case let .suggest(_, total, keep): "\(total)장 → \(keep)장으로 줄여서 물어볼까요?"
        case .nothing: "이대로 물어봐도 좋아요"
        case let .applied(_, before): "처음 고른 사진은 \(before)장이었어요"
        }
    }

    private var actionName: String {
        switch state {
        case .applied: "되돌리기"
        default: "추려보기"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .analyzing:
            ProgressView()
                .controlSize(.small)
                .tint(Color.black400)
                .padding(.trailing, 6)
        case .suggest:
            Button(action: onOpen) {
                Text("추려보기")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.black800, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .applied:
            Button(action: onUndo) {
                Text("되돌리기")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black800)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.black200, lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .nothing:
            EmptyView()
        }
    }
}

/// "추려보기" 를 누르면 뜨는 화면: 비슷한 묶음마다 수달이 고른 사진을 보여 주고, 눌러서 바꿀 수 있음
/// 질문 보내기 화면과 같은 머리(닫기 + 가운데 제목)와 아래 검정 버튼
struct OtterPickSheet: View {
    let photos: [PhotoItem]
    let pick: OtterPick
    /// 남길 사진 (화면 순서)
    let onApply: ([PhotoItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keep: Set<UUID>

    init(photos: [PhotoItem], pick: OtterPick, onApply: @escaping ([PhotoItem]) -> Void) {
        self.photos = photos
        self.pick = pick
        self.onApply = onApply
        let ids = Set(photos.map(\.id))
        _keep = State(initialValue: pick.suggested.intersection(ids))
    }

    private var byID: [UUID: PhotoItem] {
        Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
    }

    private let singleColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                intro

                ForEach(Array(pick.similarGroups.enumerated()), id: \.offset) { _, group in
                    similarSection(group)
                }

                if !pick.singles.isEmpty {
                    singlesSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { applyBar }
        .background(Color.black50)
        .sensoryFeedback(.selection, trigger: keep)
    }

    // MARK: - 위

    private var header: some View {
        HStack {
            CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기") { dismiss() }
            Spacer()
        }
        .overlay {
            Text("수달이 추려봤어요")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black800)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(alignment: .top) { TopFade() }
    }

    /// 수달 + 말풍선
    private var intro: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Image(.otterPresent)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 75)
                .accessibilityHidden(true)

            Text("제일 잘 나온 사진을 골랐어요.\n눌러서 바꿀 수도 있어요.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black600)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white, in: UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16
                ))
                .padding(.bottom, 14)
        }
    }

    // MARK: - 비슷한 사진 묶음

    private func similarSection(_ group: OtterPick.Group) -> some View {
        let ids = group.photoIDs.filter { byID[$0] != nil }
        let kept = ids.count { keep.contains($0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("비슷한 사진 \(ids.count)장")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black800)
                Spacer()
                Text(kept == 0 ? "모두 빼기" : "\(kept)장 남기기")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black400)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ids, id: \.self) { id in
                        if let photo = byID[id] {
                            PickPhotoTile(
                                photo: photo,
                                note: pick.notes[id],
                                isKept: keep.contains(id)
                            ) { toggle(id) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .animation(.snappy(duration: 0.2), value: kept)
    }

    // MARK: - 혼자인 사진

    private var singlesSection: some View {
        let ids = pick.singles.filter { byID[$0] != nil }
        return VStack(alignment: .leading, spacing: 12) {
            Text("겹치지 않는 사진 \(ids.count)장")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black800)

            LazyVGrid(columns: singleColumns, spacing: 10) {
                ForEach(ids, id: \.self) { id in
                    if let photo = byID[id] {
                        let isKept = keep.contains(id)
                        Button { toggle(id) } label: {
                            FolderPhotoCell(photo: photo)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .opacity(isKept ? 1 : 0.4)
                                .overlay(alignment: .topLeading) {
                                    SelectionCheck(isOn: isKept)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("사진")
                        .accessibilityAddTraits(isKept ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            if keep.contains(id) { keep.remove(id) } else { keep.insert(id) }
        }
    }

    // MARK: - 아래

    private var applyBar: some View {
        let count = keep.count
        return Button {
            onApply(photos.filter { keep.contains($0.id) })
            dismiss()
        } label: {
            Text(count == 0 ? "남길 사진을 골라 주세요" : "\(count)장으로 질문하기")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.black800.opacity(count > 0 ? 1 : 0.3), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .animation(.snappy(duration: 0.2), value: count)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 33)
        .background { BottomFade() }
    }
}

/// 비슷한 묶음의 사진 한 장 (3:4). 남기면 검정 테두리 + 체크, 빼면 흐리게. 아래에 수달 한마디
private struct PickPhotoTile: View {
    let photo: PhotoItem
    let note: OtterPick.Note?
    let isKept: Bool
    let action: () -> Void

    private let size = CGSize(width: 116, height: 155)

    var body: some View {
        Button(action: action) {
            FolderPhoto(url: photo.url, cornerRadius: 12)
                .frame(width: size.width, height: size.height)
                .opacity(isKept ? 1 : 0.4)
                .overlay {
                    if isKept {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.black800, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topLeading) {
                    SelectionCheck(isOn: isKept)
                        .padding(4)
                }
                .overlay(alignment: .bottom) {
                    if let note {
                        noteChip(note)
                            .padding(.bottom, 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.map { "사진, \($0.label)" } ?? "사진")
        .accessibilityAddTraits(isKept ? .isSelected : [])
    }

    private func noteChip(_ note: OtterPick.Note) -> some View {
        let isBest = note == .best
        return Text(note.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isBest ? .white : Color.black600)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .shadowedBackground(isBest ? Color.black800 : .white.opacity(0.92), in: Capsule(), blur: 8)
    }
}

#Preview("카드") {
    VStack(spacing: 12) {
        OtterPickCard(state: .analyzing)
        OtterPickCard(state: .suggest(groups: 2, total: 7, keep: 3))
        OtterPickCard(state: .nothing)
        OtterPickCard(state: .applied(kept: 3, before: 7))
    }
    .padding(24)
    .background(Color.black50)
}
