import Foundation

/// How a conversation opens from the list (Settings → Appearance).
enum ThreadOpenStyle: String, CaseIterable {
    /// Superhuman-style: the conversation fills the whole window; Esc (or
    /// the back button) returns to the list.
    case fullWindow
    /// Outlook/Apple Mail-style: the conversation shows in a pane beside
    /// the list.
    case readingPane
    /// Center peek: the conversation opens in a centered card over
    /// the list; Esc (or clicking the backdrop) returns to it.
    case centerPeek

    static let storageKey = "threadOpenStyle"

    /// The style for an install with no stored choice: Gmail's reading pane
    /// beside the list. A stored choice always wins.
    static let defaultStyle: ThreadOpenStyle = .readingPane

    /// The style for a stored raw value; nil or unrecognized (a value from a
    /// newer or older build) falls back to `defaultStyle`.
    static func resolved(storedRaw: String?) -> ThreadOpenStyle {
        storedRaw.flatMap(ThreadOpenStyle.init(rawValue:)) ?? defaultStyle
    }
}

enum MailLayoutMode: Equatable {
    case list
    case compactDetail
    case threePane
    /// Conversation fills the window (sidebar + list hidden). Entered via ⌘↩.
    case threadFocus
}

enum MailLayout {
    /// Below this width, keeping sidebar + list + message visible makes the
    /// reading pane too narrow to read. Compact mode swaps list and message.
    /// UI tests only (`DREAMAIL_UI_TEST=1`) may lower it with
    /// `DREAMAIL_THREE_PANE_MIN_WIDTH`: the CI screen is 1024 pt wide, too
    /// narrow for three panes at 1080.
    static let threePaneMinimumWidth: CGFloat = resolvedThreePaneMinimumWidth(
        environment: ProcessInfo.processInfo.environment)

    static func resolvedThreePaneMinimumWidth(environment: [String: String]) -> CGFloat {
        if environment["DREAMAIL_UI_TEST"] == "1",
           let raw = environment["DREAMAIL_THREE_PANE_MIN_WIDTH"],
           let value = Double(raw), value > 0 {
            return CGFloat(value)
        }
        return 1_080
    }

    /// First-launch window width. Must fit three panes, since the default
    /// open style is the reading pane (`ThreadOpenStyle.defaultStyle`).
    static let defaultWindowWidth: CGFloat = 1_200

    static func mode(width: CGFloat, readingPaneHidden: Bool,
                     hasSelection: Bool,
                     threadFocus: Bool = false,
                     fullWindowThreads: Bool = false) -> MailLayoutMode {
        // Superhuman-style open: there is no side-by-side reading pane at
        // all — you're either on the list or inside the conversation.
        if fullWindowThreads {
            return (threadFocus && hasSelection) ? .threadFocus : .list
        }
        // Focus needs a selected conversation; without one, fall through.
        if threadFocus, hasSelection { return .threadFocus }
        if readingPaneHidden { return .list }
        if width < threePaneMinimumWidth {
            return hasSelection ? .compactDetail : .list
        }
        return .threePane
    }

    /// Width the layout mode is computed from: the mailbox host, less the
    /// Ask AI panel, plus the collapsed sidebar's icon strip when it is on
    /// screen. The strip sits outside the host (right of the account rail)
    /// but stands in for a sidebar that is collapsed, so it must not move
    /// the three-pane threshold: collapsing the sidebar never drops the
    /// reading pane.
    static func modeWidth(host: CGFloat, askAIPanel: CGFloat, stripShown: Bool) -> CGFloat {
        host - askAIPanel + (stripShown ? AccountRailMetrics.stripWidth : 0)
    }
}
