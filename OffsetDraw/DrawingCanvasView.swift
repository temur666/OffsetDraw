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

    var interactionMode: DrawingInteractionMode = .longPress {
        didSet {
            isButtonStrokeActive = false
            finishActiveStroke()
            resetInteractionState(keepCursor: true)
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
    private let doubleTapInterval: TimeInterval = 0.28
    private let doubleTapMovementTolerance: CGFloat = 18
    private var lastTapTime: TimeInterval?
    private var lastTapPosition: CGPoint?
    private var isButtonStrokeActive = false

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
    }

    func clearDrawing() {
        strokes.removeAll()
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
    }

    func renderImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            drawStrokes(strokes, in: context.cgContext)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        ensureCursorPosition()
        UIColor.white.setFill()
        context.fill(rect)
        drawStrokes(strokes, in: context)

        if !activePoints.isEmpty {
            drawStroke(Stroke(points: activePoints, brush: brush), in: context)
        }

        if let cursorPosition, let targetPosition {
            drawStabilizerLine(from: cursorPosition, to: targetPosition, in: context)
        }

        if let cursorPosition {
            drawCursor(at: cursorPosition, in: context)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        ensureCursorPosition()
        resetInteractionState(keepCursor: true)
        guard let cursorPosition else {
            return
        }

        let touchPoint = touch.location(in: self)
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
            latestTouchPosition = sample.location(in: self)

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
        recordTapIfNeeded(touch: touches.first)
        finishActiveStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = .white
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    func beginButtonStroke() {
        guard interactionMode == .buttonHold else {
            return
        }

        isButtonStrokeActive = true
        ensureCursorPosition()
        guard let cursorPosition else {
            return
        }

        guard drawingMode != .drawing else {
            return
        }

        beginDrawing(at: cursorPosition)
    }

    func endButtonStroke() {
        guard interactionMode == .buttonHold else {
            return
        }

        isButtonStrokeActive = false
        finishActiveStroke()
    }

    private func drawingPoint(from touch: UITouch?, movementScale: CGFloat) -> CGPoint? {
        guard let touch else {
            return nil
        }

        let touchPoint = touch.location(in: self)
        guard let touchAnchorPosition, let tipAnchorPosition else {
            return touchPoint
        }

        return CGPoint(
            x: tipAnchorPosition.x + (touchPoint.x - touchAnchorPosition.x) * movementScale,
            y: tipAnchorPosition.y + (touchPoint.y - touchAnchorPosition.y) * movementScale
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
            strokes.append(Stroke(points: activePoints, brush: brush))
        }

        activePoints.removeAll()
        smoothedDrawingPoint = nil
        resetInteractionState(keepCursor: true)
        setNeedsDisplay()
    }

    private func ensureCursorPosition() {
        if cursorPosition == nil {
            cursorPosition = CGPoint(x: bounds.midX, y: bounds.midY - 48)
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
        switch interactionMode {
        case .longPress:
            longPressStartTime = CACurrentMediaTime()
            drawingMode = .waitingLongPress
            startLongPressTimer()
        case .buttonHold:
            if isButtonStrokeActive {
                beginDrawing(at: point)
            } else {
                drawingMode = .hoveringTip
            }
        case .doubleTapHold:
            if isSecondTap(at: point) {
                lastTapTime = nil
                lastTapPosition = nil
                beginDrawing(at: point)
            } else {
                drawingMode = .hoveringTip
            }
        }
    }

    private func recordTapIfNeeded(touch: UITouch?) {
        guard interactionMode == .doubleTapHold, drawingMode != .drawing else {
            return
        }

        guard let point = drawingPoint(from: touch, movementScale: 1) ?? cursorPosition else {
            return
        }

        lastTapTime = CACurrentMediaTime()
        lastTapPosition = point
    }

    private func isSecondTap(at point: CGPoint) -> Bool {
        guard let lastTapTime, let lastTapPosition else {
            return false
        }

        let elapsed = CACurrentMediaTime() - lastTapTime
        let xDistance = point.x - lastTapPosition.x
        let yDistance = point.y - lastTapPosition.y
        return elapsed <= doubleTapInterval && hypot(xDistance, yDistance) <= doubleTapMovementTolerance
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

    private func drawStrokes(_ strokes: [Stroke], in context: CGContext) {
        for stroke in strokes {
            drawStroke(stroke, in: context)
        }
    }

    private func drawStroke(_ stroke: Stroke, in context: CGContext) {
        guard let firstPoint = stroke.points.first?.position else {
            return
        }

        context.saveGState()
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
