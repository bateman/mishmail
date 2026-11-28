import XCTest

/// Gmail web's "Label color" menu (the 30 preset pairs and their check
/// mark) and its "Add custom color" dialog's choice.
final class LabelColorMenuTests: XCTestCase {
    // MARK: - Preset table

    func testTableHas30DistinctPairsInFiveRowsOfSix() {
        XCTAssertEqual(GmailLabelColorMenu.table.count, 30)
        XCTAssertEqual(GmailLabelColorMenu.presets.count, 30)
        XCTAssertEqual(GmailLabelColorMenu.columns, 6)
        XCTAssertEqual(GmailLabelColorMenu.presets.count % GmailLabelColorMenu.columns, 0)
        XCTAssertEqual(GmailLabelColorMenu.presets.count / GmailLabelColorMenu.columns, 5)
        XCTAssertEqual(Set(GmailLabelColorMenu.presets).count, 30, "no duplicate pair")
    }

    /// The table as measured from Gmail web's menu, pinned row by row.
    func testTablePinsGmailsMenu() {
        let rows = stride(from: 0, to: 30, by: 6).map { i in
            GmailLabelColorMenu.table[i..<i + 6].map { "\($0.0)/\($0.1)" }
        }
        XCTAssertEqual(rows[0], ["#e7e7e7/#464646", "#b6cff5/#0d3472", "#98d7e4/#0d3b44",
                                 "#e3d7ff/#3d188e", "#fbd3e0/#711a36", "#f2b2a8/#8a1c0a"])
        XCTAssertEqual(rows[1], ["#666666/#ffffff", "#285bac/#ffffff", "#2da2bb/#ffffff",
                                 "#8e63ce/#ffffff", "#994a64/#ffffff", "#cc3a21/#ffffff"])
        XCTAssertEqual(rows[2], ["#ffc8af/#7a2e0b", "#ffdeb5/#7a4706", "#fbe983/#594c05",
                                 "#fdedc1/#684e07", "#b3efd3/#0b4f30", "#a2dcc1/#04502e"])
        XCTAssertEqual(rows[3], ["#ff7537/#594c05", "#ffbc6b/#594c05", "#ebdbde/#662e37",
                                 "#cca6ac/#662e37", "#68dfa9/#0b4f30", "#44b984/#ffffff"])
        XCTAssertEqual(rows[4], ["#e66550/#ffffff", "#000000/#ffffff", "#cca6ac/#ffffff",
                                 "#4a86e8/#ffffff", "#1c4587/#ffffff", "#ff7537/#ffffff"])
    }

    func testEveryPresetValueIsInTheAPIPalette() {
        for (bg, text) in GmailLabelColorMenu.table {
            XCTAssertTrue(GmailLabelPalette.allowed.contains(bg), bg)
            XCTAssertTrue(GmailLabelPalette.allowed.contains(text), text)
            XCTAssertNotEqual(bg, text)
        }
        // The built pairs are the table, in its order.
        XCTAssertEqual(GmailLabelColorMenu.presets.map(\.background), GmailLabelColorMenu.table.map(\.0))
        XCTAssertEqual(GmailLabelColorMenu.presets.map(\.text), GmailLabelColorMenu.table.map(\.1))
    }

    /// Gmail's own pairs are not all WCAG AA (white on #cca6ac is about
    /// 2.2:1), so this only checks that the text never fades into the fill.
    func testEveryPresetTextStandsOut() {
        for p in GmailLabelColorMenu.presets {
            let fill = LabelRGB(hexString: p.background)!
            let text = LabelRGB(hexString: p.text)!
            XCTAssertGreaterThanOrEqual(text.contrast(with: fill), 2, "\(p.background)/\(p.text)")
        }
    }

    // MARK: - Check mark

    func testCheckedIsTheMatchingPair() {
        let blue = LabelColors(background: "#b6cff5", text: "#0d3472")
        XCTAssertEqual(GmailLabelColorMenu.checked(blue), GmailLabelColor(background: "#b6cff5", text: "#0d3472"))
        // Case and `#` aside.
        XCTAssertEqual(GmailLabelColorMenu.checked(LabelColors(background: "B6CFF5", text: "#0D3472")),
                       GmailLabelColorMenu.checked(blue))
    }

