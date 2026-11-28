import CoreGraphics

/// Widths of the search field, a flexible toolbar item of the list column
/// (`ListSearchToolbar`). Whether the system really narrows the field to
/// `fieldMinWidth` before moving anything into the » overflow menu is not
/// assumed: `ListSearchFieldUITests` measures the field's width and the
/// toolbar's items at the window's minimum size.
enum ListHeaderLayout {
    static let fieldMinWidth: CGFloat = 140
    static let fieldIdealWidth: CGFloat = 260
    static let fieldMaxWidth: CGFloat = 380
    /// Room kept between the field and the list column's right edge.
    static let columnTrailingInset: CGFloat = 8

    struct FieldWidths: Equatable {
        var min: CGFloat
        var ideal: CGFloat
        var max: CGFloat
        /// Narrower than `fieldMinWidth` would be needed: the field is not shown.
        var hidden: Bool
    }

    /// The field's widths when its left edge is at `fieldMinX` and the list
    /// column ends at `columnMaxX` (window coordinates; nil while not yet
    /// measured). A `.principal` toolbar item is sized to its ideal width and
    /// does not follow the column, so the ideal is bounded by the room left
    /// of the column's edge: the field never crosses into the reading pane.
    static func fieldWidths(fieldMinX: CGFloat?, columnMaxX: CGFloat?) -> FieldWidths {
        guard let fieldMinX, let columnMaxX else {
            return FieldWidths(min: fieldMinWidth, ideal: fieldIdealWidth,
                               max: fieldMaxWidth, hidden: false)
        }
        let room = Swift.max(0, columnMaxX - fieldMinX - columnTrailingInset)
        let ideal = Swift.min(fieldIdealWidth, room)
        return FieldWidths(min: Swift.min(fieldMinWidth, ideal), ideal: ideal,
                           max: Swift.min(fieldMaxWidth, room),
                           hidden: room < fieldMinWidth)
    }
}
