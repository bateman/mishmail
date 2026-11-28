import SwiftUI
import AppKit

extension AccountRailPalette {
    static let background = Color(nsColor: .adaptive(light: backgroundLight, dark: backgroundDark))
    static let glyph = Color(nsColor: .adaptive(light: glyphLight, dark: glyphDark))
    static let idleRing = Color(nsColor: .adaptive(light: idleRingLight, dark: idleRingDark))
}

/// The always-visible strip left of the sidebar: one avatar per account
/// (ring, unread badge), "All accounts" first when there are several, a "+"
/// to add an account, and at the bottom the Settings button.
struct AccountRail: View {
    static let avatarSize = AccountRailMetrics.avatarSize
    static let width = AccountRailMetrics.width
    static let showAddAccountKey = AccountRailMetrics.showAddAccountKey
    static let showAddAccountDefault = AccountRailMetrics.showAddAccountDefault

    @AppStorage(AccountRail.showAddAccountKey) private var showAddAccount =
        AccountRail.showAddAccountDefault

    @Environment(MailStore.self) var store
    private var bound: Bindable<MailStore> { Bindable(store) }
    /// Id of the account being dragged, for the live reorder.
    @State private var draggingAccountId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Many accounts scroll; the bottom area stays put.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if UnifiedInbox.railShowsEntry(enabled: store.unifiedInboxEnabled,
                                                   accountCount: store.accounts.count) { allEntry }
                    ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                        accountEntry(account, shortcut: UnifiedInbox.shortcutDigit(
                            forAccountAt: index, enabled: store.unifiedInboxEnabled))
                            .onDrag {
                                draggingAccountId = account.id
                                return NSItemProvider(object: account.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: AccountDropDelegate(
                                target: account, draggingId: $draggingAccountId, store: store))
                    }
                    if showAddAccount { addButton }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            bottomArea
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        // Behind the title bar too, so it joins the top band
        // (`AccountRailTopBand`) with no seam.
        .background(AccountRailPalette.background.ignoresSafeArea())
        // A drop outside an account avatar still clears the dragged id.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            draggingAccountId = nil
            return true
        }
        .sheet(isPresented: bound.editingAccountLabels) {
            AccountLabelsEditor()
        }
    }

    // MARK: - Entries

    private var allEntry: some View {
        let selected = store.activeAccountId == nil
        return Button {
            store.setActiveAccount(nil)
        } label: {
            Image(systemName: "tray.2.fill")
                .font(.system(size: 17))
                .foregroundStyle(AccountRailPalette.glyph)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .background(Circle().fill(AccountRailPalette.glyph.opacity(0.14)))
                .overlay {
                    if selected {
                        Circle().strokeBorder(AccountRailPalette.glyph,
                                              lineWidth: AccountAvatarView.emphasizedRingWidth)
                    }
                }
                .opacity(selected ? 1 : 0.6)
                // After the dimming, so the ring keeps its full contrast.
                .overlay {
                    if !selected {
                        Circle().strokeBorder(AccountRailPalette.idleRing, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("All accounts (⌘1)")
        .accessibilityLabel("All accounts")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("accountRail.all")
    }

    private func accountEntry(_ account: Account, shortcut: Int) -> some View {
        // With one account the unified entry is hidden, so it is the selection.
        let selected = store.activeAccountId == account.id || store.accounts.count == 1
        let unread = store.accountUnread[account.id] ?? 0
        let title = AccountLabelColor.title(account)
        let needsReauth = store.accountsNeedingReauth.contains(account.id)
        let tooltip = [title, account.id, unread > 0 ? "\(unread) unread" : nil]
            .compactMap { $0 }.joined(separator: " · ")
            + (shortcut <= 9 ? " (⌘\(shortcut))" : "")
        return Button {
            store.setActiveAccount(account.id)
        } label: {
            AccountAvatarView(
                name: title, key: account.id, size: Self.avatarSize,
                photo: store.accountPhotos[account.id],
                ring: .init(storedHex: account.labelColor, surface: .rail),
                decorative: true, unread: unread,
                emphasized: selected, dimmed: !selected)
                .overlay(alignment: .bottomTrailing) {
                    if needsReauth {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(1.5)
                            .background(Circle().fill(AccountRailPalette.background))
                            .offset(x: 3, y: 3)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(needsReauth ? tooltip + " — needs to be reauthorized" : tooltip)
        .accessibilityLabel("\(title), \(account.id)")
        .accessibilityValue([unread > 0 ? "\(unread) unread" : nil,
                             needsReauth ? "needs reauthorization" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(store.accounts.count > 1 ? "Drag to reorder" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("accountRail.account.\(account.id)")
        .contextMenu {
            if needsReauth {
                Button("Reauthorize…") { store.addAccount(reauthorizing: account.id) }
                    .disabled(store.connectingAccount)
            }
            Button("Edit Account Labels…") { store.editingAccountLabels = true }
            if store.connectingAccount {
                Button("Cancel Connecting") { store.cancelAccountSignIn() }
            } else {
                Button("Add Google Account…") { store.addAccount() }
            }
        }
    }

    private var addButton: some View {
        Button {
            // While the browser sign-in waits, the same button gives it up.
            if store.connectingAccount {
                store.cancelAccountSignIn()
            } else {
                store.addAccount()
            }
        } label: {
            Image(systemName: store.connectingAccount ? "xmark" : "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AccountRailPalette.glyph)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .overlay(Circle().strokeBorder(AccountRailPalette.glyph.opacity(0.5),
                                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(store.connectingAccount ? "Connecting… Click to cancel." : "Add Google Account…")
        .accessibilityLabel(store.connectingAccount ? "Cancel connecting" : "Add Google Account")
        .accessibilityIdentifier("accountRail.add")
    }

    // MARK: - Bottom area

    /// Grows upward: the gear is last; a later link (contacts, chat,
    /// calendar) goes in the stack above it, one line each.
    private var bottomArea: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(AccountRailPalette.glyph.opacity(0.15))
                .frame(width: Self.avatarSize, height: 1)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(AccountRailPalette.glyph)
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("accountRail.settings")
        }
        .padding(.bottom, 10)
    }
}

/// The top of the upside-down "L": a band in the rail's colour, as tall as the
/// title-bar row, from the window's left edge across the window buttons to the
/// sidebar's right edge (sidebar collapsed, in light: to the window's right edge, see
/// `AccountRailMetrics.bandSpansWindow`). An overlay of the window's content, so it also covers
/// the top of the sidebar; toolbar items (the sidebar toggle) stay above it.
struct AccountRailTopBand: View {
    @Environment(MailStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    /// Whether the sidebar is on screen (decided by `ContentView`).
    let sidebarVisible: Bool
    /// Whether the collapsed sidebar (`SidebarIconStrip`) is on screen.
    var stripVisible = false
    /// The sidebar is collapsed (the preference), strip on screen or not.
    var sidebarCollapsed = false

    var body: some View {
        // Read here, not inside the GeometryReader closure, so the view
        // observes the store.
        let width = AccountRailMetrics.bandWidth(
            sidebarTrailing: store.sidebarTrailingEdge, sidebarVisible: sidebarVisible,
            stripVisible: stripVisible)
        let spansWindow = AccountRailMetrics.bandSpansWindow(
            sidebarCollapsed: sidebarCollapsed, isLight: colorScheme == .light)
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            // Always the rail colour. Sidebar collapsed, in light, the content's top
            // bar is white against the rail's grey, which cut the sidebar
            // toggle in half; there the colour also runs under the rest of the
            // title-bar row, so no seam crosses the toggle, the view icon or
            // the title. Dark keeps its short band: the content colour is
            // nearly the rail's. The band itself (the element the UI tests
            // measure) keeps its `bandWidth`; the rest is a separate fill.
            ZStack(alignment: .topLeading) {
                if spansWindow {
                    AccountRailPalette.background
                        .frame(width: proxy.size.width, height: top)
                        .accessibilityHidden(true)
                }
                AccountRailPalette.background
                    .frame(width: width, height: top)
                    // Only the UI test looks the band up, by frame.
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("accountRail.topBand")
            }
            .offset(y: -top)
        }
        .allowsHitTesting(false)
    }
}

/// Reports one horizontal edge (right by default) of the view it backs, in
/// window coordinates. Measured in AppKit: the sidebar lives in a split-view
/// column, and the search field in a toolbar item, where SwiftUI's own
/// geometry (`GeometryReader`, `.global`) did not give the real edge.
struct HorizontalEdgeReader: NSViewRepresentable {
    var edge: HorizontalEdge = .trailing
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> EdgeView {
        let view = EdgeView()
        view.leading = edge == .leading
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: EdgeView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class EdgeView: NSView {
        var onChange: ((CGFloat) -> Void)?
        var leading = false
        private var last: CGFloat?

        /// Frame observers on the ancestors: when one moves without resizing
        /// this view (the icon strip leaving shifts the split view left), the
        /// edge moves too and no layout of this view reports it.
        /// Dropped when the view leaves its window.
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeAncestors()
            report()
        }

        /// Re-parented inside the same window: the chain of ancestors changed.
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            observeAncestors()
            report()
        }

        private func observeAncestors() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if window != nil {
                var ancestor = superview
                while let view = ancestor {
                    observers.append(NotificationCenter.default.addObserver(
                        forName: NSView.frameDidChangeNotification, object: view, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    })
                    ancestor = view.superview
                }
            }
        }

        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); report() }
        override func layout() { super.layout(); report() }

        func report() {
            guard window != nil else { return }
            let frame = convert(bounds, to: nil)
            let edge = (leading ? frame.minX : frame.maxX).rounded()
            guard edge != last else { return }
            last = edge
            DispatchQueue.main.async { [weak self] in self?.onChange?(edge) }
        }
    }
}

/// Live-reorders the rail as a dragged avatar crosses a neighbor — the
/// standard SwiftUI reorderable pattern (`List.onMove` is not available in a
/// plain stack).
struct AccountDropDelegate: DropDelegate {
    let target: Account
    @Binding var draggingId: String?
    let store: MailStore

    func dropEntered(info: DropInfo) {
        guard let draggingId, draggingId != target.id,
              let from = store.accounts.firstIndex(where: { $0.id == draggingId }),
              let to = store.accounts.firstIndex(where: { $0.id == target.id }) else { return }
        store.reorderAccounts(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}
