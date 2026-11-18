import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 질문 보내기 전에 수달이 사진을 추려 주기.
/// 사진은 기기 안에서만 살펴봅니다 (Apple Vision, 서버로 보내지 않음).
///
/// 1. 사진마다 특징(닮은 정도를 잴 지문 + 잘 나온 정도)을 뽑고
/// 2. 서로 닮은 사진끼리 묶어서
/// 3. 묶음마다 제일 잘 나온 한 장만 남기자고 제안합니다.
nonisolated enum OtterPicker {
    /// 이만큼은 있어야 추려 볼 만함
    static let minPhotos = 2
    /// 한 번에 같이 살펴볼 사진 수
    private static let parallelism = 4
    /// 살펴볼 때 줄이는 긴 변 길이
    private static let analysisSide: CGFloat = 512

    // MARK: - 1. 사진 살펴보기

    /// 사진마다 특징을 뽑음. 못 받은 사진도 빈 특징으로 돌려줘서 "다 봤는지" 알 수 있게 함
    @concurrent
    static func analyze(_ photos: [PhotoItem]) async -> [UUID: PhotoSignal] {
        await withTaskGroup(of: (UUID, PhotoSignal).self) { group in
            var pending = photos.makeIterator()
            var result: [UUID: PhotoSignal] = [:]

            func addNext() {
                guard let photo = pending.next() else { return }
                group.addTask { (photo.id, await signal(for: photo)) }
            }

            for _ in 0..<parallelism { addNext() }
            while let (id, signal) = await group.next() {
                result[id] = signal
                if Task.isCancelled { group.cancelAll() } else { addNext() }
            }
            return result
        }
    }

    @concurrent
    private static func signal(for photo: PhotoItem) async -> PhotoSignal {
        guard let url = photo.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = thumbnail(of: data)
        else { return PhotoSignal() }

        var signal = PhotoSignal()
        signal.hash = differenceHash(image)
        signal.sharpness = sharpness(image)
        #if !targetEnvironment(simulator)
        // 시뮬레이터의 Vision 은 모델을 못 돌려서 사진마다 같은 값을 줌 → 위의 지문·선명도만 씀
        signal.featurePrint = try? await GenerateImageFeaturePrintRequest().perform(on: image)
        if let scores = try? await CalculateImageAestheticsScoresRequest().perform(on: image) {
            // -1 ~ 1 → 0 ~ 1
            signal.aesthetics = Double((scores.overallScore + 1) / 2)
        }
        if let faces = try? await DetectFaceCaptureQualityRequest().perform(on: image) {
            let scores = faces.compactMap { $0.captureQuality?.score }
            if !scores.isEmpty {
                signal.faceQuality = Double(scores.reduce(0, +)) / Double(scores.count)
            }
        }
        #endif
        return signal
    }

    private static func thumbnail(of data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: analysisSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 흑백으로 줄인 픽셀 (0 ~ 255)
    private static func grayPixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// 9×8 로 줄여 옆 칸끼리 밝기를 비교한 64비트 지문 (Vision 지문을 못 쓸 때 대신)
    private static func differenceHash(_ image: CGImage) -> UInt64? {
        guard let pixels = grayPixels(image, width: 9, height: 8) else { return nil }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                hash <<= 1
                if pixels[row * 9 + column] < pixels[row * 9 + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    /// 선명한 정도: 라플라시안의 분산 (흔들리거나 초점이 나가면 작아짐)
    private static func sharpness(_ image: CGImage) -> Double? {
        let side = 256
        guard let pixels = grayPixels(image, width: side, height: side) else { return nil }
        var sum = 0.0
        var squares = 0.0
        var count = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let center = Double(pixels[y * side + x]) * 4
                let around = Double(pixels[(y - 1) * side + x]) + Double(pixels[(y + 1) * side + x])
                    + Double(pixels[y * side + x - 1]) + Double(pixels[y * side + x + 1])
                let value = around - center
                sum += value
                squares += value * value
                count += 1
            }
        }
        let mean = sum / count
        return squares / count - mean * mean
    }

    // MARK: - 2·3. 묶고 고르기

    /// 닮은 사진끼리 묶고, 묶음마다 제일 잘 나온 사진을 고름. order 는 화면 순서
    static func suggest(for order: [UUID], signals: [UUID: PhotoSignal]) -> OtterPick {
        // 평균 연결 군집: 묶음 사이 평균 거리가 기준보다 가까우면 합침
        var clusters: [[UUID]] = order.map { [$0] }
        var distances: [[Double]] = order.map { a in
            order.map { b in a == b ? 0 : distance(signals[a], signals[b]) }
        }

        while clusters.count > 1 {
            var best: (i: Int, j: Int, d: Double)?
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count where distances[i][j] < (best?.d ?? .infinity) {
                    best = (i, j, distances[i][j])
                }
            }
            guard let best, best.d < 1 else { break }

            // j 를 i 에 합치고 거리 다시 계산 (크기 가중 평균)
            let sizeI = Double(clusters[best.i].count)
            let sizeJ = Double(clusters[best.j].count)
            for k in 0..<clusters.count where k != best.i && k != best.j {
                let merged = (distances[best.i][k] * sizeI + distances[best.j][k] * sizeJ) / (sizeI + sizeJ)
                distances[best.i][k] = merged
                distances[k][best.i] = merged
            }
            clusters[best.i] += clusters[best.j]
            clusters.remove(at: best.j)
            distances.remove(at: best.j)
            for k in distances.indices { distances[k].remove(at: best.j) }
        }

        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        var groups: [OtterPick.Group] = []
        var notes: [UUID: OtterPick.Note] = [:]

        for cluster in clusters {
            let ranked = rank(cluster, signals: signals)
            if ranked.count > 1, let top = ranked.first {
                notes[top] = .best
                for id in ranked.dropFirst() {
                    notes[id] = note(for: signals[id], comparedTo: signals[top])
                }
            }
            groups.append(OtterPick.Group(photoIDs: ranked))
        }
        // 화면에서 먼저 나온 사진의 묶음부터
        groups.sort { a, b in
            (a.photoIDs.compactMap { position[$0] }.min() ?? 0) < (b.photoIDs.compactMap { position[$0] }.min() ?? 0)
        }
        return OtterPick(groups: groups, notes: notes)
    }

    /// 0 = 같은 사진, 1 이상 = 다른 사진 (묶을지 말지 기준이 1)
    private static func distance(_ a: PhotoSignal?, _ b: PhotoSignal?) -> Double {
        guard let a, let b else { return .infinity }
        if let fa = a.featurePrint, let fb = b.featurePrint, let d = try? fa.distance(to: fb) {
            return d / featurePrintThreshold
        }
        if let ha = a.hash, let hb = b.hash {
            return Double((ha ^ hb).nonzeroBitCount) / hashThreshold
        }
        return .infinity
    }

    /// Vision 지문 거리가 이보다 가까우면 "비슷한 사진" (0 ~ 2 사이 값)
    private static let featurePrintThreshold = 0.62
    /// 64비트 지문에서 다른 비트가 이보다 적으면 "비슷한 사진"
    private static let hashThreshold = 14.0

    /// 잘 나온 순서
    private static func rank(_ ids: [UUID], signals: [UUID: PhotoSignal]) -> [UUID] {
        guard ids.count > 1 else { return ids }
        let sharpest = ids.compactMap { signals[$0]?.sharpness }.max() ?? 0
        // 묶음 안 사진에 다 얼굴이 있을 때만 얼굴 점수를 씀 (얼굴 없는 사진이 불리하지 않게)
        let useFaces = ids.allSatisfy { signals[$0]?.faceQuality != nil }

        func score(_ id: UUID) -> Double {
            guard let signal = signals[id] else { return -1 }
            let sharp = sharpest > 0 ? (signal.sharpness ?? 0) / sharpest : 0
            let look = signal.aesthetics ?? sharp
            if useFaces, let face = signal.faceQuality {
                return look * 0.45 + face * 0.4 + sharp * 0.15
            }
            return look * 0.75 + sharp * 0.25
        }
        return ids.sorted { score($0) > score($1) }
    }

    /// 빼자고 한 사진이 왜 빠졌는지 (제일 잘 나온 사진과 비교)
    private static func note(for signal: PhotoSignal?, comparedTo best: PhotoSignal?) -> OtterPick.Note {
        guard let signal, let best else { return .similar }
        if let sharp = signal.sharpness, let bestSharp = best.sharpness, bestSharp > 0, sharp < bestSharp * 0.55 {
            return .blurry
        }
        if let face = signal.faceQuality, let bestFace = best.faceQuality, bestFace - face > 0.12 {
            return .face
        }
        return .similar
    }
}

