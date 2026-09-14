import UIKit
import PencilKit

@available(iOS 18.0, *)
private final class ToolPickerCanvasView: PKCanvasView {
    override var canBecomeFirstResponder: Bool {
        true
    }
}

@available(iOS 18.0, *)
private struct CheckHighlighterStamp {
    let center: CGPoint
    let color: UIColor
    let size: CGFloat
}

@available(iOS 18.0, *)
private struct CheckHighlighterStroke {
    let points: [CGPoint]
    let color: UIColor
    let size: CGFloat
}

@available(iOS 18.0, *)
private final class CheckHighlighterCanvasView: UIView {
    var styleProvider: (() -> (color: UIColor, size: CGFloat))?

    private let strokeMovementThreshold: CGFloat = 8
    private var stamps: [CheckHighlighterStamp] = []
    private var strokes: [CheckHighlighterStroke] = []
    private var touchStartPoint: CGPoint?
    private var activePoints: [CGPoint] = []
    private var activeStyle: (color: UIColor, size: CGFloat)?
    private var isDrawingStroke = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let point = touch.location(in: self)
        touchStartPoint = point
        activePoints = [point]
        activeStyle = resolvedStyle()
        isDrawingStroke = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        var didChangeStroke = false
        for sample in samples {
            didChangeStroke = handleMovedPoint(sample.location(in: self)) || didChangeStroke
        }

        if didChangeStroke {
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            _ = handleMovedPoint(touch.location(in: self))
        }

        if isDrawingStroke,
           activePoints.count > 1,
           let activeStyle {
            strokes.append(
                CheckHighlighterStroke(
                    points: activePoints,
                    color: activeStyle.color,
                    size: activeStyle.size
                )
            )
        } else if let touchStartPoint {
            placeStamp(at: touchStartPoint, style: activeStyle ?? resolvedStyle())
        }

        resetInteraction()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetInteraction()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for stroke in strokes {
            draw(stroke, in: context)
        }

        for stamp in stamps {
            draw(stamp, in: context)
        }

        if isDrawingStroke,
           activePoints.count > 1,
           let activeStyle {
            draw(
                CheckHighlighterStroke(
                    points: activePoints,
                    color: activeStyle.color,
                    size: activeStyle.size
                ),
                in: context
            )
        }
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @discardableResult
    private func handleMovedPoint(_ point: CGPoint) -> Bool {
        guard let touchStartPoint else {
            return false
        }

        if !isDrawingStroke {
            let distanceFromStart = hypot(
                point.x - touchStartPoint.x,
                point.y - touchStartPoint.y
            )

            guard distanceFromStart >= strokeMovementThreshold else {
                return false
            }

            // The gesture becomes a normal highlighter stroke as soon as it moves
            // far enough. The stored start point lets the stroke begin exactly at
            // touch-down instead of appearing after the threshold.
            isDrawingStroke = true
        }

        guard activePoints.last != point else {
            return false
        }

        activePoints.append(point)
        return true
    }

    private func placeStamp(at point: CGPoint, style: (color: UIColor, size: CGFloat)) {
        stamps.append(
            CheckHighlighterStamp(
                center: point,
                color: style.color,
                size: style.size
            )
        )
    }

    private func resolvedStyle() -> (color: UIColor, size: CGFloat) {
        let style = styleProvider?() ?? (.systemYellow, 40)
        return (style.color, max(22, style.size))
    }

    private func resetInteraction() {
        touchStartPoint = nil
        activePoints.removeAll()
        activeStyle = nil
        isDrawingStroke = false
    }

    private func draw(_ stroke: CheckHighlighterStroke, in context: CGContext) {
        guard stroke.points.count > 1 else {
            return
        }

        context.saveGState()
        context.setBlendMode(.multiply)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let lineWidth = max(8, stroke.size * 0.30)
        let selectedAlpha = max(stroke.color.cgColor.alpha, 0.35)

        drawPath(
            stroke.points,
            color: stroke.color.withAlphaComponent(selectedAlpha * 0.09),
            lineWidth: lineWidth * 1.24,
            in: context
        )
        drawPath(
            stroke.points,
            color: stroke.color.withAlphaComponent(selectedAlpha * 0.30),
            lineWidth: lineWidth,
            in: context
        )

        context.restoreGState()
    }

    private func drawPath(
        _ points: [CGPoint],
        color: UIColor,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        guard let first = points.first else {
            return
        }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func draw(_ stamp: CheckHighlighterStamp, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: stamp.center.x, y: stamp.center.y)
        context.setBlendMode(.multiply)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let size = stamp.size
        let lineWidth = max(7, size * 0.21)
        let start = CGPoint(x: -size * 0.36, y: 0)
        let middle = CGPoint(x: -size * 0.10, y: size * 0.28)
        let end = CGPoint(x: size * 0.44, y: -size * 0.34)
        let selectedAlpha = max(stamp.color.cgColor.alpha, 0.35)

        context.setStrokeColor(stamp.color.withAlphaComponent(selectedAlpha * 0.10).cgColor)
        context.setLineWidth(lineWidth * 1.30)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: middle)
        context.addLine(to: end)
        context.strokePath()

