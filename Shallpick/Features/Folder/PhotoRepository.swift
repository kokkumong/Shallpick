import Foundation
import Photos
import Supabase
import UIKit

/// 폴더에 올라간 사진 한 장. url 은 잠깐(1시간) 쓰는 서명 주소.
nonisolated struct PhotoItem: Decodable, Sendable, Identifiable, Hashable {
    let id: UUID
    let folderID: UUID
    let uploaderID: UUID
    let storagePath: String
    let createdAt: Date
    var url: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case folderID = "folder_id"
        case uploaderID = "uploader_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
}

/// supabase/migrations 의 public.photos + Storage 버킷 photos
enum PhotoRepository {
    static let bucket = "photos"
    /// 올릴 때 긴 변 최대 길이
    static let maxUploadSide: CGFloat = 2048

    private struct NewPhoto: Encodable {
        let id: UUID
        let folder_id: UUID
        let storage_path: String
    }

    enum PhotoError: LocalizedError {
        case unreadableImage
        case libraryDenied

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "사진을 읽지 못했어요."
            case .libraryDenied: "사진을 저장하려면 설정에서 사진 추가를 허용해 주세요."
            }
        }
    }

    private static var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else { throw FolderRepository.FolderError.notConfigured }
            return client
        }
    }

    static var currentUserID: UUID? {
        DemoStore.shared.isActive ? DemoStore.shared.userID : SupabaseManager.client?.auth.currentUser?.id
    }

    /// 폴더 사진 (최신 순), 보기용 서명 주소 포함
    static func fetch(folderID: UUID) async throws -> [PhotoItem] {
        if DemoStore.shared.isActive { return DemoStore.shared.photos(in: folderID) }
        let client = try client
        var photos: [PhotoItem] = try await client
            .from("photos")
            .select()
            .eq("folder_id", value: folderID)
            .order("created_at", ascending: false)
            .execute()
            .value
        guard !photos.isEmpty else { return [] }

        let urlByPath = try await signedURLs(for: photos.map(\.storagePath))
        for index in photos.indices {
            photos[index].url = urlByPath[photos[index].storagePath]
        }
        return photos
    }

    private nonisolated struct CoverRow: Decodable, Sendable {
        let folder_id: UUID
        let storage_path: String
    }

    /// 서명 주소 재사용 (같은 주소면 이미지를 다시 받지 않음). 만료 10분 전까지만 씀
    private static var signedURLCache: [String: (url: URL, expiresAt: Date)] = [:]
    private static let signedURLLifetime: TimeInterval = 60 * 60

    /// 메인 화면 폴더 표지용: 폴더마다 최신 사진 `limit` 장의 서명 주소
    static func fetchCovers(folderIDs: [UUID], limit: Int = 4) async throws -> [UUID: [URL]] {
        if DemoStore.shared.isActive {
            return Dictionary(uniqueKeysWithValues: folderIDs.map { ($0, Array(DemoStore.shared.photos(in: $0).compactMap(\.url).prefix(limit))) })
        }
        guard !folderIDs.isEmpty else { return [:] }
        let client = try client

        // 폴더마다 최신 limit 장만 (동시에)
        let rows = try await withThrowingTaskGroup(of: [CoverRow].self) { group in
            for folderID in folderIDs {
                group.addTask {
                    try await client
                        .from("photos")
                        .select("folder_id, storage_path")
                        .eq("folder_id", value: folderID)
                        .order("created_at", ascending: false)
                        .limit(limit)
                        .execute()
                        .value
                }
            }
            var all: [CoverRow] = []
            for try await folderRows in group { all += folderRows }
            return all
        }
        let urlByPath = try await signedURLs(for: rows.map(\.storage_path))

        var covers: [UUID: [URL]] = [:]
        // 그룹 결과 순서는 섞이므로 폴더별로 다시 묶되, 폴더 안 순서(최신 순)는 유지됨
        for row in rows {
            if let url = urlByPath[row.storage_path] {
                covers[row.folder_id, default: []].append(url)
            }
        }
        return covers
    }

    /// 아직 쓸 수 있는 주소는 재사용하고 나머지만 한 번에 서명
    private static func signedURLs(for paths: [String]) async throws -> [String: URL] {
        let freshUntil = Date().addingTimeInterval(10 * 60)
        let missing = paths.filter { (signedURLCache[$0]?.expiresAt ?? .distantPast) <= freshUntil }
        if !missing.isEmpty {
            let expiresAt = Date().addingTimeInterval(signedURLLifetime)
            let signed = try await client.storage
                .from(bucket)
                .createSignedURLs(paths: missing, expiresIn: Int(signedURLLifetime))
            for result in signed {
                if let url = result.signedURL {
                    signedURLCache[result.path] = (url, expiresAt)
                }
            }
        }
        return paths.reduce(into: [:]) { result, path in
            result[path] = signedURLCache[path]?.url
        }
    }

    /// 보관함 사진들을 차례로 올립니다. 하나 끝날 때마다 onProgress(올린 개수)
    static func upload(
        _ assets: [PHAsset],
        to folderID: UUID,
        onProgress: (Int) -> Void = { _ in }
    ) async throws {
        let client = try client
        for (index, asset) in assets.enumerated() {
            guard let image = await PhotoLibrary.image(for: asset, maxSide: maxUploadSide),
                  let data = await Self.jpegData(image)
            else { throw PhotoError.unreadableImage }

            let id = UUID()
            let path = "\(folderID.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg"
            try await client.storage
                .from(bucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            try await client
                .from("photos")
                .insert(NewPhoto(id: id, folder_id: folderID, storage_path: path))
                .execute()
            onProgress(index + 1)
        }
    }

    /// 폴더 사진 원본을 받아 기기 사진 보관함에 차례로 저장. 하나 끝날 때마다 onProgress(저장한 개수)
    static func saveToLibrary(_ photos: [PhotoItem], onProgress: (Int) -> Void = { _ in }) async throws {
        guard await PhotoLibrary.requestAddAccess() else { throw PhotoError.libraryDenied }
        let storage = try (DemoStore.shared.isActive ? nil : client.storage.from(bucket))
        for (index, photo) in photos.enumerated() {
            let data: Data
            if DemoStore.shared.isActive, let name = photo.url?.lastPathComponent,
               let bundled = UIImage(named: name)?.jpegData(compressionQuality: 0.9) {
                data = bundled
            } else if let storage {
                data = try await storage.download(path: photo.storagePath)
            } else { throw PhotoError.unreadableImage }
            try await PhotoLibrary.addPhoto(data)
            onProgress(index + 1)
        }
    }

    /// 내가 올린 사진만 지웁니다 (다른 사람 사진은 RLS 로 막힘). 줄을 먼저 지우고 파일을 지움
    static func delete(_ photos: [PhotoItem]) async throws {
        if DemoStore.shared.isActive { DemoStore.shared.deletePhotos(photos); return }
        guard let me = currentUserID else { return }
        let mine = photos.filter { $0.uploaderID == me }
        guard !mine.isEmpty else { return }
        let client = try client
        try await client
            .from("photos")
            .delete()
            .in("id", values: mine.map(\.id))
            .eq("uploader_id", value: me)
            .execute()
        // 파일이 남아도 화면엔 안 보이므로, 파일 지우기 실패는 넘어감
        _ = try? await client.storage.from(bucket).remove(paths: mine.map(\.storagePath))
        for photo in mine { signedURLCache[photo.storagePath] = nil }
    }

    private static func jpegData(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.8)
        }.value
    }
}
