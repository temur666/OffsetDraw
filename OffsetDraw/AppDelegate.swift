import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

private enum MemoryExpansionVariant: CaseIterable {
    case restrained
    case expanded

    var title: String {
        switch self {
        case .restrained:
            return "Memory A"
        case .expanded:
            return "Memory B"
        }
    }

    var subtitle: String {
        switch self {
        case .restrained:
            return "96pt context · softer, more restrained expansion"
        case .expanded:
            return "112pt context · wider, more obvious remembered surroundings"
        }
    }

    var cropPadding: CGFloat {
        switch self {
        case .restrained: return 96
        case .expanded: return 112
        }
    }

    var wideMaskAlpha: CGFloat {
        switch self {
        case .restrained: return 0.36
        case .expanded: return 0.42
        }
    }

    var wideMaskBlur: Float {
        switch self {
        case .restrained: return 54
        case .expanded: return 64
        }
    }

    var sourceBlur: Float {
        switch self {
        case .restrained: return 10
        case .expanded: return 12
        }
    }

    var saturation: Float {
        switch self {
        case .restrained: return 0.40
        case .expanded: return 0.34
        }
    }

    var contrast: Float {
        switch self {
        case .restrained: return 0.85
        case .expanded: return 0.82
        }
    }

    var brightness: Float {
        switch self {
        case .restrained: return 0.04
        case .expanded: return 0.045
        }
    }

    var haloAlpha: CGFloat {
        switch self {
        case .restrained: return 0.15
        case .expanded: return 0.17
        }
    }
}

private enum MemoryExpansionRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(
        source: UIImage,
        canvasBounds: CGRect,
        points: [CGPoint],
        variant: MemoryExpansionVariant
    ) -> UIImage? {
        guard points.count > 2,
              canvasBounds.width > 0,
              canvasBounds.height > 0,
              let sourceCI = CIImage(image: source) else {
            return nil
        }

        let extent = sourceCI.extent
        let coreMaskImage = makeMask(
            bounds: canvasBounds,
            points: points,
            fillAlpha: 1
        )
        let wideMaskImage = makeMask(
            bounds: canvasBounds,
            points: points,
            fillAlpha: variant.wideMaskAlpha
        )

        guard let coreMaskCI = CIImage(image: coreMaskImage),
              let wideMaskCI = CIImage(image: wideMaskImage),
              let innerMask = blurred(coreMaskCI, radius: 12, extent: extent),
              let wideMask = blurred(wideMaskCI, radius: variant.wideMaskBlur, extent: extent),
              let blurredSource = blurred(sourceCI, radius: variant.sourceBlur, extent: extent) else {
            return nil
        }

        let clear = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: extent)

        let controls = CIFilter.colorControls()
        controls.inputImage = blurredSource
        controls.saturation = variant.saturation
        controls.contrast = variant.contrast
        controls.brightness = variant.brightness

        guard let fadedSource = controls.outputImage?.cropped(to: extent),
              let contextLayer = blend(
                source: fadedSource,
                background: clear,
                mask: wideMask
              ),
              let halo = warmHalo(
                mask: wideMask,
                clear: clear,
                extent: extent,
                alpha: variant.haloAlpha
              ) else {
            return nil
        }

        let expandedBase = contextLayer
            .composited(over: halo)
            .cropped(to: extent)

        guard let final = blend(
            source: sourceCI,
            background: expandedBase,
            mask: innerMask
        )?.cropped(to: extent),
              let fullCG = context.createCGImage(final, from: extent) else {
            return nil
        }

        let full = UIImage(cgImage: fullCG)
        let crop = bounds(for: points)
            .insetBy(dx: -variant.cropPadding, dy: -variant.cropPadding)
            .intersection(canvasBounds)
            .integral

        guard crop.width > 1,
              crop.height > 1,
              let cropped = full.cgImage?.cropping(to: crop) else {
            return full
        }

        return UIImage(cgImage: cropped)
    }

    private static func makeMask(
        bounds: CGRect,
        points: [CGPoint],
        fillAlpha: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            UIColor.white.withAlphaComponent(fillAlpha).setFill()
            closedPath(points).fill()
        }
    }

    private static func closedPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)

        if points.count > 2 {
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(
                    x: (previous.x + current.x) * 0.5,
                    y: (previous.y + current.y) * 0.5
                )
                path.addQuadCurve(to: midpoint, controlPoint: previous)
            }
        } else if let last = points.last {
            path.addLine(to: last)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        path.close()
        return path
    }

    private static func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
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

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func blurred(
        _ image: CIImage,
        radius: Float,
        extent: CGRect
    ) -> CIImage? {
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = radius
        return blur.outputImage?.cropped(to: extent)
    }

    private static func blend(
        source: CIImage,
        background: CIImage,
        mask: CIImage
    ) -> CIImage? {
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = source
        blend.backgroundImage = background
        blend.maskImage = mask
        return blend.outputImage
    }

    private static func warmHalo(
        mask: CIImage,
        clear: CIImage,
        extent: CGRect,
        alpha: CGFloat
    ) -> CIImage? {
        let yellow = CIImage(
            color: CIColor(color: UIColor.systemYellow.withAlphaComponent(alpha))
        ).cropped(to: extent)
        return blend(source: yellow, background: clear, mask: mask)?.cropped(to: extent)
    }
}

