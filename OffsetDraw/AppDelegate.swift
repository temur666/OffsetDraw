import UIKit
import ObjectiveC.runtime

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GeometryLabExperimentBootstrap.install()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

// MARK: - Geometry Lab experiments

private enum GeometryLabExperimentBootstrap {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let original = #selector(UIViewController.viewDidLayoutSubviews)
        let replacement = #selector(GeometryLabViewController.od_experiment_viewDidLayoutSubviews)

        guard
            let originalMethod = class_getInstanceMethod(GeometryLabViewController.self, original),
            let replacementMethod = class_getInstanceMethod(GeometryLabViewController.self, replacement)
        else { return }

        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension GeometryLabViewController {
    @objc fileprivate func od_experiment_viewDidLayoutSubviews() {
        od_experiment_viewDidLayoutSubviews()
        GeometryLabExperimentSupport.installSmoothExperiments(in: self)
    }
}

private enum GeometryLabExperimentSupport {
    private static let pipelineButtonID = "geometry.smooth.compare.pipeline"
    private static let filterButtonID = "geometry.smooth.context.filter"

    static func installSmoothExperiments(in controller: GeometryLabViewController) {
        guard let smoothControls: UIStackView = reflectedValue(
            named: "smoothControls",
            from: controller,
            as: UIStackView.self
        ) else { return }

        if !smoothControls.arrangedSubviews.contains(where: { $0.accessibilityIdentifier == pipelineButtonID }) {
            addPipelineCompareSection(to: smoothControls, controller: controller)
        }

        if !smoothControls.arrangedSubviews.contains(where: { $0.accessibilityIdentifier == filterButtonID }) {
            addContextFilterSection(to: smoothControls, controller: controller)
        }
    }

