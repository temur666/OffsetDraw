import UIKit

final class DrawingCanvasView: UIView {
    var brush = BrushConfig.initial {
        didSet {
            setNeedsDisplay()
        }
    }

    private(set) var strokes: [Stroke] = []
    private var activePoints: [StrokePoint] = []
    private var cursorPosition: CGPoint?
    private var targetPosition: CGPoint?
    private var touchToTipOffset: CGPoint?
    private var touchStartPosition: CGPoint?
    private var longPressStartTime: TimeInterval?
    private var longPressTimer: Timer?
    private var drawingMode = DrawingMode.idle
    private let longPressDuration: TimeInterval = 0.3
    private let longPressMovementTolerance: CGFloat = 8

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
        resetLongPressState(keepCursor: true)
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
        resetLongPressState(keepCursor: true)
        guard let cursorPosition else {
            return
        }

        let touchPoint = touch.location(in: self)
        touchToTipOffset = CGPoint(
            x: cursorPosition.x - touchPoint.x,
            y: cursorPosition.y - touchPoint.y
        )

        activePoints.removeAll()
        targetPosition = cursorPosition
        touchStartPosition = cursorPosition
        longPressStartTime = CACurrentMediaTime()
        drawingMode = .waitingLongPress
        startLongPressTimer()
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            guard let point = drawingPoint(from: sample) else {
                continue
            }

            switch drawingMode {
            case .waitingLongPress:
                moveCursor(to: point)
                if hasMovedBeyondLongPressTolerance(to: point) {
                    cancelLongPress(keepCursor: true, keepTouchOffset: true)
                    drawingMode = .hoveringTip
                }
            case .hoveringTip:
                moveCursor(to: point)
            case .drawing:
                appendPoint(point)
            case .idle:
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
        resetLongPressState(keepCursor: true)
        setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = .white
        isMultipleTouchEnabled = false
        contentMode = .redraw
    }

    private func drawingPoint(from touch: UITouch?) -> CGPoint? {
        guard let touch else {
            return nil
        }

        let touchPoint = touch.location(in: self)
        guard let touchToTipOffset else {
            return touchPoint
        }

        return CGPoint(
            x: touchPoint.x + touchToTipOffset.x,
            y: touchPoint.y + touchToTipOffset.y
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
        let previousTipPosition = cursorPosition ?? stabilizedPoint
        targetPosition = point
        guard previousTipPosition != stabilizedPoint else {
            return
        }

        if activePoints.isEmpty {
            activePoints.append(StrokePoint(position: previousTipPosition, timestamp: CACurrentMediaTime()))
        }

        guard activePoints.last?.position != stabilizedPoint else {
            cursorPosition = stabilizedPoint
            return
        }

        activePoints.append(StrokePoint(position: stabilizedPoint, timestamp: CACurrentMediaTime()))
        cursorPosition = stabilizedPoint
    }

    private func moveCursor(to targetPoint: CGPoint) {
        targetPosition = targetPoint
        cursorPosition = stabilizedTipPosition(for: targetPoint)
    }

    private func finishActiveStroke() {
        if drawingMode == .drawing && !activePoints.isEmpty {
            strokes.append(Stroke(points: activePoints, brush: brush))
        }

        activePoints.removeAll()
        resetLongPressState(keepCursor: true)
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

        longPressTimer?.invalidate()
        longPressTimer = nil
        drawingMode = .drawing
        activePoints.removeAll()
        setNeedsDisplay()
    }

    private func cancelLongPress(keepCursor: Bool, keepTouchOffset: Bool = false) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressStartTime = nil
        touchStartPosition = nil
        if !keepTouchOffset {
            touchToTipOffset = nil
        }
        activePoints.removeAll()
        if !keepCursor {
            cursorPosition = nil
            targetPosition = nil
        }
    }

    private func resetLongPressState(keepCursor: Bool) {
        cancelLongPress(keepCursor: keepCursor)
        drawingMode = .idle
    }

    private var longPressProgress: CGFloat {
        guard drawingMode == .waitingLongPress, let longPressStartTime else {
            return 0
        }

        let elapsed = CACurrentMediaTime() - longPressStartTime
        return min(max(CGFloat(elapsed / longPressDuration), 0), 1)
    }

    private func hasMovedBeyondLongPressTolerance(to point: CGPoint) -> Bool {
        guard let touchStartPosition else {
            return false
        }

        let xDistance = point.x - touchStartPosition.x
        let yDistance = point.y - touchStartPosition.y
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
