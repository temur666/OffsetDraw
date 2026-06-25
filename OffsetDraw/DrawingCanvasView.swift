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
    private let tipOffset = CGPoint(x: 0, y: -72)

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
        cursorPosition = nil
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

        UIColor.white.setFill()
        context.fill(rect)
        drawStrokes(strokes, in: context)

        if !activePoints.isEmpty {
            drawStroke(Stroke(points: activePoints, brush: brush), in: context)
        }

        if let cursorPosition {
            drawCursor(at: cursorPosition, in: context)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = drawingPoint(from: touches.first) else {
            return
        }

        activePoints = [StrokePoint(position: point, timestamp: CACurrentMediaTime())]
        cursorPosition = point
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
            appendPoint(point)
        }

        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishActiveStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePoints.removeAll()
        cursorPosition = nil
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
        return CGPoint(x: touchPoint.x + tipOffset.x, y: touchPoint.y + tipOffset.y)
    }

    private func appendPoint(_ point: CGPoint) {
        guard activePoints.last?.position != point else {
            return
        }

        let smoothedPoint: CGPoint
        if let previous = activePoints.last?.position {
            smoothedPoint = CGPoint(
                x: previous.x * 0.35 + point.x * 0.65,
                y: previous.y * 0.35 + point.y * 0.65
            )
        } else {
            smoothedPoint = point
        }

        activePoints.append(StrokePoint(position: smoothedPoint, timestamp: CACurrentMediaTime()))
        cursorPosition = smoothedPoint
    }

    private func finishActiveStroke() {
        if !activePoints.isEmpty {
            strokes.append(Stroke(points: activePoints, brush: brush))
        }

        activePoints.removeAll()
        cursorPosition = nil
        setNeedsDisplay()
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
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        context.move(to: CGPoint(x: point.x - 11, y: point.y))
        context.addLine(to: CGPoint(x: point.x + 11, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - 11))
        context.addLine(to: CGPoint(x: point.x, y: point.y + 11))
        context.strokePath()
        context.restoreGState()
    }
}
