import Foundation

/// What "Print" (the message's "More" menu) prints, as Gmail on the web
/// prints one message: the subject, then the sender with the date, To and
/// Cc, then the body as the pane renders it. Pure — tested;
/// `MessagePrinter` loads the document in an offscreen web view and runs
/// the macOS print panel.
///
/// Every header value is escaped: a subject or sender name holding HTML is
/// printed as text, never interpreted. The body goes through the reading
/// pane's own trusted wrapper (`HTMLBodyDocument.trustedWrapper`), with the
/// CSP the card's remote-content decision gives: printing never loads
/// content the pane blocks.
enum MessagePrint {
    /// The body to print, decided like the pane decides it.
    enum Body: Equatable {
        /// Untrusted message HTML (stored, `cid:`-inlined or with cached
        /// remote images inlined).
        case html(String)
        /// Plain text, escaped when the document is built.
        case text(String)
    }

    /// The pane's body rules, without its collapsed quote (Gmail prints the
    /// whole message): the text that replaces the body first (the card's
    /// decrypted or signed PGP text, or its notice: never the armor),
    /// then the "Show plain text" choice, then the HTML body, then the
    /// plain text.
    static func body(replacement: String?, showPlainText: Bool,
                     html: String?, text: String) -> Body {
        if let replacement { return .text(replacement) }
        if showPlainText, !text.isEmpty { return .text(text) }
        if let html, !html.isEmpty { return .html(html) }
        return .text(text)
    }

    /// Gmail's print date: "Thu, Nov 27, 2025 at 3:04 PM".
    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }

    /// The header block: escaped text only, inline styles so the message's
    /// own stylesheet cannot easily restyle it.
    static func headerHTML(subject: String, from: String, to: String, cc: String,
                           date: Date, timeZone: TimeZone = .current) -> String {
        let shownSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = """
        <div style="display:flex;justify-content:space-between;gap:16px;margin:0 0 2px 0">\
        <span>\(escape(from))</span>\
        <span style="white-space:nowrap">\(escape(dateText(date, timeZone: timeZone)))</span></div>
        """
        if !to.isEmpty { rows += "<div>To: \(escape(to))</div>" }
        if !cc.isEmpty { rows += "<div>Cc: \(escape(cc))</div>" }
        return """
        <div id="dreamail-print-header" style="font:13px -apple-system,sans-serif;color:#000;\
        margin:0 0 16px 0;padding:0 0 12px 0;border-bottom:1px solid #ccc">\
        <div style="font-size:18px;font-weight:bold;margin:0 0 12px 0">\
        \(escape(shownSubject.isEmpty ? "(no subject)" : shownSubject))</div>\
        \(rows)</div>
        """
    }

    /// Print stylesheet: always light (paper), the pane's image sizing.
    static let styleCSS = """
    :root { color-scheme: light; }
    body { font: 13px -apple-system, sans-serif; color: #000; background: #fff; margin: 0; }
    img { max-width: 100%; height: auto; }
    """

    /// The whole document handed to the web view.
    static func document(header: String, body: Body, allowRemoteImages: Bool) -> String {
        let content: String
        switch body {
        case .html(let html):
            content = html
        case .text(let text):
            content = "<div style=\"white-space:pre-wrap;font:13px -apple-system,sans-serif\">"
                + escape(text) + "</div>"
        }
        return HTMLBodyDocument.trustedWrapper(
            html: header + content,
            cspMeta: HTMLBodyCSP.metaTag(allowRemoteImages: allowRemoteImages),
            styleCSS: styleCSS)
    }

    /// The print job's name, as Gmail's page title gives it: the subject.
    /// Also the name "Save as PDF" proposes.
    static func jobTitle(subject: String) -> String {
        let shown = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return shown.isEmpty ? "(no subject)" : shown
    }

    private static func escape(_ s: String) -> String {
        ComposeLinks.escapeAttribute(s)
    }
}

/// What `MessagePrinter` does with the web view's callbacks. Only the
/// first navigation (the document's own `loadHTMLString`) is allowed; the
/// print panel starts once, at that load's end or at the bound, whichever
/// comes first; after that every navigation is refused and every failure
/// ignored, so a `<meta http-equiv="refresh">` can neither open a second
/// panel nor end the job while the panel is open. Pure — tested.
struct MessagePrintGate: Equatable {
    enum Phase: Equatable { case loading, printing, done }
    private(set) var phase: Phase = .loading
    private var navigationAllowed = false

    /// A navigation policy decision: true for the initial load only.
    mutating func allowsNavigation() -> Bool {
        guard phase == .loading, !navigationAllowed else { return false }
        navigationAllowed = true
        return true
    }

    /// The initial load finished, or the load bound passed: true once,
    /// when the print panel is to start.
    mutating func startsPrinting() -> Bool {
        guard phase == .loading else { return false }
        phase = .printing
        return true
    }

    /// The initial load failed: true when the job is to end (only before
    /// printing started).
    mutating func endsOnFailure() -> Bool {
        guard phase == .loading else { return false }
        phase = .done
        return true
    }

    /// The print panel closed (or could not open).
    mutating func printingEnded() {
        phase = .done
    }
}