    private static func addPipelineCompareSection(
        to stack: UIStackView,
        controller: GeometryLabViewController
    ) {
        addDivider(to: stack)
        addHeading("COMPARE OUTPUT", to: stack)
        addBody("同一条 Smooth：A 继续经过 Bézier，B 直接生成 Stroke。", to: stack)

        var config = UIButton.Configuration.bordered()
        config.title = "Pipeline compare"
        config.image = UIImage(systemName: "rectangle.split.2x1")
        config.imagePadding = 7
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = pipelineButtonID
        button.addAction(UIAction { [weak controller] _ in
            guard let controller else { return }
            presentPipelineCompare(from: controller)
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private static func addContextFilterSection(
        to stack: UIStackView,
        controller: GeometryLabViewController
    ) {
        addDivider(to: stack)
        addHeading("EDGE CONTEXT FILTER", to: stack)
        addBody("整条 Smooth 先生成低频参考，只允许修正起笔 / 收笔，中间不动。", to: stack)

        var config = UIButton.Configuration.borderedProminent()
        config.title = "Try context filter"
        config.image = UIImage(systemName: "waveform.path.ecg")
        config.imagePadding = 7
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = filterButtonID
        button.addAction(UIAction { [weak controller] _ in
            guard let controller else { return }
            presentContextFilter(from: controller)
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private static func addDivider(to stack: UIStackView) {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)
    }

    private static func addHeading(_ text: String, to stack: UIStackView) {
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .label
        stack.addArrangedSubview(label)
    }

    private static func addBody(_ text: String, to stack: UIStackView) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }

    private static func presentContextFilter(from controller: GeometryLabViewController) {
        guard
            let canvas: UIView = reflectedValue(named: "canvas", from: controller, as: UIView.self),
            let smoothed: [CGPoint] = reflectedValue(
                named: "latestSmoothed",
                from: canvas,
                as: [CGPoint].self
            ),
            smoothed.count >= 8
        else {
            showNeedStrokeAlert(on: controller, message: "先在 RAW 里画一条稍长的线，再测试起收笔过滤。")
            return
        }

        let experiment = ContextEdgeFilterViewController(points: smoothed)
        let navigation = UINavigationController(rootViewController: experiment)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        controller.present(navigation, animated: true)
    }

    private static func presentPipelineCompare(from controller: GeometryLabViewController) {
        guard
            let canvas: UIView = reflectedValue(named: "canvas", from: controller, as: UIView.self),
            let smoothed: [CGPoint] = reflectedValue(
                named: "latestSmoothed",
                from: canvas,
                as: [CGPoint].self
            ),
            smoothed.count > 1
        else {
            showNeedStrokeAlert(on: controller, message: "先在 RAW 里画完一笔，再比较两条输出路径。")
            return
        }

        let segments = reflectedSegments(named: "committedSegments", from: canvas)
            + reflectedSegments(named: "activeSegments", from: canvas)
        guard !segments.isEmpty else {
            showNeedStrokeAlert(on: controller, message: "当前还没有 Bézier 输出，先完成一笔。")
            return
        }

        let width: CGFloat = reflectedValue(
            named: "vectorStrokeWidth",
            from: canvas,
            as: CGFloat.self
        ) ?? 12

        let current = sampleBezierCenterline(segments, samplesPerSegment: 16)
        let direct = sampleSmoothSpline(smoothed, samplesPerSegment: 16)
        let experiment = PipelineCompareViewController(
            current: current,
            direct: direct,
            strokeWidth: width
        )
        let navigation = UINavigationController(rootViewController: experiment)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        controller.present(navigation, animated: true)
    }

    private static func showNeedStrokeAlert(on controller: UIViewController, message: String) {
        let alert = UIAlertController(title: "先画一笔", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        controller.present(alert, animated: true)
    }

    private static func reflectedValue<T>(named name: String, from object: Any, as type: T.Type) -> T? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children where child.label == name {
                return child.value as? T
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func reflectedAnyValue(named name: String, from object: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children where child.label == name {
                return child.value
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func reflectedSegments(named name: String, from object: Any) -> [ExperimentBezierSegment] {
        guard let value = reflectedAnyValue(named: name, from: object) else { return [] }
        return Mirror(reflecting: value).children.compactMap { element in
            var start: CGPoint?
            var control1: CGPoint?
            var control2: CGPoint?
            var end: CGPoint?

            for field in Mirror(reflecting: element.value).children {
                switch field.label {
                case "start": start = field.value as? CGPoint
                case "control1": control1 = field.value as? CGPoint
                case "control2": control2 = field.value as? CGPoint
                case "end": end = field.value as? CGPoint
                default: break
                }
            }

            guard let start, let control1, let control2, let end else { return nil }
            return ExperimentBezierSegment(
                start: start,
                control1: control1,
                control2: control2,
                end: end
            )
        }
    }

    private static func sampleBezierCenterline(
        _ segments: [ExperimentBezierSegment],
        samplesPerSegment: Int
    ) -> [CGPoint] {
        var result: [CGPoint] = []
        for (segmentIndex, segment) in segments.enumerated() {
            for step in 0...samplesPerSegment {
                if segmentIndex > 0 && step == 0 { continue }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicPoint(
                    start: segment.start,
                    control1: segment.control1,
                    control2: segment.control2,
                    end: segment.end,
                    t: t
                ))
            }
        }
        return result
    }

    private static func sampleSmoothSpline(_ points: [CGPoint], samplesPerSegment: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        if points.count == 2 { return points }

        var result: [CGPoint] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            for step in 0...samplesPerSegment {
                if index > 0 && step == 0 { continue }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicPoint(start: p1, control1: c1, control2: c2, end: p2, t: t))
            }
        }
        return result
    }

    private static func cubicPoint(
        start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        end: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}

private struct ExperimentBezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

// MARK: - Context edge filter

private final class ContextEdgeFilterViewController: UIViewController {
    private let original: [CGPoint]
    private let canvas: ContextEdgeFilterCanvasView
    private let rangeSlider = UISlider()
    private let contextSlider = UISlider()
    private let strengthSlider = UISlider()
    private let rangeValue = UILabel()
    private let contextValue = UILabel()
    private let strengthValue = UILabel()
    private let startSwitch = UISwitch()
    private let endSwitch = UISwitch()
    private let modeControl = UISegmentedControl(items: ["A 原始", "B 过滤", "并排", "叠加"])

    init(points: [CGPoint]) {
        original = points
        canvas = ContextEdgeFilterCanvasView(original: points)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Context Edge Filter"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        rangeSlider.minimumValue = 0.05
        rangeSlider.maximumValue = 0.30
        rangeSlider.value = 0.14
        rangeSlider.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)

        contextSlider.minimumValue = 0.20
        contextSlider.maximumValue = 1.00
        contextSlider.value = 0.65
        contextSlider.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)

        strengthSlider.minimumValue = 0
        strengthSlider.maximumValue = 1
        strengthSlider.value = 0.85
        strengthSlider.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)

        startSwitch.isOn = true
        endSwitch.isOn = true
        startSwitch.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)
        endSwitch.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)

        modeControl.selectedSegmentIndex = 3
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        let intro = UILabel()
        intro.text = "先用更大范围的上下文得到低频参考，再只修正起笔 / 收笔；首尾落点和中间主体保持不动。"
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        let controls = UIStackView(arrangedSubviews: [
            sliderRow(title: "Edge range", value: rangeValue, slider: rangeSlider),
            sliderRow(title: "Context", value: contextValue, slider: contextSlider),
            sliderRow(title: "Strength", value: strengthValue, slider: strengthSlider),
            switchRow(title: "Start", toggle: startSwitch),
            switchRow(title: "End", toggle: endSwitch),
            modeControl
        ])
        controls.axis = .vertical
        controls.spacing = 10

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .systemBackground
        canvas.layer.cornerRadius = 16
        canvas.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [intro, controls, canvas])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])

