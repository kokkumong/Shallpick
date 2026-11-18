import SwiftUI
import UIKit

struct PhotoBatchResult {
    var succeeded: Set<UUID> = []
    var failed: [PhotoItem] = []
}

/// Files are downloaded through the authenticated storage client, never from an expired display URL.
enum PhotoExport {
    static func save(_ photos: [PhotoItem], onProgress: (Int) -> Void = { _ in }) async throws -> PhotoBatchResult {
        guard await PhotoLibrary.requestAddAccess() else { throw PhotoRepository.PhotoError.libraryDenied }
        var result = PhotoBatchResult()
        for (index, photo) in photos.enumerated() {
            do {
                try Task.checkCancellation()
                let data = try await PhotoRepository.download(photo)
                try await PhotoLibrary.addPhoto(data)
                result.succeeded.insert(photo.id)
            } catch is CancellationError {
                result.failed += Array(photos[index...])
                break
            } catch {
                result.failed.append(photo)
            }
            onProgress(index + 1)
        }
        return result
    }

    static func prepareShare(_ photos: [PhotoItem]) async throws -> PhotoShareFiles {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Shallpick-Share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var urls: [URL] = []
            for photo in photos {
                try Task.checkCancellation()
                let data = try await PhotoRepository.download(photo)
                let url = directory.appendingPathComponent("\(photo.id.uuidString).jpg")
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return PhotoShareFiles(directory: directory, urls: urls)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct PhotoShareFiles: Identifiable {
    let id = UUID()
    let directory: URL
    let urls: [URL]
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

struct PhotoShareSheet: UIViewControllerRepresentable {
    let files: PhotoShareFiles
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files.urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onFinish() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
