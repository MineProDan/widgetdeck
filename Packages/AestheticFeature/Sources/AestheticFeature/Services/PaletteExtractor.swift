import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreKit
import DesignSystem
import Foundation

/// A colour cluster found in an image: its mean colour and share of the pixels (0…1).
public struct ColorCluster: Hashable, Sendable {
    public var color: RGBAColor
    public var weight: Double

    public init(color: RGBAColor, weight: Double) {
        self.color = color
        self.weight = weight
    }
}

/// Theme Sync step 1 (A-02): the five main colours of the wallpaper photo the user picked.
///
/// Pipeline: downsample to a 64 px thumbnail (CoreKit `Downsampler`, the full image is never
/// decoded) → `CIKMeans` (Core Image, 6 clusters, perceptual, seeded deterministically with
/// farthest-point picks, refined by Lloyd passes) → weights by nearest-centre assignment → edge
/// blends under 3 % dropped, five kept. If Core Image returns nothing
/// usable, a plain Swift k-means over the same 4 096 pixels runs instead. No ML frameworks.
public enum PaletteExtractor {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case unreadableImage

        public var errorDescription: String? {
            "That photo couldn't be read. Try another one."
        }
    }

    public static let thumbnailSize = 64
    public static let clusterCount = 5

    /// Extracts `clusterCount` clusters, heaviest first. Duplicate or empty clusters are filled
    /// with lighter/darker mixes so the result always has exactly five colours.
    public static func extract(from data: Data) throws -> [ColorCluster] {
        let thumbnail: CGImage
        do {
            thumbnail = try Downsampler.downsample(data: data, maxPixelSize: thumbnailSize)
        } catch {
            throw Error.unreadableImage
        }
        return try extract(from: thumbnail)
    }

    public static func extract(from image: CGImage) throws -> [ColorCluster] {
        let pixels = try rgbPixels(of: image)
        guard !pixels.isEmpty else { throw Error.unreadableImage }
        // One spare cluster soaks up anti-aliased edges between areas; `selected` drops it.
        let seeds = farthestPointSeeds(pixels, count: clusterCount + 1)
        // CIKMeans' means are refined with a few Lloyd passes, and compared with a run from the
        // farthest-point seeds alone; the tighter clustering (lower squared error) wins.
        var candidates = [lloyd(pixels, seeds: seeds)]
        if let ciMeans = coreImageMeans(image: image, seeds: seeds) { candidates.insert(lloyd(pixels, seeds: ciMeans), at: 0) }
        let centres = candidates.min { squaredError(pixels, $0) < squaredError(pixels, $1) }!
        return completed(selected(weighted(pixels, centres: centres)))
    }

    /// Clusters under 3 % of the image are edge blends or noise and are dropped. Of the rest, the
    /// five heaviest are kept, but a vivid small accent (a sun, a flower) always keeps its place.
    static let minimumWeight = 0.03

    static func selected(_ clusters: [ColorCluster]) -> [ColorCluster] {
        let solid = clusters.filter { $0.weight >= minimumWeight }
        guard solid.count > clusterCount else { return solid.isEmpty ? Array(clusters.prefix(1)) : solid }
        var kept = Array(solid.prefix(clusterCount))
        if let vivid = solid.max(by: { vividness($0.color) < vividness($1.color) }), !kept.contains(vivid) {
            kept[clusterCount - 1] = vivid
        }
        return kept
    }

    static func vividness(_ color: RGBAColor) -> Double {
        let maxC = max(color.red, color.green, color.blue)
        let minC = min(color.red, color.green, color.blue)
        return maxC == 0 ? 0 : (maxC - minC) // saturation × brightness in HSB
    }

    // MARK: Pixels

    typealias RGB = SIMD3<Double>

    /// sRGB pixels of the thumbnail (at most 64×64), alpha ignored.
    static func rgbPixels(of image: CGImage) throws -> [RGB] {
        let scale = min(1, Double(thumbnailSize) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Error.unreadableImage
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let buffer = context.data else { throw Error.unreadableImage }
        let bytes = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).map { i in
            RGB(Double(bytes[i * 4]) / 255, Double(bytes[i * 4 + 1]) / 255, Double(bytes[i * 4 + 2]) / 255)
        }
    }

    // MARK: Clustering

    /// Deterministic seeds: the pixel nearest the mean, then repeatedly the pixel farthest from
    /// every seed so far (so small, strong accents like a sun get their own cluster).
    static func farthestPointSeeds(_ pixels: [RGB], count: Int) -> [RGB] {
        let mean = pixels.reduce(RGB.zero, +) / Double(pixels.count)
        var seeds = [pixels.min { distance($0, mean) < distance($1, mean) }!]
        var nearest = pixels.map { distance($0, seeds[0]) }
        while seeds.count < count {
            guard let index = nearest.indices.max(by: { nearest[$0] < nearest[$1] }), nearest[index] > 0 else { break }
            seeds.append(pixels[index])
            for i in pixels.indices { nearest[i] = min(nearest[i], distance(pixels[i], pixels[index])) }
        }
        return seeds
    }

    /// `CIKMeans` refinement of the seeds. Returns nil if Core Image can't run the filter.
    static func coreImageMeans(image: CGImage, seeds: [RGB]) -> [RGB]? {
        guard !seeds.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var seedBytes: [Float] = seeds.flatMap { [Float($0.x), Float($0.y), Float($0.z), 1] }
        let seedImage = seedBytes.withUnsafeMutableBytes { raw in
            CIImage(bitmapData: Data(raw), bytesPerRow: seeds.count * 16,
                    size: CGSize(width: seeds.count, height: 1), format: .RGBAf, colorSpace: space)
        }
        let input = CIImage(cgImage: image)
        let filter = CIFilter.kMeans()
        filter.inputImage = input
        filter.extent = input.extent
        filter.inputMeans = seedImage
        filter.count = seeds.count
        filter.passes = 5
        filter.perceptual = true
        // The output's alpha holds cluster weights; force it to 1 so colours aren't premultiplied.
        guard let output = filter.outputImage?.settingAlphaOne(in: CGRect(x: 0, y: 0, width: seeds.count, height: 1)) else {
            return nil
        }
        var result = [Float](repeating: 0, count: seeds.count * 4)
        let context = CIContext(options: [.workingColorSpace: space, .cacheIntermediates: false])
        context.render(output, toBitmap: &result, rowBytes: seeds.count * 16,
                       bounds: CGRect(x: 0, y: 0, width: seeds.count, height: 1), format: .RGBAf, colorSpace: space)
        let means = (0..<seeds.count).map { i in
            RGB(Double(result[i * 4]), Double(result[i * 4 + 1]), Double(result[i * 4 + 2]))
        }
        // All-black output means the filter didn't run (e.g. no GPU/CPU renderer available).
        guard means.contains(where: { $0.x + $0.y + $0.z > 0.001 }), means.allSatisfy({ $0.x.isFinite }) else { return nil }
        return means.map { RGB($0.x.clamped, $0.y.clamped, $0.z.clamped) }
    }

    /// Plain Lloyd k-means (fallback when Core Image is unavailable).
    static func lloyd(_ pixels: [RGB], seeds: [RGB], passes: Int = 8) -> [RGB] {
        var centres = seeds
        for _ in 0..<passes {
            var sums = [RGB](repeating: .zero, count: centres.count)
            var counts = [Int](repeating: 0, count: centres.count)
            for pixel in pixels {
                let c = nearestIndex(pixel, centres)
                sums[c] += pixel
                counts[c] += 1
            }
            for c in centres.indices where counts[c] > 0 { centres[c] = sums[c] / Double(counts[c]) }
        }
        return centres
    }

    static func squaredError(_ pixels: [RGB], _ centres: [RGB]) -> Double {
        pixels.reduce(0) { $0 + distance($1, centres[nearestIndex($1, centres)]) }
    }

    /// Assigns every pixel to its nearest centre; recomputes each cluster's mean and weight.
    static func weighted(_ pixels: [RGB], centres: [RGB]) -> [ColorCluster] {
        var sums = [RGB](repeating: .zero, count: centres.count)
        var counts = [Int](repeating: 0, count: centres.count)
        for pixel in pixels {
            let c = nearestIndex(pixel, centres)
            sums[c] += pixel
            counts[c] += 1
        }
        return centres.indices.compactMap { c in
            guard counts[c] > 0 else { return nil }
            let mean = sums[c] / Double(counts[c])
            return ColorCluster(color: RGBAColor(red: mean.x, green: mean.y, blue: mean.z),
                                weight: Double(counts[c]) / Double(pixels.count))
        }
        .sorted { $0.weight > $1.weight }
    }

    /// Merges near-identical clusters, then pads to five with lighter and darker mixes of the
    /// found colours (a flat or two-colour wallpaper still yields a usable ramp).
    static func completed(_ clusters: [ColorCluster]) -> [ColorCluster] {
        var merged: [ColorCluster] = []
        for cluster in clusters {
            if let i = merged.firstIndex(where: { distance(rgb($0.color), rgb(cluster.color)) < 0.0016 }) {
                merged[i].weight += cluster.weight
            } else {
                merged.append(cluster)
            }
        }
        guard !merged.isEmpty else { return [] }
        let steps: [(RGBAColor, Double)] = [(.white, 0.55), (.black, 0.55), (.white, 0.8), (.black, 0.3), (.white, 0.3), (.black, 0.8)]
        var candidates: [RGBAColor] = []
        for (target, amount) in steps {
            for cluster in merged { candidates.append(cluster.color.mixed(with: target, amount: amount)) }
        }
        for color in candidates where merged.count < clusterCount {
            if !merged.contains(where: { distance(rgb($0.color), rgb(color)) < 0.0016 }) {
                merged.append(ColorCluster(color: color, weight: 0))
            }
        }
        return Array(merged.prefix(clusterCount))
    }

    static func rgb(_ color: RGBAColor) -> RGB { RGB(color.red, color.green, color.blue) }

    static func distance(_ a: RGB, _ b: RGB) -> Double {
        let d = a - b
        return (d * d).sum()
    }

    static func nearestIndex(_ pixel: RGB, _ centres: [RGB]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (i, centre) in centres.enumerated() {
            let d = distance(pixel, centre)
            if d < bestDistance { best = i; bestDistance = d }
        }
        return best
    }
}

private extension Double {
    var clamped: Double { Swift.min(Swift.max(self, 0), 1) }
}
