import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

private enum PaperDemoTool: Int {
    case pen
    case highlighter
    case region
}

private struct PaperDemoStroke {
    let tool: PaperDemoTool
    let points: [CGPoint]
}

private final class PaperAnnotationView: UIView {
    var selectedTool: PaperDemoTool = .region
    var onRegionCommitted: (([CGPoint]) -> Void)?

    private var strokes: [PaperDemoStroke] = []
    private var committedRegion: [CGPoint]?
    private var activePoints: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func clearAll() {
        strokes.removeAll()
        committedRegion = nil
        activePoints.removeAll()
        setNeedsDisplay()
    }

    func clearRegion() {
        committedRegion = nil
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (event?.allTouches?.count ?? touches.count) > 1 {
            activePoints.removeAll()
            return
        }
        guard let touch = touches.first else { return }
        activePoints = [touch.location(in: self)]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (event?.allTouches?.count ?? touches.count) > 1 {
            activePoints.removeAll()
            setNeedsDisplay()
            return
        }
        guard let touch = touches.first else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            let point = sample.location(in: self)
            if let last = activePoints.last, hypot(point.x - last.x, point.y - last.y) < 1.5 {
                continue
            }
            activePoints.append(point)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activePoints.isEmpty else { return }

        switch selectedTool {
        case .pen, .highlighter:
            if activePoints.count > 1 {
                strokes.append(PaperDemoStroke(tool: selectedTool, points: activePoints))
            }
        case .region:
            if regionBounds(for: activePoints).width > 24,
               regionBounds(for: activePoints).height > 24 {
                committedRegion = activePoints
                onRegionCommitted?(activePoints)
            }
        }

        activePoints.removeAll()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePoints.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for stroke in strokes {
            drawStroke(stroke, in: context)
        }

        if let committedRegion {
            drawFocusMask(region: committedRegion, in: context)
            drawRegionOutline(committedRegion, alpha: 0.78, in: context)
        }

        guard activePoints.count > 1 else { return }
        switch selectedTool {
        case .pen, .highlighter:
            drawStroke(PaperDemoStroke(tool: selectedTool, points: activePoints), in: context)
        case .region:
            drawRegionOutline(activePoints, alpha: 0.72, in: context, closed: false)
        }
    }

    static func closedPath(points: [CGPoint]) -> UIBezierPath {
        let path = smoothPath(points: points)
        path.close()
        return path
    }

    static func regionBounds(for points: [CGPoint]) -> CGRect {
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
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    private func drawStroke(_ stroke: PaperDemoStroke, in context: CGContext) {
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

        drawPolyline(stroke.points, in: context)
        context.restoreGState()
    }

    private func drawRegionOutline(
        _ points: [CGPoint],
        alpha: CGFloat,
        in context: CGContext,
        closed: Bool = true
    ) {
        guard points.count > 1 else { return }
        let path = Self.smoothPath(points: points)
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

    private func drawFocusMask(region: [CGPoint], in context: CGContext) {
        guard region.count > 2 else { return }
        let outside = UIBezierPath(rect: bounds)
        outside.append(Self.closedPath(points: region))
        outside.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.14).setFill()
        outside.fill()
    }

    private func drawPolyline(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func smoothPath(points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            if let last = points.last { path.addLine(to: last) }
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) * 0.5, y: (previous.y + current.y) * 0.5)
            path.addQuadCurve(to: midpoint, controlPoint: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }
}

private final class PaperDemoToolButton: UIButton {
    let tool: PaperDemoTool?

    init(title: String, symbol: String, tool: PaperDemoTool?) {
        self.tool = tool
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .top
        config.imagePadding = 7
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6)
        configuration = config
        layer.cornerRadius = 18
        clipsToBounds = true
        titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelectedStyle(_ selected: Bool) {
        guard var config = configuration else { return }
        config.baseForegroundColor = selected ? .systemBlue : .secondaryLabel
        config.background.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.11) : .clear
        configuration = config
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
    private let penButton = PaperDemoToolButton(title: "Pen", symbol: "pencil.tip", tool: .pen)
    private let highlighterButton = PaperDemoToolButton(title: "Highlighter", symbol: "highlighter", tool: .highlighter)
    private let regionButton = PaperDemoToolButton(title: "Region", symbol: "lasso.badge.sparkles", tool: .region)
    private let noteButton = PaperDemoToolButton(title: "Note", symbol: "note.text", tool: nil)