        updateExperiment()
    }

    private func sliderRow(title: String, value: UILabel, slider: UISlider) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        value.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        value.textColor = .secondaryLabel
        value.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), value])
        header.axis = .horizontal
        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func switchRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let row = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    @objc private func parametersChanged() {
        updateExperiment()
    }

    @objc private func modeChanged() {
        canvas.mode = ContextEdgeFilterCanvasView.Mode(rawValue: modeControl.selectedSegmentIndex) ?? .overlay
    }

    private func updateExperiment() {
        rangeValue.text = String(format: "%.0f%%", rangeSlider.value * 100)
        contextValue.text = String(format: "%.0f%%", contextSlider.value * 100)
        strengthValue.text = String(format: "%.0f%%", strengthSlider.value * 100)

        let result = ContextEdgeFilter.make(
            points: original,
            edgeFraction: CGFloat(rangeSlider.value),
            contextFraction: CGFloat(contextSlider.value),
            strength: CGFloat(strengthSlider.value),
            filterStart: startSwitch.isOn,
            filterEnd: endSwitch.isOn
        )
        canvas.reference = result.reference
        canvas.filtered = result.filtered
        canvas.edgeCount = result.edgeCount
        canvas.mode = ContextEdgeFilterCanvasView.Mode(rawValue: modeControl.selectedSegmentIndex) ?? .overlay
    }
}

private enum ContextEdgeFilter {
    struct Result {
        let reference: [CGPoint]
        let filtered: [CGPoint]
        let edgeCount: Int
    }

    static func make(
        points: [CGPoint],
        edgeFraction: CGFloat,
        contextFraction: CGFloat,
        strength: CGFloat,
        filterStart: Bool,
        filterEnd: Bool
    ) -> Result {
        guard points.count >= 4 else {
            return Result(reference: points, filtered: points, edgeCount: 0)
        }

        let n = points.count
        let edgeCount = max(2, min(n / 3, Int(round(CGFloat(n - 1) * edgeFraction))))
        let radius = max(2, min(n / 3, Int(round(CGFloat(n) * contextFraction * 0.25))))
        let reference = lowFrequencyReference(points, radius: radius)
        var filtered = points
        let s = max(0, min(1, strength))

        if filterStart, edgeCount > 1 {
            let boundary = edgeCount
            let ref0 = reference[0]
            let ref1 = reference[boundary]
            let delta0 = CGVector(dx: points[0].x - ref0.x, dy: points[0].y - ref0.y)
            let delta1 = CGVector(dx: points[boundary].x - ref1.x, dy: points[boundary].y - ref1.y)

            for i in 0...boundary {
                let t = CGFloat(i) / CGFloat(boundary)
                let adjusted = CGPoint(
                    x: reference[i].x + delta0.dx * (1 - t) + delta1.dx * t,
                    y: reference[i].y + delta0.dy * (1 - t) + delta1.dy * t
                )
                let weight = s * sqrt(max(0, 1 - t))
                filtered[i] = lerp(points[i], adjusted, weight: weight)
            }
        }

        if filterEnd, edgeCount > 1 {
            let boundary = n - 1 - edgeCount
            let last = n - 1
            let ref0 = reference[boundary]
            let ref1 = reference[last]
            let delta0 = CGVector(dx: points[boundary].x - ref0.x, dy: points[boundary].y - ref0.y)
            let delta1 = CGVector(dx: points[last].x - ref1.x, dy: points[last].y - ref1.y)

            for i in boundary...last {
                let t = CGFloat(i - boundary) / CGFloat(edgeCount)
                let adjusted = CGPoint(
                    x: reference[i].x + delta0.dx * (1 - t) + delta1.dx * t,
                    y: reference[i].y + delta0.dy * (1 - t) + delta1.dy * t
                )
                let weight = s * sqrt(max(0, t))
                filtered[i] = lerp(points[i], adjusted, weight: weight)
            }
        }

        filtered[0] = points[0]
        filtered[n - 1] = points[n - 1]
        return Result(reference: reference, filtered: filtered, edgeCount: edgeCount)
    }

