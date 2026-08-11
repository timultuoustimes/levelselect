import Foundation
import CoreText

/// Registers bundled display fonts (Press Start 2P) for this process.
/// Runtime registration keeps the multiplatform Info.plist free of the
/// per-OS font keys (UIAppFonts / ATSApplicationFontsPath).
enum FontRegistrar {
    static func registerBundledFonts() {
        guard let url = Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf") else {
            assertionFailure("PressStart2P-Regular.ttf missing from bundle")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