/// 사진 한 장에서 뽑은 특징. 다 nil 이면 못 본 사진 (혼자 한 묶음이 됨)
nonisolated struct PhotoSignal: Sendable {
    var featurePrint: FeaturePrintObservation?
    var hash: UInt64?
    var sharpness: Double?
    /// 0 ~ 1, 사진이 잘 나온 정도 (Vision 미적 점수)
    var aesthetics: Double?
    /// 0 ~ 1, 얼굴이 잘 나온 정도 (눈 감음·흔들림·가림이면 낮음). 얼굴이 없으면 nil
    var faceQuality: Double?
}

/// 수달의 제안
nonisolated struct OtterPick: Sendable, Equatable {
    struct Group: Sendable, Equatable {
        /// 잘 나온 순서. 첫 장이 수달 추천
        let photoIDs: [UUID]
        var isSimilar: Bool { photoIDs.count > 1 }
    }

    enum Note: Sendable, Equatable {
        /// 비슷한 사진 중 제일 잘 나옴
        case best
        /// 비슷한데 흔들렸거나 초점이 나감
        case blurry
        /// 비슷한데 표정·눈·얼굴이 덜 잘 나옴
        case face
        /// 비슷하고 조금 덜 잘 나옴
        case similar

        var label: String {
            switch self {
            case .best: "수달 추천"
            case .blurry: "흔들렸어요"
            case .face: "표정이 아쉬워요"
            case .similar: "비슷해요"
            }
        }
    }

    let groups: [Group]
    let notes: [UUID: Note]

    var similarGroups: [Group] { groups.filter(\.isSimilar) }
    var singles: [UUID] { groups.filter { !$0.isSimilar }.flatMap(\.photoIDs) }
    /// 수달이 남기자는 사진 (묶음마다 한 장 + 혼자인 사진)
    var suggested: Set<UUID> { Set(groups.compactMap(\.photoIDs.first)) }
    var removableCount: Int { groups.reduce(0) { $0 + $1.photoIDs.count - 1 } }
}
