// xcode: set sdk=iOS

import SwiftUI

/// 흰 동그라미 안에 수달 (45pt)
/// Figma: Component 3 (179:22169), Component 1 ask (179:22155)
struct OtterButton: View {
    var accessibilityLabel = "수달"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.otterQuestion)
                .resizable()
                .scaledToFill()
                .frame(width: 53, height: 55)
                .offset(x: 1, y: 4)
                .frame(width: 45, height: 45)
                .background(.white)
                .clipShape(Circle())
                .floatingShadow()
        }
        .buttonStyle(ShallpickPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    OtterButton {}
        .padding(40)
        .background(Color.black50)
}
