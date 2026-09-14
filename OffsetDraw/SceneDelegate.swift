import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

private enum PaperTool: Int {
    case pen
    case highlighter
    case region
}

private struct PaperStroke {
    let tool: PaperTool
    let points: [CGPoint]
}

private enum MemoEdgeEffect: CaseIterable {
    case soft
    case paper
    case memory

    var title: String {
        switch self {
        case .soft: return "Soft"
        case .paper: return "Paper"
        case .memory: return "Memory"
        }
    }

    var subtitle: String {
        switch self {
        case .soft:
            return "Clean double feather · restrained and office-friendly"
        case .paper:
            return "Fibrous broken edge · feels lifted from the physical page"
        case .memory:
            return "Soft focus context + warm haze · like a recalled fragment"
        }
    }

    var symbolName: String {
        switch self {
        case .soft: return "circle.lefthalf.filled"
        case .paper: return "doc.text.image"
        case .memory: return "sparkles"
        }
    }

    var cropPadding: CGFloat {
        switch self {
        case .soft: return 44
        case .paper: return 48
        case .memory: return 72
        }
    }
}

private final class PaperAnnotationView: UIView {
    var selectedTool: PaperTool = .region
    var onRegionCommitted: (([CGPoint]) -> Void)?

    private var strokes: [PaperStroke] = []
    private var region: [CGPoint]?
    private var active: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    func clearAll() {
        strokes.removeAll()
        region = nil
        active.removeAll()
        setNeedsDisplay()
    }

    func clearRegion() {
        region = nil
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard (event?.allTouches?.count ?? touches.count) == 1,
              let touch = touches.first else {
            active.removeAll()
            return
        }
        active = [touch.location(in: self)]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard (event?.allTouches?.count ?? touches.count) == 1,
              let touch = touches.first else {
            active.removeAll()
            setNeedsDisplay()
            return
        }

        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: self)
            if let last = active.last,
               hypot(point.x - last.x, point.y - last.y) < 1.5 {
                continue
            }
            active.append(point)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !active.isEmpty else { return }

        switch selectedTool {
        case .pen, .highlighter:
            if active.count > 1 {
                strokes.append(PaperStroke(tool: selectedTool, points: active))
            }
        case .region:
            let regionBounds = Self.bounds(for: active)
            if regionBounds.width > 24, regionBounds.height > 24 {
                region = active
                onRegionCommitted?(active)
            }
        }

        active.removeAll()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        active.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for stroke in strokes {
            draw(stroke, in: context)
        }

        if let region {
            drawDimOutside(region, in: context)
            drawRegion(region, closed: true, alpha: 0.8, in: context)
        }

        guard active.count > 1 else { return }
        switch selectedTool {
        case .pen, .highlighter:
            draw(PaperStroke(tool: selectedTool, points: active), in: context)
        case .region:
            drawRegion(active, closed: false, alpha: 0.72, in: context)
        }
    }

    static func closedPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = smoothPath(points)
        path.close()
        return path
    }

    static func bounds(for points: [CGPoint]) -> CGRect {
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

    private func draw(_ stroke: PaperStroke, in context: CGContext) {
        guard stroke.points.count > 1 else { return }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch stroke.tool {
        case .pen:
            context.setBlendMode(.normal)
            context.setStrokeColor(UIColor.label.withAlphaComponent(0.92).cgColor)
            context.setLineWidth(3.2)
        case .highlighter:
            context.setBlendMode(.multiply)
            context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.34).cgColor)
            context.setLineWidth(19)
        case .region:
            break
        }

        strokePath(stroke.points, in: context)
        context.restoreGState()
    }

    private func drawRegion(
        _ points: [CGPoint],
        closed: Bool,
        alpha: CGFloat,
        in context: CGContext
    ) {
        guard points.count > 1 else { return }
        let path = Self.smoothPath(points)
        if closed { path.close() }

        context.saveGState()
        context.setBlendMode(.multiply)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(alpha * 0.28).cgColor)
        context.setLineWidth(25)
        context.addPath(path.cgPath)
        context.strokePath()

        context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(alpha * 0.62).cgColor)
        context.setLineWidth(13)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private func drawDimOutside(_ points: [CGPoint], in context: CGContext) {
        guard points.count > 2 else { return }
        let outside = UIBezierPath(rect: bounds)
        outside.append(Self.closedPath(points))
        outside.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.14).setFill()
        outside.fill()
    }

    private func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func smoothPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 2 else {
            if let last = points.last {
                path.addLine(to: last)
            }
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) * 0.5,
                y: (previous.y + current.y) * 0.5
            )
            path.addQuadCurve(to: midpoint, controlPoint: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }
}

