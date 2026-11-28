import Foundation

/// A label color Gmail accepts: a background and a text color, both from
/// Gmail's fixed set (`GmailLabelPalette.allowedHex`). `labels.patch`
/// refuses any other value, so there is no way to build one outside it.
struct GmailLabelColor: Equatable, Hashable, Sendable {
    /// `#rrggbb`, lowercase.
    let background: String
    /// `#rrggbb`, lowercase.
    let text: String

    /// nil unless both colors are in Gmail's set (case and `#` are
    /// normalized; anything else is refused).
    init?(background: String?, text: String?) {
        guard let bg = LabelRGB.normalizedHex(background),
              let fg = LabelRGB.normalizedHex(text),
              GmailLabelPalette.allowed.contains(bg),
              GmailLabelPalette.allowed.contains(fg) else { return nil }
        self.background = bg
        self.text = fg
    }

    var colors: LabelColors { LabelColors(background: background, text: text) }
}

/// Gmail's label colors, as listed for `color.backgroundColor` and
/// `color.textColor` in the Gmail API reference (users.labels, the two
/// lists are identical). Frozen here: the API rejects anything else.
enum GmailLabelPalette {
    /// The 102 values the API accepts, in the reference's order.
    static let allowedHex: [String] = [
        "#000000", "#434343", "#666666", "#999999", "#cccccc", "#efefef", "#f3f3f3", "#ffffff",
        "#fb4c2f", "#ffad47", "#fad165", "#16a766", "#43d692", "#4a86e8", "#a479e2", "#f691b3",
        "#f6c5be", "#ffe6c7", "#fef1d1", "#b9e4d0", "#c6f3de", "#c9daf8", "#e4d7f5", "#fcdee8",
        "#efa093", "#ffd6a2", "#fce8b3", "#89d3b2", "#a0eac9", "#a4c2f4", "#d0bcf1", "#fbc8d9",
        "#e66550", "#ffbc6b", "#fcda83", "#44b984", "#68dfa9", "#6d9eeb", "#b694e8", "#f7a7c0",
        "#cc3a21", "#eaa041", "#f2c960", "#149e60", "#3dc789", "#3c78d8", "#8e63ce", "#e07798",
        "#ac2b16", "#cf8933", "#d5ae49", "#0b804b", "#2a9c68", "#285bac", "#653e9b", "#b65775",
        "#822111", "#a46a21", "#aa8831", "#076239", "#1a764d", "#1c4587", "#41236d", "#83334c",
        "#464646", "#e7e7e7", "#0d3472", "#b6cff5", "#0d3b44", "#98d7e4", "#3d188e", "#e3d7ff",
        "#711a36", "#fbd3e0", "#8a1c0a", "#f2b2a8", "#7a2e0b", "#ffc8af", "#7a4706", "#ffdeb5",
        "#594c05", "#fbe983", "#684e07", "#fdedc1", "#0b4f30", "#b3efd3", "#04502e", "#a2dcc1",
        "#c2c2c2", "#4986e7", "#2da2bb", "#b99aff", "#994a64", "#f691b2", "#ff7537", "#ffad46",
        "#662e37", "#ebdbde", "#cca6ac", "#094228", "#42d692", "#16a765",
    ]

    static let allowed: Set<String> = Set(allowedHex)

    /// Columns of the picker grid: one hue per column.
    static let columns = 8

    /// The grids of the "Add custom color" dialog (background and text):
    /// the first 64 values (a grey row, a saturated row, then six rows of
    /// tints, the grid Gmail's own dialog shows), each
    /// with black or white text, whichever contrasts more. Both are in the
    /// set, and one of the two always reaches 4.5:1 (WCAG AA).
    static let swatches: [GmailLabelColor] = allowedHex.prefix(64).map { hex in
        let fill = LabelRGB(hexString: hex)!
        let text = fill.contrast(with: .black) >= fill.contrast(with: .white) ? "#000000" : "#ffffff"
        return GmailLabelColor(background: hex, text: text)!
    }
}