    func testCheckedNeedsBothColors() {
        // Right background, other text: not the preset.
        XCTAssertNil(GmailLabelColorMenu.checked(LabelColors(background: "#b6cff5", text: "#000000")))
        // The reversed pair is not a preset.
        XCTAssertNil(GmailLabelColorMenu.checked(LabelColors(background: "#0d3472", text: "#b6cff5")))
        // Same background, two presets: each is checked by its own text.
        XCTAssertEqual(GmailLabelColorMenu.checked(LabelColors(background: "#cca6ac", text: "#662e37")),
                       GmailLabelColor(background: "#cca6ac", text: "#662e37"))
        XCTAssertEqual(GmailLabelColorMenu.checked(LabelColors(background: "#cca6ac", text: "#ffffff")),
                       GmailLabelColor(background: "#cca6ac", text: "#ffffff"))
        XCTAssertNil(GmailLabelColorMenu.checked(LabelColors(background: "#b6cff5", text: nil)))
    }

    func testNothingCheckedWithoutAColorOrOffThePalette() {
        XCTAssertNil(GmailLabelColorMenu.checked(.none))
        XCTAssertNil(GmailLabelColorMenu.checked(LabelColors(background: "#6E56CF", text: "#ffffff")))
        // In the palette but not a preset.
        XCTAssertNil(GmailLabelColorMenu.checked(LabelColors(background: "#fb4c2f", text: "#ffffff")))
    }

    /// The check follows the pair the label is drawn with (`drawnGmailColors`).
    func testCheckedFollowsTheDrawnColors() {
        let row = LabelRow(id: "a:L", accountId: "a", gmailLabelId: "L", name: "Work", type: "user",
                           color: nil, gmailBackgroundColor: "#e7e7e7", gmailTextColor: "#464646")
        XCTAssertEqual(GmailLabelColorMenu.checked(row.drawnGmailColors),
                       GmailLabelColor(background: "#e7e7e7", text: "#464646"))
    }

    // MARK: - Add custom color

    func testCustomStartsFromTheLabelsColors() {
        let c = GmailCustomLabelColor(current: LabelColors(background: "#FB4C2F", text: "#ffffff"))
        XCTAssertEqual(c.color, GmailLabelColor(background: "#fb4c2f", text: "#ffffff"))
    }

    func testCustomStartsFromTheDefaultWithoutAColor() {
        XCTAssertEqual(GmailCustomLabelColor(current: .none).color, GmailCustomLabelColor.defaultColor)
        XCTAssertEqual(GmailCustomLabelColor.defaultColor,
                       GmailLabelColor(background: "#cccccc", text: "#000000"))
        // The default is on both grids, so it shows checked.
        let grid = GmailLabelPalette.swatches.map(\.background)
        XCTAssertTrue(grid.contains(GmailCustomLabelColor.defaultColor.background))
        XCTAssertTrue(grid.contains(GmailCustomLabelColor.defaultColor.text))
    }

    func testCustomKeepsEachAcceptedColorOnItsOwn() {
        // Off-palette background, valid text: the text stays.
        let c = GmailCustomLabelColor(current: LabelColors(background: "#6E56CF", text: "#ffffff"))
        XCTAssertEqual(c.color, GmailLabelColor(background: "#cccccc", text: "#ffffff"))
        // Valid background, no text.
        let d = GmailCustomLabelColor(current: LabelColors(background: "#16a766", text: nil))
        XCTAssertEqual(d.color, GmailLabelColor(background: "#16a766", text: "#000000"))
    }

    func testApplyGivesThePickedPair() {
        var c = GmailCustomLabelColor(current: .none)
        c.pick(background: "#4a86e8")
        c.pick(text: "#ffffff")
        XCTAssertEqual(c.result(applied: true), GmailLabelColor(background: "#4a86e8", text: "#ffffff"))
    }

    func testCancelGivesNothing() {
        var c = GmailCustomLabelColor(current: LabelColors(background: "#fb4c2f", text: "#ffffff"))
        XCTAssertNil(c.result(applied: false))
        c.pick(background: "#4a86e8")
        XCTAssertNil(c.result(applied: false))
    }

    func testAValueTheAPIRefusesChangesNothing() {
        var c = GmailCustomLabelColor(current: .none)
        c.pick(background: "#123456")
        c.pick(text: "not a color")
        XCTAssertEqual(c.color, GmailCustomLabelColor.defaultColor)
    }

    /// Both grids are the palette's 64-value grid: a grey row, a saturated
    /// row, six rows of tints, eight per row.
    func testCustomGridsAreThePaletteGrid() {
        let grid = GmailLabelPalette.swatches.map(\.background)
        XCTAssertEqual(grid, Array(GmailLabelPalette.allowedHex.prefix(64)))
        XCTAssertEqual(Array(grid.prefix(8)),
                       ["#000000", "#434343", "#666666", "#999999", "#cccccc", "#efefef", "#f3f3f3", "#ffffff"])
        XCTAssertEqual(Array(grid[8..<16]),
                       ["#fb4c2f", "#ffad47", "#fad165", "#16a766", "#43d692", "#4a86e8", "#a479e2", "#f691b3"])
    }
}
