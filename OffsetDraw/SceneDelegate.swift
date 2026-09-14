import UIKit

private enum PaperTool: Int {
    case pen
    case highlighter
    case region
}

private struct PaperStroke {
    let tool: PaperTool
    let points: [CGPoint]
}

private enum MemoCaptureState {
    case idle
    case draft
    case saving
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
        active.removeAll()
        setNeedsDisplay()
    }

    func renderContentAnnotations(in context: CGContext) {
        for stroke in strokes {
            draw(stroke, in: context)
        }
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

        renderContentAnnotations(in: context)

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

private final class PaperToolButton: UIButton {
    let tool: PaperTool

    init(title: String, symbol: String, tool: PaperTool) {
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

    private let memoCard = UIView()
    private let memoTitle = UILabel()
    private let memoMenu = UIButton(type: .system)
    private let memoPreview = UIImageView()
    private let noteField = UITextField()
    private let saveButton = UIButton(type: .system)

    private var sourceImage = PaperMemoDemoViewController.makeSamplePaperImage()
    private var needsPaperLayout = true
    private var latestRegion: [CGPoint]?
    private var memoState: MemoCaptureState = .idle

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
            self?.beginMemoDraft(points)
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
            regionButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        toolbar.contentView.addSubview(stack)

        [penButton, highlighterButton, regionButton].forEach {
            $0.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        }

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
        memoCard.layer.cornerRadius = 26
        memoCard.layer.cornerCurve = .continuous
        memoCard.layer.shadowColor = UIColor.black.cgColor
        memoCard.layer.shadowOpacity = 0.2
        memoCard.layer.shadowRadius = 20
        memoCard.layer.shadowOffset = CGSize(width: 0, height: 10)
        memoCard.isHidden = true
        view.addSubview(memoCard)

        memoTitle.translatesAutoresizingMaskIntoConstraints = false
        memoTitle.text = "✦  Memo Draft"
        memoTitle.font = .systemFont(ofSize: 16, weight: .semibold)

        memoMenu.translatesAutoresizingMaskIntoConstraints = false
        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "ellipsis")
        menuConfig.baseForegroundColor = .secondaryLabel
        memoMenu.configuration = menuConfig
        memoMenu.addTarget(self, action: #selector(showMemoMenu), for: .touchUpInside)

        memoPreview.translatesAutoresizingMaskIntoConstraints = false
        memoPreview.contentMode = .scaleAspectFit
        memoPreview.clipsToBounds = false

        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.placeholder = "Add a note…"
        noteField.font = .systemFont(ofSize: 16)
        noteField.returnKeyType = .done
        noteField.delegate = self

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.configuration = defaultSaveConfiguration(title: "Save")
        saveButton.addTarget(self, action: #selector(saveMemo), for: .touchUpInside)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.4)

        [memoTitle, memoMenu, memoPreview, divider, noteField, saveButton].forEach(memoCard.addSubview)

        NSLayoutConstraint.activate([
            memoCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            memoCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            memoCard.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -12),
            memoCard.heightAnchor.constraint(equalToConstant: 274),

            memoTitle.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 20),
            memoTitle.topAnchor.constraint(equalTo: memoCard.topAnchor, constant: 15),
            memoMenu.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -10),
            memoMenu.centerYAnchor.constraint(equalTo: memoTitle.centerYAnchor),
            memoMenu.widthAnchor.constraint(equalToConstant: 40),
            memoMenu.heightAnchor.constraint(equalToConstant: 40),

            memoPreview.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 18),
            memoPreview.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -18),
            memoPreview.topAnchor.constraint(equalTo: memoTitle.bottomAnchor, constant: 7),
            memoPreview.heightAnchor.constraint(equalToConstant: 146),

            divider.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: memoPreview.bottomAnchor, constant: 5),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            noteField.leadingAnchor.constraint(equalTo: memoCard.leadingAnchor, constant: 20),
            noteField.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            noteField.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: memoCard.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: memoCard.bottomAnchor, constant: -13),
            saveButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func defaultSaveConfiguration(title: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(
            red: 0.18,
            green: 0.18,
            blue: 0.21,
            alpha: 1
        )
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 11,
            leading: 18,
            bottom: 11,
            trailing: 18
        )
        return config
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
        memoState = .idle
        memoCard.isHidden = true
        memoCard.alpha = 1
        memoCard.transform = .identity
        memoPreview.image = nil
        noteField.text = nil
        noteField.resignFirstResponder()
        saveButton.configuration = defaultSaveConfiguration(title: "Save")
        saveButton.isEnabled = true
        annotationView.isUserInteractionEnabled = true
        toolbar.isUserInteractionEnabled = true
        needsPaperLayout = true
        view.setNeedsLayout()
    }

    private func select(_ tool: PaperTool) {
        annotationView.selectedTool = tool
        penButton.setActive(tool == .pen)
        highlighterButton.setActive(tool == .highlighter)
        regionButton.setActive(tool == .region)
    }

    private func beginMemoDraft(_ points: [CGPoint]) {
        guard memoState != .saving else { return }

        let startsNewDraft = memoState == .idle
        latestRegion = points
        memoState = .draft

        if startsNewDraft {
            noteField.text = nil
        }

        guard let source = paperSnapshot(),
              let preview = MemoryAMemoRenderer.render(
                source: source,
                canvasBounds: annotationView.bounds,
                points: points
              ) else {
            discardDraft(animated: false)
            return
        }

        memoPreview.image = preview
        memoTitle.text = "✦  Memo Draft"
        saveButton.configuration = defaultSaveConfiguration(title: "Save")
        saveButton.isEnabled = true
        annotationView.isUserInteractionEnabled = false
        toolbar.isUserInteractionEnabled = false

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presentMemoCardIfNeeded()
    }

    private func presentMemoCardIfNeeded() {
        if memoCard.isHidden {
            memoCard.isHidden = false
            memoCard.alpha = 0
            memoCard.transform = CGAffineTransform(
                translationX: 0,
                y: 24
            ).scaledBy(x: 0.985, y: 0.985)
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.35,
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
            annotationView.renderContentAnnotations(in: renderer.cgContext)
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
        guard memoState == .idle else { return }
        select(sender.tool)
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

        if memoState == .draft {
            sheet.addAction(UIAlertAction(title: "Discard Memo Draft", style: .destructive) { [weak self] _ in
                self?.discardDraft(animated: true)
            })
        }

        sheet.addAction(UIAlertAction(title: "Reset annotations", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.discardDraft(animated: false)
            self.annotationView.clearAll()
        })

        sheet.addAction(UIAlertAction(title: "Use sample paper", style: .default) { [weak self] _ in
            self?.setImage(Self.makeSamplePaperImage())
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func showMemoMenu() {
        guard memoState == .draft else { return }

        let sheet = UIAlertController(
            title: "Memo Draft",
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Discard Draft", style: .destructive) { [weak self] _ in
            self?.discardDraft(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func saveMemo() {
        guard memoState == .draft,
              latestRegion != nil else {
            return
        }

        memoState = .saving
        saveButton.isEnabled = false
        var saved = defaultSaveConfiguration(title: "Saved ✓")
        saved.baseBackgroundColor = .systemGreen
        saveButton.configuration = saved
        noteField.resignFirstResponder()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self else { return }

            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                self.memoCard.alpha = 0
                self.memoCard.transform = CGAffineTransform(
                    translationX: 0,
                    y: 18
                ).scaledBy(x: 0.97, y: 0.97)
            } completion: { _ in
                self.finishMemoSave()
            }
        }
    }

    private func finishMemoSave() {
        annotationView.clearRegion()
        latestRegion = nil
        memoState = .idle
        memoCard.isHidden = true
        memoCard.alpha = 1
        memoCard.transform = .identity
        memoPreview.image = nil
        memoTitle.text = "✦  Memo Draft"
        noteField.text = nil
        saveButton.configuration = defaultSaveConfiguration(title: "Save")
        saveButton.isEnabled = true
        annotationView.isUserInteractionEnabled = true
        toolbar.isUserInteractionEnabled = true
    }

    private func discardDraft(animated: Bool) {
        guard memoState != .saving else { return }

        let cleanup = { [weak self] in
            guard let self else { return }
            self.annotationView.clearRegion()
            self.latestRegion = nil
            self.memoState = .idle
            self.memoCard.isHidden = true
            self.memoCard.alpha = 1
            self.memoCard.transform = .identity
            self.memoPreview.image = nil
            self.noteField.text = nil
            self.noteField.resignFirstResponder()
            self.saveButton.configuration = self.defaultSaveConfiguration(title: "Save")
            self.saveButton.isEnabled = true
            self.annotationView.isUserInteractionEnabled = true
            self.toolbar.isUserInteractionEnabled = true
        }

        guard animated, !memoCard.isHidden else {
            cleanup()
            return
        }

        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.memoCard.alpha = 0
                self.memoCard.transform = CGAffineTransform(translationX: 0, y: 16)
            },
            completion: { _ in cleanup() }
        )
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
