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
                title: "走珠笔",
                image: UIImage(systemName: "pencil.tip"),
                selectedImage: UIImage(systemName: "pencil.tip")
            )

            let geometryNavigation = UINavigationController(rootViewController: GeometryLabViewController())
            geometryNavigation.overrideUserInterfaceStyle = .light
            geometryNavigation.tabBarItem = UITabBarItem(
                title: "Geometry",
                image: UIImage(systemName: "point.3.connected.trianglepath.dotted"),
                selectedImage: UIImage(systemName: "point.3.connected.trianglepath.dotted")
            )

            let tabBarController = UITabBarController()
            tabBarController.viewControllers = [
                rollerballNavigation,
                geometryNavigation,
                delayNavigation,
                canvasNavigation,
                worksNavigation
            ]
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

final class GeometryLabViewController: UIViewController {
    private let canvas = GeometryComparisonCanvasView()
    private let summary = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Geometry Lab"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(clear)
        )

        let explanation = UILabel()
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0
        explanation.text = "只在第一格画一笔。下面两格自动使用同一份真实输入：先比较点分布，再单独比较两条拟合曲线。"

        summary.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        summary.textColor = .secondaryLabel
        summary.numberOfLines = 0
        summary.text = "真实点 0 · 等距点 0 · UIKit 批次 0"

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onStats = { [weak self] rawCount, resampledCount, batches, samplesPerBatch in
            self?.summary.text = String(
                format: "真实点 %d · 等距点 %d · UIKit 批次 %d · %.1f 点/批",
                rawCount,
                resampledCount,
                batches,
                samplesPerBatch
            )
        }

        let stack = UIStackView(arrangedSubviews: [explanation, summary, canvas])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @objc private func clear() {
        canvas.clear()
    }
}

private final class GeometryComparisonCanvasView: UIView {
    var onStats: ((Int, Int, Int, Double) -> Void)?

    private let resampleSpacing: CGFloat = 3
    private let panelGap: CGFloat = 10
    private let panelInset: CGFloat = 8
    private let panelTitleHeight: CGFloat = 28

