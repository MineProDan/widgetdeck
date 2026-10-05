import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An exact size in pixels (not points).
public struct PixelSize: Hashable, Codable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// Converts a point size at a display scale (e.g. widget size × `displayScale`).
    public init(points: CGSize, scale: CGFloat) {
        self.init(width: Int((points.width * scale).rounded(.up)), height: Int((points.height * scale).rounded(.up)))
    }

    public var description: String { "\(width)x\(height)" }
}

/// Memory-safe image downsampling with ImageIO.
///
/// `CGImageSourceCreateThumbnailAtIndex` decodes straight to the target size without ever
/// holding the full-resolution bitmap in memory. **Always** downsample when caching; a decoded
/// 12 MP photo in a widget (≈48 MB) exceeds the ~30 MB extension limit and renders blank.
public enum Downsampler {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case unreadableSource
        case thumbnailFailed
        case cropFailed
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableSource: "That image couldn't be opened."
            case .thumbnailFailed, .cropFailed: "That image couldn't be resized."
            case .encodingFailed: "That image couldn't be saved."
            }
        }
    }

    public enum OutputFormat: Sendable {
        case jpeg
        case heic
        case png

        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .heic: .heic
            case .png: .png
            }
        }
    }

    // MARK: Aspect fit

    /// Downsamples so the longest side is at most `maxPixelSize` (aspect ratio preserved,
    /// EXIF orientation applied). Never upsamples.
    public static func downsample(data: Data, maxPixelSize: Int) throws -> CGImage {
        try downsample(source: makeSource(data: data), maxPixelSize: maxPixelSize)
    }

    public static func downsample(url: URL, maxPixelSize: Int) throws -> CGImage {
        try downsample(source: makeSource(url: url), maxPixelSize: maxPixelSize)
    }

    // MARK: Aspect fill to exact size

    /// Produces an image of **exactly** `size` pixels: scales to fill, then center-crops.
    /// Use this for widget images, keyed by `(assetID, family, scale)`.
    public static func downsample(data: Data, toFill size: PixelSize) throws -> CGImage {
        try downsample(source: makeSource(data: data), toFill: size)
    }

    public static func downsample(url: URL, toFill size: PixelSize) throws -> CGImage {
        try downsample(source: makeSource(url: url), toFill: size)
    }

    /// Pixel dimensions after EXIF orientation, without decoding the image.
    public static func pixelSize(of data: Data) throws -> PixelSize {
        try orientedSize(of: makeSource(data: data))
    }

    // MARK: Encoding

    /// Encodes `image`. HEIC falls back to JPEG where the encoder is unavailable (some simulators).
    public static func encode(_ image: CGImage, format: OutputFormat = .jpeg, quality: Double = 0.85) throws -> Data {
        if let data = encodeOnce(image, type: format.type, quality: quality) { return data }
        if format == .heic, let data = encodeOnce(image, type: .jpeg, quality: quality) { return data }
        throw Error.encodingFailed
    }

    // MARK: Internals

    private static func makeSource(data: Data) throws -> CGImageSource {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0 else {
            throw Error.unreadableSource
        }
        return source
    }

    private static func makeSource(url: URL) throws -> CGImageSource {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options), CGImageSourceGetCount(source) > 0 else {
            throw Error.unreadableSource
        }
        return source
    }

    private static func orientedSize(of source: CGImageSource) throws -> PixelSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Error.unreadableSource }
        // EXIF orientations 5–8 are rotated 90°, so width and height swap.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    private static func downsample(source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let original = try orientedSize(of: source)
        let limit = min(max(1, maxPixelSize), max(original.width, original.height))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw Error.thumbnailFailed }
        return image
    }

    private static func downsample(source: CGImageSource, toFill target: PixelSize) throws -> CGImage {
        let original = try orientedSize(of: source)
        // Scale factor that makes the image cover the target in both dimensions.
        let scale = max(Double(target.width) / Double(original.width), Double(target.height) / Double(original.height))
        let longest = Double(max(original.width, original.height)) * scale
        let thumbnail = try downsample(source: source, maxPixelSize: Int(longest.rounded(.up)))

        if thumbnail.width == target.width && thumbnail.height == target.height { return thumbnail }
        if thumbnail.width >= target.width && thumbnail.height >= target.height {
            let rect = CGRect(x: (thumbnail.width - target.width) / 2, y: (thumbnail.height - target.height) / 2,
                              width: target.width, height: target.height)
            guard let cropped = thumbnail.cropping(to: rect) else { throw Error.cropFailed }
            return cropped
        }
        // Source smaller than the target (or off by a rounding pixel): redraw to the exact size.
        return try redraw(thumbnail, to: target)
    }

    private static func redraw(_ image: CGImage, to target: PixelSize) throws -> CGImage {
        guard let context = CGContext(data: nil, width: target.width, height: target.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Error.cropFailed }
        context.interpolationQuality = .high
        let scale = max(Double(target.width) / Double(image.width), Double(target.height) / Double(image.height))
        let drawSize = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        let origin = CGPoint(x: (Double(target.width) - drawSize.width) / 2, y: (Double(target.height) - drawSize.height) / 2)
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        guard let output = context.makeImage() else { throw Error.cropFailed }
        return output
    }

    private static func encodeOnce(_ image: CGImage, type: UTType, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
