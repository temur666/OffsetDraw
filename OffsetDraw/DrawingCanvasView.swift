import UIKit

final class DrawingCanvasView: UIView {
    var brush = BrushConfig.initial {
        didSet {
            setNeedsDisplay()
        }
    }

    var control = DrawingControlConfig.initial {
        didSet {
            control.movementScale = min(max(control.movementScale, 0.05), 1)
            control.smoothingAmount = min(max(control.smoothingAmount, 0), 1)
        }
    }

    var boardColor: UIColor = .white {
        didSet {
            backgroundColor = boardColor
            setNeedsDisplay()
        }
    }

    var canvasConfig = CanvasConfigDTO.initial {
        didSet {
            setNeedsDisplay()
        }
    }

    var showsCalibrationOverlay = false {
        didSet {
            setNeedsDisplay()
        }
    }

    var layers: [DrawingLayer] = [DrawingLayer(id: UUID(), title: "Layer 1", isVisible: true, opacity: 1)] {
        didSet {
            if !layers.contains(where: { $0.id == activeLayerID }), let firstLayer = layers.first {
                activeLayerID = firstLayer.id
            }
            setNeedsDisplay()
        }
    }

    var activeLayerID: UUID = UUID() {
        didSet {
            setNeedsDisplay()
        }
    }

    private(set) var strokes: [Stroke] = []
    private var activePoints: [StrokePoint] = []
    private var smoothedDrawingPoint: CGPoint?
    private var cursorPosition: CGPoint?
    private var targetPosition: CGPoint?
    private var latestTouchPosition: CGPoint?
    private var touchAnchorPosition: CGPoint?
    private var tipAnchorPosition: CGPoint?
    private var longPressStartTime: TimeInterval?
    private var longPressTimer: Timer?
    private var drawingMode = DrawingMode.idle
    private let longPressDuration: TimeInterval = 0.18
    private let longPressMovementTolerance: CGFloat = 8
    var onDocumentChanged: (() -> Void)?

    private enum DrawingMode {
        case idle
        case waitingLongPress
        case hoveringTip
        case drawing
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func undoLastStroke() {
        guard !strokes.isEmpty else {
            return
        }

        strokes.removeLast()
        setNeedsDisplay()
        onDocumentChanged?()
    }

    func clearDrawing() {
        strokes.removeAll()
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
        onDocumentChanged?()
    }

    var isEraserEnabled: Bool {
        brush.blendMode == .clear
    }

    var activeLayerTitle: String {
        layers.first(where: { $0.id == activeLayerID })?.title ?? "Layer"
    }

    var isActiveLayerVisible: Bool {
        layers.first(where: { $0.id == activeLayerID })?.isVisible ?? true
    }

    func load(
        strokes: [Stroke],
        brush: BrushConfig,
        control: DrawingControlConfig,
        boardColor: UIColor,
        canvas: CanvasConfigDTO,
        layers: [DrawingLayer],
        activeLayerID: UUID
    ) {
        self.strokes = strokes
        self.brush = brush
        self.control = control
        self.boardColor = boardColor
        self.canvasConfig = canvas
        self.layers = layers.isEmpty ? [DrawingLayer(id: activeLayerID, title: "Layer 1", isVisible: true, opacity: 1)] : layers
        self.activeLayerID = self.layers.contains(where: { $0.id == activeLayerID }) ? activeLayerID : self.layers[0].id
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: false)
        setNeedsDisplay()
    }

