import Foundation

/// 메인 화면 폴더 순서 (길게 눌러 바꾼 순서). 이 기기에 계정마다 저장합니다.
/// 저장된 순서에 없는 폴더(새로 만들거나 참여한 폴더)는 맨 위에, 서버 순서(최근 참여 순) 그대로 둡니다.
nonisolated struct FolderOrder: Sendable {
    let userID: UUID

    private var key: String { "folders.order.\(userID)" }

    func apply(to folders: [Folder]) -> [Folder] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        let position = Dictionary(
            saved.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let new = folders.filter { position[$0.id.uuidString] == nil }
        let ordered = folders
            .filter { position[$0.id.uuidString] != nil }
            .sorted { position[$0.id.uuidString]! < position[$1.id.uuidString]! }
        return new + ordered
    }

    func save(_ folders: [Folder]) {
        UserDefaults.standard.set(folders.map(\.id.uuidString), forKey: key)
    }
}
