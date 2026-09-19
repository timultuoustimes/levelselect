import SwiftUI
#if os(iOS)
import MessageUI
#endif
#if os(macOS)
import AppKit
#endif

/// Mail, composed inside the app.
///
/// Tim: *"Being able to inform people, and give them a way to communicate with
/// me, all from within the app and not needing to go to my website or their
/// email is the best way to do it. It removes every bit of friction one could
/// bump up against."*
///
/// Three paths, in order of how well they keep that promise:
///
/// 1. **iOS with a mail account** — `MFMailComposeViewController` presents
///    over the app. Nothing leaves LevelSelect and nothing is sent until the
///    person taps Send in a sheet they can read in full.
/// 2. **Anywhere else** — a `mailto:` URL hands the same prefilled message to
///    whatever mail app they do have. One app switch, still no retyping.
/// 3. **Neither** — the text is copied to the clipboard with the address, so
///    the message survives even on a device with no mail set up at all.
///
/// There is no server in any of these. The message goes from their mail
/// account to `feedback@levelselect.app` and the reply lands back in their own
/// inbox — which is also why there is no ticket number to lose.
enum Mail {
    static let feedbackAddress = "feedback@levelselect.app"

    /// Whether path 1 is available. Everything else falls to `mailto:`.
    static var canComposeInApp: Bool {
        #if os(iOS)
        MFMailComposeViewController.canSendMail()
        #else
        false
        #endif
    }

    /// Path 2. Returns false when the system has nothing that opens `mailto:`.
    @discardableResult
    static func openInMailApp(to: String, subject: String, body: String) -> Bool {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components.url else { return false }
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
        #endif
    }

    /// Path 3.
    static func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#if os(iOS)
/// The in-app compose sheet.
///
/// Deliberately thin: it prefills and reports back whether the message was
/// sent, and nothing else. The app never reads the message, never keeps a
/// copy, and cannot send it — the person does, from their own account.
struct MailComposeSheet: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    /// True only for `.sent`. Cancel and save-as-draft both report false, so a
    /// caller can avoid claiming a question was answered when it wasn't.
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([to])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
            onFinish(result == .sent)
        }
    }
}
#endif
