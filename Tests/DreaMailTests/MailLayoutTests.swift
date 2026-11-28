import XCTest

final class MailLayoutTests: XCTestCase {
    func testWideWindowUsesThreePanes() {
        XCTAssertEqual(MailLayout.mode(width: 1_200, readingPaneHidden: false,
                                       hasSelection: true), .threePane)
    }

    func testCompactWindowShowsSelectedConversationInsteadOfSqueezingIt() {
        XCTAssertEqual(MailLayout.mode(width: 900, readingPaneHidden: false,
                                       hasSelection: true), .compactDetail)
    }

    func testCompactWindowShowsListWithoutSelection() {
        XCTAssertEqual(MailLayout.mode(width: 900, readingPaneHidden: false,
                                       hasSelection: false), .list)
    }

    func testHiddenReadingPaneAlwaysShowsList() {
        XCTAssertEqual(MailLayout.mode(width: 1_400, readingPaneHidden: true,
                                       hasSelection: true), .list)
    }

    func testThreadFocusFillsTheWindowWhenAConversationIsSelected() {
        XCTAssertEqual(MailLayout.mode(width: 1_200, readingPaneHidden: false,
                                       hasSelection: true, threadFocus: true),
                       .threadFocus)
    }

    func testFullWindowStyleOpensConversationAsFocus() {
        XCTAssertEqual(MailLayout.mode(width: 1_400, readingPaneHidden: false,
                                       hasSelection: true, threadFocus: true,
                                       fullWindowThreads: true),
                       .threadFocus)
    }

    func testFullWindowStyleNeverShowsAReadingPane() {
        // A selection without an explicit open stays on the list — wide
        // windows must not sneak back to three panes.
        XCTAssertEqual(MailLayout.mode(width: 1_400, readingPaneHidden: false,
                                       hasSelection: true,
                                       fullWindowThreads: true),
                       .list)
        XCTAssertEqual(MailLayout.mode(width: 900, readingPaneHidden: true,
                                       hasSelection: true,
                                       fullWindowThreads: true),
                       .list)
    }

    func testFullWindowStyleWithoutSelectionFallsBackToList() {
        XCTAssertEqual(MailLayout.mode(width: 1_200, readingPaneHidden: false,
                                       hasSelection: false, threadFocus: true,
                                       fullWindowThreads: true),
                       .list)
    }

    func testThreadFocusWithoutSelectionFallsBack() {
        XCTAssertEqual(MailLayout.mode(width: 1_200, readingPaneHidden: false,
                                       hasSelection: false, threadFocus: true),
                       .threePane)
        XCTAssertEqual(MailLayout.mode(width: 1_200, readingPaneHidden: true,
                                       hasSelection: false, threadFocus: true),
                       .list)
    }

    /// Collapsing the sidebar to its icon strip never drops the reading
    /// pane: in a 1160 pt window the mailbox host is 1160 − 104 (rail and
    /// strip) collapsed and 1160 − 64 expanded, and both give three panes.
    func testCollapsingTheSidebarKeepsThreePanes() {
        let window: CGFloat = 1_160
        let collapsed = MailLayout.modeWidth(host: window - 104, askAIPanel: 0, stripShown: true)
        let expanded = MailLayout.modeWidth(host: window - 64, askAIPanel: 0, stripShown: false)
        XCTAssertEqual(collapsed, expanded)
        for width in [collapsed, expanded] {
            XCTAssertEqual(MailLayout.mode(width: width, readingPaneHidden: false, hasSelection: true),
                           .threePane)
        }
        // The threshold is where it was before the strip: 1080 + the 64 pt rail.
        XCTAssertEqual(MailLayout.mode(
            width: MailLayout.modeWidth(host: 1_143 - 104, askAIPanel: 0, stripShown: true),
            readingPaneHidden: false, hasSelection: true), .compactDetail)
        XCTAssertEqual(MailLayout.mode(
            width: MailLayout.modeWidth(host: 1_144 - 104, askAIPanel: 0, stripShown: true),
            readingPaneHidden: false, hasSelection: true), .threePane)
        // Ask AI still takes its width.
        XCTAssertEqual(MailLayout.modeWidth(host: 1_000, askAIPanel: 300, stripShown: true), 740)
    }

    /// The threshold override is honoured in UI tests only, and only when valid.
    func testThreePaneThresholdOverrideIsForUITestsOnly() {
        XCTAssertEqual(MailLayout.resolvedThreePaneMinimumWidth(environment: [:]), 1_080)
        XCTAssertEqual(MailLayout.resolvedThreePaneMinimumWidth(
            environment: ["DREAMAIL_THREE_PANE_MIN_WIDTH": "900"]), 1_080)
        XCTAssertEqual(MailLayout.resolvedThreePaneMinimumWidth(
            environment: ["DREAMAIL_UI_TEST": "1", "DREAMAIL_THREE_PANE_MIN_WIDTH": "900"]), 900)
        XCTAssertEqual(MailLayout.resolvedThreePaneMinimumWidth(
            environment: ["DREAMAIL_UI_TEST": "1", "DREAMAIL_THREE_PANE_MIN_WIDTH": "x"]), 1_080)
        XCTAssertEqual(MailLayout.resolvedThreePaneMinimumWidth(
            environment: ["DREAMAIL_UI_TEST": "1", "DREAMAIL_THREE_PANE_MIN_WIDTH": "-5"]), 1_080)
    }
}
