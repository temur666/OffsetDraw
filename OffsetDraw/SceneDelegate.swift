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
    private let toleranceLabel = UILabel()
    private let toleranceSlider = UISlider()

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
        explanation.text = "第一格是真实采样；第二格是当前 5 点平滑；第三格把平滑轨迹压缩成少量锚点，再用 cubic Bézier 重建。拖动容差，看锚点怎样减少。"

        summary.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        summary.textColor = .secondaryLabel
        summary.numberOfLines = 0
        summary.text = "真实点 0 · 平滑点 0 · Fit 锚点 0 · Bezier 段 0"

        toleranceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        toleranceLabel.textColor = .label
        toleranceLabel.setContentHuggingPriority(.required, for: .horizontal)

        toleranceSlider.minimumValue = 0.5
        toleranceSlider.maximumValue = 8.0
        toleranceSlider.value = 2.5
        toleranceSlider.addTarget(self, action: #selector(toleranceChanged(_:)), for: .valueChanged)
        updateToleranceLabel()

        let toleranceRow = UIStackView(arrangedSubviews: [toleranceLabel, toleranceSlider])
        toleranceRow.axis = .horizontal
        toleranceRow.alignment = .center
        toleranceRow.spacing = 12

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.fitTolerance = CGFloat(toleranceSlider.value)
        canvas.onStats = { [weak self] rawCount, smoothCount, anchorCount, segmentCount, batches, samplesPerBatch in
            self?.summary.text = String(
                format: "真实点 %d · 平滑点 %d · Fit 锚点 %d · Bezier 段 %d\nUIKit 批次 %d · %.1f 点/批",
                rawCount,
                smoothCount,
                anchorCount,
                segmentCount,
                batches,
                samplesPerBatch
            )
        }

        let stack = UIStackView(arrangedSubviews: [explanation, summary, toleranceRow, canvas])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            toleranceRow.heightAnchor.constraint(equalToConstant: 30)
        ])
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @objc private func toleranceChanged(_ sender: UISlider) {
        canvas.fitTolerance = CGFloat(sender.value)
        updateToleranceLabel()
    }

    private func updateToleranceLabel() {
        toleranceLabel.text = String(format: "Fit tolerance  %.1f pt", toleranceSlider.value)
    }

    @objc private func clear() {
        canvas.clear()
    }
}

private struct GeometryBezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private final class GeometryComparisonCanvasView: UIView {
    var onStats: ((Int, Int, Int, Int, Int, Double) -> Void)?

    var fitTolerance: CGFloat = 2.5 {
        didSet {
            fitTolerance = max(0.1, fitTolerance)
            updateStats()
            setNeedsDisplay()
        }
    }

    private let resampleSpacing: CGFloat = 3
    private let panelGap: CGFloat = 10
    private let panelInset: CGFloat = 8
    private let panelTitleHeight: CGFloat = 28

    /// All geometry is stored in local coordinates of the first panel's drawable area.
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
        onStats?(0, 0, 0, 0, 0, 0)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let rawPanel = panelRects().first else {
            return
        }

