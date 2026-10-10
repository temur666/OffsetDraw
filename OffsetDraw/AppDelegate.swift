import UIKit
import ObjectiveC.runtime

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GeometrySmoothCompareBootstrap.install()
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

// MARK: - Geometry Smooth Compare

private enum GeometrySmoothCompareBootstrap {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let originalSelector = #selector(UIViewController.viewDidLayoutSubviews)
        let replacementSelector = #selector(GeometryLabViewController.od_compare_viewDidLayoutSubviews)

        guard
            let originalMethod = class_getInstanceMethod(GeometryLabViewController.self, originalSelector),
            let replacementMethod = class_getInstanceMethod(GeometryLabViewController.self, replacementSelector)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension GeometryLabViewController {
    @objc fileprivate func od_compare_viewDidLayoutSubviews() {
        od_compare_viewDidLayoutSubviews()
        GeometrySmoothCompareSupport.installCompareButton(in: self)
    }
}

private enum GeometrySmoothCompareSupport {
    private static let buttonIdentifier = "geometry.smooth.compare.output"

    static func installCompareButton(in controller: GeometryLabViewController) {
        guard
            let smoothControls: UIStackView = reflectedValue(
                named: "smoothControls",
                from: controller,
                as: UIStackView.self
            ),
            !smoothControls.arrangedSubviews.contains(where: {
                $0.accessibilityIdentifier == buttonIdentifier
            })
        else {
            return
        }

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        smoothControls.addArrangedSubview(divider)

        let compareTitle = UILabel()
        compareTitle.text = "COMPARE OUTPUT"
        compareTitle.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        compareTitle.textColor = .label
        smoothControls.addArrangedSubview(compareTitle)

        let compareDetail = UILabel()
        compareDetail.text = "同一条 Smooth：A 继续经过 Bézier，B 直接生成 Stroke。"
        compareDetail.font = .systemFont(ofSize: 11)
        compareDetail.textColor = .secondaryLabel
        compareDetail.numberOfLines = 0
        smoothControls.addArrangedSubview(compareDetail)

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "Compare output"
        configuration.image = UIImage(systemName: "rectangle.split.2x1")
        configuration.imagePadding = 7
        configuration.cornerStyle = .medium

        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = buttonIdentifier
        button.addAction(
            UIAction { [weak controller] _ in
                guard let controller else { return }
                presentCompare(from: controller)
            },
            for: .touchUpInside
        )
        smoothControls.addArrangedSubview(button)
    }