private enum MemoEffectRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(
        source: UIImage,
        canvasBounds: CGRect,
        points: [CGPoint],
        style: MemoEdgeEffect
    ) -> UIImage? {
        guard points.count > 2,
              canvasBounds.width > 0,
              canvasBounds.height > 0,
              let sourceCI = CIImage(image: source) else {
            return nil
        }

        let extent = sourceCI.extent
        let coreMask = makeMask(
            bounds: canvasBounds,
            points: points,
            fillAlpha: 1,
            paperFibers: style == .paper
        )
        guard let coreMaskCI = CIImage(image: coreMask) else { return nil }

        let clear = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: extent)

        let output: CIImage?
        switch style {
        case .soft:
            output = renderSoft(
                source: sourceCI,
                mask: coreMaskCI,
                clear: clear,
                extent: extent
            )
        case .paper:
            output = renderPaper(
                source: sourceCI,
                mask: coreMaskCI,
                clear: clear,
                extent: extent
            )
        case .memory:
            output = renderMemory(
                source: sourceCI,
                canvasBounds: canvasBounds,
                points: points,
                coreMask: coreMaskCI,
                clear: clear,
                extent: extent
            )
        }

        guard let output,
              let fullCG = context.createCGImage(output, from: extent) else {
            return nil
        }

        let full = UIImage(cgImage: fullCG)
        let crop = PaperAnnotationView.bounds(for: points)
            .insetBy(dx: -style.cropPadding, dy: -style.cropPadding)
            .intersection(canvasBounds)
            .integral

        guard crop.width > 1,
              crop.height > 1,
              let cropped = full.cgImage?.cropping(to: crop) else {
            return full
        }

        return UIImage(cgImage: cropped)
    }

    private static func renderSoft(
        source: CIImage,
        mask: CIImage,
        clear: CIImage,
        extent: CGRect
    ) -> CIImage? {
        guard let inner = blurred(mask, radius: 9, extent: extent),
              let outerBase = translucentMask(mask, alpha: 0.28),
              let outer = blurred(outerBase, radius: 28, extent: extent),
              let outerLayer = blend(source: source, background: clear, mask: outer),
              let coreLayer = blend(source: source, background: outerLayer, mask: inner) else {
            return nil
        }
        return coreLayer.cropped(to: extent)
    }

    private static func renderPaper(
        source: CIImage,
        mask: CIImage,
        clear: CIImage,
        extent: CGRect
    ) -> CIImage? {
        guard let fiberMask = blurred(mask, radius: 7, extent: extent),
              let softBase = translucentMask(mask, alpha: 0.18),
              let softEdge = blurred(softBase, radius: 20, extent: extent),
              let warm = warmHalo(mask: softEdge, clear: clear, extent: extent, alpha: 0.055),
              let underlay = blend(source: source, background: warm, mask: softEdge),
              let final = blend(source: source, background: underlay, mask: fiberMask) else {
            return nil
        }
        return final.cropped(to: extent)
    }

    private static func renderMemory(
        source: CIImage,
        canvasBounds: CGRect,
        points: [CGPoint],
        coreMask: CIImage,
        clear: CIImage,
        extent: CGRect
    ) -> CIImage? {
        let wideMaskImage = makeMask(
            bounds: canvasBounds,
            points: points,
            fillAlpha: 0.32,
            paperFibers: false
        )
        guard let wideMaskCI = CIImage(image: wideMaskImage),
              let wideMask = blurred(wideMaskCI, radius: 42, extent: extent),
              let innerMask = blurred(coreMask, radius: 12, extent: extent),
              let blurredSource = blurred(source, radius: 8, extent: extent) else {
            return nil
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = blurredSource
        controls.saturation = 0.42
        controls.contrast = 0.86
        controls.brightness = 0.035
        guard let fadedSource = controls.outputImage?.cropped(to: extent),
              let contextLayer = blend(source: fadedSource, background: clear, mask: wideMask),
              let halo = warmHalo(mask: wideMask, clear: clear, extent: extent, alpha: 0.13) else {
            return nil
        }

        let base = contextLayer.composited(over: halo).cropped(to: extent)
        guard let final = blend(source: source, background: base, mask: innerMask) else {
            return nil
        }
        return final.cropped(to: extent)
    }

    private static func makeMask(
        bounds: CGRect,
        points: [CGPoint],
        fillAlpha: CGFloat,
        paperFibers: Bool
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { renderer in
            UIColor.white.withAlphaComponent(fillAlpha).setFill()
            PaperAnnotationView.closedPath(points).fill()

            guard paperFibers else { return }
            let cg = renderer.cgContext
            cg.saveGState()
            cg.setBlendMode(.clear)

            for (index, point) in points.enumerated() where index % 3 == 0 {
                let phase = CGFloat(index)
                let dx = sin(phase * 1.71) * 6
                let dy = cos(phase * 1.29) * 5
                let width = 1.8 + abs(sin(phase * 0.73)) * 4.5
                let height = 1.2 + abs(cos(phase * 0.91)) * 3.2
                let fiber = CGRect(
                    x: point.x + dx - width * 0.5,
                    y: point.y + dy - height * 0.5,
                    width: width,
                    height: height
                )
                cg.fillEllipse(in: fiber)
            }

            cg.restoreGState()
        }
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

    private static func translucentMask(_ mask: CIImage, alpha: CGFloat) -> CIImage? {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = mask
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: alpha)
        return matrix.outputImage
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

private final class PaperToolButton: UIButton {
    let tool: PaperTool?

    init(title: String, symbol: String, tool: PaperTool?) {
        self.tool = tool
        super.init(frame: .zero)

        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .top
        config.imagePadding = 7
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: 5,
            bottom: 10,
            trailing: 5
        )
        configuration = config
        clipsToBounds = true
        layer.cornerRadius = 18
    }

    required init?(coder: NSCoder) { nil }

    func setActive(_ active: Bool) {
        guard var config = configuration else { return }
        config.baseForegroundColor = active ? .systemBlue : .secondaryLabel
        config.background.backgroundColor = active
            ? UIColor.systemBlue.withAlphaComponent(0.11)
            : .clear
        configuration = config
    }
}

private final class EffectPreviewCard: UIView {
    let effect: MemoEdgeEffect

    init(effect: MemoEdgeEffect, image: UIImage?) {
        self.effect = effect
        super.init(frame: .zero)

        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)

        let symbol = UIImageView(image: UIImage(systemName: effect.symbolName))
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.tintColor = .label
        symbol.contentMode = .scaleAspectFit

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = effect.title
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = effect.subtitle
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 2

        let preview = UIImageView(image: image)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.contentMode = .scaleAspectFit
        preview.clipsToBounds = false

        [symbol, title, subtitle, preview].forEach(addSubview)

        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            symbol.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            symbol.widthAnchor.constraint(equalToConstant: 24),
            symbol.heightAnchor.constraint(equalToConstant: 24),

            title.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: symbol.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),

            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            subtitle.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 10),

            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            preview.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            preview.heightAnchor.constraint(equalToConstant: 190),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class MemoEffectComparisonViewController: UIViewController {
    private let source: UIImage
    private let canvasBounds: CGRect
    private let points: [CGPoint]

    init(source: UIImage, canvasBounds: CGRect, points: [CGPoint]) {
        self.source = source
        self.canvasBounds = canvasBounds
        self.points = points
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Memo Edge Effects"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        scroll.addSubview(stack)

        let intro = UILabel()
        intro.text = "Same paper. Same hand-drawn region. Only the edge treatment changes."
        intro.font = .systemFont(ofSize: 15)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        stack.addArrangedSubview(intro)

        for effect in MemoEdgeEffect.allCases {
            let image = MemoEffectRenderer.render(
                source: source,
                canvasBounds: canvasBounds,
                points: points,
                style: effect
            )
            stack.addArrangedSubview(EffectPreviewCard(effect: effect, image: image))
        }

        let footer = UILabel()
        footer.text = "Soft is the safest default. Paper keeps more physical texture. Memory is deliberately more emotional and atmospheric."
        footer.font = .systemFont(ofSize: 13)
        footer.textColor = .tertiaryLabel
        footer.numberOfLines = 0
        stack.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }
}

