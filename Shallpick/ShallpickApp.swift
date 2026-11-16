// xcode: set sdk=iOS

import KakaoSDKAuth
import KakaoSDKCommon
import SwiftUI

@main
struct ShallpickApp: App {
    init() {
        if let appKey = AppConfig.kakaoNativeAppKey {
            KakaoSDK.initSDK(appKey: appKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // 카카오톡 앱에서 로그인 후 돌아올 때
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
        }
    }
}
