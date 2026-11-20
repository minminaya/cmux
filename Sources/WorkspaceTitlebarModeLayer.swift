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


struct PaneSpotlightPresetsMenu: View {
    let workspace: Workspace

    var body: some View {
        let label = String(localized: "toolbar.spotlight.presets", defaultValue: "Pane Layout Presets")
        Menu {
            Button(String(localized: "toolbar.spotlight.gridPreset", defaultValue: "Split Grid")) {
                workspace.switchSpotlightPreset(to: .grid)
            }
            Button(String(localized: "toolbar.spotlight.focusPreset", defaultValue: "Focused Pane")) {
                workspace.switchSpotlightPreset(to: .focus)
            }
        } label: {
            Image(systemName: "rectangle.split.2x2")
                .accessibilityLabel(label)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(label)
        .accessibilityIdentifier("titlebarControl.paneLayoutPresets")
        .titlebarInteractiveControl()
    }
}