    private static func lowFrequencyReference(_ points: [CGPoint], radius: Int) -> [CGPoint] {
        var result = points
        for _ in 0..<2 {
            var next: [CGPoint] = []
            next.reserveCapacity(result.count)
            for index in result.indices {
                let lower = max(0, index - radius)
                let upper = min(result.count - 1, index + radius)
                var x: CGFloat = 0
                var y: CGFloat = 0
                var total: CGFloat = 0

                for candidate in lower...upper {
                    let distance = abs(candidate - index)
                    let weight = CGFloat(radius + 1 - distance)
                    x += result[candidate].x * weight
                    y += result[candidate].y * weight
                    total += weight
                }
                next.append(CGPoint(x: x / total, y: y / total))
            }
            result = next
        }
        return result
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, weight: CGFloat) -> CGPoint {
        let w = max(0, min(1, weight))
        return CGPoint(x: a.x + (b.x - a.x) * w, y: a.y + (b.y - a.y) * w)
    }
}

private final class ContextEdgeFilterCanvasView: UIView {
    enum Mode: Int { case original, filtered, sideBySide, overlay }

    let original: [CGPoint]
    var reference: [CGPoint] = [] { didSet { setNeedsDisplay() } }
    var filtered: [CGPoint] = [] { didSet { setNeedsDisplay() } }
    var edgeCount = 0 { didSet { setNeedsDisplay() } }
    var mode: Mode = .overlay { didSet { setNeedsDisplay() } }

    init(original: [CGPoint]) {
        self.original = original
        super.init(frame: .zero)
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard !original.isEmpty else { return }
        UIColor.systemBackground.setFill()
        UIRectFill(bounds)

        switch mode {
        case .original:
            drawSingle(points: original, color: .label, label: "A  Original Smooth", in: bounds)
        case .filtered:
            drawSingle(points: filtered, color: .systemBlue, label: "B  Context Filter", in: bounds)
        case .sideBySide:
            let gap: CGFloat = 16
            let half = (bounds.width - gap) / 2
            drawSingle(
                points: original,
                color: .label,
                label: "A  Original",
                in: CGRect(x: 0, y: 0, width: half, height: bounds.height)
            )
            drawSingle(
                points: filtered,
                color: .systemBlue,
                label: "B  Filtered",
                in: CGRect(x: half + gap, y: 0, width: half, height: bounds.height)
            )
        case .overlay:
            let source = boundsForPoints(original + filtered + reference)
            let target = bounds.insetBy(dx: 24, dy: 30)
            let transform = fittingTransform(source: source, into: target)
            drawPath(reference, transform: transform, color: .systemGray3, width: 1, dash: [4, 4])
            drawPath(original, transform: transform, color: .systemOrange, width: 2.2)
            drawPath(filtered, transform: transform, color: .systemBlue, width: 2.4)
            drawEdgeMarkers(transform: transform)
            drawLegend()
        }
    }

