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

// MARK: - Stroke Pipeline Lab

private enum GeometryPipelineLayer: Int, CaseIterable {
    case raw
    case smooth
    case bezier
    case stroke

    var title: String {
        switch self {
        case .raw: return "RAW"
        case .smooth: return "SMOOTH"
        case .bezier: return "BEZIER"
        case .stroke: return "STROKE"
        }
    }

    var detail: String {
        switch self {
        case .raw: return "输入事实 · 只观察"
        case .smooth: return "重采样 + 局部平滑"
        case .bezier: return "实时拟合 + 尾部等待"
        case .stroke: return "中心线 → 矢量笔迹"
        }
    }
}

final class GeometryLabViewController: UIViewController {
    private let canvas = GeometryComparisonCanvasView()
    private let inspector = UIView()
    private let inspectorStack = UIStackView()
    private let inspectorTitle = UILabel()
    private let inspectorDetail = UILabel()
    private let rawStats = UILabel()

    private let resampleSlider = UISlider()
    private let resampleValue = UILabel()
    private let smoothSlider = UISlider()
    private let smoothValue = UILabel()

    private let toleranceSlider = UISlider()
    private let toleranceValue = UILabel()
    private let lookAheadControl = UISegmentedControl(items: ["0", "1", "2"])

    private let strokeWidthSlider = UISlider()
    private let strokeWidthValue = UILabel()
    private let centerlineSwitch = UISwitch()

    private let rawControls = UIStackView()
    private let smoothControls = UIStackView()
    private let bezierControls = UIStackView()
    private let strokeControls = UIStackView()

