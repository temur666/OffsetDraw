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
    private static let filterButtonID = "geometry.smooth.context.motion.filter"

    static func installSmoothExperiments(in controller: GeometryLabViewController) {
        guard let smoothControls: UIStackView = reflectedValue(named: "smoothControls", from: controller, as: UIStackView.self) else { return }
        if !smoothControls.arrangedSubviews.contains(where: { $0.accessibilityIdentifier == pipelineButtonID }) {
            addPipelineCompareSection(to: smoothControls, controller: controller)
        }
        if !smoothControls.arrangedSubviews.contains(where: { $0.accessibilityIdentifier == filterButtonID }) {
            addContextMotionFilterSection(to: smoothControls, controller: controller)
        }
    }

    private static func addPipelineCompareSection(to stack: UIStackView, controller: GeometryLabViewController) {
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

    private static func addContextMotionFilterSection(to stack: UIStackView, controller: GeometryLabViewController) {
        addDivider(to: stack)
        addHeading("CONTEXT MOTION FILTER V2", to: stack)
        addBody("Context 只判断首尾应该往哪走；RAW 点距 + 方向突变判断可疑程度；最终只重构首尾局部，中间 Smooth 不动。", to: stack)
        var config = UIButton.Configuration.borderedProminent()
        config.title = "Try motion filter V2"
        config.image = UIImage(systemName: "waveform.path.ecg")
        config.imagePadding = 7
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = filterButtonID
        button.addAction(UIAction { [weak controller] _ in
            guard let controller else { return }
            presentContextMotionFilter(from: controller)
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

    private static func presentContextMotionFilter(from controller: GeometryLabViewController) {
        guard
            let canvas: UIView = reflectedValue(named: "canvas", from: controller, as: UIView.self),
            let smoothed: [CGPoint] = reflectedValue(named: "latestSmoothed", from: canvas, as: [CGPoint].self),
            smoothed.count >= 8
        else {
            showNeedStrokeAlert(on: controller, message: "先在 RAW 里画一条稍长的线，再测试起收笔 Motion Filter。")
            return
        }
        let raw: [CGPoint] = reflectedValue(named: "points", from: canvas, as: [CGPoint].self) ?? smoothed
        let experiment = ContextMotionFilterViewController(smoothPoints: smoothed, rawPoints: raw)
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
            let smoothed: [CGPoint] = reflectedValue(named: "latestSmoothed", from: canvas, as: [CGPoint].self),
            smoothed.count > 1
        else {
            showNeedStrokeAlert(on: controller, message: "先在 RAW 里画完一笔，再比较两条输出路径。")
            return
        }
        let segments = reflectedSegments(named: "committedSegments", from: canvas) + reflectedSegments(named: "activeSegments", from: canvas)
        guard !segments.isEmpty else {
            showNeedStrokeAlert(on: controller, message: "当前还没有 Bézier 输出，先完成一笔。")
            return
        }
        let width: CGFloat = reflectedValue(named: "vectorStrokeWidth", from: canvas, as: CGFloat.self) ?? 12
        let current = sampleBezierCenterline(segments, samplesPerSegment: 16)
        let direct = sampleSmoothSpline(smoothed, samplesPerSegment: 16)
        let experiment = PipelineCompareViewController(current: current, direct: direct, strokeWidth: width)
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
            for child in current.children where child.label == name { return child.value as? T }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func reflectedAnyValue(named name: String, from object: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children where child.label == name { return child.value }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func reflectedSegments(named name: String, from object: Any) -> [ExperimentBezierSegment] {
        guard let value = reflectedAnyValue(named: name, from: object) else { return [] }
        return Mirror(reflecting: value).children.compactMap { element in
            var start: CGPoint?, control1: CGPoint?, control2: CGPoint?, end: CGPoint?
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
            return ExperimentBezierSegment(start: start, control1: control1, control2: control2, end: end)
        }
    }

    private static func sampleBezierCenterline(_ segments: [ExperimentBezierSegment], samplesPerSegment: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for (segmentIndex, segment) in segments.enumerated() {
            for step in 0...samplesPerSegment {
                if segmentIndex > 0 && step == 0 { continue }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicPoint(start: segment.start, control1: segment.control1, control2: segment.control2, end: segment.end, t: t))
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

    private static func cubicPoint(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x, y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }
}

private struct ExperimentBezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private final class ContextMotionFilterViewController: UIViewController {
    private let smoothPoints: [CGPoint]
    private let rawPoints: [CGPoint]
    private let canvas: ContextMotionFilterCanvasView
    private let rangeSlider = UISlider(), contextSlider = UISlider(), sensitivitySlider = UISlider()
    private let rangeValue = UILabel(), contextValue = UILabel(), sensitivityValue = UILabel(), signalLabel = UILabel()
    private let startSwitch = UISwitch(), endSwitch = UISwitch()
    private let modeControl = UISegmentedControl(items: ["A 原始", "B 过滤", "并排", "叠加"])

    init(smoothPoints: [CGPoint], rawPoints: [CGPoint]) {
        self.smoothPoints = smoothPoints
        self.rawPoints = rawPoints
        self.canvas = ContextMotionFilterCanvasView(original: smoothPoints)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Context Motion Filter V2"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })

        rangeSlider.minimumValue = 0.04; rangeSlider.maximumValue = 0.24; rangeSlider.value = 0.12
        contextSlider.minimumValue = 0.20; contextSlider.maximumValue = 1.00; contextSlider.value = 0.60
        sensitivitySlider.minimumValue = 0; sensitivitySlider.maximumValue = 1; sensitivitySlider.value = 0.60
        [rangeSlider, contextSlider, sensitivitySlider].forEach { $0.addTarget(self, action: #selector(parametersChanged), for: .valueChanged) }
        startSwitch.isOn = true; endSwitch.isOn = true
        startSwitch.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)
        endSwitch.addTarget(self, action: #selector(parametersChanged), for: .valueChanged)
        modeControl.selectedSegmentIndex = 3
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        let intro = UILabel()
        intro.text = "Context 只提供方向，不再当最终轨迹。RAW 点距作为速度代理，方向突变决定可疑度；可疑度自动决定修正强度。"
        intro.font = .systemFont(ofSize: 12); intro.textColor = .secondaryLabel; intro.numberOfLines = 0
        signalLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium); signalLabel.textColor = .secondaryLabel; signalLabel.numberOfLines = 0

        let controls = UIStackView(arrangedSubviews: [
            sliderRow(title: "Edge range", value: rangeValue, slider: rangeSlider),
            sliderRow(title: "Context", value: contextValue, slider: contextSlider),
            sliderRow(title: "Sensitivity", value: sensitivityValue, slider: sensitivitySlider),
            switchRow(title: "Start", toggle: startSwitch), switchRow(title: "End", toggle: endSwitch), signalLabel, modeControl
        ])
        controls.axis = .vertical; controls.spacing = 9
        canvas.translatesAutoresizingMaskIntoConstraints = false; canvas.backgroundColor = .systemBackground; canvas.layer.cornerRadius = 16; canvas.clipsToBounds = true
        let stack = UIStackView(arrangedSubviews: [intro, controls, canvas])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
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
        let titleLabel = UILabel(); titleLabel.text = title; titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        value.font = .monospacedSystemFont(ofSize: 11, weight: .semibold); value.textColor = .secondaryLabel; value.textAlignment = .right
        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), value]); header.axis = .horizontal
        let stack = UIStackView(arrangedSubviews: [header, slider]); stack.axis = .vertical; stack.spacing = 4
        return stack
    }

    private func switchRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 12, weight: .medium)
        let row = UIStackView(arrangedSubviews: [label, UIView(), toggle]); row.axis = .horizontal; row.alignment = .center
        return row
    }

    @objc private func parametersChanged() { updateExperiment() }
    @objc private func modeChanged() { canvas.mode = ContextMotionFilterCanvasView.Mode(rawValue: modeControl.selectedSegmentIndex) ?? .overlay }

    private func updateExperiment() {
        rangeValue.text = String(format: "%.0f%%", rangeSlider.value * 100)
        contextValue.text = String(format: "%.0f%%", contextSlider.value * 100)
        sensitivityValue.text = String(format: "%.0f%%", sensitivitySlider.value * 100)
        let result = ContextMotionFilter.make(
            smoothPoints: smoothPoints, rawPoints: rawPoints,
            edgeFraction: CGFloat(rangeSlider.value), contextFraction: CGFloat(contextSlider.value), sensitivity: CGFloat(sensitivitySlider.value),
            filterStart: startSwitch.isOn, filterEnd: endSwitch.isOn
        )
        canvas.reference = result.reference; canvas.filtered = result.filtered; canvas.edgeCount = result.edgeCount
        canvas.startConfidence = result.start.confidence; canvas.endConfidence = result.end.confidence
        canvas.mode = ContextMotionFilterCanvasView.Mode(rawValue: modeControl.selectedSegmentIndex) ?? .overlay
        signalLabel.text = String(format: "Start  %.2f  dir %.2f  speed× %.2f\nEnd    %.2f  dir %.2f  speed× %.2f",
                                  result.start.confidence, result.start.directionScore, result.start.speedRatio,
                                  result.end.confidence, result.end.directionScore, result.end.speedRatio)
    }
}

private enum ContextMotionFilter {
    struct EdgeSignal { let confidence: CGFloat; let directionScore: CGFloat; let speedRatio: CGFloat }
    struct Result { let reference: [CGPoint]; let filtered: [CGPoint]; let edgeCount: Int; let start: EdgeSignal; let end: EdgeSignal }

    static func make(
        smoothPoints: [CGPoint], rawPoints: [CGPoint], edgeFraction: CGFloat, contextFraction: CGFloat, sensitivity: CGFloat,
        filterStart: Bool, filterEnd: Bool
    ) -> Result {
        guard smoothPoints.count >= 4 else {
            let empty = EdgeSignal(confidence: 0, directionScore: 0, speedRatio: 1)
            return Result(reference: smoothPoints, filtered: smoothPoints, edgeCount: 0, start: empty, end: empty)
        }
        let n = smoothPoints.count
        let edgeCount = max(3, min(n / 3, Int(round(CGFloat(n - 1) * edgeFraction))))
        let radius = max(2, min(n / 3, Int(round(CGFloat(n) * contextFraction * 0.22))))
        let reference = lowFrequencyReference(smoothPoints, radius: radius)
        let startDirection = referenceDirection(reference, edgeCount: edgeCount)
        let reversedReferenceDirection = referenceDirection(Array(reference.reversed()), edgeCount: edgeCount)
        let startSignal = edgeSignal(rawPoints: rawPoints, expectedDirection: startDirection, edgeFraction: edgeFraction, sensitivity: sensitivity)
        let endSignal = edgeSignal(rawPoints: Array(rawPoints.reversed()), expectedDirection: reversedReferenceDirection, edgeFraction: edgeFraction, sensitivity: sensitivity)
        var filtered = smoothPoints
        if filterStart, startSignal.confidence > 0.001 {
            filtered = correctedStart(points: filtered, referenceDirection: startDirection, edgeCount: edgeCount, confidence: startSignal.confidence)
        }
        if filterEnd, endSignal.confidence > 0.001 {
            let reversed = correctedStart(points: Array(filtered.reversed()), referenceDirection: reversedReferenceDirection, edgeCount: edgeCount, confidence: endSignal.confidence)
            filtered = Array(reversed.reversed())
        }
        filtered[0] = smoothPoints[0]; filtered[n - 1] = smoothPoints[n - 1]
        return Result(reference: reference, filtered: filtered, edgeCount: edgeCount, start: startSignal, end: endSignal)
    }

    private static func correctedStart(points: [CGPoint], referenceDirection: CGVector, edgeCount: Int, confidence: CGFloat) -> [CGPoint] {
        guard points.count > edgeCount + 2, edgeCount >= 3 else { return points }
        var result = points
        let start = points[0], boundaryIndex = edgeCount, boundary = points[boundaryIndex]
        let chord = distance(start, boundary)
        guard chord > 0.001 else { return points }
        let startDirection = normalized(referenceDirection)
        let boundaryDirection = normalized(vector(from: points[max(0, boundaryIndex - 2)], to: points[min(points.count - 1, boundaryIndex + 1)]))
        let c1 = CGPoint(x: start.x + startDirection.dx * chord * 0.34, y: start.y + startDirection.dy * chord * 0.34)
        let c2 = CGPoint(x: boundary.x - boundaryDirection.dx * chord * 0.24, y: boundary.y - boundaryDirection.dy * chord * 0.24)
        for i in 1..<boundaryIndex {
            let t = CGFloat(i) / CGFloat(boundaryIndex)
            let target = cubicPoint(start: start, control1: c1, control2: c2, end: boundary, t: t)
            let localShape = min(1, 6.75 * t * (1 - t) * (1 - t))
            result[i] = lerp(points[i], target, weight: confidence * localShape)
        }
        result[0] = points[0]; result[boundaryIndex] = points[boundaryIndex]
        return result
    }

    private static func edgeSignal(rawPoints: [CGPoint], expectedDirection: CGVector, edgeFraction: CGFloat, sensitivity: CGFloat) -> EdgeSignal {
        guard rawPoints.count >= 6 else { return EdgeSignal(confidence: 0, directionScore: 0, speedRatio: 1) }
        let allLengths = segmentLengths(rawPoints).filter { $0 > 0.0001 }
        let baseline = max(0.001, median(allLengths))
        let edgePointCount = max(5, min(rawPoints.count / 3, Int(round(CGFloat(rawPoints.count) * max(0.08, edgeFraction * 1.6)))))
        let edge = Array(rawPoints.prefix(edgePointCount))
        let edgeLengths = segmentLengths(edge)
        let earlyCount = min(3, edgeLengths.count)
        let earlyMean = earlyCount > 0 ? edgeLengths.prefix(earlyCount).reduce(0, +) / CGFloat(earlyCount) : baseline
        let speedRatio = max(0, earlyMean / baseline)
        let speedScore = clamp01((speedRatio - 1) / 2.2)
        let sampleEnd = min(edge.count - 1, 3)
        let initialDirection = normalized(vector(from: edge[0], to: edge[sampleEnd]))
        let expected = normalized(expectedDirection)
        let initialDeviation = angleScore(initialDirection, expected)
        var maximumTurn: CGFloat = 0
        if edge.count >= 3 {
            for i in 1..<(edge.count - 1) {
                let incoming = normalized(vector(from: edge[i - 1], to: edge[i]))
                let outgoing = normalized(vector(from: edge[i], to: edge[i + 1]))
                maximumTurn = max(maximumTurn, angleScore(incoming, outgoing))
            }
        }
        let directionScore = clamp01(max(initialDeviation, maximumTurn * 0.85))
        let rawAnomaly = directionScore * (0.68 + 0.32 * speedScore)
        let threshold = 0.68 - clamp01(sensitivity) * 0.53
        let confidence = smoothstep(clamp01((rawAnomaly - threshold) / max(0.001, 1 - threshold)))
        return EdgeSignal(confidence: confidence, directionScore: directionScore, speedRatio: speedRatio)
    }

    private static func referenceDirection(_ points: [CGPoint], edgeCount: Int) -> CGVector {
        guard points.count > 1 else { return CGVector(dx: 1, dy: 0) }
        let far = min(points.count - 1, max(2, edgeCount * 2))
        return normalized(vector(from: points[0], to: points[far]))
    }

    private static func lowFrequencyReference(_ points: [CGPoint], radius: Int) -> [CGPoint] {
        var result = points
        for _ in 0..<2 {
            var next: [CGPoint] = []; next.reserveCapacity(result.count)
            for index in result.indices {
                let lower = max(0, index - radius), upper = min(result.count - 1, index + radius)
                var x: CGFloat = 0, y: CGFloat = 0, total: CGFloat = 0
                for candidate in lower...upper {
                    let distance = abs(candidate - index), weight = CGFloat(radius + 1 - distance)
                    x += result[candidate].x * weight; y += result[candidate].y * weight; total += weight
                }
                next.append(CGPoint(x: x / total, y: y / total))
            }
            result = next
        }
        return result
    }

    private static func segmentLengths(_ points: [CGPoint]) -> [CGFloat] {
        guard points.count > 1 else { return [] }
        return (1..<points.count).map { distance(points[$0 - 1], points[$0]) }
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 1 }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func angleScore(_ a: CGVector, _ b: CGVector) -> CGFloat {
        let an = normalized(a), bn = normalized(b)
        let dot = max(-1, min(1, an.dx * bn.dx + an.dy * bn.dy))
        return clamp01(acos(dot) / (.pi / 2))
    }

    private static func vector(from a: CGPoint, to b: CGPoint) -> CGVector { CGVector(dx: b.x - a.x, dy: b.y - a.y) }
    private static func normalized(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        return length > 0.0001 ? CGVector(dx: vector.dx / length, dy: vector.dy / length) : CGVector(dx: 1, dy: 0)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    private static func lerp(_ a: CGPoint, _ b: CGPoint, weight: CGFloat) -> CGPoint {
        let w = clamp01(weight); return CGPoint(x: a.x + (b.x - a.x) * w, y: a.y + (b.y - a.y) * w)
    }
    private static func cubicPoint(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x, y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }
    private static func smoothstep(_ value: CGFloat) -> CGFloat { let x = clamp01(value); return x * x * (3 - 2 * x) }
    private static func clamp01(_ value: CGFloat) -> CGFloat { max(0, min(1, value)) }
}

private final class ContextMotionFilterCanvasView: UIView {
    enum Mode: Int { case original, filtered, sideBySide, overlay }
    let original: [CGPoint]
    var reference: [CGPoint] = [] { didSet { setNeedsDisplay() } }
    var filtered: [CGPoint] = [] { didSet { setNeedsDisplay() } }
    var edgeCount = 0 { didSet { setNeedsDisplay() } }
    var startConfidence: CGFloat = 0 { didSet { setNeedsDisplay() } }
    var endConfidence: CGFloat = 0 { didSet { setNeedsDisplay() } }
    var mode: Mode = .overlay { didSet { setNeedsDisplay() } }

    init(original: [CGPoint]) { self.original = original; super.init(frame: .zero); contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard !original.isEmpty else { return }
        UIColor.systemBackground.setFill(); UIRectFill(bounds)
        switch mode {
        case .original: drawSingle(points: original, color: .label, label: "A  Original Smooth", in: bounds)
        case .filtered: drawSingle(points: filtered, color: .systemBlue, label: "B  Motion Filter V2", in: bounds)
        case .sideBySide:
            let gap: CGFloat = 16, half = (bounds.width - gap) / 2
            drawSingle(points: original, color: .label, label: "A  Original", in: CGRect(x: 0, y: 0, width: half, height: bounds.height))
            drawSingle(points: filtered, color: .systemBlue, label: "B  Filtered", in: CGRect(x: half + gap, y: 0, width: half, height: bounds.height))
        case .overlay:
            let source = boundsForPoints(original + filtered + reference), target = bounds.insetBy(dx: 24, dy: 32)
            let transform = fittingTransform(source: source, into: target)
            drawPath(reference, transform: transform, color: .systemGray3, width: 1, dash: [4, 4])
            drawPath(original, transform: transform, color: .systemOrange, width: 2.1)
            drawPath(filtered, transform: transform, color: .systemBlue, width: 2.5)
            drawEdgeMarkers(transform: transform); drawLegend()
        }
    }

    private func drawSingle(points: [CGPoint], color: UIColor, label: String, in area: CGRect) {
        guard !points.isEmpty else { return }
        let transform = fittingTransform(source: boundsForPoints(original + filtered + reference), into: area.insetBy(dx: 18, dy: 32))
        drawPath(points, transform: transform, color: color, width: 2.5)
        label.draw(at: CGPoint(x: area.minX + 14, y: area.minY + 10), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])
    }

    private func drawPath(_ points: [CGPoint], transform: (CGPoint) -> CGPoint, color: UIColor, width: CGFloat, dash: [CGFloat] = []) {
        guard let first = points.first else { return }
        let path = UIBezierPath(); path.move(to: transform(first)); for point in points.dropFirst() { path.addLine(to: transform(point)) }
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke(); path.stroke()
    }

    private func drawEdgeMarkers(transform: (CGPoint) -> CGPoint) {
        guard edgeCount > 0, original.count > edgeCount * 2 else { return }
        let points = [(transform(original[edgeCount]), confidenceColor(startConfidence)), (transform(original[original.count - 1 - edgeCount]), confidenceColor(endConfidence))]
        for (point, color) in points { color.setFill(); UIBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill() }
    }

    private func confidenceColor(_ value: CGFloat) -> UIColor {
        if value > 0.66 { return .systemRed }; if value > 0.25 { return .systemPurple }; return .systemGray2
    }

    private func drawLegend() {
        "橙 原始".draw(at: CGPoint(x: 16, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.systemOrange])
        "蓝 过滤".draw(at: CGPoint(x: 76, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.systemBlue])
        "灰 Context=只做方向参考".draw(at: CGPoint(x: 136, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])
    }

    private func boundsForPoints(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() { minX = min(minX, point.x); maxX = max(maxX, point.x); minY = min(minY, point.y); maxY = max(maxY, point.y) }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func fittingTransform(source: CGRect, into target: CGRect) -> (CGPoint) -> CGPoint {
        let scale = min(target.width / max(1, source.width), target.height / max(1, source.height))
        let dx = target.midX - source.midX * scale, dy = target.midY - source.midY * scale
        return { point in CGPoint(x: point.x * scale + dx, y: point.y * scale + dy) }
    }
}

private final class PipelineCompareViewController: UIViewController {
    private let canvas: DualPathCanvas
    private let mode = UISegmentedControl(items: ["A", "B", "并排", "叠加"])
    init(current: [CGPoint], direct: [CGPoint], strokeWidth: CGFloat) { canvas = DualPathCanvas(a: current, b: direct, lineWidth: strokeWidth); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Compare from Smooth"; view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let label = UILabel(); label.text = "A = Smooth → Bézier → Stroke   ·   B = Smooth → Stroke"; label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabel; label.numberOfLines = 0
        mode.selectedSegmentIndex = 2; mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        canvas.translatesAutoresizingMaskIntoConstraints = false; canvas.backgroundColor = .systemBackground; canvas.layer.cornerRadius = 16; canvas.clipsToBounds = true
        let stack = UIStackView(arrangedSubviews: [label, mode, canvas]); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }
    @objc private func modeChanged() { canvas.mode = DualPathCanvas.Mode(rawValue: mode.selectedSegmentIndex) ?? .sideBySide }
}

private final class DualPathCanvas: UIView {
    enum Mode: Int { case a, b, sideBySide, overlay }
    private let a: [CGPoint], b: [CGPoint], baseLineWidth: CGFloat
    var mode: Mode = .sideBySide { didSet { setNeedsDisplay() } }
    init(a: [CGPoint], b: [CGPoint], lineWidth: CGFloat) { self.a = a; self.b = b; self.baseLineWidth = lineWidth; super.init(frame: .zero); contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        UIColor.systemBackground.setFill(); UIRectFill(bounds)
        switch mode {
        case .a: drawSingle(a, label: "A  Current", area: bounds, color: .label)
        case .b: drawSingle(b, label: "B  Direct", area: bounds, color: .label)
        case .sideBySide:
            let gap: CGFloat = 16, half = (bounds.width - gap) / 2
            drawSingle(a, label: "A  Current", area: CGRect(x: 0, y: 0, width: half, height: bounds.height), color: .label)
            drawSingle(b, label: "B  Direct", area: CGRect(x: half + gap, y: 0, width: half, height: bounds.height), color: .label)
        case .overlay:
            let transform = fittingTransform(source: pointsBounds(a + b), into: bounds.insetBy(dx: 24, dy: 30))
            drawPath(a, transform: transform, color: .systemOrange, alpha: 0.72); drawPath(b, transform: transform, color: .systemBlue, alpha: 0.58)
        }
    }
    private func drawSingle(_ points: [CGPoint], label: String, area: CGRect, color: UIColor) {
        let transform = fittingTransform(source: pointsBounds(a + b), into: area.insetBy(dx: 18, dy: 30)); drawPath(points, transform: transform, color: color, alpha: 0.88)
        label.draw(at: CGPoint(x: area.minX + 14, y: area.minY + 10), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])
    }
    private func drawPath(_ points: [CGPoint], transform: (point: (CGPoint) -> CGPoint, scale: CGFloat), color: UIColor, alpha: CGFloat) {
        guard let first = points.first else { return }
        let path = UIBezierPath(); path.move(to: transform.point(first)); for point in points.dropFirst() { path.addLine(to: transform.point(point)) }
        path.lineWidth = max(1, baseLineWidth * transform.scale); path.lineCapStyle = .round; path.lineJoinStyle = .round; color.withAlphaComponent(alpha).setStroke(); path.stroke()
    }
    private func pointsBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() { minX = min(minX, point.x); maxX = max(maxX, point.x); minY = min(minY, point.y); maxY = max(maxY, point.y) }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
    private func fittingTransform(source: CGRect, into target: CGRect) -> (point: (CGPoint) -> CGPoint, scale: CGFloat) {
        let scale = min(target.width / max(1, source.width), target.height / max(1, source.height)), dx = target.midX - source.midX * scale, dy = target.midY - source.midY * scale
        return (point: { p in CGPoint(x: p.x * scale + dx, y: p.y * scale + dy) }, scale: scale)
    }
}