    private func drawSingle(points: [CGPoint], color: UIColor, label: String, in area: CGRect) {
        guard !points.isEmpty else { return }
        let target = area.insetBy(dx: 18, dy: 30)
        let source = boundsForPoints(original + filtered + reference)
        let transform = fittingTransform(source: source, into: target)
        drawPath(points, transform: transform, color: color, width: 2.5)
        label.draw(at: CGPoint(x: area.minX + 14, y: area.minY + 10), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    private func drawPath(
        _ points: [CGPoint],
        transform: (CGPoint) -> CGPoint,
        color: UIColor,
        width: CGFloat,
        dash: [CGFloat] = []
    ) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: transform(first))
        for point in points.dropFirst() { path.addLine(to: transform(point)) }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    private func drawEdgeMarkers(transform: (CGPoint) -> CGPoint) {
        guard edgeCount > 0, original.count > edgeCount * 2 else { return }
        let startBoundary = transform(original[edgeCount])
        let endBoundary = transform(original[original.count - 1 - edgeCount])
        UIColor.systemPurple.setFill()
        for point in [startBoundary, endBoundary] {
            UIBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
        }
    }

    private func drawLegend() {
        "橙 A 原始".draw(at: CGPoint(x: 16, y: 10), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.systemOrange
        ])
        "蓝 B 过滤".draw(at: CGPoint(x: 88, y: 10), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.systemBlue
        ])
        "灰 虚线=低频参考".draw(at: CGPoint(x: 160, y: 10), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    private func boundsForPoints(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func fittingTransform(source: CGRect, into target: CGRect) -> (CGPoint) -> CGPoint {
        let scale = min(target.width / max(1, source.width), target.height / max(1, source.height))
        let dx = target.midX - source.midX * scale
        let dy = target.midY - source.midY * scale
        return { point in CGPoint(x: point.x * scale + dx, y: point.y * scale + dy) }
    }
}

// MARK: - Pipeline comparison

private final class PipelineCompareViewController: UIViewController {
    private let canvas: DualPathCanvas
    private let mode = UISegmentedControl(items: ["A", "B", "并排", "叠加"])

    init(current: [CGPoint], direct: [CGPoint], strokeWidth: CGFloat) {
        canvas = DualPathCanvas(a: current, b: direct, lineWidth: strokeWidth)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compare from Smooth"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        let label = UILabel()
        label.text = "A = Smooth → Bézier → Stroke   ·   B = Smooth → Stroke"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        mode.selectedSegmentIndex = 2
        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .systemBackground
        canvas.layer.cornerRadius = 16
        canvas.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [label, mode, canvas])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    @objc private func modeChanged() {
        canvas.mode = DualPathCanvas.Mode(rawValue: mode.selectedSegmentIndex) ?? .sideBySide
    }
}

private final class DualPathCanvas: UIView {
    enum Mode: Int { case a, b, sideBySide, overlay }

    private let a: [CGPoint]
    private let b: [CGPoint]
    private let baseLineWidth: CGFloat
    var mode: Mode = .sideBySide { didSet { setNeedsDisplay() } }

    init(a: [CGPoint], b: [CGPoint], lineWidth: CGFloat) {
        self.a = a
        self.b = b
        self.baseLineWidth = lineWidth
        super.init(frame: .zero)
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        UIColor.systemBackground.setFill()
        UIRectFill(bounds)
        switch mode {
        case .a:
            drawSingle(a, label: "A  Current", area: bounds, color: .label)
        case .b:
            drawSingle(b, label: "B  Direct", area: bounds, color: .label)
        case .sideBySide:
            let gap: CGFloat = 16
            let half = (bounds.width - gap) / 2
            drawSingle(a, label: "A  Current", area: CGRect(x: 0, y: 0, width: half, height: bounds.height), color: .label)
            drawSingle(b, label: "B  Direct", area: CGRect(x: half + gap, y: 0, width: half, height: bounds.height), color: .label)
        case .overlay:
            let source = pointsBounds(a + b)
            let transform = fittingTransform(source: source, into: bounds.insetBy(dx: 24, dy: 30))
            drawPath(a, transform: transform, color: .systemOrange, alpha: 0.72)
            drawPath(b, transform: transform, color: .systemBlue, alpha: 0.58)
        }
    }

    private func drawSingle(_ points: [CGPoint], label: String, area: CGRect, color: UIColor) {
        let transform = fittingTransform(source: pointsBounds(a + b), into: area.insetBy(dx: 18, dy: 30))
        drawPath(points, transform: transform, color: color, alpha: 0.88)
        label.draw(at: CGPoint(x: area.minX + 14, y: area.minY + 10), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    private func drawPath(
        _ points: [CGPoint],
        transform: (point: (CGPoint) -> CGPoint, scale: CGFloat),
        color: UIColor,
        alpha: CGFloat
    ) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: transform.point(first))
        for point in points.dropFirst() { path.addLine(to: transform.point(point)) }
        path.lineWidth = max(1, baseLineWidth * transform.scale)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func pointsBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func fittingTransform(
        source: CGRect,
        into target: CGRect
    ) -> (point: (CGPoint) -> CGPoint, scale: CGFloat) {
        let scale = min(target.width / max(1, source.width), target.height / max(1, source.height))
        let dx = target.midX - source.midX * scale
        let dy = target.midY - source.midY * scale
        return (
            point: { p in CGPoint(x: p.x * scale + dx, y: p.y * scale + dy) },
            scale: scale
        )
    }
}
