import Foundation
import CmuxCanvas
import CmuxSettings

/// User-configurable canvas layout settings.
///
/// Values persist through `UserDefaults` (mirrored into `~/.config/cmux/cmux.json`
/// by the settings catalog) and feed ``CanvasMetrics`` so every canvas
/// operation shares one canonical gap.
enum CanvasLayoutSettings {
    static let paneGapKey = "canvasPaneGap"
    static let snappingEnabledKey = "canvasSnappingEnabled"

    static let defaultPaneGap = CanvasMetrics.defaultGap
    static let defaultSnappingEnabled = true

    static let paneGapRange: ClosedRange<Double> = 0...64

    static func paneGap(defaults: UserDefaults = .standard) -> Double {
        // The settings catalog writes this key as Int (canvas.paneGap);
        // accept any numeric representation.
        guard let value = (defaults.object(forKey: paneGapKey) as? NSNumber)?.doubleValue else {
            return defaultPaneGap
        }
        return value.clamped(to: paneGapRange)
    }

    static func snappingEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: snappingEnabledKey) as? Bool ?? defaultSnappingEnabled
    }

    /// Computes the floating pane frame using current settings at the time it opens.
    static func spotlightFrame(in size: CGSize, defaults: UserDefaults = .standard) -> CGRect {
        let catalog = CanvasCatalogSection()
        func fraction(_ key: DefaultsKey<Int>, in range: ClosedRange<Int>) -> CGFloat {
            CGFloat(Double(key.value(in: defaults)).clamped(to: Double(range.lowerBound)...Double(range.upperBound))) / 100
        }
        let sizeRange = CanvasCatalogSection.spotlightSizeRange
        let positionRange = CanvasCatalogSection.spotlightPositionRange
        let width = size.width * fraction(catalog.spotlightWidth, in: sizeRange)
        let height = size.height * fraction(catalog.spotlightHeight, in: sizeRange)
        return CGRect(
            x: (size.width - width) * fraction(catalog.spotlightHorizontalPosition, in: positionRange),
            y: (size.height - height) * fraction(catalog.spotlightVerticalPosition, in: positionRange),
            width: width,
            height: height
        )
    }

    /// The metrics every canvas operation should use right now.
    static func currentMetrics(defaults: UserDefaults = .standard) -> CanvasMetrics {
        CanvasMetrics(
            gap: paneGap(defaults: defaults),
            snapThreshold: snappingEnabled(defaults: defaults) ? CanvasMetrics.defaultSnapThreshold : 0,
            minPaneSize: CanvasMetrics.defaultMinPaneSize
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