/// Gmail web's "Label color" menu: 30 preset pairs in 5 rows of 6, each
/// a background and a text color.
///
/// Origin: measured from a screenshot of Gmail web's label color menu
/// (November 2026): sampled pixels snapped to the nearest value of the API
/// palette, then checked against Gmail's known legacy pairs where one
/// exists (#f2b2a8/#8a1c0a, #b3efd3/#0b4f30, #ebdbde/#662e37). The third
/// swatch of row 2 is taken as the palette's teal, #2da2bb. Row 4's text
/// colors were uncertain in the screenshot: dark on the light swatches,
/// white on the last, as it reads. All values are in
/// `GmailLabelPalette.allowed`, so `labels.patch` accepts them.
enum GmailLabelColorMenu {
    static let columns = 6

    /// Background, text; in menu order (row by row).
    static let table: [(String, String)] = [
        ("#e7e7e7", "#464646"), ("#b6cff5", "#0d3472"), ("#98d7e4", "#0d3b44"),
        ("#e3d7ff", "#3d188e"), ("#fbd3e0", "#711a36"), ("#f2b2a8", "#8a1c0a"),
        ("#666666", "#ffffff"), ("#285bac", "#ffffff"), ("#2da2bb", "#ffffff"),
        ("#8e63ce", "#ffffff"), ("#994a64", "#ffffff"), ("#cc3a21", "#ffffff"),
        ("#ffc8af", "#7a2e0b"), ("#ffdeb5", "#7a4706"), ("#fbe983", "#594c05"),
        ("#fdedc1", "#684e07"), ("#b3efd3", "#0b4f30"), ("#a2dcc1", "#04502e"),
        ("#ff7537", "#594c05"), ("#ffbc6b", "#594c05"), ("#ebdbde", "#662e37"),
        ("#cca6ac", "#662e37"), ("#68dfa9", "#0b4f30"), ("#44b984", "#ffffff"),
        ("#e66550", "#ffffff"), ("#000000", "#ffffff"), ("#cca6ac", "#ffffff"),
        ("#4a86e8", "#ffffff"), ("#1c4587", "#ffffff"), ("#ff7537", "#ffffff"),
    ]

    static let presets: [GmailLabelColor] = table.map { GmailLabelColor(background: $0.0, text: $0.1)! }

    /// The preset that carries the check mark: the one equal to the label's
    /// colors as drawn (both of them, case and `#` aside), or nil.
    static func checked(_ colors: LabelColors) -> GmailLabelColor? {
        guard let current = GmailLabelColor(background: colors.background, text: colors.text) else { return nil }
        return presets.first { $0 == current }
    }
}

/// The "Add custom color" dialog's choice: a background and a text color
/// from the grids, starting from the label's colors.
struct GmailCustomLabelColor {
    /// The choice when the label has no color (or one the API refuses):
    /// Gmail's light grey with black text.
    static let defaultColor = GmailLabelColor(background: "#cccccc", text: "#000000")!

    private(set) var color: GmailLabelColor

    /// Each of the label's two colors is kept when the API accepts it;
    /// the other falls back to `defaultColor`'s.
    init(current: LabelColors) {
        let bg = GmailLabelColor(background: current.background, text: Self.defaultColor.text)?.background
        let fg = GmailLabelColor(background: Self.defaultColor.background, text: current.text)?.text
        color = GmailLabelColor(background: bg ?? Self.defaultColor.background,
                                text: fg ?? Self.defaultColor.text)!
    }

    /// A value the API refuses changes nothing.
    mutating func pick(background hex: String) {
        if let c = GmailLabelColor(background: hex, text: color.text) { color = c }
    }

    mutating func pick(text hex: String) {
        if let c = GmailLabelColor(background: color.background, text: hex) { color = c }
    }
}

/// Gmail's label color presets (`colorPreset`, e.g.
/// `LABEL_COLOR_PRESET_DARK_GREEN`).
///
/// Source: Google's Gmail MCP server, the `colorPreset` enum of its
/// `update_label` tool schema (where `color` is marked deprecated). This is
/// NOT Gmail REST v1 documentation: neither the users.labels reference nor
/// the v1 discovery document (revision 20261116) lists the field or these
/// colors. The one table of names and colors is `table` below.
enum GmailLabelColorPreset {
    static let prefix = "LABEL_COLOR_PRESET_"

