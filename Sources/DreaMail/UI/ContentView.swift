import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Global frame of the reading-pane column — used to pin inline compose.
private struct ReadingPaneFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

/// Global frame of the compose overlay host (window content).
private struct ComposeHostFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

struct ContentView: View {
    @Environment(MailStore.self) var store
    /// `@Environment` has no projected value, so sheets and controls that need
    /// two-way access to the store go through this instead of `$store`.
    private var bound: Bindable<MailStore> { Bindable(store) }
    /// Extracted from the draft-delete `.alert`: an inline get/set Binding
    /// there pushes the modifier chain past the type checker's time limit.
    private var confirmingDraftDeleteShown: Binding<Bool> {
        Binding(
            get: { store.confirmingDraftDelete != nil },
            set: { if !$0 { store.confirmingDraftDelete = nil } }
        )
    }
    // No `ListFocusState` observation here. ObservableObject invalidation is
    // per object, so observing it re-ran this whole body — the root
    // GeometryReader, toolbar, and detail pane — on every ↓ / j. The
    // open-policy `onChange` lives in `ListFocusObserver` (an invisible
    // child), and the two bits of body state that depend on focus arrive as
    // `focusFacts`, which only changes when one of those bits flips.
    @State private var focusFacts = ListFocusFacts()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyMonitor: Any?
    /// Toolbar bridge for the split-compose conversation column.
    @State private var splitToolbarModel = ThreadToolbarModel()
    @State private var layoutMode: MailLayoutMode = .list
    // Persisted so the layout survives relaunch, like the sidebar state.
    @AppStorage("readingPaneHidden") private var readingPaneHidden = false
    // Gmail-style (default): the conversation shows in a reading pane
    // beside the list. Settings → Appearance can switch to full-window or
    // the centered card.
    @AppStorage(ThreadOpenStyle.storageKey) private var threadOpenStyleRaw =
        ThreadOpenStyle.defaultStyle.rawValue
    // Sidebar starts collapsed to its icon strip; ← collapses it, → expands
    // it (persisted).
    @AppStorage("sidebarHidden") private var sidebarHidden = true
    /// "More" and the order of the system views, shared by the full sidebar
    /// and its collapsed icon strip.
    @State private var sidebarDisclosure = SidebarDisclosureModel()
    /// Measured frames for PreferenceKey-aligned inline compose.
    @State private var readingPaneFrame: CGRect = .zero
    @State private var composeHostFrame: CGRect = .zero
    @State private var detailSelectionTask: Task<Void, Never>?
    /// Last browse keyDown's auto-repeat flag — single presses open at 0 ms;
    /// held-key repeats coalesce via `DetailOpenPolicy.keyRepeatSettleNanoseconds`.
    @State private var browseKeyIsRepeat = false
    /// Width the Ask AI panel currently claims (0 when hidden). The compose
    /// overlay is window-trailing, so it shifts left by this much.
    @State private var askAIPanelWidth: CGFloat = 0
    @State private var showDefaultMailPrompt = false
    @State private var settingDefaultMail = false

    /// Whether a sidebar is on screen: not collapsed, not replaced by the
    /// split compose or by a full-window conversation (the center peek keeps
    /// the list layout underneath).
    private var sidebarOnScreen: Bool {
        !sidebarHidden && sidebarSlotShown
    }

    /// Whether the collapsed sidebar (the icon strip) is on screen: where the
    /// full one would be.
    private var sidebarStripOnScreen: Bool {
        sidebarHidden && sidebarSlotShown
    }

    /// Where a sidebar, full or collapsed, has room: not replaced by the
    /// split compose or by a full-window conversation (the center peek keeps
    /// the list layout underneath).
    private var sidebarSlotShown: Bool {
        guard !splitComposeActive else { return false }
        return layoutMode != .threadFocus || centerPeekThreads
    }

    /// Gmail's `/` (and the strip's search icon): focus the search field in
    /// the list column's toolbar. It always reaches search: with a
    /// conversation filling the window (full-window style, centre peek) or
    /// open in the compact layout there is no list to focus, so the
    /// conversation is left first, as Esc does, and the field focuses when the
    /// list mounts (`searchFocusPending`).
    private func revealSearch() {
        if store.threadFocusMode {
            store.threadFocusMode = false
        } else if layoutMode == .compactDetail {
            store.clearSelection()
        }
        store.focusSearch()
    }

    private var fullWindowThreads: Bool {
        // Center peek shares the whole open/close flow with full-window
        // (threadFocusMode, Esc ladder, compose placement) — only the
        // rendering differs (overlay card instead of a takeover).
        ThreadOpenStyle.resolved(storedRaw: threadOpenStyleRaw) != .readingPane
    }

    private var centerPeekThreads: Bool {
        ThreadOpenStyle.resolved(storedRaw: threadOpenStyleRaw) == .centerPeek
    }

    /// What "the reading pane is hidden" means for compose placement and
    /// inline-compose promotion. In full-window style the pane is the focus
    /// view itself: visible while a conversation is open, hidden on the list.
    private var effectivePaneHidden: Bool {
        fullWindowThreads ? !store.threadFocusMode : readingPaneHidden
    }

