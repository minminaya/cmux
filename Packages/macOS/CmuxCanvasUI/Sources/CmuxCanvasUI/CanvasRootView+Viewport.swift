public import AppKit
import QuartzCore
import CmuxCanvas


extension CanvasRootView: CanvasViewportControlling {
    private static let discreteZoomAnimationKey = "cmux.canvas.discreteZoom"
    private static let discreteZoomAnimationDuration: TimeInterval = 0.2
    static let overviewAnimationDuration: TimeInterval = 0.3

    public func modelDidChangeExternally(animated: Bool) {
        reconcilePanes()
        applyZOrder()
        recomputeDocumentGeometry()
        if shouldAnimate(animated) {
            animatePaneFrames {
                for (paneID, paneView) in self.paneViews {
                    if let frame = self.model.layout.frame(of: paneID)?.cgRect {
                        paneView.animator().frame = self.documentRect(fromCanvas: frame)
                    }
                }
            } completion: { [weak self] in
                guard let self else { return }
                self.callbacks.onViewportGeometryChanged(self.window)
            }
        } else {
            applyAllPaneFrames()
        }
        updateLifecycle()
        updateMinimap()
        callbacks.onLayoutChanged()
        callbacks.onViewportGeometryChanged(window)
    }

    /// Schedules enlargement after the split-sized canvas and its viewport have been laid out.
    ///
    /// - Parameter frame: The enlarged pane's destination in canvas coordinates.
    public func prepareSpotlightExpansion(to frame: CGRect) {
        guard !didPrepareSpotlightExpansion else { return }
        didPrepareSpotlightExpansion = true
        spotlightExpansionFrame = frame
        needsLayout = true
    }

    /// Moves enlargement to another pane while retaining the floating frame.
    public func transferSpotlight(
        from previous: UUID, restoring original: CGRect, to next: UUID, inPane paneID: UUID, frame: CGRect
    ) -> Bool {
        guard dragSession == nil, spotlightExpansionFrame == nil, spotlightRestore == nil,
              animatingSpotlightPaneID == nil, model.paneID(containing: next)?.rawValue == paneID else { return false }
        model.setFrame(original, for: previous)
        model.bringToFront(next)
        spotlightPaneID = paneID
        modelDidChangeExternally(animated: false)
        moveSpotlightPane(to: frame) { [weak self] in self?.startSpotlightRestore() }
        return true
    }

    /// Animates the enlarged pane back to its split position.
    ///
    /// - Parameters:
    ///   - frame: The original pane frame in canvas coordinates.
    ///   - completion: Called after the pane reaches its split position.
    public func animateSpotlightRestore(to frame: CGRect, completion: @escaping @MainActor () -> Void) {
        guard spotlightRestore == nil else { return }
        if dragSession != nil {
            dragSession = nil
            guidesView.setGuides([])
            releaseMinimapAfterInteraction()
        }
        spotlightExpansionFrame = nil
        spotlightRestore = (frame, completion)
        if animatingSpotlightPaneID == nil {
            startSpotlightRestore()
        }
    }

    private func startSpotlightRestore() {
        guard let restore = spotlightRestore else { return }
        moveSpotlightPane(to: restore.frame) { [weak self] in
            guard let self else { return }
            self.spotlightRestore = nil
            restore.completion()
        }
    }

    func startPreparedSpotlightExpansion() {
        guard let frame = spotlightExpansionFrame else { return }
        spotlightExpansionFrame = nil
        moveSpotlightPane(to: frame) { [weak self] in
            self?.startSpotlightRestore()
        }
    }

    private func moveSpotlightPane(to frame: CGRect, completion: @escaping @MainActor () -> Void) {
        guard let spotlightPaneID else {
            completion()
            return
        }
        let paneID = CanvasPaneID(rawValue: spotlightPaneID)
        guard let paneView = paneViews[paneID],
              let panelID = model.layout.selectedPanelId(in: paneID)?.rawValue,
              model.frame(of: panelID) != frame else {
            completion()
            return
        }

        let startFrame = canvasRect(fromDocument: paneView.frame)
        model.setFrame(frame, for: panelID)
        recomputeDocumentGeometry()
        if shouldAnimate(isWorkspaceVisible && window != nil) {
            animatingSpotlightPaneID = paneID
            paneView.frame = documentRect(fromCanvas: startFrame)
            animatePaneFrames {
                paneView.animator().frame = self.documentRect(fromCanvas: frame)
            } completion: { [weak self] in
                guard let self, self.animatingSpotlightPaneID == paneID else { return }
                self.animatingSpotlightPaneID = nil
                self.applyAllPaneFrames()
                self.updateLifecycle()
                self.updateMinimap()
                self.callbacks.onViewportGeometryChanged(self.window)
                completion()
            }
        } else {
            applyAllPaneFrames()
            updateLifecycle()
            updateMinimap()
            callbacks.onViewportGeometryChanged(window)
            completion()
        }
    }

