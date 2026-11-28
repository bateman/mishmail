import AppKit
import GRDB
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Disarms auto-pin on trackpad scroll. Offset observation (macOS 15+) is
/// preferred; scroll-wheel monitor covers macOS 14 and single-message threads
/// where `scrollPosition` id never changes.
private final class InlineScrollDisarmGate {
    var onUserScroll: (() -> Void)?
    private var wheelMonitor: Any?

    func setWheelArmed(_ armed: Bool) {
        if armed {
            guard wheelMonitor == nil else { return }
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                if abs(event.scrollingDeltaY) > 0.5 || abs(event.scrollingDeltaX) > 0.5 {
                    DispatchQueue.main.async { self?.onUserScroll?() }
                }
                return event
            }
        } else if let monitor = wheelMonitor {
            NSEvent.removeMonitor(monitor)
            wheelMonitor = nil
        }
    }

    deinit {
        if let monitor = wheelMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Scroll anchor for `.scrollPosition(id:)`, held outside plain `@State`.
/// The binding's setter fires every time a message card crosses the top of
/// the viewport while the user scrolls. As `@State`, each of those writes
/// invalidated the entire (eager) thread body — on a thread with many replies
/// that re-diffed every message card per crossing and made scrolling stutter.
/// As an `@Observable` box, user-scroll writes only touch the scroll-position
/// machinery that reads it; programmatic moves also go through
/// `ScrollViewProxy.scrollTo` explicitly.
@Observable
private final class ThreadScrollAnchor {
    var id: String?

    init(id: String? = nil) {
        self.id = id
    }
}

struct ThreadDetailView: View {
    @Environment(MailStore.self) var store
    @AppStorage("fontScale") private var fontScale = 1.0
    let thread: MailThread
    let compactMode: Bool
    /// Full-app conversation (⌘↩) — back control exits focus, not the thread.
    var focusMode: Bool = false
    /// Left column of side-by-side compose (⇧⌘↩): back control exits split,
    /// and prev/next hide (selection is decoupled from this conversation).
    var splitMode: Bool = false
    let onBack: () -> Void
    let onReply: (Message) -> Void
    /// Owned by the host: the toolbar is declared outside `.id(thread.id)`.
    let toolbarModel: ThreadToolbarModel

    @State private var messages: [Message] = [] {
        // Every mutation (assign, subscript write, animated merge) lands here,
        // so the draft/sent split below can never go stale.
        didSet {
            messageRoles = ThreadMessageRoles(messages: messages, threadUnread: thread.isUnread)
            toolbarModel.publish(threadId: thread.id, messages: messages)
            summaryFingerprint = ThreadSummaryPolicy.fingerprint(subject: thread.subject, messages: messages)
            summaryEligible = ThreadSummaryPolicy.isWorthSummarizing(messages)
        }
    }
    /// Draft vs sent split of `messages`, derived once per change instead of
    /// re-splitting every message's `labelIds` on each body pass (the ForEach,
    /// the banner, and the expand seed all read it).
    @State private var messageRoles = ThreadMessageRoles(messages: [])
    @State private var attachmentsByMessageId: [String: [AttachmentRow]] = [:]
    /// Gmail's "N deleted messages in this conversation" line: its count
    /// and place, from the payload (no message of theirs is in it).
    @State private var deletedSummary: DeletedMessagesSummary?
    /// "View" pressed: the deleted messages are shown inline. Per open
    /// conversation, never remembered (`.id(thread.id)` remounts this view).
    @State private var showsDeleted = false
    /// What "View" loaded, apart from `messages` (which the toolbar, export,
    /// the summary and the keyboard read): never in the cache or mirror.
    @State private var deletedLoad = DeletedMessagesLoad.empty
    @State private var deletedLoadTask: Task<Void, Never>?
    /// Off-main quote-trail + assembled HTML from `ThreadDetailRepository`.
    @State private var bodyPrepByMessageId: [String: MessageHTMLPrep] = [:]
    @State private var threadAttachments: [(message: Message, attachment: AttachmentRow)] = []
    @State private var scrollAnchor = ThreadScrollAnchor()
    @State private var aiSummary: String?
    /// Identifies the running summary so a late stream cannot write into
    /// the next thread after the user moves on.
    @State private var summaryRequestId: UUID?
    @State private var summaryTask: Task<Void, Never>?
    @State private var summaryFingerprint = ""
    @State private var summaryEligible = false
    @State private var summarySourceFingerprint = ""
    private var summarizing: Bool { summaryRequestId != nil }
    @State private var summaryError: String?
    @AppStorage(ThreadSummaryPolicy.autoSummarizeKey) private var autoSummarizeLocal = false
    /// Completed summaries are cached locally and carry their source fingerprint.
    @State private var persistedSummary: ThreadSummaryRow?
    /// Session opt-in: Load images for every card in this thread.
    @State private var loadRemoteImagesForThread = false
    /// Message ids we already tried to hydrate — avoids re-querying forever
    /// for genuinely empty bodies (`needsBodyLoad` stays true).
    @State private var bodyLoadAttempted: Set<String> = []
    /// Session-only HTML with `cid:` rewritten to `data:` (not persisted).
    @State private var cidInlinedHTMLById: [String: String] = [:]
    /// Quote trail + assembled documents for `cidInlinedHTMLById`, built off
    /// the main actor. Always written in the same main-actor turn as the
    /// inlined HTML, so a card never sees one without the other. Kept apart
    /// from `bodyPrepByMessageId` because refresh / hydration overwrite that
    /// map with DB-HTML prep that still carries unresolved `cid:` refs.
    /// `htmlBytes` here is the *pre-inline* size (see `cidInlinedPrep`).
    @State private var cidPrepByMessageId: [String: MessageHTMLPrep] = [:]
    /// Avoid re-fetching the same message for Content-ID recovery every expand.
    @State private var cidResolveAttempted: Set<String> = []
    /// `cid:` resolves still running: a remote-image resolve for the same
    /// message waits for it, so it works on the final base once.
    @State private var cidResolveInFlight: Set<String> = []
    /// Bodies with every cacheable remote image from the cache
    /// (`RemoteInlinedBody`), seeded from the payload when the conversation
    /// opens (a warmed payload, or one an earlier open filled); never
    /// changed while it is open.
    @State private var remoteBodyById: [String: RemoteInlinedBody] = [:]
    /// "id|cid" / "id|raw": remote resolves started, per base.
    /// Remote-image decisions for this conversation (cache checks, fetches
    /// for the next open, cancellation): `RemoteImagePaneState`.
    @State private var remotePane = RemoteImagePaneState()
    /// The running check, rebuild or fetch per message, cancelled when its
    /// images stop being allowed or its body leaves, and on thread change.
    @State private var remoteResolveTasks: [String: Task<Void, Never>] = [:]
    /// Avoid re-fetching the same message for missing-attachment recovery every expand.
    @State private var attachmentRecoverAttempted: Set<String> = []
    /// Open message cards (live HTML body renderers). The reading pane keeps
    /// this to one id (`MessageExpandPolicy.single`); side-by-side compose
    /// opens every sent card so the draft can reference the full thread.
    @State private var expandedMessageIds: Set<String> = []
    /// Gmail `;` pressed: every card open until `:` (or another conversation).
    @State private var expandAllActive = false
    /// The message Gmail's `n` / `p` last moved to.
    @State private var messageCursorId: String?
    /// Visible height of the conversation's scroll view. The open card
    /// reserves it for a body that has not measured itself yet, so the pane
    /// never opens as a short box (see `MessageBodyHeight`).
    @State private var paneViewportHeight: CGFloat = 0
    /// Reading position to restore when inline compose closes.
    @State private var inlineScrollRestore: InlineScrollRestore = .unset
    @State private var inlineScrollTargetId: String?
    @State private var lastPinnedTargetHeight: CGFloat = 0
    @State private var autoPinInlineScroll = false
    @State private var pinnedComposeRequestId: UUID?
    @State private var scrollWrite: UUID?
    @State private var pinnedScrollOffsetY: CGFloat?
    @State private var scrollDisarmGate = InlineScrollDisarmGate()
    @State private var refreshTask: Task<Void, Never>?
    @State private var detailLoadGeneration = 0
    /// Content revision this pane's messages were built from, so a change to
    /// some *other* conversation never triggers a reload here.
    @State private var seenContentRevision: ThreadContentRevision?
    /// Arm neighbor HTML pre-render once per open after the body first settles.
    @State private var neighborPrerenderArmed = false
    /// Message whose Gmail-style Unsubscribe confirm is showing.
    @State private var unsubscribeTarget: Message?
    /// Sender block confirmation target; blocking moves matching threads to
    /// Spam, so it should never be a one-click destructive menu item.
    private struct BlockTarget {
        let email: String
        let thread: MailThread?
    }
    @State private var blockTarget: BlockTarget?
    /// Message ids we already tried to backfill List-Unsubscribe for.
    @State private var unsubscribeRefreshAttempted: Set<String> = []
    /// "Mark as unread" during the read-on-open dwell: the dwell
    /// must not mark the conversation read again.
    @State private var markedUnreadSinceOpen = false

    /// `.id(thread.id)` remounts this view for every conversation, so `@State`
    /// starts empty and `.task` cannot run until *after* the first body
    /// evaluation — the pane would paint blank for a frame no matter how fast
    /// the payload arrives. Seeding here puts the conversation in that first
    /// frame whenever the caller already had it.
    init(thread: MailThread,
         compactMode: Bool,
         focusMode: Bool = false,
         splitMode: Bool = false,
         initialPayload: ThreadDetailPayload? = nil,
         toolbarModel: ThreadToolbarModel,
         onBack: @escaping () -> Void,
         onReply: @escaping (Message) -> Void) {
        self.toolbarModel = toolbarModel
        self.thread = thread
        self.compactMode = compactMode
        self.focusMode = focusMode
        self.splitMode = splitMode
        self.onBack = onBack
        self.onReply = onReply
        guard let initialPayload else { return }
        _messages = State(initialValue: initialPayload.messages)
        let initialRoles = ThreadMessageRoles(messages: initialPayload.messages,
                                             threadUnread: thread.isUnread)
        _messageRoles = State(initialValue: initialRoles)
        // Open the default card set in the first frame too. Without it the
        // seeded conversation painted every card collapsed — a one-message
        // conversation showed as a header-only row, like an older message in
        // a long thread — until onAppear or the load task opened it.
        _expandedMessageIds = State(
            initialValue: MessageExpandPolicy.initialExpandedIds(
                policy: splitMode ? .multiple : .single,
                nonDraftIds: initialRoles.nonDraftIds,
                lastNonDraftId: initialRoles.lastNonDraftId,
                openIds: initialRoles.openExpandedIds))
        _summaryFingerprint = State(initialValue: ThreadSummaryPolicy.fingerprint(
            subject: thread.subject, messages: initialPayload.messages))
        _summaryEligible = State(initialValue: ThreadSummaryPolicy.isWorthSummarizing(initialPayload.messages))
        _attachmentsByMessageId = State(
            initialValue: initialPayload.attachmentsByMessageId)
        _deletedSummary = State(initialValue: initialPayload.deletedSummary)
        _bodyPrepByMessageId = State(
            initialValue: initialPayload.bodyPrepByMessageId)
        _threadAttachments = State(
            initialValue: ThreadRefresh.threadAttachments(in: initialPayload))
        _scrollAnchor = State(
            initialValue: ThreadScrollAnchor(
                id: ThreadRefresh.initialScrolledMessageId(
                    in: initialPayload.messages, threadUnread: thread.isUnread)))
        _bodyLoadAttempted = State(
            initialValue: Set(ThreadRefresh.initialBodyLoadSeedIds(
                in: initialPayload.messages, threadUnread: thread.isUnread)))
    }

    /// Space below each block above the messages (subject, chips, summary,
    /// draft banner). Messages themselves are split by a hairline only.
    static let headerBlockSpacing: CGFloat = 12

    /// The first message the pane actually draws: a live draft hidden while
    /// its compose editor is open does not count, so no hairline sits on top
    /// of the first row.
    private func firstRenderedRowId(in rows: [DeletedMessagesInConversation.Row]) -> String? {
        rows.first { row in
            guard case .message(let message, false) = row else { return true }
            return !(messageRoles.isLiveDraft(message.id)
              && ComposingDraftVisibility.hidesDraftCard(
                  messageId: message.id,
                  composingDraftIds: store.composingDraftMessageIds))
        }?.id
    }

    /// The pane's rows: the live messages, the deleted-messages line where
    /// the first deleted message is, and, after "View", the deleted
    /// messages in date order (`DeletedMessagesInConversation.rows`).
    private var paneRows: [DeletedMessagesInConversation.Row] {
        DeletedMessagesInConversation.rows(
            live: messages, deleted: deletedLoad.messages,
            summary: deletedSummary, showing: showsDeleted)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Message rows are cheap while collapsed and only expanded rows
                // mount WKWebView. An eager stack avoids LazyVStack's geometry
                // cache repeatedly invalidating around dynamically sized WebViews.
                // No stack spacing: the blocks above the messages carry their
                // own bottom padding, and message rows touch (hairline only),
                // so each row's id sits on its real top edge.
                VStack(alignment: .leading, spacing: 0) {
                    Text(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                        .font(.system(size: 19 * fontScale, weight: .semibold))
                        .textSelection(.enabled)
                        .padding(.horizontal)
                        .accessibilityIdentifier("threadSubject")
                        .id(ComposePlacement.threadTopScrollId)
                        .padding(.bottom, Self.headerBlockSpacing)

                    threadMetaRow
                        .padding(.bottom, Self.headerBlockSpacing)

                    // Its .task is the auto-summary: gone with the section.
                    // Not for the trashed messages of a live conversation
                    // opened from the Trash view.
                    if AIFeatures.isEnabled, !store.opensTrashReader(threadId: thread.id) {
                        summarySection
                            .padding(.bottom, Self.headerBlockSpacing)
                    }

                    // Slim cue for long threads only: on short threads the draft
                    // card is already in the first viewport, so a second orange
                    // affordance is noise. Continues the newest draft.
                    if showDraftBanner {
                        Button {
                            store.editDraft(inThread: thread)
                        } label: {
                            HStack(spacing: 8) {
                                Text("Draft")
                                    .font(.system(size: 11 * fontScale, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule())
                                Text("Unsent reply in this conversation")
                                    .font(.system(size: 12.5 * fontScale))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("Continue")
                                    .font(.system(size: 12.5 * fontScale, weight: .medium))
                                    .foregroundStyle(.accentText)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10 * fontScale, weight: .semibold))
                                    .foregroundStyle(.accentForeground)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: PMRadius.md)
                                    .fill(Color.orange.opacity(0.10))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: PMRadius.md)
                                    .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: PMRadius.md))
                        }
                        .buttonStyle(.plain)
                        .help("Continue editing the unsent draft")
                        .padding(.horizontal)
                        .padding(.bottom, Self.headerBlockSpacing)
                    }

                    // Flat rows split by a hairline (Gmail on the web), drawn
                    // over the top edge of every row but the first. Rows stay
                    // direct children of this stack: they are the scroll
                    // position's targets.
                    // Built once per body pass, not once per row.
                    let rows = paneRows
                    let firstRenderedMessageId = firstRenderedRowId(in: rows)
                    ForEach(rows) { row in
                        switch row {
                        case .line:
                            deletedMessagesLine
                                .messageRowSeparator(
                                    isFirst: DeletedMessagesInConversation.lineId == firstRenderedMessageId)
                                .id(DeletedMessagesInConversation.lineId)
                        case .message(let message, true):
                            deletedMessageCard(for: message)
                                .messageRowSeparator(isFirst: message.id == firstRenderedMessageId)
                                .id(message.id)
                        case .message(let message, false):
                            if messageRoles.isLiveDraft(message.id) {
                                // Live unsent drafts only — DRAFT+TRASH (discarded)
                                // keeps ordinary MessageCard chrome so Trash still
                                // shows content for discarded-compose threads.
                                // The card steps aside while its own compose editor
                                // is open, and returns when compose closes.
                                if !ComposingDraftVisibility.hidesDraftCard(
                                    messageId: message.id,
                                    composingDraftIds: store.composingDraftMessageIds) {
                                    DraftMessageCard(
                                        message: message,
                                        onNeedBody: { loadBodyIfNeeded(id: message.id) })
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .messageRowSeparator(isFirst: message.id == firstRenderedMessageId)
                                        .id(message.id)
                                        .background { pinnedHeightReader(id: message.id, proxy: proxy) }
                                }
                            } else {
                                messageCard(for: message,
                                            lastNonDraftId: messageRoles.lastNonDraftId,
                                            scrollTargetId: messageRoles.scrollTargetId,
                                            starredTargetId: messageRoles.starredTargetId)
                                    .messageRowSeparator(isFirst: message.id == firstRenderedMessageId)
                                    .id(message.id)
                                    .background { pinnedHeightReader(id: message.id, proxy: proxy) }
                            }
                        }
                    }

                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            // Stable top anchor for reading; inline reply uses one-shot bottom
            // scrollTo so dismiss does not flip anchors and jump the thread.
            .scrollPosition(id: scrollAnchorBinding, anchor: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // Whole points only: sub-point layout noise must not
                // re-render every card.
                let rounded = height.rounded()
                if rounded != paneViewportHeight { paneViewportHeight = rounded }
            }
            .modifier(ScrollOffsetDisarmModifier(armed: autoPinInlineScroll && inlineComposeActive) { oldY, newY in
                noteScrollOffsetChange(from: oldY, to: newY)
            })
            .task(id: thread.id) {
                detailLoadGeneration &+= 1
                let loadGeneration = detailLoadGeneration
                // Seed before the load: anything that lands after this point
                // is a real change and must refresh, anything already folded
                // into this payload must not.
                seenContentRevision = store.contentRevision(of: thread.id)
                bodyLoadAttempted = []
                cidInlinedHTMLById = [:]
                cidPrepByMessageId = [:]
                cidResolveAttempted = []
                cidResolveInFlight = []
                remoteBodyById = [:]
                for task in remoteResolveTasks.values { task.cancel() }
                remoteResolveTasks = [:]
                remotePane = RemoteImagePaneState()
                loadRemoteImagesForThread = false
                // Keep the open set `init` seeded for this conversation; the
                // payload re-seeds below. Clearing it here collapsed the card
                // until the load returned (the whole repository round-trip
                // when the warm mirror missed).
                expandedMessageIds = MessageExpandPolicy.keptAtLoadStart(
                    current: expandedMessageIds,
                    messageThreadIds: messages.map(\.threadId),
                    threadId: thread.id)
                neighborPrerenderArmed = false
                unsubscribeTarget = nil
                blockTarget = nil
                unsubscribeRefreshAttempted = []
                markedUnreadSinceOpen = false
                // Cancel any in-flight neighbor paints from the previous open.
                HTMLBodyNeighborPrerender.cancel()
                // Did `init` already seed from the mirror? When this is 1 the
                // first rendered frame already showed the conversation; when
                // it is 0 the pane painted empty until this task ran.
                let preseeded = messages.isEmpty ? 0 : 1
                let readyInterval = PerfMetrics.begin(
                    .openReady, meta: "preseeded=\(preseeded)")
                // Paint from the main-actor mirror when the payload is already
                // known — no `await`, so the pane lands in the same frame as
                // the row removal. This is the common case on the advance path
                // (the neighbour was warmed by `scheduleNeighborPrefetch`), and
                // it is the whole point: going to the repository costs a
                // round-trip whose return hop waits on the SwiftUI work the
                // delete just queued, which measured 176–209 ms.
                if let warm = store.warmThreadDetail(threadId: thread.id) {
                    applyDetailPayload(warm, proxy: proxy)
                    readyInterval.end(extraMeta: "warm n=\(warm.messages.count)")
                } else {
                    let load = await store.threadDetailPayload(threadId: thread.id)
                    guard !Task.isCancelled else {
                        readyInterval.end(extraMeta: "cancelled")
                        return
                    }
                    if loadGeneration == detailLoadGeneration,
                       splitMode || store.openedThreadId == thread.id {
                        applyDetailPayload(load.payload, proxy: proxy)
                        readyInterval.end(
                            extraMeta: "\(load.cacheHit ? "cache_hit" : "cache_miss")"
                                + " n=\(load.payload.messages.count)")
                    } else {
                        readyInterval.end(extraMeta: "superseded")
                    }
                }
                // Dwell before auto mark-read so j/k / scroll-select through the
                // inbox does not clear every unread badge. Archive (`e`) marks
                // read immediately in MailStore.archive; `.task(id:)` cancels
                // this sleep when selection leaves.
                guard thread.isUnread else { return }
                do {
                    try await Task.sleep(nanoseconds: MarkReadOnOpen.dwellNanoseconds)
                } catch {
                    return
                }
                // Require a live list row — never fall back to the captured
                // `thread` snapshot. After archive of the last visible row,
                // selection can still point here while the row is gone; using
                // the stale model would re-save inInbox=true via setRead.
                let liveThread = store.threads.first(where: { $0.id == thread.id })
                guard MarkReadOnOpen.shouldMarkRead(
                    selectedId: store.selectedThreadId,
                    threadId: thread.id,
                    liveIsUnread: liveThread?.isUnread,
                    userMarkedUnread: markedUnreadSinceOpen),
                      let liveThread else { return }
                store.setRead(liveThread, read: true)
            }
            // Some thread's message rows changed (sync, draft discard, send…).
            // Refresh in place — a discarded draft's card disappears without
            // navigating away — but only when it was *this* thread: a sync
            // touching other conversations must not disturb what we're reading.
            // Scroll anchor and summary stay put.
            // Gmail `n` / `p` / `;` / `:` (routed by ContentView only while
            // this conversation is on screen).
            .onChange(of: store.conversationKeyRequest) { _, request in
                guard let request, request.threadId == thread.id else { return }
                runConversationKey(request.action, proxy: proxy)
            }
            .onChange(of: store.threadContentToken) {
                let revision = store.contentRevision(of: thread.id)
                guard revision != seenContentRevision else { return }
                seenContentRevision = revision
                refreshMessages(proxy: proxy)
            }
            // Suppression changes no content revision (it is applied to the
            // payload on the way out, not cached), so it needs its own nudge.
            // The reload behind it is a cache hit.
            .onChange(of: store.suppressedDraftMessageIds) {
                refreshMessages(proxy: proxy)
            }
            .onChange(of: inlineComposeActive) { _, active in
                if active {
                    beginInlineComposeScroll(proxy: proxy)
                } else {
                    endInlineComposeScroll(proxy: proxy)
                }
            }
            .onChange(of: store.composeRequest?.id) { oldId, newId in
                guard inlineComposeActive, let newId, oldId != nil else { return }
                guard autoPinInlineScroll else { return }
                guard newId != pinnedComposeRequestId else { return }
                pinnedComposeRequestId = newId
                lastPinnedTargetHeight = 0
                scrollInlineComposeTarget(proxy, releaseTopPin: false)
            }
            .onChange(of: autoPinInlineScroll) { _, armed in
                scrollDisarmGate.onUserScroll = { disarmAutoPin() }
                scrollDisarmGate.setWheelArmed(armed && inlineComposeActive)
            }
            .onAppear {
                // `init` seeds `messages` without running its `didSet`.
                toolbarModel.publish(threadId: thread.id, messages: messages)
                toolbarModel.install(
                    .init(copyMarkdown: { copyThreadAsMarkdown() },
                          saveMarkdown: { saveThreadAsMarkdown() },
                          unsubscribe: { unsubscribeTarget = $0 },
                          confirmBlock: { email, thread in
                              blockTarget = BlockTarget(email: email, thread: thread)
                          }),
                    threadId: thread.id)
            }
            .onDisappear {
                toolbarModel.uninstall(threadId: thread.id)
                cancelSummary()
                disarmAutoPin()
                scrollWrite = nil
                scrollDisarmGate.setWheelArmed(false)
                detailLoadGeneration &+= 1
                refreshTask?.cancel()
                refreshTask = nil
                deletedLoadTask?.cancel()
                deletedLoadTask = nil
                neighborPrerenderArmed = false
                HTMLBodyNeighborPrerender.cancel()
            }
            .alert(
                unsubscribeTarget.map {
                    ListUnsubscribe.confirmationTitle(fromHeader: $0.fromHeader)
                } ?? "Unsubscribe?",
                isPresented: Binding(
                    get: { unsubscribeTarget != nil },
                    set: { if !$0 { unsubscribeTarget = nil } })
            ) {
                Button("Unsubscribe") {
                    if let msg = unsubscribeTarget {
                        store.unsubscribe(from: msg)
                    }
                    unsubscribeTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    unsubscribeTarget = nil
                }
            } message: {
                if let msg = unsubscribeTarget,
                   let action = ListUnsubscribe.offer(from: msg)?.preferredAction {
                    Text(ListUnsubscribe.confirmationDetail(for: action))
                }
            }
            .confirmationDialog(
                "Block sender?",
                isPresented: Binding(
                    get: { blockTarget != nil },
                    set: { if !$0 { blockTarget = nil } }),
                presenting: blockTarget
            ) { target in
                Button("Block Sender", role: .destructive) {
                    if let thread = target.thread {
                        store.blockThreadSender(thread)
                    } else {
                        store.blockSender(target.email)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                Text("New threads from \(target.email) will move to Spam.")
            }
        }
    }

    /// User-scroll writes land here (not in a `@State`), so a fling through a
    /// long thread never invalidates the whole body. The disarm check that
    /// used to live in `.onChange(of: scrolledMessageId)` runs in the setter,
    /// deferred a turn (like `onChange` was) so the `@State` write never lands
    /// inside the scroll machinery's own update.
    private var scrollAnchorBinding: Binding<String?> {
        Binding(
            get: { scrollAnchor.id },
            set: { newValue in
                let changed = newValue != scrollAnchor.id
                scrollAnchor.id = newValue
                guard changed, autoPinInlineScroll, inlineComposeActive else { return }
                DispatchQueue.main.async {
                    guard inlineComposeActive, autoPinInlineScroll,
                          scrollWrite == nil else { return }
                    disarmAutoPin()
                }
            })
    }

    /// Programmatic anchor move: record it and scroll explicitly next turn,
    /// after the freshly assigned `messages` have produced rows to target.
    /// (`scrollAnchor` writes alone no longer re-render anything, so the old
    /// binding-driven post-layout anchoring must be an explicit `scrollTo`.)
    private func applyScrollAnchor(_ id: String?, proxy: ScrollViewProxy, write: UUID? = nil) {
        scrollAnchor.id = id
        guard let id else { return }
        DispatchQueue.main.async {
            if let write, scrollWrite != write { return }
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private enum InlineScrollRestore: Equatable {
        case unset
        case threadTop
        case message(String)
    }

    private struct ScrollOffsetDisarmModifier: ViewModifier {
        let armed: Bool
        let onOffset: (CGFloat, CGFloat) -> Void

        func body(content: Content) -> some View {
            if #available(macOS 15.0, *) {
                content.onScrollGeometryChange(for: CGFloat?.self) { geo in
                    armed ? geo.contentOffset.y : nil
                } action: { oldY, newY in
                    if let oldY, let newY { onOffset(oldY, newY) }
                }
            } else {
                content
            }
        }
    }


    /// Split out of `body`: the full MessageCard initializer inside the
    /// thread ForEach is too much for the type checker in one expression.
    private func messageCard(for message: Message, lastNonDraftId: String?,
                             scrollTargetId: String?, starredTargetId: String?) -> some View {
        MessageCard(message: message,
                    isLast: message.id == scrollTargetId,
                    attachments: attachmentsByMessageId[message.id] ?? [],
                    bodyPrep: bodyPrepByMessageId[message.id],
                    cidInlinedHTML: cidInlinedHTMLById[message.id],
                    cidPrep: cidPrepByMessageId[message.id],
                    remoteBody: remoteBodyById[message.id],
                    remoteCheck: remotePane.checks[message.id],
                    expandPolicy: messageExpandPolicy,
                    expandedMessageIds: $expandedMessageIds,
                    isCollapsible: MessageExpandPolicy.isCollapsible(
                        id: message.id, nonDraftIds: messageRoles.nonDraftIds),
                    fillsPaneHeight: MessageExpandPolicy.fillsPane(
                        id: message.id,
                        policy: messageExpandPolicy,
                        expanded: expandedMessageIds,
                        lastNonDraftId: lastNonDraftId,
                        scrollTargetId: starredTargetId)
                        ? paneViewportHeight : nil,
                    loadImagesForThread: $loadRemoteImagesForThread,
                    threadInSpam: thread.inSpam,
                    onReply: { onReply(message) },
                    onBlockSender: { email in
                        blockTarget = BlockTarget(email: email, thread: nil)
                    },
                    onNeedBody: { loadBodyIfNeeded(id: message.id) },
                    onRemoteImagesDecision: { allowed, mounted in
                        remoteImagesDecisionChanged(id: message.id, allowed: allowed,
                                                    bodyMounted: mounted)
                    },
                    onBodySettled: { armNeighborPrerenderIfNeeded() },
                    onUnsubscribe: { unsubscribeTarget = message },
                    onNeedUnsubscribeHeaders: {
                        Task { await refreshUnsubscribeHeaders(message) }
                    },
                    onMarkUnreadFromHere: {
                        markedUnreadSinceOpen = true
                        store.markUnreadFromHere(message, shown: messages)
                    })
    }

    /// Gmail web's line where the deleted messages of a live conversation
    /// were: the count, then "View" (or "Hide" and "Restore all" while they
    /// are shown). No mail content.
    private var deletedMessagesLine: some View {
        let label = DeletedMessagesInConversation.label(count: deletedSummary?.count ?? 0)
        return HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 12.5 * fontScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(showsDeleted ? "Hide" : "View") { toggleDeletedMessages() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5 * fontScale, weight: .medium))
                .foregroundStyle(.accentText)
                .fixedSize()
                .help(showsDeleted ? "Hide the deleted messages" : "Show the deleted messages")
                .accessibilityIdentifier(showsDeleted
                    ? "thread.deletedMessages.hide" : "thread.deletedMessages.view")
            if showsDeleted, !deletedLoad.messages.isEmpty {
                Button("Restore all") {
                    store.restoreDeletedMessages(gmailIds: deletedLoad.messages.map(\.gmailId),
                                                 inThread: thread.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5 * fontScale, weight: .medium))
                .foregroundStyle(.accentText)
                .fixedSize()
                .help("Move the deleted messages back to this conversation")
                .accessibilityIdentifier("thread.deletedMessages.restoreAll")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("thread.deletedMessages")
    }

    /// A deleted message shown after "View": marked "In Trash", muted, and
    /// with "Restore" as its only action (no reply, forward or unsubscribe).
    /// Its body is the stored one, already loaded: expanding it sends no
    /// request and marks nothing read.
    private func deletedMessageCard(for message: Message) -> some View {
        MessageCard(message: message,
                    isLast: false,
                    attachments: deletedLoad.attachmentsByMessageId[message.id] ?? [],
                    bodyPrep: deletedLoad.bodyPrepByMessageId[message.id],
                    expandPolicy: messageExpandPolicy,
                    expandedMessageIds: $expandedMessageIds,
                    loadImagesForThread: $loadRemoteImagesForThread,
                    threadInSpam: thread.inSpam,
                    inTrash: true,
                    onReply: {},
                    onRestore: {
                        store.restoreDeletedMessages(gmailIds: [message.gmailId], inThread: thread.id)
                    },
                    onBlockSender: { email in
                        blockTarget = BlockTarget(email: email, thread: nil)
                    })
    }

    /// "View" reads the deleted messages (local rows only); "Hide" closes
    /// them again.
    private func toggleDeletedMessages() {
        if showsDeleted {
            closeDeletedMessages()
        } else {
            loadDeletedMessages(reveal: true)
        }
    }

    private func loadDeletedMessages(reveal: Bool) {
        deletedLoadTask?.cancel()
        let threadId = thread.id
        deletedLoadTask = Task {
            let load = await store.deletedMessagesForReadingPane(threadId: threadId)
            guard !Task.isCancelled, splitMode || store.openedThreadId == threadId else { return }
            withAnimation(PMMotion.interactive) {
                deletedLoad = load
                if reveal { showsDeleted = true }
            }
        }
    }

    /// A payload's line facts. While the deleted messages are shown, a
    /// changed count (a restore, a sync) reads them again; no line left
    /// closes them.
    private func applyDeletedSummary(_ summary: DeletedMessagesSummary?) {
        let changed = summary != deletedSummary
        deletedSummary = summary
        // No line left: close, and drop a View still reading, so it cannot
        // open them later by itself.
        if summary == nil {
            closeDeletedMessages()
        } else if showsDeleted, changed {
            loadDeletedMessages(reveal: false)
        }
    }

    /// "Hide", or no deleted message left.
    private func closeDeletedMessages() {
        deletedLoadTask?.cancel()
        deletedLoadTask = nil
        expandedMessageIds.subtract(deletedLoad.messages.map(\.id))
        withAnimation(PMMotion.interactive) { showsDeleted = false }
        deletedLoad = .empty
    }

    /// Only the inline reply's target needs height updates as its HTML settles.
    @ViewBuilder
    private func pinnedHeightReader(id: String, proxy: ScrollViewProxy) -> some View {
        if autoPinInlineScroll, inlineScrollTargetId == id, inlineComposeActive {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard autoPinInlineScroll, inlineScrollTargetId == id, inlineComposeActive else { return }
                if height > lastPinnedTargetHeight + 8 {
                    lastPinnedTargetHeight = height
                    scrollInlineComposeTarget(proxy, releaseTopPin: false)
                } else if lastPinnedTargetHeight == 0 {
                    lastPinnedTargetHeight = height
                }
            }
        }
    }

    private var inlineComposeActive: Bool {
        guard let req = store.composeRequest,
              req.presentation == .inline,
              !store.composeMinimized,
              req.boundThreadId == thread.id else { return false }
        return true
    }

    private func disarmAutoPin() {
        guard autoPinInlineScroll else { return }
        autoPinInlineScroll = false
        pinnedScrollOffsetY = nil
        scrollWrite = nil
    }

    private func noteScrollOffsetChange(from oldY: CGFloat, to newY: CGFloat) {
        if scrollWrite != nil {
            pinnedScrollOffsetY = newY
            return
        }
        guard inlineComposeActive, autoPinInlineScroll else { return }
        if let pinned = pinnedScrollOffsetY, abs(newY - pinned) < 2 {
            return
        }
        if abs(newY - oldY) < 0.5 { return }
        disarmAutoPin()
    }

    private func beginInlineComposeScroll(proxy: ScrollViewProxy) {
        guard let requestID = store.composeRequest?.id, pinnedComposeRequestId != requestID else { return }
        if inlineScrollRestore == .unset {
            if let id = scrollAnchor.id {
                inlineScrollRestore = .message(id)
            } else {
                inlineScrollRestore = .threadTop
            }
        }
        autoPinInlineScroll = true
        pinnedComposeRequestId = requestID
        pinnedScrollOffsetY = nil
        lastPinnedTargetHeight = 0
        scrollInlineComposeTarget(proxy, releaseTopPin: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard inlineComposeActive, autoPinInlineScroll, pinnedComposeRequestId == requestID else { return }
            scrollInlineComposeTarget(proxy, releaseTopPin: false)
        }
    }

    private func endInlineComposeScroll(proxy: ScrollViewProxy) {
        let restore = inlineScrollRestore
        inlineScrollRestore = .unset
        inlineScrollTargetId = nil
        lastPinnedTargetHeight = 0
        autoPinInlineScroll = false
        pinnedComposeRequestId = nil
        pinnedScrollOffsetY = nil
        let write = UUID()
        scrollWrite = write
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            switch restore {
            case .unset:
                scrollWrite = nil
            case .threadTop:
                scrollAnchor.id = nil
                DispatchQueue.main.async {
                    guard scrollWrite == write else { return }
                    var inner = Transaction()
                    inner.animation = nil
                    withTransaction(inner) {
                        proxy.scrollTo(ComposePlacement.threadTopScrollId, anchor: .top)
                    }
                    DispatchQueue.main.async { if scrollWrite == write { scrollWrite = nil } }
                }
            case .message(let id):
                applyScrollAnchor(id, proxy: proxy, write: write)
                DispatchQueue.main.async { if scrollWrite == write { scrollWrite = nil } }
            }
        }
    }

    private func scrollInlineComposeTarget(_ proxy: ScrollViewProxy,
                                           releaseTopPin: Bool) {
        guard autoPinInlineScroll || releaseTopPin else { return }
        let target = ComposePlacement.scrollTargetId(
            replyTo: store.composeRequest?.replyTo,
            messages: messages)
        guard let target else { return }
        if target != inlineScrollTargetId {
            inlineScrollTargetId = target
            lastPinnedTargetHeight = 0
        }
        let write = UUID()
        scrollWrite = write
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            if releaseTopPin { scrollAnchor.id = nil }
            DispatchQueue.main.async {
                guard scrollWrite == write else { return }
                var inner = Transaction()
                inner.animation = nil
                withTransaction(inner) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if scrollWrite == write { scrollWrite = nil }
                }
            }
        }
    }

    /// Re-query this thread's rows and merge into the visible list, keeping
    /// already-hydrated bodies so open cards don't collapse back to
    /// "Loading…". No-op when nothing about the thread changed.
    private func refreshMessages(proxy: ScrollViewProxy) {
        detailLoadGeneration &+= 1
        let loadGeneration = detailLoadGeneration
        refreshTask?.cancel()
        refreshTask = Task {
            // No forceReload: the revision carried by the request is the source
            // of truth now. A real content change misses and re-reads; a
            // suppression-only refresh hits the warm entry.
            let load = await store.threadDetailPayload(threadId: thread.id)
            guard !Task.isCancelled,
                  loadGeneration == detailLoadGeneration,
                  splitMode || store.openedThreadId == thread.id else { return }
            // Superseded initial .task leaves messages empty; when merge is
            // the first population, apply the same anchor/seed as open.
            let wasEmpty = messages.isEmpty
            // Capture before merge so "new" means arrived-this-refresh, not
            // "user collapsed" (which would re-open on every sync).
            let priorIds = Set(messages.map(\.id))
            let merged = ThreadRefresh.merge(
                current: messages, fresh: load.payload.messages)
            attachmentsByMessageId = load.payload.attachmentsByMessageId
            applyDeletedSummary(load.payload.deletedSummary)
            // Keep prep for bodies we already hydrated that the fresh payload
            // may have as header-only; overlay with any newly computed prep.
            var mergedPrep = bodyPrepByMessageId
            for (id, prep) in load.payload.bodyPrepByMessageId {
                mergedPrep[id] = prep
            }
            bodyPrepByMessageId = mergedPrep
            threadAttachments = merged.flatMap { msg in
                (attachmentsByMessageId[msg.id] ?? []).map {
                    (message: msg, attachment: $0)
                }
            }
            // Cheap display comparison: a full `!=` walked every hydrated
            // body (multi-MB HTML) on the main actor per sync refresh.
            guard !ThreadRefresh.isDisplayEquivalent(merged, messages) else { return }
            withAnimation(PMMotion.interactive) {
                messages = merged
            }
            backfillUnsubscribeHeaders()
            if wasEmpty {
                bodyLoadAttempted.formUnion(
                    ThreadRefresh.initialBodyLoadSeedIds(in: merged, threadUnread: thread.isUnread))
                applyScrollAnchor(
                    ThreadRefresh.initialScrolledMessageId(in: merged, threadUnread: thread.isUnread),
                    proxy: proxy)
                // First population via refresh (initial .task was superseded):
                // open the policy default set, same as applyDetailPayload.
                seedExpandedMessagesIfNeeded()
            } else {
                // Drop ids that left the thread (send/discard renumber).
                let live = Set(messageRoles.nonDraftIds)
                let wasOpen = expandedMessageIds
                // A shown deleted message stays open too.
                expandedMessageIds = MessageExpandPolicy.reconciledAfterRefresh(
                    current: expandedMessageIds,
                    nonDraftIds: messageRoles.nonDraftIds
                        + (showsDeleted ? deletedLoad.messages.map(\.id) : []))
                // A renumbered sole message (send, Gmail re-id) reopens.
                for id in expandedMessageIds.subtracting(wasOpen) {
                    loadBodyIfNeeded(id: id)
                }
                // Side-by-side: open only messages that arrived this refresh.
                // Diff against prior message ids so a manual collapse survives
                // background sync / draft-suppression refreshes.
                if messageExpandPolicy == .multiple {
                    let arrived = live.subtracting(priorIds)
                    if !arrived.isEmpty {
                        expandedMessageIds.formUnion(arrived)
                        for id in arrived { loadBodyIfNeeded(id: id) }
                    }
                }
            }
        }
    }

    /// True when a reading-pane message still needs a body fetch.
    static func needsBodyLoad(_ message: Message) -> Bool {
        ThreadRefresh.needsBodyLoad(message)
    }

    /// Banner only when the draft card is likely below the first viewport
    /// (≥4 messages) and that draft isn't already open in compose. Shorter
    /// threads already show the draft card on screen.
    private var showDraftBanner: Bool {
        ComposingDraftVisibility.showsDraftBanner(
            liveDraftIds: messageRoles.liveDraftIds,
            messageCount: messages.count,
            composingDraftIds: store.composingDraftMessageIds)
    }

    /// Side-by-side opens every sent card; the reading pane stays
    /// single-active unless Gmail's `;` opened every message.
    private var messageExpandPolicy: MessageExpandPolicy {
        splitMode || expandAllActive ? .multiple : .single
    }

    private func runConversationKey(_ action: MessageNavigation.Action, proxy: ScrollViewProxy) {
        let ids = messageRoles.nonDraftIds
        let before = MessageNavigation.State(
            expanded: expandedMessageIds, cursor: messageCursorId,
            expandAll: expandAllActive || splitMode)
        let (after, scrollTo) = MessageNavigation.apply(
            action, to: before, ids: ids, policy: messageExpandPolicy)
        messageCursorId = after.cursor
        // Side-by-side always keeps every card open; `:` there closes them
        // but the policy stays multiple.
        expandAllActive = after.expandAll && !splitMode
        withAnimation(.easeOut(duration: 0.12)) {
            expandedMessageIds = after.expanded
        }
        // In thread order, so the bounded fetch starts at the top.
        let opened = after.expanded.subtracting(before.expanded)
        loadBodiesBounded(ids.filter { opened.contains($0) })
        if let scrollTo {
            applyScrollAnchor(scrollTo, proxy: proxy)
        }
    }

    /// Seed open cards for the active policy and hydrate each body.
    ///
    /// Multiple mode always re-applies the full seed: MessageCard's last-card
    /// `onAppear` can race and open only the newest id before this runs, which
    /// would otherwise leave older cards collapsed in side-by-side.
    private func seedExpandedMessagesIfNeeded() {
        // Reading pane: keeps a card `init` (or the user) already opened
        // while it is still in the thread, else opens the payload's newest.
        expandedMessageIds = MessageExpandPolicy.applyingPayload(
            current: expandedMessageIds,
            policy: messageExpandPolicy,
            nonDraftIds: messageRoles.nonDraftIds,
            lastNonDraftId: messageRoles.lastNonDraftId,
            openIds: messageRoles.openExpandedIds)
        for id in expandedMessageIds {
            loadBodyIfNeeded(id: id)
        }
    }

    /// Hydrate one message's body into `messages` when the user expands it.
    private func loadBodyIfNeeded(id: String) {
        guard claimBodyLoad(id: id) else { return }
        Task { await fetchBody(id: id) }
    }

    /// Gmail `;` opens every card at once: fetch the missing bodies a few at
    /// a time rather than one request per message in a burst.
    static let expandAllBodyFetchLimit = 2

    private func loadBodiesBounded(_ ids: [String]) {
        let pending = ids.filter { claimBodyLoad(id: $0) }
        guard !pending.isEmpty else { return }
        // `expandAllBodyFetchLimit` serial walks, each over every n-th id.
        let lanes = min(Self.expandAllBodyFetchLimit, pending.count)
        for lane in 0..<lanes {
            let mine = stride(from: lane, to: pending.count, by: lanes).map { pending[$0] }
            Task {
                for id in mine { await fetchBody(id: id) }
            }
        }
    }

    /// True when `id` still needs its body fetched (and marks it attempted).
    /// A body already present only gets the CID and attachment recovery.
    private func claimBodyLoad(id: String) -> Bool {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return false }
        guard Self.needsBodyLoad(messages[idx]) else {
            // Body already present (newest message, cache hit) — still try CID
            // and missing-attachment recovery.
            recoverAttachmentsIfNeeded(id: id)
            resolveCIDImagesIfNeeded(id: id)
            return false
        }
        guard !bodyLoadAttempted.contains(id) else { return false }
        bodyLoadAttempted.insert(id)
        return true
    }

    @MainActor
    private func fetchBody(id: String) async {
        guard let loaded = await store.messageBodyForReadingPane(id: id),
              splitMode || store.openedThreadId == thread.id,
              let currentIdx = messages.firstIndex(where: { $0.id == id })
        else { return }
        messages[currentIdx] = loaded.message
        bodyPrepByMessageId[id] = loaded.prep
        recoverAttachmentsIfNeeded(id: id)
        resolveCIDImagesIfNeeded(id: id)
    }

    /// Full re-fetch when this card has no attachment chips but Gmail may still
    /// have files (stale body-without-attachments cache). Session-once per id.
    private func recoverAttachmentsIfNeeded(id: String) {
        guard !attachmentRecoverAttempted.contains(id) else { return }
        guard let msg = messages.first(where: { $0.id == id }) else { return }
        let localCount = (attachmentsByMessageId[id] ?? []).count
        guard SyncEngine.shouldRecoverAttachments(
            hasAttachmentFlag: msg.hasAttachment,
            localAttachmentCount: localCount,
            accountRepairCompleted: SyncEngine.attachmentRepairCompleted(
                accountId: msg.accountId)
        ) else { return }
        attachmentRecoverAttempted.insert(id)
        let scale = fontScale
        Task {
            guard let result = await store.recoverAttachmentsIfNeeded(
                message: msg, localAttachmentCount: localCount)
            else { return }
            // Quote scan + document assembly off the main actor. Built from
            // the re-fetched DB body; only used when no CID-inlined body is
            // active (checked again below, after the hop).
            let refetched = result.message
            let prep = await Task.detached(priority: .userInitiated) {
                MessageHTMLPrepBuilder.prep(
                    bodyText: refetched.bodyText,
                    bodyHTML: refetched.bodyHTML,
                    fontScale: scale)
            }.value
            await MainActor.run {
                guard splitMode || store.openedThreadId == thread.id else { return }
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    var merged = result.message
                    // Keep any session CID-inlined HTML if we already resolved it.
                    if let inlined = cidInlinedHTMLById[id] {
                        merged.bodyHTML = inlined
                    }
                    messages[idx] = merged
                    if cidInlinedHTMLById[id] == nil {
                        bodyPrepByMessageId[id] = prep
                    }
                }
                attachmentsByMessageId[id] = result.attachments
                threadAttachments = messages.flatMap { m in
                    (attachmentsByMessageId[m.id] ?? []).map {
                        (message: m, attachment: $0)
                    }
                }
            }
        }
    }

    /// Download / re-parse Content-ID image parts and rewrite `cid:` → `data:`
    /// for the open card. Local bytes only — not gated on Load images.
    private func resolveCIDImagesIfNeeded(id: String) {
        guard !cidResolveAttempted.contains(id) else { return }
        guard let msg = messages.first(where: { $0.id == id }),
              let html = msg.bodyHTML,
              CIDImageInliner.containsCIDReferences(html)
        else { return }
        cidResolveAttempted.insert(id)
        cidResolveInFlight.insert(id)
        let atts = attachmentsByMessageId[id] ?? []
        // Pre-inline size gates the oversized-HTML placeholder (see
        // `MessageHTMLPrepBuilder.cidInlinedPrep`).
        let preInlineBytes = html.utf8.count
        let scale = fontScale
        // Captured before the downloads: a change landing meanwhile must
        // keep this result out of the cache (see `rememberCIDInline`).
        let revision = store.contentRevision(of: thread.id)
        Task {
            guard let result = await store.inlineCIDImages(
                message: msg, attachments: atts, html: html)
            else {
                await MainActor.run { cidResolveDidFinish(id: id) }
                return
            }
            // The inlined body embeds base64 image bytes (often MBs). Scan
            // its quote trail and assemble its documents off the main actor,
            // once, so `MessageCard.init` / body only do lookups.
            let inlinedHTML = result.html
            let cidPrep = await Task.detached(priority: .userInitiated) {
                MessageHTMLPrepBuilder.cidInlinedPrep(
                    inlinedHTML: inlinedHTML,
                    preInlineBytes: preInlineBytes,
                    fontScale: scale)
            }.value
            await MainActor.run {
                guard splitMode || store.openedThreadId == thread.id else { return }
                // Same turn: a card must never see the inlined HTML without
                // its prep (it would fall back to the DB prep's `cid:` head).
                cidInlinedHTMLById[id] = result.html
                cidPrepByMessageId[id] = cidPrep
                attachmentsByMessageId[id] = result.attachments
                // `bodyPrepByMessageId[id]` keeps the DB-HTML prep: cards
                // prefer `cidPrepByMessageId` while an inlined body exists.
                if let refreshed = result.refreshedMessage,
                   let idx = messages.firstIndex(where: { $0.id == id }) {
                    // Keep session-inlined HTML on the card via cidInlinedHTMLById;
                    // update headers/snippet from the re-fetch.
                    var merged = refreshed
                    merged.bodyHTML = result.html
                    messages[idx] = merged
                } else if let idx = messages.firstIndex(where: { $0.id == id }) {
                    var copy = messages[idx]
                    copy.bodyHTML = result.html
                    messages[idx] = copy
                }
                threadAttachments = messages.flatMap { m in
                    (attachmentsByMessageId[m.id] ?? []).map {
                        (message: m, attachment: $0)
                    }
                }
                // A re-fetch rewrote the message and bumped the revision;
                // the next open loads the new rows and resolves again.
                if !result.didRefetch {
                    store.rememberCIDInline(
                        CIDInlinedBody(html: result.html, prep: cidPrep),
                        messageId: id, threadId: thread.id, revision: revision)
                }
                cidResolveDidFinish(id: id)
            }
        }
    }

    /// A `cid:` resolve ended: a remote-image resolve that waited for it
    /// runs now, on the final base.
    private func cidResolveDidFinish(id: String) {
        cidResolveInFlight.remove(id)
        // Only a body whose load had ended, with images allowed, waits for
        // this. With no inlined base it is still that loaded document; with
        // one, the card loads a new document and asks again once that load
        // has ended (its `.task` follows the load key).
        if remotePane.cidFinished(id), cidInlinedHTMLById[id] == nil {
            remoteImagesDecisionChanged(id: id, allowed: true, bodyMounted: true)
        }
    }

    /// The card's remote-image decision changed (or its base did, or its
    /// body mounted), through the one gate (`RemoteImagePaneState.step`).
    /// While images are allowed: one cache check before the first paint
    /// (bounded), so a fully cached message, prefetched or not, opens with
    /// no request; otherwise the live body, exactly as without the cache,
    /// and one background fetch for the next open, started only once the
    /// mounted body's own web-view load has ended (never alongside it). A
    /// blocked card cancels and fetches nothing.
    private func remoteImagesDecisionChanged(id: String, allowed: Bool, bodyMounted: Bool) {
        let cidInlined = cidInlinedHTMLById[id] != nil
        let prep = cidInlined ? cidPrepByMessageId[id] : bodyPrepByMessageId[id]
        let step = remotePane.step(
            id: id, allowRemoteImages: allowed, bodyMounted: bodyMounted,
            candidateCount: prep?.remoteImageCount ?? 0,
            cidResolveInFlight: cidResolveInFlight.contains(id),
            cidInlined: cidInlined, remoteBody: remoteBodyById[id])
        switch step {
        case .cancel:
            remoteResolveTasks.removeValue(forKey: id)?.cancel()
        case .nothing:
            break
        case .markCachedUsed:
            store.noteCachedRemoteImagesShown(messageIds: [id])
        case .checkCache(let baseIsCID):
            startCacheRead(id: id, baseIsCID: baseIsCID, isCheck: true)
        case .rebuildFromCache(let baseIsCID):
            startCacheRead(id: id, baseIsCID: baseIsCID, isCheck: false)
        case .fetchForNextOpen(let baseIsCID):
            startFetchForNextOpen(id: id, baseIsCID: baseIsCID)
        }
    }

    private struct RemoteWork {
        let base: String
        let preInlineBytes: Int
        let accountId: String
    }

    private func remoteWork(id: String, baseIsCID: Bool) -> RemoteWork? {
        guard let msg = messages.first(where: { $0.id == id }),
              let rawHTML = msg.bodyHTML, !rawHTML.isEmpty else { return nil }
        let base = (baseIsCID ? cidInlinedHTMLById[id] : nil) ?? rawHTML
        let prep = baseIsCID ? cidPrepByMessageId[id] : bodyPrepByMessageId[id]
        return RemoteWork(base: base, preInlineBytes: prep?.htmlBytes ?? rawHTML.utf8.count,
                          accountId: msg.accountId)
    }

    /// The cache check before the first paint (`isCheck`), bounded by
    /// `RemoteImagePaneState.checkDeadline`, or a rebuild of a complete
    /// cache for a newer base. Records the result; starts nothing else.
    private func startCacheRead(id: String, baseIsCID: Bool, isCheck: Bool) {
        guard let work = remoteWork(id: id, baseIsCID: baseIsCID) else {
            if isCheck { _ = remotePane.checkFinished(id, complete: false) }
            return
        }
        let scale = fontScale
        let revision = store.contentRevision(of: thread.id)
        let threadId = thread.id
        let imageStore = store.remoteImageStore
        remoteResolveTasks[id]?.cancel()
        let checkInterval = isCheck ? PerfMetrics.begin(.openRemoteCheck) : nil
        if isCheck {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(RemoteImagePaneState.checkDeadline * 1e9))
                await MainActor.run {
                    guard thread.id == threadId else { return }
                    remotePane.checkTimedOut(id)
                }
            }
        }
        remoteResolveTasks[id] = Task {
            let body = await RemoteImageResolver.cachedBody(
                messageId: id, accountId: work.accountId, baseHTML: work.base,
                preInlineBytes: work.preInlineBytes, baseIsCIDInlined: baseIsCID,
                fontScale: scale, store: imageStore)
            await MainActor.run {
                guard !Task.isCancelled, thread.id == threadId else {
                    checkInterval?.end(extraMeta: "cancelled")
                    return
                }
                remoteResolveTasks.removeValue(forKey: id)
                let showNow = isCheck ? remotePane.checkFinished(id, complete: body != nil) : true
                checkInterval?.end(extraMeta: "complete=\(body != nil ? 1 : 0) late=\(showNow ? 0 : 1)")
                guard let body else { return }
                if showNow { remoteBodyById[id] = body }
                // Past the deadline: kept for the next open only.
                store.rememberRemoteInline(body, messageId: id, threadId: threadId,
                                           revision: revision)
            }
        }
    }

    /// The live body is on screen: fetch the cacheable images for the next
    /// open. The open is never changed; the next open's body is kept with
    /// the payload.
    private func startFetchForNextOpen(id: String, baseIsCID: Bool) {
        guard let work = remoteWork(id: id, baseIsCID: baseIsCID) else { return }
        let scale = fontScale
        let revision = store.contentRevision(of: thread.id)
        let threadId = thread.id
        let imageStore = store.remoteImageStore
        let transport = store.remoteImageTransport
        remoteResolveTasks[id]?.cancel()
        remoteResolveTasks[id] = Task {
            let next = await RemoteImageResolver.fetchForNextOpen(
                messageId: id, accountId: work.accountId, baseHTML: work.base,
                preInlineBytes: work.preInlineBytes, baseIsCIDInlined: baseIsCID,
                fontScale: scale, store: imageStore, transport: transport,
                reportFailures: { failures, attempted in
                    DiagnosticLog.remoteImageFetch(failures: failures, attempted: attempted)
                })
            await MainActor.run {
                // A cancelled task's slot may already hold a newer one.
                guard !Task.isCancelled else { return }
                remoteResolveTasks.removeValue(forKey: id)
                guard let next else { return }
                store.rememberRemoteInline(next, messageId: id, threadId: threadId,
                                           revision: revision)
            }
        }
    }

    /// Mount a freshly loaded (or mirrored) payload. Shared by the synchronous
    /// warm path and the awaited fallback so both land identical state.
    private func applyDetailPayload(_ payload: ThreadDetailPayload,
                                    proxy: ScrollViewProxy) {
        let loaded = payload.messages
        // Newest sent + draft cards arrive hydrated; seed so we don't
        // re-query. Shared with refreshMessages' empty→full path.
        bodyLoadAttempted.formUnion(ThreadRefresh.initialBodyLoadSeedIds(in: loaded, threadUnread: thread.isUnread))
        messages = loaded
        attachmentsByMessageId = payload.attachmentsByMessageId
        bodyPrepByMessageId = payload.bodyPrepByMessageId
        applyDeletedSummary(payload.deletedSummary)
        // `cid:` images this session already resolved: paint them in the
        // first frame and mark them attempted, so the open makes no
        // attachment request and does not load the body a second time.
        let cidSeed = CIDInlineSeed.seed(from: payload, fontScale: fontScale)
        if !cidSeed.resolvedIds.isEmpty {
            cidInlinedHTMLById = cidSeed.htmlById
            cidPrepByMessageId = cidSeed.prepById
            cidResolveAttempted.formUnion(cidSeed.resolvedIds)
        }
        // Remote images already in the encrypted cache (the prefetch built
        // these from the cache only): the card shows them in its first frame
        // when its own decision allows remote images, and only on the base it
        // was built from.
        let warmRemote = payload.remoteInlineByMessageId.filter { id, body in
            body.baseIsCIDInlined == (cidSeed.htmlById[id] != nil)
                && RemoteInlineCachePolicy.shouldRemember(body, fontScale: fontScale)
        }
        // What this session already resolved stays.
        remoteBodyById.merge(warmRemote) { current, _ in current }
        threadAttachments = ThreadRefresh.threadAttachments(in: payload)
        // Anchor on newest sent when multi-message; draft-only falls back to
        // the last row so a pure-draft pane still positions.
        applyScrollAnchor(
            ThreadRefresh.initialScrolledMessageId(in: messages, threadUnread: thread.isUnread),
            proxy: proxy)
        if inlineComposeActive {
            beginInlineComposeScroll(proxy: proxy)
        }
        // Open the policy's default card set (newest only, or every sent card
        // in side-by-side) and hydrate bodies + CID/attachment recovery.
        seedExpandedMessagesIfNeeded()
        for id in expandedMessageIds {
            recoverAttachmentsIfNeeded(id: id)
            resolveCIDImagesIfNeeded(id: id)
        }
        backfillUnsubscribeHeaders()
    }

    /// Pre-v37 rows have nil List-Unsubscribe. Fill the newest few so the
    /// Gmail-style control appears without a full resync.
    private func backfillUnsubscribeHeaders() {
        let stale = messages
            .filter { $0.listUnsubscribe == nil }
            .sorted { $0.date > $1.date }
            .prefix(3)
        for msg in stale {
            Task { await refreshUnsubscribeHeaders(msg) }
        }
    }

    private func refreshUnsubscribeHeaders(_ message: Message) async {
        guard message.listUnsubscribe == nil else { return }
        guard !unsubscribeRefreshAttempted.contains(message.id) else { return }
        unsubscribeRefreshAttempted.insert(message.id)
        guard let headers = await store.refreshUnsubscribeHeaders(message) else { return }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[idx].listUnsubscribe = headers.0
        messages[idx].listUnsubscribePost = headers.1
        // Pre-v43 rows: Reply reads this (ReplyRecipients).
        messages[idx].replyToHeader = headers.replyTo
        // Pre-v47 rows: the "delivered to" row reads this (DeliveredAddress).
        messages[idx].deliveredTo = headers.deliveredTo
    }

    /// After the open body's first stable paint, warm prev/next newest-message
    /// HTML into pooled WebViews (using payloads already in the detail LRU
    /// when neighbor prefetch has finished).
    private func armNeighborPrerenderIfNeeded() {
        guard !neighborPrerenderArmed else { return }
        guard splitMode || store.openedThreadId == thread.id else { return }
        neighborPrerenderArmed = true
        let order = store.displayOrder.isEmpty
            ? store.threads.map(\.id)
            : store.displayOrder
        let scale = fontScale
        // Pre-render paints the blocked variant only (no remote request for
        // mail the user has not opened). A neighbour whose open would load
        // images could never claim that view, so it is skipped rather than
        // painted and thrown away. Same decision the card makes, minus the
        // opt-ins (they reset per conversation).
        let policy = RemoteImagePolicy.stored()
        let vipEmails = store.vipEmails
        HTMLBodyNeighborPrerender.schedule(
            openedThreadId: thread.id,
            displayOrder: order,
            fontScale: scale,
            loadPayload: { [store] threadId in
                await store.threadDetailPayload(threadId: threadId).payload
            },
            opensWithRemoteImages: { [store] threadId, message in
                RemoteImagePolicy.autoLoads(
                    message: message,
                    threadInSpam: store.thread(withId: threadId)?.inSpam ?? false,
                    policy: policy,
                    vipEmails: vipEmails)
            })
    }

    /// Meta row under the subject: an attachments menu
    /// (every file in the thread, one click to Quick Look), removable
    /// category chips (Gmail categories, Important, and user labels), and
    /// "Add category" opening the label picker.
    private var threadMetaRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if !threadAttachments.isEmpty {
                    Menu {
                        ForEach(threadAttachments, id: \.attachment.displayIdentity) { pair in
                            Button {
                                store.quickLookAttachment(pair.attachment, message: pair.message)
                            } label: {
                                Label(pair.attachment.filename, systemImage: "doc")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 11 * fontScale))
                            Text(threadAttachments.count == 1
                                 ? "1 attachment"
                                 : "\(threadAttachments.count) attachments")
                                .font(.system(size: 12 * fontScale))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Attachments in this thread — click to Quick Look")
                }
                ForEach(categoryChipItems, id: \.id) { chip in
                    if let colors = chip.colors {
                        // User label: solid pill in its Gmail color, the
                        // remove button in the pill's own text color.
                        LabelPill(name: chip.name, colors: colors,
                                  fontSize: 11.5 * fontScale) {
                            removeChipButton(chip.id, name: chip.name)
                        }
                    } else {
                        // Same geometry as the label chips beside it.
                        let chipMetrics = LabelChipMetrics(fontSize: 11.5 * fontScale)
                        HStack(spacing: 4) {
                            Text(chip.name)
                                .font(.system(size: 11.5 * fontScale, weight: .medium))
                            removeChipButton(chip.id, name: chip.name)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, chipMetrics.horizontalPadding)
                        .frame(minHeight: chipMetrics.height)
                        .background(Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: chipMetrics.cornerRadius,
                                                         style: .continuous))
                    }
                }
                Button {
                    store.openLabelPicker()
                } label: {
                    Text("Add category")
                        .font(.system(size: 12 * fontScale))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Label this thread (\(store.keyBindings.displayKey(for: .label)))")
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
        }
    }

    private func removeChipButton(_ labelId: String, name: String) -> some View {
        Button {
            store.toggleLabel(thread, labelId: labelId)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .pmHitTarget(extra: 8)
        }
        .buttonStyle(PressScaleButtonStyle())
        .help("Remove \(name)")
    }

    /// Everything categorizing this thread: Gmail's own
    /// classification (Important, Updates, …) plus the user's labels, all
    /// removable in place. User labels carry their display colors.
    private var categoryChipItems: [(id: String, name: String, colors: LabelColors?)] {
        var items: [(id: String, name: String, colors: LabelColors?)] = []
        for label in thread.labels {
            if label == "IMPORTANT" {
                items.append((label, "Important", nil))
            } else if label.hasPrefix("CATEGORY_"), label != "CATEGORY_PERSONAL",
                      CategoryRows.showsChip(
                        label: label, accountOn: store.showsPromotionsAndSocial(thread.accountId)) {
                items.append((label, String(label.dropFirst("CATEGORY_".count)).capitalized, nil))
            }
        }
        for labelId in userLabelIds {
            let name = store.labelName(labelId, account: thread.accountId) ?? labelId
            items.append((labelId, name, store.labelColors(name, account: thread.accountId)))
        }
        return items
    }

    /// A compact brief at the point of reading. Cached text stays visible when
    /// new mail arrives, with a freshness cue and a refresh action.
    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summaryEligible || persistedSummary != nil || aiSummary != nil {
                if let text = aiSummary ?? persistedSummary?.summary {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11 * fontScale))
                                .foregroundStyle(.accentForeground)
                            Text(text)
                                .font(.system(size: 12.5 * fontScale))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: 8) {
                            if summarizing {
                                ProgressView().controlSize(.mini)
                                Text("Summarizing…")
                            } else if let row = persistedSummary, aiSummary == nil {
                                Text(summaryFreshnessLabel(row))
                            } else {
                                Text("Thread summary")
                            }
                            Spacer(minLength: 8)
                            if summarizing {
                                Button("Stop") { cancelSummary() }
                                    .buttonStyle(.plain)
                            } else {
                                Button("Refresh") { summarizeThread() }
                                    .buttonStyle(.plain)
                                    .help("Update the summary and next action from the current conversation")
                                    .accessibilityIdentifier("thread.summaryRefresh")
                            }
                        }
                        .font(.system(size: 10.5 * fontScale))
                        .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.accentFill.opacity(0.08), in: RoundedRectangle(cornerRadius: PMRadius.md))
                    .accessibilityIdentifier("thread.summary")
                } else {
                    HStack(spacing: 8) {
                    Button { summarizeThread() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: summarizing ? "hourglass" : "sparkles")
                            Text(summarizing ? "Summarizing…" : "Summarize with AI")
                        }
                        .font(.system(size: 11 * fontScale))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(summarizing)
                    .help("Generate an AI TL;DR of this thread")
                    .accessibilityIdentifier("thread.summarize")
                    if summarizing {
                        Button("Stop") { cancelSummary() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11 * fontScale))
                            .foregroundStyle(.secondary)
                    }
                    }
                }
                if let summaryError {
                    Text(summaryError)
                        .font(.system(size: 11 * fontScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .task(id: summaryFingerprint) {
            if summarySourceFingerprint != summaryFingerprint {
                cancelSummary()
                aiSummary = nil
                summaryError = nil
            }
            await loadPersistedSummary()
            guard !Task.isCancelled, !summarizing,
                  let resolved = LLMTaskRunner.resolve(.summaries),
                  ThreadSummaryPolicy.shouldAutoSummarize(
                    messages: messages, config: resolved.config, model: resolved.model,
                    enabled: autoSummarizeLocal),
                  persistedSummary.map({ !ThreadSummaryPolicy.isCurrent($0, fingerprint: summaryFingerprint) }) ?? true
            else { return }
            summarizeThread(quiet: true)
        }
    }

    private func summaryFreshnessLabel(_ row: ThreadSummaryRow) -> String {
        if ThreadSummaryPolicy.isCurrent(row, fingerprint: summaryFingerprint) {
            return "\(row.model) · \(row.updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return row.contentFingerprint == nil
            ? "Refresh to verify this summary" : "New messages since this summary"
    }

    private func cancelSummary() {
        if summarizing { aiSummary = nil }
        summaryRequestId = nil
        summaryTask?.cancel()
        summaryTask = nil
    }

    private func loadPersistedSummary() async {
        let id = thread.id
        let fingerprint = summaryFingerprint
        let row = try? await AppDatabase.shared.dbPool.read { db in
            try ThreadSummaryRow.fetchOne(db, key: id)
        }
        await MainActor.run {
            guard !Task.isCancelled, thread.id == id, summaryFingerprint == fingerprint else { return }
            persistedSummary = row
        }
    }

    private func summarizeThread(quiet: Bool = false) {
        guard !summarizing, !summaryFingerprint.isEmpty,
              !store.opensTrashReader(threadId: thread.id) else { return }
        summaryError = nil
        aiSummary = nil
        let fingerprint = summaryFingerprint
        summarySourceFingerprint = fingerprint
        // Summary needs full bodies; hydrate anything still header-only.
        let sent = ThreadSummaryPolicy.sentMessages(messages)
        let ids = sent.map(\.id)
        let fullById = Dictionary(uniqueKeysWithValues:
            store.messagesWithBodies(ids: ids).map { ($0.id, $0) })
        let fullMessages = sent.map { fullById[$0.id] ?? $0 }
        let hasMissingBodies = fullMessages.contains {
            ThreadRefresh.needsBodyLoad($0) && !$0.snippet.isEmpty
        }
        let resolved = LLMTaskRunner.resolve(.summaries)
        let budget = resolved?.config.kind == .ollama
            ? LLMPrompts.localThreadContextBudget
            : LLMPrompts.hostedThreadContextBudget
        let body = LLMPrompts.threadContext(
            subject: thread.subject, messages: fullMessages, characterBudget: budget)
        let prompt = LLMPrompts.summarize(subject: thread.subject, body: body,
                                        userEmail: thread.accountId)
        let requestId = UUID()
        summaryRequestId = requestId
        summaryTask = Task { @MainActor in
            defer {
                if summaryRequestId == requestId {
                    summaryRequestId = nil
                    summaryTask = nil
                }
            }
            var accumulated = ""
            do {
                for try await piece in LLMTaskRunner.stream(
                    task: .summaries, prompt: prompt, using: resolved,
                    onNotice: { notice in
                        if summaryRequestId == requestId { summaryError = notice }
                    }) {
                    guard !Task.isCancelled, summaryRequestId == requestId,
                          summaryFingerprint == fingerprint else { return }
                    accumulated += piece
                    aiSummary = accumulated
                }
                guard !Task.isCancelled, summaryRequestId == requestId,
                      summaryFingerprint == fingerprint else { return }
                let text = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty, summaryError == nil {
                    summaryError = "No summary was produced."
                    aiSummary = nil
                } else if hasMissingBodies, summaryError == nil {
                    summaryError = "Some message bodies are unavailable. This summary uses previews; refresh after mail loads."
                } else if summaryError == nil {
                    let row = ThreadSummaryRow(threadId: thread.id, summary: text,
                                               model: resolved?.model ?? "AI", updatedAt: Date(),
                                               contentFingerprint: fingerprint)
                    // Check the source again in the same transaction as the
                    // cache write: sync may land before this view refreshes.
                    do {
                        let saved = try await AppDatabase.shared.dbPool.write { db -> Bool in
                            guard let current = try MailThread.fetchOne(db, key: row.threadId) else { return false }
                            let headers = try Message.filter(Column("threadId") == row.threadId).fetchAll(db)
                            guard ThreadSummaryPolicy.fingerprint(subject: current.subject, messages: headers)
                                    == fingerprint else { return false }
                            try row.save(db)
                            return true
                        }
                        guard !Task.isCancelled, summaryRequestId == requestId else { return }
                        if saved {
                            persistedSummary = row
                            aiSummary = nil
                        } else {
                            aiSummary = nil
                            summaryError = "The conversation changed. Refresh the summary."
                        }
                    } catch {
                        guard !Task.isCancelled, summaryRequestId == requestId else { return }
                        summaryError = "Summary is shown, but couldn't be saved for next time."
                    }
                }
            } catch {
                guard !Task.isCancelled, summaryRequestId == requestId else { return }
                aiSummary = nil
                if !quiet { summaryError = LLMTaskRunner.errorMessage(error, task: .summaries) }
            }
            if quiet, summaryError != nil {
                aiSummary = nil
                summaryError = nil
            }
        }
    }

    /// User-created labels on this thread (system labels stay hidden).
    private var userLabelIds: [String] {
        let known = Set(store.userLabels(forAccount: thread.accountId).map(\.gmailLabelId))
        return thread.labels.filter { known.contains($0) }.sorted {
            (store.labelName($0, account: thread.accountId) ?? $0)
                < (store.labelName($1, account: thread.accountId) ?? $1)
        }
    }

    // MARK: - Share (Markdown)

    /// Hydrate every body so export is complete even for collapsed cards.
    private func messagesForExport() -> [Message] {
        let ids = messages.map(\.id)
        let fullById = Dictionary(uniqueKeysWithValues:
            store.messagesWithBodies(ids: ids).map { ($0.id, $0) })
        return messages.map { fullById[$0.id] ?? $0 }
    }

    private func exportMarkdown() -> String {
        let full = messagesForExport()
        let refs = threadAttachments.map {
            ThreadExporter.AttachmentRef(
                messageId: $0.message.id, filename: $0.attachment.filename)
        }
        return ThreadExporter.markdown(
            subject: thread.subject, messages: full, attachments: refs)
    }

    private func copyThreadAsMarkdown() {
        let md = exportMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private func saveThreadAsMarkdown() {
        let md = exportMarkdown()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        // UTType for markdown if available — fall back stays .md via nameField.
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType, .plainText]
        }
        panel.nameFieldStringValue = ThreadExporter.suggestedFilename(
            subject: thread.subject, date: thread.lastDate)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Keep the export: clipboard fallback + tell the user what happened.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(md, forType: .string)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't save the file"
                    alert.informativeText =
                        "\(error.localizedDescription)\n\nThe Markdown was copied to the clipboard instead."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}

/// Saved Gmail draft rendered in the thread — not a regular MessageCard.
///
/// Gmail-style cues: orange "Draft" pill, warm tint, left accent, compact
/// authored preview (no HTML quote trail / "…" gap), and Continue/Discard
/// actions on the card itself so edit isn't only at the top of the pane.
struct DraftMessageCard: View {
    @Environment(MailStore.self) var store
    @AppStorage("fontScale") private var fontScale = 1.0
    let message: Message
    let onNeedBody: () -> Void

    private var preview: String {
        QuotedReply.authoredPreview(text: message.bodyText, html: message.bodyHTML)
    }

    private var toSummary: String {
        let names = MessageParser.splitAddresses(message.toHeader)
            .map { store.participantDisplayName(fromHeader: $0) }
            .filter { !$0.isEmpty }
        if names.isEmpty { return "No recipients" }
        if names.count == 1 { return "To \(names[0])" }
        return "To \(names[0]) +\(names.count - 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tap-to-edit on chrome + preview only. Buttons sit outside the
            // gesture so Discard isn't stolen by editDraft on macOS (a parent
            // onTapGesture over Buttons often wins the hit test).
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Draft")
                        .font(.system(size: 11 * fontScale, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                    Text("Not sent")
                        .font(.system(size: 12 * fontScale, weight: .medium))
                        .foregroundStyle(Color.orange)
                    Spacer(minLength: 8)
                    Text(message.date, format: message.date.messageHeaderFormat)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    // Sender/recipient chrome is muted like the preview: a draft
                    // is not a message in the conversation, so it must not read
                    // with a sent card's primary-text weight.
                    Text(store.participantDisplayName(fromHeader: message.fromHeader))
                        .font(.system(size: 13.5 * fontScale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(toSummary)
                        .font(.system(size: 12.5 * fontScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if ThreadDetailView.needsBodyLoad(message) {
                    Text("Loading draft…")
                        .font(.system(size: 13.5 * fontScale))
                        .foregroundStyle(.secondary)
                } else if preview.isEmpty {
                    Text("Empty draft — click Continue to write")
                        .font(.system(size: 13.5 * fontScale))
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    // No textSelection: preview is tap-to-edit, so a selection
                    // gesture would fight the hit target.
                    Text(preview)
                        .font(.system(size: 14 * fontScale))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { store.editDraft(message) }

            HStack(spacing: 8) {
                Button {
                    store.editDraft(message)
                } label: {
                    Label("Continue", systemImage: "pencil")
                        .font(.system(size: 12.5 * fontScale))
                }
                .buttonStyle(.borderedProminent)
                .help("Continue editing this draft")
                Button(role: .destructive) {
                    store.confirmingDraftDelete = message
                } label: {
                    Text("Discard")
                        .font(.system(size: 12.5 * fontScale))
                }
                .buttonStyle(.bordered)
                .help("Delete this draft")
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .padding(.leading, 4) // room for the accent bar inside the card
        .background(
            RoundedRectangle(cornerRadius: PMRadius.md)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(alignment: .leading) {
            // Gmail-ish draft accent: solid orange rail, not a full red banner.
            UnevenRoundedRectangle(
                topLeadingRadius: PMRadius.md,
                bottomLeadingRadius: PMRadius.md,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(Color.orange)
            .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: PMRadius.md)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .pmCardElevation(cornerRadius: PMRadius.md)
        .pmPointingHandCursor()
        .onAppear { onNeedBody() }
        .help("Continue editing this draft")
    }
}

struct MessageCard: View {
    @Environment(MailStore.self) var store
    @AppStorage("fontScale") private var fontScale = 1.0
    /// Settings → Appearance. Unset follows `RemoteImagePolicy.defaultPolicy`.
    @AppStorage(RemoteImagePolicy.defaultsKey) private var remoteImagePolicyRaw =
        RemoteImagePolicy.defaultPolicy.rawValue
    let message: Message
    let isLast: Bool
    let attachments: [AttachmentRow]
    /// Off-main precomputed trail + assembled documents from the repository.
    let bodyPrep: MessageHTMLPrep?
    /// Session-only body with `cid:` images rewritten to `data:` URIs.
    /// When set, preferred over `message.bodyHTML` / repository docs.
    let cidInlinedHTML: String?
    /// Off-main prep for `cidInlinedHTML` (trail, pre-inline byte gate,
    /// documents). Set together with `cidInlinedHTML` by the parent.
    let cidPrep: MessageHTMLPrep?
    /// The body with every cacheable remote image from the encrypted cache.
    /// Used only while this card's own decision allows remote images
    /// (`RemoteImageRendering.choice`).
    let remoteBody: RemoteInlinedBody?
    /// The pane's cache check for this message (`RemoteImagePaneState`):
    /// until it settles (at most `checkDeadline`) a card whose images are
    /// allowed and that has cacheable images does not paint its body, so it
    /// never loads live first and then again from the cache.
    let remoteCheck: RemoteImagePaneState.Check?
    /// Single-active reading pane vs multi-open side-by-side compose.
    let expandPolicy: MessageExpandPolicy
    @Binding var expandedMessageIds: Set<String>
    /// False for the sole message of a conversation: always open, no chevron.
    let isCollapsible: Bool
    /// Pane height to fill while the HTML body has not measured itself;
    /// nil for cards that do not fill the pane.
    let fillsPaneHeight: CGFloat?
    /// Session-wide opt-in shared by every card in the open thread.
    @Binding var loadImagesForThread: Bool
    /// The thread row's Spam flag: written optimistically when the user
    /// marks spam, before this message's own labels catch up.
    let threadInSpam: Bool
    /// A deleted message of a live conversation, shown after "View": tagged
    /// "In Trash" and muted; "Restore" (`onRestore`) is its only action.
    let inTrash: Bool
    let onReply: () -> Void
    let onRestore: () -> Void
    /// Parent owns the confirmation dialog for sender blocking.
    let onBlockSender: (String) -> Void
    /// Parent loads the body when a collapsed header-only card expands.
    let onNeedBody: () -> Void
    /// The card's remote-image decision, each time it or the base changes
    /// and false when the body leaves: the parent resolves (cache, then the
    /// app's fetch) only while it is true, and cancels otherwise.
    /// (allowed, the HTML body view is mounted).
    let onRemoteImagesDecision: (Bool, Bool) -> Void
    /// Parent arms neighbor HTML pre-render after this card's body settles.
    let onBodySettled: () -> Void
    /// Parent shows the Gmail-style unsubscribe confirm for this message.
    let onUnsubscribe: () -> Void
    /// Parent fills List-Unsubscribe on pre-v37 rows (nil).
    let onNeedUnsubscribeHeaders: () -> Void
    /// "Mark as unread": the parent knows the later messages.
    let onMarkUnreadFromHere: () -> Void
    /// The sheet a "More" item opened: the filter editor ("Filter messages
    /// like this", from this sender) or "Show original".
    private enum MenuSheet: Identifiable {
        case filter(GmailFilterEditTarget)
        case original
        var id: String {
            switch self {
            case .filter(let target): return target.id.uuidString
            case .original: return "original"
            }
        }
    }
    @State private var menuSheet: MenuSheet?
    // Full FROM/TO/CC rows ("Show more"); compact by default.
    @State private var recipientsExpanded = false
    /// Last height the HTML body reported for this card; nil until the
    /// first report (see `MessageBodyHeight`).
    @State private var measuredHTMLHeight: CGFloat?
    /// Set by the first height report. Only a body's first load reserves the
    /// pane; a later reload (quote toggle) starts from its cached height.
    @State private var htmlBodyEverMeasured = false
    /// Load key (content id, CSP variant, font scale) of the body document
    /// whose web-view load has ended (`HTMLBodyView.onLoadFinished`): the
    /// background image fetch for the next open starts only then, never
    /// alongside the web view's own loads. Cleared when the body leaves, so
    /// a re-expanded card waits for its new load.
    @State private var loadFinishedKey: HTMLBodyLoadKey?
    /// Offset of the body from the card's top (header and banners), so the
    /// reservation makes the card, not just its body, end at the pane bottom.
    @State private var bodyTopInCard: CGFloat = 0
    /// The row's width, for the date's narrow-pane rule; nil until measured.
    @State private var rowWidth: CGFloat?
    private static let cardSpace = "messageCard"
    private static let exposesRowFrame =
        ProcessInfo.processInfo.environment["DREAMAIL_UI_TEST"] == "1"
    /// Per-message opt-in when policy is ask/vip and the sender isn't allowed.
    @State private var loadRemoteImages = false
    /// Manual escape hatch: render multipart plain text instead of HTML.
    /// Useful for privacy-sensitive transactional mail when remote images are
    /// blocked and the HTML shell is unreadable — not an automatic switch.
    @State private var showPlainText = false
    /// Giant HTML bodies require an explicit click before WebKit receives the
    /// full document. This stays scoped to the card/session.
    @State private var approvedOversizedHTML = false
    // The quoted reply trail below the new text stays collapsed behind a "…"
    // pill (Gmail-style) on every message — threads repeat their history in
    // each body, so showing it all drowns the actual message.
    @State private var showQuoted = false
    /// The authored text above a plain-text quoted trail; nil when there is
    /// nothing to collapse (always nil for HTML bodies).
    private let textHead: String?
    /// Raw authored HTML above a structured quote container. Loading this
    /// instead of hiding the full trail with CSS avoids parsing repeated mail.
    private let htmlHead: String?
    private let htmlBytes: Int
    private let htmlHeadBytes: Int
    /// Whether this message carries a collapsible quoted trail — HTML bodies
    /// load only `htmlHead`, plain text renders `textHead`.
    private let hasQuotedTrail: Bool
    /// Pre-assembled WebKit documents (nil when scale mismatched or absent).
    private let htmlDocuments: MessageHTMLDocuments?

    /// Fallback NSCache for cards opened without a repository prep (e.g. rare
    /// main-thread-only paths). Primary path is `bodyPrep` from the actor.
    private final class TrailCacheEntry {
        let textHead: String?
        let htmlHead: String?
        let hasTrail: Bool
        let htmlBytes: Int
        let htmlHeadBytes: Int

        init(textHead: String?, htmlHead: String?, hasTrail: Bool,
             htmlBytes: Int, htmlHeadBytes: Int) {
            self.textHead = textHead
            self.htmlHead = htmlHead
            self.hasTrail = hasTrail
            self.htmlBytes = htmlBytes
            self.htmlHeadBytes = htmlHeadBytes
        }

        var cacheCost: Int {
            htmlHeadBytes + (textHead?.utf8.count ?? 0)
        }
    }

    private static let maximumTrailCacheCost = 2 * 1_024 * 1_024
    private static let maximumTrailCacheEntries = 128
    private static let trailCache: NSCache<NSString, TrailCacheEntry> = {
        let cache = NSCache<NSString, TrailCacheEntry>()
        cache.countLimit = maximumTrailCacheEntries
        cache.totalCostLimit = maximumTrailCacheCost
        return cache
    }()

    private static func cacheTrail(_ entry: TrailCacheEntry, for id: String) {
        guard entry.cacheCost <= maximumTrailCacheCost else { return }
        trailCache.setObject(entry, forKey: id as NSString, cost: entry.cacheCost)
    }

    init(message: Message, isLast: Bool,
         attachments: [AttachmentRow] = [],
         bodyPrep: MessageHTMLPrep? = nil,
         cidInlinedHTML: String? = nil,
         cidPrep: MessageHTMLPrep? = nil,
         remoteBody: RemoteInlinedBody? = nil,
         remoteCheck: RemoteImagePaneState.Check? = .incomplete,
         expandPolicy: MessageExpandPolicy = .single,
         expandedMessageIds: Binding<Set<String>>,
         isCollapsible: Bool = true,
         fillsPaneHeight: CGFloat? = nil,
         loadImagesForThread: Binding<Bool> = .constant(false),
         threadInSpam: Bool = false,
         inTrash: Bool = false,
         onReply: @escaping () -> Void,
         onRestore: @escaping () -> Void = {},
         onBlockSender: @escaping (String) -> Void = { _ in },
         onNeedBody: @escaping () -> Void = {},
         onRemoteImagesDecision: @escaping (Bool, Bool) -> Void = { _, _ in },
         onBodySettled: @escaping () -> Void = {},
         onUnsubscribe: @escaping () -> Void = {},
         onNeedUnsubscribeHeaders: @escaping () -> Void = {},
         onMarkUnreadFromHere: @escaping () -> Void = {}) {
        self.message = message
        self.isLast = isLast
        self.attachments = attachments
        self.bodyPrep = bodyPrep
        self.cidInlinedHTML = cidInlinedHTML
        self.cidPrep = cidPrep
        self.remoteBody = remoteBody
        self.remoteCheck = remoteCheck
        self.expandPolicy = expandPolicy
        self._expandedMessageIds = expandedMessageIds
        self.isCollapsible = isCollapsible
        self.fillsPaneHeight = fillsPaneHeight
        self._loadImagesForThread = loadImagesForThread
        self.threadInSpam = threadInSpam
        self.inTrash = inTrash
        self.onReply = onReply
        self.onRestore = onRestore
        self.onBlockSender = onBlockSender
        self.onNeedBody = onNeedBody
        self.onRemoteImagesDecision = onRemoteImagesDecision
        self.onBodySettled = onBodySettled
        self.onUnsubscribe = onUnsubscribe
        self.onNeedUnsubscribeHeaders = onNeedUnsubscribeHeaders
        self.onMarkUnreadFromHere = onMarkUnreadFromHere
        let hasBody = !ThreadDetailView.needsBodyLoad(message)
        // CID-inlined HTML already embeds image bytes; prefer its prep over
        // the repository prep (which still has unresolved `cid:`). The parent
        // built it off-main — init runs on every parent body pass, so the
        // multi-MB quote scan that used to live here must not.
        if hasBody, let inlined = cidInlinedHTML, !inlined.isEmpty {
            let prep = cidPrep ?? .empty
            textHead = nil
            htmlHead = prep.htmlHead
            hasQuotedTrail = prep.hasQuotedTrail
            // Pre-inline size (see `MessageHTMLPrepBuilder.cidInlinedPrep`).
            htmlBytes = prep.htmlBytes
            htmlHeadBytes = prep.htmlHeadBytes
            htmlDocuments = prep.documents
        } else if hasBody, let prep = bodyPrep {
            textHead = prep.textHead
            htmlHead = prep.htmlHead
            hasQuotedTrail = prep.hasQuotedTrail
            htmlBytes = prep.htmlBytes
            htmlHeadBytes = prep.htmlHeadBytes
            htmlDocuments = prep.documents
        } else if hasBody, let cached = Self.trailCache.object(forKey: message.id as NSString) {
            textHead = cached.textHead
            htmlHead = cached.htmlHead
            hasQuotedTrail = cached.hasTrail
            htmlBytes = cached.htmlBytes
            htmlHeadBytes = cached.htmlHeadBytes
            htmlDocuments = nil
        } else if hasBody {
            let fullHTMLBytes = message.bodyHTML?.utf8.count ?? 0
            // Prefer structured HTML collapse (gmail_quote / cite). When HTML
            // has no marker but plain text still has a `>` / "On … wrote:"
            // trail, keep a text head so "…" can hide it (some clients ship
            // nested history as plain `>` lines inside a single HTML div).
            // Giant bodies skip all whole-body trail scans and go straight to
            // the explicit-load placeholder; scanning them on the main actor
            // would defeat the guard before WebKit even mounts.
            let detectedHTMLHead: String? = {
                guard let html = message.bodyHTML, !html.isEmpty else { return nil }
                if fullHTMLBytes <= HTMLBodyRenderPolicy.maximumAutomaticBytes {
                    return QuotedReply.authoredHTMLHead(html)
                }
                return QuotedReply.authoredHTMLHead(
                    html,
                    scanCharacterLimit: HTMLBodyRenderPolicy.oversizedQuoteScanCharacterLimit)
            }()
            if let head = detectedHTMLHead {
                textHead = nil
                htmlHead = head
                hasQuotedTrail = true
            } else if fullHTMLBytes <= HTMLBodyRenderPolicy.maximumAutomaticBytes,
                      let head = QuotedReply.splitText(message.bodyText)?.head {
                textHead = head
                htmlHead = nil
                hasQuotedTrail = true
            } else {
                textHead = nil
                htmlHead = nil
                hasQuotedTrail = false
            }
            htmlBytes = fullHTMLBytes
            htmlHeadBytes = htmlHead?.utf8.count ?? 0
            htmlDocuments = nil
            Self.cacheTrail(TrailCacheEntry(
                textHead: textHead,
                htmlHead: htmlHead,
                hasTrail: hasQuotedTrail,
                htmlBytes: htmlBytes,
                htmlHeadBytes: htmlHeadBytes), for: message.id)
        } else {
            textHead = nil
            htmlHead = nil
            hasQuotedTrail = false
            htmlBytes = 0
            htmlHeadBytes = 0
            htmlDocuments = nil
        }
    }

    private func toggleExpanded() {
        if expanded, !isCollapsible { return }
        let willExpand = !expanded
        withAnimation(.easeOut(duration: 0.12)) {
            expandedMessageIds = expandPolicy.applyingToggle(
                id: message.id, currently: expandedMessageIds)
        }
        if willExpand { onNeedBody() }
    }

    private func expandCard() {
        if !expanded {
            withAnimation(.easeOut(duration: 0.12)) {
                expandedMessageIds = expandPolicy.applyingExpand(
                    id: message.id, currently: expandedMessageIds)
            }
            onNeedBody()
        }
    }

    private var expanded: Bool {
        expandedMessageIds.contains(message.id)
    }

    private var remoteImagePolicy: RemoteImagePolicy {
        RemoteImagePolicy.from(raw: remoteImagePolicyRaw)
    }

    /// The one pure decision (`RemoteImagePolicy.autoLoads`): policy, VIPs
    /// and their auth verdict, Spam (message or thread), and the opt-ins.
    private var allowRemoteImages: Bool {
        // OpenPGP: blocked until the message is checked, and for anything
        // encrypted (EFAIL), whatever the policy or an opt-in says.
        if store.openPGP.blocksRemoteContent(message, candidate: pgpCandidate) { return false }
        // A deleted message loads nothing by itself: only its own
        // "Load images" click (never the policy or the conversation's).
        if inTrash, !loadRemoteImages { return false }
        return RemoteImagePolicy.autoLoads(
            message: message,
            threadInSpam: threadInSpam,
            policy: remoteImagePolicy,
            vipEmails: store.vipEmails,
            messageOptIn: loadRemoteImages,
            threadOptIn: loadImagesForThread)
    }

    /// Which body this card paints for remote images
    /// (`RemoteImageRendering.choice`): the body from the cache only while
    /// images are allowed, else the body exactly as without the cache.
    private var remoteChoice: RemoteImageRendering.Choice {
        let cidInlined = cidInlinedHTML.map { !$0.isEmpty } ?? false
        let prep = cidInlined ? cidPrep : bodyPrep
        return RemoteImageRendering.choice(
            allowRemoteImages: allowRemoteImages,
            remoteBody: remoteBody,
            awaitingCacheCheck: RemoteImagePaneState.awaitsCacheCheck(
                check: remoteCheck, allowRemoteImages: allowRemoteImages,
                candidateCount: prep?.remoteImageCount ?? 0, hasRemoteBody: remoteBody != nil))
    }

    private var metrics: ThreadMessageRowMetrics {
        ThreadMessageRowMetrics(fontScale: fontScale)
    }

    private var senderName: String {
        store.participantDisplayName(fromHeader: message.fromHeader)
    }

    /// The name line's date: full, absolute or compact by the row's width
    /// (`MessageRowDateStyle`). Absolute until the row has been measured.
    private func dateText(now: Date) -> String {
        // An open message's controls share the line with the date.
        let controls = expanded && !inTrash ? metrics.headerControlsWidth(count: headerControlCount) : 0
        let style = rowWidth.map {
            MessageRowDateStyle.forTextColumn(
                width: metrics.textColumnWidth(rowWidth: $0) - controls, fontScale: fontScale)
        } ?? .absolute
        return MessageRowDate.text(message.date, style: style, now: now)
    }

    /// The account's photo for the user's own mail, else an initial disc.
    @ViewBuilder
    private var senderAvatar: some View {
        let choice = MessageAvatar.resolve(
            senderEmail: MessageParser.emailAddress(message.fromHeader),
            senderName: senderName,
            labelIds: message.labelIds,
            owners: MessageAvatar.ownerMap(
                accountIds: store.accounts.map(\.id),
                aliases: store.sendIdentities.map { (email: $0.email, accountId: $0.accountId) }),
            accountId: message.accountId,
            // The account switcher's title, so the initial matches it.
            accountNames: Dictionary(
                store.accounts.map { ($0.id, AccountLabelColor.title($0)) },
                uniquingKeysWith: { first, _ in first }),
            accountsWithPhoto: Set(store.accountPhotos.keys))
        switch choice {
        case .accountPhoto(let accountId):
            AccountAvatarView(name: senderName, key: accountId,
                              size: metrics.avatarSize,
                              photo: store.accountPhotos[accountId],
                              decorative: true)
        case .initial(let name, let key):
            AccountAvatarView(name: name, key: key, size: metrics.avatarSize,
                              decorative: true)
        }
    }

    /// Avatar, then the name line (bold sender, date on the right) and one
    /// line below it: the snippet when collapsed, the recipients when open.
    /// An open message has its controls after the date (`headerControls`).
    /// The name line is the same view in both states, so opening a message
    /// does not move its header.
    private var header: some View {
        HStack(alignment: .top, spacing: metrics.avatarGap) {
            senderAvatar
            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                HStack(alignment: .center, spacing: 8) {
                    // Sole flexible child: the name takes the width the date
                    // leaves and truncates at its tail.
                    Group {
                        if expanded {
                            participantMenu(message.fromHeader, nameSize: 14,
                                            nameWeight: .semibold)
                        } else {
                            Text(senderName)
                                .font(.system(size: metrics.nameFontSize,
                                              weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("messageSender")
                    if inTrash {
                        Text("In Trash")
                            .font(.system(size: metrics.dateFontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                            .accessibilityIdentifier("messageInTrashTag")
                    }
                    if expanded, isCollapsible {
                        // An open message collapses from a real button (the
                        // date), so Full Keyboard Access and VoiceOver reach
                        // it; a click elsewhere on the header does the same.
                        Button {
                            toggleExpanded()
                        } label: {
                            headerDate
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse")
                        .accessibilityIdentifier("messageHeaderDate")
                    } else {
                        headerDate
                            .accessibilityIdentifier("messageHeaderDate")
                    }
                    // A deleted message shown through "View" has Restore as
                    // its only action (#107): no star, reply or "More".
                    if expanded, !inTrash {
                        headerControls
                    }
                }
                if expanded {
                    expandedHeaderDetails
                } else {
                    Text(message.snippet.decodingHTMLEntities())
                        .font(.system(size: metrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("messageSnippet")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(inTrash ? 0.6 : 1)
        .padding(.leading, metrics.leadingInset)
        .padding(.trailing, metrics.trailingInset)
        .padding(.top, metrics.verticalPadding)
        .padding(.bottom, expanded ? 3 * metrics.lineSpacing : metrics.verticalPadding)
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { width in
            if width != rowWidth { rowWidth = width }
        }
        .contentShape(Rectangle())
        // Open: a click on the header collapses it (not the only message).
        .onTapGesture {
            if expanded { toggleExpanded() }
        }
        .overlay {
            // Collapsed: the whole row is one plain button, focusable from
            // the keyboard and announced by VoiceOver. An overlay rather than
            // a Button around the header, so the name, date and snippet stay
            // separate accessibility elements.
            if !expanded {
                Button {
                    expandCard()
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inTrash
                    ? "Open deleted message from \(senderName)"
                    : "Open message from \(senderName)")
                .accessibilityIdentifier("messageRowExpand")
            }
        }
        .pmPointingHandCursor(enabled: isCollapsible || !expanded)
    }

    /// Below the open message's name: "to me ⌄" (or every participant),
    /// with the message's own controls on the right.
    private var expandedHeaderDetails: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if recipientsExpanded {
                    recipientGrid
                } else {
                    compactRecipientGrid
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let reading = pgpReading {
                PGPIndicatorButton(reading: reading, onDecryptPart: { checkPGP(decryptPart: true) })
            } else if pgpCandidate, store.openPGP.uncheckable.contains(message.id) {
                PGPUncheckableIndicator()
            }
            headerActions
        }
    }

    /// May carry OpenPGP: scanned once per message by `PGPCenter`, never in
    /// `init`. Always false with the build switch off.
    private var pgpCandidate: Bool {
        // A deleted message is not checked: the check fetches the raw
        // message from Gmail and keeps its plaintext in memory.
        !inTrash && PGPFeatures.isEnabled && store.openPGP.isCandidate(message, attachments: attachments)
    }

    /// The engine's verdict on this message, once checked (`PGPCenter`).
    private var pgpReading: PGPCenter.Reading? {
        pgpCandidate ? store.openPGP.readings[message.id] : nil
    }

    /// What replaces the body, if anything: decrypted or signed text, or a
    /// notice (never armor shown as the message).
    private var pgpBody: PGPBodyDisplay? {
        guard let body = pgpReading?.body, body != .original else { return nil }
        return body
    }

    private func checkPGP(decryptPart: Bool = false) {
        guard pgpCandidate else { return }
        let client = store.client(for: message.accountId)
        let center = store.openPGP
        let message = message
        let attachments = attachments
        Task {
            await center.check(message, attachments: attachments,
                               fetchRaw: { try await client.getRawMessage(id: $0) },
                               decryptPart: decryptPart)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 10) {
            if message.bodyHTML != nil, !message.bodyText.isEmpty, pgpBody == nil {
                Button {
                    showPlainText.toggle()
                } label: {
                    Text(showPlainText ? "Show HTML" : "Show plain text")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(showPlainText
                      ? "Render the HTML body again"
                      : "Show the multipart plain-text alternative (no remote images; useful when HTML is unreadable)")
            }
            if message.bodyHTML != nil, !allowRemoteImages, !showPlainText, pgpBody == nil,
               !store.openPGP.blocksRemoteContent(message, candidate: pgpCandidate) {
                // Click loads this message; chevron / long-press offers the thread.
                Menu {
                    Button("This conversation") { loadImagesForThread = true }
                } label: {
                    Text("Load images")
                        .font(.caption)
                } primaryAction: {
                    loadRemoteImages = true
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Remote images can track opens. Click for this message; menu for the whole conversation (Spam messages still need their own click). The image policy is in Settings → Appearance.")
            }
            if inTrash {
                // Deleted: no reply, reply all or forward; only restore.
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .fixedSize()
                .help("Move this message out of the Trash, back to this conversation")
                .accessibilityIdentifier("messageActionRestore")
            }
        }
    }

    /// The name line's date, redrawn every minute so "(12 hours ago)"
    /// stays true.
    private var headerDate: some View {
        TimelineView(.everyMinute) { context in
            Text(dateText(now: context.date))
                .font(.system(size: metrics.dateFontSize).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .help(message.date.formatted(date: .complete, time: .shortened))
        }
    }

    private var canReplyAll: Bool {
        ReplyComposer.hasAdditionalReplyAllRecipients(message, ownAddresses: store.ownEmailAddresses)
    }

    private var isStarred: Bool { MessageActions.isStarred(message) }

    /// Star (not on a draft), reply, reply all (when it differs from
    /// reply, as in Gmail) and "More".
    private var headerControlCount: Int {
        (TrashedMessages.isDraft(message) ? 0 : 1) + 1 + (canReplyAll ? 1 : 0) + 1
    }

    /// After the open message's date, as in Gmail on the web: star, reply,
    /// reply all, then "More" (⋮). Fixed width: the sender's name is the
    /// line's only flexible child and gives way first.
    private var headerControls: some View {
        HStack(spacing: metrics.headerControlSpacing) {
            if !TrashedMessages.isDraft(message) {
                Button {
                    store.toggleMessageStar(message)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                        .frame(width: metrics.headerControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isStarred ? "Starred" : "Not starred")
                .accessibilityLabel(isStarred ? "Unstar this message" : "Star this message")
                .accessibilityIdentifier("messageHeaderStar")
            }
            Button {
                store.openCompose(.init(replyTo: message))
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .frame(width: metrics.headerControlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Reply (\(store.keyBindings.displayKey(for: .reply)))")
            .accessibilityLabel("Reply")
            .accessibilityIdentifier("messageHeaderReply")
            if canReplyAll {
                Button {
                    store.openCompose(.init(replyTo: message, replyAll: true))
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.2")
                        .frame(width: metrics.headerControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Reply all (\(store.keyBindings.displayKey(for: .replyAll)))")
                .accessibilityLabel("Reply all")
                .accessibilityIdentifier("messageHeaderReplyAll")
            }
            Menu {
                moreMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .frame(width: metrics.headerControlSize)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .frame(width: metrics.headerControlSize)
            .help("More")
            .accessibilityLabel("More")
            .accessibilityIdentifier("messageHeaderMore")
        }
        .font(.system(size: 13 * fontScale))
        .fixedSize()
    }

    private var menuContext: MessageActions.Context {
        let email = MessageParser.emailAddress(message.fromHeader)
        return MessageActions.Context(
            canReplyAll: canReplyAll,
            fromSelf: store.ownEmailAddresses.contains(email.lowercased()),
            senderBlocked: store.isBlocked(email),
            threadInSpam: threadInSpam,
            isTrashed: TrashedMessages.isTrashed(message))
    }

    /// Gmail web's per-message menu, in its order and groups
    /// (`MessageActions`), a divider between groups.
    @ViewBuilder
    private var moreMenuItems: some View {
        let sections = MessageActions.menuSections(menuContext)
        ForEach(sections.indices, id: \.self) { index in
            if index > 0 { Divider() }
            ForEach(sections[index], id: \.self) { item in
                moreMenuButton(item)
            }
        }
    }

    /// Prints this message as the pane renders it (`MessagePrint`): the
    /// body the card shows, with the card's remote-image decision.
    private func printMessage() {
        var html = cidInlinedHTML ?? message.bodyHTML
        var allow = allowRemoteImages
        if case .remote(let remote) = remoteChoice {
            html = remote.html
            allow = remote.loadAllowsRemoteImages
        }
        // OpenPGP: the text shown in place of the body, or its notice.
        let replacement: String? = {
            switch pgpBody {
            case .text(let shown): return shown
            case .notice(let notice): return notice.text
            case .original, nil: return nil
            }
        }()
        let body = MessagePrint.body(replacement: replacement, showPlainText: showPlainText,
                                     html: html, text: message.bodyText)
        let header = MessagePrint.headerHTML(
            subject: message.subject, from: message.fromHeader,
            to: message.toHeader, cc: message.ccHeader, date: message.date)
        if case .text = body { allow = false }
        MessagePrinter.print(
            document: MessagePrint.document(header: header, body: body, allowRemoteImages: allow),
            allowRemoteImages: allow,
            jobTitle: MessagePrint.jobTitle(subject: message.subject),
            window: NSApp.keyWindow)
    }

    private func moreMenuButton(_ item: MessageActions.MenuItem) -> some View {
        let email = MessageParser.emailAddress(message.fromHeader)
        return Button(role: item == .deleteMessage || item == .blockSender ? .destructive : nil) {
            switch item {
            case .reply:
                store.openCompose(.init(replyTo: message))
            case .replyAll:
                store.openCompose(.init(replyTo: message, replyAll: true))
            case .forward:
                store.openCompose(.init(replyTo: message, forward: true))
            case .filterLikeThis:
                var draft = GmailFilterDraft()
                draft.from = MessageActions.filterFromAddress(message.fromHeader)
                menuSheet = .filter(GmailFilterEditTarget(
                    accountId: message.accountId, original: nil, prefill: draft))
            case .deleteMessage:
                store.trashMessage(message)
            case .blockSender:
                onBlockSender(email)
            case .unblockSender:
                store.unblockSender(email)
            case .reportSpam:
                store.reportSpam(message, spam: true)
            case .reportNotSpam:
                store.reportSpam(message, spam: false)
            case .showOriginal:
                menuSheet = .original
            case .print:
                printMessage()
            case .downloadMessage:
                store.downloadMessage(message)
            case .markUnreadFromHere:
                onMarkUnreadFromHere()
            }
        } label: {
            // macOS draws a Label in a menu title-only unless asked for both.
            Label(MessageActions.title(item, senderName: senderName),
                  systemImage: MessageActions.symbol(item))
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("messageMenu.\(item)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    expandedContent
                }
                .padding(.horizontal, metrics.bodyInset)
                .padding(.bottom, metrics.verticalPadding)
                // OpenPGP: checked when opened (again at each open while it
                // could not be checked), and after the keys, a passphrase or
                // the lock state change (`generation`).
                .task(id: "\(message.id)|\(store.openPGP.generation)|\(pgpCandidate)") {
                    if pgpReading == nil { checkPGP() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Flat row: no card fill or shadow. Hairlines between rows are drawn
        // by the thread view. HTML bodies keep their own dark-mode styling
        // over the pane's background (the web view draws no background).
        .background {
            // The row's whole frame for the UI tests (a container's frame is
            // its children's). Absent outside UI tests: no VoiceOver noise.
            if Self.exposesRowFrame {
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel("Message row")
                    .accessibilityIdentifier("messageRowFrame")
            }
        }
        .coordinateSpace(.named(Self.cardSpace))
        .sheet(item: $menuSheet) { sheet in
            switch sheet {
            case .filter(let target): GmailFilterEditorSheet(target: target)
            case .original: OriginalMessageSheet(message: message)
            }
        }
        // A collapsed row is all header, and its header is a button.
        .onAppear {
            // Parent seeds the open set on payload apply. Cards that land
            // already expanded (or the single last-card default before seed)
            // still need body hydration.
            if isLast, expandedMessageIds.isEmpty {
                expandedMessageIds = expandPolicy.applyingExpand(
                    id: message.id, currently: expandedMessageIds)
                onNeedBody()
            } else if expanded {
                onNeedBody()
            }
            if message.listUnsubscribe == nil {
                onNeedUnsubscribeHeaders()
            }
        }
    }

    /// An open message below its header: body, quoted-text toggle,
    /// invites, attachments, the action bar and matching filters.
    @ViewBuilder
    private var expandedContent: some View {
        // Collapsed cards never mount HTMLBodyView (gated on expanded).
        // Header-only rows show nothing until the parent hydrates the body.
        //
        // When we only have a plain-text head (no structured HTML quote),
        // show that head while collapsed — even if bodyHTML exists —
        // so nested `>` history doesn't stay visible by default.
        if let pgpBody {
            PGPBodyReplacement(display: pgpBody, accountId: message.accountId, fontScale: fontScale)
        } else if hasQuotedTrail, let head = textHead, !showQuoted {
            PlainTextBody(text: head, fontScale: fontScale)
        } else if showPlainText, !message.bodyText.isEmpty {
            // Manual plain-text escape hatch (see header control).
            PlainTextBody(text: message.bodyText, fontScale: fontScale)
        } else if case .awaitingCacheCheck = remoteChoice,
                  !(cidInlinedHTML ?? message.bodyHTML ?? "").isEmpty {
            // The pane is checking the cache (a few milliseconds): the body
            // waits in its reserved space instead of loading live first.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: fillsPaneHeight.map { max(0, $0 - bodyTopInCard) } ?? 0)
                .task(id: "\(allowRemoteImages)|\(cidInlinedHTML != nil)") {
                    // Starts the check only; never a fetch (not mounted).
                    onRemoteImagesDecision(allowRemoteImages, false)
                }
        } else if let baseHTML = (cidInlinedHTML ?? message.bodyHTML), !baseHTML.isEmpty {
            // Remote images: a body with them inlined replaces the base
            // (with its own prep: head, sizes, documents) only while this
            // card allows them; the load's CSP follows the choice.
            let choice = remoteChoice
            let remote: RemoteInlinedBody? = {
                if case .remote(let body) = choice { return body }
                return nil
            }()
            let loadAllowsRemoteImages: Bool = {
                switch choice {
                case .base(let allow): return allow
                case .remote(let body): return body.loadAllowsRemoteImages
                case .awaitingCacheCheck: return false
                }
            }()
            let html = remote?.html ?? baseHTML
            let bodyHead = remote.map { $0.prep.htmlHead } ?? htmlHead
            let bodyHeadBytes = remote?.prep.htmlHeadBytes ?? htmlHeadBytes
            let bodyBytes = remote?.prep.htmlBytes ?? htmlBytes
            let bodyDocuments = remote.map { $0.prep.documents } ?? htmlDocuments
            // Structured quotes are removed before WebKit sees the
            // document. Besides avoiding repeated history parsing,
            // this gives head/full loads distinct constant-time ids.
            let useAuthoredHTML = textHead == nil && !showQuoted
                && bodyHead != nil
            let renderedHTML = useAuthoredHTML ? (bodyHead ?? html) : html
            let renderedBytes = useAuthoredHTML ? bodyHeadBytes : bodyBytes
            if HTMLBodyRenderPolicy.requiresExplicitLoad(
                byteCount: renderedBytes,
                userApproved: approvedOversizedHTML) {
                oversizedHTMLPlaceholder(byteCount: renderedBytes)
            } else {
                // `htmlDocuments` matches the HTML on screen: CID
                // prep for inlined bodies, repository prep otherwise.
                // Font-scale mismatch → no docs; HTMLBodyView then
                // assembles off-main from `html`.
                let docsForScale: MessageHTMLDocuments? = {
                    guard let docs = bodyDocuments,
                          abs(docs.fontScale - fontScale) < 0.001
                    else { return nil }
                    return docs
                }()
                // Lookup only — an allowed variant that is not built
                // yet comes back nil and is built off-main by the
                // view (which also fills the shared memo).
                let preassembled = docsForScale?.readyDocument(
                    authored: useAuthoredHTML,
                    allowRemoteImages: loadAllowsRemoteImages)
                // `:cid` follows the body on screen (R1): a cached body built
                // before the `cid:` resolve keeps its id until rebuilt.
                let bodyContentID = RemoteImageRendering.contentID(
                    messageId: message.id, authored: useAuthoredHTML,
                    cidInlined: cidInlinedHTML != nil, remoteBody: remote)
                // This document's own load ended: the same key the view
                // loads, so a Load-images click or a `cid:` base is a new
                // load to wait for.
                let bodyLoaded = RemoteImageRendering.bodyLoaded(
                    finished: loadFinishedKey, contentID: bodyContentID,
                    allowRemoteImages: loadAllowsRemoteImages, fontScale: fontScale)
                // Read in body, not onAppear: a known height (re-open,
                // or a pre-rendered neighbor) must size the very first
                // frame. Without one, the open card reserves the pane
                // until the first report instead of opening as a
                // short box that then jumps to the body's length.
                // At the pane's last measured width: a height measured
                // at another width (pane resized, or an estimate) would
                // paint clipped or over-tall and then resize.
                let cachedHeight = measuredHTMLHeight == nil
                    ? HTMLBodyHeightCacheStore.height(
                        contentID: bodyContentID,
                        fontScale: fontScale,
                        width: HTMLBodyHeightCacheStore.lastLayoutWidth)
                    : nil
                let bodyHeight = MessageBodyHeight.webViewHeight(
                    measured: measuredHTMLHeight, cached: cachedHeight)
                let containerHeight = MessageBodyHeight.containerHeight(
                    measured: measuredHTMLHeight,
                    cached: cachedHeight,
                    reserve: htmlBodyEverMeasured ? nil
                        : fillsPaneHeight.flatMap {
                            MessageBodyHeight.paneReserve(
                                viewportHeight: $0,
                                // Header above the body + the row's
                                // bottom padding.
                                chromeHeight: bodyTopInCard
                                    + metrics.verticalPadding)
                        })
                HTMLBodyView(
                    contentID: bodyContentID,
                    html: renderedHTML,
                    preassembledDocument: preassembled,
                    documents: docsForScale,
                    documentIsAuthored: useAuthoredHTML,
                    allowRemoteImages: loadAllowsRemoteImages,
                    fontScale: fontScale,
                    height: Binding(
                        get: { bodyHeight },
                        set: {
                            measuredHTMLHeight = $0
                            htmlBodyEverMeasured = true
                        }),
                    onSettled: onBodySettled,
                    onLoadFinished: { finished in
                        if loadFinishedKey != finished { loadFinishedKey = finished }
                    })
                    // The web view keeps its own frame (measuring is
                    // unchanged); only its container reserves space.
                    .frame(height: bodyHeight)
                    .frame(maxWidth: .infinity, minHeight: containerHeight,
                           maxHeight: containerHeight, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(Self.cardSpace)).minY.rounded()
                    } action: { top in
                        if top != bodyTopInCard { bodyTopInCard = top }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("messageBody")
                    // The card's decision (policy, click, conversation
                    // opt-in, Spam): the parent resolves only while it
                    // allows, and stops when it no longer does or the body
                    // leaves. "Mounted" for the fetch means this document's
                    // own load ended: the app's requests to the image hosts
                    // never compete with the web view's.
                    .task(id: "\(allowRemoteImages)|\(cidInlinedHTML != nil)|\(bodyLoaded)") {
                        onRemoteImagesDecision(allowRemoteImages, bodyLoaded)
                    }
                    .onDisappear {
                        loadFinishedKey = nil
                        onRemoteImagesDecision(false, true)
                    }
            }
        } else if !message.bodyText.isEmpty {
            // Collapsed plain-text heads are handled above; this branch
            // is full body (no trail, or showQuoted).
            PlainTextBody(text: message.bodyText, fontScale: fontScale)
        }
        if let part = pgpReading?.separatePart {
            PGPEncryptedPartView(text: part, fontScale: fontScale)
        }
        if hasQuotedTrail, pgpBody == nil {
            // Same pill as the compose card: the trail is one click
            // away, and one more click tucks it back.
            Button {
                // Collapsing shrinks the content, and a reloaded web
                // view can't measure below its current frame — drop
                // back to the head's cached height (or the
                // placeholder) and let it grow to fit.
                // Expanding only grows, so the height stays put until
                // the new load reports in (no visible snap).
                if showQuoted { measuredHTMLHeight = nil }
                // Showing the full trail is itself an explicit request
                // to load it. Keep the authored head visible instead of
                // replacing it with another confirmation placeholder.
                if !showQuoted,
                   HTMLBodyRenderPolicy.quoteExpansionApprovesFullBody(
                       byteCount: htmlBytes) {
                    approvedOversizedHTML = true
                }
                withAnimation { showQuoted.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13 * fontScale, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(showQuoted ? "Hide quoted text" : "Show quoted text")
            .accessibilityLabel(showQuoted ? "Hide quoted text" : "Show quoted text")
        }
        // Calendar invites get a Gmail-style Accept card; the
        // .ics itself is hidden from the generic attachment chips so
        // it isn't double-presented as a dumb file. uniqueCalendar…
        // collapses Google's text/calendar + application/ics pair
        // (and already-synced duplicate rows) to one card.
        let calendarAtts = CalendarInvite.uniqueCalendarAttachments(attachments)
        // A deleted message's invite is a plain file: no reply card.
        let fileAtts = inTrash ? attachments : attachments.filter {
            !CalendarInvite.isCalendarAttachment(
                mimeType: $0.mimeType, filename: $0.filename)
        }
        if !inTrash, !calendarAtts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(calendarAtts, id: \.displayIdentity) { att in
                    CalendarInviteCard(message: message, attachment: att,
                                       fontScale: fontScale)
                }
            }
        }
        if !fileAtts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if fileAtts.count > 1 {
                        Button {
                            store.saveAllAttachments(fileAtts, message: message)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.to.line")
                                Text("Download all (\(fileAtts.count))")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(.accentFill.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help("Save every attachment to a folder you choose")
                    }
                    ForEach(fileAtts, id: \.displayIdentity) { att in
                        MessageAttachmentChip(
                            filename: att.filename,
                            sizeBytes: att.size,
                            iconName: iconName(for: att.mimeType),
                            onQuickLook: {
                                store.quickLookAttachment(att, message: message)
                            },
                            onSave: {
                                store.saveAttachment(att, message: message)
                            },
                            onOpen: {
                                store.openAttachment(att, message: message)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        // A deleted message has no actions but "Restore" (in its header),
        // and loads nothing more (filters come from Gmail).
        if !inTrash {
            // Action bar on every message.
            HStack(spacing: 8) {
                Button {
                    store.openCompose(.init(replyTo: message))
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 12.5 * fontScale))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("messageActionReply")
                if ReplyComposer.hasAdditionalReplyAllRecipients(
                    message, ownAddresses: store.ownEmailAddresses) {
                    Button {
                        store.openCompose(.init(replyTo: message, replyAll: true))
                    } label: {
                        Label("Reply all", systemImage: "arrowshape.turn.up.left.2")
                            .font(.system(size: 12.5 * fontScale))
                    }
                    .buttonStyle(.bordered)
                    .help("Reply all (\(store.keyBindings.displayKey(for: .replyAll)))")
                }
                Button {
                    store.openCompose(.init(replyTo: message, forward: true))
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                        .font(.system(size: 12.5 * fontScale))
                }
                .buttonStyle(.bordered)
                .help("Forward this message · starts a new conversation")
            }
            .padding(.top, 4)

            // Which of your Gmail filters match this message — collapsed
            // by default; toggle the header to expand. Hidden until the
            // account's filters have loaded and at least one hits.
            MatchingFiltersSection(message: message, fontScale: fontScale)
        }
    }

    private func oversizedHTMLPlaceholder(byteCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Large HTML message", systemImage: "doc.richtext")
                .font(.system(size: 13 * fontScale, weight: .semibold))
            Text("This body is \(byteSize(byteCount)). Loading it may briefly slow the reading pane.")
                .font(.system(size: 12.5 * fontScale))
                .foregroundStyle(.secondary)
            // Gmail's snippet is already short. Do not call authoredPreview
            // here: its plain-text/HTML quote detection is intentionally
            // thorough and would scan the giant body this placeholder avoids.
            let preview = message.snippet.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if !preview.isEmpty {
                Text(String(preview.prefix(HTMLBodyRenderPolicy.previewCharacterLimit)))
                    .font(.system(size: 13 * fontScale))
                    .lineLimit(8)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Load full HTML") {
                approvedOversizedHTML = true
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Own address this message reached. `needsOwnRow` when To / Cc do not
    /// already show it (Bcc, mailing list, forwarding).
    private var deliveredAddress: DeliveredAddress.Result {
        DeliveredAddress.resolve(message, ownEmails: store.ownEmailAddresses)
    }

    /// Show the "delivered to" row only when it adds information: the
    /// address is not in To / Cc, and the message is not the user's own
    /// sent mail (except an own Bcc). A bare mailbox guess shows only when
    /// more than one account is linked (unified inbox).
    private var showsDeliveredRow: Bool {
        let delivered = deliveredAddress
        guard delivered.needsOwnRow else { return false }
        switch delivered.source {
        case .to, .cc: return false
        case .bcc: return true
        case .delivered, .mailbox:
            let sender = MessageParser.emailAddress(message.fromHeader)
            let sentByMe = store.ownEmailAddresses.contains {
                $0.caseInsensitiveCompare(sender) == .orderedSame
            } || sender.caseInsensitiveCompare(message.accountId) == .orderedSame
            if sentByMe { return false }
            // One address, one account: the row would only ever repeat it.
            let several = store.ownEmailAddresses.count > 1 || store.accounts.count > 1
            if delivered.source == .mailbox { return store.accounts.count > 1 }
            return several
                || delivered.email.caseInsensitiveCompare(message.accountId) != .orderedSame
        }
    }

    private var deliveredHelp: String {
        switch deliveredAddress.source {
        case .bcc: return "You sent this as Bcc to this address"
        case .delivered, .mailbox:
            return "This message came to this address. You were Bcc'd, or it came through a list or a forward."
        case .to, .cc: return ""
        }
    }

    private var deliveredRow: some View {
        GridRow {
            recipientRole(deliveredAddress.source == .bcc ? "BCC" : "VIA")
            Text(deliveredLabel)
                .font(.system(size: 12.5 * fontScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(deliveredHelp)
                .accessibilityLabel("Delivered to \(deliveredAddress.email)")
        }
    }

    /// "me · alias@x.com" so the exact address is always visible.
    private var deliveredLabel: String {
        let email = deliveredAddress.email
        let own = store.ownEmailAddresses.contains { $0.caseInsensitiveCompare(email) == .orderedSame }
            || store.accounts.contains { $0.id.caseInsensitiveCompare(email) == .orderedSame }
        return own ? "me · \(email)" : email
    }

    /// Compact recipient value: "me", "Van Ju +3" (extras include Cc).
    private var recipientSummary: String {
        let own = Set(store.ownEmailAddresses.map { $0.lowercased() })
            .union(store.accounts.map { $0.id.lowercased() })
        let recipients = MessageParser.splitAddresses(message.toHeader)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ccCount = MessageParser.splitAddresses(message.ccHeader)
            .filter { $0.contains("@") }.count
        guard let first = recipients.first else { return "—" }
        let firstName = own.contains(MessageParser.emailAddress(first).lowercased())
            ? "me" : MessageParser.displayName(fromHeader: first)
        let extra = recipients.count - 1 + ccCount
        return extra > 0 ? "\(firstName) +\(extra)" : firstName
    }

    /// The open message's line below the name: "to me ⌄" (Gmail on the
    /// web), Unsubscribe when the list offers it, and the "via" row when the
    /// message reached an address To / Cc do not show. The sender itself is
    /// on the name line above.
    private var compactRecipientGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: 12,
             verticalSpacing: 3) {
            GridRow {
                recipientRole("TO")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            recipientsExpanded = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(recipientSummary)
                                .font(.system(size: 12.5 * fontScale))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8 * fontScale,
                                              weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12, height: 12,
                                       alignment: .center)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("To \(recipientSummary)")
                    .accessibilityHint("Show all senders and recipients")
                    .help("Show all senders and recipients")
                    unsubscribeButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsDeliveredRow { deliveredRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var unsubscribeButton: some View {
        if !inTrash, ListUnsubscribe.offer(from: message) != nil {
            Button("Unsubscribe", action: onUnsubscribe)
                .buttonStyle(.plain)
                .font(.system(size: 12 * fontScale))
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("Unsubscribe from this mailing list")
        }
    }

    private func recipientRole(_ role: String) -> some View {
        Text(role)
            .font(.system(size: 10 * fontScale, weight: .medium))
            .foregroundStyle(.tertiary)
            .gridColumnAlignment(.leading)
    }

    /// Full participant details: FROM / TO / CC rows with
    /// one clickable participant per line, and "Show less" to tuck it back.
    private var recipientGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
            recipientRows("FROM", header: message.fromHeader)
            recipientRows("TO", header: message.toHeader)
            recipientRows("CC", header: message.ccHeader)
            if showsDeliveredRow { deliveredRow }
            GridRow {
                Text("")
                Button("Show less") {
                    withAnimation(.easeOut(duration: 0.12)) { recipientsExpanded = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12 * fontScale))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recipientRows(_ role: String, header: String) -> some View {
        let addresses = MessageParser.splitAddresses(header)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        ForEach(Array(addresses.enumerated()), id: \.offset) { index, address in
            GridRow {
                Text(index == 0 ? role : "")
                    .font(.system(size: 10 * fontScale, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .gridColumnAlignment(.leading)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    participantMenu(address)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if role == "FROM", index == 0 { unsubscribeButton }
                }
            }
        }
    }

    /// A clickable participant: name + address, opening a menu
    /// (draft to them, search their mail, copy, VIP, split, block).
    @ViewBuilder
    private func participantMenu(_ raw: String, nameSize: CGFloat = 12.5,
                                 nameWeight: Font.Weight = .regular) -> some View {
        let email = MessageParser.emailAddress(raw)
        let name = store.participantDisplayName(fromHeader: raw)
        let showEmail = name.lowercased() != email.lowercased()
        // Canonical "is this me" set (accounts ∪ send-as aliases) — same as
        // reply-all / participant labeling elsewhere in this file.
        let ownEmails = store.ownEmailAddresses
        let vipAction = ParticipantMenuVIP.action(
            email: email,
            vipEmails: store.vipEmails,
            ownEmails: ownEmails)
        Menu {
            Button {
                store.openCompose(.init(replyTo: nil, prefillTo: email))
            } label: {
                Label("Draft email to \(name)", systemImage: "square.and.pencil")
            }
            Button {
                store.commitSearch("from:\(email)")
            } label: {
                Label("Search emails from \(name)", systemImage: "magnifyingglass")
            }
            Divider()
            Button("Copy \"\(email)\"") { copyToPasteboard(email) }
            if showEmail {
                Button("Copy \"\(name)\"") { copyToPasteboard(name) }
            }
            // VIP / split / block only make sense for other people's addresses.
            // VIP sits between copy and split so promoting a sender is one
            // click from the same menu that opens when you click their name.
            if let vipAction {
                Divider()
                Button {
                    switch vipAction {
                    case .add(let e): store.addVIP(e)
                    case .remove(let e): store.removeVIP(e)
                    }
                } label: {
                    Label(ParticipantMenuVIP.title(for: vipAction),
                          systemImage: ParticipantMenuVIP.systemImage(for: vipAction))
                }
            }
            if !ownEmails.contains(email.lowercased()) {
                Divider()
                Button {
                    store.splitFromInbox(matching: email, named: name)
                } label: {
                    Label("Split \(name) from Inbox", systemImage: "arrow.triangle.branch")
                }
                if let domain = email.split(separator: "@").last.map(String.init),
                   domain.contains(".") {
                    Button {
                        store.splitFromInbox(matching: "@\(domain)", named: domain)
                    } label: {
                        Label("Split \(domain) from Inbox", systemImage: "at")
                    }
                }
                Divider()
                if store.isBlocked(email) {
                    Button {
                        store.unblockSender(email)
                    } label: {
                        Label("Unblock \(email)", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } else {
                    Button(role: .destructive) {
                        onBlockSender(email)
                    } label: {
                        Label("Block \(email)", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            }
        } label: {
            // Label hugs its text so whitespace to the right still falls
            // through to the header's collapse onTapGesture. The Menu's
            // outer maxWidth frame (below) expands layout proposal only.
            participantLabel(name: name, email: email, showEmail: showEmail,
                             nameSize: nameSize, nameWeight: nameWeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(email)
    }

    /// Progressive disclosure for the participant chip: full name+email when
    /// it fits, else a tail-truncated name (email stays in `.help` / menu).
    /// Avoids dual middle-truncation that produced unreadable fragments
    /// like "Ale…sque abda…y.edu".
    @ViewBuilder
    private func participantLabel(name: String, email: String, showEmail: Bool,
                                  nameSize: CGFloat, nameWeight: Font.Weight) -> some View {
        let nameFont = Font.system(size: nameSize * fontScale, weight: nameWeight)
        let emailFont = Font.system(size: (nameSize - 1.5) * fontScale)
        if showEmail {
            // Two alternatives only: a non-fixedSize name with .tail already
            // "fits" any proposal by truncating, so a middle name-only tier
            // would never be selected.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(nameFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(email)
                        .font(emailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(name)
                    .font(nameFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(name)
                .font(nameFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func byteSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func iconName(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("compressed") { return "doc.zipper" }
        if mime.contains("spreadsheet") || mime.contains("csv") || mime.contains("excel") { return "tablecells" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("text/calendar") || mime.contains("application/ics") {
            return "calendar"
        }
        return "doc"
    }
}

/// A plain-text message body. Web links and addresses in it are clickable
/// (`PlainTextLinks`): only http, https and mailto, and a link always shows
/// its own destination. Link runs carry the accent's text colour themselves; `.tint`
/// alone does not color them while text selection is on.
private struct PlainTextBody: View {
    let text: String
    let fontScale: Double
    @Environment(\.mailAccent) private var accent

    var body: some View {
        Text(PlainTextLinks.attributed(text, accent: accent))
            .font(.system(size: 14.5 * fontScale))
            .lineSpacing(4)
            .textSelection(.enabled)
            .tint(accent.text)
            .accessibilityIdentifier("messageBody")
            .environment(\.openURL, OpenURLAction { url in
                // Hand the link to the system, as the HTML body does; never
                // navigate inside the app. Anything off the allow-list is inert.
                if let external = PlainTextLinks.externalURL(for: url) {
                    NSWorkspace.shared.open(external)
                }
                return .handled
            })
    }
}

private struct MessageAttachmentChip: View {
    let filename: String
    let sizeBytes: Int
    let iconName: String
    let onQuickLook: () -> Void
    let onSave: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: MessageAttachmentChipLayout.regionSpacing) {
            Button(action: onQuickLook) {
                let insets = MessageAttachmentChipLayout.previewHitInsets()
                HStack(spacing: MessageAttachmentChipLayout.iconTextSpacing) {
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.stable(for: filename))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(filename)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(sizeBytes),
                                                       countStyle: .file))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .padding(.vertical, insets.vertical)
                .frame(minHeight: MessageAttachmentChipLayout.chipMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick Look — Esc closes the preview")

            Button(action: onQuickLook) {
                Image(systemName: "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, MessageAttachmentChipLayout.verticalPadding)
                    .padding(.horizontal, MessageAttachmentChipLayout.actionInnerPadding)
                    .frame(minHeight: MessageAttachmentChipLayout.chipMinHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick Look")

            Button(action: onSave) {
                let insets = MessageAttachmentChipLayout.saveHitInsets()
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.leading, insets.leading)
                    .padding(.trailing, insets.trailing)
                    .padding(.vertical, insets.vertical)
                    .frame(minHeight: MessageAttachmentChipLayout.chipMinHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save As… (you choose where)")
        }
        // Nested chips: flat fill only. Elevation lives on the
        // parent MessageCard so we don't stack soft shadows.
        .background(Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: MessageAttachmentChipLayout.cornerRadius))
        .contextMenu {
            Button("Quick Look", action: onQuickLook)
            Button("Open", action: onOpen)
            Button("Save As…", action: onSave)
        }
    }
}

// MARK: - Matching Gmail filters (per message)

/// Collapsible disclosure under an expanded message listing the account's
/// Gmail filters whose criteria match this message. Loads filters lazily
/// via `MailStore.ensureFiltersLoaded`; hidden when none match or filters
/// aren't readable yet (scope / empty account).
private struct MatchingFiltersSection: View {
    @Environment(MailStore.self) var store
    let message: Message
    var fontScale: Double = 1.0
    @State private var expanded = false

    private var matches: [GFilter] {
        store.matchingFilters(for: message)
    }

    private var isLoading: Bool {
        store.filtersLoading.contains(message.accountId)
            && store.filtersByAccount[message.accountId] == nil
    }

    var body: some View {
        Group {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.1)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 11 * fontScale))
                            Text(matches.count == 1
                                 ? "1 matching filter"
                                 : "\(matches.count) matching filters")
                                .font(.system(size: 12 * fontScale, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9 * fontScale, weight: .semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded
                          ? "Hide matching Gmail filters"
                          : "Show Gmail filters that match this message")

                    if expanded {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(matches) { filter in
                                GmailFilterSentenceRow(
                                    filter: filter,
                                    accountId: message.accountId,
                                    compact: true)
                            }
                            Button("Edit filters in Gmail…") {
                                if let url = GmailWebLinks.filtersSettingsURL(
                                    accountEmail: message.accountId) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11 * fontScale))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 2)
                        .transition(.opacity)
                    }
                }
                .padding(.top, 6)
            } else if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking filters…")
                        .font(.system(size: 11 * fontScale))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
        .task(id: message.accountId) {
            await store.ensureFiltersLoaded(for: message.accountId)
        }
    }
}

private extension View {
    /// A message row in the conversation: a full-width hairline over the top
    /// edge of every row but the first. An overlay, so the row's frame (and
    /// its scroll id) starts at the hairline and rows touch.
    func messageRowSeparator(isFirst: Bool) -> some View {
        overlay(alignment: .top) {
            if !isFirst {
                Divider()
            }
        }
    }
}