    func renderImage(includeCursor: Bool = false, thumbnailSize: CGSize? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = !canvasConfig.isTransparentExportEnabled
        let sourceBounds = CGRect(
            x: 0,
            y: 0,
            width: max(canvasConfig.width, 1),
            height: max(canvasConfig.height, 1)
        )
        let outputBounds = CGRect(origin: .zero, size: thumbnailSize ?? sourceBounds.size)

        return UIGraphicsImageRenderer(bounds: outputBounds, format: format).image { context in
            let scale = min(
                outputBounds.width / max(sourceBounds.width, 1),
                outputBounds.height / max(sourceBounds.height, 1)
            )
            let renderedSize = CGSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
            let xOffset = (outputBounds.width - renderedSize.width) / 2
            let yOffset = (outputBounds.height - renderedSize.height) / 2

            drawRenderBackground(in: outputBounds, context: context.cgContext)
            context.cgContext.translateBy(x: xOffset, y: yOffset)
            context.cgContext.scaleBy(x: scale, y: scale)
            drawStoredStrokes(strokes, in: context.cgContext)
            if includeCursor, let cursorPosition {
                drawCursor(at: renderedPoint(from: cursorPosition, scale: scale, offset: CGPoint(x: xOffset, y: yOffset)), in: context.cgContext)
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        ensureCursorPosition()
        drawCanvasShadow(in: context)
        drawBoardBackground(in: canvasRect, context: context, respectsTransparency: false)

        context.saveGState()
        context.translateBy(x: canvasRect.minX, y: canvasRect.minY)
        context.scaleBy(x: canvasScale, y: canvasScale)
        drawStrokes(activeStroke: activeStroke, in: context)
        context.restoreGState()

        if control.showsStabilizerGuide, let cursorPosition, let targetPosition {
            drawStabilizerLine(from: viewPoint(from: cursorPosition), to: viewPoint(from: targetPosition), in: context)
        }

        if let cursorPosition {
            drawCursor(at: viewPoint(from: cursorPosition), in: context)
        }

        if showsCalibrationOverlay {
            drawCalibrationOverlay(in: context)
        }
    }

    private var canvasRect: CGRect {
        let configuredSize = CGSize(width: max(canvasConfig.width, 1), height: max(canvasConfig.height, 1))
        let scale = min(bounds.width / configuredSize.width, bounds.height / configuredSize.height)
        let renderedSize = CGSize(width: configuredSize.width * scale, height: configuredSize.height * scale)
        return CGRect(
            x: (bounds.width - renderedSize.width) / 2,
            y: (bounds.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    private var canvasScale: CGFloat {
        let configuredSize = CGSize(width: max(canvasConfig.width, 1), height: max(canvasConfig.height, 1))
        return min(bounds.width / configuredSize.width, bounds.height / configuredSize.height)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        ensureActiveLayerVisible()
        ensureCursorPosition()
        resetInteractionState(keepCursor: true)
        guard let cursorPosition else {
            return
        }

        guard let touchPoint = canvasPoint(from: touch.location(in: self)) else {
            return
        }
        latestTouchPosition = touchPoint
        touchAnchorPosition = touchPoint
        tipAnchorPosition = cursorPosition

        activePoints.removeAll()
        targetPosition = cursorPosition
        configureTouchStart(for: cursorPosition)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            guard let samplePoint = canvasPoint(from: sample.location(in: self)) else {
                continue
            }
            latestTouchPosition = samplePoint

            switch drawingMode {
            case .waitingLongPress:
                guard let point = drawingPoint(from: sample, movementScale: 1) else {
                    continue
                }

                moveCursor(to: point)
                if hasMovedBeyondLongPressTolerance(to: point) {
                    cancelLongPress(keepCursor: true, keepTouchAnchor: true)
                    drawingMode = .hoveringTip
                }
            case .hoveringTip:
                guard let point = drawingPoint(from: sample, movementScale: 1) else {
                    continue
                }

                moveCursor(to: point)
            case .drawing:
                guard let point = drawingPoint(from: sample, movementScale: control.movementScale) else {
                    continue
                }

                appendPoint(point)
            case .idle:
                guard let point = drawingPoint(from: sample, movementScale: 1) else {
                    continue
                }

                moveCursor(to: point)
            }
        }

        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishActiveStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = boardColor
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    private func drawingPoint(from touch: UITouch?, movementScale: CGFloat) -> CGPoint? {
        guard let touch else {
            return nil
        }

        guard let touchPoint = canvasPoint(from: touch.location(in: self)) else {
            return nil
        }
        guard let touchAnchorPosition, let tipAnchorPosition else {
            return touchPoint
        }

        return CGPoint(
            x: tipAnchorPosition.x + (touchPoint.x - touchAnchorPosition.x) * movementScale,
            y: tipAnchorPosition.y + (touchPoint.y - touchAnchorPosition.y) * movementScale
        )
    }

    func addLayer() {
        let layer = DrawingLayer(id: UUID(), title: "Layer \(layers.count + 1)", isVisible: true, opacity: 1)
        layers.append(layer)
        activeLayerID = layer.id
        onDocumentChanged?()
    }

    func ensureActiveLayerVisible() {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }), !layers[index].isVisible else {
            return
        }

        layers[index].isVisible = true
        onDocumentChanged?()
    }

    func toggleActiveLayerVisibility() {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return
        }

        layers[index].isVisible.toggle()
        if !layers[index].isVisible, layers[index].id == activeLayerID {
            if let visibleLayer = layers.first(where: \.isVisible) {
                activeLayerID = visibleLayer.id
            } else {
                layers[index].isVisible = true
            }
        }
        onDocumentChanged?()
    }

    func renameActiveLayer(to title: String) {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        layers[index].title = trimmedTitle
        onDocumentChanged?()
    }

    func setActiveLayerOpacity(_ opacity: CGFloat) {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return
        }

        layers[index].opacity = min(max(opacity, 0), 1)
        onDocumentChanged?()
    }

    func moveActiveLayer(up: Bool) {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return
        }

        let targetIndex = up ? index + 1 : index - 1
        guard layers.indices.contains(targetIndex) else {
            return
        }

        layers.swapAt(index, targetIndex)
        onDocumentChanged?()
    }

