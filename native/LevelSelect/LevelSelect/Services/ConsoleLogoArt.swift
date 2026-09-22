import Foundation
import CoreGraphics
import ImageIO

/// Fetches a console's logo from Commons and prepares it for both grounds.
///
/// **Bytes on disk, images in memory.** The PNG is kept in Caches — it's
/// derived, every device can fetch it for itself, and it isn't user data, so
/// it doesn't belong in the store or CloudKit (the same reasoning as
/// `LogoArt`'s cache). The two adapted images, one per appearance, are made
/// once per launch.
///
/// **A failed fetch isn't remembered.** Every console in the table has a
/// logo, so a miss is the network, and the next visit should try again.
@MainActor
enum ConsoleLogoArt {

    struct Prepared: @unchecked Sendable {
        let light: CGImage
        let dark: CGImage
    }

    private static var memory: [String: Prepared] = [:]
    private static var inFlight: [String: Task<Prepared?, Never>] = [:]

    /// Wikimedia asks for a descriptive agent with a contact — the one
    /// `wikidata-proxy` uses.
    private static let userAgent =
        "LevelSelect/1.0 (https://levelselect.app; wikimedia@timrmiller.com)"

    /// Text colors per appearance — the ink for what would vanish.
    nonisolated private static let lightInk: (UInt8, UInt8, UInt8) = (28, 22, 40)
    nonisolated private static let darkInk: (UInt8, UInt8, UInt8) = (240, 236, 248)

    static func cached(_ entry: ConsoleLogo.Entry) -> Prepared? { memory[entry.file] }

    static func load(_ entry: ConsoleLogo.Entry) async -> Prepared? {
        if let hit = memory[entry.file] { return hit }
        if let running = inFlight[entry.file] { return await running.value }
        let task = Task<Prepared?, Never> {
            guard let data = await bytes(for: entry) else { return nil }
            let keepsColors = entry.keepsColors
            return await Task.detached(priority: .userInitiated) {
                prepare(data, keepsColors: keepsColors)
            }.value
        }
        inFlight[entry.file] = task
        let result = await task.value
        inFlight[entry.file] = nil
        if let result { memory[entry.file] = result }
        return result
    }

    // MARK: - Bytes

    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory,
                                                    in: .userDomainMask).first else { return nil }
        let dir = caches.appending(path: "ConsoleLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func diskName(_ entry: ConsoleLogo.Entry) -> String {
        let safe = entry.file.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(safe) + ".png"
    }

    private static func bytes(for entry: ConsoleLogo.Entry) async -> Data? {
        let file = directory?.appending(path: diskName(entry))
        if let file, let data = try? Data(contentsOf: file) { return data }
        guard let url = entry.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        if let file { try? data.write(to: file, options: .atomic) }
        return data
    }

    // MARK: - Pixels

    /// Decodes, then makes the light and dark versions. Off the main actor.
    nonisolated private static func prepare(_ data: Data, keepsColors: Bool) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let original = rgba(image, width: width, height: height) else { return nil }

        func adapted(ground: Double, ink: (UInt8, UInt8, UInt8)) -> CGImage? {
            var pixels = original
            if keepsColors { return makeImage(pixels, width: width, height: height) }
            LogoLegibility.adapt(&pixels, width: width, height: height,
                                 ground: ground, ink: ink, premultiplied: true)
            return makeImage(pixels, width: width, height: height)
        }
        guard let light = adapted(ground: LogoLegibility.lightGround, ink: lightInk),
              let dark = adapted(ground: LogoLegibility.darkGround, ink: darkInk) else { return nil }
        return Prepared(light: light, dark: dark)
    }

    nonisolated private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    nonisolated private static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
