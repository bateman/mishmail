import XCTest

/// The header of an open message, as Gmail on the web: after the date, the
/// star, Reply, Reply all and "More" (⋮), whose menu keeps Gmail's order.
/// The star belongs to that message only; a conversation with a starred
/// message opens on it; "Delete" trashes only that message and
/// the conversation stays in the Inbox, with Undo.
/// Demo t7 is one message copied to a second person (Reply all differs from
/// Reply), already starred; demo t2 has four messages, none starred.
final class MessageHeaderActionsUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DREAMAIL_DEMO"] = "1"
        app.launchEnvironment["DREAMAIL_UI_TEST"] = "1"
        app.launchEnvironment["DREAMAIL_DEMO_LABELS"] = "small"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-accentColor", "",
                                "-NSQuitAlwaysKeepsWindows", "NO",
                                "-readingPaneHidden", "NO",
                                "-threadOpenStyle", "readingPane",
                                "-fontScale", "1.0"]
        app.terminate()
        app.launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.appears(timeout: 10))
        app.activate()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Read from one snapshot of the app: reading element by element fails
    /// when a row leaves the pane between two reads (a delete in progress).
    private func frames(_ identifier: String, in app: XCUIApplication) -> [CGRect] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.identifier == identifier, !node.frame.isEmpty { out.append(node.frame) }
            node.children.forEach(walk)
        }
        walk(root)
        return out.sorted { $0.minY < $1.minY }
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// Frames once two reads 0.3 s apart agree and `ready` holds.
    private func settled(_ identifier: String, in app: XCUIApplication,
                         until ready: ([CGRect]) -> Bool) -> [CGRect] {
        var last = frames(identifier, in: app)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let now = frames(identifier, in: app)
            if now == last, ready(now) { return now }
            last = now
        }
        XCTFail("\(identifier) did not settle: \(last)")
        return last
    }

    /// The narrow default window shows the conversation in place of the
    /// list: its back button brings the list back.
    private func showList(_ app: XCUIApplication) {
        let back = app.buttons.matching(identifier: "compactBackButton").firstMatch
        if back.exists { back.click() }
    }

    private func open(_ app: XCUIApplication, _ thread: String) {
        showList(app)
        let row = element(app, "threadRow.you@example.com:\(thread)")
        XCTAssertTrue(row.appears(timeout: 10), thread)
        row.click()
        XCTAssertTrue(element(app, "threadSubject").appears(timeout: 5))
    }

    private func readingPane(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews.containing(
            NSPredicate(format: "identifier == 'threadSubject'")).firstMatch
    }

    func testMessageHeaderActions() {
        let app = launch()
        let steps: [(String, (XCUIApplication) -> Void)] = [
            ("Star, Reply, Reply all and More follow the date", stepControlsFollowTheDate),
            ("More lists Gmail's items in Gmail's order and groups", stepMoreMenuKeepsGmailsOrder),
            ("The star is the message's own; the conversation opens on it", stepStarredMessageOpensTheConversation),
            ("Delete keeps the conversation in the Inbox, with Undo", stepDeleteThisMessage),
        ]
        for (name, step) in steps {
            XCTContext.runActivity(named: name) { _ in step(app) }
        }
    }

    private func stepControlsFollowTheDate(_ app: XCUIApplication) {
        open(app, "t7")
        let ids = ["messageHeaderStar", "messageHeaderReply", "messageHeaderReplyAll", "messageHeaderMore"]
        for id in ids {
            XCTAssertTrue(element(app, id).appears(timeout: 5), "\(id) is in the header")
        }
        let date = element(app, "messageHeaderDate").frame
        let sender = element(app, "messageSender").frame
        let controls = ids.map { element(app, $0).frame }
        print("MessageHeaderActions: sender \(sender), date \(date), controls \(controls)")
        XCTAssertEqual(controls.map(\.minX), controls.map(\.minX).sorted(),
                       "star, reply, reply all, more: in this order")
        XCTAssertGreaterThanOrEqual(controls[0].minX, date.maxX, "after the date")
        XCTAssertLessThanOrEqual(sender.maxX, date.minX + 1, "the sender line ends before the date")
        for frame in controls {
            XCTAssertEqual(frame.midY, date.midY, accuracy: 6, "on the name line")
        }
        XCTAssertEqual(element(app, "messageHeaderStar").label, "Unstar this message",
                       "the starred demo message shows its star")

        // Reply answers the sender only; Reply all keeps the demo Cc.
        // A recipient chip is a button named after the recipient; the
        // quoted original below can name the Cc in plain text.
        let ccChip = NSPredicate(format: "label CONTAINS[c] 'sarah'")
        element(app, "messageHeaderReply").click()
        var compose = openedCompose(app)
        XCTAssertFalse(compose.descendants(matching: .any).matching(identifier: "addressField.Cc")
            .firstMatch.exists, "Reply has no Cc")
        XCTAssertFalse(compose.buttons.matching(ccChip).firstMatch.exists, "Reply leaves the Cc out")
        closeCompose(app)
        element(app, "messageHeaderReplyAll").click()
        compose = openedCompose(app)
        XCTAssertTrue(compose.descendants(matching: .any).matching(identifier: "addressField.Cc")
            .firstMatch.appears(timeout: 5), "Reply all opens with a Cc")
        XCTAssertTrue(compose.buttons.matching(ccChip).firstMatch.appears(timeout: 5),
                      "Reply all keeps the demo Cc recipient")
        closeCompose(app)
    }

    private func openedCompose(_ app: XCUIApplication) -> XCUIElement {
        let compose = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN {'composeCard', 'composeInline'}")).firstMatch
        XCTAssertTrue(compose.appears(timeout: 5), "the compose opens")
        return compose
    }

    /// Esc closes an untouched reply (as `ComposeTabFocusUITests`).
    private func closeCompose(_ app: XCUIApplication) {
        let compose = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN {'composeCard', 'composeInline'}")).firstMatch
        for _ in 0..<3 where compose.exists {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            _ = compose.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(compose.exists, "Esc closes the compose")
    }

    /// The open "More" menu: the menu holding an item only it has, so the
    /// menu bar's own Reply / Forward items never match.
    private func moreMenu(_ app: XCUIApplication) -> XCUIElement {
        app.menus.containing(NSPredicate(format: "title == 'Filter messages like this'")).firstMatch
    }

    private func stepMoreMenuKeepsGmailsOrder(_ app: XCUIApplication) {
        open(app, "t7")
        let more = element(app, "messageHeaderMore")
        XCTAssertTrue(more.appears(timeout: 5))
        more.click()
        // Gmail's groups, a divider between each.
        let groups = [["Reply", "Reply all", "Forward"],
                      ["Delete", "Mark as unread"],
                      ["Block \"Marcus Bell\"", "Report spam"],
                      ["Filter messages like this", "Print", "Download message", "Show original"]]
        let menu = moreMenu(app)
        XCTAssertTrue(menu.appears(timeout: 5), "the menu opens")
        var tops: [[CGFloat]] = []
        for group in groups {
            tops.append(group.map { title in
                let item = menu.menuItems[title]
                XCTAssertTrue(item.exists, "\(title) is in the menu")
                return item.frame.minY
            })
        }
        let flat = tops.flatMap { $0 }
        XCTAssertEqual(flat, flat.sorted(), "Gmail's order")
        // An item's step inside a group; a divider adds to it between groups.
        let step = tops[0][1] - tops[0][0]
        for index in 1..<tops.count {
            let gap = tops[index][0] - (tops[index - 1].last ?? 0)
            XCTAssertGreaterThan(gap, step + 4,
                                 "a divider before \(groups[index][0])")
        }
        for index in tops.indices {
            for (above, below) in zip(tops[index], tops[index].dropFirst()) {
                XCTAssertEqual(below - above, step, accuracy: 1,
                               "no divider inside the group of \(groups[index][0])")
            }
        }
        for gone in ["Report phishing", "Report illegal content", "Translate message",
                     "Share to help improve Google"] {
            XCTAssertFalse(menu.menuItems[gone].exists, "\(gone) is left out, not disabled")
        }
        XCTAssertFalse(menu.menuItems.matching(NSPredicate(format: "title CONTAINS 'Contacts'"))
            .firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Stars the oldest message of t2, then opens t2 again: it opens on
    /// that message, expanded and in view; the newest stays open too (no
    /// unread mail is newer than the star once t2 has been read).
    private func stepStarredMessageOpensTheConversation(_ app: XCUIApplication) {
        open(app, "t2")
        let rows = settled("messageRowFrame", in: app) { $0.count == 4 }
        guard rows.count == 4 else { return }
        // Past the 1 s read-on-open dwell: t2 is read before the star.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let pane = readingPane(app)
        if pane.exists { pane.scroll(byDeltaX: 0, deltaY: 2000) }
        let oldest = app.buttons.matching(identifier: "messageRowExpand")
            .allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(oldest)
        oldest?.click()
        let opened = settled("messageRowFrame", in: app) {
            $0.count == 4 && $0[0].height > $0[1].height + 40
        }
        guard opened.count == 4 else { return }
        // One open message: one star, the oldest's.
        let star = element(app, "messageHeaderStar")
        XCTAssertTrue(star.appears(timeout: 5))
        XCTAssertEqual(star.label, "Star this message")
        star.click()
        XCTAssertTrue(waitUntil { star.label == "Unstar this message" }, "the message is starred")
        XCTAssertEqual(frames("messageHeaderStar", in: app).count, 1,
                       "the other messages keep their own state")

        // Away and back: t2 opens on its starred message.
        open(app, "t1")
        open(app, "t2")
        let reopened = settled("messageRowFrame", in: app) {
            $0.count == 4 && $0.contains { $0.height > 160 }
        }
        guard reopened.count == 4 else { return }
        let heights = reopened.map(\.height)
        print("MessageHeaderActions: rows after reopening \(reopened.map { [$0.minY, $0.height] })")
        XCTAssertGreaterThan(heights[0], heights[1] + 40, "the starred (oldest) message is open")
        XCTAssertLessThan(heights[1], 100, "a read message between them is collapsed")
        XCTAssertLessThan(heights[2], 100)
        XCTAssertGreaterThan(heights[3], heights[1] + 40, "the newest stays open")
        let paneFrame = readingPane(app).frame
        XCTAssertTrue(paneFrame.intersects(reopened[0]), "the starred message is in view")
        XCTAssertGreaterThanOrEqual(reopened[0].minY, paneFrame.minY - 0.5,
                                    "its header is not above the pane")
        let stars = app.descendants(matching: .any).matching(identifier: "messageHeaderStar")
            .allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(stars.first?.label, "Unstar this message", "the top open message is the starred one")

        // Collapsing one of the open cards closes only that one: the date is
        // a real button (keyboard and VoiceOver reach it).
        let collapse = app.buttons.matching(identifier: "messageHeaderDate")
            .allElementsBoundByIndex.filter { !$0.frame.isEmpty }
            .max { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(collapse, "an open message's date is a button")
        collapse?.click()
        let after = settled("messageRowFrame", in: app) { $0.count == 4 && $0[3].height < 100 }
        guard after.count == 4 else { return }
        XCTAssertGreaterThan(after[0].height, after[1].height + 40,
                             "the starred message stays open")
        XCTAssertLessThan(after[3].height, 100, "the newest collapsed")
    }

    /// Deletes the topmost open message of t2 from its More menu.
    private func deleteTopOpenMessage(_ app: XCUIApplication) {
        let more = app.descendants(matching: .any).matching(identifier: "messageHeaderMore")
            .allElementsBoundByIndex.filter { !$0.frame.isEmpty }
            .min { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(more, "an open message has More")
        more?.click()
        let delete = moreMenu(app).menuItems["Delete"]
        XCTAssertTrue(delete.appears(timeout: 5))
        delete.click()
    }

    /// One open message of t2 goes to the Trash alone: the conversation
    /// keeps its other messages and its place in the Inbox; Undo brings
    /// the message back; #107's deleted-messages line then shows it, and
    /// its Restore brings it back too. Independent of the other steps: it takes the top
    /// open message, whichever the conversation opened on.
    private func stepDeleteThisMessage(_ app: XCUIApplication) {
        open(app, "t2")
        let count = settled("messageRowFrame", in: app) { $0.count >= 2 }.count

        // The undo capsule stays 3.5 s: checked and clicked right away.
        deleteTopOpenMessage(app)
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undo.appears(timeout: 3), "the delete offers Undo")
        XCTAssertTrue(waitUntil(3) { self.frames("messageRowFrame", in: app).count == count - 1 },
                      "only that message leaves the conversation")
        if undo.exists { undo.click() }
        let back = settled("messageRowFrame", in: app) { $0.count == count }
        XCTAssertEqual(back.count, count, "Undo brings the message back")

        // Deleted again, without undo: the conversation stays open and in the Inbox.
        deleteTopOpenMessage(app)
        let left = settled("messageRowFrame", in: app) { $0.count == count - 1 }
        XCTAssertEqual(left.count, count - 1, "only that message leaves the conversation")
        XCTAssertTrue(element(app, "threadSubject").exists, "the conversation stays open")
        showList(app)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t2").appears(timeout: 5),
                      "the conversation is still in the Inbox")

        // #107's line agrees: View shows it "In Trash" with Restore as its
        // only action (no star, reply or More), and Restore brings it back.
        open(app, "t2")
        let line = element(app, "thread.deletedMessages")
        XCTAssertTrue(line.appears(timeout: 5), "the deleted-messages line is shown")
        XCTAssertEqual(line.label, "1 deleted message in this conversation")
        let moreBefore = frames("messageHeaderMore", in: app).count
        let view = element(app, "thread.deletedMessages.view")
        XCTAssertTrue(view.appears(timeout: 5))
        view.click()
        XCTAssertTrue(element(app, "messageInTrashTag").appears(timeout: 5))
        let expand = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Open deleted message from'")).firstMatch
        XCTAssertTrue(expand.appears(timeout: 5))
        expand.click()
        let restore = element(app, "messageActionRestore")
        XCTAssertTrue(restore.appears(timeout: 5), "the open deleted message offers Restore")
        XCTAssertLessThanOrEqual(frames("messageHeaderMore", in: app).count, moreBefore,
                                 "the deleted message adds no header controls")
        // The open deleted card can end below the pane: scroll down to it.
        let pane = readingPane(app)
        for attempt in 0..<10 where !restore.isHittable && pane.exists {
            pane.scroll(byDeltaX: 0, deltaY: attempt < 5 ? -150 : 300)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertTrue(restore.isHittable, "Restore is reachable")
        restore.click()
        XCTAssertTrue(waitUntil { !self.element(app, "thread.deletedMessages").exists }, "the line goes")
        let restored = settled("messageRowFrame", in: app) {
            $0.count == count && !self.element(app, "messageInTrashTag").exists
        }
        XCTAssertEqual(restored.count, count, "Restore brings the message back")
    }
}
