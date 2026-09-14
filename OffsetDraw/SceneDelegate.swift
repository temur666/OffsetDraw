import UIKit
import PencilKit

@available(iOS 18.0, *)
private final class ToolPickerCanvasView: PKCanvasView {
    var passesTouchesThrough = false

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !passesTouchesThrough else {
            return false
        }
        return super.point(inside: point, with: event)
    }
}

@available(iOS 18.0, *)
private final class OffsetToolPickerBridge: NSObject, PKToolPickerObserver {
    private static let offsetIdentifier = "com.tiemuernow.OffsetDraw.tool.offset"

    private weak var drawingCanvas: DrawingCanvasView?
    private let pencilCanvas = ToolPickerCanvasView()
    private let offsetItem: PKToolPickerCustomItem
    private let toolPicker: PKToolPicker

    init(drawingCanvas: DrawingCanvasView) {
        self.drawingCanvas = drawingCanvas

        var configuration = PKToolPickerCustomItem.Configuration(
            identifier: Self.offsetIdentifier,
            name: "Offset"
        )
        configuration.allowsColorSelection = true
        configuration.defaultColor = drawingCanvas.brush.color
        configuration.defaultWidth = drawingCanvas.brush.lineWidth
        configuration.widthVariants = [
            3: Self.widthVariantImage(lineWidth: 2),
            6: Self.widthVariantImage(lineWidth: 4),
            12: Self.widthVariantImage(lineWidth: 7)
        ]
        configuration.imageProvider = { item in
            Self.offsetToolImage(color: item.color)
        }

        let offsetItem = PKToolPickerCustomItem(configuration: configuration)
        self.offsetItem = offsetItem

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
            offsetItem,
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

        drawingCanvas.addSubview(pencilCanvas)
        NSLayoutConstraint.activate([
            pencilCanvas.leadingAnchor.constraint(equalTo: drawingCanvas.leadingAnchor),
            pencilCanvas.trailingAnchor.constraint(equalTo: drawingCanvas.trailingAnchor),
            pencilCanvas.topAnchor.constraint(equalTo: drawingCanvas.topAnchor),
            pencilCanvas.bottomAnchor.constraint(equalTo: drawingCanvas.bottomAnchor)
        ])

        toolPicker.stateAutosaveName = nil
        toolPicker.addObserver(pencilCanvas)
        toolPicker.addObserver(self)
        toolPicker.selectedToolItem = offsetItem
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

        // A newly pushed drawing controller can finish its responder transition
        // one run loop after UINavigationController reports didShow. Reassert the
        // picker once the transition is fully settled so it cannot remain hidden.
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
        let usesOffsetTool = toolPicker.selectedToolItem.identifier == Self.offsetIdentifier
        pencilCanvas.passesTouchesThrough = usesOffsetTool

        guard usesOffsetTool, var brush = drawingCanvas?.brush else {
            return
        }

        brush.color = offsetItem.color
        brush.lineWidth = offsetItem.width
        brush.blendMode = .normal
        drawingCanvas?.brush = brush
    }

    private static func offsetToolImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 72, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setFillColor(color.cgColor)
            cg.setLineCap(.round)
            cg.setLineWidth(12)
            cg.move(to: CGPoint(x: 45, y: 28))
            cg.addLine(to: CGPoint(x: 28, y: 128))
            cg.strokePath()
            cg.fillEllipse(in: CGRect(x: 15, y: 132, width: 24, height: 24))
        }
    }

    private static func widthVariantImage(lineWidth: CGFloat) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.label.cgColor)
            cg.setLineCap(.round)
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: 8, y: 22))
            cg.addLine(to: CGPoint(x: 36, y: 22))
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

        if let existingBridge = toolPickerBridge as? OffsetToolPickerBridge {
            existingBridge.deactivate()
            toolPickerBridge = nil
        }

        guard viewController is ViewController,
              let rootView = viewController?.view,
              let drawingCanvas = findDrawingCanvas(in: rootView) else {
            return
        }

        let bridge = OffsetToolPickerBridge(drawingCanvas: drawingCanvas)
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