    func deleteActiveLayer() {
        guard layers.count > 1, let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return
        }

        let removedLayerID = layers[index].id
        layers.remove(at: index)
        strokes.removeAll { $0.layerID == removedLayerID }
        activeLayerID = layers[min(index, layers.count - 1)].id
        onDocumentChanged?()
    }

    func mergeActiveLayerDown() {
        guard let index = layers.firstIndex(where: { $0.id == activeLayerID }), index > 0 else {
            return
        }

        let sourceLayerID = layers[index].id
        let targetLayerID = layers[index - 1].id
        strokes = strokes.map { stroke in
            if stroke.layerID == sourceLayerID {
                return Stroke(points: stroke.points, brush: stroke.brush, layerID: targetLayerID)
            }
            return stroke
        }
        layers.remove(at: index)
        activeLayerID = targetLayerID
        onDocumentChanged?()
    }

    func selectLayer(at index: Int) {
        guard layers.indices.contains(index) else {
            return
        }

        activeLayerID = layers[index].id
        onDocumentChanged?()
    }

    private func canvasPoint(from viewPoint: CGPoint) -> CGPoint? {
        guard canvasRect.contains(viewPoint), canvasScale > 0 else {
            return nil
        }

        return CGPoint(
            x: (viewPoint.x - canvasRect.minX) / canvasScale,
            y: (viewPoint.y - canvasRect.minY) / canvasScale
        )
    }

    private func viewPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasRect.minX + canvasPoint.x * canvasScale,
            y: canvasRect.minY + canvasPoint.y * canvasScale
        )
    }

    private func renderedPoint(from canvasPoint: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(
            x: offset.x + canvasPoint.x * scale,
            y: offset.y + canvasPoint.y * scale
        )
    }

    private func stabilizedTipPosition(for targetPoint: CGPoint) -> CGPoint {
        let radius = max(brush.stabilizerRadius, 0)
        guard radius > 0, let cursorPosition else {
            return targetPoint
        }

        let xDistance = targetPoint.x - cursorPosition.x
        let yDistance = targetPoint.y - cursorPosition.y
        let distance = hypot(xDistance, yDistance)
        guard distance > radius else {
            return cursorPosition
        }

        let pullDistance = distance - radius
        let pullRatio = pullDistance / distance
        return CGPoint(
            x: cursorPosition.x + xDistance * pullRatio,
            y: cursorPosition.y + yDistance * pullRatio
        )
    }

    private func appendPoint(_ point: CGPoint) {
        let stabilizedPoint = stabilizedTipPosition(for: point)
        let smoothedPoint = smoothedPoint(for: stabilizedPoint)
        let previousTipPosition = cursorPosition ?? stabilizedPoint
        targetPosition = point
        guard previousTipPosition != smoothedPoint else {
            return
        }

        if activePoints.isEmpty {
            activePoints.append(StrokePoint(position: previousTipPosition, timestamp: CACurrentMediaTime()))
        }

        guard activePoints.last?.position != smoothedPoint else {
            cursorPosition = smoothedPoint
            return
        }

        guard shouldAppendPoint(smoothedPoint) else {
            cursorPosition = smoothedPoint
            return
        }

        activePoints.append(StrokePoint(position: smoothedPoint, timestamp: CACurrentMediaTime()))
        cursorPosition = smoothedPoint
    }

    private func beginDrawing(at point: CGPoint) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressStartTime = nil
        drawingMode = .drawing
        activePoints.removeAll()
        targetPosition = point
        cursorPosition = point
        smoothedDrawingPoint = point
        if let latestTouchPosition {
            touchAnchorPosition = latestTouchPosition
            tipAnchorPosition = point
        }
        activePoints.append(StrokePoint(position: point, timestamp: CACurrentMediaTime()))
        setNeedsDisplay()
    }

    private func moveCursor(to targetPoint: CGPoint) {
        targetPosition = targetPoint
        cursorPosition = targetPoint
    }

    private func finishActiveStroke() {
        if drawingMode == .drawing && !activePoints.isEmpty {
            strokes.append(Stroke(points: activePoints, brush: brush, layerID: activeLayerID))
            onDocumentChanged?()
        }

        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
    }

    private func ensureCursorPosition() {
        if cursorPosition == nil {
            cursorPosition = CGPoint(x: canvasConfig.width / 2, y: canvasConfig.height / 2 - 48)
        }
    }

    private func startLongPressTimer() {
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            guard drawingMode == .waitingLongPress else {
                timer.invalidate()
                return
            }

            if longPressProgress >= 1 {
                beginDrawing()
            }

            setNeedsDisplay()
        }
    }

    private func beginDrawing() {
        guard drawingMode == .waitingLongPress else {
            return
        }

        beginDrawing(at: cursorPosition ?? tipAnchorPosition ?? .zero)
    }

    private func cancelLongPress(keepCursor: Bool, keepTouchAnchor: Bool = false) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressStartTime = nil
        if !keepTouchAnchor {
            latestTouchPosition = nil
            touchAnchorPosition = nil
            tipAnchorPosition = nil
        }
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        if !keepCursor {
            cursorPosition = nil
            targetPosition = nil
        }
    }

    private func smoothedPoint(for point: CGPoint) -> CGPoint {
        guard let smoothedDrawingPoint else {
            self.smoothedDrawingPoint = point
            return point
        }

        let followFactor = 0.65 - control.smoothingAmount * 0.49
        let smoothedPoint = CGPoint(
            x: smoothedDrawingPoint.x + (point.x - smoothedDrawingPoint.x) * followFactor,
            y: smoothedDrawingPoint.y + (point.y - smoothedDrawingPoint.y) * followFactor
        )
        self.smoothedDrawingPoint = smoothedPoint
        return smoothedPoint
    }

    private func shouldAppendPoint(_ point: CGPoint) -> Bool {
        guard let lastPoint = activePoints.last?.position else {
            return true
        }

        let minimumDistance = 0.5 + control.smoothingAmount * 4.5
        let xDistance = point.x - lastPoint.x
        let yDistance = point.y - lastPoint.y
        return hypot(xDistance, yDistance) >= minimumDistance
    }

    private func resetInteractionState(keepCursor: Bool) {
        cancelLongPress(keepCursor: keepCursor)
        drawingMode = .idle
    }

    private func configureTouchStart(for point: CGPoint) {
        guard control.requiresLongPress else {
            beginDrawing(at: point)
            return
        }

        longPressStartTime = CACurrentMediaTime()
        drawingMode = .waitingLongPress
        startLongPressTimer()
    }

    private var longPressProgress: CGFloat {
        guard drawingMode == .waitingLongPress, let longPressStartTime else {
            return 0
        }

        let elapsed = CACurrentMediaTime() - longPressStartTime
        return min(max(CGFloat(elapsed / longPressDuration), 0), 1)
    }

    private func hasMovedBeyondLongPressTolerance(to point: CGPoint) -> Bool {
        guard let tipAnchorPosition else {
            return false
        }

        let xDistance = point.x - tipAnchorPosition.x
        let yDistance = point.y - tipAnchorPosition.y
        return hypot(xDistance, yDistance) > longPressMovementTolerance
    }

    private var activeStroke: Stroke? {
        guard !activePoints.isEmpty else {
            return nil
        }

        return Stroke(points: activePoints, brush: brush, layerID: activeLayerID)
    }

    private func drawStrokes(activeStroke: Stroke?, in context: CGContext) {
        let visibleLayers = layers.filter(\.isVisible)
        for layer in visibleLayers {
            var layerStrokes = strokes
            if let activeStroke, activeStroke.layerID == layer.id {
                layerStrokes.append(activeStroke)
            }
            drawLayer(layer: layer, strokes: layerStrokes, in: context)
        }
    }

    private func drawStoredStrokes(_ strokes: [Stroke], in context: CGContext) {
        let visibleLayers = layers.filter(\.isVisible)
        for layer in visibleLayers {
            drawLayer(layer: layer, strokes: strokes, in: context)
        }
    }

    private func drawLayer(layer: DrawingLayer, strokes: [Stroke], in context: CGContext) {
        let layerStrokes = strokes.filter { $0.layerID == layer.id }
        guard !layerStrokes.isEmpty else {
            return
        }

        context.saveGState()
        context.setAlpha(layer.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        for stroke in layerStrokes {
            drawStroke(stroke, in: context)
        }

        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawStroke(_ stroke: Stroke, in context: CGContext) {
        guard let firstPoint = stroke.points.first?.position else {
            return
        }

        context.saveGState()
        context.setBlendMode(stroke.brush.blendMode)
        context.setStrokeColor(stroke.brush.color.cgColor)
        context.setLineWidth(stroke.brush.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if stroke.points.count == 1 {
            context.setFillColor(stroke.brush.color.cgColor)
            let radius = stroke.brush.lineWidth / 2
            context.fillEllipse(in: CGRect(
                x: firstPoint.x - radius,
                y: firstPoint.y - radius,
                width: stroke.brush.lineWidth,
                height: stroke.brush.lineWidth
            ))
        } else {
            context.beginPath()
            context.move(to: firstPoint)

            for index in 1..<stroke.points.count {
                let current = stroke.points[index].position
                let previous = stroke.points[index - 1].position
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                context.addQuadCurve(to: midpoint, control: previous)
            }

            if let lastPoint = stroke.points.last?.position {
                context.addLine(to: lastPoint)
            }

            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawBoardBackground(in rect: CGRect, context: CGContext, respectsTransparency: Bool) {
        guard !respectsTransparency || !canvasConfig.isTransparentExportEnabled else {
            context.clear(rect)
            return
        }

        boardColor.setFill()
        context.fill(rect)
    }

    private func drawRenderBackground(in rect: CGRect, context: CGContext) {
        if canvasConfig.isTransparentExportEnabled {
            context.clear(rect)
        } else {
            boardColor.setFill()
            context.fill(rect)
        }
    }

    private func drawCanvasShadow(in context: CGContext) {
        guard canvasRect != bounds else {
            return
        }

        context.saveGState()
        UIColor.secondarySystemBackground.setFill()
        context.fill(bounds)
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        UIColor.white.setFill()
        context.fill(canvasRect)
        context.restoreGState()
    }

    private func drawCalibrationOverlay(in context: CGContext) {
        context.saveGState()
        let rect = canvasRect.insetBy(dx: 18, dy: 18)
        context.setLineWidth(1)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.28).cgColor)
        context.setLineDash(phase: 0, lengths: [6, 6])

        let horizontalY = rect.midY
        context.move(to: CGPoint(x: rect.minX, y: horizontalY))
        context.addLine(to: CGPoint(x: rect.maxX, y: horizontalY))

        let verticalX = rect.midX
        context.move(to: CGPoint(x: verticalX, y: rect.minY))
        context.addLine(to: CGPoint(x: verticalX, y: rect.maxY))

        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.18).cgColor)
        let radius = min(rect.width, rect.height) * 0.22
        context.strokeEllipse(in: CGRect(
            x: rect.midX - radius,
            y: rect.midY - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.restoreGState()
    }

    private func drawCursor(at point: CGPoint, in context: CGContext) {
        context.saveGState()

        let pencilAngle = CGFloat.pi * 3 / 4
        let pencilLength: CGFloat = 46
        let pencilWidth: CGFloat = 12
        let axis = CGPoint(x: cos(pencilAngle), y: sin(pencilAngle))
        let normal = CGPoint(x: -axis.y, y: axis.x)
        let tipLength: CGFloat = 12
        let woodBase = CGPoint(
            x: point.x - axis.x * tipLength,
            y: point.y - axis.y * tipLength
        )
        let endCenter = CGPoint(
            x: point.x - axis.x * pencilLength,
            y: point.y - axis.y * pencilLength
        )

        let graphitePath = UIBezierPath()
        graphitePath.move(to: point)
        graphitePath.addLine(to: CGPoint(
            x: woodBase.x + normal.x * pencilWidth * 0.45,
            y: woodBase.y + normal.y * pencilWidth * 0.45
        ))
        graphitePath.addLine(to: CGPoint(
            x: woodBase.x - normal.x * pencilWidth * 0.45,
            y: woodBase.y - normal.y * pencilWidth * 0.45
        ))
        graphitePath.close()
        UIColor(white: 0.16, alpha: 1).setFill()
        graphitePath.fill()

        let bodyPath = UIBezierPath()
        bodyPath.move(to: CGPoint(
            x: woodBase.x + normal.x * pencilWidth * 0.5,
            y: woodBase.y + normal.y * pencilWidth * 0.5
        ))
        bodyPath.addLine(to: CGPoint(
            x: endCenter.x + normal.x * pencilWidth * 0.5,
            y: endCenter.y + normal.y * pencilWidth * 0.5
        ))
        bodyPath.addLine(to: CGPoint(
            x: endCenter.x - normal.x * pencilWidth * 0.5,
            y: endCenter.y - normal.y * pencilWidth * 0.5
        ))
        bodyPath.addLine(to: CGPoint(
            x: woodBase.x - normal.x * pencilWidth * 0.5,
            y: woodBase.y - normal.y * pencilWidth * 0.5
        ))
        bodyPath.close()
        UIColor.systemYellow.setFill()
        bodyPath.fill()

        UIColor(white: 0.2, alpha: 0.9).setStroke()
        graphitePath.lineWidth = 1
        graphitePath.stroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        if drawingMode == .waitingLongPress {
            drawLongPressProgress(at: point, in: context)
        }

        context.restoreGState()
    }

    private func drawStabilizerLine(from cursorPoint: CGPoint, to targetPoint: CGPoint, in context: CGContext) {
        guard cursorPoint != targetPoint else {
            return
        }

        context.saveGState()
        context.setLineWidth(1.5)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.45).cgColor)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.move(to: cursorPoint)
        context.addLine(to: targetPoint)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.65).cgColor)
        context.fillEllipse(in: CGRect(x: targetPoint.x - 3, y: targetPoint.y - 3, width: 6, height: 6))
        context.restoreGState()
    }

    private func drawLongPressProgress(at point: CGPoint, in context: CGContext) {
        let radius: CGFloat = 18
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + CGFloat.pi * 2 * longPressProgress

        context.setLineWidth(3)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.18).cgColor)
        context.strokeEllipse(in: rect)

        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineCap(.round)
        context.addArc(center: point, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        context.strokePath()
    }
}
