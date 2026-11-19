import SwiftUI
import UIKit

// 사진 칸을 손가락으로 쭉 쓸어서 한꺼번에 고르기 (애플 사진의 선택 모드처럼)
//
// - 사진 위에서 옆으로 밀기 시작하면 고르기, 처음부터 위아래로 밀면 그냥 스크롤
// - 시작한 칸이 안 골라져 있었으면 지나간 칸을 고르고, 골라져 있었으면 풀어 줌
// - 시작 칸부터 지금 손가락 칸까지(화면 순서) 범위를 바꾸고,
//   손가락을 되돌려 범위에서 빠진 칸은 시작 전 상태로 돌려 놓음
//
// 쓰는 법: 그리드(스크롤뷰)에 .dragToSelect(...), 각 칸에 .dragSelectItem(id)

extension View {
    /// - ids: 화면에 보이는 순서대로의 칸 id (사진이 아주 많으면 0..<count 같은 Range 를 넘겨도 됨)
    /// - apply: 바꿀 칸들 (시작 칸에서 가까운 순서). true 면 고르기, false 면 풀기
    func dragToSelect<IDs: RandomAccessCollection>(
        ids: IDs,
        isEnabled: Bool = true,
        isSelected: @escaping (IDs.Element) -> Bool,
        apply: @escaping ([(id: IDs.Element, selected: Bool)]) -> Void
    ) -> some View where IDs.Element: Hashable, IDs.Index == Int {
        modifier(DragToSelect(ids: ids, isEnabled: isEnabled, isSelected: isSelected, apply: apply))
    }

    /// 드래그로 고를 수 있는 칸 하나 (위치를 알려 줌)
    func dragSelectItem<ID: Hashable>(_ id: ID) -> some View {
        modifier(DragSelectItem(id: AnyHashable(id)))
    }
}

/// 화면에 떠 있는 칸들의 위치. 바뀔 때마다 화면을 다시 그릴 필요가 없어 관찰하지 않는 객체에 둠
final class DragSelectFrames {
    var frames: [AnyHashable: CGRect] = [:]
}

extension EnvironmentValues {
    @Entry var dragSelectFrames: DragSelectFrames?
}

private struct DragSelectItem: ViewModifier {
    let id: AnyHashable
    @Environment(\.dragSelectFrames) private var store

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                store?.frames[id] = frame
            }
            // 화면 밖으로 나가 지워진 칸이 옛 자리에 남아 다른 칸과 겹치지 않게
            .onDisappear { store?.frames[id] = nil }
    }
}

private struct DragToSelect<IDs: RandomAccessCollection>: ViewModifier
where IDs.Element: Hashable, IDs.Index == Int {
    typealias ID = IDs.Element

    let ids: IDs
    let isEnabled: Bool
    let isSelected: (ID) -> Bool
    let apply: ([(id: ID, selected: Bool)]) -> Void

    @State private var store = DragSelectFrames()
    @State private var session: Session?

    private struct Session {
        let startIndex: Int
        /// true: 지나간 칸을 고름, false: 풂
        let selecting: Bool
        var currentIndex: Int
        /// 범위에 들어온 적 있는 칸의 드래그 전 상태 (범위에서 빠지면 이걸로 되돌림)
        var original: [Int: Bool] = [:]
    }

    func body(content: Content) -> some View {
        content
            .environment(\.dragSelectFrames, store)
            .gesture(
                SidewaysPan(
                    isEnabled: isEnabled,
                    onBegan: begin,
                    onChanged: move,
                    onEnded: { session = nil }
                )
            )
            .sensoryFeedback(.selection, trigger: session?.currentIndex) { _, new in new != nil }
    }

    /// 화면에 떠 있는 칸(수십 개)만 살펴봄
    private func index(at point: CGPoint) -> Int? {
        guard let hit = store.frames.first(where: { $0.value.contains(point) })?.key,
              let id = hit.base as? ID
        else { return nil }
        return ids.firstIndex(of: id)
    }

    private func begin(at point: CGPoint) {
        guard let start = index(at: point) else { session = nil; return }
        session = Session(startIndex: start, selecting: !isSelected(ids[start]), currentIndex: start)
        update(to: start)
    }

    private func move(to point: CGPoint) {
        // 칸 사이 틈에서는 마지막 칸을 유지
        guard session != nil, let index = index(at: point), index != session?.currentIndex else { return }
        update(to: index)
    }

    /// 지난번 범위와 이번 범위에 걸친 칸만 다시 계산
    private func update(to index: Int) {
        guard var session else { return }
        let start = session.startIndex
        let previous = min(start, session.currentIndex)...max(start, session.currentIndex)
        let range = min(start, index)...max(start, index)
        let touched = min(previous.lowerBound, range.lowerBound)...max(previous.upperBound, range.upperBound)

        // 시작 칸에서 가까운 순서로 (순서를 기억하는 선택에서 지나간 순서대로 쌓이게)
        var changes: [(id: ID, selected: Bool)] = []
        for i in touched.sorted(by: { abs($0 - start) < abs($1 - start) }) {
            let id = ids[i]
            let now = isSelected(id)
            let wanted: Bool
            if range.contains(i) {
                if session.original[i] == nil { session.original[i] = now }
                wanted = session.selecting
            } else {
                wanted = session.original[i] ?? now
            }
            if wanted != now { changes.append((id, wanted)) }
        }

        session.currentIndex = index
        self.session = session
        if !changes.isEmpty { apply(changes) }
    }
}

/// 옆으로 밀기 시작할 때만 잡히는 한 손가락 팬.
/// 위아래로 시작하면 바로 포기해서 스크롤뷰가 평소처럼 스크롤함
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        context.coordinator.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            // 잡히기까지 손가락이 조금 움직였으므로, 처음 손가락을 댄 칸부터
            onBegan(context.coordinator.touchDown ?? point)
            onChanged(point)
        case .changed:
            onChanged(point)
        default:
            onEnded()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        /// 손가락을 처음 댄 곳 (창 좌표 = SwiftUI .global)
        var touchDown: CGPoint?

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touchDown = touch.location(in: nil)
            return true
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let moved = pan.translation(in: pan.view)
            return abs(moved.x) > abs(moved.y)
        }

        // 스크롤은 이 팬이 "옆으로가 아님" 으로 포기한 뒤에 시작
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            isEnabled && other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
