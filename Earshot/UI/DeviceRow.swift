import SwiftUI

/// A tappable card for one audio device: symbol, name, subtitle and, when
/// selected, a checkmark with an accent fill and border.
struct DeviceRow: View {
    let name: String
    let subtitle: Text
    let symbol: String
    let isSelected: Bool

    /// Whether to show the orange "another app is using it" dot.
    var showsInUseDot = false

    /// Whether the card expands a list: `nil` shows no chevron, otherwise a
    /// chevron pointing up (`true`, expanded) or down.
    var isExpanded: Bool?

    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .lineLimit(1)
                    subtitle
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if showsInUseDot {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                if let isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(hovering ? 0.08 : 0.04)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The device cards of one section, collapsed to the selected device.
///
/// Only the selected card is shown; when there are other devices it carries a
/// chevron, and tapping it reveals the rest. Picking another device collapses
/// the list again. Without a selection every device is shown.
struct DeviceList: View {
    let devices: [AudioDevice]
    let selectedUID: String?
    let direction: AudioDirection

    /// The subtitle of a card, given its device and whether it is selected.
    let subtitle: (AudioDevice, Bool) -> Text

    /// Whether a card shows the orange in-use dot.
    var showsInUseDot: (AudioDevice, Bool) -> Bool = { _, _ in false }

    let select: (String) -> Void

    @State private var isExpanded = false

    var body: some View {
        let selected = devices.first { $0.uid == selectedUID }
        let others = devices.filter { $0.uid != selected?.uid }

        VStack(spacing: 6) {
            if let selected {
                card(selected, isSelected: true, isExpanded: others.isEmpty ? nil : isExpanded) {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
            }
            if selected == nil || isExpanded {
                ForEach(others) { device in
                    card(device, isSelected: false, isExpanded: nil) {
                        withAnimation(.snappy) {
                            isExpanded = false
                            select(device.uid)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func card(
        _ device: AudioDevice,
        isSelected: Bool,
        isExpanded: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        DeviceRow(
            name: device.name,
            subtitle: subtitle(device, isSelected),
            symbol: device.symbolName(for: direction),
            isSelected: isSelected,
            showsInUseDot: showsInUseDot(device, isSelected),
            isExpanded: isExpanded,
            action: action
        )
        .help(isExpanded == nil ? Text(device.name) : Text(isExpanded == true ? "Hide other devices" : "Show other devices"))
    }
}
