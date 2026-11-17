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

    /// 테스트 알림: seconds 초 뒤에 채팅 알림 모양으로 뜸 (그 사이 홈 화면으로 나가면 앱 밖 알림으로 보임)
    static func scheduleTest(folder: Folder?, senderNickname: String, after seconds: TimeInterval = 5) async throws {
        let content = await messageContent(
            folderID: folder?.id,
            folderName: folder?.name ?? "Shallpick",
            senderNickname: senderNickname,
            body: "test"
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    /// 새 채팅·질문이 왔을 때 바로 띄우는 앱 밖 알림
    static func presentMessage(_ message: ChatMessage, folder: Folder, senderNickname: String) async {
        let content = await messageContent(
            folderID: folder.id,
            folderName: folder.name,
            senderNickname: senderNickname,
            body: body(for: message, senderNickname: senderNickname)
        )
        let request = UNNotificationRequest(identifier: "message-\(message.id.uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[Push] 채팅 알림을 띄우지 못함:", error)
        }
    }

    /// 알림 둘째 줄
    /// - 사진을 골라 보낸 질문: 안내 문구
    /// - 그 밖의 채팅·질문: 보낸 글 그대로 (글 없이 사진만 보냈으면 사진 장수)
    static func body(for message: ChatMessage, senderNickname: String) -> String {
        let photoCount = message.photoIDs.count
        if message.isQuestion, photoCount > 0 {
            return "\(senderNickname)님이 사진 \(photoCount)장에 대한 질문을 올렸어요! 확인해주세요:)"
        }
        let text = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, photoCount > 0 {
            return "사진 \(photoCount)장을 보냈어요"
        }
        return text
    }

    /// 채팅·질문 알림 내용
    /// 첫 줄: [폴더 이름] 보낸 사람 닉네임 (굵게) / 둘째 줄: body
    /// 메시지형으로 바꿔서 왼쪽 큰 동그라미에 수달, 귀퉁이에 작은 앱 아이콘을 보여 줌.
    /// 보낸 사람 이름을 "[폴더] 닉네임" 으로 한 1:1 대화로 만듭니다. (단체방으로 만들면 iOS 가
    /// 보낸 사람 / 방 이름 / 내용 세 줄로 보여 줌)
    /// Communication Notifications 권한이 없으면(실제 기기 + 무료 계정 등) 일반 알림 모양으로 보냅니다.
    static func messageContent(
        folderID: UUID?,
        folderName: String,
        senderNickname: String,
        body: String
    ) async -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "[\(folderName)] \(senderNickname)"
        content.body = body
        content.sound = .default
        if let folderID {
            content.userInfo = [PushPayloadKey.folderID: folderID.uuidString]
            content.threadIdentifier = folderID.uuidString
        }

        let avatar = UIImage(resource: .notificationAvatar).pngData().map(INImage.init(imageData:))
        let folderKey = folderID?.uuidString ?? "test"
        let senderKey = "\(folderKey):\(senderNickname)"
        // 메시지형에서는 보낸 사람 이름이 첫 줄(굵게)에 나옴
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderKey, type: .unknown),
            nameComponents: nil,
            displayName: content.title,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: senderKey
        )
        let me = INPerson(
            personHandle: INPersonHandle(value: "me", type: .unknown),
            nameComponents: nil,
            displayName: nil,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: "me",
            isMe: true
        )
        let intent = INSendMessageIntent(
            recipients: [me],
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: folderKey,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            // 제목을 그대로 두면 첫 줄이 두 번 나와서 비움
            let messageContent = content.mutableCopy() as! UNMutableNotificationContent
            messageContent.title = ""
            return try messageContent.updating(from: intent)
        } catch {
            print("[Push] 메시지형 알림으로 바꾸지 못해 기본 모양으로 보냄:", error)
            return content
        }
    }
}