        let location = touch.location(in: self)
        guard panelContentRect(rawPanel).contains(location) else {
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

    private func processedGeometry() -> (
        resampled: [CGPoint],
        smoothed: [CGPoint],
        anchors: [CGPoint],
        segments: [GeometryBezierSegment]
    ) {
        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        let smoothed = fivePointSmoothed(resampled)
        let anchors = simplifiedAnchors(smoothed, tolerance: fitTolerance)
        let segments = bezierSegments(from: anchors)
        return (resampled, smoothed, anchors, segments)
    }

    private func updateStats() {
        let processed = processedGeometry()
        let average = moveBatchCount > 0
            ? Double(moveSampleCount) / Double(moveBatchCount)
            : 0

        onStats?(
            points.count,
            processed.smoothed.count,
            processed.anchors.count,
            processed.segments.count,
            moveBatchCount,
            average
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let panels = panelRects()
        guard panels.count == 3 else { return }

        drawPanelBackground(
            panels[0],
            title: "1  RAW SAMPLES",
            subtitle: "真实 coalesced 点 · 在这里画"
        )
        drawPanelBackground(
            panels[1],
            title: "2  SMOOTH · 5 POINTS",
            subtitle: "3 pt 等距 → 1-2-3-2-1 局部平均"
        )
        drawPanelBackground(
            panels[2],
            title: String(format: "3  BEZIER FIT · ε %.1f pt", fitTolerance),
            subtitle: "橙 = 锚点 · 蓝紫 = 控制点 · 绿 = 拟合曲线"
        )

        guard !points.isEmpty else {
            drawEmptyHint(in: panels[0])
            return
        }

        let processed = processedGeometry()
        drawRawPanel(points, in: panels[0], context: context)
        drawSmoothPanel(
            original: processed.resampled,
            smoothed: processed.smoothed,
            in: panels[1],
            context: context
        )
        drawBezierFitPanel(
            smoothed: processed.smoothed,
            anchors: processed.anchors,
            segments: processed.segments,
            in: panels[2],
            context: context
        )
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

            context.setFillColor(UIColor.label.withAlphaComponent(0.82).cgColor)
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

    private func drawSmoothPanel(
        original: [CGPoint],
        smoothed: [CGPoint],
        in panel: CGRect,
        context: CGContext
    ) {
        withPanelClip(panel, context: context) {
            let mappedOriginal = original.map { displayPoint($0, in: panel) }
            let mappedSmoothed = smoothed.map { displayPoint($0, in: panel) }

            context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(0.9)
            for point in mappedOriginal {
                let radius: CGFloat = 2.0
                context.strokeEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.22).cgColor)
            context.setLineWidth(0.6)
            for (before, after) in zip(mappedOriginal, mappedSmoothed) {
                context.move(to: before)
                context.addLine(to: after)
            }
            context.strokePath()

            UIColor.systemPurple.setStroke()
            let path = splinePath(mappedSmoothed)
            path.lineWidth = 2.5
            path.stroke()

            context.setFillColor(UIColor.systemPink.withAlphaComponent(0.72).cgColor)
            for point in mappedSmoothed {
                let radius: CGFloat = 1.4
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

    private func drawBezierFitPanel(
        smoothed: [CGPoint],
        anchors: [CGPoint],
        segments: [GeometryBezierSegment],
        in panel: CGRect,
        context: CGContext
    ) {
        withPanelClip(panel, context: context) {
            let mappedSmoothed = smoothed.map { displayPoint($0, in: panel) }

            UIColor.systemGray.withAlphaComponent(0.18).setStroke()
            let sourcePath = polylinePath(mappedSmoothed)
            sourcePath.lineWidth = 0.8
            sourcePath.stroke()

            context.saveGState()
            context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.48).cgColor)
            context.setLineWidth(0.8)
            context.setLineDash(phase: 0, lengths: [3, 3])
            for segment in segments {
                let start = displayPoint(segment.start, in: panel)
                let c1 = displayPoint(segment.control1, in: panel)
                let c2 = displayPoint(segment.control2, in: panel)
                let end = displayPoint(segment.end, in: panel)
                context.move(to: start)
                context.addLine(to: c1)
                context.move(to: end)
                context.addLine(to: c2)
            }
            context.strokePath()
            context.restoreGState()

            UIColor.systemGreen.setStroke()
            let fittedPath = UIBezierPath()
            if let first = segments.first {
                fittedPath.move(to: displayPoint(first.start, in: panel))
                for segment in segments {
                    fittedPath.addCurve(
                        to: displayPoint(segment.end, in: panel),
                        controlPoint1: displayPoint(segment.control1, in: panel),
                        controlPoint2: displayPoint(segment.control2, in: panel)
                    )
                }
            } else if let firstAnchor = anchors.first {
                fittedPath.move(to: displayPoint(firstAnchor, in: panel))
            }
            fittedPath.lineWidth = 3
            fittedPath.stroke()

            context.setFillColor(UIColor.systemOrange.cgColor)
            for anchor in anchors {
                let point = displayPoint(anchor, in: panel)
                let radius: CGFloat = 3.2
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            context.setFillColor(UIColor.systemIndigo.withAlphaComponent(0.82).cgColor)
            for segment in segments {
                for control in [segment.control1, segment.control2] {
                    let point = displayPoint(control, in: panel)
                    let radius: CGFloat = 2.3
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
    /// This still passes through every supplied point and is used only for the smoothing panel.
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

    /// Local low-pass experiment. The first and last point stay fixed.
    private func fivePointSmoothed(_ input: [CGPoint]) -> [CGPoint] {
        guard input.count >= 3 else { return input }
        let kernel: [CGFloat] = [1, 2, 3, 2, 1]
        var result: [CGPoint] = []
        result.reserveCapacity(input.count)

        for index in input.indices {
            if index == input.startIndex || index == input.index(before: input.endIndex) {
                result.append(input[index])
                continue
            }

            var weightedX: CGFloat = 0
            var weightedY: CGFloat = 0
            var totalWeight: CGFloat = 0

            for offset in -2...2 {
                let candidate = index + offset
                guard input.indices.contains(candidate) else { continue }
                let weight = kernel[offset + 2]
                weightedX += input[candidate].x * weight
                weightedY += input[candidate].y * weight
                totalWeight += weight
            }

            result.append(
                CGPoint(
                    x: weightedX / totalWeight,
                    y: weightedY / totalWeight
                )
            )
        }

        return result
    }

    /// Ramer-Douglas-Peucker simplification: keep only points whose removal would exceed the
    /// requested error tolerance. This is the experiment's "lower the degrees of freedom" step.
    private func simplifiedAnchors(_ input: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard input.count > 2 else { return input }

        var maxDistance: CGFloat = 0
        var splitIndex = 0
        let first = input[0]
        let last = input[input.count - 1]

        for index in 1..<(input.count - 1) {
            let deviation = distanceToSegment(input[index], a: first, b: last)
            if deviation > maxDistance {
                maxDistance = deviation
                splitIndex = index
            }
        }

        guard maxDistance > tolerance, splitIndex > 0 else {
            return [first, last]
        }

        let left = simplifiedAnchors(Array(input[0...splitIndex]), tolerance: tolerance)
        let right = simplifiedAnchors(Array(input[splitIndex..<input.count]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    /// Turn the sparse anchors into cubic Bezier segments. Tangents are estimated from adjacent
    /// anchors; handle length is tied to each segment so sparse anchors do not create huge overshoot.
    private func bezierSegments(from anchors: [CGPoint]) -> [GeometryBezierSegment] {
        guard anchors.count > 1 else { return [] }
        var result: [GeometryBezierSegment] = []
        result.reserveCapacity(anchors.count - 1)

        for index in 0..<(anchors.count - 1) {
            let p0 = anchors[max(0, index - 1)]
            let p1 = anchors[index]
            let p2 = anchors[index + 1]
            let p3 = anchors[min(anchors.count - 1, index + 2)]

            let segmentLength = distance(p1, p2)
            let tangent1 = unitVector(from: p0, to: p2)
            let tangent2 = unitVector(from: p1, to: p3)
            let handleLength = segmentLength / 3

            let control1 = CGPoint(
                x: p1.x + tangent1.dx * handleLength,
                y: p1.y + tangent1.dy * handleLength
            )
            let control2 = CGPoint(
                x: p2.x - tangent2.dx * handleLength,
                y: p2.y - tangent2.dy * handleLength
            )

            result.append(
                GeometryBezierSegment(
                    start: p1,
                    control1: control1,
                    control2: control2,
                    end: p2
                )
            )
        }

        return result
    }

    private func unitVector(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.0001 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private func distanceToSegment(_ point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0.0001 else { return distance(point, a) }

        let t = max(
            0,
            min(
                1,
                ((point.x - a.x) * vx + (point.y - a.y) * vy) / lengthSquared
            )
        )
        let projection = CGPoint(x: a.x + vx * t, y: a.y + vy * t)
        return distance(point, projection)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
