import UIKit

/// 내비게이션 바를 숨겨도 화면 왼쪽 끝을 밀어서 뒤로 갈 수 있게 합니다.
/// (SwiftUI 는 바를 숨기면 이 제스처도 꺼 버립니다.)
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
