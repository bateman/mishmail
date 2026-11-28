import SwiftUI
import AppKit

/// The search field as a toolbar item of the list column: right of the view's
/// icon and title, with the results panel under it. A real toolbar item, so it
/// takes the mouse like any other. Applied to every list column (Inbox,
/// labels, saved views, All accounts, Scheduled, Outbox).
///
/// Not `.searchable`: programmatic focus is needed (macOS 14). The text field
/// is an AppKit `NSTextField`: `@FocusState` set from outside does not reach a
/// view hosted in a toolbar item (UI run: `/` focused nothing), while a mouse
/// click does. `/` and the icon strip's search button focus it by calling
/// `makeFirstResponder` on a token bump (`store.searchFocusToken`) or, when the
/// list was not mounted, when the field attaches to its window
/// (`store.searchFocusPending`).
///
/// The item is flexible (`ListHeaderLayout`: ideal 260 pt, 140-380 pt), and
/// bounded by the list column: a `.principal` item is sized to its ideal
/// width whatever the column's width, so the ideal is the room between the
/// field's left edge and the column's right edge (both measured in AppKit,
/// `HorizontalEdgeReader`). The field shrinks with the column and never
/// crosses into the reading pane; with less room than its minimum it is
/// hidden. `ListSearchFieldUITests` measures its width and the toolbar's
/// items at the window's minimum size and against the list/pane divider.
/// While a conversation fills the window (full-window style, centre peek)
/// the field is disabled: it must not take focus behind the peek's card
/// (`/` leaves the conversation first).
///
/// `trailingButtons` (the window's pane toggle and focus button, with the
/// list only): `.automatic` items of this column's toolbar go to the
/// window's trailing end when the list is the only column (where the field
/// itself went as `.automatic`), while the same buttons declared on the
/// window's root toolbar sat between the title and the field.
struct ListSearchToolbar<TrailingButtons: View>: ViewModifier {
    var trailingButtons: TrailingButtons? = nil
    @Environment(MailStore.self) private var store
    /// Window x of the field's left edge and of the list column's right edge.
    @State private var fieldMinX: CGFloat?
    @State private var columnMaxX: CGFloat?

    func body(content: Content) -> some View {
        let widths = ListHeaderLayout.fieldWidths(fieldMinX: fieldMinX, columnMaxX: columnMaxX)
        content
            .background(HorizontalEdgeReader { columnMaxX = $0 }.accessibilityHidden(true))
            // `.principal` + `.editor` role: the item sits in the column's title
            // region, after the title, above the list column. `.navigation`
            // pins to the window's leading edge on macOS 26 (over the sidebar),
            // `.automatic` to the trailing end of the window when the list is
            // the only column.
            .toolbarRole(.editor)
            .toolbar {
                // Shared glass hidden (macOS 26): the field is the one rounded
                // box, not a box inside the system capsule.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        // No room left of the column's edge (below the minimum):
                        // no field at all, not one across the divider. Hiding
                        // it in place was not enough: the box kept its content
                        // width (CI: 33 pt) and stayed exposed.
                        if widths.hidden {
                            Color.clear.frame(width: 0, height: 0)
                        } else {
                            ToolbarSearchField(
                                text: Bindable(store).searchText,
                                focusToken: store.searchFocusToken,
                                pendingFocus: { store.searchFocusPending && store.searchFocusStillWanted },
                                onFocusChange: { focused in
                                    // Drive the results panel from the field's focus. Blur
                                    // is deferred (see noteSearchFocused) so a click on a
                                    // result row can land before the panel is torn down.
                                    if focused { store.searchFocusPending = false }
                                    store.noteSearchFocused(focused)
                                },
                                onSubmit: {
                                    // Fallback path — with the dropdown open, Enter is handled
                                    // by the key monitor and routed to the panel instead.
                                    store.commitSearch(store.searchText)
                                    store.dismissSearchPanel()
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                    if store.selectedThreadId == nil { store.moveSelection(1) }
                                })
                            .frame(minWidth: widths.min, idealWidth: widths.ideal, maxWidth: widths.max)
                            // Measured only while shown: the last left edge is kept
                            // while hidden, so the field comes back when the
                            // column widens.
                            .background(HorizontalEdgeReader(edge: .leading) { fieldMinX = $0 }
                                .accessibilityHidden(true))
                            .layoutPriority(1)
                            .disabled(store.threadFocusMode)
                            .help("Search — from: to: subject: label: has:attachment is:unread is:starred after: before:")
                            // One element for the whole field box (its children keep their own).
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("listSearchBox")
                            // Unmounted while focused (layout switch): end the
                            // search-active state, or the key monitor keeps swallowing
                            // arrows and Enter.
                            .onDisappear { store.dismissSearchPanel() }
                        }
                    }
                }
                .pmHideSharedBackground()
                if let trailingButtons {
                    // Shared glass hidden too: with it, and the sidebar
                    // collapsed, macOS 26 drew the column's top edge over the
                    // whole title-bar row and the rail's band was gone
                    // (TopBandSeamUITests, CI run 46166175036).
                    ToolbarItemGroup(placement: .automatic) { trailingButtons }
                        .pmHideSharedBackground()
                }
            }
            // Command-K-style panel, floated over the top of the list column
            // under the field, at the column's leading edge (the field's
            // side), never wider than the column.
            .overlay(alignment: .topLeading) {
                if store.searchActive {
                    SearchResultsPanel()
                        .frame(maxWidth: 600, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("searchResultsPanel")
                        // Snappy fade in place — no slide-in; this app is fast.
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.06), value: store.searchActive)
    }
}

/// Same look as `SearchField` (magnifier, clear button, accent ring when
/// focused), around an AppKit text field that reports focus.
private struct ToolbarSearchField: View {
    @Binding var text: String
    let focusToken: Int
    let pendingFocus: () -> Bool
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    @State private var focused = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            SearchAppKitField(text: $text, focusToken: focusToken, pendingFocus: pendingFocus,
                              onFocusChange: { isFocused in
                                  focused = isFocused
                                  onFocusChange(isFocused)
                              },
                              onSubmit: onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        // Hit expands; layout stays icon-sized so the field doesn't jump.
                        .pmHitTarget(extra: 8)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Clear")
                .help("Clear")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, focused ? 7 : 5)
        .background(Color.primary.opacity(focused ? 0.09 : 0.06),
                    in: RoundedRectangle(cornerRadius: PMRadius.sm))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: PMRadius.sm)
                    .strokeBorder(.accentForeground.opacity(0.7), lineWidth: 1.5)
            }
        }
        .animation(.easeOut(duration: 0.08), value: focused)
    }
}

/// `NSTextField` that reports when it takes and loses the keyboard, and when
/// it joins a window (for a focus request made before it existed).
final class SearchNSTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var onMoveToWindow: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }
}

private struct SearchAppKitField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let pendingFocus: () -> Bool
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchNSTextField {
        let field = SearchNSTextField()
        field.placeholderString = "Search"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        field.onFocusChange = { [weak coordinator] focused in coordinator?.parent.onFocusChange(focused) }
        field.onMoveToWindow = { [weak coordinator, weak field] in
            guard let field, let coordinator, coordinator.parent.pendingFocus() else { return }
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        coordinator.lastToken = focusToken
        return field
    }

    func updateNSView(_ field: SearchNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = isEnabled
        if context.coordinator.lastToken != focusToken {
            context.coordinator.lastToken = focusToken
            DispatchQueue.main.async {
                if field.isEnabled { field.window?.makeFirstResponder(field) }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchAppKitField
        var lastToken = 0
        init(_ parent: SearchAppKitField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
