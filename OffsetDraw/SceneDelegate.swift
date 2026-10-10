import UIKit

final class DrawingNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
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

        do {
            let worksStore = try DrawingDocumentStore()
            let delayStore = try DrawingDocumentStore(
                documentsDirectoryName: "DelayLabDrawings",
                thumbnailsDirectoryName: "DelayLabThumbnails"
            )

            let delayDocument = try loadOrCreateDelayDocument(in: delayStore)
            let delayController = ViewController(store: delayStore, document: delayDocument)
            delayController.title = "Delay"
            let delayNavigation = DrawingNavigationController(rootViewController: delayController)
            delayNavigation.tabBarItem = UITabBarItem(
                title: "Delay",
                image: UIImage(systemName: "scribble.variable"),
                selectedImage: UIImage(systemName: "scribble.variable")
            )

            let canvasController = CanvasExperimentViewController()
            let canvasNavigation = UINavigationController(rootViewController: canvasController)
            canvasNavigation.tabBarItem = UITabBarItem(
                title: "Canvas",
                image: UIImage(systemName: "square.on.square"),
                selectedImage: UIImage(systemName: "square.on.square.fill")
            )

            let worksController = HomeViewController(store: worksStore)
            let worksNavigation = DrawingNavigationController(rootViewController: worksController)
            worksNavigation.tabBarItem = UITabBarItem(
                title: "Works",
                image: UIImage(systemName: "rectangle.grid.2x2"),
                selectedImage: UIImage(systemName: "rectangle.grid.2x2.fill")
            )

            let rollerballNavigation = UINavigationController(rootViewController: RollerballViewController())
            rollerballNavigation.overrideUserInterfaceStyle = .light
            rollerballNavigation.tabBarItem = UITabBarItem(
                title: "走珠笔", image: UIImage(systemName: "pencil.tip"), selectedImage: UIImage(systemName: "pencil.tip")
            )

            let geometryNavigation = UINavigationController(rootViewController: GeometryLabViewController())
            geometryNavigation.overrideUserInterfaceStyle = .light
            geometryNavigation.tabBarItem = UITabBarItem(
                title: "Geometry",
                image: UIImage(systemName: "point.3.connected.trianglepath.dotted"),
                selectedImage: UIImage(systemName: "point.3.connected.trianglepath.dotted")
            )

            let tabBarController = UITabBarController()
            tabBarController.viewControllers = [rollerballNavigation, geometryNavigation, delayNavigation, canvasNavigation, worksNavigation]
            tabBarController.selectedIndex = 0

            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = tabBarController
            window.makeKeyAndVisible()
            self.window = window
        } catch {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .systemBackground

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "OffsetDraw could not open its local workspace."
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            fallback.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: fallback.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: fallback.view.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: fallback.view.centerYAnchor)
            ])

            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = fallback
            window.makeKeyAndVisible()
            self.window = window
        }
    }

    private func loadOrCreateDelayDocument(in store: DrawingDocumentStore) throws -> DrawingDocument {
        if let existing = store.listDocuments().first {
            return try store.loadDocument(id: existing.id)
        }

        let document = try store.createDocument()
        try store.renameDocument(id: document.id, title: "Delay Lab")
        return try store.loadDocument(id: document.id)
    }
}

// MARK: - Geometry Lab

private enum GeometryLabLayer: Int, CaseIterable {
    case mainEvents
    case samples
    case resampled
    case polyline
    case spline
    case resampledSpline
    case robust

    var title: String {
        switch self {
        case .mainEvents: "UIKit"
        case .samples: "Samples"
        case .resampled: "Resampled"
        case .polyline: "Polyline"
        case .spline: "Raw Spline"
        case .resampledSpline: "Re Spline"
        case .robust: "Robust"
        }
    }

    var color: UIColor {
        switch self {
        case .mainEvents: .systemRed
        case .samples: .label
        case .resampled: .systemTeal
        case .polyline: .systemOrange
        case .spline: .systemBlue
        case .resampledSpline: .systemPurple
        case .robust: .systemGreen
        }
    }

    var isVisibleByDefault: Bool {
        self != .robust
    }
}

