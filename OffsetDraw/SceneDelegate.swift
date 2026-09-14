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
private final class CheckHighlighterCanvasView: UIView {
    var styleProvider: (() -> (color: UIColor, size: CGFloat))?

    private var stamps: [CheckHighlighterStamp] = []
    private var lastStampPoint: CGPoint?

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
        placeStamp(at: point)
        lastStampPoint = point
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            placeIntermediateStamps(toward: sample.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastStampPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastStampPoint = nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for stamp in stamps {
            draw(stamp, in: context)
        }
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    private func placeIntermediateStamps(toward point: CGPoint) {
        guard let lastStampPoint else {
            placeStamp(at: point)
            self.lastStampPoint = point
            return
        }

        let style = resolvedStyle()
        let spacing = max(18, style.size * 0.82)
        let dx = point.x - lastStampPoint.x
        let dy = point.y - lastStampPoint.y
        let distance = hypot(dx, dy)

        guard distance >= spacing else {
            return
        }

        let stepCount = Int(distance / spacing)
        guard stepCount > 0 else {
            return
        }

        let unitX = dx / distance
        let unitY = dy / distance
        var newestStampPoint = lastStampPoint

        for step in 1...stepCount {
            let stepDistance = CGFloat(step) * spacing
            let stampPoint = CGPoint(
                x: lastStampPoint.x + unitX * stepDistance,
                y: lastStampPoint.y + unitY * stepDistance
            )
            placeStamp(at: stampPoint, style: style)
            newestStampPoint = stampPoint
        }

        self.lastStampPoint = newestStampPoint
    }

    private func placeStamp(at point: CGPoint) {
        placeStamp(at: point, style: resolvedStyle())
    }

    private func placeStamp(at point: CGPoint, style: (color: UIColor, size: CGFloat)) {
        stamps.append(
            CheckHighlighterStamp(
                center: point,
                color: style.color,
                size: style.size
            )
        )
        setNeedsDisplay()
    }

    private func resolvedStyle() -> (color: UIColor, size: CGFloat) {
        let style = styleProvider?() ?? (.systemYellow, 40)
        return (style.color, max(22, style.size))
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
        let selectedAlpha = stamp.color.cgColor.alpha

        // A soft outer pass gives the mark a slightly soaked highlighter edge.
        context.setStrokeColor(stamp.color.withAlphaComponent(selectedAlpha * 0.10).cgColor)
        context.setLineWidth(lineWidth * 1.30)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: middle)
        context.addLine(to: end)
        context.strokePath()

        // The main pass stays translucent so overlapping parts become naturally darker.
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

        // PencilKit stays underneath. The check layer only intercepts touches while
        // the custom tool is active, so the system tools remain completely native.
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
