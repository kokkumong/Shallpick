import Photos
import SwiftUI
import UIKit

/// 기기 사진 보관함 읽기 (권한 요청, 목록, 썸네일)
enum PhotoLibrary {
    enum Access {
        case allowed
        /// 사용자가 고른 일부 사진만 허용
        case limited
        case denied
    }

    static func requestAccess() async -> Access {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: return .allowed
        case .limited: return .limited
        default: return .denied
        }
    }

    /// 사진 보관함에 추가만 하는 권한 (저장하기)
    static func requestAddAccess() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return status == .authorized || status == .limited
    }

    /// 사진 보관함에 이미지 한 장 추가.
    /// performChanges 블록은 백그라운드에서 돌므로 메인 액터에 묶이지 않게 nonisolated 로 둡니다.
    nonisolated static func addPhoto(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    /// 최근 사진부터
    static func fetchImages(favoritesOnly: Bool = false) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if favoritesOnly {
            options.predicate = NSPredicate(format: "favorite == YES")
        }
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    /// 고른 순서를 지키며 identifier → PHAsset
    static func assets(withIdentifiers ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }

    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        await image(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, resizeMode: .fast)
    }

    /// 긴 변이 maxSide 를 넘지 않는 원본 비율 이미지 (올리기용)
    static func image(for asset: PHAsset, maxSide: CGFloat) async -> UIImage? {
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        let scale = min(1, maxSide / max(width, height, 1))
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        return await image(for: asset, targetSize: size, contentMode: .aspectFit, resizeMode: .exact)
    }

    private static func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async -> UIImage? {
        let options = PHImageRequestOptions()
        // 결과 핸들러가 딱 한 번 불리도록
        options.deliveryMode = .highQualityFormat
        options.resizeMode = resizeMode
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { @Sendable image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// 정사각형 사진 칸 하나 (보관함 사진)
struct AssetThumbnail: View {
    let asset: PHAsset

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.blue50
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                image = await PhotoLibrary.thumbnail(for: asset, side: 120 * displayScale)
            }
    }
}