    private static func presentCompare(from controller: GeometryLabViewController) {
        guard
            let canvas: UIView = reflectedValue(named: "canvas", from: controller, as: UIView.self),
            let smoothed: [CGPoint] = reflectedValue(
                named: "latestSmoothed",
                from: canvas,
                as: [CGPoint].self
            ),
            smoothed.count > 1
        else {
            let alert = UIAlertController(
                title: "先画一笔",
                message: "在 RAW 里画完一笔后，再比较同一份 Smooth 的两条输出路径。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            controller.present(alert, animated: true)
            return
        }

        let committed = reflectedSegments(named: "committedSegments", from: canvas)
        let active = reflectedSegments(named: "activeSegments", from: canvas)
        let segments = committed + active

        guard !segments.isEmpty else {
            let alert = UIAlertController(
                title: "还没有 Bézier 输出",
                message: "先完成一笔，再打开 Compare。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            controller.present(alert, animated: true)
            return
        }

        let width: CGFloat = reflectedValue(
            named: "vectorStrokeWidth",
            from: canvas,
            as: CGFloat.self
        ) ?? 12

        let currentCenterline = sampleBezierCenterline(segments, samplesPerSegment: 16)
        let directCenterline = sampleSmoothSpline(smoothed, samplesPerSegment: 16)

        let compare = GeometrySmoothCompareViewController(
            currentCenterline: currentCenterline,
            directCenterline: directCenterline,
            strokeWidth: width
        )
        let navigation = UINavigationController(rootViewController: compare)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        controller.present(navigation, animated: true)
    }

    private static func reflectedValue<T>(
        named name: String,
        from object: Any,
        as type: T.Type
    ) -> T? {
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

    private static func reflectedSegments(named name: String, from object: Any) -> [CompareBezierSegment] {
        guard let value = reflectedAnyValue(named: name, from: object) else { return [] }
        let collection = Mirror(reflecting: value)

        return collection.children.compactMap { element in
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

            guard
                let start,
                let control1,
                let control2,
                let end
            else {
                return nil
            }

            return CompareBezierSegment(
                start: start,
                control1: control1,
                control2: control2,
                end: end
            )
        }
    }

    private static func sampleBezierCenterline(
        _ segments: [CompareBezierSegment],
        samplesPerSegment: Int
    ) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(segments.count * samplesPerSegment + 1)

        for (segmentIndex, segment) in segments.enumerated() {
            for step in 0...samplesPerSegment {
                if segmentIndex > 0 && step == 0 { continue }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(
                    cubicPoint(
                        start: segment.start,
                        control1: segment.control1,
                        control2: segment.control2,
                        end: segment.end,
                        t: t
                    )
                )
            }
        }
        return result
    }

    private static func sampleSmoothSpline(
        _ points: [CGPoint],
        samplesPerSegment: Int
    ) -> [CGPoint] {
        guard points.count > 1 else { return points }
        if points.count == 2 { return points }

        var result: [CGPoint] = []
        result.reserveCapacity((points.count - 1) * samplesPerSegment + 1)

        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            for step in 0...samplesPerSegment {
                if index > 0 && step == 0 { continue }
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(
                    cubicPoint(
                        start: p1,
                        control1: control1,
                        control2: control2,
                        end: p2,
                        t: t
                    )
                )
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
        let oneMinusT = 1 - t
        let a = oneMinusT * oneMinusT * oneMinusT
        let b = 3 * oneMinusT * oneMinusT * t
        let c = 3 * oneMinusT * t * t
        let d = t * t * t

        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}

private struct CompareBezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private final class GeometrySmoothCompareViewController: UIViewController {
    private let compareCanvas: GeometrySmoothCompareCanvasView
    private let modeControl = UISegmentedControl(items: ["A", "B", "并排", "叠加"])
    private let explanation = UILabel()

    init(currentCenterline: [CGPoint], directCenterline: [CGPoint], strokeWidth: CGFloat) {
        compareCanvas = GeometrySmoothCompareCanvasView(
            currentCenterline: currentCenterline,
            directCenterline: directCenterline,
            strokeWidth: strokeWidth
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compare from Smooth"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        let intro = UILabel()
        intro.text = "同一条 Smooth 输入，只改变后半段 pipeline。"
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        modeControl.selectedSegmentIndex = 2
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        explanation.font = .systemFont(ofSize: 12, weight: .medium)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0

        compareCanvas.translatesAutoresizingMaskIntoConstraints = false
        compareCanvas.backgroundColor = .systemBackground
        compareCanvas.layer.cornerRadius = 16
        compareCanvas.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [intro, modeControl, explanation, compareCanvas])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            compareCanvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        updateMode()
    }

    @objc private func modeChanged() {
        updateMode()
    }

    private func updateMode() {
        let mode = GeometrySmoothCompareCanvasView.Mode(rawValue: modeControl.selectedSegmentIndex) ?? .sideBySide
        compareCanvas.mode = mode

        switch mode {
        case .current:
            explanation.text = "A · Current: Smooth → Bézier → Stroke"
        case .direct:
            explanation.text = "B · Bypass: Smooth → Stroke"
        case .sideBySide:
            explanation.text = "左 A = 当前链路 · 右 B = 跳过 Bézier。两边使用同一条输入和同一笔宽。"
        case .overlay:
            explanation.text = "叠加：橙色 = A 当前链路 · 蓝色 = B Smooth 直出。偏离的位置就是 Bézier 后发生的变化。"
        }
    }
}

private final class GeometrySmoothCompareCanvasView: UIView {
    enum Mode: Int {
        case current
        case direct
        case sideBySide
        case overlay
    }

    var mode: Mode = .sideBySide {
        didSet { setNeedsDisplay() }
    }

    private let currentCenterline: [CGPoint]
    private let directCenterline: [CGPoint]
    private let strokeWidth: CGFloat

    init(currentCenterline: [CGPoint], directCenterline: [CGPoint], strokeWidth: CGFloat) {
        self.currentCenterline = currentCenterline
        self.directCenterline = directCenterline
        self.strokeWidth = strokeWidth
        super.init(frame: .zero)
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.systemBackground.setFill()
        context.fill(bounds)

        switch mode {
        case .current:
            drawSingle(
                centerline: currentCenterline,
                in: bounds.insetBy(dx: 24, dy: 28),
                fill: UIColor.label,
                label: "A  Smooth → Bézier → Stroke",
                context: context
            )

        case .direct:
            drawSingle(
                centerline: directCenterline,
                in: bounds.insetBy(dx: 24, dy: 28),
                fill: UIColor.label,
                label: "B  Smooth → Stroke",
                context: context
            )

        case .sideBySide:
            let gap: CGFloat = 18
            let halfWidth = (bounds.width - gap) / 2
            let left = CGRect(x: 0, y: 0, width: halfWidth, height: bounds.height)
                .insetBy(dx: 16, dy: 28)
            let right = CGRect(x: halfWidth + gap, y: 0, width: halfWidth, height: bounds.height)
                .insetBy(dx: 16, dy: 28)

            drawSingle(
                centerline: currentCenterline,
                in: left,
                fill: UIColor.label,
                label: "A  Current",
                context: context
            )
            drawSingle(
                centerline: directCenterline,
                in: right,
                fill: UIColor.label,
                label: "B  Direct",
                context: context
            )

            context.setStrokeColor(UIColor.separator.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: bounds.midX, y: 18))
            context.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY - 18))
            context.strokePath()

        case .overlay:
            let target = bounds.insetBy(dx: 24, dy: 28)
            let sourceBounds = unionBounds(currentCenterline, directCenterline)
            guard sourceBounds.width > 0, sourceBounds.height > 0 else { return }

            let transform = fittingTransform(source: sourceBounds, into: target)
            drawStroke(
                centerline: currentCenterline,
                transform: transform,
                fill: .systemOrange,
                alpha: 0.72,
                context: context
            )
            drawStroke(
                centerline: directCenterline,
                transform: transform,
                fill: .systemBlue,
                alpha: 0.58,
                context: context
            )

            drawLabel("A Current", at: CGPoint(x: 18, y: 12), color: .systemOrange)
            drawLabel("B Direct", at: CGPoint(x: 104, y: 12), color: .systemBlue)
        }
    }

    private func drawSingle(
        centerline: [CGPoint],
        in target: CGRect,
        fill: UIColor,
        label: String,
        context: CGContext
    ) {
        guard let sourceBounds = boundsForPoints(centerline), sourceBounds.width > 0, sourceBounds.height > 0 else {
            return
        }
        let transform = fittingTransform(source: sourceBounds, into: target)
        drawStroke(
            centerline: centerline,
            transform: transform,
            fill: fill,
            alpha: 0.88,
            context: context
        )
        drawLabel(label, at: CGPoint(x: target.minX, y: 10), color: .secondaryLabel)
    }

    private func drawStroke(
        centerline: [CGPoint],
        transform: (point: (CGPoint) -> CGPoint, scale: CGFloat),
        fill: UIColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        let mapped = centerline.map(transform.point)
        guard mapped.count > 1 else { return }

        let width = max(1, strokeWidth * transform.scale)
        let outline = vectorOutlinePath(centerline: mapped, width: width)
        fill.withAlphaComponent(alpha).setFill()
        outline.fill()

        if let first = mapped.first, let last = mapped.last {
            context.setFillColor(fill.withAlphaComponent(alpha).cgColor)
            let radius = width / 2
            context.fillEllipse(
                in: CGRect(x: first.x - radius, y: first.y - radius, width: width, height: width)
            )
            context.fillEllipse(
                in: CGRect(x: last.x - radius, y: last.y - radius, width: width, height: width)
            )
        }
    }

    private func fittingTransform(
        source: CGRect,
        into target: CGRect
    ) -> (point: (CGPoint) -> CGPoint, scale: CGFloat) {
        let safeWidth = max(source.width, 1)
        let safeHeight = max(source.height, 1)
        let scale = min(target.width / safeWidth, target.height / safeHeight)
        let drawnWidth = source.width * scale
        let drawnHeight = source.height * scale
        let offsetX = target.midX - drawnWidth / 2 - source.minX * scale
        let offsetY = target.midY - drawnHeight / 2 - source.minY * scale

        return (
            point: { point in
                CGPoint(
                    x: point.x * scale + offsetX,
                    y: point.y * scale + offsetY
                )
            },
            scale: scale
        )
    }

    private func unionBounds(_ a: [CGPoint], _ b: [CGPoint]) -> CGRect {
        let combined = a + b
        return boundsForPoints(combined) ?? .zero
    }

    private func boundsForPoints(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let padding = max(12, strokeWidth)
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(1, maxX - minX + padding * 2),
            height: max(1, maxY - minY + padding * 2)
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

    private func drawLabel(_ text: String, at point: CGPoint, color: UIColor) {
        text.draw(
            at: point,
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: color
            ]
        )
    }
}