    /// Sidebar collapse driven by ←/→ (and the native toolbar toggle).
    /// `hidden` is the split view's "sidebar collapsed" value for the
    /// current column count (.detailOnly for 2, .doubleColumn for 3).
    private func splitVisibility(whenHidden hidden: NavigationSplitViewVisibility)
        -> Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarHidden ? hidden : .all },
            set: { sidebarHidden = ($0 != .all) }
        )
    }

    // `body` is split into stages (baseLayout → interactionLayer → body):
    // as one modifier chain the type checker times out on the expression
    // ("unable to type-check this expression in reasonable time").
    private var baseLayout: some View {
        GeometryReader { proxy in
            // Compact mode swaps list ↔ detail on whether a conversation is
            // actually OPEN — the quiet auto-highlight of the top row is a
            // selection without an open, and must keep showing the list.
            // Ask AI takes width from the mailbox, so the layout mode must be
            // derived from what is left — otherwise a window that is wide
            // enough only with the panel closed keeps a three-pane layout it
            // can no longer fit.
            let askAIVisible = AskAILayout.showsPanel(
                hostWidth: proxy.size.width,
                enabled: store.showAskAI && AIFeatures.isEnabled)
            let panelWidth = askAIVisible
                ? AskAILayout.panelWidth(hostWidth: proxy.size.width) : 0
            let mode = MailLayout.mode(
                width: MailLayout.modeWidth(host: proxy.size.width, askAIPanel: panelWidth,
                                            stripShown: sidebarStripOnScreen),
                readingPaneHidden: readingPaneHidden,
                hasSelection: store.openedThreadId != nil,
                threadFocus: store.threadFocusMode,
                fullWindowThreads: fullWindowThreads)
            // Center peek keeps the list layout mounted underneath (stable
            // view identity — no list teardown on open/close) and floats the
            // conversation card in an overlay instead of switching layouts.
            let peekOpen = centerPeekThreads && mode == .threadFocus
            HStack(spacing: 0) {
                Group {
                    if splitComposeActive {
                        splitComposeLayout(hostWidth: proxy.size.width - panelWidth)
                    } else {
                        mailboxLayout(peekOpen ? .list : mode)
                            .overlay {
                                if peekOpen { centerPeekOverlay }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Compose pins itself to this host, so the frame must exclude
                // the panel or a floating card would sit under it.
                .background(
                    GeometryReader { host in
                        Color.clear.preference(
                            key: ComposeHostFrameKey.self,
                            value: host.frame(in: .global))
                    }
                )
                if askAIVisible {
                    // Reserve the panel's width without animation: animating
                    // the mail column's width re-lays out every WKWebView in
                    // the open conversation each frame, which reads as a
                    // freeze. The content snaps once; only the panel slides.
                    Color.clear.frame(width: panelWidth)
                }
            }
            .overlay(alignment: .trailing) {
                ZStack(alignment: .trailing) {
                    if askAIVisible {
                        HStack(spacing: 0) {
                            Divider()
                            AskAIPanelView(
                                controller: store.askAIControllerCreatingIfNeeded())
                        }
                        .frame(width: panelWidth)
                        .transition(.move(edge: .trailing))
                    }
                }
                // Scoped here, not on the outer HStack, so the slide never
                // animates the mailbox/detail layout.
                .animation(.easeOut(duration: 0.18), value: askAIVisible)
            }
            .onAppear {
                layoutMode = mode
                askAIPanelWidth = panelWidth
            }
            .onChange(of: mode) { layoutMode = mode }
            .onChange(of: panelWidth) { askAIPanelWidth = panelWidth }
        }
    }

    /// List focus moved (runs from `ListFocusObserver`, not from this body —
    /// see `focusFacts`). Consumes the one-shot selection intent and applies
    /// the open policy.
    private func handleListFocusChange() {
        let intent = store.consumeSelectionIntent()
        // Leaving a thread (or clearing selection) promotes inline compose
        // to the floating card so the draft stays editable.
        store.promoteInlineComposeIfNeeded(
            selectedThreadId: store.selectedThreadId,
            readingPaneHidden: effectivePaneHidden)
        // Focus mode requires a conversation; drop it when selection clears.
        if store.selectedThreadId == nil {
            store.threadFocusMode = false
            detailSelectionTask?.cancel()
        }
        guard let selectedId = store.selectedThreadId else { return }
        // Auto-highlight of the top row (Superhuman default): selection
        // only — never opens the conversation.
        if intent == .quiet { return }
        if intent == .browse {
            // Hidden-pane browsing is highlight-only. Ask AI is too:
            // opening in compact width replaces the thread list, so ↓
            // would jump to the next email instead of letting the user
            // keep scrolling. Enter / click still open.
            if DetailOpenPolicy.browseOpensDetail(
                paneHidden: effectivePaneHidden,
                askAIVisible: askAIPanelWidth > 0) {
                if DetailOpenPolicy.opensImmediately(
                    openedThreadId: store.openedThreadId,
                    listedIds: store.threads.lazy.map(\.id)) {
                    // Auto-advance after trash/archive: the opened row is
                    // gone, so debouncing would blank and rebuild the pane.
                    detailSelectionTask?.cancel()
                    store.openDetail(selectedId)
                } else {
                    scheduleDetailSelection(selectedId)
                }
            }
        } else {
            openClickedThread(selectedId, intent: intent)
        }
    }

    private var interactionLayer: some View {
        baseLayout
        .onPreferenceChange(ReadingPaneFrameKey.self) { frame in
            readingPaneFrame = frame
            // Pathological short panes: float compose instead of a 0-height dock.
            store.demoteInlineComposeIfPaneTooShort(paneHeight: frame.height)
        }
        .onPreferenceChange(ComposeHostFrameKey.self) { composeHostFrame = $0 }
        // Search lives in the list column's top bar (ListSearchToolbar).
        // Typing only feeds the dropdown preview; the list follows
        // committedSearch. Clearing the field also clears an active search.
        .onChange(of: store.searchText) {
            if store.searchText.isEmpty, !store.committedSearch.isEmpty {
                store.committedSearch = ""
                store.reloadThreads()
            }
        }
        // A clicked (not keyboard-browsed) selection reopens the reading pane.
        // Clicking a pure draft skips the pane entirely and hops straight
        // into compose at the bottom.
        // Selection changes publish only through ListFocusState, so the
        // observer child is the trigger that consumes the one-shot
        // selection intent.
        .background {
            ListFocusObserver(facts: $focusFacts, onFocusChange: handleListFocusChange)
        }
        // A click on the row that is already selected (e.g. the pre-highlighted
        // top row) produces no selection change — open it via this token.
        .onChange(of: store.openSelectedToken) {
            guard let selectedId = store.selectedThreadId else { return }
            openClickedThread(selectedId)
        }
        .onChange(of: readingPaneHidden) {
            // Full-window style ignores the reading-pane flag entirely; the
            // focus-mode onChange below owns compose placement there.
            guard !fullWindowThreads else { return }
            store.readingPaneHiddenForCompose = readingPaneHidden
            store.promoteInlineComposeIfNeeded(
                selectedThreadId: store.selectedThreadId,
                readingPaneHidden: readingPaneHidden)
            if readingPaneHidden { store.threadFocusMode = false }
            else if let selected = store.selectedThreadId {
                detailSelectionTask?.cancel()
                store.openDetail(selected)
            }
        }
        .onChange(of: store.threadFocusMode) {
            guard fullWindowThreads else { return }
            store.readingPaneHiddenForCompose = !store.threadFocusMode
            // Going back to the list with an inline reply open keeps the
            // draft as a floating card instead of tearing it down.
            store.promoteInlineComposeIfNeeded(
                selectedThreadId: store.selectedThreadId,
                readingPaneHidden: !store.threadFocusMode)
            if store.threadFocusMode, let selected = store.selectedThreadId {
                detailSelectionTask?.cancel()
                store.openDetail(selected)
            }
        }
        .onChange(of: store.selectedView) {
            store.clearSelection()
            store.clearCheckedThreads()
            store.resetChips()
            // Sidebar click (or any selectedView write) should land on the
            // real mailbox, not keep a committed `/` search overlay. goTo
            // clears search first; this covers the List selection binding.
            if !store.searchText.isEmpty || !store.committedSearch.isEmpty {
                store.searchText = ""
                store.committedSearch = ""
            }
            store.reloadThreads()
        }
        .onChange(of: store.chips) { store.reloadThreadsDebounced() }
        .onAppear {
            store.readingPaneHiddenForCompose = effectivePaneHidden
            store.openDetail(store.selectedThreadId)
            installKeyMonitor()
            // Don't let the search field start with keyboard focus —
            // it would swallow Esc/j/k until clicked away.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            considerDefaultMailPrompt()
        }
        .onChange(of: store.accounts.count) { _, _ in
            considerDefaultMailPrompt()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            store.viewCommandHandler = nil
            detailSelectionTask?.cancel()
            detailSelectionTask = nil
        }
        // Refocusing the app lands with the top row selected (Superhuman-
        // style) when nothing else is — ↩ opens it without touching arrows.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            store.autoSelectTopThread()
        }
        .toolbar {
            // List only (no reading-pane column): the list column's toolbar
            // shows them instead, after the search field (`paneButtons`).
            if layoutMode != .list {
                ToolbarItemGroup { paneButtons }
            }
        }
    }

    /// The window's pane toggle, focus button and Ask AI. With a reading pane
    /// they sit at the trailing end of its column. With the list only, as
    /// root items they came between the view's title and the search field,
    /// pushing the field right: there the list column's toolbar shows them
    /// after the field, at the window's trailing end (`ListSearchToolbar`).
    @ViewBuilder
    private var paneButtons: some View {
        // Full-window style has no reading pane to toggle.
        if !fullWindowThreads {
            Button {
                readingPaneHidden.toggle()
            } label: {
                Label(readingPaneHidden ? "Show Reading Pane" : "Hide Reading Pane",
                      systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .help(readingPaneHidden ? "Show the reading pane (⌥⌘0)"
                                    : "Hide the reading pane (⌥⌘0)")
        }
        Button {
            guard store.selectedThreadId != nil else { return }
            store.threadFocusMode.toggle()
            if store.threadFocusMode, !fullWindowThreads {
                readingPaneHidden = false
                store.readingPaneHiddenForCompose = false
            }
        } label: {
            Label(store.threadFocusMode ? "Exit Focus" : "Focus Conversation",
                  systemImage: store.threadFocusMode
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
        }
        .disabled(!focusFacts.hasSelection)
        .help(store.threadFocusMode
              ? "Exit full-app conversation (esc or ⌘↩)"
              : "Open conversation full-app (⌘↩)")
        // No button, so no ⌥⌘M, in a build without AI features.
        if AIFeatures.isEnabled {
            Button {
                store.showAskAI.toggle()
            } label: {
                Label("Ask AI", systemImage: "sparkles")
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .help("Ask AI (⌥⌘M)")
        }
    }

    var body: some View {
        // The account rail sits outside the mailbox layout, so it stays
        // visible whatever the sidebar does, and the layout mode is derived
        // from the width that is left of it.
        HStack(spacing: 0) {
            AccountRail()
            if sidebarStripOnScreen {
                SidebarIconStrip()
                    // Under the center peek's backdrop, as the full
                    // sidebar is (`centerPeekOverlay`).
                    .overlay {
                        if centerPeekThreads, layoutMode == .threadFocus {
                            Color.black.opacity(CenterPeekLayout.backdropOpacity)
                                .contentShape(Rectangle())
                                .onTapGesture { store.threadFocusMode = false }
                        }
                    }
            }
            interactionLayer
        }
        .environment(sidebarDisclosure)
        // "Deleted means gone" (DEC-019): a removed account's disclosure
        // state leaves memory with its defaults.
        .onChange(of: store.accounts.map(\.id)) { old, new in
            for id in Set(old).subtracting(new) { sidebarDisclosure.forget(accountId: id) }
        }
        .overlay(alignment: .topLeading) {
            AccountRailTopBand(sidebarVisible: sidebarOnScreen, stripVisible: sidebarStripOnScreen,
                               sidebarCollapsed: sidebarHidden)
        }
        // Single ComposeView host for both floating and inline so presentation
        // flips keep editor state. Floating = bottom-trailing card; inline =
        // bottom of the reading-pane column (leading inset skips sidebar/list).
        .overlay(alignment: .bottomTrailing) {
            Group {
                if let request = store.composeRequest {
                    composeChrome(request)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8),
                       value: store.composeRequest?.id)
            .animation(.spring(response: 0.28, dampingFraction: 0.85),
                       value: store.composeMinimized)
            .animation(.spring(response: 0.3, dampingFraction: 0.85),
                       value: store.composeRequest?.presentation)
            // Keep the card inside the mailbox column when Ask AI is open.
            .padding(.trailing, askAIPanelWidth)
        }
        .animation(.easeOut(duration: 0.2), value: store.threadFocusMode)
        .animation(.easeOut(duration: 0.1), value: splitComposeActive)
        // Undo + notice toasts: bottom-leading. Notice is non-interactive so it
        // never covers clickable controls (draft card Continue/Discard sit
        // bottom-center/trailing); undo stays hit-testable for the Undo button.
        // Stacked in one overlay so both can appear without overlapping.
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 10) {
                if let notice = store.notice {
                    Text(notice)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 22).padding(.vertical, 13)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let undo = store.undoAction {
                    HStack(spacing: 14) {
                        Text(undo.label)
                            .font(.system(size: 14, weight: .medium))
                        Button {
                            undo.undo()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Undo")
                                // Rebindable single-key (default `z`); ⌘Z is also
                                // wired in the key monitor for the standard chord.
                                Text(store.keyBindings.displayKey(for: .undo))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .opacity(0.75)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .help("Undo (\(store.keyBindings.displayKey(for: .undo)) or ⌘Z)")
                        .accessibilityIdentifier("undoToast.undo")
                    }
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.leading, 20 + AccountRail.width).padding(.bottom, 20)
        }
        // Presence only — not `undoAction?.id` — so rapid keyboard archive/
        // trash updates the label in place instead of re-sliding every time.
        .animation(PMMotion.feedback, value: UndoToast.isPresented(store.undoAction))
        .animation(PMMotion.feedback, value: store.notice)
        .sheet(item: bound.editingView) { view in
            ViewEditor(view: view)
        }
        .alert(
            "Delete this draft?",
            isPresented: confirmingDraftDeleteShown,
            presenting: store.confirmingDraftDelete
        ) { draft in
            Button("Delete", role: .destructive) { store.deleteDraft(draft) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert("Open mailto: links in DreaMail?", isPresented: $showDefaultMailPrompt) {
            Button("Set as Default") {
                settingDefaultMail = true
                DefaultMailClient.makeDefault { _ in
                    Task { @MainActor in
                        settingDefaultMail = false
                        if DefaultMailClient.isDefault {
                            showDefaultMailPrompt = false
                        }
                    }
                }
            }
            .disabled(settingDefaultMail)
            Button("Not Now", role: .cancel) {
                DefaultMailClient.dismissDefaultOffer()
            }
        } message: {
            Text("When DreaMail is your default email app, browsers and other apps open compose here for mailto: links.")
        }
        .sheet(isPresented: bound.showShortcutsHelp) {
            ShortcutsHelpView(bindings: store.keyBindings)
        }
        .sheet(isPresented: bound.showLabelOrganizer) {
            LabelOrganizer()
        }
        // Snooze is an overlay (not a .sheet): modal sheet presentation on
        // macOS costs ~200–300 ms of window chrome + animation, so the
        // presets felt laggy after `b`. LabelPicker / CommandPalette already
        // use this pattern for the same reason.
        .overlay {
            if store.showCommandPalette {
                CommandPalette()
            }
            if store.showLabelPicker {
                LabelPicker(picker: store.labelPicker)
            }
            if let thread = store.snoozingThread {
                SnoozeSheet(
                    current: thread.snoozeUntil,
                    snooze: { store.snooze(thread, until: $0) },
                    cancel: { store.dismissSnoozePicker() }
                )
                // Reset query/highlight if the target thread changes while open.
                .id(thread.id)
            } else if store.snoozingChecked {
                // Multi-select `h`/`b`: no single "current" snooze date to
                // show, so the sheet's "Unsnooze" clear option stays hidden
                // (it only appears when `current != nil`) and `snooze` is
                // never called with `nil` here.
                SnoozeSheet(
                    current: nil,
                    snooze: { date in
                        guard let date else { return }
                        store.snoozeChecked(until: date)
                    },
                    cancel: { store.dismissSnoozePicker() }
                )
            }
        }
        // Non-modal error banner (a background sync hiccup shouldn't interrupt
        // you). Sits above the undo/notice toast; stays until dismissed.
        .overlay(alignment: .bottom) {
            if let error = store.lastError {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: 360, alignment: .leading)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    }
                    .buttonStyle(.borderless)
                    if store.lastErrorRecovery == .retrySync {
                        Button("Sync") {
                            store.lastError = nil
                            Task { await store.syncAll() }
                        }
                        .buttonStyle(.borderless)
                    } else if store.lastErrorRecovery == .reauthorize {
                        Button("Reauthorize") {
                            UserDefaults.standard.set(SettingsView.Pane.accounts.rawValue,
                                                      forKey: "settingsPane")
                            store.lastError = nil
                            openSettings()
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        store.lastError = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .pmHitTarget(extra: 8)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PMRadius.md + 2))
                .overlay(RoundedRectangle(cornerRadius: PMRadius.md + 2).strokeBorder(.orange.opacity(0.4)))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.lastError)
        // First-run: guide the Google setup instead of dead-ending on an empty
        // inbox. Disappears the moment an account connects or demo starts.
        .overlay {
            if store.accounts.isEmpty {
                OnboardingView()
            }
        }
        // Read-only cache (F-02): a persistent strip, separate from the error
        // banner, so nothing dismisses it and no later error replaces it.
        .overlay(alignment: .top) {
            if store.storageState == .readOnly, let message = store.storageState.statusMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PMRadius.md))
                .overlay(RoundedRectangle(cornerRadius: PMRadius.md).strokeBorder(.orange.opacity(0.4)))
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        }
        // Plaintext cache too old to read without migrating it (F-02): show no
        // mailbox — it would look empty — and no onboarding either.
        .overlay {
            if !store.storageState.showsMailbox, let message = store.storageState.statusMessage {
                VStack(spacing: 14) {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Finish encrypting your mail")
                        .font(.title2.weight(.semibold))
                    Text(message)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: store.undoAction?.id) {
            guard let undo = store.undoAction else { return }
            postAccessibilityAnnouncement("\(undo.label). Undo is available.")
        }
        .onChange(of: store.notice) {
            if let notice = store.notice { postAccessibilityAnnouncement(notice) }
        }
        .onChange(of: store.lastError) {
            if let error = store.lastError { postAccessibilityAnnouncement(error) }
        }
        // One app-level Reduce Motion gate covers the entire rendered body,
        // including compose, toast, search, and error-banner overlays.
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }

    private func postAccessibilityAnnouncement(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    @ViewBuilder
    private func mailboxLayout(_ mode: MailLayoutMode) -> some View {
        switch mode {
        case .list:
            NavigationSplitView(columnVisibility: splitVisibility(whenHidden: .detailOnly)) {
                Sidebar()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
            } detail: {
                listColumnWithSearch
            }
        case .compactDetail:
            NavigationSplitView(columnVisibility: splitVisibility(whenHidden: .detailOnly)) {
                Sidebar()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
            } detail: {
                detailPane(compact: true)
            }
        case .threePane:
            NavigationSplitView(columnVisibility: splitVisibility(whenHidden: .doubleColumn)) {
                Sidebar()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
            } content: {
                listColumnWithSearch
                    .navigationSplitViewColumnWidth(min: 420, ideal: 560)
            } detail: {
                detailPane(compact: false)
            }
        case .threadFocus:
            // Full-app conversation: no sidebar / list chrome.
            detailPane(compact: false)
        }
    }

    /// Center peek: the conversation floats in a card over
    /// the (still-mounted) list. Reuses detailPane, so the WebView pool,
    /// warm payloads, and inline-compose pinning all behave as in focus mode.
    private var centerPeekOverlay: some View {
        GeometryReader { host in
            let card = CenterPeekLayout.cardSize(host: host.size)
            ZStack {
                Color.black.opacity(CenterPeekLayout.backdropOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.threadFocusMode = false }
                detailPane(compact: false)
                    .frame(width: card.width, height: card.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
    }

    /// Side-by-side compose is active: the layout swaps to the split canvas
    /// and the overlay card fills the right column. Minimizing pauses split
    /// (mailbox comes back); expanding restores it.
    private var splitComposeActive: Bool {
        store.composeRequest?.presentation == .split && !store.composeMinimized
    }

    /// Left column of split compose: the draft's source conversation,
    /// full-height. The right column is empty space the overlay-hosted
    /// ComposeView pins itself to (same view identity as floating/inline,
    /// so entering/leaving split keeps the typed body).
    ///
    /// `NavigationStack` hosts the detail toolbar (exit split, archive/star,
    /// reply, ⋯ More) — without it the column is a bare HStack child and
    /// principal/editor toolbar items never mount.
    @ViewBuilder
    private func splitComposeLayout(hostWidth: CGFloat) -> some View {
        let composeWidth = ComposePlacement.splitComposeWidth(hostWidth: hostWidth)
        HStack(spacing: 0) {
            NavigationStack {
                Group {
                    if let id = store.composeRequest?.boundThreadId,
                       let thread = store.thread(withId: id) {
                        ThreadDetailView(
                            thread: thread,
                            compactMode: false,
                            focusMode: true,
                            splitMode: true,
                            toolbarModel: splitToolbarModel,
                            onBack: { store.exitSplitCompose() },
                            onReply: { msg in
                                store.openCompose(.init(replyTo: msg))
                            })
                            // Fresh view state per conversation, as in the
                            // main detail path: a "load images for this
                            // conversation" opt-in must never carry over.
                            // The Trash view's trashed-only reader is its
                            // own identity there too: leaving the Trash
                            // remounts the live conversation.
                            .id(store.opensTrashReader(threadId: thread.id)
                                ? "\(thread.id)#trash" : thread.id)
                            .modifier(ThreadDetailToolbar(
                                thread: thread,
                                compactMode: false,
                                focusMode: true,
                                splitMode: true,
                                model: splitToolbarModel,
                                onBack: { store.exitSplitCompose() },
                                onReply: { msg in
                                    store.openCompose(.init(replyTo: msg))
                                }))
                    } else {
                        Text("Conversation unavailable")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mailContent)
            Color.clear
                .frame(width: composeWidth)
                // Reserve width only — clicks land on the trailing compose
                // overlay card, not this spacer.
                .allowsHitTesting(false)
        }
    }

    /// Detail column is mounted and idle — floating compose can claim it as
    /// a primary writing surface (pane fill). Pure rule lives in
    /// `ComposePlacement.readingPaneIsEmpty` (three-pane only).
    private var readingPaneIsEmpty: Bool {
        ComposePlacement.readingPaneIsEmpty(
            layoutMode: layoutMode,
            openedThreadId: store.openedThreadId)
    }

    /// Floating card vs inline vs pane-fill vs split. One ComposeView identity
    /// so pop-out / promote keep the typed body.
    @ViewBuilder
    private func composeChrome(_ request: MailStore.ComposeRequest) -> some View {
        let minimized = store.composeMinimized
        let presentation = ComposePlacement.resolvedPresentation(
            request.presentation,
            paneHeight: readingPaneFrame.height,
            readingPaneEmpty: readingPaneIsEmpty,
            paneWidth: readingPaneFrame.width)
        // Minimized always docks like floating regardless of presentation.
        let chromePresentation: ComposePresentation = minimized ? .floating : presentation
        let inline = presentation == .inline && !minimized
        let pane = presentation == .pane && !minimized
        let pinToPane = inline || pane
        let split = presentation == .split && !minimized
        let chrome = ComposePlacement.cardChrome(
            presentation: chromePresentation,
            minimized: minimized,
            host: composeHostFrame,
            pane: readingPaneFrame,
            layoutMode: layoutMode)
        let splitPad = ComposePlacement.splitPadding
        let inlineHeight = ComposePlacement.effectiveInlineCardHeight(
            paneHeight: readingPaneFrame.height)
        let paneHeight = ComposePlacement.effectivePaneCardHeight(
            paneHeight: readingPaneFrame.height)
        let cardHeight: CGFloat = minimized ? 40
            : split ? max(composeHostFrame.height - splitPad * 2, 400)
            : pane ? paneHeight
            : (inline ? inlineHeight
               : ComposePlacement.effectiveFloatingCardHeight(
                    hostHeight: composeHostFrame.height))
        // Pin-to-pane uses a full-host-width HStack so trailing-anchored
        // placement agrees with chrome.leading (leading + width + trailing
        // == host). Leading gutter spans sidebar + list under pane-fill —
        // force hit-through so mailbox clicks still land (defensive even if
        // plain Spacer often ignores hits).
        HStack(spacing: 0) {
            if pinToPane {
                Spacer()
                    .frame(width: chrome.leading)
                    .allowsHitTesting(false)
            }
            ComposeView(request: request)
                .id(request.id)
                // topLeading: an over-wide child must not center-clip under
                // clipShape (footer fixedSize / long tokens on narrow cards).
                .frame(width: chrome.width, height: cardHeight, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: minimized ? PMRadius.md : PMRadius.lg))
                .pmCardElevation(cornerRadius: minimized ? PMRadius.md : PMRadius.lg,
                                 intense: true)
            if pinToPane {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
        }
        .padding(pane
                 ? EdgeInsets(top: 0, leading: 0,
                              bottom: ComposePlacement.paneBottomPadding,
                              trailing: chrome.trailingPadding)
                 : inline
                 ? EdgeInsets(top: 0, leading: 0,
                              bottom: ComposePlacement.inlineBottomPadding,
                              trailing: chrome.trailingPadding)
                 : split
                 ? EdgeInsets(top: splitPad, leading: 0,
                              bottom: splitPad, trailing: chrome.trailingPadding)
                 : EdgeInsets(top: 0, leading: 0,
                              bottom: ComposePlacement.floatingBottomPadding,
                              trailing: chrome.trailingPadding))
        // Pane fill is derived (not stored on the request); animate size when
        // the empty-pane condition flips (e.g. open/close a conversation).
        .animation(.spring(response: 0.3, dampingFraction: 0.85),
                   value: presentation)
    }

    /// True when expanded inline compose is open for the selected thread —
    /// detail pane reserves bottom safe area so the scroll doesn't hide under it.
    /// Pane fill sits in an empty column and must not reserve thread scroll space.
    private var reservesInlineComposeSpace: Bool {
        // `composeBoundToSelection` is `boundThreadId == selectedThreadId`,
        // maintained by ListFocusObserver so this body never reads focus.
        guard let req = store.composeRequest,
              !store.composeMinimized,
              focusFacts.composeBoundToSelection else { return false }
        return ComposePlacement.resolvedPresentation(
                req.presentation,
                paneHeight: readingPaneFrame.height,
                readingPaneEmpty: readingPaneIsEmpty,
                paneWidth: readingPaneFrame.width
            ) == .inline
    }

    private var inlineComposeReserveHeight: CGFloat {
        guard reservesInlineComposeSpace else { return 0 }
        return ComposePlacement.inlineReservedHeight(
            paneHeight: readingPaneFrame.height)
    }

    @ViewBuilder
    private var listColumn: some View {
        if store.selectedView == .scheduled {
            ScheduledListView()
        } else if store.selectedView == .outbox {
            OutboxListView()
        } else {
            ThreadListView()
        }
    }

    private var listColumnWithSearch: some View {
        listColumn.modifier(ListSearchToolbar(
            trailingButtons: layoutMode == .list ? paneButtons : nil))
    }

    @ViewBuilder
    private func detailPane(compact: Bool) -> some View {
        // Equatable host: ContentView re-renders for many reasons (compose,
        // toasts, layout) but must not rebuild ThreadDetailView until
        // openedThreadId actually changes.
        DetailPaneHost(
            openedThreadId: store.openedThreadId,
            thread: store.openedThreadId.flatMap { id in
                store.threads.first(where: { $0.id == id })
            },
            compact: compact,
            focusMode: store.threadFocusMode,
            paneHidden: effectivePaneHidden,
            inlineReserve: inlineComposeReserveHeight,
            // Read here because DetailPaneHost is deliberately store-free.
            // Non-mutating, so evaluating it in `body` has no side effects.
            trashReader: OpenFromSearch.showsTrashReader(
                openedId: store.openedThreadId, projected: store.trashViewProjectedIds),
            initialPayload: store.openedThreadId.flatMap {
                store.warmThreadDetail(threadId: $0)
            },
            onBack: {
                if store.threadFocusMode {
                    store.threadFocusMode = false
                } else {
                    store.clearSelection()
                }
            },
            onReply: { msg in
                store.openCompose(.init(replyTo: msg),
                                  readingPaneHidden: effectivePaneHidden)
            }
        )
        .equatable()
    }
}

/// The only focus-derived facts ContentView's body renders from. Held in
/// ContentView `@State` and written only when a value flips, so a focus move
/// between two ordinary rows re-renders nothing at the root.
private struct ListFocusFacts: Equatable {
    /// Something is highlighted (enables "Focus Conversation").
    var hasSelection = false
    /// The open compose request is bound to the highlighted thread (inline
    /// compose reserves space in the reading pane).
    var composeBoundToSelection = false
}

/// Invisible child that owns ContentView's list-focus observation, so the
/// root body (GeometryReader, toolbar, detail pane) does not depend on
/// `ListFocusState`. Its body is a zero-size clear view: re-running it per
/// ↓ / j costs one comparison.
private struct ListFocusObserver: View {
    @EnvironmentObject private var listFocus: ListFocusState
    @Environment(MailStore.self) private var store
    @Binding var facts: ListFocusFacts
    /// Open policy for a focus move; see `ContentView.handleListFocusChange`.
    let onFocusChange: () -> Void

    private var currentFacts: ListFocusFacts {
        let selected = listFocus.id
        return ListFocusFacts(
            hasSelection: selected != nil,
            composeBoundToSelection: selected != nil
                && store.composeRequest?.boundThreadId == selected)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: listFocus.id) { onFocusChange() }
            // `initial: true` seeds ContentView before the first focus move.
            .onChange(of: currentFacts, initial: true) { _, new in
                if facts != new { facts = new }
            }
    }
}

/// Isolates reading-pane identity from list-focus churn. Compared only on the
/// fields that should remount or reconfigure the conversation UI.
private struct DetailPaneHost: View, Equatable {
    let openedThreadId: String?
    let thread: MailThread?
    let compact: Bool
    let focusMode: Bool
    let paneHidden: Bool
    let inlineReserve: CGFloat
    /// The open thread is shown from its trashed messages only
    /// (`MailStore.opensTrashReader`). Part of the pane's identity: when it
    /// changes, the pane remounts and loads the other reader.
    let trashReader: Bool
    /// Seeds a remounted `ThreadDetailView` so its first frame already shows
    /// the conversation. Excluded from `==` (below) and safe to go stale: it
    /// is only consumed when `.id(thread.id)` builds a new pane, which cannot
    /// happen without `thread` — which *is* compared — changing first.
    let initialPayload: ThreadDetailPayload?
    let onBack: () -> Void
    let onReply: (Message) -> Void
    @State private var toolbarModel = ThreadToolbarModel()

    // Closures are deliberately excluded, so a skipped body keeps the OLD
    // captures. Safe only while every environment value a closure captures is
    // mirrored by a compared field (onReply's `effectivePaneHidden` ↔
    // `paneHidden`; onBack reads store live). If you capture a new value in a
    // closure, add its mirror here or it will go stale.
    static func == (lhs: DetailPaneHost, rhs: DetailPaneHost) -> Bool {
        lhs.openedThreadId == rhs.openedThreadId
            && lhs.thread == rhs.thread
            && lhs.compact == rhs.compact
            && lhs.focusMode == rhs.focusMode
            && lhs.paneHidden == rhs.paneHidden
            && lhs.inlineReserve == rhs.inlineReserve
            && lhs.trashReader == rhs.trashReader
    }

    var body: some View {
        Group {
            if let thread {
                // The remount (`.id`) must sit inside a container, and the
                // toolbar outside it. With `.id` directly on the column's
                // content, or the toolbar declared inside the remounted
                // view, SwiftUI re-creates every NSToolbarItem per open:
                // measured at over half the main-thread work of opening a
                // conversation. Both halves are needed; either alone is not.
                VStack(spacing: 0) {
                    ThreadDetailView(
                        thread: thread,
                        compactMode: compact,
                        focusMode: focusMode,
                        initialPayload: initialPayload,
                        toolbarModel: toolbarModel,
                        onBack: onBack,
                        onReply: onReply)
                        .id(trashReader ? "\(thread.id)#trash" : thread.id)
                }
                .modifier(ThreadDetailToolbar(
                    thread: thread,
                    compactMode: compact,
                    focusMode: focusMode,
                    model: toolbarModel,
                    initialMessages: initialPayload?.messages,
                    onBack: onBack,
                    onReply: onReply))
            } else {
                Text("Select a conversation")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .background(Color.mailContent)
        // Keep the last messages above the overlay card.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: inlineReserve)
                .accessibilityHidden(true)
        }
        .animation(nil, value: inlineReserve)
        // Publish the reading column's global frame for inline compose pin.
        // MUST sit outside the safeAreaInset: the reserve height is computed
        // from this measurement, so measuring inside the inset feeds the
        // reserve back into its own input — at window heights below ~1050pt
        // the two maps have no fixed point and layout livelocks (396↔592
        // oscillation, 99% CPU, unbounded memory; shipped in 72d6524).
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ReadingPaneFrameKey.self,
                    value: geo.frame(in: .global))
            }
        )
    }
}

// MARK: - ContentView keyboard helpers (extension keeps main struct smaller)

private extension ContentView {

    /// Offer to claim `mailto:` once, after onboarding (account connected).
    /// macOS still shows its own confirmation when the user accepts.
    func considerDefaultMailPrompt() {
        guard !store.demoMode,
              !store.accounts.isEmpty,
              DefaultMailClient.shouldOfferDefault,
              !showDefaultMailPrompt else { return }
        showDefaultMailPrompt = true
    }

    /// Gmail-style single-key shortcuts plus Cmd-K. Ignores events when a
    /// text field, the search bar, or a sheet has focus.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        store.viewCommandHandler = { command in
            switch command {
            case .open: openSelectedFromKeyboard()
            case .backToList: backToList()
            case .archiveNext, .archivePrevious:
                // Gmail's `[` / `]` act on the open conversation only.
                guard BackToList.conversationOnScreen(
                    layoutMode: layoutMode,
                    openedThread: store.openedThreadId != nil) else { return }
                store.archiveOpenConversation(
                    goToPrevious: command == .archivePrevious)
            case .nextMessage, .previousMessage, .expandAll, .collapseAll:
                // Gmail's `n` `p` `;` `:` act inside the open conversation.
                guard BackToList.conversationOnScreen(
                    layoutMode: layoutMode,
                    openedThread: store.openedThreadId != nil),
                      let action = MessageNavigation.Action(command) else { return }
                store.requestConversationKey(action)
            default: break
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
            guard let store else { return event }
            // Settings is capturing a key for rebinding — don't run shortcuts.
            if store.keyBindings.capturing { return event }
            // Any sheet or alert is up (new label, Organize Labels, filter,
            // signature, default-mail prompt, label menu dialogs, the "l"
            // picker's "Create new"...): its keys, Esc included, belong to
            // it. The event's window is the sheet (`sheetParent`), or the
            // main window holding one (`attachedSheet`), or a popover of a
            // sheet (the colour palette in Organize Labels: its `parent`
            // is the sheet). Single letters like "e" and "#" were already
            // blocked behind a sheet (`MailboxKeyGate`); what this stops is
            // Escape walking the mailbox ladder (reading pane, checks,
            // search) and the other shortcuts (⌘1-9, ⌃F, ⌘K) acting behind
            // a dialog. The shortcuts help is the one sheet that needs `?`
            // and Esc handled below.
            if !store.showShortcutsHelp, DialogKeyOwnership.owns(event.window) {
                return event
            }
            // A label menu dialog is up (Edit, colour, Remove, failure):
            // its keys, Esc included, belong to it. Kept: it is set before
            // the sheet window attaches.
            if store.labelMenu.presentsDialog { return event }
            // Quick Look panel is up: every key (Esc, space, arrows) belongs
            // to the panel — the Esc ladder below must not close the reading
            // pane underneath it. `event.window is QLPreviewPanel` misses the
            // case where the local monitor still sees the main window.
            if QuickLookKeyOwnership.claimsKeys(
                eventWindowIsPreviewPanel: event.window is QLPreviewPanel,
                previewPanelVisible: QLPreviewPanel.sharedPreviewPanelExists()
                    && QLPreviewPanel.shared().isVisible) {
                return event
            }
            // The snooze overlay runs its own monitor (↑/↓/Return/Esc while
            // typing a date) — everything must pass through untouched. Same
            // for the bulk variant opened over a multi-select.
            if store.snoozingThread != nil || store.snoozingChecked { return event }
            // ⇧⌘↩ toggles side-by-side compose (conversation | draft). Runs
            // before the compose-typing passthrough so it works mid-sentence.
            if event.modifierFlags.intersection([.command, .shift, .option, .control])
                == [.command, .shift],
               event.keyCode == 36, store.composeRequest != nil {
                store.toggleSplitCompose()
                return nil
            }
            // Compose Esc ladder (before NSText passthrough): expanded compose
            // owns Esc while open, but priority is explicit — never local-
            // monitor install order (FIFO; an early `return nil` starves later
            // monitors). Pure policy in ComposeEsc.intent.
            if event.keyCode == 53 {
                let isSettings = event.window?.identifier?.rawValue
                    .contains("Settings") == true
                // Mid-finish (Send awaiting persist) is not "expanded" for Esc:
                // save-and-close already ran; don't re-queue it.
                let composeExpanded = ComposeKeyOwnership.claimsTyping(
                    hasRequest: store.composeRequest != nil,
                    minimized: store.composeMinimized,
                    finishing: store.composeFinishing)
                let isSplit = store.composeRequest?.presentation == .split
                    && !store.composeFinishing
                switch ComposeEsc.intent(
                    isSettingsWindow: isSettings,
                    fromPickerOpen: store.fromPickerOpen,
                    slashPickerVisible: store.slashPickerVisible,
                    commandPaletteOpen: store.showCommandPalette,
                    searchActive: store.searchActive,
                    composeExpanded: composeExpanded,
                    isSplit: isSplit) {
                case .passThrough:
                    // Settings: when compose is nil/minimized the mailbox Esc
                    // ladder below owns blur-then-close; with expanded compose
                    // that gate is skipped and AppKit gets the event (pre-existing).
                    break
                case .dismissFromPicker:
                    store.dismissFromPicker()
                    return nil
                case .dismissSlashPicker:
                    store.dismissSlashPicker()
                    return nil
                case .closeCommandPalette:
                    store.mailboxOverlay = nil
                    return nil
                case .dismissSearchFocus:
                    // Keep the draft; drop search focus/panel (three-pane +
                    // floating compose + `/` must not save-and-close).
                    event.window?.makeFirstResponder(nil)
                    store.dismissSearchPanel()
                    return nil
                case .exitSplit:
                    store.exitSplitCompose()
                    return nil
                case .saveAndCloseCompose:
                    store.requestComposeEsc()
                    return nil
                case .fallThrough:
                    break
                }
            }
            // Expanded compose + typing: every chord belongs to the text system
            // / compose handlers (⌘K insert-link, ⌃F/⌃K caret motion, …), not
            // app-level shortcuts. Minimized compose resigns focus so inbox
            // keys work again. Mid-finish (Send awaiting
            // persist) also yields so `g i` is not typed into the body. Esc
            // for compose is handled above so it is not trapped here.
            if ComposeKeyOwnership.claimsTyping(
                    hasRequest: store.composeRequest != nil,
                    minimized: store.composeMinimized,
                    finishing: store.composeFinishing),
               event.window?.firstResponder is NSText {
                return event
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            if mods == .command, event.charactersIgnoringModifiers == "k" {
                store.mailboxOverlay = store.showCommandPalette ? nil : .commands
                return nil
            }
            // ⌘↩: Send when expanded compose owns the chord (button shortcut).
            // Otherwise toggle thread focus mode (conversation fills the app).
            // Plain ⌘ only — ⌘⇧↩ is side-by-side compose (handled above) and
            // must never fall through to focus when no compose is open.
            if mods == .command, event.keyCode == 36,
               !event.modifierFlags.contains(.shift) {
                let composeClaimsReturn = ComposeKeyOwnership.claimsTyping(
                    hasRequest: store.composeRequest != nil,
                    minimized: store.composeMinimized,
                    finishing: store.composeFinishing)
                if !composeClaimsReturn, store.selectedThreadId != nil {
                    store.threadFocusMode.toggle()
                    if store.threadFocusMode, !fullWindowThreads {
                        readingPaneHidden = false
                        store.readingPaneHiddenForCompose = false
                    }
                    return nil
                }
            }
            // ⌘↑/⌘↓: jump to the first / last conversation. Never while a
            // text field owns the caret (⌘arrows are line start/end there).
            if mods == .command, !event.modifierFlags.contains(.shift),
               event.keyCode == 125 || event.keyCode == 126,
               !store.showCommandPalette, !store.showLabelPicker,
               store.editingView == nil,
               !TextFocus.isEditing(event.window?.firstResponder) {
                browseKeyIsRepeat = event.isARepeat
                store.jumpSelection(toEnd: event.keyCode == 125)
                return nil
            }
            // ⌘1 = All accounts, ⌘2… = individual accounts, in rail order
            // (one shortcut per inbox).
            if mods == .command, let chars = event.charactersIgnoringModifiers,
               chars.count == 1, let digit = Int(chars), (1...9).contains(digit) {
                switch UnifiedInbox.shortcut(digit: digit, enabled: store.unifiedInboxEnabled,
                                             railOrder: store.accounts.map(\.id)) {
                case .unified:
                    store.setActiveAccount(nil)
                    return nil
                case .account(let id):
                    store.setActiveAccount(id)
                    return nil
                case .none:
                    return event
                }
            }
            if mods == .control, event.charactersIgnoringModifiers == "f" {
                store.showFilterMenu.toggle()
                return nil
            }
            // ⌘Z undoes the pending toast action (archive/trash/send…). Bare
            // `z` is the rebindable single-key below; this chord is the macOS
            // standard and must not rely on a SwiftUI button shortcut (those
            // often miss when the toast has just appeared). Match the bare-key
            // overlay guards (palette / label picker / view editor) so ⌘Z and
            // `z` agree. Never steal text undo while expanded compose owns typing.
            // After Send, a lagging AppKit re-steal can leave an editable NSText
            // first responder with no compose claiming typing — allow ⌘Z to
            // cancel pending send in that window (same class as post-Send `e`).
            if mods == .command,
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "z",
               store.undoAction != nil,
               !store.showCommandPalette,
               !store.showLabelPicker,
               !store.showShortcutsHelp,
               store.editingView == nil,
               ComposeKeyOwnership.allowsMailboxKeys(
                   hasRequest: store.composeRequest != nil,
                   minimized: store.composeMinimized,
                   finishing: store.composeFinishing),
               !(TextFocus.isEditing(event.window?.firstResponder)
                 && ComposeKeyOwnership.textFocusBlocksMailboxKeys(
                     finishing: store.composeFinishing)
                 && !ComposeKeyOwnership.undoChordBypassesTextFocus(
                     pendingSend: store.pendingSend != nil,
                     composeClaimsTyping: ComposeKeyOwnership.claimsTyping(
                         hasRequest: store.composeRequest != nil,
                         minimized: store.composeMinimized,
                         finishing: store.composeFinishing))) {
                store.perform(.undo)
                return nil
            }
            // ⌘A selects every thread currently loaded in the list (Gmail-
            // style select-all), mirroring the checkbox multi-select. It
            // yields to anything that already owns ⌘A: editable fields
            // (search, compose, address chips, Settings…), the selectable
            // conversation text, and the HTML body's web view all keep the
            // OS's native Select All. Note this uses `ownsSelectAll`, not
            // the bare-key `isEditing` — reading a message must not turn
            // "select the message" into "check every thread".
            if mods == .command,
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "a",
               event.window == NSApp.mainWindow,
               !store.showCommandPalette,
               !store.showLabelPicker,
               !store.showShortcutsHelp,
               store.editingView == nil,
               ComposeKeyOwnership.allowsMailboxKeys(
                   hasRequest: store.composeRequest != nil,
                   minimized: store.composeMinimized,
                   finishing: store.composeFinishing),
               !TextFocus.ownsSelectAll(event.window?.firstResponder) {
                store.checkAllVisibleThreads()
                return nil
            }
            // ⌘L copies a gmail.com conversation URL for the focused
            // thread. Yield to typing in
            // search/compose/Settings (`isEditing`), but fire while reading
            // the conversation — unlike ⌘A, ⌘L is not a text-system chord.
            if mods == .command,
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers?.lowercased() == "l",
               event.window == NSApp.mainWindow,
               !store.showCommandPalette,
               !store.showLabelPicker,
               !store.showShortcutsHelp,
               store.editingView == nil,
               ComposeKeyOwnership.allowsMailboxKeys(
                   hasRequest: store.composeRequest != nil,
                   minimized: store.composeMinimized,
                   finishing: store.composeFinishing),
               !TextFocus.isEditing(event.window?.firstResponder),
               let thread = store.selectedThread {
                store.copyThreadLink(thread)
                return nil
            }
            if store.showCommandPalette, event.keyCode == 53 {  // esc
                store.mailboxOverlay = nil
                return nil
            }
            if store.showShortcutsHelp, event.keyCode == 53 {  // esc
                store.showShortcutsHelp = false
                return nil
            }
            // While the help sheet is up, ? still closes it, but no other bare
            // key may fall through to mail actions on the background selection.
            if store.showShortcutsHelp {
                if event.charactersIgnoringModifiers == "?" {
                    store.showShortcutsHelp = false
                    return nil
                }
                return event
            }
            if store.showLabelPicker {
                let picker = store.labelPicker
                // The "Create new" sheet on top is covered by the sheet
                // rule at the top of the monitor.
                switch event.keyCode {
                case 53:  // esc
                    store.mailboxOverlay = nil
                    return nil
                case 125:  // down — picker clamps to the filtered list
                    picker.highlight += 1
                    picker.navigated = true
                    return nil
                case 126:  // up
                    picker.highlight = max(picker.highlight - 1, 0)
                    picker.navigated = true
                    return nil
                case 36, 76:  // return / keypad enter: apply and close (or create)
                    // Handled here, not by the text field's onSubmit — before
                    // the field wins focus, Return would otherwise be eaten
                    // by the default branch below (it's a control character,
                    // so it neither deletes nor appends).
                    // A held Return must not fire again (several creates) or
                    // reach the list once the picker is gone.
                    if event.isARepeat { return nil }
                    store.labelPickerActivateHighlighted(closeAfterApply: true)
                    return nil
                case 49 where picker.navigated:  // space after arrows: toggle, stay open
                    store.labelPickerActivateHighlighted(closeAfterApply: false)
                    return nil
                default:
                    // If the picker's text field hasn't grabbed focus yet (it
                    // can lose the race right after opening), typed characters
                    // would fall through to the thread list's type-select.
                    // Route them into the filter query instead.
                    if mods.isEmpty, !(event.window?.firstResponder is NSTextView) {
                        if event.keyCode == 51 {  // delete
                            if !picker.query.isEmpty { picker.query.removeLast() }
                        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
                                  !chars.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                            picker.query += chars
                        }
                        return nil
                    }
                }
            }
            // Search dropdown open: ↑/↓/Enter drive the panel directly, so
            // `/` → arrows → Enter works without ever leaving the keyboard.
            // Intercepted here so the text field never sees them. Main window
            // only — Settings keeps its own arrows/Enter even while the
            // search field technically still holds main-window focus.
            if store.searchActive, mods.isEmpty, event.window == NSApp.mainWindow {
                switch event.keyCode {
                case 125:  // down — panel clamps to its rows
                    store.searchHighlight += 1
                    return nil
                case 126:  // up
                    store.searchHighlight = max(store.searchHighlight - 1, 0)
                    return nil
                case 36:   // return — run the highlighted row
                    store.searchActivateToken += 1
                    return nil
                default:
                    break
                }
            }
            // Esc: first press while typing (e.g. in search) drops focus back
            // to the list; otherwise it closes the reading pane
            // but KEEPS the selection, so you stay where you are.
            // Expanded compose / view editor keep their own Esc behavior;
            // minimized / mid-finish compose does not block Esc.
            if event.keyCode == 53,
               ComposeKeyOwnership.allowsMailboxKeys(
                   hasRequest: store.composeRequest != nil,
                   minimized: store.composeMinimized,
                   finishing: store.composeFinishing),
               store.editingView == nil {
                // The global monitor also fires for the Settings window. There,
                // Esc should close Settings and return to the mailbox — not
                // toggle the main window's reading pane. Drop text-field focus
                // first so an in-progress edit commits before the window closes.
                if let window = event.window,
                   window.identifier?.rawValue.contains("Settings") == true {
                    if window.firstResponder is NSTextView
                        || window.firstResponder is NSTextField {
                        window.makeFirstResponder(nil)
                        return nil
                    }
                    window.close()
                    return nil
                }
                // Editable only: selectable conversation text holding focus
                // must not turn the first Esc into a blur, or leaving a
                // full-window conversation would cost two presses.
                if TextFocus.isEditing(event.window?.firstResponder) {
                    event.window?.makeFirstResponder(nil)
                    // Drop the `/` panel immediately on Esc (don't wait for
                    // the deferred blur dismiss used by mouse clicks).
                    if store.searchActive { store.dismissSearchPanel() }
                    return nil
                }
                // Panel still up after the field already blurred (click-away
                // grace window) — next Esc closes it.
                if store.searchActive {
                    store.dismissSearchPanel()
                    return nil
                }
                // Clear multi-select checks first (Gmail-style Esc ladder).
                if !store.checkedThreadIds.isEmpty {
                    store.clearCheckedThreads()
                    return nil
                }
                // Exit full-app conversation before collapsing the pane.
                if store.threadFocusMode {
                    store.threadFocusMode = false
                    return nil
                }
                // Next Esc drops an active search back to the plain inbox
                // (so from the search field, Esc-Esc gets you home).
                if !store.committedSearch.isEmpty || !store.searchText.isEmpty {
                    store.clearSearch()
                    return nil
                }
                if layoutMode == .compactDetail {
                    store.clearSelection()
                    return nil
                }
                if !fullWindowThreads, !readingPaneHidden {
                    readingPaneHidden = true
                    return nil
                }
            }
            let finishingCompose = store.composeFinishing
            let textEditing = TextFocus.isEditing(event.window?.firstResponder)
            // A window other than the main one (e.g. Settings) being key
            // must not let these shortcuts act on the invisible main-window
            // thread list behind it, and no single key fires while an
            // editable field owns the keyboard (MailboxKeyGate).
            guard MailboxKeyGate.allowsSingleKeys(.init(
                unmodified: mods.isEmpty,
                isMainWindow: event.window == NSApp.mainWindow,
                commandPaletteOpen: store.showCommandPalette,
                labelPickerOpen: store.showLabelPicker,
                viewEditorOpen: store.editingView != nil,
                hasComposeRequest: store.composeRequest != nil,
                composeMinimized: store.composeMinimized,
                composeFinishing: finishingCompose,
                textEditing: textEditing))
            else { return event }
            // After the guards: mid-finish with a lagging body focus — resign
            // so the key is not also typed into a finishing draft.
            if finishingCompose, textEditing {
                event.window?.makeFirstResponder(nil)
            }
            // After `g` or `*`, the next key belongs to the sequence whatever
            // it is: ahead of `/`, the arrows and the Shift chords, so `* u`
            // typed with Shift still down selects unread instead of marking
            // the focused conversation unread, and `g` then an unknown key
            // is eaten rather than run (ShortcutKeyRouter).
            if store.hasPendingShortcutPrefix,
               let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                _ = store.handleKey(chars)
                return nil
            }
            // Gmail's `/`: jump focus to the search field.
            if event.charactersIgnoringModifiers == "/" {
                revealSearch()
                return nil
            }
            // Arrow keys: ↑/↓ browse the list without opening the pane
            // (Enter or a click opens the selected thread); ←/→ hide/show
            // the sidebar. Ask AI owns ↑/↓ for scrolling while it is on
            // screen — the mailbox key would otherwise open the next email.
            switch event.keyCode {
            case 123:  // left — collapse the sidebar
                withAnimation { sidebarHidden = true }
                return nil
            case 124:  // right — reveal the sidebar
                withAnimation { sidebarHidden = false }
                return nil
            case 125:  // down (⇧↓ extends the multi-select range)
                browseKeyIsRepeat = event.isARepeat
                if event.modifierFlags.contains(.shift) {
                    store.extendSelection(1)
                } else if askAIVisible(in: event.window),
                          scrollPane(in: event.window, up: false, page: false) {
                    return nil
                } else {
                    store.moveSelection(1, intent: .browse)
                }
                return nil
            case 126:  // up (⇧↑ extends the multi-select range)
                browseKeyIsRepeat = event.isARepeat
                if event.modifierFlags.contains(.shift) {
                    store.extendSelection(-1)
                } else if askAIVisible(in: event.window),
                          scrollPane(in: event.window, up: true, page: false) {
                    return nil
                } else {
                    store.moveSelection(-1, intent: .browse)
                }
                return nil
            case 36:   // return (Gmail's other open key is the rebindable `o`)
                // Not on auto-repeat: a Return held through the label picker
                // would otherwise open the conversation when it closes.
                if event.isARepeat { return nil }
                openSelectedFromKeyboard()
                return nil
            case 115:  // home — first conversation
                browseKeyIsRepeat = false
                store.jumpSelection(toEnd: false)
                return nil
            case 119:  // end — last conversation
                browseKeyIsRepeat = false
                store.jumpSelection(toEnd: true)
                return nil
            case 49:   // space — page the reading pane (⇧ pages up); with
                       // no open conversation it opens the selection (Gmail).
                if store.openedThreadId != nil, !effectivePaneHidden,
                   pageReadingPane(in: event.window,
                                   up: event.modifierFlags.contains(.shift)) {
                    return nil
                }
                if !event.modifierFlags.contains(.shift),
                   let thread = store.selectedThread,
                   !store.isDraftOnly(thread) {
                    detailSelectionTask?.cancel()
                    store.openDetail(thread.id)
                    if fullWindowThreads {
                        store.threadFocusMode = true
                    } else {
                        readingPaneHidden = false
                    }
                }
                return nil
            default:
                break
            }
            guard let chars = event.charactersIgnoringModifiers else { return event }
            // Gmail Shift+I / Shift+U mark read / unread, Shift+N refreshes.
            // Fixed chords (not in KeyBindings): charactersIgnoringModifiers
            // keeps Shift on letters ("I"/"U"/"N"), so they must be handled
            // before the single-key lookup lowercases them. Drop auto-repeat:
            // a held chord must not fire again on every repeat.
            let shiftOnly = event.modifierFlags
                .intersection([.command, .option, .control, .shift]) == [.shift]
            if let chord = GmailMarkReadKeys.chord(key: chars, shiftOnly: shiftOnly) {
                if !event.isARepeat {
                    store.applyGmailMarkReadChord(chord)
                }
                return nil
            }
            if GmailRefreshKey.matches(key: chars, shiftOnly: shiftOnly) {
                if !event.isARepeat {
                    Task { await store.syncAll() }
                }
                return nil
            }
            // Shift + the next/prev browse keys (j/k by default) extends the
            // multi-select range, matching ⇧↑/⇧↓. Checked before handleKey:
            // letter normalization there would otherwise treat ⇧J as plain j.
            // Letters only: a next/prev rebind to a symbol key (e.g. "!")
            // already needs Shift to type, and must keep plain navigation.
            if shiftOnly, chars.rangeOfCharacter(from: .letters) != nil,
               let command = store.keyBindings.command(for: chars),
               command == .next || command == .prev {
                browseKeyIsRepeat = event.isARepeat
                store.extendSelection(command == .next ? 1 : -1)
                return nil
            }
            // j/k (and other rebindable browse keys) also auto-repeat; pass
            // through so held navigation coalesces like ↑/↓.
            browseKeyIsRepeat = event.isARepeat
            // A held `m` or `v` must not toggle mute back and forth or reopen
            // the picker on every repeat.
            if event.isARepeat, !store.hasPendingShortcutPrefix,
               let command = store.keyBindings.command(for: chars),
               command.ignoresAutoRepeat {
                return nil
            }
            if store.handleKey(chars) { return nil }
            // Unhandled printable keys must not fall through: SwiftUI List
            // type-selects to the first row starting with that letter, which
            // fights Gmail-style single-key bindings on random taps.
            if !chars.isEmpty,
               !chars.unicodeScalars.contains(where: {
                   CharacterSet.controlCharacters.contains($0)
               }) {
                return nil
            }
            return event
        }
    }

    /// Return / Gmail `o`: open the focused conversation (a draft-only
    /// thread opens its draft in compose instead).
    private func openSelectedFromKeyboard() {
        guard let thread = store.selectedThread else { return }
        if store.isDraftOnly(thread) {
            store.editDraft(inThread: thread)
            store.clearSelection()
            return
        }
        detailSelectionTask?.cancel()
        store.openDetail(thread.id)
        if fullWindowThreads {
            store.threadFocusMode = true
        } else {
            readingPaneHidden = false
        }
    }

    /// Gmail `u`: back to the conversation list. The selection stays on the
    /// conversation just read, so j/k carry on from it (Gmail keeps its
    /// cursor). In a narrow window only the mounted conversation closes.
    private func backToList() {
        switch BackToList.action(layoutMode: layoutMode,
                                 threadFocus: store.threadFocusMode) {
        case .exitThreadFocus: store.threadFocusMode = false
        case .closeConversation:
            detailSelectionTask?.cancel()
            store.openDetail(nil)
        case .stay: break
        }
    }

    /// Page the reading pane one viewport (minus a reading overlap) for
    /// Space / Shift+Space. Returns false when there is nothing to scroll
    /// (short conversation, or already at the edge).
    private func pageReadingPane(in window: NSWindow?, up: Bool) -> Bool {
        scrollPane(in: window, up: up, page: true)
    }

    /// Ask AI is actually on screen (wide enough host + toggled on).
    /// Live from the event window so the key monitor does not stale-capture
    /// the last GeometryReader width.
    private func askAIVisible(in window: NSWindow?) -> Bool {
        AskAILayout.showsPanel(
            hostWidth: window?.contentView?.bounds.width ?? 0,
            enabled: store.showAskAI && AIFeatures.isEnabled)
    }

    /// Scroll the rightmost non-list pane (Ask AI when it is up, else the
    /// conversation). `page` is Space; otherwise one arrow-key line.
    private func scrollPane(in window: NSWindow?, up: Bool, page: Bool) -> Bool {
        guard let scrollView = Self.readingPaneScrollView(in: window) else {
            return false
        }
        let clip = scrollView.contentView
        let contentHeight = Double(scrollView.documentView?.frame.height ?? 0)
        let target = page
            ? ReadingPaneSpaceScroll.pageTarget(
                current: clip.bounds.origin.y,
                viewportHeight: clip.bounds.height,
                contentHeight: contentHeight,
                up: up)
            : ReadingPaneSpaceScroll.lineTarget(
                current: clip.bounds.origin.y,
                viewportHeight: clip.bounds.height,
                contentHeight: contentHeight,
                up: up)
        guard let target else { return false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = page ? 0.18 : 0.08
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(
                NSPoint(x: clip.bounds.origin.x, y: target))
            scrollView.reflectScrolledClipView(clip)
        }
        return true
    }

    /// The conversation pane's vertical NSScrollView: the rightmost
    /// scrollable scroll view that is not a List/table (thread list and
    /// sidebar are NSTableViews) and not inside a text view.
    private static func readingPaneScrollView(in window: NSWindow?)
        -> NSScrollView? {
        guard let root = window?.contentView else { return nil }
        var candidates: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView {
                let doc = scroll.documentView
                let isText = doc is NSTableView || doc is NSTextView
                let scrollable = (doc?.frame.height ?? 0)
                    > scroll.contentView.bounds.height + 1
                if !isText, scrollable, scroll.frame.height > 200 {
                    candidates.append(scroll)
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(root)
        return candidates.max {
            $0.convert($0.bounds.origin, to: nil).x
                < $1.convert($1.bounds.origin, to: nil).x
        }
    }

    /// Open from a mouse click — immediately, no debounce. Also serves
    /// re-clicks on the already-selected row (openSelectedToken), where the
    /// List selection binding never fires. Non-navigation intents
    /// (auto-advance, restore-focus) swap the mounted detail but never
    /// redirect drafts to compose or reveal a pane the user hid.
    private func openClickedThread(_ selectedId: String,
                                   intent: ThreadSelectionIntent = .click) {
        detailSelectionTask?.cancel()
        store.openDetail(selectedId)
        if intent.redirectsDraftToCompose,
           let thread = store.selectedThread,
           store.isDraftOnly(thread) {
            store.editDraft(inThread: thread)
            store.clearSelection()
            return
        }
        guard intent.revealsReadingPane else { return }
        if fullWindowThreads {
            store.threadFocusMode = true
        } else {
            readingPaneHidden = false
        }
    }

    /// Open the detail pane for a browse selection. Single keypresses open with
    /// no delay; auto-repeating keys coalesce through a short settle. A newer
    /// selection cancels in-flight work so only the latest id opens.
    private func scheduleDetailSelection(_ id: String) {
        detailSelectionTask?.cancel()
        let settle = DetailOpenPolicy.settleNanoseconds(
            isKeyRepeat: browseKeyIsRepeat,
            keyRepeatInterval: NSEvent.keyRepeatInterval)
        // Consume the repeat flag: every browse keypress re-arms it before
        // moveSelection, but a mouse click or programmatic selection after a
        // held-key burst must not inherit the burst's settle delay.
        browseKeyIsRepeat = false
        detailSelectionTask = Task { @MainActor in
            if settle > 0 {
                do {
                    try await Task.sleep(nanoseconds: settle)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            guard store.selectedThreadId == id else { return }
            store.openDetail(id)
        }
    }
}

struct Sidebar: View {
    @Environment(MailStore.self) var store
    @Environment(\.mailAccent) private var accent
    /// `@Environment` has no projected value, so controls that need two-way
    /// access to the store go through this instead of `$store`.
    private var bound: Bindable<MailStore> { Bindable(store) }
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var viewToDelete: SavedView?
    /// Shared with the icon strip (`ContentView` owns it).
    @Environment(SidebarDisclosureModel.self) private var disclosure
    @State private var newLabel: NewLabelRequest?
    @AppStorage(SidebarDensity.storageKey) private var sidebarDensityRaw =
        SidebarDensity.comfortable.rawValue
    private var sidebarDensity: SidebarDensity { .from(raw: sidebarDensityRaw) }

    private var confirmingViewDeleteShown: Binding<Bool> {
        Binding(
            get: { viewToDelete != nil },
            set: { if !$0 { viewToDelete = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: compose. (Search lives in the list column's top bar.)
            HStack(spacing: 6) {
                // The account switcher lives in the rail (AccountRail).
                Spacer(minLength: 0)
                Button {
                    store.openCompose(.init(replyTo: nil))
                } label: {
                    // Monochrome like the sidebar glyphs: a borderless
                    // button would otherwise take the accent colour.
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
                .help("Compose (⌘N or \(store.keyBindings.displayKey(for: .compose)))")
                .accessibilityLabel("Compose")
                .accessibilityIdentifier("composeButton")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            List(selection: bound.selectedView) {
                // Gmail's system views, in Gmail's order unless dragged.
                Section {
                    ForEach(systemRows, id: \.self) { id in
                        systemRow(id)
                            .moveDisabled(id == SidebarSystemOrder.moreId)
                            .contextMenu {
                                Button("Reset Sidebar Order") {
                                    disclosure.setSystemOrder(nil, orderScope)
                                }
                                .disabled(disclosure.systemOrder(orderScope) == nil)
                            }
                    }
                    .onMove { from, to in
                        let moved = SidebarSystemOrder.move(
                            systemOrder, rows: systemRows, from: from, to: to)
                        if moved != systemOrder { disclosure.setSystemOrder(moved, orderScope) }
                    }
                }
                Section {
                    labelTrees
                } header: {
                    HStack {
                        Text("Labels")
                        Spacer()
                        Button {
                            newLabel = NewLabelRequest(
                                accountId: store.activeAccountId
                                    ?? (store.accounts.count == 1 ? store.accounts.first?.id : nil))
                        } label: {
                            // Gmail's "+": the glyph of the "Add view" row
                            // below (same style), in the neutral sidebar ink.
                            Image(systemName: "plus")
                                .mailIconStyle(selected: false)
                                // Layout height of a header line (the glyph
                                // may overflow it). No hit area outside the
                                // frame: one padded past it reached the label
                                // row below and covered its "⋮" in the UI test.
                                .frame(height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Create new label")
                        .accessibilityLabel("Create new label")
                        .accessibilityIdentifier("sidebar.labels.add")
                    }
                }
                Section("Views") {
                    ForEach(store.visibleSavedViews) { view in
                        sidebarItem(.saved(view.id ?? -1, view.name))
                            .contextMenu {
                                Button("Edit View…") { store.editingView = view }
                                Button("Delete View", role: .destructive) {
                                    viewToDelete = view
                                }
                            }
                    }
                    Button {
                        store.editingView = SavedView.empty()
                    } label: {
                        Label {
                            Text("Add view").mailRowFont()
                        } icon: {
                            Image(systemName: "plus")
                                .mailIconStyle(selected: false)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            // View ▸ Reset Sidebar Order: the sidebar being shown.
            .onChange(of: store.sidebarOrderResetToken) {
                disclosure.setSystemOrder(nil, orderScope)
            }
            .environment(\.defaultMinListRowHeight, sidebarDensity.minRowHeight)
            .modifier(SidebarListDensity(density: sidebarDensity))
            .scrollContentBackground(.hidden)
            // No scroller gutter beside the rows: the selection band reaches
            // the column's trailing edge. The list still scrolls by wheel,
            // trackpad and keyboard.
            .scrollIndicators(.never)
            // The list spans the column edge to edge: macOS 26 insets a
            // sidebar list by its safe area (CI: column x 64-313, list scroll
            // view x 72-312), and no row background can paint outside it.
            .ignoresSafeArea(.container, edges: .horizontal)

            Divider()
            if store.demoMode {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 12))
                    Text("Demo inbox")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button("Exit") { store.exitDemoMode() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("exitDemoInbox")
                }
                .padding(.horizontal, 12).padding(.top, 8)
                .help("Fictional mail only — Gmail sync and sending are disabled")
            }
            if let release = updates.available {
                Button {
                    updates.openUpdate()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        // Says "restart" up front: from here one click on a
                        // sidebar row installs and relaunches the app.
                        Text("Update to \(release.version) and restart")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.top, 8)
                .disabled(updates.activity != .idle)
                .help("Install DreaMail \(release.version) and relaunch")
            }
            // Settings moved to the account rail (AccountRail).
            Color.clear.frame(height: 8)
        }
        .background {
            // The selected row's band across the column, behind the list.
            ZStack {
                Color.mailSidebar
                // Into the column's safe-area margin like the colour above it
                // (CI, macOS 26.7.2: the column starts at x 64, the list at 72).
                SidebarSelectionBand(accent: accent)
                    .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        .background(HorizontalEdgeReader { store.sidebarTrailingEdge = $0 })
        .sheet(item: $newLabel) { request in
            NewLabelSheet(request: request)
        }
        .modifier(LabelMenuPresentation())
        .confirmationDialog(
            "Delete saved view?",
            isPresented: confirmingViewDeleteShown,
            presenting: viewToDelete
        ) { view in
            Button("Delete View", role: .destructive) {
                store.deleteView(view)
                viewToDelete = nil
            }
            Button("Cancel", role: .cancel) { viewToDelete = nil }
        } message: { view in
            Text("Delete \(view.name)? Its saved filters will be removed from this Mac.")
        }
    }


    /// Order, rows and counts of the system views, shared with the icon
    /// strip (`SidebarIconStrip`) so both list the same views.
    private var system: SidebarSystemRows { SidebarSystemRows(store: store, disclosure: disclosure) }
    private var orderScope: SidebarSystemOrder.Scope { system.scope }
    private var systemOrder: [String] { system.order }
    private var systemRows: [String] { system.rows }

    @ViewBuilder private func systemRow(_ id: String) -> some View {
        if id == SidebarSystemOrder.moreId {
            SidebarMoreToggle(open: disclosure.moreOpen, identifier: "sidebar.more") {
                disclosure.moreOpen.toggle()
            }
        } else if let view = SidebarSystemOrder.view(for: id) {
            sidebarItem(view, badge: system.badge(view))
        }
    }

    /// The labels of the account in scope; with every account in scope, one
    /// collapsible tree per account under its name and colored dot.
    @ViewBuilder private var labelTrees: some View {
        let onNewLabel: (NewLabelRequest) -> Void = { newLabel = $0 }
        if let account = store.activeAccountId {
            SidebarLabelTreeView(accountId: account, disclosure: disclosure,
                                 onNewLabel: onNewLabel)
        } else if store.accounts.count == 1, let only = store.accounts.first {
            SidebarLabelTreeView(accountId: only.id, disclosure: disclosure,
                                 onNewLabel: onNewLabel)
        } else {
            ForEach(store.accounts) { account in
                DisclosureGroup(isExpanded: Binding(
                    get: { disclosure.accountOpen(account.id) },
                    set: { disclosure.setAccountOpen(account.id, $0) })
                ) {
                    SidebarLabelTreeView(accountId: account.id, disclosure: disclosure,
                                         onNewLabel: onNewLabel)
                } label: {
                    SidebarAccountHeader(account: account)
                }
            }
        }
    }

    /// Sidebar row, Gmail-style: a monochrome outline glyph; the selected row
    /// gets the filled glyph, a darker tint and a bold title.
    private func sidebarItem(_ view: MailboxView, badge: Int? = nil) -> some View {
        // List(selection:) only fires onChange when the value *changes*, so
        // re-clicking the already-selected row (e.g. Inbox while a committed
        // `/` search is active) would otherwise be a no-op — same shape as the
        // original gi bug. Only install the reselect gesture for hit-testing
        // when this row is already selected (GestureMask.subviews otherwise):
        // a permanent TapGesture on every row steals List selection on macOS
        // (same class as ThreadListView's selected-only open overlay). Keep
        // one view identity (no if/else branch) so selection flips don't
        // rebuild the row. `.tag` stays outermost so List(selection:) sees it.
        let reselect = ListReselectPolicy.mountsHandler(
            row: view, selected: store.selectedView)
        let selected = store.selectedView == view
        // Explicit icon and title styles: the sidebar list style would
        // otherwise draw the glyph large and light, and tint the selected
        // row's glyph with the accent (see `mailIcon`, `MailIconMetrics`).
        return Label {
            Text(view.title)
                .fontWeight(selected ? .semibold : .regular)
                .mailRowTitleStyle()
        } icon: {
            Image(systemName: view.icon(selected: selected))
                .mailIconStyle(selected: selected)
        }
        .listItemTint(.monochrome)
        .modifier(SidebarCount(count: badge ?? 0, selected: selected,
                               painted: accent.paintsSelection || (selected && accent.keepsSelectionColor)))
        .environment(\.sidebarRowSelected, selected)
        .accessibilityIdentifier(sidebarAccessibilityID(for: view))
        // The selection band in the custom accent (`AccentSelectionBackground`).
        .listRowBackground(AccentSelectionBackground.sidebar(selected: selected, accent: accent))
        .simultaneousGesture(
            TapGesture().onEnded { store.goTo(view) },
            including: reselect ? .gesture : .subviews)
        .tag(view)
    }

    /// Stable id for UI tests / a11y (e.g. `sidebar.inbox`, `sidebar.sent`).
    private func sidebarAccessibilityID(for view: MailboxView) -> String {
        switch view {
        case .account(let email): return "sidebar.account.\(email)"
        case .scheduled: return "sidebar.scheduled"
        case .outbox: return "sidebar.outbox"
        case .saved(let id, _): return "sidebar.saved.\(id)"
        case .label(let account, let labelId, _):
            return "sidebar.label.\(account).\(labelId)"
        default:
            if let key = view.prefsKey { return "sidebar.\(key)" }
            return "sidebar.\(view.title)"
        }
    }
}


/// A sidebar row's count, hidden at zero. Without a painted selection it
/// is exactly the old `.badge(Int)`; on a selection the app paints the
/// number takes the selection ink (`SidebarBadgeStyle`).
struct SidebarCount: ViewModifier {
    let count: Int
    let selected: Bool
    let painted: Bool

    @Environment(\.mailRowSizeOverride) private var sizeOverride

    /// The count as `Text` (`badge` takes one); in a Compact sidebar it keeps
    /// the font of the user's own row size.
    private var countText: Text {
        let text = Text("\(count)")
        guard let size = sizeOverride else { return text }
        return text.font(.system(size: MailIconMetrics(rowSize: size).pointSize))
    }

    func body(content: Content) -> some View {
        if painted {
            content.badge(count > 0 ? countText.foregroundStyle(SidebarBadgeStyle(selected: selected)) : nil)
        } else if sizeOverride != nil {
            content.badge(count > 0 ? countText : nil)
        } else {
            content.badge(count)
        }
    }
}

/// Measures the panel's natural content height so the floating panel can hug
/// its rows (instead of ScrollView greedily claiming its full max height and
/// leaving dead space below the last row).
private struct SearchPanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Command-K-style search results panel. Floats under the field in the list
/// column's top bar (see `ListSearchToolbar`), over the message list. Shows recent searches when the query is
/// empty; otherwise a "View all results" row plus Contacts and Threads.
/// ↑/↓/Enter come in from the global key monitor via searchHighlight /
/// searchActivateToken, so the flow is fully keyboard-driven after `/`.
struct SearchResultsPanel: View {
    @Environment(\.mailAccent) private var accent
    @Environment(MailStore.self) var store
    // Live thread matches; refreshed as the query changes.
    @State private var threadPreview: [MailThread] = []
    // Contact matches for the current query — @State so we filter once per
    // keystroke, not on every SwiftUI body/layout pass (was a major / jank source).
    @State private var contactPreview: [MailStore.Contact] = []
    // Natural content height, so the panel caps+scrolls at 460 but otherwise
    // shrinks to fit. Defaults to the cap so the first frame isn't collapsed.
    @State private var contentHeight: CGFloat = 460
    // Debounced, off-main FTS lookup for the live preview.
    @State private var previewTask: Task<Void, Never>?

    /// Everything the highlight can land on, in display order.
    private enum Row {
        case viewAll
        case contact(MailStore.Contact)
        case thread(MailThread)
        case recent(String)
    }

    private var trimmedSearch: String {
        store.searchText.trimmingCharacters(in: .whitespaces)
    }

    private var visibleRecentSearches: [String] {
        guard !trimmedSearch.isEmpty else { return store.recentSearches }
        return store.recentSearches.filter {
            $0.range(of: trimmedSearch, options: .caseInsensitive) != nil
                && $0.caseInsensitiveCompare(trimmedSearch) != .orderedSame
        }
    }

    /// Contacts shown in the panel: matches while typing, top senders when the
    /// query is empty (so `/` opens a full panel immediately).
    private var shownContacts: [MailStore.Contact] {
        trimmedSearch.isEmpty ? Array(store.contacts.prefix(3)) : contactPreview
    }

    private var rows: [Row] {
        let base = trimmedSearch.isEmpty
            ? visibleRecentSearches.map { Row.recent($0) }
            : [Row.viewAll]
        return base
            + shownContacts.map { .contact($0) }
            + threadPreview.map { .thread($0) }
    }

    /// Index where the Contacts section starts (recents or view-all precede it).
    private var contactsStart: Int {
        trimmedSearch.isEmpty ? visibleRecentSearches.count : 1
    }

    /// The store's raw highlight, clamped to what's actually on screen.
    private var highlight: Int { min(store.searchHighlight, max(rows.count - 1, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if trimmedSearch.isEmpty {
                            recentsSection
                        } else {
                            viewAllResultsRow(index: 0).id(0)
                        }
                        if !shownContacts.isEmpty {
                            sectionHeader("Contacts")
                            ForEach(Array(shownContacts.enumerated()), id: \.element.id) { i, contact in
                                contactRow(contact, index: contactsStart + i).id(contactsStart + i)
                            }
                        }
                        if !threadPreview.isEmpty {
                            sectionHeader("Threads")
                            ForEach(Array(threadPreview.enumerated()), id: \.element.id) { i, thread in
                                threadRow(thread, index: contactsStart + shownContacts.count + i)
                                    .id(contactsStart + shownContacts.count + i)
                            }
                        }
                        if !trimmedSearch.isEmpty, shownContacts.isEmpty, threadPreview.isEmpty {
                            Text("No contacts or threads match")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                    }
                    .padding(.vertical, 5)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: SearchPanelContentHeightKey.self,
                                               value: geo.size.height)
                    })
                }
                // Hug the content, but cap (and scroll) at 460.
                .frame(height: min(contentHeight, 460))
                .onPreferenceChange(SearchPanelContentHeightKey.self) { contentHeight = $0 }
                // Keyboard highlight: clamp over-scrolled ↓ presses back to the
                // last row (like LabelPicker) and keep the row visible.
                .onChange(of: store.searchHighlight) {
                    if store.searchHighlight >= rows.count {
                        store.searchHighlight = max(rows.count - 1, 0)
                    }
                    proxy.scrollTo(highlight)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PMRadius.md + 2))
        .pmCardElevation(cornerRadius: PMRadius.md + 2, intense: true)
        .onAppear {
            store.searchHighlight = 0
            refreshThreadPreview()
        }
        .onDisappear { previewTask?.cancel() }
        .onChange(of: store.searchText) {
            store.searchHighlight = 0
            refreshThreadPreview()
        }
        // Contact mining can finish after the panel opened with a typed query;
        // re-filter so matches aren't stuck empty until the next keystroke.
        .onChange(of: store.contacts) {
            guard !trimmedSearch.isEmpty else { return }
            contactPreview = store.contactSuggestions(for: trimmedSearch)
        }
        // The empty-query "latest threads" must track the list (it can reload
        // right after ✕ clears a committed search, in either observer order).
        .onChange(of: store.threads) { if trimmedSearch.isEmpty { refreshThreadPreview() } }
        // Enter from the key monitor: run whatever is highlighted.
        .onChange(of: store.searchActivateToken) { activate(rows[safe: highlight]) }
    }

    private func activate(_ row: Row?) {
        switch row {
        case .viewAll:
            runFullSearch(store.searchText)
        case .contact(let contact):
            runFullSearch("from:\(contact.email)")
        case .thread(let thread):
            openThread(thread)
        case .recent(let query):
            runFullSearch(query)
        case nil:
            // Nothing to act on (e.g. empty recents) — just close the panel.
            store.dismissSearchPanel()
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func rowBackground(_ index: Int) -> some View {
        (index == highlight ? accent.fill.opacity(0.18) : Color.clear)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold)).kerning(0.4)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
    }

    private func viewAllResultsRow(index: Int) -> some View {
        Button { runFullSearch(store.searchText) } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).frame(width: 20)
                Text("View all results")
                Text("\u{201C}\(trimmedSearch)\u{201D}")
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "return").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground(index))
        .onHover { if $0 { store.searchHighlight = index } }
    }

    private func contactRow(_ contact: MailStore.Contact, index: Int) -> some View {
        Button {
            // Jump to everything from this person.
            runFullSearch("from:\(contact.email)")
        } label: {
            HStack(spacing: 9) {
                avatar(for: contact.name.isEmpty ? contact.email : contact.name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.name.isEmpty ? contact.email : contact.name)
                        .font(.system(size: 13)).lineLimit(1)
                    if !contact.name.isEmpty {
                        Text(contact.email)
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground(index))
        .onHover { if $0 { store.searchHighlight = index } }
    }

    private func threadRow(_ thread: MailThread, index: Int) -> some View {
        Button { openThread(thread) } label: {
            HStack(spacing: 9) {
                Image(systemName: "envelope")
                    .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                        .font(.system(size: 13, weight: thread.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Text(thread.participants.isEmpty ? thread.snippet : thread.participants)
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground(index))
        .onHover { if $0 { store.searchHighlight = index } }
    }

    private func avatar(for label: String) -> some View {
        let initial = label.first.map { String($0).uppercased() } ?? "?"
        return Circle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 24, height: 24)
            .overlay(Text(initial).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary))
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visibleRecentSearches.isEmpty {
                // Nothing yet — the Contacts/Threads sections below still fill
                // the panel, so no placeholder needed beyond a search hint.
                Text("Search — from: to: subject: label: is:unread …")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                HStack {
                    Text("RECENT SEARCHES")
                        .font(.system(size: 10, weight: .semibold)).kerning(0.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { store.clearRecentSearches() }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundStyle(.secondary).help("Clear search history")
                }
                .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
                ForEach(Array(visibleRecentSearches.enumerated()), id: \.element) { i, query in
                    Button { runFullSearch(query) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20)
                            Text(query).font(.system(size: 13)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button { store.removeRecentSearch(query) } label: {
                                Image(systemName: "xmark").font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain).help("Remove from history")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(rowBackground(i))
                    .onHover { if $0 { store.searchHighlight = i } }
                    .id(i)
                }
                .padding(.bottom, 5)
            }
        }
    }

    private func openThread(_ thread: MailThread) {
        // Commit the query so the list shows matching results, then select
        // this thread (pinned into `threads` immediately so the reading pane
        // can resolve it while the async reload finishes).
        if !trimmedSearch.isEmpty { store.commitSearch(trimmedSearch) }
        store.openThread(thread)
        store.dismissSearchPanel()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Commit the search to the thread list and hand focus back to it.
    private func runFullSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        store.commitSearch(q)
        store.dismissSearchPanel()
        NSApp.keyWindow?.makeFirstResponder(nil)
        if store.selectedThreadId == nil { store.moveSelection(1) }
    }

    private func refreshThreadPreview() {
        previewTask?.cancel()
        let q = trimmedSearch
        // Empty query: latest threads from the current list, so `/` opens a
        // full panel right away — instant, straight from memory.
        if q.isEmpty {
            contactPreview = []
            threadPreview = Array(store.threads.prefix(4))
            return
        }
        // Contacts: in-memory, update immediately once per keystroke (not in
        // `body`). Threads: debounce, then FTS off the main thread. Keep the
        // previous thread rows until the new ones arrive (no flicker).
        contactPreview = store.contactSuggestions(for: q)
        // Short queries skip FTS (too broad); clear stale multi-char results.
        if q.count < ThreadTypeahead.minimumQueryLength {
            threadPreview = []
            return
        }
        previewTask = Task {
            // 80ms feels snappier than 120ms once the FTS path is a single
            // limited JOIN; still coalesces fast typists.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let matches = await store.threadSuggestions(for: q)
            guard !Task.isCancelled else { return }
            threadPreview = matches
        }
    }
}

/// Rename accounts ("Personal", "Fund", …) and color their avatar rings;
/// labels and colors are local only.
struct AccountLabelsEditor: View {
    @Environment(MailStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var labels: [String: String] = [:]
    @State private var senderNames: [String: String] = [:]
    /// Edited label colors by account: `#rrggbb`, or "" for the default.
    @State private var labelColors: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts")
                .font(.headline)
                .padding(.bottom, 10)
            Form {
                ForEach(store.accounts) { account in
                    Section(account.id) {
                        TextField("Label (only you see this)", text: .init(
                            get: { labels[account.id] ?? account.displayName },
                            set: { labels[account.id] = $0 }
                        ), prompt: Text("e.g. Personal"))
                        TextField("Send as (recipients see this)", text: .init(
                            get: { senderNames[account.id] ?? account.senderName },
                            set: { senderNames[account.id] = $0 }
                        ), prompt: Text("e.g. Jane Doe"))
                        .accessibilityIdentifier("accountSenderName.\(account.id)")
                        colorRows(account)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    for (id, label) in labels { store.renameAccount(id, label: label) }
                    for (id, name) in senderNames { store.setSenderName(id, name: name) }
                    for (id, hex) in labelColors {
                        store.setAccountLabelColor(id, hex: hex.isEmpty ? nil : hex)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 420)
        // The system color panel is shared and outlives the sheet: close it
        // on Save, Cancel or Esc so it does not linger over the app.
        .onDisappear { PickedColor.closeSharedPanel() }
    }

    /// The account's color as edited so far: `#rrggbb`, or nil for the default.
    private func editedColor(_ account: Account) -> String? {
        LabelRGB.normalizedHex(labelColors[account.id] ?? account.labelColor)
    }

    /// Label color: a preview of the ringed avatar and the system color
    /// picker, then the organizer's swatches for one-click choices and
    /// "Default". The ring always shows the color, so the rows are always
    /// enabled.
    @ViewBuilder
    private func colorRows(_ account: Account) -> some View {
        let chosen = editedColor(account)
        let shownHex = AccountLabelColor.resolvedHex(stored: chosen, accountId: account.id)
        HStack {
            Text("Label color")
            Spacer()
            AccountAvatarView(name: editedTitle(account), key: account.id, size: 35,
                              photo: store.accountPhotos[account.id],
                              ring: .init(storedHex: chosen, surface: .groupedForm))
                .accessibilityLabel("Label color preview")
                .accessibilityIdentifier("accountLabelColorPreview.\(account.id)")
            ColorPicker("Label color", selection: Binding(
                get: {
                    Color(nsColor: AccountLabelColor.nsColor(hex: chosen, accountId: account.id))
                },
                set: { color in
                    if let hex = PickedColor.pickedHex(color, shown: shownHex) {
                        labelColors[account.id] = hex
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .accessibilityLabel("Label color for \(account.id)")
            .accessibilityIdentifier("accountLabelColorPicker.\(account.id)")
        }
        HStack(spacing: 5) {
            ForEach(Color.labelPalette, id: \.hex) { swatch in
                ColorSwatch(name: swatch.name, hex: swatch.hex,
                            selected: chosen == LabelRGB.normalizedHex(swatch.hex),
                            accessibilityID: "accountLabelSwatch.\(account.id).\(swatch.name)") {
                    labelColors[account.id] = LabelRGB.normalizedHex(swatch.hex) ?? ""
                }
            }
            Spacer(minLength: 4)
            Button("Default") { labelColors[account.id] = "" }
                .controlSize(.small)
                .disabled(chosen == nil)
                .help("Use the account's default color")
                .accessibilityLabel("Default label color")
                .accessibilityIdentifier("accountLabelColorDefault.\(account.id)")
        }
    }

    /// The title with the edits so far, for the preview avatar's initial.
    private func editedTitle(_ account: Account) -> String {
        AccountLabelColor.title(displayName: labels[account.id] ?? account.displayName,
                                senderName: senderNames[account.id] ?? account.senderName,
                                accountId: account.id)
    }
}