    /// All geometry is stored in local coordinates of the first panel.
    private var points: [CGPoint] = []
    private var moveBatchCount = 0
    private var moveSampleCount = 0
    private var acceptingStroke = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        accessibilityLabel = "Geometry comparison canvas"
    }

    func clear() {
        resetStroke()
        onStats?(0, 0, 0, 0)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let panels = panelRects()
        guard let rawPanel = panels.first else { return }

        let location = touch.location(in: self)
        guard rawPanel.contains(location) else {
            acceptingStroke = false
            return
        }

        resetStroke()
        acceptingStroke = true
        appendGeometryPoint(localPoint(from: location, in: rawPanel))
        updateStats()
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptingStroke,
              let touch = touches.first,
              let rawPanel = panelRects().first else {
            return
        }

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

        for sample in batch {
            appendGeometryPoint(localPoint(from: sample.location(in: self), in: rawPanel))
        }

        updateStats()
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard acceptingStroke,
              let touch = touches.first,
              let rawPanel = panelRects().first else {
            return
        }

        appendGeometryPoint(localPoint(from: touch.location(in: self), in: rawPanel))
        acceptingStroke = false
        updateStats()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        acceptingStroke = false
    }

    private func resetStroke() {
        points.removeAll(keepingCapacity: true)
        moveBatchCount = 0
        moveSampleCount = 0
        acceptingStroke = false
    }

    private func appendGeometryPoint(_ point: CGPoint) {
        if let last = points.last, distance(last, point) < 0.001 {
            return
        }
        points.append(point)
    }

    private func updateStats() {
        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        let average = moveBatchCount > 0
            ? Double(moveSampleCount) / Double(moveBatchCount)
            : 0
        onStats?(points.count, resampled.count, moveBatchCount, average)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let panels = panelRects()
        guard panels.count == 3 else { return }

        drawPanelBackground(panels[0], title: "1  RAW SAMPLES", subtitle: "真实采样点 · 在这里画")
        drawPanelBackground(panels[1], title: "2  RESAMPLED · 3 pt", subtitle: "沿真实折线重新等距取点")
        drawPanelBackground(panels[2], title: "3  CURVE COMPARE", subtitle: "蓝 = Raw spline · 紫 = Resampled spline")

        guard !points.isEmpty else {
            drawEmptyHint(in: panels[0])
            return
        }

        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        drawRawPanel(points, in: panels[0], context: context)
        drawResampledPanel(resampled, in: panels[1], context: context)
        drawCurvePanel(raw: points, resampled: resampled, in: panels[2], context: context)
    }

    private func panelRects() -> [CGRect] {
        let usableHeight = max(0, bounds.height - panelGap * 2)
        let height = usableHeight / 3
        guard height > 0 else { return [] }

        return (0..<3).map { index in
            CGRect(
                x: 0,
                y: CGFloat(index) * (height + panelGap),
                width: bounds.width,
                height: height
            )
        }
    }

    private func drawPanelBackground(_ panel: CGRect, title: String, subtitle: String) {
        let shape = UIBezierPath(roundedRect: panel, cornerRadius: 14)
        UIColor.systemBackground.setFill()
        shape.fill()

        UIColor.separator.withAlphaComponent(0.35).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel
        ]

        title.draw(
            at: CGPoint(x: panel.minX + 12, y: panel.minY + 7),
            withAttributes: titleAttributes
        )

        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        subtitle.draw(
            at: CGPoint(
                x: panel.maxX - subtitleSize.width - 12,
                y: panel.minY + 8
            ),
            withAttributes: subtitleAttributes
        )

        let dividerY = panel.minY + panelTitleHeight
        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: panel.minX, y: dividerY))
        divider.addLine(to: CGPoint(x: panel.maxX, y: dividerY))
        UIColor.separator.withAlphaComponent(0.28).setStroke()
        divider.lineWidth = 0.5
        divider.stroke()
    }

    private func drawRawPanel(_ input: [CGPoint], in panel: CGRect, context: CGContext) {
        withPanelClip(panel, context: context) {
            let mapped = input.map { displayPoint($0, in: panel) }

            UIColor.systemGray.withAlphaComponent(0.28).setStroke()
            let path = polylinePath(mapped)
            path.lineWidth = 0.8
            path.stroke()

            context.setFillColor(UIColor.label.withAlphaComponent(0.8).cgColor)
            for point in mapped {
                let radius: CGFloat = 1.8
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        }
    }

    private func drawResampledPanel(_ input: [CGPoint], in panel: CGRect, context: CGContext) {
        withPanelClip(panel, context: context) {
            let mapped = input.map { displayPoint($0, in: panel) }

            UIColor.systemTeal.withAlphaComponent(0.22).setStroke()
            let path = polylinePath(mapped)
            path.lineWidth = 0.8
            path.stroke()

            context.setStrokeColor(UIColor.systemTeal.cgColor)
            context.setLineWidth(1.3)
            for point in mapped {
                let radius: CGFloat = 3
                context.strokeEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        }
    }

    private func drawCurvePanel(
        raw: [CGPoint],
        resampled: [CGPoint],
        in panel: CGRect,
        context: CGContext
    ) {
        withPanelClip(panel, context: context) {
            let mappedRaw = raw.map { displayPoint($0, in: panel) }
            let mappedResampled = resampled.map { displayPoint($0, in: panel) }

            UIColor.systemBlue.setStroke()
            let rawPath = splinePath(mappedRaw)
            rawPath.lineWidth = 2.2
            rawPath.stroke()

            UIColor.systemPurple.setStroke()
            let resampledPath = splinePath(mappedResampled)
            resampledPath.lineWidth = 2.2
            resampledPath.stroke()
        }
    }

    private func withPanelClip(
        _ panel: CGRect,
        context: CGContext,
        drawing: () -> Void
    ) {
        context.saveGState()
        let content = panelContentRect(panel)
        context.addPath(UIBezierPath(rect: content).cgPath)
        context.clip()
        drawing()
        context.restoreGState()
    }

    private func drawEmptyHint(in panel: CGRect) {
        let text = "在这里用 Pencil 画一笔"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        let content = panelContentRect(panel)
        text.draw(
            at: CGPoint(
                x: content.midX - size.width / 2,
                y: content.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func panelContentRect(_ panel: CGRect) -> CGRect {
        CGRect(
            x: panel.minX + panelInset,
            y: panel.minY + panelTitleHeight + panelInset,
            width: max(0, panel.width - panelInset * 2),
            height: max(0, panel.height - panelTitleHeight - panelInset * 2)
        )
    }

    /// Stored points use local coordinates of the first panel's drawable content region.
    private func localPoint(from location: CGPoint, in rawPanel: CGRect) -> CGPoint {
        let content = panelContentRect(rawPanel)
        return CGPoint(
            x: location.x - content.minX,
            y: location.y - content.minY
        )
    }

    private func displayPoint(_ point: CGPoint, in panel: CGRect) -> CGPoint {
        let content = panelContentRect(panel)
        return CGPoint(
            x: content.minX + point.x,
            y: content.minY + point.y
        )
    }

    private func polylinePath(_ input: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = input.first else { return path }
        path.move(to: first)
        for point in input.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// Interpolating Catmull-Rom spline converted into cubic Bezier segments.
    /// The exact same curve builder is used for both inputs so this comparison changes only
    /// the distribution of points, not the curve algorithm.
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
    /// Every generated point stays on an already observed raw polyline segment.
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

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
