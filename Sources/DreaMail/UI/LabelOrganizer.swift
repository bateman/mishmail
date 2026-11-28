import SwiftUI

/// Organize labels: drag to reorder and pick a color per label. The order is
/// local. A label's color is its color on Gmail (written with
/// labels.patch, shown on the web and the phone too). It drives the label
/// pills, the Labels filter dropdown, and the "l" picker everywhere in the
/// app.
struct LabelOrganizer: View {
    @Environment(MailStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Organize Labels")
                    .font(.headline)
                Spacer()
                // With more than one account, labels are scoped per account
                // (Gmail ids don't cross accounts).
                if store.accounts.count > 1 {
                    Picker("", selection: $selectedAccount) {
                        ForEach(store.accounts) { account in
                            Text(AccountLabelColor.title(account)).tag(String?.some(account.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            Text("Drag to reorder (only on this Mac); sublabels move with their label and stay under it. Click a swatch to change the color on Gmail. A label's color also goes to its sublabels.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 8)

            Divider()

            let account = resolvedAccount
            let labels = account.map { store.userLabels(forAccount: $0) } ?? []
            let entries = LabelOrganizerOrder.entries(
                tree: account.flatMap { store.labelTrees[$0] } ?? [], rows: labels)
            if labels.isEmpty {
                ContentUnavailableView("No labels",
                                       systemImage: "tag",
                                       description: Text("Labels you create in Gmail show up here."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(entries) { entry in
                        LabelOrganizerRow(entry: entry)
                    }
                    .onMove { source, destination in
                        // A drop that would leave the label's family (or land
                        // inside another) is refused: the row goes back.
                        if let account, source.count == 1, let from = source.first,
                           let order = LabelOrganizerOrder.moved(entries, from: from, to: destination) {
                            store.reorderLabels(account: account, to: order)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }

            Divider()
            HStack {
                Button("Use Gmail's Order") {
                    if let account { store.resetLabelOrder(account: account) }
                }
                .disabled(!labels.contains { $0.sortOrder != LabelRow.unsorted })
                .help("Forget the order set here for this account's labels and list them as Gmail does.")
                .accessibilityIdentifier("labelOrganizer.useGmailOrder")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 440, height: 480)
        // Escape closes it: "Done" is only the default action.
        .onExitCommand { dismiss() }
        .onAppear {
            if selectedAccount == nil {
                selectedAccount = store.activeAccountId ?? store.accounts.first?.id
            }
        }
    }

    private var resolvedAccount: String? {
        selectedAccount ?? store.activeAccountId ?? store.accounts.first?.id
    }
}

/// One organizer row: a color swatch (opens a palette), the label name, and a
/// drag handle courtesy of List's move support.
private struct LabelOrganizerRow: View {
    @Environment(MailStore.self) var store
    let entry: LabelOrganizerEntry
    private var label: LabelRow { entry.row }
    @State private var showPalette = false

    var body: some View {
        HStack(spacing: 10) {
            Button { showPalette = true } label: {
                LabelDot(colors: label.displayColors, size: 18)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPalette, arrowEdge: .bottom) {
                LabelColorChooser(label: label, title: nil) { showPalette = false }
            }

            Text(entry.displayName).font(.system(size: 13))
                .help(label.name)
                .accessibilityLabel(label.name)
                .accessibilityIdentifier("labelOrganizer.name.\(label.id)")
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(entry.depth) * 18)
    }
}

/// The label color chooser: Gmail's "Label color" menu, replaced by its
/// "Add custom color" dialog once that is chosen. Shown by the sidebar's
/// sheet (with a title and Done) and by the organizer's popover.
struct LabelColorChooser: View {
    let label: LabelRow
    /// The sheet's heading; nil in the popover.
    let title: String?
    let onClose: () -> Void
    @State private var addingCustom = false

    var body: some View {
        if addingCustom {
            LabelCustomColorDialog(label: label, onClose: onClose)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(verbatim: title).font(.headline)
                        .lineLimit(1).truncationMode(.middle)
                        .padding([.top, .horizontal], 12)
                }
                LabelColorPalette(label: label, onPick: onClose) { addingCustom = true }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("labelColor.palette")
                if title != nil {
                    HStack {
                        Spacer()
                        Button("Done", action: onClose)
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("labelColor.done")
                    }
                    .padding([.bottom, .horizontal], 12)
                }
            }
            // As wide as the palette (244 pt, its own padding included).
            .frame(width: 244)
        }
    }
}

/// Gmail's "Label color" menu: the 30 preset pairs (`GmailLabelColorMenu`),
/// each a circle in the background color with an "a" in the text color,
/// the current one checked; then "Add custom color" and "Remove color".
struct LabelColorPalette: View {
    @Environment(MailStore.self) var store
    let label: LabelRow
    let onPick: () -> Void
    let onAddCustom: () -> Void

    private static let size: CGFloat = 28
    private let columns = Array(repeating: GridItem(.fixed(LabelColorPalette.size), spacing: 8),
                                count: GmailLabelColorMenu.columns)

    var body: some View {
        let saving = store.gmailLabelColorSaving.contains(label.id)
        let checked = GmailLabelColorMenu.checked(label.drawnGmailColors)
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(GmailLabelColorMenu.presets, id: \.self) { preset in
                    Button {
                        store.setGmailLabelColor(label, to: preset)
                        onPick()
                    } label: {
                        LabelColorPresetSwatch(color: preset, checked: preset == checked, size: Self.size)
                    }
                    .buttonStyle(.plain)
                    .help("\(preset.background) with \(preset.text) text")
                    .accessibilityLabel("Background \(preset.background), text \(preset.text)")
                    .accessibilityIdentifier("labelColor.preset.\(preset.background).\(preset.text)")
                    .accessibilityAddTraits(preset == checked ? .isSelected : [])
                }
            }
            .disabled(saving)
            menuRow("Add custom color", systemImage: "plus", id: "labelColor.addCustom", action: onAddCustom)
                .disabled(saving)
            menuRow("Remove color", systemImage: "circle.slash", id: "labelColor.remove") {
                store.setGmailLabelColor(label, to: nil)
                onPick()
            }
            .disabled(saving || !label.hasGmailColor)
            if saving {
                Text("Saving to Gmail…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        // Fill the 244 pt, left-aligned.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(width: 244)
    }

    /// A row that spans the sheet, as in a menu: the whole row is the button.
    private func menuRow(_ title: String, systemImage: String, id: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// One preset: a circle in the background color with a lowercase "a" in
/// the text color (a check mark instead on the current one), so the text's
/// lightness shows. A hairline keeps light fills visible on a light sheet.
private struct LabelColorPresetSwatch: View {
    let color: GmailLabelColor
    let checked: Bool
    let size: CGFloat

    var body: some View {
        let ink = LabelRGB(hexString: color.text).map(Color.init) ?? .primary
        Circle()
            .fill(LabelRGB(hexString: color.background).map(Color.init) ?? .clear)
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
            .overlay {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else {
                    Text(verbatim: "a").font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}

/// Gmail's "Add custom color" dialog: a preview chip, then the background
/// and the text grids side by side (the API palette's 64-value grid each:
/// a grey row, a saturated row, six rows of tints). Apply writes the pair
/// through the usual path (the family follows, DEC-071); Cancel changes
/// nothing.
struct LabelCustomColorDialog: View {
    @Environment(MailStore.self) private var store
    let label: LabelRow
    let onClose: () -> Void
    @State private var choice: GmailCustomLabelColor

    private static let cell: CGFloat = 20
    private static let spacing: CGFloat = 4
    private static let gridWidth = CGFloat(GmailLabelPalette.columns) * cell
        + CGFloat(GmailLabelPalette.columns - 1) * spacing

    init(label: LabelRow, onClose: @escaping () -> Void) {
        self.label = label
        self.onClose = onClose
        _choice = State(initialValue: GmailCustomLabelColor(current: label.drawnGmailColors))
    }

    var body: some View {
        let saving = store.gmailLabelColorSaving.contains(label.id)
        VStack(alignment: .leading, spacing: 14) {
            Text("Add custom color").font(.headline)
            HStack(spacing: 10) {
                LabelPill(name: LabelText.safe(label.name), colors: choice.color.colors,
                          fontSize: 12, maxWidth: 160)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("labelColor.custom.preview")
                Text("Preview label color - pick colors below.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize()
            }
            HStack(alignment: .top, spacing: 20) {
                grid("Background color", part: "background", selected: choice.color.background) {
                    choice.pick(background: $0)
                }
                grid("Text color", part: "text", selected: choice.color.text) {
                    choice.pick(text: $0)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(applied: false) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("labelColor.custom.cancel")
                Button("Apply") { finish(applied: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
                    .accessibilityIdentifier("labelColor.custom.apply")
            }
        }
        .padding(20)
        // As large as its content: nothing is truncated.
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("labelColor.custom")
    }

    private func finish(applied: Bool) {
        if let color = choice.result(applied: applied) {
            store.setGmailLabelColor(label, to: color)
        }
        onClose()
    }

    private func grid(_ title: String, part: String, selected: String,
                      pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.system(size: 12, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.spacing),
                                     count: GmailLabelPalette.columns),
                      spacing: Self.spacing) {
                ForEach(GmailLabelPalette.swatches, id: \.self) { swatch in
                    let on = selected == swatch.background
                    Button { pick(swatch.background) } label: {
                        LabelDot(colors: swatch.colors, size: Self.cell)
                            .overlay {
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(LabelRGB(hexString: swatch.text).map(Color.init) ?? .primary)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.background)
                    .accessibilityLabel("\(title) \(swatch.background)")
                    .accessibilityIdentifier("labelColor.custom.\(part).\(swatch.background)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .frame(width: Self.gridWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("labelColor.custom.\(part)")
    }
}
