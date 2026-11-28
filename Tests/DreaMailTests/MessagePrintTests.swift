import XCTest

/// "Print" from a message's "More" menu (`MessagePrint`): the header Gmail
/// prints, escaped; the body the pane shows; the pane's CSP.
final class MessagePrintTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2025-11-27 15:04 UTC, a Thursday.
    private let date = Date(timeIntervalSince1970: 1_764_255_840)

    func testDateIsGmailsPrintFormat() {
        XCTAssertEqual(MessagePrint.dateText(date, timeZone: utc), "Thu, Nov 27, 2025 at 3:04 PM")
    }

    func testHeaderShowsSubjectSenderRecipientsAndDate() {
        let header = MessagePrint.headerHTML(
            subject: "Plans", from: "Ann <ann@example.com>", to: "you@example.com",
            cc: "bob@example.com", date: date, timeZone: utc)
        XCTAssertTrue(header.contains(">Plans</div>"))
        XCTAssertTrue(header.contains("Ann &lt;ann@example.com&gt;"))
        XCTAssertTrue(header.contains("To: you@example.com"))
        XCTAssertTrue(header.contains("Cc: bob@example.com"))
        XCTAssertTrue(header.contains("Thu, Nov 27, 2025 at 3:04 PM"))
        let order = ["Plans", "Ann", "To:", "Cc:"].map { header.range(of: $0)!.lowerBound }
        XCTAssertEqual(order, order.sorted(), "subject, sender, To, Cc")
    }

    func testHeaderLeavesOutEmptyCcAndNamesAMissingSubject() {
        let header = MessagePrint.headerHTML(subject: "  ", from: "ann@example.com",
                                             to: "you@example.com", cc: "", date: date)
        XCTAssertFalse(header.contains("Cc:"))
        XCTAssertTrue(header.contains("(no subject)"))
    }

    /// HTML in a subject or a sender name is printed as text.
    func testHeaderValuesAreEscaped() {
        let header = MessagePrint.headerHTML(
            subject: "<img src=\"https://tracker.example.com/p.gif\"> & <b>hi</b>",
            from: "\"<script>x</script>\" <ann@example.com>",
            to: "<i>you</i>@example.com", cc: "\"q\" <c@example.com>", date: date)
        XCTAssertFalse(header.contains("<img"))
        XCTAssertFalse(header.contains("<b>"))
        XCTAssertFalse(header.contains("<script"))
        XCTAssertFalse(header.contains("<i>"))
        XCTAssertTrue(header.contains("&lt;img src=&quot;https://tracker.example.com/p.gif&quot;&gt; &amp; &lt;b&gt;hi&lt;/b&gt;"))
        XCTAssertTrue(header.contains("&quot;&lt;script&gt;x&lt;/script&gt;&quot; &lt;ann@example.com&gt;"))
    }

    func testBodyFollowsThePane() {
        XCTAssertEqual(MessagePrint.body(replacement: nil, showPlainText: false, html: "<p>x</p>", text: "x"),
                       .html("<p>x</p>"))
        XCTAssertEqual(MessagePrint.body(replacement: nil, showPlainText: true, html: "<p>x</p>", text: "x"),
                       .text("x"), "Show plain text")
        XCTAssertEqual(MessagePrint.body(replacement: nil, showPlainText: true, html: "<p>x</p>", text: ""),
                       .html("<p>x</p>"), "no text to show: the pane keeps the HTML")
        XCTAssertEqual(MessagePrint.body(replacement: nil, showPlainText: false, html: nil, text: "plain"),
                       .text("plain"))
        XCTAssertEqual(MessagePrint.body(replacement: nil, showPlainText: false, html: "", text: "plain"),
                       .text("plain"))
    }

    /// OpenPGP: the card's replacement text (decrypted, signed, or a
    /// notice) is printed instead of the body; never the armor.
    func testReplacementTextIsPrintedInsteadOfTheBody() {
        let armor = "-----BEGIN PGP MESSAGE-----"
        XCTAssertEqual(MessagePrint.body(replacement: "secret plans", showPlainText: false,
                                         html: "<p>\(armor)</p>", text: armor),
                       .text("secret plans"))
        XCTAssertEqual(MessagePrint.body(replacement: "a notice", showPlainText: true,
                                         html: "<p>\(armor)</p>", text: armor),
                       .text("a notice"))
    }

    func testPlainTextBodyIsEscaped() {
        let doc = MessagePrint.document(header: "", body: .text("<b>a</b> & b"), allowRemoteImages: false)
        XCTAssertTrue(doc.contains("&lt;b&gt;a&lt;/b&gt; &amp; b"))
        XCTAssertFalse(doc.contains("<b>a</b>"))
    }

    /// The pane's trusted wrapper: CSP first, ahead of any message markup,
    /// and the variant the card's remote-content decision gives.
    func testDocumentUsesThePanesCSP() {
        let body = MessagePrint.Body.html("<img src=\"https://images.example.com/a.png\">")
        let blocked = MessagePrint.document(header: "<div>H</div>", body: body, allowRemoteImages: false)
        let blockedMeta = HTMLBodyCSP.metaTag(allowRemoteImages: false)
        XCTAssertTrue(blocked.hasPrefix("<html><head>\(blockedMeta)"))
        XCTAssertFalse(blocked.contains("img-src data: cid: https:"),
                       "blocked images stay blocked for printing")
        let headerAt = blocked.range(of: "<div>H</div>")!.lowerBound
        let bodyAt = blocked.range(of: "<img")!.lowerBound
        XCTAssertLessThan(headerAt, bodyAt, "the header comes before the body")

        let allowed = MessagePrint.document(header: "", body: body, allowRemoteImages: true)
        XCTAssertTrue(allowed.hasPrefix("<html><head>\(HTMLBodyCSP.metaTag(allowRemoteImages: true))"))
    }

    func testJobIsNamedAfterTheSubject() {
        XCTAssertEqual(MessagePrint.jobTitle(subject: " Plans "), "Plans")
        XCTAssertEqual(MessagePrint.jobTitle(subject: ""), "(no subject)")
    }

    // MARK: - The printer's callbacks (`MessagePrintGate`)

    func testOnlyTheInitialLoadIsAllowed() {
        var gate = MessagePrintGate()
        XCTAssertTrue(gate.allowsNavigation(), "loadHTMLString")
        XCTAssertFalse(gate.allowsNavigation(), "a meta refresh, even to about:blank")
    }

    /// The load's end and the bound both ask to print: one panel only.
    func testPrintingStartsOnce() {
        var gate = MessagePrintGate()
        XCTAssertTrue(gate.startsPrinting())
        XCTAssertFalse(gate.startsPrinting())
        XCTAssertEqual(gate.phase, .printing)
    }

    /// With the panel open nothing navigates and no failure ends the job:
    /// only the panel closing does.
    func testWhilePrintingNavigationsAreRefusedAndFailuresIgnored() {
        var gate = MessagePrintGate()
        XCTAssertTrue(gate.allowsNavigation())
        XCTAssertTrue(gate.startsPrinting())
        XCTAssertFalse(gate.allowsNavigation())
        XCTAssertFalse(gate.endsOnFailure())
        XCTAssertEqual(gate.phase, .printing)
        gate.printingEnded()
        XCTAssertEqual(gate.phase, .done)
        XCTAssertFalse(gate.startsPrinting(), "a late load end opens nothing")
    }

    func testAFailedLoadEndsTheJobBeforePrinting() {
        var gate = MessagePrintGate()
        XCTAssertTrue(gate.endsOnFailure())
        XCTAssertFalse(gate.startsPrinting(), "the bound then prints nothing")
        XCTAssertFalse(gate.allowsNavigation())
    }
}
