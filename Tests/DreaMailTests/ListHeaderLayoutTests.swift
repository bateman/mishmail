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

    /// Below the minimum the field is hidden and takes no more than the room.
    func testBelowTheMinimumTheFieldIsHiddenAndNeverCrosses() {
        let w = L.fieldWidths(fieldMinX: 300, columnMaxX: 400)
        XCTAssertTrue(w.hidden)
        XCTAssertEqual(w.ideal, 92)
        XCTAssertLessThanOrEqual(w.min, w.ideal)
        XCTAssertEqual(w.max, 92)
        let none = L.fieldWidths(fieldMinX: 500, columnMaxX: 400)
        XCTAssertTrue(none.hidden)
        XCTAssertEqual(none.ideal, 0)
        XCTAssertEqual(none.max, 0)
    }
}
