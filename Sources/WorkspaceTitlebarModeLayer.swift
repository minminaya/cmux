import CmuxSettingsUI
import SwiftUI

struct WorkspaceTitlebarModeLayer<Titlebar: View>: View {
    let titlebar: () -> Titlebar

    @AppStorage(WorkspacePresentationModeSettings.modeKey)
    private var workspacePresentationMode = WorkspacePresentationModeSettings.defaultMode.rawValue

    private var isMinimalMode: Bool {
        WorkspacePresentationModeSettings.mode(for: workspacePresentationMode) == .minimal
    }

    var body: some View {
        if !isMinimalMode {
            titlebar()
        }
    }
}

/// Window-titlebar control for the same preference shown in App settings.
struct PaneSpotlightToolbarButton: View {
    @LiveSetting(\.canvas.spotlightFocusOnly) private var focusOnly

    var body: some View {
        let label = String(localized: "toolbar.spotlight.autoEnlarge", defaultValue: "Automatically Enlarge Focused Pane")
        Toggle(label, isOn: Binding(get: { !focusOnly }, set: { focusOnly = !$0 }))
        .toggleStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("titlebarControl.autoEnlargePane")
        .titlebarInteractiveControl()
    }
}