        context.setStrokeColor(stamp.color.withAlphaComponent(selectedAlpha * 0.34).cgColor)
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: middle)
        context.addLine(to: end)
        context.strokePath()

        context.restoreGState()
    }
}

@available(iOS 18.0, *)
private final class CheckToolPickerBridge: NSObject, PKToolPickerObserver {
    private static let checkIdentifier = "com.tiemuernow.OffsetDraw.tool.check-highlighter"

    private weak var drawingCanvas: DrawingCanvasView?
    private let pencilCanvas = ToolPickerCanvasView()
    private let checkCanvas = CheckHighlighterCanvasView()
    private let checkItem: PKToolPickerCustomItem
    private let toolPicker: PKToolPicker

    init(drawingCanvas: DrawingCanvasView) {
        self.drawingCanvas = drawingCanvas

        var configuration = PKToolPickerCustomItem.Configuration(
            identifier: Self.checkIdentifier,
            name: "Check"
        )
        configuration.allowsColorSelection = true
        configuration.defaultColor = .systemYellow
        configuration.defaultWidth = 40
        configuration.widthVariants = [
            28: Self.widthVariantImage(size: 28),
            40: Self.widthVariantImage(size: 40),
            54: Self.widthVariantImage(size: 54)
        ]
        configuration.imageProvider = { item in
            Self.checkToolImage(color: item.color, size: item.width)
        }

        let checkItem = PKToolPickerCustomItem(configuration: configuration)
        self.checkItem = checkItem

        let pen = PKToolPickerInkingItem(
            type: .pen,
            color: nil,
            width: nil,
            identifier: "com.tiemuernow.OffsetDraw.tool.pen"
        )
        let pencil = PKToolPickerInkingItem(
            type: .pencil,
            color: nil,
            width: nil,
            identifier: "com.tiemuernow.OffsetDraw.tool.pencil"
        )
        let marker = PKToolPickerInkingItem(
            type: .marker,
            color: nil,
            width: nil,
            identifier: "com.tiemuernow.OffsetDraw.tool.marker"
        )
        let eraser = PKToolPickerEraserItem(type: .vector)

        toolPicker = PKToolPicker(toolItems: [
            checkItem,
            pen,
            pencil,
            marker,
            eraser
        ])

        super.init()

        pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
        pencilCanvas.backgroundColor = .clear
        pencilCanvas.isOpaque = false
        pencilCanvas.isScrollEnabled = false
        pencilCanvas.bounces = false
        pencilCanvas.drawingPolicy = .anyInput

        checkCanvas.translatesAutoresizingMaskIntoConstraints = false
        checkCanvas.styleProvider = { [weak checkItem] in
            guard let checkItem else {
                return (.systemYellow, 40)
            }
            return (checkItem.color, checkItem.width)
        }

        // PencilKit stays underneath. The custom layer only intercepts touches while
        // Check is selected: a drag draws normally and a tap stamps a check mark.
        drawingCanvas.addSubview(pencilCanvas)
        drawingCanvas.addSubview(checkCanvas)
        NSLayoutConstraint.activate([
            pencilCanvas.leadingAnchor.constraint(equalTo: drawingCanvas.leadingAnchor),
            pencilCanvas.trailingAnchor.constraint(equalTo: drawingCanvas.trailingAnchor),
            pencilCanvas.topAnchor.constraint(equalTo: drawingCanvas.topAnchor),
            pencilCanvas.bottomAnchor.constraint(equalTo: drawingCanvas.bottomAnchor),
            checkCanvas.leadingAnchor.constraint(equalTo: drawingCanvas.leadingAnchor),
            checkCanvas.trailingAnchor.constraint(equalTo: drawingCanvas.trailingAnchor),
            checkCanvas.topAnchor.constraint(equalTo: drawingCanvas.topAnchor),
            checkCanvas.bottomAnchor.constraint(equalTo: drawingCanvas.bottomAnchor)
        ])

        toolPicker.stateAutosaveName = nil
        toolPicker.addObserver(pencilCanvas)
        toolPicker.addObserver(self)
        toolPicker.selectedToolItem = checkItem
        applySelectedToolState()
    }

