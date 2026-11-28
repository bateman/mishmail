import XCTest

/// The sidebar's label menu, as Gmail's (demo mailbox: `Vendors` with the
/// sublabels `Vendors/AWS` and `Vendors/Stripe`; `Research`). The demo
/// mailbox has no Gmail behind it, so the edits stay local.
final class SidebarLabelMenuUITests: XCTestCase {
    private let account = "you@example.com"

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DREAMAIL_DEMO"] = "1"
        app.launchEnvironment["DREAMAIL_UI_TEST"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                                "-accentColor", "",
                                "-NSQuitAlwaysKeepsWindows", "NO",
                                "-threadOpenStyle", "readingPane",
                                "-sidebar.more.expanded", "NO",
                                // Vendors open, so its sublabels are rows.
                                "-sidebar.labels.expanded.\(account)", "(Label_vendors)",
                                "-sidebar.labels.more.\(account)", "NO"]
        app.terminate()
        app.launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.appears(timeout: 10))
        app.activate()
        // Sidebar starts collapsed; → reveals it (see SidebarNavUITests).
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ gmailId: String, in app: XCUIApplication) -> XCUIElement {
        element("sidebar.label.\(account).\(gmailId)", in: app)
    }

    /// A menu item by identifier, or by title where the menu does not carry
    /// SwiftUI's identifier. The first match is the first in menu order.
    private func menuItem(_ id: String, _ title: String, in app: XCUIApplication) -> XCUIElement {
        app.menuItems.matching(NSPredicate(format: "identifier == %@ OR title == %@", id, title)).firstMatch
    }

    /// Scrolls the sidebar until `element` can be clicked: the demo has
    /// some 70 labels, so Vendors and the labels' More row start below the
    /// fold.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let sidebar = app.outlines.firstMatch
        for step in [-300.0, 300.0] {
            var tries = 0
            while !(element.exists && element.isHittable), tries < 15 {
                sidebar.scroll(byDeltaX: 0, deltaY: step)
                tries += 1
            }
            if element.exists && element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }

    /// Clicks the ⋮ where it is drawn. XCUITest's own `click()` refuses the
    /// ⋮ as "not hittable" on the CI runners, in a way that comes and goes
    /// from one run to the next whatever the label is (a SwiftUI menu, a
    /// borderless one, an image), and scrolls the sidebar away from under
    /// the pointer, so the ⋮ vanishes. What `isHittable` would prove is
    /// checked here instead: the ⋮ lies inside the row and inside the
    /// window; and that it receives the click is proved by the callers (the
    /// menu opens, the row does not reopen). The frames go to the log.
    private func clickDots(_ dots: XCUIElement, in row: XCUIElement, app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        let box = dots.frame
        let window = app.windows.firstMatch.frame
        print("SidebarLabelMenu: ⋮ frame \(box), row \(row.frame), window \(window), hittable \(dots.isHittable)")
        XCTAssertTrue(window.contains(box), "the ⋮ \(box) is inside the window \(window)",
                      file: file, line: line)
        XCTAssertTrue(row.frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: box.midX, y: box.midY)),
                      "the ⋮ \(box) is inside its row \(row.frame)", file: file, line: line)
        dots.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    func testMenuFromDotsAndRightClickAndDotsDoNotReopenTheLabel() {
        let app = launch()
        let research = label("Label_research", in: app)
        XCTAssertTrue(research.appears(timeout: 10))
        research.hover()
        let dots = element("sidebar.label.menu.\(account).Label_research", in: app)
        XCTAssertTrue(dots.appears(timeout: 5), "hovering a label shows its ⋮")
        clickDots(dots, in: research, app: app)
        let items: [(String, String)] = [
            ("labelMenu.color", "Label color"),
            ("labelMenu.labelList.show", "Show"),
            ("labelMenu.labelList.showIfUnread", "Show if unread"),
            ("labelMenu.labelList.hide", "Hide"),
            ("labelMenu.edit", "Edit"),
            ("labelMenu.remove", "Remove label"),
            ("labelMenu.addSublabel", "Add sublabel"),
            ("labelMenu.organize", "Organize Labels…"),
        ]
        for (id, title) in items {
            XCTAssertTrue(menuItem(id, title, in: app).appears(timeout: 5),
                          "\(title) must be in the ⋮ menu\n\(app.debugDescription)")
        }
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        research.rightClick()
        for (id, title) in items {
            XCTAssertTrue(menuItem(id, title, in: app).appears(timeout: 5),
                          "\(title) must be in the context menu")
        }
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        // On the open label, "⋮" opens the menu only: it must not also run
        // the row's tap, which would reopen the label and close the open
        // conversation. (One launch for both checks: the UI job has a time
        // budget.)
        research.click()
        let row = element("threadRow.\(account):t2", in: app)
        XCTAssertTrue(row.appears(timeout: 5))
        row.click()
        let subject = app.staticTexts.matching(identifier: "threadSubject").firstMatch
        XCTAssertTrue(subject.appears(timeout: 5), "the conversation is open")

        research.hover()
        XCTAssertTrue(dots.appears(timeout: 5), "the open label shows its ⋮")
        clickDots(dots, in: research, app: app)
        XCTAssertTrue(menuItem("labelMenu.edit", "Edit", in: app).appears(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(subject.exists, "the ⋮ click did not reopen the label")
        // Gmail's "⋮" is vertical: its box is taller than wide (the old
        // horizontal ellipsis, drawn by AppKit, was wider than tall). Read
        // last, on the open label (which keeps its ⋮ without hover): reading
        // the frame before a click left the click "not hittable" in CI.
        XCTAssertTrue(dots.appears(timeout: 5), "the open label keeps its ⋮")
        XCTAssertGreaterThan(dots.frame.height, dots.frame.width, "the ⋮ is three dots stacked")
        // And no heavier than the sidebar's other glyphs: its box is not
        // taller than the row's title text plus a small margin.
        let title = research.staticTexts.firstMatch
        XCTAssertTrue(title.exists, "the label row has its title")
        XCTAssertLessThanOrEqual(dots.frame.height, title.frame.height + 4,
                                 "the ⋮ \(dots.frame) is taller than the title \(title.frame)")
    }

    /// Opens "Label color ▸ Choose color…" on `label`.
    private func openColorSheet(_ label: XCUIElement, in app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        label.rightClick()
        let color = menuItem("labelMenu.color", "Label color", in: app)
        XCTAssertTrue(color.appears(timeout: 5), file: file, line: line)
        color.hover()
        let choose = menuItem("labelMenu.color.choose", "Choose color…", in: app)
        XCTAssertTrue(choose.appears(timeout: 5), file: file, line: line)
        choose.click()
    }

    private func presets(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'labelColor.preset.'"))
    }

    func testColorSheetIsGmailsMenuAndRemoveAsksFirst() {
        let app = launch()
        let vendors = label("Label_vendors", in: app)
        let aws = label("Label_vendors_aws", in: app)
        XCTAssertTrue(vendors.appears(timeout: 10))
        XCTAssertTrue(reveal(vendors, in: app), "Vendors can be scrolled to")
        XCTAssertTrue(aws.appears(timeout: 5), "Vendors starts open")

        openColorSheet(vendors, in: app)
        let swatch = element("labelColor.preset.#e7e7e7.#464646", in: app)
        XCTAssertTrue(swatch.appears(timeout: 5), "the sheet shows Gmail's preset pairs")
        // Gmail's menu: 30 preset pairs, "Add custom color", "Remove color".
        XCTAssertEqual(presets(in: app).count, 30, "30 preset pairs")
        XCTAssertTrue(element("labelColor.addCustom", in: app).exists, "Add custom color is there")
        XCTAssertTrue(element("labelColor.remove", in: app).exists, "Remove color is there")
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'labelColor.gmail.'")).count, 0, "no 64-colour grid in the menu")
        // The sheet hugs the palette: no empty half, Done close to its edge.
        let palette = element("labelColor.palette", in: app)
        let sheet = app.sheets.firstMatch
        let done = element("labelColor.done", in: app)
        XCTAssertTrue(palette.exists && sheet.exists && done.exists, "palette, sheet and Done exist")
        // The palette's frame excludes its own padding: add it back on both sides.
        let paletteWidth = palette.frame.width + 2 * (palette.frame.minX - sheet.frame.minX)
        XCTAssertEqual(sheet.frame.width, paletteWidth, accuracy: 2,
                       "the sheet \(sheet.frame) is as wide as the palette \(palette.frame) with its padding")
        XCTAssertLessThanOrEqual(done.frame.maxX, palette.frame.maxX + 16,
                                 "Done \(done.frame) is not far beyond the palette \(palette.frame)")
        // Every swatch fits inside the sheet.
        for i in 0..<presets(in: app).count {
            let frame = presets(in: app).element(boundBy: i).frame
            XCTAssertTrue(sheet.frame.contains(frame), "swatch \(frame) inside the sheet \(sheet.frame)")
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'labelColor.mac.'")).count, 0, "no Mac-only swatches")
        XCTAssertFalse(element("labelColor.current.gmail", in: app).exists, "no Current line")
        XCTAssertFalse(element("labelColor.current.mac", in: app).exists, "no Mac-only Current line")
        XCTAssertFalse(app.staticTexts["Only on this Mac"].exists, "no Mac-only section")
        XCTAssertFalse(app.staticTexts["Also shown in Gmail on the web and on your phone."].exists,
                       "no caption")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(swatch), "Escape closes the sheet")

        // Remove asks first, and Cancel keeps the label (same launch: the UI
        // job has a time budget).
        XCTAssertTrue(reveal(vendors, in: app))
        vendors.rightClick()
        let remove = menuItem("labelMenu.remove", "Remove label", in: app)
        XCTAssertTrue(remove.appears(timeout: 5))
        remove.click()
        let cancel = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR title == %@", "labelRemove.cancel", "Cancel")).firstMatch
        XCTAssertTrue(cancel.appears(timeout: 5), "Remove asks for confirmation")
        // Return presses the default button, Cancel.
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(cancel))
        XCTAssertTrue(vendors.exists, "Cancel keeps the label")
        XCTAssertTrue(aws.exists, "and its sublabel")
    }

    func testHideInLabelListMovesTheLabelUnderMore() {
        let app = launch()
        let research = label("Label_research", in: app)
        XCTAssertTrue(research.appears(timeout: 10))
        let more = element("sidebar.labels.more.\(account)", in: app)
        XCTAssertFalse(more.exists, "every demo label is shown: no labels' More row")

        research.rightClick()
        let hide = menuItem("labelMenu.labelList.hide", "Hide", in: app)
        XCTAssertTrue(hide.appears(timeout: 5))
        hide.click()

        XCTAssertTrue(waitForAbsence(research), "a hidden label leaves the list")
        XCTAssertTrue(more.appears(timeout: 5), "and goes behind the labels' More row")
        XCTAssertTrue(reveal(more, in: app), "the labels' More row can be scrolled to")
        more.click()
        XCTAssertTrue(research.appears(timeout: 5), "More shows it")
        // Closed means closed: the open label goes too.
        research.click()
        XCTAssertTrue(reveal(more, in: app))
        more.click()
        XCTAssertTrue(waitForAbsence(research), "a closed More hides the open label as well")
    }

    /// A sublabel of a listed parent is always shown nested under it, in
    /// place, whatever its own list visibility (Gmail's sidebar): hiding
    /// Vendors/Stripe through its menu sets Gmail's value but changes nothing
    /// here: no More row, no path name, the parent's name once.
    func testHiddenSublabelStaysNestedUnderItsListedParent() {
        let app = launch()
        let vendors = label("Label_vendors", in: app)
        let aws = label("Label_vendors_aws", in: app)
        let stripe = label("Label_vendors_stripe", in: app)
        let more = element("sidebar.labels.more.\(account)", in: app)
        XCTAssertTrue(reveal(vendors, in: app))
        XCTAssertTrue(aws.appears(timeout: 5))
        XCTAssertTrue(stripe.exists)
        XCTAssertFalse(more.exists, "every demo label is shown: no labels' More row")

        stripe.rightClick()
        let hide = menuItem("labelMenu.labelList.hide", "Hide", in: app)
        XCTAssertTrue(hide.appears(timeout: 5))
        hide.click()
        // Give a wrong removal time to show before asserting the row stays.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(stripe.exists, "a hidden sublabel of a listed parent stays listed")
        XCTAssertFalse(more.exists, "and needs no More row")
        // Inside Vendors' subtree: after its sibling, indented like it.
        XCTAssertLessThan(vendors.frame.minY, aws.frame.minY)
        XCTAssertLessThan(aws.frame.minY, stripe.frame.minY, "in sibling order, under AWS")
        XCTAssertEqual(stripe.frame.minX, aws.frame.minX, accuracy: 1, "indented like its siblings")
        // Short names, no path: the demo has labels named "Starred / keep",
        // so look at the sublabels' own rows, not at every text.
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(stripe.staticTexts["Stripe"].exists, "the sublabel shows its short name")
        XCTAssertTrue(aws.staticTexts["AWS"].exists)
        XCTAssertFalse(sidebar.staticTexts["Vendors/Stripe"].exists, "no row is named with a path")
        XCTAssertFalse(sidebar.staticTexts["Vendors/AWS"].exists)
        XCTAssertEqual(sidebar.staticTexts.matching(NSPredicate(
            format: "label == 'Vendors' OR identifier == 'Vendors'")).count, 1,
                       "the parent's name appears once")
    }

    /// The demo's Work label has Gmail color #6E56CF, which is not one of
    /// the presets: the presets are there and none is checked.
    func testColorSheetChecksNoPresetForAnOffGridColor() {
        let app = launch()
        let work = label("Label_work", in: app)
        XCTAssertTrue(work.appears(timeout: 10))
        openColorSheet(work, in: app)
        let remove = element("labelColor.remove", in: app)
        XCTAssertTrue(remove.appears(timeout: 5), "the sheet has Remove color")
        let swatches = presets(in: app)
        XCTAssertEqual(swatches.count, 30, "the presets are there")
        for i in 0..<swatches.count {
            XCTAssertFalse(swatches.element(boundBy: i).isSelected, "no preset is checked for an off-grid color")
        }
    }

    /// "Add custom color": the dialog replaces the menu with a preview and
    /// both grids (64 values each), inside the sheet. Work's color is off
    /// the API palette, so the choice starts at the default pair. Cancel
    /// closes it; Apply closes it too (the demo refuses the Gmail write, so
    /// the write itself is not covered here).
    func testAddCustomColorDialogHasBothGridsAndFits() {
        let app = launch()
        let work = label("Label_work", in: app)
        XCTAssertTrue(work.appears(timeout: 10))
        openColorSheet(work, in: app)
        let add = element("labelColor.addCustom", in: app)
        XCTAssertTrue(add.appears(timeout: 5))
        add.click()

        let dialog = element("labelColor.custom", in: app)
        XCTAssertTrue(dialog.appears(timeout: 5), "the custom dialog opens")
        XCTAssertTrue(app.staticTexts["Add custom color"].exists, "with Gmail's title")
        XCTAssertTrue(app.staticTexts["Preview label color - pick colors below."].exists, "and the preview line")
        XCTAssertTrue(element("labelColor.custom.preview", in: app).exists, "the preview chip")
        XCTAssertEqual(presets(in: app).count, 0, "the menu is gone")
        let background = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'labelColor.custom.background.'"))
        let text = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'labelColor.custom.text.'"))
        XCTAssertEqual(background.count, 64, "the background grid")
        XCTAssertEqual(text.count, 64, "the text grid")
        let cancel = element("labelColor.custom.cancel", in: app)
        let apply = element("labelColor.custom.apply", in: app)
        XCTAssertTrue(cancel.exists && apply.exists, "Cancel and Apply")

        // Everything fits inside the sheet; the grids sit side by side.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists)
        let bgGrid = element("labelColor.custom.background", in: app).frame
        let textGrid = element("labelColor.custom.text", in: app).frame
        for frame in [bgGrid, textGrid, cancel.frame, apply.frame,
                      element("labelColor.custom.preview", in: app).frame,
                      background.element(boundBy: 63).frame, text.element(boundBy: 63).frame] {
            XCTAssertTrue(sheet.frame.contains(frame), "\(frame) inside the sheet \(sheet.frame)")
        }
        XCTAssertLessThan(bgGrid.maxX, textGrid.minX, "Background left of Text")
        XCTAssertEqual(bgGrid.minY, textGrid.minY, accuracy: 2, "side by side")

        // The default pair is checked, one swatch per grid; a click moves it.
        let grey = element("labelColor.custom.background.#cccccc", in: app)
        XCTAssertTrue(grey.isSelected, "default background checked")
        XCTAssertTrue(element("labelColor.custom.text.#000000", in: app).isSelected, "default text checked")
        XCTAssertEqual((0..<background.count).filter { background.element(boundBy: $0).isSelected }.count, 1,
                       "one background checked")
        let red = element("labelColor.custom.background.#fb4c2f", in: app)
        red.click()
        XCTAssertTrue(red.isSelected, "the click selects the background")
        XCTAssertFalse(grey.isSelected, "and unchecks the old one")

        cancel.click()
        XCTAssertTrue(waitForAbsence(dialog), "Cancel closes the dialog")

        openColorSheet(work, in: app)
        XCTAssertTrue(add.appears(timeout: 5), "the sheet opens on the menu again")
        add.click()
        XCTAssertTrue(dialog.appears(timeout: 5))
        XCTAssertTrue(grey.isSelected, "Cancel kept nothing: the choice starts over")
        apply.click()
        XCTAssertTrue(waitForAbsence(dialog), "Apply closes the dialog")
    }
}
