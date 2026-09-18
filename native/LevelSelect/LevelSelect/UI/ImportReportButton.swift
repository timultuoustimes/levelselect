import SwiftUI

/// "This didn't import — send it to LevelSelect."
///
/// Every community sheet is laid out its own way, so the reader only gets
/// better from the ones it fails on. Tim, 09-17: *"If we get enough sent to
/// us, then we can hopefully close gaps and minimize the numbers that fail
/// going forward."* The person sends it from their own mail, after reading
/// it, to `feedback@levelselect.app` — nothing leaves the device otherwise.
struct ImportFailureReport: Equatable {
    /// "Google Sheets link", "CSV file", "Pasted list".
    var source: String
    /// What went wrong, as the person saw it.
    var problem: String
    var link: String? = nil
    var tab: String? = nil
    var fileName: String? = nil
    /// The rows themselves, attached as a .csv (or .txt for a paste).
    var content: String? = nil

    var subject: String { "LevelSelect \(Diagnostics.versionString) — Import didn't work (\(source))" }

    /// Everything that explains it, readable on its own. The start of the
    /// content goes in too, for the mail app path that can't attach.
    func body(inlineLimit: Int) -> String {
        var lines = ["What happened: \(problem)", "Source: \(source)"]
        if let link { lines.append("Link: \(link)") }
        if let tab { lines.append("Tab: \(tab)") }
        if let fileName { lines.append("File: \(fileName)") }
        lines.append("App: \(Diagnostics.versionString)")
        var text = "Here's a list LevelSelect couldn't read. (Anything you'd like to add about what you expected is welcome above this line.)\n\n"
            + lines.joined(separator: "\n")
        if let content, inlineLimit > 0 {
            let head = String(content.prefix(inlineLimit))
            text += "\n\n— First part of the file —\n" + head
            if content.count > inlineLimit { text += "\n… (\(content.count - inlineLimit) more characters)" }
        }
        return text + "\n"
    }

    var attachment: (data: Data, mimeType: String, fileName: String)? {
        guard let content, !content.isEmpty else { return nil }
        let isCSV = source != "Pasted list"
        let base = fileName.map { ($0 as NSString).deletingPathExtension } ?? tab ?? "import"
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return (Data(content.utf8), isCSV ? "text/csv" : "text/plain",
                "\(safe).\(isCSV ? "csv" : "txt")")
    }
}

struct ImportReportButton: View {
    let report: ImportFailureReport
    var label = "Send this to LevelSelect so it can learn to read it"
    @State private var composing = false
    @State private var outcome: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                send()
            } label: {
                Label(label, systemImage: "paperplane")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
            Text(outcome ?? "Opens an email to \(Mail.feedbackAddress) with the \(report.content == nil ? "link" : "sheet") attached. Nothing is sent until you tap Send.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #if os(iOS)
        .sheet(isPresented: $composing) {
            MailComposeSheet(to: Mail.feedbackAddress, subject: report.subject,
                             body: report.body(inlineLimit: 0),
                             attachment: report.attachment) { sent in
                if sent { outcome = "Sent — thank you. It helps the next person with a sheet like yours." }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private func send() {
        #if os(iOS)
        if Mail.canComposeInApp {
            composing = true
            return
        }
        #endif
        // A mail link can't attach, and a long one won't open: the first part
        // of the file rides in the body instead.
        if Mail.openInMailApp(to: Mail.feedbackAddress, subject: report.subject,
                              body: report.body(inlineLimit: 1500)) {
            outcome = "Opened in Mail. If you can, attach the file there too."
        } else {
            Mail.copyToClipboard("To: \(Mail.feedbackAddress)\nSubject: \(report.subject)\n\n"
                                 + report.body(inlineLimit: 20_000))
            outcome = "No mail app here — copied it to the clipboard, addressed to \(Mail.feedbackAddress)."
        }
    }
}