    /// Name (without `prefix`) → background and text, as Google lists them.
    static let colors: [String: GmailLabelColor] = table.mapValues {
        GmailLabelColor(background: $0.0, text: $0.1)!
    }

    /// Internal, not private, so a test checks every pair builds.
    static let table: [String: (String, String)] = [
        "BLACK": ("#000000", "#ffffff"), "DARK_GRAY": ("#434343", "#ffffff"),
        "GRAY": ("#666666", "#ffffff"), "LIGHT_GRAY": ("#cccccc", "#000000"),
        "WHITE": ("#ffffff", "#000000"), "RED": ("#fb4c2f", "#ffffff"),
        "ORANGE": ("#ffad47", "#000000"), "YELLOW": ("#fad165", "#000000"),
        "GREEN": ("#16a765", "#ffffff"), "MINT": ("#43d692", "#000000"),
        "TEAL": ("#2da2bb", "#ffffff"), "BLUE": ("#4a86e8", "#ffffff"),
        "PURPLE": ("#a479e2", "#ffffff"), "PINK": ("#f691b2", "#000000"),
        "DARK_RED": ("#822111", "#ffffff"), "DARK_ORANGE": ("#a46a21", "#ffffff"),
        "DARK_GREEN": ("#076239", "#ffffff"), "DARK_BLUE": ("#1c4587", "#ffffff"),
        "DARK_PURPLE": ("#41236d", "#ffffff"), "DARK_PINK": ("#83334c", "#ffffff"),
        "BROWN": ("#7a4706", "#ffffff"),
    ]

    /// The neutral pair Gmail has been seen to send in `color` for a label
    /// it draws in another color. Not one of the documented values.
    static let neutralFallback = LabelColors(background: "#eeeeee", text: "#222222")

    /// Whether `colors` is exactly the neutral pair (case and `#` aside).
    static func isNeutralFallback(_ colors: LabelColors) -> Bool {
        LabelRGB.normalizedHex(colors.background) == neutralFallback.background
            && LabelRGB.normalizedHex(colors.text) == neutralFallback.text
    }

    /// Whether a listed user label is read again in full (`labels.get`):
    /// it came without a background, or with the neutral pair and no
    /// preset (the full read may carry the preset the list leaves out).
    static func wantsFullRead(_ label: GLabel) -> Bool {
        let listed = GmailLabelColorEdit.colors(of: label)
        if listed.background == nil { return true }
        return isNeutralFallback(listed) && shortName(label.colorPreset) == nil
    }

    /// The preset as shown: the name without `prefix`, or the raw value
    /// when it does not start with it. nil for nil, empty, or the bare
    /// prefix: those say nothing about a preset.
    static func shortName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let name = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        return name.isEmpty ? nil : name
    }

    /// The colors a label is drawn with: Gmail's own pair, unless it is
    /// absent or the neutral fallback and the preset is a known one; then
    /// the preset's pair. An unknown preset changes nothing.
    static func drawnColors(_ gmail: LabelColors, preset: String?) -> LabelColors {
        guard let name = shortName(preset), let mapped = colors[name] else { return gmail }
        let bg = LabelRGB.normalizedHex(gmail.background)
        return bg == nil || isNeutralFallback(gmail) ? mapped.colors : gmail
    }
}

extension LabelRow {
    /// The row for a label this app has just created on Gmail.
    static func created(_ l: GLabel, accountId: String) -> LabelRow {
        LabelRow(id: "\(accountId):\(l.id)", accountId: accountId,
                 gmailLabelId: l.id, name: l.name, type: l.type ?? "user",
                 color: nil,
                 gmailBackgroundColor: LabelRGB.normalizedHex(l.color?.backgroundColor),
                 gmailTextColor: LabelRGB.normalizedHex(l.color?.textColor),
                 listVisibility: l.labelListVisibility,
                 messageListVisibility: l.messageListVisibility,
                 gmailColorPreset: l.colorPreset)
    }

    /// The Gmail color a new sublabel starts with: the parent's as drawn
    /// (pair or preset, DEC-071), as one the API accepts, or nil. Every
    /// preset pair is in Gmail's palette.
    var inheritableGmailColor: GmailLabelColor? {
        let drawn = drawnGmailColors
        return GmailLabelColor(background: drawn.background, text: drawn.text)
    }
}