    func activate() {
        guard pencilCanvas.window != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.activate()
            }
            return
        }

        if #available(iOS 26.0, *) {
            pencilCanvas.pencilKitResponderState.activeToolPicker = toolPicker
            pencilCanvas.pencilKitResponderState.toolPickerVisibility = .visible
        } else {
            toolPicker.setVisible(true, forFirstResponder: pencilCanvas)
        }

        pencilCanvas.becomeFirstResponder()

        DispatchQueue.main.async { [weak self] in
            self?.ensurePickerVisible()
        }
    }

    func deactivate() {
        if #available(iOS 26.0, *) {
            pencilCanvas.pencilKitResponderState.toolPickerVisibility = .inactive
            pencilCanvas.pencilKitResponderState.activeToolPicker = nil
        } else {
            toolPicker.setVisible(false, forFirstResponder: pencilCanvas)
        }

        pencilCanvas.resignFirstResponder()
        toolPicker.removeObserver(self)
        toolPicker.removeObserver(pencilCanvas)
        checkCanvas.removeFromSuperview()
        pencilCanvas.removeFromSuperview()
    }

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        applySelectedToolState()
    }

    private func ensurePickerVisible() {
        guard pencilCanvas.window != nil else {
            return
        }

        if #available(iOS 26.0, *) {
            pencilCanvas.pencilKitResponderState.activeToolPicker = toolPicker
            pencilCanvas.pencilKitResponderState.toolPickerVisibility = .visible
        } else {
            toolPicker.setVisible(true, forFirstResponder: pencilCanvas)
        }

        if !pencilCanvas.isFirstResponder {
            pencilCanvas.becomeFirstResponder()
        }
    }

    private func applySelectedToolState() {
        let usesCheckTool = toolPicker.selectedToolItem.identifier == Self.checkIdentifier
        checkCanvas.isUserInteractionEnabled = usesCheckTool
    }

    private static func checkToolImage(color: UIColor, size: CGFloat) -> UIImage {
        let imageSize = CGSize(width: 72, height: 180)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setBlendMode(.multiply)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let normalizedSize = min(max(size, 28), 54)
            let lineWidth = 8 + (normalizedSize - 28) / 26 * 5
            let alpha = max(color.cgColor.alpha, 0.35)
            cg.setStrokeColor(color.withAlphaComponent(alpha * 0.65).cgColor)
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: 15, y: 96))
            cg.addLine(to: CGPoint(x: 31, y: 112))
            cg.addLine(to: CGPoint(x: 58, y: 72))
            cg.strokePath()
        }
    }

    private static func widthVariantImage(size: CGFloat) -> UIImage {
        let imageSize = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.label.cgColor)
            let lineWidth = max(3, min(8, size * 0.14))
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: 7, y: 23))
            cg.addLine(to: CGPoint(x: 17, y: 32))
            cg.addLine(to: CGPoint(x: 37, y: 12))
            cg.strokePath()
        }
    }
}

final class DrawingNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private var toolPickerBridge: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        updateInteractivePopGesture(for: topViewController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        updateInteractivePopGesture(for: viewController)
        updateToolPickerExperiment(for: viewController)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer
            || gestureRecognizer === contentSwipeGestureRecognizer else {
            return true
        }

        return viewControllers.count > 1 && !(topViewController is ViewController)
    }

    private func updateInteractivePopGesture(for viewController: UIViewController?) {
        let allowsInteractivePop = viewControllers.count > 1 && !(viewController is ViewController)
        let popGestures = [interactivePopGestureRecognizer, contentSwipeGestureRecognizer].compactMap { $0 }

        for popGesture in popGestures {
            popGesture.delegate = self
            popGesture.isEnabled = allowsInteractivePop
        }
    }

    private func updateToolPickerExperiment(for viewController: UIViewController?) {
        guard #available(iOS 18.0, *) else {
            return
        }

        if let existingBridge = toolPickerBridge as? CheckToolPickerBridge {
            existingBridge.deactivate()
            toolPickerBridge = nil
        }

        guard viewController is ViewController,
              let rootView = viewController?.view,
              let drawingCanvas = findDrawingCanvas(in: rootView) else {
            return
        }

        let bridge = CheckToolPickerBridge(drawingCanvas: drawingCanvas)
        toolPickerBridge = bridge
        bridge.activate()
    }

    private func findDrawingCanvas(in view: UIView) -> DrawingCanvasView? {
        if let drawingCanvas = view as? DrawingCanvasView {
            return drawingCanvas
        }

        for subview in view.subviews {
            if let drawingCanvas = findDrawingCanvas(in: subview) {
                return drawingCanvas
            }
        }

        return nil
    }

    private var contentSwipeGestureRecognizer: UIGestureRecognizer? {
        // iOS 26 uses a separate full-width swipe recognizer for navigation transitions.
        view.gestureRecognizers?.first { $0.name == "UINavigationController.contentSwipe" }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let store: DrawingDocumentStore
        do {
            store = try DrawingDocumentStore()
        } catch {
            return
        }
        window.rootViewController = DrawingNavigationController(rootViewController: HomeViewController(store: store))
        window.makeKeyAndVisible()
        self.window = window
    }
}
