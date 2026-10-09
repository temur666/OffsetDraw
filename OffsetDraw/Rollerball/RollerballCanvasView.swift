import UIKit

final class RollerballCanvasView: UIView {
    var settings = RollerballSettings()
    var onChange: (() -> Void)?
    private(set) var strokes: [RollerballStroke] = []
    private var redoStack: [RollerballStroke] = []
    let engine = RollerballEngine()
    private var activeTouch: UITouch?
    private var bitmap: CGContext?
    private var bitmapSize: CGSize = .zero
    private var paintedPoints = 0
    private var displayLink: CADisplayLink?
    private let clockTarget = RollerballClockTarget()
    var isDrawing: Bool { engine.stroke != nil }
    var canUndo: Bool { !strokes.isEmpty && !isDrawing }
    var canRedo: Bool { !redoStack.isEmpty && !isDrawing }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1)
        isOpaque = true
        isMultipleTouchEnabled = false
        layer.cornerRadius = 16
        clipsToBounds = true
        accessibilityLabel = "走珠笔独立画布"
        clockTarget.canvas = self
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate(); NotificationCenter.default.removeObserver(self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bitmapSize != bounds.size { rebuild() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { interrupted() }
    }

    private func rebuild() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        bitmapSize = bounds.size
        let scale = min(window?.screen.scale ?? traitCollection.displayScale, 2.5)
        bitmap = CGContext(data: nil, width: Int(ceil(bounds.width * scale)),
                           height: Int(ceil(bounds.height * scale)), bitsPerComponent: 8,
                           bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        bitmap?.translateBy(x: 0, y: CGFloat(bitmap?.height ?? 0))
        bitmap?.scaleBy(x: scale, y: -scale)
        for stroke in strokes { paint(stroke) }
        paintedPoints = 0
        paintActive()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(backgroundColor?.cgColor ?? UIColor.black.cgColor)
        context.fill(bounds)
        context.setFillColor(UIColor(red: 0.25, green: 0.28, blue: 0.33, alpha: 0.68).cgColor)
        for x in stride(from: 12.0, to: bounds.width, by: 24) {
            for y in stride(from: 12.0, to: bounds.height, by: 24) {
                context.fillEllipse(in: CGRect(x: x - 0.65, y: y - 0.65, width: 1.3, height: 1.3))
            }
        }
        if let image = bitmap?.makeImage() {
            // The bitmap uses a top-left drawing transform, so draw its raw image flipped back.
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: bounds)
            context.restoreGState()
        }
    }

    private func circle(_ p: RollerballPoint) {
        let r = max(0.001, p.radius)
        bitmap?.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private func segment(_ a: RollerballPoint, _ b: RollerballPoint) {
        let distance = hypot(b.x - a.x, b.y - a.y)
        let step = max(0.13, min(a.radius, b.radius) * 0.45)
        let count = max(1, Int(ceil(distance / step)))
        for i in 1...count {
            let t = Double(i) / Double(count)
            circle(RollerballPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                                   time: b.time, radius: a.radius + (b.radius - a.radius) * t))
        }
    }

    private func paint(_ stroke: RollerballStroke) {
        bitmap?.setFillColor(UIColor(rollerballHex: stroke.settings.color).nightCanvasInk.cgColor)
        guard let first = stroke.points.first else { return }
        circle(first)
        for index in 1..<stroke.points.count { segment(stroke.points[index - 1], stroke.points[index]) }
        if let pool = stroke.pool { circle(pool) }
    }

    private func paintActive() {
        guard let stroke = engine.stroke else { return }
        bitmap?.setFillColor(UIColor(rollerballHex: stroke.settings.color).nightCanvasInk.cgColor)
        for index in paintedPoints..<stroke.points.count {
            if index == 0 { circle(stroke.points[index]) }
            else { segment(stroke.points[index - 1], stroke.points[index]) }
        }
        paintedPoints = stroke.points.count
        setNeedsDisplay()
        onChange?()
    }

    private func pressure(_ touch: UITouch) -> Double? {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return nil }
        let rawPressure = min(1, max(0, Double(touch.force / touch.maximumPossibleForce)))
        // Pencil force is perceptually very low in the first part of its range. Lift
        // light strokes toward the finger-width baseline while retaining full pressure.
        return pow(max(0.2, rawPressure), 0.55)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let point = touch.location(in: self)
        engine.begin(x: point.x, y: point.y, time: touch.timestamp, pressure: pressure(touch), settings: settings)
        paintedPoints = 0
        paintActive()
        let link = CADisplayLink(target: clockTarget, selector: #selector(RollerballClockTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: self)
            engine.move(x: point.x, y: point.y, time: sample.timestamp, pressure: pressure(sample))
        }
        paintActive()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        // Release reports zero force; preserve the last contact pressure just like the HTML.
        engine.move(x: point.x, y: point.y, time: touch.timestamp, pressure: nil)
        paintActive()
        finish(time: touch.timestamp, withPool: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { interrupted() }

    @objc private func interrupted() { finish(time: CACurrentMediaTime(), withPool: false) }

    fileprivate func tick(_ link: CADisplayLink) {
        engine.tick(time: link.timestamp)
        paintActive()
    }

    private func finish(time: Double, withPool: Bool) {
        displayLink?.invalidate()
        displayLink = nil
        activeTouch = nil
        guard let stroke = engine.finish(time: time, withPool: withPool) else { return }
        if let pool = stroke.pool {
            bitmap?.setFillColor(UIColor(rollerballHex: stroke.settings.color).nightCanvasInk.cgColor)
            circle(pool)
        }
        strokes.append(stroke)
        redoStack.removeAll()
        onChange?()
        setNeedsDisplay()
    }

    func undo() {
        guard canUndo, let stroke = strokes.popLast() else { return }
        redoStack.append(stroke)
        rebuild()
        onChange?()
    }

    func redo() {
        guard canRedo, let stroke = redoStack.popLast() else { return }
        strokes.append(stroke)
        rebuild()
        onChange?()
    }

    func clear() {
        guard !isDrawing else { return }
        strokes.removeAll()
        redoStack.removeAll()
        rebuild()
        onChange?()
    }
}

private final class RollerballClockTarget: NSObject {
    weak var canvas: RollerballCanvasView?
    @objc func tick(_ link: CADisplayLink) { canvas?.tick(link) }
}

extension UIColor {
    convenience init(rollerballHex: String) {
        let value = UInt32(rollerballHex.dropFirst(), radix: 16) ?? 0x203656
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

private extension UIColor {
    /// Preserve the selected hue while lifting dark inks to readable colors on the night canvas.
    var nightCanvasInk: UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        let lift: CGFloat = 0.68
        return UIColor(red: red + (1 - red) * lift, green: green + (1 - green) * lift,
                       blue: blue + (1 - blue) * lift, alpha: alpha)
    }
}