    private let rootStack = UIStackView()
    private var inspectorWidthConstraint: NSLayoutConstraint?
    private var selectedLayer: GeometryPipelineLayer = .smooth
    private var latestStats = GeometryStats()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stroke Pipeline"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(clear)
        )

        configureCanvas()
        configureInspector()
        configureLayout()
        selectLayer(.smooth)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        GeometryLabExperimentSupport.installSmoothExperiments(in: self)
        let useSideInspector = view.bounds.width >= 700
        let desiredAxis: NSLayoutConstraint.Axis = useSideInspector ? .horizontal : .vertical
        guard rootStack.axis != desiredAxis else { return }

        rootStack.axis = desiredAxis
        inspectorWidthConstraint?.isActive = useSideInspector
        inspector.layer.cornerRadius = useSideInspector ? 16 : 14
    }

    private func configureCanvas() {
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onLayerSelected = { [weak self] layer in
            self?.selectLayer(layer)
        }
        canvas.onStats = { [weak self] stats in
            self?.latestStats = stats
            self?.updateRawStats()
        }
    }

    private func configureInspector() {
        inspector.backgroundColor = .secondarySystemGroupedBackground
        inspector.layer.cornerRadius = 16
        inspector.layer.borderWidth = 0.5
        inspector.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor

        inspectorTitle.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        inspectorTitle.textColor = .label

        inspectorDetail.font = .systemFont(ofSize: 12, weight: .regular)
        inspectorDetail.textColor = .secondaryLabel
        inspectorDetail.numberOfLines = 0

        let hint = UILabel()
        hint.text = "点击右侧任一层，左侧只调整这一层。"
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabel
        hint.numberOfLines = 0

        configureRawControls()
        configureSmoothControls()
        configureBezierControls()
        configureStrokeControls()

        let divider = UIView()
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        inspectorStack.axis = .vertical
        inspectorStack.spacing = 14
        inspectorStack.translatesAutoresizingMaskIntoConstraints = false
        inspectorStack.addArrangedSubview(inspectorTitle)
        inspectorStack.addArrangedSubview(inspectorDetail)
        inspectorStack.addArrangedSubview(divider)
        inspectorStack.addArrangedSubview(rawControls)
        inspectorStack.addArrangedSubview(smoothControls)
        inspectorStack.addArrangedSubview(bezierControls)
        inspectorStack.addArrangedSubview(strokeControls)
        inspectorStack.addArrangedSubview(hint)
        inspectorStack.setCustomSpacing(6, after: inspectorTitle)

        inspector.addSubview(inspectorStack)
        NSLayoutConstraint.activate([
            inspectorStack.leadingAnchor.constraint(equalTo: inspector.leadingAnchor, constant: 16),
            inspectorStack.trailingAnchor.constraint(equalTo: inspector.trailingAnchor, constant: -16),
            inspectorStack.topAnchor.constraint(equalTo: inspector.topAnchor, constant: 16),
            inspectorStack.bottomAnchor.constraint(lessThanOrEqualTo: inspector.bottomAnchor, constant: -16)
        ])
    }

    private func configureRawControls() {
        rawControls.axis = .vertical
        rawControls.spacing = 8

        let label = sectionLabel("INPUT")
        rawStats.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        rawStats.textColor = .label
        rawStats.numberOfLines = 0

        let note = bodyLabel(
            "Raw 是输入事实，不提供修正参数。这里看真实 coalesced samples 和 UIKit 每批送来的点数。"
        )

        rawControls.addArrangedSubview(label)
        rawControls.addArrangedSubview(rawStats)
        rawControls.addArrangedSubview(note)
        updateRawStats()
    }

    private func configureSmoothControls() {
        smoothControls.axis = .vertical
        smoothControls.spacing = 16

        resampleSlider.minimumValue = 1
        resampleSlider.maximumValue = 8
        resampleSlider.value = 3
        resampleSlider.addTarget(self, action: #selector(resampleChanged(_:)), for: .valueChanged)
        smoothControls.addArrangedSubview(
            sliderSection(
                title: "Resample spacing",
                valueLabel: resampleValue,
                slider: resampleSlider
            )
        )

        smoothSlider.minimumValue = 0
        smoothSlider.maximumValue = 1
        smoothSlider.value = 1
        smoothSlider.addTarget(self, action: #selector(smoothChanged(_:)), for: .valueChanged)
        smoothControls.addArrangedSubview(
            sliderSection(
                title: "Smooth strength",
                valueLabel: smoothValue,
                slider: smoothSlider
            )
        )

        let note = bodyLabel("青色圆点 = 输入 · 紫色线 = 输出。Strength 只混合原始重采样结果与当前 5-point smooth。")
        smoothControls.addArrangedSubview(note)
        updateSmoothLabels()
    }

    private func configureBezierControls() {
        bezierControls.axis = .vertical
        bezierControls.spacing = 16

        toleranceSlider.minimumValue = 0.5
        toleranceSlider.maximumValue = 8
        toleranceSlider.value = 2.5
        toleranceSlider.addTarget(self, action: #selector(toleranceChanged(_:)), for: .valueChanged)
        bezierControls.addArrangedSubview(
            sliderSection(
                title: "Fit tolerance",
                valueLabel: toleranceValue,
                slider: toleranceSlider
            )
        )

        let lookAhead = UIStackView()
        lookAhead.axis = .vertical
        lookAhead.spacing = 8
        lookAhead.addArrangedSubview(sectionLabel("Look-ahead"))
        lookAheadControl.selectedSegmentIndex = 1
        lookAheadControl.addTarget(self, action: #selector(lookAheadChanged(_:)), for: .valueChanged)
        lookAhead.addArrangedSubview(lookAheadControl)
        bezierControls.addArrangedSubview(lookAhead)

        let note = bodyLabel("灰 = Smooth 输入 · 绿 = 已冻结 · 橙 = Active tail · 灰点 = Waiting。")
        bezierControls.addArrangedSubview(note)
        updateToleranceLabel()
    }

    private func configureStrokeControls() {
        strokeControls.axis = .vertical
        strokeControls.spacing = 16

        strokeWidthSlider.minimumValue = 4
        strokeWidthSlider.maximumValue = 30
        strokeWidthSlider.value = 12
        strokeWidthSlider.addTarget(self, action: #selector(strokeWidthChanged(_:)), for: .valueChanged)
        strokeControls.addArrangedSubview(
            sliderSection(
                title: "Stroke width",
                valueLabel: strokeWidthValue,
                slider: strokeWidthSlider
            )
        )

        let centerlineRow = UIStackView()
        centerlineRow.axis = .horizontal
        centerlineRow.alignment = .center
        centerlineRow.spacing = 10

        let centerlineLabel = UILabel()
        centerlineLabel.text = "Show centerline"
        centerlineLabel.font = .systemFont(ofSize: 13, weight: .medium)
        centerlineLabel.textColor = .label

        centerlineSwitch.isOn = true
        centerlineSwitch.addTarget(self, action: #selector(centerlineChanged(_:)), for: .valueChanged)

        centerlineRow.addArrangedSubview(centerlineLabel)
        centerlineRow.addArrangedSubview(UIView())
        centerlineRow.addArrangedSubview(centerlineSwitch)
        strokeControls.addArrangedSubview(centerlineRow)

        let note = bodyLabel("黑 = 最终矢量笔迹 · 蓝 = Bézier 中心线。暂时仍不接压感、速度或纹理。")
        strokeControls.addArrangedSubview(note)
        updateStrokeWidthLabel()
    }

    private func configureLayout() {
        inspector.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .horizontal
        rootStack.spacing = 12
        rootStack.alignment = .fill
        rootStack.distribution = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(inspector)
        rootStack.addArrangedSubview(canvas)
        view.addSubview(rootStack)

        inspectorWidthConstraint = inspector.widthAnchor.constraint(equalToConstant: 280)
        inspectorWidthConstraint?.priority = .required
        inspectorWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            canvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])
    }

    private func selectLayer(_ layer: GeometryPipelineLayer) {
        selectedLayer = layer
        canvas.selectedLayer = layer
        inspectorTitle.text = "\(layer.rawValue + 1)  \(layer.title)"
        inspectorDetail.text = layer.detail

        rawControls.isHidden = layer != .raw
        smoothControls.isHidden = layer != .smooth
        bezierControls.isHidden = layer != .bezier
        strokeControls.isHidden = layer != .stroke
    }

    private func updateRawStats() {
        rawStats.text = String(
            format: "Raw points     %d\nSmooth points  %d\nUIKit batches  %d\nAvg / batch    %.1f",
            latestStats.rawCount,
            latestStats.smoothCount,
            latestStats.batchCount,
            latestStats.samplesPerBatch
        )
    }

    private func updateSmoothLabels() {
        resampleValue.text = String(format: "%.1f pt", resampleSlider.value)
        smoothValue.text = String(format: "%.0f%%", smoothSlider.value * 100)
    }

    private func updateToleranceLabel() {
        toleranceValue.text = String(format: "%.1f pt", toleranceSlider.value)
    }

    private func updateStrokeWidthLabel() {
        strokeWidthValue.text = String(format: "%.0f pt", strokeWidthSlider.value)
    }

    private func sliderSection(title: String, valueLabel: UILabel, slider: UISlider) -> UIView {
        let titleLabel = sectionLabel(title)

        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
        header.axis = .horizontal
        header.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .label
        return label
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    @objc private func resampleChanged(_ sender: UISlider) {
        canvas.resampleSpacing = CGFloat(sender.value)
        updateSmoothLabels()
    }

    @objc private func smoothChanged(_ sender: UISlider) {
        canvas.smoothStrength = CGFloat(sender.value)
        updateSmoothLabels()
    }

    @objc private func toleranceChanged(_ sender: UISlider) {
        canvas.fitTolerance = CGFloat(sender.value)
        updateToleranceLabel()
    }

    @objc private func lookAheadChanged(_ sender: UISegmentedControl) {
        canvas.lookAheadCount = sender.selectedSegmentIndex
    }

    @objc private func strokeWidthChanged(_ sender: UISlider) {
        canvas.vectorStrokeWidth = CGFloat(sender.value)
        updateStrokeWidthLabel()
    }

    @objc private func centerlineChanged(_ sender: UISwitch) {
        canvas.showsStrokeCenterline = sender.isOn
    }

    @objc private func clear() {
        canvas.clear()
    }
}

private struct GeometryStats {
    var rawCount = 0
    var smoothCount = 0
    var committedCount = 0
    var activeCount = 0
    var waitingCount = 0
    var batchCount = 0
    var samplesPerBatch: Double = 0
}

private struct GeometryBezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private final class GeometryComparisonCanvasView: UIView {
    var onStats: ((GeometryStats) -> Void)?
    var onLayerSelected: ((GeometryPipelineLayer) -> Void)?

    var selectedLayer: GeometryPipelineLayer = .smooth {
        didSet {
            if oldValue != selectedLayer {
                setNeedsDisplay()
            }
        }
    }

    var resampleSpacing: CGFloat = 3 {
        didSet {
            let clamped = max(1, min(8, resampleSpacing))
            if clamped != resampleSpacing {
                resampleSpacing = clamped
                return
            }
            rebuildRealtimeFit()
        }
    }

    var smoothStrength: CGFloat = 1 {
        didSet {
            let clamped = max(0, min(1, smoothStrength))
            if clamped != smoothStrength {
                smoothStrength = clamped
                return
            }
            rebuildRealtimeFit()
        }
    }

    var fitTolerance: CGFloat = 2.5 {
        didSet {
            let clamped = max(0.1, fitTolerance)
            if clamped != fitTolerance {
                fitTolerance = clamped
                return
            }
            rebuildRealtimeFit()
        }
    }

    var lookAheadCount: Int = 1 {
        didSet {
            let clamped = max(0, min(2, lookAheadCount))
            if clamped != lookAheadCount {
                lookAheadCount = clamped
                return
            }
            rebuildRealtimeFit()
        }
    }

    var vectorStrokeWidth: CGFloat = 12 {
        didSet {
            let clamped = max(1, vectorStrokeWidth)
            if clamped != vectorStrokeWidth {
                vectorStrokeWidth = clamped
                return
            }
            setNeedsDisplay()
        }
    }

    var showsStrokeCenterline = true {
        didSet {
            if oldValue != showsStrokeCenterline {
                setNeedsDisplay()
            }
        }
    }

    private let panelGap: CGFloat = 8
    private let panelInset: CGFloat = 8
    private let panelTitleHeight: CGFloat = 34
    private let activeTailSourcePoints = 14
    private let commitChunkSourcePoints = 8

    private var points: [CGPoint] = []
    private var moveBatchCount = 0
    private var moveSampleCount = 0
    private var acceptingStroke = false

    private var committedSegments: [GeometryBezierSegment] = []
    private var activeSegments: [GeometryBezierSegment] = []
    private var activeAnchors: [CGPoint] = []
    private var waitingPoints: [CGPoint] = []
    private var latestResampled: [CGPoint] = []
    private var latestSmoothed: [CGPoint] = []
    private var committedSourceIndex = 0

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
        accessibilityLabel = "Stroke pipeline inspector canvas"
    }

    func clear() {
        resetStroke()
        updateStats()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let panels = panelRects()
        guard let panelIndex = panels.firstIndex(where: { $0.contains(location) }),
              let layer = GeometryPipelineLayer(rawValue: panelIndex) else {
            return
        }

        selectedLayer = layer
        onLayerSelected?(layer)

        guard layer == .raw,
              let rawPanel = panels.first,
              panelContentRect(rawPanel).contains(location) else {
            acceptingStroke = false
            return
        }

        resetStroke()
        acceptingStroke = true
        appendGeometryPoint(localPoint(from: location, in: rawPanel))
        updateRealtimeFit(forceFlush: false)
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

        updateRealtimeFit(forceFlush: false)
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
        updateRealtimeFit(forceFlush: true)
        updateStats()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        acceptingStroke = false
        updateRealtimeFit(forceFlush: true)
        updateStats()
        setNeedsDisplay()
    }

    private func resetStroke() {
        points.removeAll(keepingCapacity: true)
        moveBatchCount = 0
        moveSampleCount = 0
        acceptingStroke = false
        resetRealtimeState()
    }

    private func resetRealtimeState() {
        committedSegments.removeAll(keepingCapacity: true)
        activeSegments.removeAll(keepingCapacity: true)
        activeAnchors.removeAll(keepingCapacity: true)
        waitingPoints.removeAll(keepingCapacity: true)
        latestResampled.removeAll(keepingCapacity: true)
        latestSmoothed.removeAll(keepingCapacity: true)
        committedSourceIndex = 0
    }

    private func rebuildRealtimeFit() {
        resetRealtimeState()
        updateRealtimeFit(forceFlush: !acceptingStroke)
        updateStats()
        setNeedsDisplay()
    }

    private func appendGeometryPoint(_ point: CGPoint) {
        if let last = points.last, distance(last, point) < 0.001 {
            return
        }
        points.append(point)
    }

    private func processedInputs() -> (resampled: [CGPoint], smoothed: [CGPoint]) {
        let resampled = spatiallyResampled(points, spacing: resampleSpacing)
        let fullySmoothed = fivePointSmoothed(resampled)
        let strength = smoothStrength
        let smoothed = zip(resampled, fullySmoothed).map { original, target in
            CGPoint(
                x: original.x + (target.x - original.x) * strength,
                y: original.y + (target.y - original.y) * strength
            )
        }
        return (resampled, smoothed)
    }

    private func updateRealtimeFit(forceFlush: Bool) {
        let processed = processedInputs()
        latestResampled = processed.resampled
        latestSmoothed = processed.smoothed

        guard !latestSmoothed.isEmpty else {
            activeSegments.removeAll(keepingCapacity: true)
            activeAnchors.removeAll(keepingCapacity: true)
            waitingPoints.removeAll(keepingCapacity: true)
            return
        }

        let visibleCount = forceFlush
            ? latestSmoothed.count
            : max(0, latestSmoothed.count - lookAheadCount)

        if visibleCount < latestSmoothed.count {
            waitingPoints = Array(latestSmoothed[visibleCount..<latestSmoothed.count])
        } else {
            waitingPoints.removeAll(keepingCapacity: true)
        }

        guard visibleCount > 0 else {
            activeSegments.removeAll(keepingCapacity: true)
            activeAnchors.removeAll(keepingCapacity: true)
            return
        }

        committedSourceIndex = min(committedSourceIndex, visibleCount - 1)

        if forceFlush {
            let tail = Array(latestSmoothed[committedSourceIndex..<visibleCount])
            let anchors = simplifiedAnchors(tail, tolerance: fitTolerance)
            committedSegments.append(contentsOf: bezierSegments(from: anchors))
            committedSourceIndex = visibleCount - 1
            activeSegments.removeAll(keepingCapacity: true)
            activeAnchors.removeAll(keepingCapacity: true)
            waitingPoints.removeAll(keepingCapacity: true)
            return
        }

        while visibleCount - committedSourceIndex > activeTailSourcePoints + commitChunkSourcePoints {
            let chunkEndExclusive = min(
                visibleCount,
                committedSourceIndex + commitChunkSourcePoints + 1
            )
            let chunk = Array(latestSmoothed[committedSourceIndex..<chunkEndExclusive])
            let anchors = simplifiedAnchors(chunk, tolerance: fitTolerance)
            committedSegments.append(contentsOf: bezierSegments(from: anchors))
            committedSourceIndex = chunkEndExclusive - 1
        }

        let activeInput = Array(latestSmoothed[committedSourceIndex..<visibleCount])
        activeAnchors = simplifiedAnchors(activeInput, tolerance: fitTolerance)
        activeSegments = bezierSegments(from: activeAnchors)
    }

    private func updateStats() {
        let average = moveBatchCount > 0
            ? Double(moveSampleCount) / Double(moveBatchCount)
            : 0

        onStats?(
            GeometryStats(
                rawCount: points.count,
                smoothCount: latestSmoothed.count,
                committedCount: committedSegments.count,
                activeCount: activeSegments.count,
                waitingCount: waitingPoints.count,
                batchCount: moveBatchCount,
                samplesPerBatch: average
            )
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let panels = panelRects()
        guard panels.count == GeometryPipelineLayer.allCases.count else { return }

        drawPanelBackground(
            panels[0],
            layer: .raw,
            title: "1  RAW SAMPLES",
            subtitle: "真实 coalesced 点 · 在这里画"
        )
        drawPanelBackground(
            panels[1],
            layer: .smooth,
            title: "2  SMOOTH",
            subtitle: String(
                format: "%.1f pt resample · %.0f%% strength",
                resampleSpacing,
                smoothStrength * 100
            )
        )
        drawPanelBackground(
            panels[2],
            layer: .bezier,
            title: "3  REALTIME BEZIER",
            subtitle: String(format: "ε %.1f · look-ahead %d", fitTolerance, lookAheadCount)
        )
        drawPanelBackground(
            panels[3],
            layer: .stroke,
            title: "4  VECTOR STROKE",
            subtitle: String(format: "%.0f pt width", vectorStrokeWidth)
        )

        guard !points.isEmpty else {
            drawEmptyHint(in: panels[0])
            return
        }

        drawRawPanel(points, in: panels[0], context: context)
        drawSmoothPanel(
            original: latestResampled,
            smoothed: latestSmoothed,
            in: panels[1],
            context: context
        )
        drawRealtimePanel(in: panels[2], context: context)
        drawVectorStrokePanel(in: panels[3], context: context)
    }

    private func panelRects() -> [CGRect] {
        let count = CGFloat(GeometryPipelineLayer.allCases.count)
        let usableHeight = max(0, bounds.height - panelGap * (count - 1))
        let height = usableHeight / count
        guard height > 0 else { return [] }

        return GeometryPipelineLayer.allCases.map { layer in
            CGRect(
                x: 0,
                y: CGFloat(layer.rawValue) * (height + panelGap),
                width: bounds.width,
                height: height
            )
        }
    }

    private func drawPanelBackground(
        _ panel: CGRect,
        layer: GeometryPipelineLayer,
        title: String,
        subtitle: String
    ) {
        let shape = UIBezierPath(roundedRect: panel, cornerRadius: 14)
        UIColor.systemBackground.setFill()
        shape.fill()

        let isSelected = layer == selectedLayer
        (isSelected ? UIColor.systemBlue : UIColor.separator.withAlphaComponent(0.35)).setStroke()
        shape.lineWidth = isSelected ? 2 : 0.5
        shape.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: isSelected ? UIColor.systemBlue : UIColor.label
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel
        ]

        title.draw(
            at: CGPoint(x: panel.minX + 12, y: panel.minY + 8),
            withAttributes: titleAttributes
        )

        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let availableWidth = max(0, panel.width - 180)
        let subtitleX = max(
            panel.minX + 160,
            panel.maxX - min(subtitleSize.width, availableWidth) - 12
        )
        subtitle.draw(
            at: CGPoint(x: subtitleX, y: panel.minY + 9),
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

            UIColor.systemTeal.withAlphaComponent(0.25).setStroke()
            let inputPath = polylinePath(mappedOriginal)
            inputPath.lineWidth = 0.8
            inputPath.stroke()

            context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(0.9)
            for point in mappedOriginal {
                let radius: CGFloat = 2
                context.strokeEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            UIColor.systemPurple.setStroke()
            let path = splinePath(mappedSmoothed)
            path.lineWidth = 2.5
            path.stroke()
        }
    }

    private func drawRealtimePanel(in panel: CGRect, context: CGContext) {
        withPanelClip(panel, context: context) {
            let mappedInput = latestSmoothed.map { displayPoint($0, in: panel) }
            UIColor.systemGray.withAlphaComponent(0.28).setStroke()
            let inputPath = polylinePath(mappedInput)
            inputPath.lineWidth = 0.8
            inputPath.stroke()

            drawBezierSegments(
                committedSegments,
                in: panel,
                color: .systemGreen,
                lineWidth: 3
            )

            drawActiveHandles(activeSegments, in: panel, context: context)
            drawBezierSegments(
                activeSegments,
                in: panel,
                color: .systemOrange,
                lineWidth: 3
            )

            context.setFillColor(UIColor.systemOrange.cgColor)
            for anchor in activeAnchors {
                let point = displayPoint(anchor, in: panel)
                let radius: CGFloat = 2.5
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            context.setFillColor(UIColor.systemGray.withAlphaComponent(0.75).cgColor)
            for waiting in waitingPoints {
                let point = displayPoint(waiting, in: panel)
                let radius: CGFloat = 2.1
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            if let boundary = committedSegments.last?.end {
                let point = displayPoint(boundary, in: panel)
                context.setFillColor(UIColor.systemGreen.cgColor)
                let radius: CGFloat = 3.4
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

    private func drawVectorStrokePanel(in panel: CGRect, context: CGContext) {
        withPanelClip(panel, context: context) {
            let segments = committedSegments + activeSegments
            let centerline = sampledCenterline(from: segments, samplesPerSegment: 12)
            guard !centerline.isEmpty else { return }

            let mappedCenterline = centerline.map { displayPoint($0, in: panel) }
            let outline = vectorOutlinePath(
                centerline: mappedCenterline,
                width: vectorStrokeWidth
            )

            UIColor.label.withAlphaComponent(0.86).setFill()
            outline.fill()

            if let first = mappedCenterline.first,
               let last = mappedCenterline.last {
                context.setFillColor(UIColor.label.withAlphaComponent(0.86).cgColor)
                let radius = vectorStrokeWidth / 2
                context.fillEllipse(
                    in: CGRect(
                        x: first.x - radius,
                        y: first.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                context.fillEllipse(
                    in: CGRect(
                        x: last.x - radius,
                        y: last.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }

            if showsStrokeCenterline {
                UIColor.systemBlue.withAlphaComponent(0.95).setStroke()
                let centerPath = polylinePath(mappedCenterline)
                centerPath.lineWidth = 1.1
                centerPath.stroke()
            }
        }
    }

    private func sampledCenterline(
        from segments: [GeometryBezierSegment],
        samplesPerSegment: Int
    ) -> [CGPoint] {
        guard samplesPerSegment > 0 else { return [] }
        var result: [CGPoint] = []
        result.reserveCapacity(segments.count * samplesPerSegment + 1)

        for (segmentIndex, segment) in segments.enumerated() {
            for step in 0...samplesPerSegment {
                if segmentIndex > 0 && step == 0 {
                    continue
                }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicPoint(on: segment, t: t))
            }
        }

        return result
    }

    private func cubicPoint(on segment: GeometryBezierSegment, t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        let a = oneMinusT * oneMinusT * oneMinusT
        let b = 3 * oneMinusT * oneMinusT * t
        let c = 3 * oneMinusT * t * t
        let d = t * t * t

        return CGPoint(
            x: a * segment.start.x
                + b * segment.control1.x
                + c * segment.control2.x
                + d * segment.end.x,
            y: a * segment.start.y
                + b * segment.control1.y
                + c * segment.control2.y
                + d * segment.end.y
        )
    }

    private func vectorOutlinePath(centerline: [CGPoint], width: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        guard centerline.count > 1, width > 0 else { return path }

        let halfWidth = width / 2
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(centerline.count)
        right.reserveCapacity(centerline.count)

        for index in centerline.indices {
            let previous = centerline[index == centerline.startIndex ? index : index - 1]
            let next = centerline[index == centerline.index(before: centerline.endIndex) ? index : index + 1]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = hypot(dx, dy)

            let normal: CGVector
            if length > 0.0001 {
                normal = CGVector(dx: -dy / length, dy: dx / length)
            } else {
                normal = .zero
            }

            left.append(
                CGPoint(
                    x: centerline[index].x + normal.dx * halfWidth,
                    y: centerline[index].y + normal.dy * halfWidth
                )
            )
            right.append(
                CGPoint(
                    x: centerline[index].x - normal.dx * halfWidth,
                    y: centerline[index].y - normal.dy * halfWidth
                )
            )
        }

        guard let firstLeft = left.first else { return path }
        path.move(to: firstLeft)
        for point in left.dropFirst() {
            path.addLine(to: point)
        }
        for point in right.reversed() {
            path.addLine(to: point)
        }
        path.close()
        return path
    }

    private func drawBezierSegments(
        _ segments: [GeometryBezierSegment],
        in panel: CGRect,
        color: UIColor,
        lineWidth: CGFloat
    ) {
        guard let first = segments.first else { return }
        let path = UIBezierPath()
        path.move(to: displayPoint(first.start, in: panel))
        for segment in segments {
            path.addCurve(
                to: displayPoint(segment.end, in: panel),
                controlPoint1: displayPoint(segment.control1, in: panel),
                controlPoint2: displayPoint(segment.control2, in: panel)
            )
        }
        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func drawActiveHandles(
        _ segments: [GeometryBezierSegment],
        in panel: CGRect,
        context: CGContext
    ) {
        guard !segments.isEmpty else { return }
        context.saveGState()
        context.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(0.7)
        context.setLineDash(phase: 0, lengths: [3, 3])
        for segment in segments {
            context.move(to: displayPoint(segment.start, in: panel))
            context.addLine(to: displayPoint(segment.control1, in: panel))
            context.move(to: displayPoint(segment.end, in: panel))
            context.addLine(to: displayPoint(segment.control2, in: panel))
        }
        context.strokePath()
        context.restoreGState()
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
        let text = "在 RAW 里用 Pencil 画一笔"
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
