import Foundation

/// Settings under the dotted-id prefix `canvas.*`.
///
/// Controls the freeform canvas workspace layout. ``paneGap`` is the one
/// canonical spacing every canvas operation respects (snapping targets,
/// tidy/distribute commands, new-pane placement); ``snappingEnabled``
/// turns edge/gap snapping during drags and resizes on or off (Command
/// always suspends snapping for one gesture either way).
public struct CanvasCatalogSection: SettingCatalogSection {
    /// Gap between panes, in canvas points, used by snapping and every
    /// alignment/placement command.
    public let paneGap = DefaultsKey<Int>(
        id: "canvas.paneGap",
        defaultValue: 16,
        userDefaultsKey: "canvasPaneGap"
    )

    /// Whether drags and resizes snap to neighbor edges and the canonical
    /// gap. Holding Command suspends snapping per-gesture regardless.
    public let snappingEnabled = DefaultsKey<Bool>(
        id: "canvas.snappingEnabled",
        defaultValue: true,
        userDefaultsKey: "canvasSnappingEnabled"
    )

    /// Whether focusing a split pane keeps its original size.
    public let spotlightFocusOnly = DefaultsKey<Bool>(
        id: "canvas.spotlightFocusOnly",
        defaultValue: true,
        userDefaultsKey: "canvasSpotlightFocusOnly"
    )

    /// Supported floating pane dimensions, as percentages of the workspace.
    public static let spotlightSizeRange = 20...95

    /// Supported floating pane positions across the available space.
    public static let spotlightPositionRange = 0...100

    /// Width of the floating pane as a percentage of workspace width.
    public let spotlightWidth = DefaultsKey<Int>(
        id: "canvas.spotlightWidth",
        defaultValue: 65,
        userDefaultsKey: "canvasSpotlightWidth"
    )

    /// Height of the floating pane as a percentage of workspace height.
    public let spotlightHeight = DefaultsKey<Int>(
        id: "canvas.spotlightHeight",
        defaultValue: 65,
        userDefaultsKey: "canvasSpotlightHeight"
    )

    /// Horizontal position of the floating pane. 0% is left, 50% is centered, and 100% is right.
    public let spotlightHorizontalPosition = DefaultsKey<Int>(
        id: "canvas.spotlightHorizontalPosition",
        defaultValue: 50,
        userDefaultsKey: "canvasSpotlightHorizontalPosition"
    )

    /// Vertical position of the floating pane. 0% is top, 50% is centered, and 100% is bottom.
    public let spotlightVerticalPosition = DefaultsKey<Int>(
        id: "canvas.spotlightVerticalPosition",
        defaultValue: 50,
        userDefaultsKey: "canvasSpotlightVerticalPosition"
    )

    /// Creates the canvas settings section with its default keys.
    public init() {}
}
