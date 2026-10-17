import AppKit
import SwiftUI

/// The menu bar panel.
///
/// Placeholder layout with the three sections from the design document, top to
/// bottom: master volume + output device, apps currently playing, and
/// microphone. All content is static text for now — the controls are wired up in
/// later steps.
struct PanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Earshot")
                .font(.headline)

            PanelSection(title: "Output") {
                Text("Master volume and output device controls go here.")
            }

            PanelSection(title: "Apps") {
                Text("Apps currently playing appear here.")
            }

            PanelSection(title: "Microphone") {
                Text("Input device, volume and level meter go here.")
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// A titled group used by the panel sections.
private struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
        }
    }
}