    private let memoCard = UIView()
    private let memoTitleLabel = UILabel()
    private let memoMenuButton = UIButton(type: .system)
    private let memoPreview = UIImageView()
    private let noteField = UITextField()
    private let saveButton = UIButton(type: .system)

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var sourceImage: UIImage = PaperMemoDemoViewController.makeSamplePaperImage()
    private var needsPaperLayout = true
    private var latestRegionPoints: [CGPoint]?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.105, green: 0.102, blue: 0.098, alpha: 1)
        configureHeader()
        configureCanvas()
        configureToolbar()
        configureMemoCard()
        setSourceImage(sourceImage)
        selectTool(.region)
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
        subtitleLabel.textAlignment = .center

        var photoConfig = UIButton.Configuration.filled()
        photoConfig.image = UIImage(systemName: "camera.fill")
        photoConfig.baseForegroundColor = .white
        photoConfig.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        photoConfig.cornerStyle = .capsule
        photoButton.configuration = photoConfig
        photoButton.translatesAutoresizingMaskIntoConstraints = false
        photoButton.addTarget(self, action: #selector(choosePhoto), for: .touchUpInside)

        var moreConfig = UIButton.Configuration.filled()
        moreConfig.image = UIImage(systemName: "ellipsis")
        moreConfig.baseForegroundColor = .white
        moreConfig.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        moreConfig.cornerStyle = .capsule
        moreButton.configuration = moreConfig
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(photoButton)
        view.addSubview(moreButton)

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

    private func configureCanvas() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        view.insertSubview(scrollView, at: 0)

        paperContainer.backgroundColor = .systemBackground
        paperContainer.layer.cornerRadius = 18
        paperContainer.layer.cornerCurve = .continuous
        paperContainer.layer.shadowColor = UIColor.black.cgColor
        paperContainer.layer.shadowOpacity = 0.28
        paperContainer.layer.shadowRadius = 18
        paperContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        paperContainer.clipsToBounds = false
        scrollView.addSubview(paperContainer)

        paperImageView.contentMode = .scaleAspectFill
        paperImageView.clipsToBounds = true
        paperImageView.layer.cornerRadius = 18
        paperImageView.layer.cornerCurve = .continuous
        paperContainer.addSubview(paperImageView)

        annotationView.layer.cornerRadius = 18
        annotationView.layer.cornerCurve = .continuous
        annotationView.clipsToBounds = true
        annotationView.onRegionCommitted = { [weak self] points in
            self?.latestRegionPoints = points
            self?.showMemo(for: points)
        }
        paperContainer.addSubview(annotationView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 30
        toolbar.layer.cornerCurve = .continuous
        toolbar.clipsToBounds = true
        view.addSubview(toolbar)

        let stack = UIStackView(arrangedSubviews: [penButton, highlighterButton, regionButton, noteButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
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

        memoTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        memoTitleLabel.text = "✦  Memo"
        memoTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        memoTitleLabel.textColor = .label

        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "ellipsis")
        menuConfig.baseForegroundColor = .secondaryLabel
        memoMenuButton.configuration = menuConfig
        memoMenuButton.translatesAutoresizingMaskIntoConstraints = false
        memoMenuButton.addTarget(self, action: #selector(clearRegionFromMemo), for: .touchUpInside)

        memoPreview.translatesAutoresizingMaskIntoConstraints = false
        memoPreview.contentMode = .scaleAspectFit
        memoPreview.clipsToBounds = false

        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.placeholder = "Add a note…"
        noteField.font = .systemFont(ofSize: 16)
        noteField.returnKeyType = .done
        noteField.delegate = self
        noteField.clearButtonMode = .whileEditing

        var saveConfig = UIButton.Configuration.filled()
        saveConfig.title = "Save to Memo"
        saveConfig.baseBackgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1)
        saveConfig.baseForegroundColor = .white
        saveConfig.cornerStyle = .capsule
        saveConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        saveButton.configuration = saveConfig
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addTarget(self, action: #selector(saveMemo), for: .touchUpInside)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.45)

        memoCard.addSubview(memoTitleLabel)
        memoCard.addSubview(memoMenuButton)
        memoCard.addSubview(memoPreview)
        memoCard.addSubview(divider)
        memoCard.addSubview(noteField)
        memoCard.addSubview(saveButton)

        NSLayoutConstraint.activate([
            memoCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            memoCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            memoCard.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -12),
            memoCard.heightAnchor.constraint(equalToConstant: 286),

            memoTitleLabel.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 20),
            memoTitleLabel.topAnchor.constraint(equalTo: memoCard.topAnchor, constant: 16),
            memoMenuButton.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -12),
            memoMenuButton.centerYAnchor.constraint(equalTo: memoTitleLabel.centerYAnchor),
            memoMenuButton.widthAnchor.constraint(equalToConstant: 40),
            memoMenuButton.heightAnchor.constraint(equalToConstant: 40),

            memoPreview.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 18),
            memoPreview.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -18),
            memoPreview.topAnchor.constraint(equalTo: memoTitleLabel.bottomAnchor, constant: 8),
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
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        scrollView.setZoomScale(1, animated: false)

        let topInset: CGFloat = 92
        let bottomInset: CGFloat = 112
        let horizontalInset: CGFloat = 16
        let available = CGSize(
            width: scrollView.bounds.width - horizontalInset * 2,
            height: max(240, scrollView.bounds.height - topInset - bottomInset)
        )
        let imageAspect = sourceImage.size.width / max(sourceImage.size.height, 1)
        var size = CGSize(width: available.width, height: available.width / imageAspect)
        if size.height > available.height {
            size.height = available.height
            size.width = available.height * imageAspect
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

    private func setSourceImage(_ image: UIImage) {
        sourceImage = normalized(image)
        paperImageView.image = sourceImage
        annotationView.clearAll()
        latestRegionPoints = nil
        memoCard.isHidden = true
        memoPreview.image = nil
        noteField.text = nil
        needsPaperLayout = true
        view.setNeedsLayout()
    }

    private func selectTool(_ tool: PaperDemoTool) {
        annotationView.selectedTool = tool
        penButton.setSelectedStyle(tool == .pen)
        highlighterButton.setSelectedStyle(tool == .highlighter)
        regionButton.setSelectedStyle(tool == .region)
    }

    private func showMemo(for points: [CGPoint]) {
        guard let preview = makeFeatheredPreview(points: points) else { return }
        memoPreview.image = preview

        if memoCard.isHidden {
            memoCard.isHidden = false
            memoCard.alpha = 0
            memoCard.transform = CGAffineTransform(translationX: 0, y: 28).scaledBy(x: 0.98, y: 0.98)
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

    private func makeFeatheredPreview(points: [CGPoint]) -> UIImage? {
        guard points.count > 2, paperImageView.bounds.width > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let sourceRenderer = UIGraphicsImageRenderer(bounds: paperImageView.bounds, format: format)
        let source = sourceRenderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(paperImageView.bounds)
            paperImageView.layer.render(in: ctx.cgContext)
        }

        let maskRenderer = UIGraphicsImageRenderer(bounds: annotationView.bounds, format: format)
        let mask = maskRenderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(annotationView.bounds)
            UIColor.white.setFill()
            PaperAnnotationView.closedPath(points: points).fill()
        }

        guard let sourceCI = CIImage(image: source),
              let maskCI = CIImage(image: mask) else {
            return nil
        }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = maskCI
        blur.radius = 18
        guard let blurredMask = blur.outputImage?.cropped(to: sourceCI.extent) else { return nil }

        let clearBackground = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: sourceCI.extent)

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = sourceCI
        blend.backgroundImage = clearBackground
        blend.maskImage = blurredMask
        guard let output = blend.outputImage,
              let fullCG = ciContext.createCGImage(output, from: sourceCI.extent) else {
            return nil
        }

        let fullImage = UIImage(cgImage: fullCG)
        var crop = PaperAnnotationView.regionBounds(for: points).insetBy(dx: -30, dy: -30)
        crop = crop.intersection(annotationView.bounds).integral
        guard crop.width > 1,
              crop.height > 1,
              let cropped = fullImage.cgImage?.cropping(to: crop) else {
            return fullImage
        }
        return UIImage(cgImage: cropped)
    }

    private func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    @objc private func toolTapped(_ sender: PaperDemoToolButton) {
        guard let tool = sender.tool else { return }
        selectTool(tool)
    }

    @objc private func noteTapped() {
        guard !memoCard.isHidden else {
            let alert = UIAlertController(
                title: "Circle something first",
                message: "Use Region to loosely circle a part of the paper. It will become a Memo image.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        noteField.becomeFirstResponder()
    }

    @objc private func choosePhoto() {
        let sheet = UIAlertController(title: "Paper note", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentImagePicker(sourceType: .camera)
            })
        }
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentImagePicker(sourceType: .photoLibrary)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func showMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Reset annotations", style: .destructive) { [weak self] _ in
            self?.annotationView.clearAll()
            self?.memoCard.isHidden = true
            self?.latestRegionPoints = nil
        })
        sheet.addAction(UIAlertAction(title: "Use sample paper", style: .default) { [weak self] _ in
            self?.setSourceImage(Self.makeSamplePaperImage())
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func clearRegionFromMemo() {
        let sheet = UIAlertController(title: "Memo region", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Remove region", style: .destructive) { [weak self] _ in
            self?.annotationView.clearRegion()
            self?.latestRegionPoints = nil
            self?.memoCard.isHidden = true
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func saveMemo() {
        guard latestRegionPoints != nil else { return }
        let originalTitle = saveButton.configuration?.title
        var config = saveButton.configuration
        config?.title = "Saved ✓"
        config?.baseBackgroundColor = .systemGreen
        saveButton.configuration = config
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            var reset = self.saveButton.configuration
            reset?.title = originalTitle ?? "Save to Memo"
            reset?.baseBackgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1)
            self.saveButton.configuration = reset
        }
    }

    private func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
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
                self?.setSourceImage(image)
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
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.93, green: 0.91, blue: 0.86, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            UIColor.black.withAlphaComponent(0.035).setStroke()
            cg.setLineWidth(1)
            stride(from: CGFloat(70), through: size.height - 50, by: 48).forEach { y in
                cg.move(to: CGPoint(x: 55, y: y))
                cg.addLine(to: CGPoint(x: size.width - 55, y: y))
                cg.strokePath()
            }

            let ink = UIColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 0.88)
            let titleFont = UIFont(name: "MarkerFelt-Wide", size: 43) ?? .systemFont(ofSize: 43, weight: .medium)
            let bodyFont = UIFont(name: "MarkerFelt-Thin", size: 29) ?? .systemFont(ofSize: 29)
            let smallFont = UIFont(name: "MarkerFelt-Thin", size: 24) ?? .systemFont(ofSize: 24)

            func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor = ink) {
                (text as NSString).draw(
                    at: point,
                    withAttributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                )
            }

