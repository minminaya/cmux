import Bonsplit
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


/// Geometry for two views of the same workspace split tree.
struct SpotlightPresets: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case grid
        case focus
    }

    struct Frame: Codable, Sendable {
        let width: Double
        let height: Double
        let horizontalPosition: Double
        let verticalPosition: Double

        init?(_ frame: CGRect, in size: CGSize) {
            guard size.width > 1, size.height > 1, !frame.isEmpty else { return nil }
            width = min(frame.width / size.width, 1)
            height = min(frame.height / size.height, 1)
            // Use the available travel so edge-snapped panes stay snapped after resizing.
            horizontalPosition = size.width > frame.width
                ? (frame.minX / (size.width - frame.width)).clamped(to: 0...1) : 0
            verticalPosition = size.height > frame.height
                ? (frame.minY / (size.height - frame.height)).clamped(to: 0...1) : 0
        }

        func frame(in size: CGSize) -> CGRect {
            let w = size.width * width
            let h = size.height * height
            return CGRect(x: (size.width - w) * horizontalPosition,
                          y: (size.height - h) * verticalPosition, width: w, height: h)
        }
    }

    private struct Dividers: Codable, Sendable {
        let shape: [String]
        let positions: [Double]
    }

    var active: Kind?
    var frames: [Kind: Frame] = [:]
    private var dividers: [Kind: Dividers] = [:]

    init() {}

    mutating func saveDividers(from tree: ExternalTreeNode, in preset: Kind) {
        let geometry = Self.dividerGeometry(tree)
        dividers[preset] = Dividers(shape: geometry.shape, positions: geometry.splits.map(\.dividerPosition))
    }

    func dividers(for preset: Kind, matching tree: ExternalTreeNode) -> [(id: UUID, value: CGFloat)] {
        let geometry = Self.dividerGeometry(tree)
        guard let saved = dividers[preset], saved.shape == geometry.shape else { return [] }
        return zip(geometry.splits, saved.positions).compactMap { split, position in
            guard let id = UUID(uuidString: split.id), position.isFinite else { return nil }
            return (id, CGFloat(position))
        }
    }

    private static func dividerGeometry(_ tree: ExternalTreeNode) -> (shape: [String], splits: [ExternalSplitNode]) {
        var shape: [String] = []
        var splits: [ExternalSplitNode] = []
        func visit(_ node: ExternalTreeNode) {
            switch node {
            case .pane:
                shape.append("pane")
            case .split(let split):
                shape.append(split.orientation)
                splits.append(split)
                visit(split.first)
                visit(split.second)
            }
        }
        visit(tree)
        return (shape, splits)
    }
}
