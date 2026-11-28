import AppKit
import WebKit

/// Runs "Print" for one message: loads `MessagePrint.document` in a web
/// view set up like the reading pane's (no JavaScript, an ephemeral data
/// store, every navigation but the initial load refused, the remote-image
/// rule while images are blocked), hosted in a hidden window off screen
/// (a web view in no window can print blank pages), then shows the macOS
/// print panel on the app's window. `MessagePrintGate` decides what each
/// callback does. Nothing about the message is logged.
@MainActor
final class MessagePrinter: NSObject, WKNavigationDelegate {
    /// Printers in flight, kept alive until their print panel closes.
    private static var active: [ObjectIdentifier: MessagePrinter] = [:]

    private let webView: WKWebView
    private let host: NSWindow
    private weak var window: NSWindow?
    private let jobTitle: String
    private var gate = MessagePrintGate()
    /// The document's own load; callbacks of any other navigation are ignored.
    private var initialNavigation: WKNavigation?

    static func print(document: String, allowRemoteImages: Bool, jobTitle: String,
                      window: NSWindow?) {
        let printer = MessagePrinter(window: window, jobTitle: jobTitle)
        active[ObjectIdentifier(printer)] = printer
        printer.load(document, allowRemoteImages: allowRemoteImages)
    }

    private init(window: NSWindow?, jobTitle: String) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let info = NSPrintInfo.shared
        let width = max(320, info.paperSize.width - info.leftMargin - info.rightMargin)
        let frame = NSRect(x: 0, y: 0, width: width, height: 800)
        webView = WKWebView(frame: frame, configuration: config)
        // Paper is light whatever the app's appearance.
        webView.appearance = NSAppearance(named: .aqua)
        // Ordered in, so WebKit lays out and paints, but off every screen
        // (a borderless window is not moved back onto one) and inert.
        host = NSWindow(contentRect: frame.offsetBy(dx: -20_000, dy: -20_000),
                        styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.ignoresMouseEvents = true
        host.collectionBehavior = [.transient, .ignoresCycle]
        host.contentView = webView
        self.window = window
        self.jobTitle = jobTitle
        super.init()
        webView.navigationDelegate = self
        host.orderBack(nil)
    }

    private func load(_ document: String, allowRemoteImages: Bool) {
        let controller = webView.configuration.userContentController
        if allowRemoteImages {
            start(document)
        } else if let ready = HTMLRemoteImageBlocker.preparedRuleList {
            controller.add(ready)
            start(document)
        } else {
            // Delivered on the main queue. Without the rule the document's
            // own blocked CSP still refuses every remote image.
            HTMLRemoteImageBlocker.ruleList { [weak self] list in
                guard let self else { return }
                if let list { controller.add(list) }
                self.start(document)
            }
        }
    }

    private func start(_ document: String) {
        initialNavigation = webView.loadHTMLString(document, baseURL: nil)
        // An image that never answers holds the load's end back: print
        // what is there after the pane's own bound.
        DispatchQueue.main.asyncAfter(deadline: .now() + HTMLBodyLayout.loadBound) { [weak self] in
            self?.printIfReady()
        }
    }

    private func printIfReady() {
        guard gate.startsPrinting() else { return }
        guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo,
              let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        else { return end() }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // A zero-sized print view prints blank pages.
        operation.view?.frame = webView.bounds
        // `run()` is not supported for a web view's print operation: modal
        // on the window only.
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                           contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        end()
    }

    private func end() {
        gate.printingEnded()
        webView.navigationDelegate = nil
        webView.stopLoading()
        host.orderOut(nil)
        host.contentView = nil
        Self.active[ObjectIdentifier(self)] = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === initialNavigation else { return }
        printIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === initialNavigation, gate.endsOnFailure() else { return }
        end()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard navigation === initialNavigation, gate.endsOnFailure() else { return }
        end()
    }

    /// The document's own load only: no refresh, redirect, frame or link.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        let initial = navigationAction.request.url == nil || scheme == "about"
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        guard initial, mainFrame, navigationAction.navigationType != .linkActivated,
              gate.allowsNavigation()
        else { return decisionHandler(.cancel) }
        decisionHandler(.allow)
    }
}