final class GeometryLabViewController: UIViewController {
    private let canvas = GeometryLabCanvasView()
    private let summary = UILabel()
    private var layerButtons: [GeometryLabLayer: UIButton] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Geometry Lab"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear", style: .plain, target: self, action: #selector(clear)
        )

        let explanation = UILabel()
        explanation.font = .systemFont(ofSize: 13, weight: .regular)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0
        explanation.text = "黑点 = 原始真实采样；青圈 = 沿真实折线每 3 pt 重新等距采样。蓝线直接拟合原始点，紫线拟合等距点。无 predicted touches。"

        let inputControls = makeControlRow([
            .mainEvents, .samples, .resampled
        ])
        let pathControls = makeControlRow([
            .polyline, .spline, .resampledSpline, .robust
        ])
        let controls = UIStackView(arrangedSubviews: [inputControls, pathControls])
        controls.axis = .vertical
        controls.spacing = 6

        summary.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        summary.textColor = .secondaryLabel
        summary.numberOfLines = 0
        summary.text = "UIKit 批次 0 · 原始采样 0 · 等距点 0 · 3.0 pt"

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.layer.cornerRadius = 16
        canvas.clipsToBounds = true
        canvas.onStats = { [weak self] batches, extras, samples, resampled, removed in
            guard let self else { return }
            let average = batches > 0 ? Double(samples) / Double(batches) : 0
            self.summary.text = String(
                format: "UIKit 批次 %d · 额外 coalesced %d · 原始采样 %d · %.1f 点/批\n等距点 %d · 间距 3.0 pt · Robust 剔除 %d",
                batches, extras, samples, average, resampled, removed
            )
        }

        let stack = UIStackView(arrangedSubviews: [explanation, controls, summary, canvas])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            inputControls.heightAnchor.constraint(equalToConstant: 36),
            pathControls.heightAnchor.constraint(equalToConstant: 36)
        ])
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func makeControlRow(_ layers: [GeometryLabLayer]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        for layer in layers {
            let button = makeLayerButton(layer)
            layerButtons[layer] = button
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeLayerButton(_ layer: GeometryLabLayer) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = layer.rawValue
        button.setTitle(layer.title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.layer.cornerRadius = 9
        button.layer.borderWidth = 1
        button.layer.borderColor = layer.color.withAlphaComponent(0.35).cgColor
        button.isSelected = layer.isVisibleByDefault
        button.addTarget(self, action: #selector(toggleLayer(_:)), for: .touchUpInside)
        refresh(button, layer: layer)
        return button
    }

    private func refresh(_ button: UIButton, layer: GeometryLabLayer) {
        button.backgroundColor = button.isSelected ? layer.color.withAlphaComponent(0.12) : .clear
        button.setTitleColor(button.isSelected ? layer.color : .tertiaryLabel, for: .normal)
        button.layer.borderColor = (button.isSelected ? layer.color.withAlphaComponent(0.45) : UIColor.separator).cgColor
    }

    @objc private func toggleLayer(_ sender: UIButton) {
        guard let layer = GeometryLabLayer(rawValue: sender.tag) else { return }
        sender.isSelected.toggle()
        refresh(sender, layer: layer)
        canvas.setLayer(layer, visible: sender.isSelected)
    }

    @objc private func clear() {
        canvas.clear()
    }
}

private final class GeometryLabCanvasView: UIView {
    var onStats: ((Int, Int, Int, Int, Int) -> Void)?

    private let resampleSpacing: CGFloat = 3
    private var points: [CGPoint] = []
    private var sampleMarkers: [CGPoint] = []
    private var mainEventMarkers: [CGPoint] = []
    private var moveBatchCount = 0
    private var moveSampleCount = 0
    private var moveExtraSampleCount = 0
    private var visibleLayers = Set(GeometryLabLayer.allCases.filter(\.isVisibleByDefault))

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .systemBackground
        isOpaque = true
        isMultipleTouchEnabled = false
        accessibilityLabel = "Geometry Lab drawing canvas"
    }

    func setLayer(_ layer: GeometryLabLayer, visible: Bool) {
        if visible { visibleLayers.insert(layer) }
        else { visibleLayers.remove(layer) }
        setNeedsDisplay()
    }

    func clear() {
        resetStroke()
        onStats?(0, 0, 0, 0, 0)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetStroke()
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        appendGeometryPoint(point)
        mainEventMarkers.append(point)
        update()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        var batch = event?.coalescedTouches(for: touch) ?? [touch]
        let mainPoint = touch.location(in: self)
        let containsMain = batch.contains { sample in
            abs(sample.timestamp - touch.timestamp) < 0.000_001
                && distance(sample.location(in: self), mainPoint) < 0.01
        }
        if !containsMain {
            batch.append(touch)
        }

        moveBatchCount += 1
        moveSampleCount += batch.count
        moveExtraSampleCount += max(0, batch.count - 1)

        for sample in batch {
            let point = sample.location(in: self)
            sampleMarkers.append(point)
            appendGeometryPoint(point)
        }
        mainEventMarkers.append(mainPoint)
        update()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        appendGeometryPoint(point)
        mainEventMarkers.append(point)
        update()
    }

    private func resetStroke() {
        points.removeAll(keepingCapacity: true)
        sampleMarkers.removeAll(keepingCapacity: true)
        mainEventMarkers.removeAll(keepingCapacity: true)
        moveBatchCount = 0
        moveSampleCount = 0
        moveExtraSampleCount = 0
    }

    private func appendGeometryPoint(_ point: CGPoint) {
        if let last = points.last, distance(last, point) < 0.001 { return }
        points.append(point)
    }

    private func update() {
        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        let result = robustResult(points)
        onStats?(
            moveBatchCount,
            moveExtraSampleCount,
            moveSampleCount,
            resampled.count,
            result.removed.count
        )
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.systemBackground.setFill()
        context.fill(bounds)
        drawGrid(in: context)

        guard !points.isEmpty else {
            drawHint(in: context)
            return
        }

        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        let robust = robustResult(points)

        if visibleLayers.contains(.polyline) {
            GeometryLabLayer.polyline.color.withAlphaComponent(0.5).setStroke()
            let path = polylinePath(points)
            path.lineWidth = 1
            path.stroke()
        }

        if visibleLayers.contains(.spline) {
            GeometryLabLayer.spline.color.setStroke()
            let path = splinePath(points)
            path.lineWidth = 1.8
            path.stroke()
        }

        if visibleLayers.contains(.resampledSpline) {
            GeometryLabLayer.resampledSpline.color.setStroke()
            let path = splinePath(resampled)
            path.lineWidth = 2.4
            path.stroke()
        }

        if visibleLayers.contains(.robust) {
            GeometryLabLayer.robust.color.setStroke()
            let path = splinePath(robust.points)
            path.lineWidth = 3
            path.stroke()
            drawRemoved(robust.removed, in: context)
        }

        if visibleLayers.contains(.resampled) {
            drawResampled(resampled, in: context)
        }
        if visibleLayers.contains(.samples) {
            drawSamples(in: context)
        }
        if visibleLayers.contains(.mainEvents) {
            drawMainEvents(in: context)
        }
    }

    private func drawGrid(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(UIColor.separator.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.5)
        let spacing: CGFloat = 24
        var x: CGFloat = 0
        while x <= bounds.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawHint(in context: CGContext) {
        let text = "慢画再快画：比较黑色原始点与青色 3 pt 等距点"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawSamples(in context: CGContext) {
        context.saveGState()
        context.setFillColor(GeometryLabLayer.samples.color.withAlphaComponent(0.68).cgColor)
        for point in sampleMarkers {
            let r: CGFloat = 1.6
            context.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }

    private func drawResampled(_ resampled: [CGPoint], in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(GeometryLabLayer.resampled.color.cgColor)
        context.setLineWidth(1.4)
        for point in resampled {
            let r: CGFloat = 3.2
            context.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }

    private func drawMainEvents(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(GeometryLabLayer.mainEvents.color.cgColor)
        context.setLineWidth(2)
        for point in mainEventMarkers {
            let r: CGFloat = 5.2
            context.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }

    private func drawRemoved(_ removed: [CGPoint], in context: CGContext) {
        guard !removed.isEmpty else { return }
        context.saveGState()
        context.setStrokeColor(UIColor.systemPink.cgColor)
        context.setLineWidth(1.5)
        for point in removed {
            let r: CGFloat = 4
            context.move(to: CGPoint(x: point.x - r, y: point.y - r))
            context.addLine(to: CGPoint(x: point.x + r, y: point.y + r))
            context.move(to: CGPoint(x: point.x + r, y: point.y - r))
            context.addLine(to: CGPoint(x: point.x - r, y: point.y + r))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func polylinePath(_ input: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = input.first else { return path }
        path.move(to: first)
        for point in input.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// Interpolating Catmull-Rom spline converted into cubic Bezier segments.
    /// The exact same curve builder is used for raw and spatially resampled points so the
    /// experiment isolates only the point distribution.
    private func splinePath(_ input: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = input.first else { return path }
        path.move(to: first)
        guard input.count > 1 else { return path }
        if input.count == 2 {
            path.addLine(to: input[1])
            return path
        }

        for index in 0..<(input.count - 1) {
            let p0 = input[max(0, index - 1)]
            let p1 = input[index]
            let p2 = input[index + 1]
            let p3 = input[min(input.count - 1, index + 2)]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, controlPoint1: control1, controlPoint2: control2)
        }
        return path
    }

    /// Converts time-spaced Pencil samples into approximately equal arc-length samples.
    /// It does not predict the future and it does not move the source path: every generated
    /// point lies on an already observed raw polyline segment.
    private func spatiallyResampled(_ input: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard input.count > 1, spacing > 0 else { return input }

        var result: [CGPoint] = [input[0]]
        var distanceSinceLastOutput: CGFloat = 0

        for index in 1..<input.count {
            var segmentStart = input[index - 1]
            let segmentEnd = input[index]
            var remainingLength = distance(segmentStart, segmentEnd)

            guard remainingLength > 0.001 else { continue }

            while distanceSinceLastOutput + remainingLength >= spacing {
                let needed = spacing - distanceSinceLastOutput
                let t = needed / remainingLength
                let generated = CGPoint(
                    x: segmentStart.x + (segmentEnd.x - segmentStart.x) * t,
                    y: segmentStart.y + (segmentEnd.y - segmentStart.y) * t
                )
                result.append(generated)
                segmentStart = generated
                remainingLength = distance(segmentStart, segmentEnd)
                distanceSinceLastOutput = 0
            }

            distanceSinceLastOutput += remainingLength
        }

        if let final = input.last,
           let lastOutput = result.last,
           distance(lastOutput, final) > 0.5 {
            result.append(final)
        }

        return result
    }

    /// First experiment: reject only isolated "out and back" spikes. A candidate must deviate
    /// strongly from its immediate chord while the motion before and after still points roughly
    /// the same way. Intentional corners therefore tend to survive.
    private func robustResult(_ input: [CGPoint]) -> (points: [CGPoint], removed: [CGPoint]) {
        guard input.count >= 5 else { return (input, []) }
        var keep = Array(repeating: true, count: input.count)
        var removed: [CGPoint] = []

        for index in 2..<(input.count - 2) {
            let before = input[index - 2]
            let previous = input[index - 1]
            let candidate = input[index]
            let next = input[index + 1]
            let after = input[index + 2]

            let incoming = distance(previous, candidate)
            let outgoing = distance(candidate, next)
            let chord = distance(previous, next)
            guard incoming > 0.01, outgoing > 0.01 else { continue }

            let detour = (incoming + outgoing) / max(chord, 0.01)
            let deviation = distanceToSegment(candidate, a: previous, b: next)
            let localStep = max(0.5, (distance(before, previous) + distance(next, after)) * 0.5)
            let surroundingAlignment = directionCosine(from: before, to: previous, andFrom: next, to: after)

            let looksLikeSingleSpike = detour > 1.8
                && deviation > max(1.2, localStep * 1.35)
                && surroundingAlignment > 0.45
                && max(incoming, outgoing) < 24

            if looksLikeSingleSpike {
                keep[index] = false
                removed.append(candidate)
            }
        }

        let corrected = zip(input, keep).compactMap { point, shouldKeep in shouldKeep ? point : nil }
        return (corrected.count >= 2 ? corrected : input, removed)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private func directionCosine(from a: CGPoint, to b: CGPoint, andFrom c: CGPoint, to d: CGPoint) -> CGFloat {
        let ux = b.x - a.x
        let uy = b.y - a.y
        let vx = d.x - c.x
        let vy = d.y - c.y
        let ul = hypot(ux, uy)
        let vl = hypot(vx, vy)
        guard ul > 0.001, vl > 0.001 else { return -1 }
        return (ux * vx + uy * vy) / (ul * vl)
    }

    private func distanceToSegment(_ point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0.0001 else { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * vx + (point.y - a.y) * vy) / lengthSquared))
        let projection = CGPoint(x: a.x + vx * t, y: a.y + vy * t)
        return distance(point, projection)
    }
}