private final class PaperMemoDemoViewController: UIViewController,
    UIScrollViewDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UITextFieldDelegate {

    private let scrollView = UIScrollView()
    private let paperContainer = UIView()
    private let paperImageView = UIImageView()
    private let annotationView = PaperAnnotationView()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let photoButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)

    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let penButton = PaperToolButton(title: "Pen", symbol: "pencil.tip", tool: .pen)
    private let highlighterButton = PaperToolButton(title: "Highlighter", symbol: "highlighter", tool: .highlighter)
    private let regionButton = PaperToolButton(title: "Region", symbol: "scribble.variable", tool: .region)
    private let noteButton = PaperToolButton(title: "Note", symbol: "note.text", tool: nil)

    private let memoCard = UIView()
    private let memoTitle = UILabel()
    private let memoMenu = UIButton(type: .system)
    private let memoPreview = UIImageView()
    private let noteField = UITextField()
    private let saveButton = UIButton(type: .system)

    private var sourceImage = PaperMemoDemoViewController.makeSamplePaperImage()
    private var needsPaperLayout = true
    private var latestRegion: [CGPoint]?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.105, green: 0.102, blue: 0.098, alpha: 1)
        configureCanvas()
        configureHeader()
        configureToolbar()
        configureMemoCard()
        setImage(sourceImage)
        select(.region)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if needsPaperLayout {
            layoutPaper()
            needsPaperLayout = false
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        paperContainer
    }

    private func configureCanvas() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        view.addSubview(scrollView)

        paperContainer.backgroundColor = .systemBackground
        paperContainer.layer.cornerRadius = 18
        paperContainer.layer.cornerCurve = .continuous
        paperContainer.layer.shadowColor = UIColor.black.cgColor
        paperContainer.layer.shadowOpacity = 0.28
        paperContainer.layer.shadowRadius = 18
        paperContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        scrollView.addSubview(paperContainer)

        paperImageView.contentMode = .scaleAspectFill
        paperImageView.clipsToBounds = true
        paperImageView.layer.cornerRadius = 18
        paperImageView.layer.cornerCurve = .continuous
        paperContainer.addSubview(paperImageView)

        annotationView.clipsToBounds = true
        annotationView.layer.cornerRadius = 18
        annotationView.layer.cornerCurve = .continuous
        annotationView.onRegionCommitted = { [weak self] points in
            self?.latestRegion = points
            self?.showMemo(points)
        }
        paperContainer.addSubview(annotationView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureHeader() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Project Notes"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Today · 1 page"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        photoButton.translatesAutoresizingMaskIntoConstraints = false
        photoButton.configuration = roundHeaderButton(symbol: "camera.fill")
        photoButton.addTarget(self, action: #selector(choosePhoto), for: .touchUpInside)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.configuration = roundHeaderButton(symbol: "ellipsis")
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)

        [titleLabel, subtitleLabel, photoButton, moreButton].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            photoButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            photoButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            photoButton.widthAnchor.constraint(equalToConstant: 42),
            photoButton.heightAnchor.constraint(equalToConstant: 42),
            moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            moreButton.widthAnchor.constraint(equalToConstant: 42),
            moreButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func roundHeaderButton(symbol: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        config.cornerStyle = .capsule
        return config
    }

    private func configureToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 30
        toolbar.layer.cornerCurve = .continuous
        toolbar.clipsToBounds = true
        view.addSubview(toolbar)

        let stack = UIStackView(arrangedSubviews: [
            penButton,
            highlighterButton,
            regionButton,
            noteButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        toolbar.contentView.addSubview(stack)

        [penButton, highlighterButton, regionButton].forEach {
            $0.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        }
        noteButton.addTarget(self, action: #selector(noteTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 86),
            stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: toolbar.contentView.bottomAnchor, constant: -6)
        ])
    }

    private func configureMemoCard() {
        memoCard.translatesAutoresizingMaskIntoConstraints = false
        memoCard.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.98)
        memoCard.layer.cornerRadius = 28
        memoCard.layer.cornerCurve = .continuous
        memoCard.layer.shadowColor = UIColor.black.cgColor
        memoCard.layer.shadowOpacity = 0.22
        memoCard.layer.shadowRadius = 24
        memoCard.layer.shadowOffset = CGSize(width: 0, height: 12)
        memoCard.isHidden = true
        view.addSubview(memoCard)

        memoTitle.translatesAutoresizingMaskIntoConstraints = false
        memoTitle.text = "✦  Memo"
        memoTitle.font = .systemFont(ofSize: 17, weight: .semibold)

        memoMenu.translatesAutoresizingMaskIntoConstraints = false
        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "ellipsis")
        menuConfig.baseForegroundColor = .secondaryLabel
        memoMenu.configuration = menuConfig
        memoMenu.addTarget(self, action: #selector(removeRegion), for: .touchUpInside)

        memoPreview.translatesAutoresizingMaskIntoConstraints = false
        memoPreview.contentMode = .scaleAspectFit
        memoPreview.clipsToBounds = false

        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.placeholder = "Add a note…"
        noteField.font = .systemFont(ofSize: 16)
        noteField.returnKeyType = .done
        noteField.delegate = self

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        var saveConfig = UIButton.Configuration.filled()
        saveConfig.title = "Save to Memo"
        saveConfig.baseForegroundColor = .white
        saveConfig.baseBackgroundColor = UIColor(
            red: 0.18,
            green: 0.18,
            blue: 0.21,
            alpha: 1
        )
        saveConfig.cornerStyle = .capsule
        saveConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: 18,
            bottom: 12,
            trailing: 18
        )
        saveButton.configuration = saveConfig
        saveButton.addTarget(self, action: #selector(saveMemo), for: .touchUpInside)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.45)

        [memoTitle, memoMenu, memoPreview, divider, noteField, saveButton].forEach(memoCard.addSubview)

        NSLayoutConstraint.activate([
            memoCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            memoCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            memoCard.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -12),
            memoCard.heightAnchor.constraint(equalToConstant: 286),

            memoTitle.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 20),
            memoTitle.topAnchor.constraint(equalTo: memoCard.topAnchor, constant: 16),
            memoMenu.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -12),
            memoMenu.centerYAnchor.constraint(equalTo: memoTitle.centerYAnchor),
            memoMenu.widthAnchor.constraint(equalToConstant: 40),
            memoMenu.heightAnchor.constraint(equalToConstant: 40),

            memoPreview.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 18),
            memoPreview.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -18),
            memoPreview.topAnchor.constraint(equalTo: memoTitle.bottomAnchor, constant: 8),
            memoPreview.heightAnchor.constraint(equalToConstant: 156),

            divider.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: memoPreview.bottomAnchor, constant: 6),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            noteField.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 20),
            noteField.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            noteField.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: memoCard.bottomAnchor, constant: -14),
            saveButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func layoutPaper() {
        guard scrollView.bounds.width > 0,
              scrollView.bounds.height > 0 else {
            return
        }

        scrollView.setZoomScale(1, animated: false)
        let topInset: CGFloat = 94
        let bottomInset: CGFloat = 112
        let horizontalInset: CGFloat = 16
        let available = CGSize(
            width: scrollView.bounds.width - horizontalInset * 2,
            height: max(240, scrollView.bounds.height - topInset - bottomInset)
        )

        let aspect = sourceImage.size.width / max(sourceImage.size.height, 1)
        var size = CGSize(
            width: available.width,
            height: available.width / aspect
        )

        if size.height > available.height {
            size.height = available.height
            size.width = available.height * aspect
        }

        let origin = CGPoint(
            x: (scrollView.bounds.width - size.width) * 0.5,
            y: topInset + max(0, (available.height - size.height) * 0.5)
        )

        paperContainer.frame = CGRect(origin: origin, size: size)
        paperImageView.frame = paperContainer.bounds
        annotationView.frame = paperContainer.bounds
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: max(scrollView.bounds.height, paperContainer.frame.maxY + bottomInset)
        )
    }

    private func setImage(_ image: UIImage) {
        sourceImage = normalizedAndDownscaled(image)
        paperImageView.image = sourceImage
        annotationView.clearAll()
        latestRegion = nil
        memoCard.isHidden = true
        memoPreview.image = nil
        noteField.text = nil
        needsPaperLayout = true
        view.setNeedsLayout()
    }

    private func select(_ tool: PaperTool) {
        annotationView.selectedTool = tool
        penButton.setActive(tool == .pen)
        highlighterButton.setActive(tool == .highlighter)
        regionButton.setActive(tool == .region)
    }

    private func showMemo(_ points: [CGPoint]) {
        guard let source = paperSnapshot(),
              let preview = MemoEffectRenderer.render(
                source: source,
                canvasBounds: annotationView.bounds,
                points: points,
                style: .soft
              ) else {
            return
        }

        memoPreview.image = preview
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if memoCard.isHidden {
            memoCard.isHidden = false
            memoCard.alpha = 0
            memoCard.transform = CGAffineTransform(
                translationX: 0,
                y: 28
            ).scaledBy(x: 0.98, y: 0.98)
        }

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.4,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.memoCard.alpha = 1
            self.memoCard.transform = .identity
        }
    }

    private func paperSnapshot() -> UIImage? {
        guard paperImageView.bounds.width > 0,
              paperImageView.bounds.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(
            bounds: paperImageView.bounds,
            format: format
        ).image { renderer in
            UIColor.clear.setFill()
            renderer.fill(paperImageView.bounds)
            paperImageView.layer.render(in: renderer.cgContext)
        }
    }

    private func defaultComparisonRegion() -> [CGPoint] {
        let bounds = annotationView.bounds.insetBy(dx: 42, dy: 42)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rx = bounds.width * 0.38
        let ry = bounds.height * 0.22
        let count = 72

        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count) * .pi * 2
            let wobble = 1 + sin(t * 3.1) * 0.055 + cos(t * 5.2) * 0.025
            return CGPoint(
                x: center.x + cos(t) * rx * wobble,
                y: center.y + sin(t) * ry * wobble
            )
        }
    }

    private func normalizedAndDownscaled(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2400
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    @objc private func toolTapped(_ sender: PaperToolButton) {
        guard let tool = sender.tool else { return }
        select(tool)
    }

    @objc private func noteTapped() {
        guard !memoCard.isHidden else {
            let alert = UIAlertController(
                title: "Circle something first",
                message: "Use Region to loosely circle a part of the paper. It becomes the image inside a Memo.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        noteField.becomeFirstResponder()
    }

    @objc private func choosePhoto() {
        let sheet = UIAlertController(
            title: "Paper note",
            message: nil,
            preferredStyle: .actionSheet
        )

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentPicker(.camera)
            })
        }

        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPicker(.photoLibrary)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func showMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Compare Memo Effects", style: .default) { [weak self] _ in
            self?.showEffectComparison()
        })

        sheet.addAction(UIAlertAction(title: "Reset annotations", style: .destructive) { [weak self] _ in
            self?.annotationView.clearAll()
            self?.memoCard.isHidden = true
            self?.latestRegion = nil
        })

        sheet.addAction(UIAlertAction(title: "Use sample paper", style: .default) { [weak self] _ in
            self?.setImage(Self.makeSamplePaperImage())
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func showEffectComparison() {
        guard let source = paperSnapshot() else { return }
        let points = latestRegion ?? defaultComparisonRegion()
        let comparison = MemoEffectComparisonViewController(
            source: source,
            canvasBounds: annotationView.bounds,
            points: points
        )
        let navigation = UINavigationController(rootViewController: comparison)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func removeRegion() {
        let sheet = UIAlertController(
            title: "Memo region",
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Remove region", style: .destructive) { [weak self] _ in
            self?.annotationView.clearRegion()
            self?.latestRegion = nil
            self?.memoCard.isHidden = true
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func saveMemo() {
        guard latestRegion != nil else { return }
        var config = saveButton.configuration
        config?.title = "Saved ✓"
        config?.baseBackgroundColor = .systemGreen
        saveButton.configuration = config
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            var reset = self.saveButton.configuration
            reset?.title = "Save to Memo"
            reset?.baseBackgroundColor = UIColor(
                red: 0.18,
                green: 0.18,
                blue: 0.21,
                alpha: 1
            )
            self.saveButton.configuration = reset
        }
    }

    private func presentPicker(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true) { [weak self] in
            if let image {
                self?.setImage(image)
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private static func makeSamplePaperImage() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let cg = renderer.cgContext
            UIColor(
                red: 0.93,
                green: 0.91,
                blue: 0.86,
                alpha: 1
            ).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            UIColor.black.withAlphaComponent(0.035).setStroke()
            cg.setLineWidth(1)
            for y in stride(from: CGFloat(70), through: size.height - 50, by: 48) {
                cg.move(to: CGPoint(x: 55, y: y))
                cg.addLine(to: CGPoint(x: size.width - 55, y: y))
                cg.strokePath()
            }

            let ink = UIColor(
                red: 0.13,
                green: 0.15,
                blue: 0.17,
                alpha: 0.88
            )
            let titleFont = UIFont(name: "MarkerFelt-Wide", size: 43)
                ?? .systemFont(ofSize: 43, weight: .medium)
            let bodyFont = UIFont(name: "MarkerFelt-Thin", size: 29)
                ?? .systemFont(ofSize: 29)
            let smallFont = UIFont(name: "MarkerFelt-Thin", size: 24)
                ?? .systemFont(ofSize: 24)

            func text(_ string: String, _ point: CGPoint, _ font: UIFont) {
                (string as NSString).draw(
                    at: point,
                    withAttributes: [
                        .font: font,
                        .foregroundColor: ink
                    ]
                )
            }

            text("Q4 Product Plan", CGPoint(x: 110, y: 95), titleFont)
            cg.setStrokeColor(ink.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: 105, y: 150))
            cg.addLine(to: CGPoint(x: 440, y: 146))
            cg.strokePath()

            [
                "• Focus on core experience",
                "• Ship MVP in January",
                "• User feedback loop",
                "• Keep it simple"
            ].enumerated().forEach { index, line in
                text(
                    line,
                    CGPoint(x: 120, y: 190 + CGFloat(index) * 50),
                    bodyFont
                )
            }

            text("User workflow (sketch)", CGPoint(x: 120, y: 430), titleFont)
            cg.setStrokeColor(ink.withAlphaComponent(0.82).cgColor)
            cg.setLineWidth(4)
            cg.stroke(CGRect(x: 125, y: 520, width: 115, height: 130))
            cg.stroke(CGRect(x: 330, y: 515, width: 95, height: 145))
            cg.stroke(CGRect(x: 505, y: 525, width: 100, height: 125))
            cg.addEllipse(in: CGRect(x: 680, y: 535, width: 110, height: 70))
            cg.strokePath()

            text("1. Capture", CGPoint(x: 120, y: 680), smallFont)
            text("2. Extract", CGPoint(x: 315, y: 680), smallFont)
            text("3. Organize", CGPoint(x: 485, y: 680), smallFont)
            text("4. Access", CGPoint(x: 675, y: 680), smallFont)
            text("anywhere", CGPoint(x: 690, y: 710), smallFont)

            text("Ideas:", CGPoint(x: 120, y: 790), titleFont)
            [
                "• Auto crop",
                "• Handwriting OCR",
                "• Link to calendar",
                "• Collab sharing?"
            ].enumerated().forEach { index, line in
                text(
                    line,
                    CGPoint(x: 130, y: 850 + CGFloat(index) * 48),
                    bodyFont
                )
            }

            cg.setStrokeColor(ink.withAlphaComponent(0.5).cgColor)
            cg.setLineWidth(3)
            cg.addEllipse(in: CGRect(x: 505, y: 830, width: 180, height: 180))
            cg.addEllipse(in: CGRect(x: 625, y: 815, width: 180, height: 180))
            cg.strokePath()
            text("Paper", CGPoint(x: 550, y: 900), smallFont)
            text("Digital", CGPoint(x: 675, y: 885), smallFont)
            text("A calmer mind.", CGPoint(x: 605, y: 1040), smallFont)
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = PaperMemoDemoViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
