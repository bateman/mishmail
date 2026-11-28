import XCTest

final class ListHeaderLayoutTests: XCTestCase {
    func testFieldWidthsAreOrdered() {
        XCTAssertLessThan(ListHeaderLayout.fieldMinWidth, ListHeaderLayout.fieldIdealWidth)
        XCTAssertLessThan(ListHeaderLayout.fieldIdealWidth, ListHeaderLayout.fieldMaxWidth)
    }
}

final class ListHeaderFieldWidthTests: XCTestCase {
    private typealias L = ListHeaderLayout

    func testNotMeasuredYetKeepsTheDefaults() {
        let w = L.fieldWidths(fieldMinX: nil, columnMaxX: 800)
        XCTAssertEqual(w, .init(min: L.fieldMinWidth, ideal: L.fieldIdealWidth,
                                max: L.fieldMaxWidth, hidden: false))
    }

    func testWideColumnKeepsTheIdealWidth() {
        let w = L.fieldWidths(fieldMinX: 100, columnMaxX: 1000)
        XCTAssertEqual(w.ideal, L.fieldIdealWidth)
        XCTAssertEqual(w.min, L.fieldMinWidth)
        XCTAssertEqual(w.max, L.fieldMaxWidth)
        XCTAssertFalse(w.hidden)
    }

    /// Narrow column: the field shrinks so its right edge stays left of the
    /// column's edge by the inset, and never grows past it.
    func testNarrowColumnShrinksTheFieldInsideTheColumn() {
        let w = L.fieldWidths(fieldMinX: 300, columnMaxX: 508)
        XCTAssertEqual(w.ideal, 200)
        XCTAssertEqual(w.max, 200)
        XCTAssertLessThanOrEqual(300 + w.max, 508 - L.columnTrailingInset)
        XCTAssertEqual(w.min, L.fieldMinWidth)
        XCTAssertFalse(w.hidden)
    }

    /// Below the minimum the field is hidden and takes no width.
    func testBelowTheMinimumTheFieldIsHiddenAndTakesNoWidth() {
        let w = L.fieldWidths(fieldMinX: 300, columnMaxX: 400)
        XCTAssertEqual(w, .init(min: 0, ideal: 0, max: 0, hidden: true))
        XCTAssertEqual(L.fieldWidths(fieldMinX: 500, columnMaxX: 400),
                       .init(min: 0, ideal: 0, max: 0, hidden: true))
        // Exactly the minimum: shown at the minimum.
        let edge = L.fieldWidths(fieldMinX: 300, columnMaxX: 300 + L.fieldMinWidth + L.columnTrailingInset)
        XCTAssertEqual(edge, .init(min: L.fieldMinWidth, ideal: L.fieldMinWidth,
                                   max: L.fieldMinWidth, hidden: false))
    }
}