private final class MemoryExpansionComparisonViewController: UIViewController {
    private let source: UIImage
    private let canvasBounds: CGRect
    private let points: [CGPoint]

    init(source: UIImage, canvasBounds: CGRect, points: [CGPoint]) {
        self.source = source
        self.canvasBounds = canvasBounds
        self.points = points
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Memory Expansion"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        configureContent()
    }

    private func configureContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        scrollView.addSubview(stack)

        let intro = UILabel()
        intro.numberOfLines = 0
        intro.font = .systemFont(ofSize: 15)
        intro.textColor = .secondaryLabel
        intro.text = "Same paper · same region · only the outward memory context changes. Compare how much surrounding material should remain visible before it fades away."
        stack.addArrangedSubview(intro)

        for variant in MemoryExpansionVariant.allCases {
            stack.addArrangedSubview(makeCard(for: variant))
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func makeCard(for variant: MemoryExpansionVariant) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.text = variant.title

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.numberOfLines = 0
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabel
        subtitle.text = variant.subtitle

        let preview = UIImageView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.contentMode = .scaleAspectFit
        preview.clipsToBounds = false
        preview.image = MemoryExpansionRenderer.render(
            source: source,
            canvasBounds: canvasBounds,
            points: points,
            variant: variant
        )

        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(preview)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            preview.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            preview.heightAnchor.constraint(equalToConstant: 250),
            preview.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }
}

private enum MemoryExpansionPrototypeLauncher {
    private static let buttonIdentifier = "memory-expansion-compare-button"

    static func installIfNeeded() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            return
        }

        guard root.view.viewWithAccessibilityIdentifier(buttonIdentifier) == nil else {
            return
        }

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = buttonIdentifier
        var config = UIButton.Configuration.filled()
        config.title = "A/B"
        config.image = UIImage(systemName: "arrow.left.and.right")
        config.imagePadding = 5
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        config.cornerStyle = .capsule
        button.configuration = config

        button.addAction(
            UIAction { [weak root] _ in
                guard let root,
                      let input = comparisonInput(from: root) else {
                    return
                }

                let comparison = MemoryExpansionComparisonViewController(
                    source: input.source,
                    canvasBounds: input.bounds,
                    points: input.points
                )
                let navigation = UINavigationController(rootViewController: comparison)
                navigation.modalPresentationStyle = .pageSheet
                root.present(navigation, animated: true)
            },
            for: .touchUpInside
        )

        root.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: root.view.leadingAnchor, constant: 14),
            button.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.widthAnchor.constraint(equalToConstant: 66),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private static func comparisonInput(
        from viewController: UIViewController
    ) -> (source: UIImage, bounds: CGRect, points: [CGPoint])? {
        guard let paperImageView = mirroredValue(named: "paperImageView", from: viewController) as? UIImageView,
              paperImageView.bounds.width > 0,
              paperImageView.bounds.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let source = UIGraphicsImageRenderer(bounds: paperImageView.bounds, format: format).image { context in
            UIColor.clear.setFill()
            context.fill(paperImageView.bounds)
            paperImageView.layer.render(in: context.cgContext)
        }

        let points: [CGPoint]
        if let latest = mirroredValue(named: "latestRegion", from: viewController) as? [CGPoint],
           latest.count > 2 {
            points = latest
        } else {
            points = defaultRegion(in: paperImageView.bounds)
        }

        return (source, paperImageView.bounds, points)
    }

    private static func mirroredValue(named name: String, from object: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children where child.label == name {
                return unwrapOptional(child.value)
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private static func defaultRegion(in bounds: CGRect) -> [CGPoint] {
        let center = CGPoint(x: bounds.midX, y: bounds.midY * 0.98)
        let rx = bounds.width * 0.34
        let ry = bounds.height * 0.18
        let count = 42

        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count) * .pi * 2
            let wobble = 1 + 0.055 * sin(t * 5) + 0.025 * cos(t * 3)
            return CGPoint(
                x: center.x + cos(t) * rx * wobble,
                y: center.y + sin(t) * ry * wobble
            )
        }
    }
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.viewWithAccessibilityIdentifier(identifier) {
                return match
            }
        }
        return nil
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        DispatchQueue.main.async {
            MemoryExpansionPrototypeLauncher.installIfNeeded()
        }
    }
}
