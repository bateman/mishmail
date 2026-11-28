import XCTest

/// The search field is a toolbar item of the list column (`listSearchBox`),
/// right of the view's title, not in the sidebar; the mouse reaches it; the
/// toolbar never overflows at the window's minimum size; and the reading
/// pane's ">>" button is gone. Demo inbox.
final class ListSearchFieldUITests: XCTestCase {
    /// `paneHidden: nil` passes no `-readingPaneHidden`: a launch argument sits in
    /// the defaults' argument domain and overrides what the toggle writes.
    /// `threePaneMinWidth` lowers the three-pane threshold (UI tests only):
    /// the CI screen (1024 pt) is narrower than the real one (1080 pt).
    private func launch(paneHidden: Bool?, openStyle: String = "readingPane",
                        threePaneMinWidth: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let threePaneMinWidth {
            app.launchEnvironment["DREAMAIL_THREE_PANE_MIN_WIDTH"] = String(threePaneMinWidth)
        }
        app.launchEnvironment["DREAMAIL_DEMO"] = "1"
        app.launchEnvironment["DREAMAIL_UI_TEST"] = "1"
        app.launchEnvironment["DREAMAIL_DEMO_LABELS"] = "small"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-accentColor", "",
                                "-NSQuitAlwaysKeepsWindows", "NO",
                                "-threadOpenStyle", openStyle]
        if let paneHidden { app.launchArguments += ["-readingPaneHidden", paneHidden ? "YES" : "NO"] }
        app.terminate()
        app.launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.appears(timeout: 10))
        app.activate()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return true
    }

    /// The text field itself (focus lives here); `listSearchBox` is its box.
    private func textField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == 'Search'")).firstMatch
    }

    private func hasFocus(_ e: XCUIElement) -> Bool {
        (e.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// The view's title in the toolbar (a static text in the top band).
    private func titleElement(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.windows.firstMatch.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text))
            .allElementsBoundByIndex.first { $0.exists && $0.frame.minY < 100 }
            ?? app.windows.firstMatch.staticTexts[text]
    }

    private static var dumpedToolbar = false

    /// What the toolbar really holds, and that it is all there. Asserted
    /// positively: the field, the pane toggle and the focus button exist and
    /// are hittable (so nothing was clipped into an overflow menu), also
    /// "Search all of Gmail" while a search is committed, and Ask AI where the
    /// build shows it. Prints the toolbar once and the field's width.
    private func assertToolbarIntact(_ app: XCUIApplication, _ when: String, searching: Bool = false) {
        let box = element(app, "listSearchBox")
        XCTAssertTrue(box.appears(timeout: 5), "\(when): the field exists")
        if !Self.dumpedToolbar {
            Self.dumpedToolbar = true
            let all = app.toolbars.descendants(matching: .any).allElementsBoundByIndex
                .filter { $0.exists }
                .map { "\($0.elementType.rawValue)|\($0.identifier)|\($0.label)|\($0.frame)" }
            print("ListSearchField toolbar dump: \(all)")
        }
        let window = app.windows.firstMatch
        print("ListSearchField [\(when)]: window \(window.frame), field \(box.frame) (width \(box.frame.width))")
        XCTAssertTrue(box.isHittable, "\(when): the field is hittable (\(box.frame))")
        XCTAssertGreaterThanOrEqual(box.frame.width, ListHeaderMetrics.minWidth - 1,
                                    "\(when): the field is at least its minimum (\(box.frame))")
        let toggle = app.toolbars.buttons.matching(NSPredicate(format: "label ENDSWITH 'Reading Pane'")).firstMatch
        XCTAssertTrue(toggle.exists && toggle.isHittable, "\(when): the pane toggle is in the toolbar and hittable")
        let focus = app.toolbars.buttons.matching(NSPredicate(format: "label == 'Focus Conversation' OR label == 'Exit Focus'")).firstMatch
        XCTAssertTrue(focus.exists && focus.isHittable, "\(when): the focus button is in the toolbar and hittable")
        if searching {
            let all = app.toolbars.buttons.matching(NSPredicate(format: "label CONTAINS 'Search all of Gmail' OR label CONTAINS 'Searching'")).firstMatch
            XCTAssertTrue(all.exists && all.isHittable, "\(when): \"Search all of Gmail\" is in the toolbar and hittable")
        }
        let askAI = app.toolbars.buttons["Ask AI"]
        if askAI.exists { XCTAssertTrue(askAI.isHittable, "\(when): Ask AI is hittable") }
    }

    /// The field against the LIST COLUMN (its rows' x range), the title and the sidebar.
    private func assertFieldInListBar(_ app: XCUIApplication, _ when: String) {
        let field = element(app, "listSearchBox")
        let row = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(field.appears(timeout: 5), "\(when): the field exists")
        XCTAssertTrue(row.appears(timeout: 5))
        let column = row.frame   // the list column's x range
        XCTAssertGreaterThanOrEqual(field.frame.minX, column.minX, "\(when): not left of the list column (\(field.frame) vs \(column))")
        XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX, "\(when): inside the window")
        XCTAssertLessThan(field.frame.maxY, row.frame.minY, "\(when): above the list rows")
        let title = titleElement(app, "Inbox")
        XCTAssertTrue(title.exists, "\(when): the title is shown")
        XCTAssertLessThanOrEqual(title.frame.maxX, field.frame.minX, "\(when): the field is right of the title (title \(title.frame), field \(field.frame))")
        XCTAssertGreaterThanOrEqual(field.frame.width, ListHeaderMetrics.minWidth - 1, "\(when): at least the minimum (\(field.frame))")
        XCTAssertLessThanOrEqual(field.frame.width, ListHeaderMetrics.maxWidth + 1, "\(when): at most the maximum (\(field.frame))")
        let sidebarRow = element(app, "sidebar.inbox")
        if sidebarRow.exists {
            XCTAssertGreaterThan(field.frame.minX, sidebarRow.frame.maxX, "\(when): right of the sidebar")
        }
        assertToolbarIntact(app, when)
    }

    /// A real toolbar item takes the mouse: a click focuses the field, it
    /// takes typing, its clear button appears and works, and the window does
    /// not move.
    private func assertMouseReach(_ app: XCUIApplication, _ when: String) {
        let window = app.windows.firstMatch
        let before = window.frame
        let text = textField(app)
        XCTAssertTrue(text.appears(timeout: 5), "\(when): text field")
        text.click()
        XCTAssertTrue(waitUntil { self.hasFocus(text) }, "\(when): a click focuses the field")
        app.typeText("ab")
        XCTAssertTrue(waitUntil { ((text.value as? String) ?? "") == "ab" }, "\(when): it accepts typing (\(String(describing: text.value)))")
        let clear = element(app, "listSearchBox").buttons["Clear"].firstMatch
        XCTAssertTrue(clear.appears(timeout: 5), "\(when): the clear button appears")
        clear.click()
        XCTAssertTrue(waitUntil { ((text.value as? String) ?? "x").isEmpty }, "\(when): the clear button clears")
        XCTAssertEqual(window.frame, before, "\(when): the window did not move or resize")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    /// Drags the window's bottom-right corner by `dx`: far to the left the
    /// window stops at its minimum size; to the right it grows.
    private func dragCorner(_ app: XCUIApplication, dx: CGFloat) {
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        let target = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: dx, dy: -2))
        corner.press(forDuration: 0.2, thenDragTo: target)
    }

    private func shrinkToMinimum(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        dragCorner(app, dx: -700)
        XCTAssertTrue(waitUntil(timeout: 8) { window.frame.width <= 970 },
                      "the window shrank to its minimum width (now \(window.frame))")
    }

    func testFieldInTheListBar_paneOpen() {
        let app = launch(paneHidden: false)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t3").appears(timeout: 10))
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "composeButton").appears(timeout: 5), "sidebar shown")
        assertFieldInListBar(app, "pane open, sidebar expanded")
        assertMouseReach(app, "pane open, sidebar expanded")
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "sidebarStrip").appears(timeout: 5))
        assertFieldInListBar(app, "pane open, sidebar collapsed")
        assertMouseReach(app, "pane open, sidebar collapsed")
    }

    func testFieldInTheListBar_paneHidden() {
        let app = launch(paneHidden: true)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t3").appears(timeout: 10))
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "composeButton").appears(timeout: 5))
        assertFieldInListBar(app, "pane hidden, sidebar expanded")
        assertMouseReach(app, "pane hidden, sidebar expanded")
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "sidebarStrip").appears(timeout: 5))
        assertFieldInListBar(app, "pane hidden, sidebar collapsed")
        assertMouseReach(app, "pane hidden, sidebar collapsed")
    }

    /// At the window's minimum size, in the sidebar states the app has
    /// (expanded, strip): no overflow chevron and the field is hittable, with
    /// the pane open and hidden.
    func testNoOverflowAtTheMinimumWindow() {
        let app = launch(paneHidden: false)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t3").appears(timeout: 10))
        shrinkToMinimum(app)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "composeButton").appears(timeout: 5))
        assertToolbarIntact(app, "minimum window, sidebar expanded")
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element(app, "sidebarStrip").appears(timeout: 5))
        assertToolbarIntact(app, "minimum window, sidebar collapsed")
        // A search in progress adds "Search all of Gmail" to the bar.
        app.typeKey("/", modifierFlags: [])
        XCTAssertTrue(waitUntil { self.hasFocus(self.textField(app)) })
        app.typeText("zzzznomatch")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(waitUntil { !self.element(app, "threadRow.you@example.com:t3").exists }, "the search is committed")
        assertToolbarIntact(app, "minimum window, searching", searching: true)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    func testSlashFocusesSearchFiltersAndEscRestores() {
        let app = launch(paneHidden: true)
        let t3 = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(t3.appears(timeout: 10))
        let field = element(app, "listSearchBox")
        app.typeKey("/", modifierFlags: [])
        XCTAssertTrue(field.appears(timeout: 5))
        XCTAssertTrue(waitUntil { self.hasFocus(self.textField(app)) }, "/ focuses the field")
        app.typeText("zzzznomatch")
        // The suggestions panel hangs under the field, at the column's leading
        // edge, over the field, inside the column.
        let panel = element(app, "searchResultsPanel")
        XCTAssertTrue(panel.appears(timeout: 5), "the results panel opens")
        print("ListSearchField panel \(panel.frame), field \(field.frame)")
        XCTAssertGreaterThanOrEqual(panel.frame.minY, field.frame.maxY - 1, "panel below the field")
        XCTAssertLessThanOrEqual(panel.frame.minX, field.frame.minX + 1, "panel starts at the column's leading edge, over the field")
        XCTAssertGreaterThanOrEqual(panel.frame.maxX, field.frame.maxX - 1, "panel spans the field")
        XCTAssertGreaterThanOrEqual(panel.frame.minX, t3.frame.minX - 1, "panel inside the list column")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(waitUntil { !t3.exists }, "the search filters the list")
        // Return committed the search and left the field: Esc drops it.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(t3.appears(timeout: 5), "Esc restores the full list")
    }

    /// Compact layout (below 1080 pt; the window is shrunk to its minimum so
    /// the test always runs it): with a conversation open there is no list,
    /// `/` goes back to it and focuses (the pending focus on mount).
    func testSlashFromAConversationInTheCompactLayout() {
        let app = launch(paneHidden: false)
        let t3 = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(t3.appears(timeout: 10))
        shrinkToMinimum(app)
        XCTAssertTrue(t3.appears(timeout: 5))
        t3.click()
        XCTAssertTrue(app.buttons["compactBackButton"].appears(timeout: 5), "a conversation is open")
        XCTAssertFalse(element(app, "listSearchBox").exists, "no field beside an open conversation")
        app.typeKey("/", modifierFlags: [])
        let field = element(app, "listSearchBox")
        XCTAssertTrue(field.appears(timeout: 5), "the list is back")
        XCTAssertTrue(waitUntil { self.hasFocus(self.textField(app)) }, "/ focused the field")
    }

    /// A conversation filling the window (full-window style): `/` leaves it and
    /// focuses the field, as it does in the compact layout.
    func testSlashFromAFullWindowConversation() {
        let app = launch(paneHidden: nil, openStyle: "fullWindow")
        let t3 = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(t3.appears(timeout: 10), "the list")
        t3.click()
        XCTAssertTrue(app.buttons["exitFocusButton"].appears(timeout: 5), "a conversation fills the window")
        app.typeKey("/", modifierFlags: [])
        XCTAssertTrue(waitUntil { !app.buttons["exitFocusButton"].exists }, "/ left the conversation")
        XCTAssertTrue(element(app, "listSearchBox").appears(timeout: 5), "the list is back")
        XCTAssertTrue(waitUntil { self.hasFocus(self.textField(app)) }, "/ focused the field")
    }

    /// The field sits right after the view's title with no conversation open
    /// (the list fills the window), not at the window's far right.
    func testSingleFieldRightAfterTheTitle_listOnly() {
        let app = launch(paneHidden: true)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t3").appears(timeout: 10))
        let box = element(app, "listSearchBox")
        XCTAssertTrue(box.appears(timeout: 5))
        let title = titleElement(app, "Inbox")
        XCTAssertTrue(title.exists, "the title is shown")
        let window = app.windows.firstMatch
        let gap = box.frame.minX - title.frame.maxX
        print("ListSearchField listOnly: window \(window.frame.width), title \(title.frame), field \(box.frame), gap \(gap)")
        XCTAssertGreaterThanOrEqual(gap, 0, "field right of the title (title \(title.frame), field \(box.frame))")
        // The toolbar leaves a constant inset (about 90 pt) after the title.
        XCTAssertLessThanOrEqual(gap, 100, "field right after the title (title \(title.frame), field \(box.frame))")
        XCTAssertLessThan(box.frame.maxX, window.frame.maxX - 200,
                          "field not at the window's far right (field \(box.frame))")
        // Not centred in the free space: the gap does not follow the window's width.
        // Narrower window (it stops at its minimum, so on a small screen it may not shrink).
        let widthBefore = window.frame.width
        dragCorner(app, dx: -200)
        _ = waitUntil(timeout: 5) { window.frame.width < widthBefore - 20 }
        if window.frame.width < widthBefore - 20 {
            let title2 = titleElement(app, "Inbox")
            let box2 = element(app, "listSearchBox")
            XCTAssertTrue(box2.appears(timeout: 5))
            let gap2 = box2.frame.minX - title2.frame.maxX
            print("ListSearchField listOnly narrower: window \(window.frame.width), title \(title2.frame), field \(box2.frame), gap \(gap2)")
            XCTAssertLessThanOrEqual(abs(gap - gap2), 10,
                                     "the gap does not depend on the window's width (\(gap) at \(widthBefore), \(gap2) at \(window.frame.width))")
        } else {
            print("ListSearchField listOnly: the window did not shrink (\(widthBefore)); one width measured")
        }
    }

    /// The list/pane divider: the split view's splitter right of the list rows.
    private func listPaneDivider(_ app: XCUIApplication, row: XCUIElement) -> XCUIElement? {
        app.windows.firstMatch.splitters.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 100 && $0.frame.midX > row.frame.midX }
            .min { $0.frame.minX < $1.frame.minX }
    }

    /// Three panes (the reading pane open beside the list): narrowing the
    /// list column by dragging the list/pane divider shrinks the field, which
    /// stays left of the divider at every width, never across it.
    func testFieldStaysInsideTheListColumn_threePanes() {
        let app = launch(paneHidden: false, threePaneMinWidth: 900)
        let row = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(row.appears(timeout: 10))
        let field = element(app, "listSearchBox")
        XCTAssertTrue(field.appears(timeout: 5))
        guard let first = listPaneDivider(app, row: row) else {
            let all = app.windows.firstMatch.splitters.allElementsBoundByIndex.map { "\($0.frame)" }
            return XCTFail("three panes: no list/pane divider (window \(app.windows.firstMatch.frame), row \(row.frame), splitters \(all))")
        }
        let title = titleElement(app, "Inbox")
        var previousWidth = CGFloat.infinity
        var lastX = first.frame.midX
        var widths = 0
        var sawShrink = false
        // Measured at the starting width, then after each drag to the left,
        // until the divider stops moving (the list column at its minimum).
        for step in 0..<10 {
            if step > 0 {
                guard let divider = listPaneDivider(app, row: row) else { return XCTFail("step \(step): divider gone") }
                let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: -80, dy: 0)))
                // The field follows the column a layout pass later.
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            }
            guard let divider = listPaneDivider(app, row: row) else { return XCTFail("step \(step): divider gone") }
            if step > 0, divider.frame.midX > lastX - 2 { break }
            lastX = divider.frame.midX
            widths += 1
            // Less room than its minimum: the field is hidden and takes no
            // width (or is not exposed at all), never across the divider.
            let f = field.exists ? field.frame : .zero
            if f.width <= 1 {
                print("ListSearchField threePanes [\(step)]: window \(app.windows.firstMatch.frame), divider \(divider.frame), row \(row.frame), title \(title.frame), field hidden (\(f))")
                XCTAssertTrue(sawShrink, "step \(step): hidden only once the field has shrunk for lack of room")
                XCTAssertLessThan(previousWidth, ListHeaderMetrics.minWidth + 120,
                                  "step \(step): hidden only near the minimum (last width \(previousWidth))")
                previousWidth = 0
                continue
            }
            let room = divider.frame.minX - f.minX
            print("ListSearchField threePanes [\(step)]: window \(app.windows.firstMatch.frame), divider \(divider.frame), row \(row.frame), title \(title.frame), field \(f), room \(room)")
            XCTAssertLessThanOrEqual(f.maxX, divider.frame.minX,
                                     "step \(step): the field stays left of the list/pane divider (field \(f), divider \(divider.frame))")
            XCTAssertGreaterThanOrEqual(f.minX, row.frame.minX, "step \(step): not left of the list column")
            XCTAssertLessThanOrEqual(title.frame.maxX, f.minX, "step \(step): right of the title")
            XCTAssertLessThanOrEqual(f.width, previousWidth + 1, "step \(step): a narrower column never widens the field")
            XCTAssertGreaterThanOrEqual(f.width, ListHeaderMetrics.minWidth - 1, "step \(step): shown at least at its minimum (\(f))")
            // It takes the room it has, up to its ideal width: it shrinks with
            // the column, not before.
            XCTAssertGreaterThanOrEqual(f.width, min(ListHeaderMetrics.idealWidth, room - ListHeaderMetrics.trailingInset) - 3,
                                        "step \(step): the field uses the room left of the divider (field \(f), room \(room))")
            XCTAssertTrue(field.isHittable, "step \(step): the field is hittable")
            if room - ListHeaderMetrics.trailingInset < ListHeaderMetrics.idealWidth,
               f.width < ListHeaderMetrics.idealWidth - 1 { sawShrink = true }
            previousWidth = f.width
        }
        XCTAssertGreaterThanOrEqual(widths, 2, "the divider drag narrowed the list column at least once")
        // Some width left less room than the ideal: the field was seen shrinking.
        XCTAssertTrue(sawShrink, "the field shrank with the list column")
    }

    /// List only (no reading pane): the pane toggle and the focus button sit
    /// at the window's right end, right of the field, which stays right after
    /// the title.
    func testPaneButtonsAtTheRightEnd_listOnly() {
        let app = launch(paneHidden: true)
        XCTAssertTrue(element(app, "threadRow.you@example.com:t3").appears(timeout: 10))
        let box = element(app, "listSearchBox")
        XCTAssertTrue(box.appears(timeout: 5))
        let window = app.windows.firstMatch
        let title = titleElement(app, "Inbox")
        XCTAssertTrue(title.exists, "the title is shown")
        let toggle = app.toolbars.buttons.matching(NSPredicate(format: "label ENDSWITH 'Reading Pane'")).firstMatch
        let focus = app.toolbars.buttons.matching(NSPredicate(format: "label == 'Focus Conversation' OR label == 'Exit Focus'")).firstMatch
        XCTAssertTrue(toggle.appears(timeout: 5), "the pane toggle")
        XCTAssertTrue(focus.appears(timeout: 5), "the focus button")
        print("ListSearchField listOnly buttons: window \(window.frame), title \(title.frame), field \(box.frame), toggle \(toggle.frame), focus \(focus.frame)")
        let gap = box.frame.minX - title.frame.maxX
        XCTAssertGreaterThanOrEqual(gap, 0, "field right of the title (title \(title.frame), field \(box.frame))")
        XCTAssertLessThanOrEqual(gap, 100, "field right after the title (title \(title.frame), field \(box.frame))")
        for (name, button) in [("pane toggle", toggle), ("focus button", focus)] {
            XCTAssertGreaterThan(button.frame.minX, box.frame.maxX,
                                 "\(name) right of the field (\(button.frame) vs field \(box.frame))")
            XCTAssertGreaterThanOrEqual(button.frame.maxX, window.frame.maxX - 160,
                                        "\(name) at the window's right end (\(button.frame), window \(window.frame))")
            XCTAssertTrue(button.isHittable, "\(name) hittable")
        }
    }

    func testNoDoubleChevronAndPaneToggleStillWorks() {
        let app = launch(paneHidden: nil)
        let t3 = element(app, "threadRow.you@example.com:t3")
        XCTAssertTrue(t3.appears(timeout: 10))
        let hide = app.buttons.matching(NSPredicate(format: "label == 'Hide Reading Pane'"))
        let show = app.buttons.matching(NSPredicate(format: "label == 'Show Reading Pane'"))
        // The toggle round trip on the list, from whichever state the defaults hold.
        XCTAssertTrue(waitUntil { hide.firstMatch.exists || show.firstMatch.exists }, "the toggle exists")
        let startedOpen = hide.firstMatch.exists
        (startedOpen ? hide : show).firstMatch.click()
        XCTAssertTrue((startedOpen ? show : hide).firstMatch.appears(timeout: 5),
                      "the toggle flips the pane")
        (startedOpen ? show : hide).firstMatch.click()
        XCTAssertTrue((startedOpen ? hide : show).firstMatch.appears(timeout: 5),
                      "the toggle flips it back")
        // Make sure the pane is open. Showing it with a thread selected opens
        // that conversation, and at this window width that replaces the list.
        if show.firstMatch.exists { show.firstMatch.click() }
        XCTAssertTrue(hide.firstMatch.appears(timeout: 5))
        // A conversation open: the old ">>" lived in its toolbar. Exactly one
        // "Hide Reading Pane" control remains: the window's toggle.
        if !element(app, "threadSubject").exists {
            XCTAssertTrue(t3.appears(timeout: 10), "the list is there to open a conversation from")
            t3.click()
        }
        XCTAssertTrue(element(app, "threadSubject").appears(timeout: 5), "a conversation is open")
        XCTAssertTrue(hide.firstMatch.appears(timeout: 5))
        XCTAssertEqual(hide.count, 1, "one \"Hide Reading Pane\" control only: no >> button")
    }
}

/// The field's sizes, as the test sees them (kept equal to `ListHeaderLayout`).
private enum ListHeaderMetrics {
    static let minWidth: CGFloat = 140
    static let idealWidth: CGFloat = 260
    static let maxWidth: CGFloat = 380
    static let trailingInset: CGFloat = 8
}
