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

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "사진을 읽지 못했어요."
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
        SupabaseManager.client?.auth.currentUser?.id
    }

    /// 폴더 사진 (최신 순), 보기용 서명 주소 포함
    static func fetch(folderID: UUID) async throws -> [PhotoItem] {
        let client = try client
        var photos: [PhotoItem] = try await client
            .from("photos")
            .select()
            .eq("folder_id", value: folderID)
            .order("created_at", ascending: false)
            .execute()
            .value
        guard !photos.isEmpty else { return [] }

        let signed = try await client.storage
            .from(bucket)
            .createSignedURLs(paths: photos.map(\.storagePath), expiresIn: 60 * 60)
        let urlByPath = Dictionary(
            signed.compactMap { result in result.signedURL.map { (result.path, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for index in photos.indices {
            photos[index].url = urlByPath[photos[index].storagePath]
        }
        return photos
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

    private static func jpegData(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.8)
        }.value
    }
}
