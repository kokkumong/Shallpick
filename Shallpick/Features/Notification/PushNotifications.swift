import Intents
import Observation
import UIKit
import UserNotifications

/// 알림(로컬 / 원격 공통) 내용에 담는 값
nonisolated enum PushPayloadKey {
    /// 알림을 누르면 이 폴더의 채팅으로 이동
    static let folderID = "folder_id"
}

/// 알림을 눌렀을 때 열어야 할 화면. HomeView 가 보고 이동한 뒤 비웁니다.
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    var pendingFolderID: UUID?
}

/// 알림 표시·탭 처리 (UNUserNotificationCenter delegate)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 앱이 꺼진 상태에서 알림을 눌러 켜질 때도 탭을 받으려면 실행 직후에 지정해야 함
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 앱을 보고 있을 때도 배너를 띄움
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[PushPayloadKey.folderID] as? String
        guard let folderID = raw.flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run { NotificationRouter.shared.pendingFolderID = folderID }
    }
}

enum LocalNotifications {
    /// 처음 한 번 권한을 묻고, 이후에는 현재 상태만 돌려줌
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// 테스트 알림: seconds 초 뒤에 뜸 (그 사이 홈 화면으로 나가면 앱 밖 알림으로 보임)
    /// folder 를 주면 알림을 눌렀을 때 그 폴더 채팅으로 이동
    static func scheduleTest(folder: Folder?, after seconds: TimeInterval = 5) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Shallpick"
        content.body = "test"
        content.sound = .default
        if let folder {
            content.subtitle = folder.name
            content.userInfo = [PushPayloadKey.folderID: folder.id.uuidString]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: await messageStyled(content, senderName: "Shallpick", groupName: folder?.name),
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    /// 메시지형 알림: 왼쪽 큰 동그라미에 보낸 사람 사진(지금은 수달), 귀퉁이에 작은 앱 아이콘.
    /// Communication Notifications 권한이 없으면(실제 기기 + 무료 계정 등) 원래 모양 그대로 보냅니다.
    static func messageStyled(
        _ content: UNMutableNotificationContent,
        senderName: String,
        groupName: String?
    ) async -> UNNotificationContent {
        let avatar = UIImage(resource: .notificationAvatar).pngData().map(INImage.init(imageData:))
        let sender = INPerson(
            personHandle: INPersonHandle(value: "shallpick-otter", type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: "shallpick-otter"
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName.map { INSpeakableString(spokenPhrase: $0) },
            conversationIdentifier: content.userInfo[PushPayloadKey.folderID] as? String,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        intent.setImage(avatar, forParameterNamed: \.sender)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            return try content.updating(from: intent)
        } catch {
            print("[Push] 메시지형 알림으로 바꾸지 못해 기본 모양으로 보냄:", error)
            return content
        }
    }
}
