import XCTest
import GRDB

/// The actions on one message of an open conversation (Gmail on the web:
/// star, reply, reply all and the "More" menu), the message a conversation
/// opens on, and the per-message label path they share with the Trash
/// view's restore (`messages.batchModify` on explicit ids, never a delete).
final class MessageActionsTests: XCTestCase {
    private let account = "you@example.com"

    private func msg(_ id: String, thread: String = "t1", minutesAgo: Double, labels: String,
                     unread: Bool = false) -> Message {
        Message(id: "\(account):\(id)", accountId: account, gmailId: id,
                threadId: "\(account):\(thread)", fromHeader: "Ann <ann@example.com>",
                toHeader: account, ccHeader: "", bccHeader: "", subject: "Plans",
                date: Date(timeIntervalSinceNow: -minutesAgo * 60),
                snippet: "snippet-\(id)", bodyText: "body-\(id)", bodyHTML: nil,
                messageIdHeader: "<\(id)@example.com>", referencesHeader: "",
                labelIds: labels, isUnread: unread, hasAttachment: false)
    }

    private var threadId: String { "\(account):t1" }

    private func makeDB(_ messages: [Message]) throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try AppDatabase.migrator.migrate(q)
        try q.write { db in
            try Account(id: self.account, displayName: "P", historyId: nil,
                        lastSyncAt: nil, senderName: "").save(db)
            for m in messages { try m.insert(db) }
            if !messages.isEmpty {
                try SyncEngine.deriveThreads(db, for: [self.threadId], accountId: self.account)
            }
        }
        return q
    }

    private func thread(_ q: DatabaseQueue) throws -> MailThread {
        try XCTUnwrap(try q.read { try MailThread.fetchOne($0, key: self.threadId) })
    }

    private func shown(_ q: DatabaseQueue) throws -> [String] {
        try q.read { db in
            try ThreadDetailRepository.fetchPayload(threadId: self.threadId, db: db).messages.map(\.gmailId)
        }
    }

    private func labels(_ q: DatabaseQueue, _ id: String) throws -> String {
        try XCTUnwrap(try q.read { try Message.fetchOne($0, key: "\(self.account):\(id)") }).labelIds
    }

    // MARK: - The "More" menu

    private let typical = MessageActions.Context(
        canReplyAll: true, fromSelf: false, senderBlocked: false,
        threadInSpam: false, isTrashed: false)

    func testMenuKeepsGmailsOrderGroupsAndWording() {
        let titles = MessageActions.menuSections(typical).map { section in
            section.map { MessageActions.title($0, senderName: "Ann") }
        }
        XCTAssertEqual(titles, [
            ["Reply", "Reply all", "Forward"],
            ["Delete", "Mark as unread"],
            ["Block \"Ann\"", "Report spam"],
            ["Filter messages like this", "Print", "Download message", "Show original"],
        ])
        XCTAssertEqual(MessageActions.menuItems(typical),
                       MessageActions.menuSections(typical).flatMap { $0 })
        XCTAssertEqual(MessageActions.symbol(.print), "printer")
    }

    /// A trashed message from oneself has nothing in the sender and spam
    /// group: no empty group, so no doubled divider.
    func testAnEmptyGroupIsDropped() {
        let c = MessageActions.Context(canReplyAll: false, fromSelf: true, senderBlocked: false,
                                       threadInSpam: false, isTrashed: true)
        XCTAssertEqual(MessageActions.menuSections(c), [
            [.reply, .forward],
            [.markUnreadFromHere],
            [.filterLikeThis, .print, .downloadMessage, .showOriginal],
        ])
    }

    func testLeftOutItemsAreNotShownAtAll() {
        for context in [typical,
                        MessageActions.Context(canReplyAll: false, fromSelf: true, senderBlocked: false,
                                               threadInSpam: true, isTrashed: true)] {
            let titles = MessageActions.menuItems(context).map {
                MessageActions.title($0, senderName: "Ann").lowercased()
            }
            for gone in ["phishing", "translate", "contacts"] {
                XCTAssertFalse(titles.contains { $0.contains(gone) }, gone)
            }
        }
    }

    func testMenuFollowsTheMessage() {
        var c = typical
        c.canReplyAll = false
        c.fromSelf = true
        let items = MessageActions.menuItems(c)
        XCTAssertFalse(items.contains(.replyAll), "as the header: only when it differs from Reply")
        XCTAssertFalse(items.contains(.blockSender), "never one's own address")
        c = typical
        c.threadInSpam = true
        XCTAssertTrue(MessageActions.menuItems(c).contains(.reportNotSpam))
        XCTAssertFalse(MessageActions.menuItems(c).contains(.reportSpam))
        c = typical
        c.senderBlocked = true
        XCTAssertTrue(MessageActions.menuItems(c).contains(.unblockSender))
        XCTAssertFalse(MessageActions.menuItems(c).contains(.blockSender))
    }

    /// From the Trash view: nothing that reaches the conversation's live
    /// messages, which are not on screen (DEC-081).
    func testATrashedMessageOffersNoConversationAction() {
        for spam in [false, true] {
            var c = typical
            c.isTrashed = true
            c.threadInSpam = spam
            let items = MessageActions.menuItems(c)
            XCTAssertFalse(items.contains(.deleteMessage), "already in the Trash")
            XCTAssertFalse(items.contains(.reportSpam))
            XCTAssertFalse(items.contains(.reportNotSpam))
            XCTAssertTrue(items.contains(.markUnreadFromHere), "acts on the trashed messages shown")
            XCTAssertFalse(items.contains(.blockSender), "the blocklist reaches live conversations")
            XCTAssertFalse(items.contains(.unblockSender))
        }
    }

    // MARK: - The message a conversation opens on

    private func ids(_ names: [String]) -> [String] { names.map { "\(account):\($0)" } }

    func testWithoutStarredMessagesTheNewestStillOpens() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX"),
                        msg("b", minutesAgo: 30, labels: "INBOX UNREAD", unread: true),
                        msg("c", minutesAgo: 20, labels: "INBOX")]
        XCTAssertNil(ConversationOpenTarget.target(in: messages))
        let roles = ThreadMessageRoles(messages: messages)
        XCTAssertEqual(roles.openExpandedIds, ["\(account):c"], "as before: the newest only")
        XCTAssertEqual(roles.scrollTargetId, "\(account):c")
        XCTAssertEqual(ThreadRefresh.initialScrolledMessageId(in: messages), "\(account):c")
        XCTAssertEqual(ThreadRefresh.initialBodyLoadSeedIds(in: messages), ["\(account):c"])
    }

    func testOldStarAndNewUnreadMailOpensOnTheNewMail() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX STARRED"),
                        msg("b", minutesAgo: 40, labels: "INBOX"),
                        msg("c", minutesAgo: 30, labels: "INBOX UNREAD", unread: true),
                        msg("d", minutesAgo: 20, labels: "INBOX UNREAD", unread: true),
                        msg("e", minutesAgo: 10, labels: "INBOX")]
        let target = ConversationOpenTarget.target(in: messages)
        XCTAssertEqual(target?.expanded, ids(["a", "c", "d", "e"]),
                       "the star, every unread message and the newest")
        XCTAssertEqual(target?.scroll, "\(account):c", "the oldest unread newer than the star")
        let roles = ThreadMessageRoles(messages: messages)
        XCTAssertEqual(roles.openExpandedIds, Set(ids(["a", "c", "d", "e"])))
        XCTAssertEqual(ThreadRefresh.initialScrolledMessageId(in: messages), "\(account):c")
        XCTAssertEqual(MessageExpandPolicy.initialExpandedIds(
            policy: .single, nonDraftIds: roles.nonDraftIds, lastNonDraftId: roles.lastNonDraftId,
            openIds: roles.openExpandedIds), Set(ids(["a", "c", "d", "e"])))
        XCTAssertEqual(Set(ThreadRefresh.initialBodyLoadSeedIds(in: messages)),
                       Set(ids(["a", "c", "d", "e"])), "their bodies arrive with the payload")
        // One card fills the pane while its body loads: the scroll target.
        for id in ids(["a", "c", "d", "e"]) {
            XCTAssertEqual(MessageExpandPolicy.fillsPane(
                id: id, policy: .single, expanded: roles.openExpandedIds,
                lastNonDraftId: roles.lastNonDraftId, scrollTargetId: roles.scrollTargetId),
                           id == "\(account):c", id)
        }
    }

    /// Read on open writes only the thread row: once it says read, the
    /// message rows' unread flags say nothing and are ignored.
    func testAReadConversationIgnoresStaleUnreadRows() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX STARRED"),
                        msg("b", minutesAgo: 30, labels: "INBOX UNREAD", unread: true),
                        msg("c", minutesAgo: 10, labels: "INBOX UNREAD", unread: true)]
        let read = ConversationOpenTarget.target(in: messages, threadUnread: false)
        XCTAssertEqual(read?.expanded, ids(["a", "c"]), "the star and the newest only")
        XCTAssertEqual(read?.scroll, "\(account):a")
        let roles = ThreadMessageRoles(messages: messages, threadUnread: false)
        XCTAssertEqual(roles.openExpandedIds, Set(ids(["a", "c"])))
        XCTAssertEqual(ThreadRefresh.initialScrolledMessageId(in: messages, threadUnread: false),
                       "\(account):a")
        let unread = ConversationOpenTarget.target(in: messages, threadUnread: true)
        XCTAssertEqual(unread?.scroll, "\(account):b")
    }

    func testALongUnreadConversationOpensAtMostFiveCards() {
        var messages = [msg("s", minutesAgo: 1_000, labels: "INBOX STARRED")]
        for i in 0..<40 {
            messages.append(msg("u\(i)", minutesAgo: Double(900 - i * 10),
                                labels: "INBOX UNREAD", unread: true))
        }
        let target = try? XCTUnwrap(ConversationOpenTarget.target(in: messages))
        XCTAssertEqual(target?.expanded.count, ConversationOpenTarget.maxExpanded)
        XCTAssertEqual(target?.scroll, "\(account):u0", "the oldest unread newer than the star")
        XCTAssertEqual(target?.expanded, ids(["s", "u0", "u37", "u38", "u39"]),
                       "the star, the scroll target and the newest unread")
        XCTAssertEqual(ThreadRefresh.hydratedOnOpen(messages).count, ConversationOpenTarget.maxExpanded,
                       "only those bodies are read with the payload")
        // The seed marks only bodies the payload brought (and the newest,
        // as before): header-only rows still get their body fetched.
        XCTAssertEqual(Set(ThreadRefresh.initialBodyLoadSeedIds(in: messages)),
                       Set(ids(["s", "u0", "u37", "u38", "u39"])))
        let headerOnly = messages.map { m -> Message in
            var copy = m
            copy.bodyText = ""
            return copy
        }
        XCTAssertEqual(ThreadRefresh.initialBodyLoadSeedIds(in: headerOnly), ["\(account):u39"])
    }

    func testUnreadMailOlderThanTheStarOpensButTheStarLeads() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX UNREAD", unread: true),
                        msg("b", minutesAgo: 40, labels: "INBOX STARRED"),
                        msg("c", minutesAgo: 10, labels: "INBOX")]
        let target = ConversationOpenTarget.target(in: messages)
        XCTAssertEqual(target?.expanded, ids(["a", "b", "c"]))
        XCTAssertEqual(target?.scroll, "\(account):b")
    }

    func testStarOnTheLastMessage() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX"),
                        msg("b", minutesAgo: 10, labels: "INBOX STARRED")]
        let target = ConversationOpenTarget.target(in: messages)
        XCTAssertEqual(target?.expanded, ids(["b"]))
        XCTAssertEqual(target?.scroll, "\(account):b")
    }

    func testSeveralStarsOpenOnTheNewestStarred() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX STARRED"),
                        msg("b", minutesAgo: 40, labels: "INBOX STARRED"),
                        msg("c", minutesAgo: 10, labels: "INBOX")]
        let target = ConversationOpenTarget.target(in: messages)
        XCTAssertEqual(target?.expanded, ids(["b", "c"]))
        XCTAssertEqual(target?.scroll, "\(account):b")
    }

    func testDraftsNeverCount() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX STARRED"),
                        msg("b", minutesAgo: 30, labels: "INBOX"),
                        msg("d", minutesAgo: 10, labels: "DRAFT STARRED UNREAD", unread: true)]
        let target = ConversationOpenTarget.target(in: messages)
        XCTAssertEqual(target?.expanded, ids(["a", "b"]), "the newest non-draft, not the draft")
        XCTAssertEqual(target?.scroll, "\(account):a")
        XCTAssertNil(ConversationOpenTarget.target(in: [msg("d", minutesAgo: 1, labels: "DRAFT STARRED")]))
    }

    func testATrashedStarDoesNotCount() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX"),
                        msg("t", minutesAgo: 30, labels: "TRASH STARRED"),
                        msg("b", minutesAgo: 20, labels: "INBOX")]
        XCTAssertNil(ConversationOpenTarget.target(in: messages))
    }

    // MARK: - Pure helpers

    /// Read on open writes only the thread row: a message row can still
    /// say unread. It is marked all the same.
    func testMarkUnreadFromHereTakesThisAndTheLaterMessages() {
        let messages = [msg("a", minutesAgo: 60, labels: "INBOX"),
                        msg("b", minutesAgo: 40, labels: "INBOX"),
                        msg("c", minutesAgo: 30, labels: "INBOX UNREAD", unread: true),
                        msg("d", minutesAgo: 20, labels: "DRAFT"),
                        msg("e", minutesAgo: 10, labels: "INBOX")]
        XCTAssertEqual(MessageActions.unreadFromHereIds(in: messages, from: "\(account):b"),
                       ["b", "c", "e"], "drafts left out, rows that say unread kept")
        XCTAssertEqual(MessageActions.unreadFromHereIds(in: messages, from: "\(account):x"), [])
        let lone = [msg("a", minutesAgo: 5, labels: "INBOX UNREAD", unread: true)]
        XCTAssertEqual(MessageActions.unreadFromHereIds(in: lone, from: "\(account):a"), ["a"])
    }

    func testFilterPrefillTakesOnlyAPlainAddress() {
        XCTAssertEqual(MessageActions.filterFromAddress("Ann <ann@example.com>"), "ann@example.com")
        XCTAssertEqual(MessageActions.filterFromAddress("ann.b+news@mail.example.com"),
                       "ann.b+news@mail.example.com")
        for crafted in ["\"a b\"@example.com", "a@example.com OR from:b@example.com",
                        "{a@example.com b@example.com}", "a(x)@example.com", "-a@example.com",
                        "a@@example.com", "a@example", "@example.com", "a@example.com\"",
                        "Ann <a@b@example.com>", "a@exa mple.com", "a@.example.com",
                        "Undisclosed recipients:;", ""] {
            let prefill = MessageActions.filterFromAddress(crafted)
            XCTAssertTrue(prefill.isEmpty || !prefill.contains(where: { " \"(){}:".contains($0) }),
                          crafted)
            if crafted.contains(" OR ") || crafted.contains("{") || crafted.contains("\"")
                || crafted.contains("(") || crafted.contains("@@") || crafted.hasPrefix("-") {
                XCTAssertEqual(prefill, "", crafted)
            }
        }
    }

    func testDownloadFilename() {
        XCTAssertEqual(MessageActions.downloadFilename(subject: "Plans"), "Plans.eml")
        XCTAssertEqual(MessageActions.downloadFilename(subject: "  "), "message.eml")
        XCTAssertEqual(MessageActions.downloadFilename(subject: "a/b: c"), "a-b- c.eml",
                       "separators replaced, nothing kept only from the tail")
        XCTAssertEqual(MessageActions.downloadFilename(subject: "...hidden"), "hidden.eml")
        XCTAssertEqual(MessageActions.downloadFilename(subject: ". .x"), "x.eml")
        XCTAssertEqual(MessageActions.downloadFilename(subject: ".\u{0301}x"), "x.eml",
                       "a dot carrying a combining mark is stripped too")
        XCTAssertFalse(MessageActions.downloadFilename(subject: " . \u{0301}. y").hasPrefix("."))
        XCTAssertEqual(MessageActions.downloadFilename(subject: "in\u{202E}voice\u{0007}\n"), "invoice.eml",
                       "bidi override and control characters dropped")
        let long = MessageActions.downloadFilename(subject: String(repeating: "é", count: 400))
        XCTAssertTrue(long.hasSuffix(".eml"))
        XCTAssertLessThanOrEqual(long.utf8.count, MessageActions.filenameBaseByteLimit + 4)
        XCTAssertLessThanOrEqual(MessageActions.downloadFilename(
            subject: String(repeating: "👩‍👩‍👧", count: 100)).utf8.count, 255)
    }

    func testOriginalPreviewIsCutByBytes() {
        let small = Data("Subject: hi\r\n\r\nbody".utf8)
        XCTAssertEqual(MessageActions.originalPreview(small, limit: 1_000).text,
                       "Subject: hi\r\n\r\nbody")
        XCTAssertFalse(MessageActions.originalPreview(small, limit: 1_000).truncated)
        // One grapheme of 50 000 combining marks is still cut at the limit.
        let stuffed = Data(("e" + String(repeating: "\u{0301}", count: 50_000)).utf8)
        let preview = MessageActions.originalPreview(stuffed, limit: 1_000)
        XCTAssertTrue(preview.truncated)
        XCTAssertLessThanOrEqual(preview.text.utf8.count, 1_000 + 3)
    }

    // MARK: - Header controls fit the narrowest pane

    func testHeaderControlsLeaveTheSenderRoomOnTheNarrowestPane() {
        // The narrowest reading pane beside the list: the three-pane
        // threshold less the sidebar's and the list's minimum widths
        // (`ContentView`). The date then takes its compact form.
        let narrowest = MailLayout.threePaneMinimumWidth - 200 - 420
        for scale in [1.0, 1.3] {
            let m = ThreadMessageRowMetrics(fontScale: scale)
            let column = m.textColumnWidth(rowWidth: narrowest)
            let controls = m.headerControlsWidth(count: 4)
            let compactDate: CGFloat = 60 * CGFloat(scale)
            XCTAssertGreaterThan(column - controls - compactDate - 8, 80 * CGFloat(scale),
                                 "the sender keeps room for a name at scale \(scale)")
            XCTAssertEqual(MessageRowDateStyle.forTextColumn(width: column - controls, fontScale: scale),
                           .compact)
        }
        XCTAssertEqual(ThreadMessageRowMetrics(fontScale: 1).headerControlsWidth(count: 0), 0)
    }

    // MARK: - Delete this message (DEC-081)

    func testDeletingOneMessageKeepsTheConversationInTheInbox() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        let before = try thread(q)
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: before, ids: ["b"],
                                                 add: ["TRASH"], remove: [])
        }
        let after = try thread(q)
        XCTAssertTrue(after.inInbox, "still in the Inbox")
        XCTAssertFalse(after.inTrash)
        XCTAssertEqual(after.messageCount, 1)
        XCTAssertEqual(after.snippet, "snippet-a")
        XCTAssertEqual(try shown(q), ["a"], "the deleted message leaves the conversation")
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "b"), "TRASH"))
        // Undo: back, in the Inbox as it was.
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: after, ids: ["b"],
                                                 add: ["INBOX"], remove: ["TRASH"])
        }
        XCTAssertEqual(try shown(q), ["a", "b"])
        XCTAssertEqual(try thread(q).messageCount, 2)
        XCTAssertTrue(try thread(q).inInbox)
    }

    func testAMessageEditKeepsTheThreadsPendingEdits() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX UNREAD", unread: true),
                            msg("b", minutesAgo: 10, labels: "INBOX UNREAD", unread: true)])
        // Read on open: a thread-level edit, on the thread row only.
        let stored = try thread(q)
        var read = stored
        read.isUnread = false
        try q.write { db in try OptimisticThreadWrite.updateChangedColumns(db, from: stored, to: read) }
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: read, ids: ["a"],
                                                 add: ["STARRED"], remove: [])
        }
        let after = try thread(q)
        XCTAssertFalse(after.isUnread, "starring a message must not bring the unread state back")
        XCTAssertTrue(after.isStarred, "the conversation shows as starred")
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "a"), "STARRED"))
        XCTAssertFalse(SyncEngine.labelIdsContain(try labels(q, "b"), "STARRED"), "that message only")
        // Unstar the only starred message: the conversation is not starred.
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: after, ids: ["a"],
                                                 add: [], remove: ["STARRED"])
        }
        XCTAssertFalse(try thread(q).isStarred)
    }

    func testMarkUnreadFromHereMarksTheConversationUnread() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        let row = try thread(q)
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: row, ids: ["b"],
                                                 add: ["UNREAD"], remove: [])
        }
        XCTAssertTrue(try thread(q).isUnread)
        XCTAssertFalse(SyncEngine.labelIdsContain(try labels(q, "a"), "UNREAD"))
    }

    // MARK: - The store's plans, applied to the database

    private func state(_ q: DatabaseQueue, _ id: String) throws -> MessageActionPlan.State {
        let m = try XCTUnwrap(try q.read { try Message.fetchOne($0, key: "\(self.account):\(id)") })
        return try XCTUnwrap(try q.read { try MessageActionPlan.State.load($0, message: m) })
    }

    private func apply(_ q: DatabaseQueue, _ edit: MessageActionPlan.Edit) throws {
        let row = try thread(q)
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: row, ids: edit.ids,
                                                 add: edit.add, remove: edit.remove)
        }
    }

    private func markRead(_ q: DatabaseQueue) throws {
        let stored = try thread(q)
        var read = stored
        read.isUnread = false
        try q.write { db in try OptimisticThreadWrite.updateChangedColumns(db, from: stored, to: read) }
    }

    func testDeletePlanTrashesThatMessageAndItsUndoRestoresIt() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX STARRED")])
        guard case .message(let edit, let undo) = MessageActionPlan.delete(try state(q, "b")) else {
            return XCTFail("one message of two")
        }
        XCTAssertEqual(edit, .init(ids: ["b"], add: ["TRASH"]))
        XCTAssertEqual(undo, .init(ids: ["b"], add: ["INBOX"], remove: ["TRASH"]))
        try apply(q, edit)
        var row = try thread(q)
        XCTAssertTrue(row.inInbox)
        XCTAssertEqual(row.messageCount, 1)
        XCTAssertFalse(row.isStarred, "the starred message left the conversation")
        XCTAssertEqual(MessageActionPlan.delete(try state(q, "b")), .none, "already in the Trash")
        try apply(q, undo)
        row = try thread(q)
        XCTAssertEqual(row.messageCount, 2)
        XCTAssertTrue(row.isStarred)
        XCTAssertTrue(row.inInbox)
    }

    func testUndoDoesNotBringAnArchivedConversationBackToTheInbox() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        // Archived on the thread row only, not yet on its messages.
        let stored = try thread(q)
        var archived = stored
        archived.inInbox = false
        try q.write { db in try OptimisticThreadWrite.updateChangedColumns(db, from: stored, to: archived) }
        guard case .message(_, let undo) = MessageActionPlan.delete(try state(q, "b")) else {
            return XCTFail("one message of two")
        }
        XCTAssertEqual(undo.add, [], "no INBOX: the conversation was archived")
    }

    func testDeletingTheLastMessageTrashesTheConversation() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "TRASH"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        XCTAssertEqual(MessageActionPlan.delete(try state(q, "b")), .conversation)
    }

    func testDeletingTheOnlyMessageBesideADraftKeepsTheDraft() throws {
        let q = try makeDB([msg("b", minutesAgo: 20, labels: "INBOX"),
                            msg("d", minutesAgo: 10, labels: "DRAFT")])
        guard case .message(let edit, _) = MessageActionPlan.delete(try state(q, "b")) else {
            return XCTFail("the draft stays: only the message goes")
        }
        XCTAssertEqual(edit.ids, ["b"])
        try apply(q, edit)
        XCTAssertEqual(try shown(q), ["d"], "the draft is still there")
        XCTAssertFalse(SyncEngine.labelIdsContain(try labels(q, "d"), "TRASH"))
        XCTAssertFalse(try thread(q).inTrash)
    }

    func testDraftsAndTrashedMessagesHaveNothingToDelete() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("t", minutesAgo: 30, labels: "TRASH"),
                            msg("d", minutesAgo: 10, labels: "DRAFT")])
        XCTAssertEqual(MessageActionPlan.delete(try state(q, "t")), .none)
        XCTAssertEqual(MessageActionPlan.delete(try state(q, "d")), .none)
        XCTAssertNil(MessageActionPlan.toggleStar(try state(q, "d")), "no star on a draft")
    }

    func testStarTogglesFromTheStoredState() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        let first = try XCTUnwrap(MessageActionPlan.toggleStar(try state(q, "a")))
        XCTAssertEqual(first, .init(ids: ["a"], add: ["STARRED"]))
        try apply(q, first)
        XCTAssertTrue(try thread(q).isStarred)
        // A second click, read after the first write: it undoes it.
        let second = try XCTUnwrap(MessageActionPlan.toggleStar(try state(q, "a")))
        XCTAssertEqual(second, .init(ids: ["a"], remove: ["STARRED"]))
        try apply(q, second)
        XCTAssertFalse(try thread(q).isStarred)
        XCTAssertEqual(try thread(q).messageCount, 2)
    }

    func testSpamIsRefusedFromATrashedMessage() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("t", minutesAgo: 30, labels: "TRASH")])
        XCTAssertFalse(MessageActionPlan.allowsConversationAction(try state(q, "t")))
        XCTAssertTrue(MessageActionPlan.allowsConversationAction(try state(q, "a")))
    }

    /// Opened unread, so read on the thread row while both message rows
    /// still say unread; "from here" on the first marks both.
    func testMarkUnreadFromHereRightAfterOpeningUnreadMail() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX UNREAD", unread: true)])
        try markRead(q)
        XCTAssertFalse(try thread(q).isUnread)
        let shownNow = try q.read { db in
            try ThreadDetailRepository.fetchPayload(threadId: self.threadId, db: db).messages
        }
        let ids = MessageActions.unreadFromHereIds(in: shownNow, from: "\(account):a")
        XCTAssertEqual(ids, ["a", "b"])
        try apply(q, .init(ids: ids, add: ["UNREAD"]))
        XCTAssertTrue(try thread(q).isUnread)
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "a"), "UNREAD"))
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "b"), "UNREAD"),
                      "the fold must not strip the message being marked")
    }

    func testMarkUnreadOnTheOnlyMessageJustOpened() throws {
        let q = try makeDB([msg("a", minutesAgo: 5, labels: "INBOX UNREAD", unread: true)])
        try markRead(q)
        let shownNow = try q.read { db in
            try ThreadDetailRepository.fetchPayload(threadId: self.threadId, db: db).messages
        }
        let ids = MessageActions.unreadFromHereIds(in: shownNow, from: "\(account):a")
        XCTAssertEqual(ids, ["a"], "something is sent")
        try apply(q, .init(ids: ids, add: ["UNREAD"]))
        XCTAssertTrue(try thread(q).isUnread)
    }

    /// A reply stored by a sync after the action read the thread row is
    /// not marked read by the fold (`applyMessageEdit` reads the row again).
    func testAReplyStoredMeanwhileStaysUnread() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX")])
        let captured = try thread(q)
        try q.write { db in
            try self.msg("r", minutesAgo: 1, labels: "INBOX UNREAD", unread: true).insert(db)
            try SyncEngine.deriveThreads(db, for: [self.threadId], accountId: self.account)
        }
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: captured, ids: ["a"],
                                                 add: ["STARRED"], remove: [])
        }
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "r"), "UNREAD"))
        XCTAssertTrue(try thread(q).isUnread)
    }

    // MARK: - What reaches Gmail, offline and refused

    func testDeleteSendsExactlyThatMessageAndNoDelete() async throws {
        let stub = StubThreadEditing()
        try await RemoteThreadSend.send(.modifyMessages(ids: ["b"], add: ["TRASH"]),
                                        via: stub, gmailThreadId: "t1")
        let calls = await stub.calls
        XCTAssertEqual(calls, [.modifyMessages(ids: ["b"], add: ["TRASH"], remove: [])])
    }

    func testOfflineDeleteThenUndoFoldsInTheQueue() throws {
        let q = try makeDB([])
        try q.write { db in
            try PendingThreadOp.enqueue(db, accountId: self.account, gmailThreadId: "t1",
                                        change: .modifyMessages(ids: ["b"], add: ["TRASH"]))
            try PendingThreadOp.enqueue(db, accountId: self.account, gmailThreadId: "t1",
                                        change: .modifyMessages(ids: ["b"], add: ["INBOX"],
                                                                remove: ["TRASH"]))
        }
        let queued = try q.read { try PendingThreadOp.fetchOne($0)?.change }
        XCTAssertEqual(queued, .modifyMessages(ids: ["b"], add: ["INBOX"], remove: []),
                       "the trash is never sent once undone")
    }

    func testARefusedMessageEditIsUndoneLocally() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        let refused = RemoteThreadChange.modifyMessages(ids: ["b"], add: ["TRASH"])
        XCTAssertEqual(TrashedMessages.storedRestores(in: refused).map(\.ids), [["b"]])
        let row = try thread(q)
        try q.write { db in
            try TrashedMessages.applyMessageEdit(db, thread: row, ids: ["b"],
                                                 add: ["TRASH"], remove: [])
        }
        try q.write { db in
            XCTAssertTrue(try TrashedMessages.revertStoredRestores(db, accountId: self.account,
                                                                   change: refused))
            try OptimisticThreadWrite.rederiveOrDelete(db, threadId: self.threadId, accountId: self.account)
        }
        XCTAssertEqual(try shown(q), ["a", "b"], "Gmail kept it: it is shown again")
    }

    func testTheUndoReTrashStepIsStillNotAStoredEdit() {
        let undo = ThreadUndo.undoTrashRemote(
            wasInInbox: false, before: .init(liveIds: ["b"], trashedIds: ["a"]))
        XCTAssertTrue(TrashedMessages.storedRestores(in: undo).isEmpty)
        let star = RemoteThreadChange.modifyMessages(ids: ["b"], add: ["STARRED"])
        XCTAssertEqual(TrashedMessages.storedRestores(in: undo.merged(with: star)).map(\.ids), [["b"]],
                       "a later message edit in the same queue row is found")
    }

    // MARK: - With the deleted messages of a live conversation (#107)

    private func payload(_ q: DatabaseQueue) throws -> ThreadDetailPayload {
        try q.read { try ThreadDetailRepository.fetchPayload(threadId: self.threadId, db: $0) }
    }

    /// The Restore of a deleted card, as `restoreDeletedMessages` writes it:
    /// the same per-message path as "Delete".
    private func restore(_ q: DatabaseQueue, _ id: String) throws {
        let row = try thread(q)
        guard case .modifyMessages(let ids, let add, let remove) = DeletedMessagesInConversation
            .restoreChange(gmailIds: [id], conversationInInbox: row.inInbox) else {
            return XCTFail("a per-message change")
        }
        try apply(q, .init(ids: ids, add: add, remove: remove))
    }

    private func stillTrashed(_ q: DatabaseQueue) throws -> [String] {
        try q.read { db in
            TrashedMessages.trashedIds(try Message.filter(Column("threadId") == self.threadId).fetchAll(db))
        }
    }

    func testDeletingAMessageShowsTheDeletedLineAndRestoreBringsItBack() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 30, labels: "INBOX"),
                            msg("c", minutesAgo: 10, labels: "INBOX")])
        guard case .message(let edit, let undo) = MessageActionPlan.delete(try state(q, "b")) else {
            return XCTFail("one message of three")
        }
        try apply(q, edit)
        let after = try payload(q)
        XCTAssertEqual(after.messages.map(\.gmailId), ["a", "c"])
        XCTAssertEqual(after.deletedSummary?.count, 1, "the line: 1 deleted message")
        XCTAssertEqual(after.deletedSummary?.messageIds, ["\(account):b"])

        try restore(q, "b")
        let restored = try payload(q)
        XCTAssertEqual(restored.messages.map(\.gmailId), ["a", "b", "c"])
        XCTAssertNil(restored.deletedSummary, "the line goes")
        XCTAssertTrue(try thread(q).inInbox)

        // The delete's undo after a Restore changes nothing.
        let labelsBefore = try labels(q, "b")
        try apply(q, undo)
        XCTAssertEqual(try labels(q, "b"), labelsBefore)
        XCTAssertEqual(try payload(q).messages.map(\.gmailId), ["a", "b", "c"])
    }

    func testRestoreAfterTheUndoHasNothingLeftToRestore() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "INBOX")])
        guard case .message(let edit, let undo) = MessageActionPlan.delete(try state(q, "b")) else {
            return XCTFail("one message of two")
        }
        try apply(q, edit)
        XCTAssertEqual(try stillTrashed(q), ["b"])
        try apply(q, undo)
        // `restoreDeletedMessages` restores only ids that are still trashed.
        XCTAssertEqual(try stillTrashed(q), [], "a late Restore sends nothing")
        XCTAssertNil(try payload(q).deletedSummary)
        XCTAssertEqual(try payload(q).messages.map(\.gmailId), ["a", "b"])
    }

    func testTheOpenTargetIgnoresDeletedMessages() throws {
        // The newest message is deleted, starred and unread: shown through
        // "View" only, it never decides where the conversation opens.
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 30, labels: "INBOX"),
                            msg("c", minutesAgo: 10, labels: "TRASH STARRED UNREAD", unread: true)])
        let live = try payload(q).messages
        XCTAssertEqual(live.map(\.gmailId), ["a", "b"])
        XCTAssertNil(ConversationOpenTarget.target(in: live), "no live star: the usual rule")
        let roles = ThreadMessageRoles(messages: live)
        XCTAssertNil(roles.starredTargetId)
        XCTAssertEqual(roles.lastNonDraftId, "\(account):b")

        // A live star still leads; the deleted unread message is not opened.
        let q2 = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX STARRED"),
                             msg("b", minutesAgo: 30, labels: "INBOX"),
                             msg("c", minutesAgo: 10, labels: "TRASH UNREAD", unread: true)])
        let target = try XCTUnwrap(ConversationOpenTarget.target(in: try payload(q2).messages))
        XCTAssertEqual(target.scroll, "\(account):a")
        XCTAssertEqual(target.expanded, ["\(account):a", "\(account):b"])
    }

    func testADeletedMessageOffersNoDeleteSpamOrBlock() throws {
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 10, labels: "TRASH")])
        let deleted = try state(q, "b")
        XCTAssertEqual(MessageActionPlan.delete(deleted), .none)
        XCTAssertFalse(MessageActionPlan.allowsConversationAction(deleted))
        var context = typical
        context.isTrashed = true
        let items = MessageActions.menuItems(context)
        for gone in [MessageActions.MenuItem.deleteMessage, .blockSender, .unblockSender,
                     .reportSpam, .reportNotSpam] {
            XCTAssertFalse(items.contains(gone), "\(gone)")
        }
    }

    func testARefusedDeleteThenRestoreAllIsRevertedNewestFirst() throws {
        // Offline: "Delete" on b, then #107's "Restore all"
        // on b and c (different ids: two queued steps, not folded). Gmail
        // refuses the whole queued change: b was never trashed there.
        let q = try makeDB([msg("a", minutesAgo: 60, labels: "INBOX"),
                            msg("b", minutesAgo: 30, labels: "INBOX"),
                            msg("c", minutesAgo: 10, labels: "TRASH")])
        let delete = RemoteThreadChange.modifyMessages(ids: ["b"], add: ["TRASH"])
        let restoreAll = DeletedMessagesInConversation.restoreChange(gmailIds: ["b", "c"],
                                                                     conversationInInbox: true)
        try apply(q, .init(ids: ["b"], add: ["TRASH"]))
        try apply(q, .init(ids: ["b", "c"], add: ["INBOX"], remove: ["TRASH"]))
        let refused = delete.merged(with: restoreAll)
        XCTAssertEqual(TrashedMessages.storedRestores(in: refused).count, 2, "two steps")
        try q.write { db in
            XCTAssertTrue(try TrashedMessages.revertStoredRestores(db, accountId: self.account,
                                                                   change: refused))
            try OptimisticThreadWrite.rederiveOrDelete(db, threadId: self.threadId, accountId: self.account)
        }
        XCTAssertFalse(SyncEngine.labelIdsContain(try labels(q, "b"), "TRASH"),
                       "newest first: the delete's revert runs last, b is not left in the Trash")
        XCTAssertTrue(SyncEngine.labelIdsContain(try labels(q, "c"), "TRASH"), "c is deleted again")
    }
}