    private func animatePaneFrames(
        _ updates: () -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        onMotionAnimationStarted?(Self.paneFrameAnimationDuration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.paneFrameAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            updates()
        }, completionHandler: {
            Task { @MainActor in completion() }
        })
    }

    public func revealPane(_ panelId: UUID, animated: Bool) {
        cancelDiscreteZoomAnimation()
        guard let frame = model.frame(of: panelId) else { return }
        let docFrame = documentRect(fromCanvas: frame)
        let visible = scrollView.contentView.documentVisibleRect
        let origin = CanvasViewportMath().originToReveal(
            CanvasRect(docFrame),
            viewportOrigin: CanvasPoint(visible.origin),
            viewportSize: CanvasSize(visible.size),
            margin: Self.revealMargin
        )
        guard origin.cgPoint != visible.origin else { return }
        setClipOrigin(origin.cgPoint, animated: animated)
    }

    public func zoom(by factor: CGFloat) {
        zoom(by: factor, animated: true)
    }

    public func zoom(by factor: CGFloat, animated: Bool) {
        // An explicit zoom invalidates the overview round-trip restore.
        overviewRestore = nil
        let target = min(
            max(scrollView.magnification * factor, scrollView.minMagnification),
            scrollView.maxMagnification
        )
        setMagnification(target, animated: animated)
    }

    public func resetZoom() {
        resetZoom(animated: true)
    }

    public func resetZoom(animated: Bool) {
        overviewRestore = nil
        setMagnification(1.0, animated: animated)
    }

    public var currentMagnification: CGFloat {
        scrollView.magnification
    }

    public var currentCenterInCanvas: CGPoint {
        let visible = scrollView.contentView.documentVisibleRect
        let canvas = canvasRect(fromDocument: visible)
        return CGPoint(x: canvas.midX, y: canvas.midY)
    }

    public func setViewport(center: CGPoint, magnification: CGFloat?) {
        setViewport(center: center, magnification: magnification, notifySettled: true)
    }

    func setViewport(center: CGPoint, magnification: CGFloat?, notifySettled: Bool) {
        // An explicit viewport set invalidates the overview round-trip restore.
        overviewRestore = nil
        cancelDiscreteZoomAnimation()
        applyViewport(center: center, magnification: magnification, notifySettled: notifySettled)
    }

    private func applyViewport(
        center: CGPoint,
        magnification: CGFloat?,
        notifySettled: Bool,
        notifyGeometry: Bool = true
    ) {
        let targetMagnification: CGFloat
        if let magnification {
            targetMagnification = min(
                max(magnification, scrollView.minMagnification),
                scrollView.maxMagnification
            )
        } else {
            targetMagnification = scrollView.magnification
        }
        // Convert the desired canvas center to document coordinates, then place
        // the clip origin so that point lands at the viewport center.
        let docCenter = CGPoint(
            x: center.x - documentOriginInCanvas.x,
            y: center.y - documentOriginInCanvas.y
        )
        let viewportSize = scrollView.contentSize
        let clipSize = CGSize(
            width: viewportSize.width / targetMagnification,
            height: viewportSize.height / targetMagnification
        )
        let targetOrigin = CGPoint(
            x: docCenter.x - clipSize.width / 2,
            y: docCenter.y - clipSize.height / 2
        )
        scrollView.magnification = targetMagnification
        scrollView.contentView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateMinimap(reveal: true)
        if notifyGeometry {
            callbacks.onViewportGeometryChanged(window)
        }
        if notifySettled {
            callbacks.onViewportSettled(window)
        }
    }

    /// Zooms by `factor` while keeping the document point under
    /// `windowLocation` fixed (cursor-anchored), for pointer-driven zoom
    /// (option+scroll). Unanimated so it tracks the wheel; the caller settles
    /// portals on a debounce.
    func zoom(by factor: CGFloat, towardWindowLocation windowLocation: CGPoint) {
        overviewRestore = nil
        cancelDiscreteZoomAnimation()
        let target = min(
            max(scrollView.magnification * factor, scrollView.minMagnification),
            scrollView.maxMagnification
        )
        guard target != scrollView.magnification else { return }
        let anchor = scrollView.contentView.convert(windowLocation, from: nil)
        scrollView.setMagnification(target, centeredAt: anchor)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateMinimap(reveal: true)
    }

    /// Applies `magnification`, keeping the current viewport center fixed.
    private func setMagnification(_ magnification: CGFloat, animated: Bool) {
        cancelDiscreteZoomAnimation()
        guard magnification != scrollView.magnification else { return }
        let center = currentCenterInCanvas
        if !shouldAnimate(animated) {
            applyViewport(center: center, magnification: magnification, notifySettled: true)
            return
        }
        animateDiscreteZoom(to: magnification, centeredAtCanvas: center)
    }

    private func animateDiscreteZoom(to magnification: CGFloat, centeredAtCanvas center: CGPoint) {
        guard let layer = documentView.layer else {
            applyViewport(center: center, magnification: magnification, notifySettled: true)
            return
        }
        let sourceMagnification = scrollView.magnification
        guard sourceMagnification > 0 else {
            applyViewport(center: center, magnification: magnification, notifySettled: true)
            return
        }

        let sourceVisibleCanvas = canvasRect(fromDocument: scrollView.contentView.documentVisibleRect)
        applyViewport(center: center, magnification: magnification, notifySettled: false, notifyGeometry: false)
        recomputeDocumentGeometry()
        applyAllPaneFrames()

        let targetMagnification = scrollView.magnification
        guard targetMagnification > 0 else {
            callbacks.onViewportSettled(window)
            return
        }
        let sourceVisibleInTargetDocument = documentRect(fromCanvas: sourceVisibleCanvas)
        updateLifecycle(visibleRect: sourceVisibleInTargetDocument.union(scrollView.contentView.documentVisibleRect))
        updateMinimap(reveal: true)
        callbacks.onViewportGeometryChanged(window)

        let targetAnchor = CGPoint(
            x: center.x - documentOriginInCanvas.x,
            y: center.y - documentOriginInCanvas.y
        )
        let compensationScale = sourceMagnification / targetMagnification
        var compensation = CATransform3DIdentity
        compensation = CATransform3DTranslate(compensation, targetAnchor.x, targetAnchor.y, 0)
        compensation = CATransform3DScale(compensation, compensationScale, compensationScale, 1)
        compensation = CATransform3DTranslate(compensation, -targetAnchor.x, -targetAnchor.y, 0)

        discreteZoomAnimationGeneration &+= 1
        let generation = discreteZoomAnimationGeneration
        isDiscreteZoomAnimationActive = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: Self.discreteZoomAnimationKey)
        layer.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()

        onMotionAnimationStarted?(Self.discreteZoomAnimationDuration)
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: compensation)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = Self.discreteZoomAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDiscreteZoomAnimation(generation: generation)
            }
        }
        layer.add(animation, forKey: Self.discreteZoomAnimationKey)
        CATransaction.commit()
    }

    func cancelDiscreteZoomAnimation() {
        guard isDiscreteZoomAnimationActive || documentView.layer?.animation(forKey: Self.discreteZoomAnimationKey) != nil else {
            return
        }
        isDiscreteZoomAnimationActive = false
        discreteZoomAnimationGeneration &+= 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        documentView.layer?.removeAnimation(forKey: Self.discreteZoomAnimationKey)
        documentView.layer?.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()
    }

    func finishDiscreteZoomAnimation(generation: UInt64? = nil) {
        if let generation, generation != discreteZoomAnimationGeneration { return }
        guard isDiscreteZoomAnimationActive else { return }
        isDiscreteZoomAnimationActive = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        documentView.layer?.removeAnimation(forKey: Self.discreteZoomAnimationKey)
        documentView.layer?.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()
        callbacks.onViewportSettled(window)
    }

    public func toggleOverview() {
        toggleOverview(animated: true)
    }

    public func toggleOverview(animated: Bool) {
        cancelDiscreteZoomAnimation()
        if let restore = overviewRestore {
            overviewRestore = nil
            applyOverviewViewport(magnification: restore.magnification, origin: restore.origin, animated: animated)
            return
        }
        guard let content = model.contentBounds else { return }
        overviewRestore = (scrollView.magnification, scrollView.contentView.bounds.origin)
        let viewportSize = scrollView.contentSize
        let fit = CGFloat(CanvasViewportMath().magnificationToFit(
            CanvasRect(content),
            in: CanvasSize(viewportSize),
            padding: Self.overviewPadding,
            range: Double(scrollView.minMagnification)...Double(scrollView.maxMagnification)
        ))
        // Anchor explicitly: after magnification `fit`, the clip's bounds are
        // viewport/fit in document coordinates; centering the content means
        // origin = contentCenter - clipSize/2. setMagnification(centeredAt:)
        // alone lands off-center when the magnification change is large.
        let docCenter = documentRect(fromCanvas: content).canvasCenter
        let clipSize = CGSize(width: viewportSize.width / fit, height: viewportSize.height / fit)
        let targetOrigin = CGPoint(
            x: docCenter.x - clipSize.width / 2,
            y: docCenter.y - clipSize.height / 2
        )
        applyOverviewViewport(magnification: fit, origin: targetOrigin, animated: animated)
    }

    /// Moves to an overview (or back to the saved viewport), animated unless
    /// the caller or Reduce Motion says otherwise.
    private func applyOverviewViewport(magnification: CGFloat, origin: CGPoint, animated: Bool) {
        if shouldAnimate(animated) {
            onMotionAnimationStarted?(Self.overviewAnimationDuration)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.overviewAnimationDuration
                context.allowsImplicitAnimation = true
                scrollView.animator().magnification = magnification
                scrollView.contentView.animator().setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            scrollView.magnification = magnification
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        updateMinimap(reveal: true)
    }
}
