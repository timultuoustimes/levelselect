import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Turns whatever the user picked into bytes this library can afford to keep.
///
/// Every image added here syncs to every one of the user's devices through
/// CloudKit and is embedded in their export. A 12-megapixel photo is roughly
/// 4MB; a hundred of them is a sync bill and a backup file nobody agreed to.
/// So ingest is not optional plumbing — it is the thing that decides whether
/// this feature is affordable.
///
/// Deliberately uses ImageIO rather than UIImage/NSImage: it downsamples
/// while decoding (`kCGImageSourceThumbnailMaxPixelSize`), so a large photo
/// never gets fully decoded into memory on the way past, and the same code
/// serves iOS, macOS and the tests.
enum ImageIngest {

    /// The longest edge we keep, per role.
    ///
    /// A cover is drawn at 138pt and a backdrop at full width; neither needs
    /// a camera's output. These are generous enough for a 3x display and a
    /// future iPad layout, and stingy enough to stay in the low hundreds of KB.
    static func maxPixels(for role: ArtworkRole) -> CGFloat {
        switch role {
        case .cover:    1200
        case .logo:     1200
        case .backdrop: 2200
        case .gallery:  2200
        }
    }

    struct Result: Equatable {
        var data: Data
        var pixelWidth: Int
        var pixelHeight: Int
        /// True when the source was kept as-is because re-encoding would have
        /// cost quality for no saving.
        var passedThrough: Bool
    }

    enum Failure: Error, Equatable {
        /// Not an image, or an image format this platform can't read.
        case unreadable
        /// Readable but produced no bytes — a broken or truncated file.
        case encodingFailed
    }

    /// Downscale and re-encode for storage.
    ///
    /// Keeps PNG for logos: a wordmark is the one role where transparency is
    /// load-bearing, and JPEG would put a black box behind it. Everything
    /// else becomes JPEG, which is several times smaller for photographic
    /// content.
    /// - Parameter maxPixels: overrides the role's default longest edge. A
    ///   profile avatar wants `.logo`'s PNG-and-alpha handling but nothing like
    ///   its 1200px, because `PlayerProfile.avatarData` is a plain inline
    ///   CloudKit field with roughly a 1MB record ceiling and no asset spill.
    static func prepare(
        _ source: Data,
        role: ArtworkRole,
        maxPixels override: CGFloat? = nil
    ) throws -> Result {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw Failure.unreadable
        }

        let wantsAlpha = (role == .logo)
        let limit = override ?? maxPixels(for: role)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF rotation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }

        let type: UTType = wantsAlpha ? .png : .jpeg
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData, type.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        // Quality is ignored for PNG, which is lossless.
        CGImageDestinationAddImage(destination, thumb, [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), destinationData.length > 0 else {
            throw Failure.encodingFailed
        }

        // If our "optimised" copy came out bigger than what we were handed AND
        // the source was already within bounds, keep the original. Re-encoding
        // a small PNG as a larger PNG helps nobody.
        let encoded = destinationData as Data
        if encoded.count >= source.count,
           thumb.width <= Int(limit), thumb.height <= Int(limit),
           let sourceSize = pixelSize(of: source),
           CGFloat(max(sourceSize.width, sourceSize.height)) <= limit {
            return Result(data: source,
                          pixelWidth: sourceSize.width,
                          pixelHeight: sourceSize.height,
                          passedThrough: true)
        }

        return Result(data: encoded,
                      pixelWidth: thumb.width,
                      pixelHeight: thumb.height,
                      passedThrough: false)
    }

    /// Whether the image carries an alpha channel at all.
    ///
    /// Matters only for logos, and it matters a lot: a wordmark without
    /// transparency renders as a block of its own background — usually black
    /// — sitting on the page. Nothing downstream can fix that, because the
    /// transparency was never in the file. JPEG never has alpha; a PNG
    /// saved through the photo library is frequently re-encoded to JPEG on
    /// the way in, which is exactly how a "logo PNG" arrives opaque.
    /// Prepare an image for use as a profile avatar.
    ///
    /// Chooses the encoding from the image itself rather than from a stored
    /// flag: transparency present means PNG, so a character render or a
    /// cut-out PNG from Photos keeps its alpha the way a game logo does.
    /// Anything opaque becomes JPEG, which is far smaller for a photograph.
    ///
    /// Then shrinks until the bytes fit. `avatarData` mirrors to a single
    /// BYTES field with no ASSET twin, so an avatar that overshoots CloudKit's
    /// record limit does not spill — it simply never syncs, silently, which is
    /// the failure mode worth spending a loop to avoid.
    static func prepareAvatar(_ source: Data) throws -> Result {
        let role: ArtworkRole = hasAlpha(source) ? .logo : .cover
        var result = try prepare(source, role: role, maxPixels: 640)
        for step in [480, 360, 256] where result.data.count > avatarByteBudget {
            result = try prepare(source, role: role, maxPixels: CGFloat(step))
        }
        return result
    }

    /// Comfortably inside CloudKit's ~1MB per-record ceiling, with room for
    /// the rest of the record and for the encoder to be off.
    static let avatarByteBudget = 600_000

    static func hasAlpha(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false
    }

    /// Pixel dimensions without decoding the image.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Human-readable size, for the places that tell someone what their
    /// pictures are costing.
    static func formattedBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