            draw("Q4 Product Plan", at: CGPoint(x: 110, y: 95), font: titleFont)
            cg.setStrokeColor(ink.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: 105, y: 150))
            cg.addLine(to: CGPoint(x: 440, y: 146))
            cg.strokePath()

            let bullets = [
                "• Focus on core experience",
                "• Ship MVP in January",
                "• User feedback loop",
                "• Keep it simple"
            ]
            for (index, line) in bullets.enumerated() {
                draw(line, at: CGPoint(x: 120, y: 190 + CGFloat(index) * 50), font: bodyFont)
            }

            draw("User workflow (sketch)", at: CGPoint(x: 120, y: 430), font: titleFont)
            cg.setStrokeColor(ink.withAlphaComponent(0.82).cgColor)
            cg.setLineWidth(4)
            cg.stroke(CGRect(x: 125, y: 520, width: 115, height: 130))
            cg.stroke(CGRect(x: 330, y: 515, width: 95, height: 145))
            cg.stroke(CGRect(x: 505, y: 525, width: 100, height: 125))

            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: 250, y: 585))
            cg.addLine(to: CGPoint(x: 315, y: 585))
            cg.move(to: CGPoint(x: 435, y: 585))
            cg.addLine(to: CGPoint(x: 490, y: 585))
            cg.strokePath()

            draw("1. Capture", at: CGPoint(x: 120, y: 680), font: smallFont)
            draw("2. Extract", at: CGPoint(x: 315, y: 680), font: smallFont)
            draw("3. Organize", at: CGPoint(x: 485, y: 680), font: smallFont)
            draw("4. Access", at: CGPoint(x: 675, y: 680), font: smallFont)
            draw("anywhere", at: CGPoint(x: 690, y: 710), font: smallFont)

            cg.addEllipse(in: CGRect(x: 680, y: 535, width: 110, height: 70))
            cg.strokePath()

            draw("Ideas:", at: CGPoint(x: 120, y: 790), font: titleFont)
            let ideas = ["• Auto crop", "• Handwriting OCR", "• Link to calendar", "• Collab sharing?"]
            for (index, line) in ideas.enumerated() {
                draw(line, at: CGPoint(x: 130, y: 850 + CGFloat(index) * 48), font: bodyFont)
            }

            cg.setStrokeColor(ink.withAlphaComponent(0.5).cgColor)
            cg.setLineWidth(3)
            cg.addEllipse(in: CGRect(x: 505, y: 830, width: 180, height: 180))
            cg.addEllipse(in: CGRect(x: 625, y: 815, width: 180, height: 180))
            cg.strokePath()
            draw("Paper", at: CGPoint(x: 550, y: 900), font: smallFont)
            draw("Digital", at: CGPoint(x: 675, y: 885), font: smallFont)
            draw("A calmer mind.", at: CGPoint(x: 605, y: 1040), font: smallFont)
        }
    }
}

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
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = PaperMemoDemoViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
