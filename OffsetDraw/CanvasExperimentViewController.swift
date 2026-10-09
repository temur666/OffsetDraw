import UIKit
import PhotosUI
import VisionKit

final class CanvasExperimentViewController: UIViewController, PHPickerViewControllerDelegate {
    private let canvasView = SubjectStickerCanvasView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Canvas"
        view.backgroundColor = .systemBackground

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.onImportPhoto = { [weak self] in
            self?.presentPhotoPicker()
        }
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else {
                return
            }

            DispatchQueue.main.async {
                self?.canvasView.addPhoto(image)
            }
        }
    }
}

private final class SubjectStickerCanvasView: UIView {
    var onImportPhoto: (() -> Void)?

    private let boardView = UIView()
    private let importButtonContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let importButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private weak var activeLiftSource: LiftablePhotoView?
    private var activeLiftPreview: UIImageView?
    private var activeLiftImage: UIImage?
    private var activeLiftPreviewSize: CGSize = .zero
    private var liftRequestID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func addPhoto(_ image: UIImage) {
        let normalizedImage = image.normalizedForSubjectLifting()
        let photoView = LiftablePhotoView(image: normalizedImage)

        photoView.onAnalysisStateChanged = { [weak self] state in
            switch state {
            case .analyzing:
                self?.showStatus("正在识别主体…")
            case .ready(let count):
                self?.showStatus(count > 0 ? "已识别主体，长按即可抠图" : "这张图片没有识别到可抠主体")
            case .unsupported:
                self?.showStatus("当前设备不支持原生抠图")
            case .failed:
                self?.showStatus("主体识别失败")
            }
        }

        boardView.addSubview(photoView)
        bringControlsToFront()

        let availableWidth = max(boardView.bounds.width - 64, 180)
        let maxWidth = min(availableWidth, 300)
        let maxHeight = min(max(boardView.bounds.height * 0.42, 220), 380)
        let fittedSize = normalizedImage.size.aspectFit(in: CGSize(width: maxWidth, height: maxHeight))
        photoView.bounds = CGRect(origin: .zero, size: fittedSize)
        photoView.center = CGPoint(x: boardView.bounds.midX, y: max(120 + fittedSize.height / 2, boardView.bounds.midY * 0.72))

        let liftRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleSubjectLift(_:)))
        liftRecognizer.minimumPressDuration = 0.35
        liftRecognizer.allowableMovement = 18
        liftRecognizer.cancelsTouchesInView = false
        liftRecognizer.delegate = photoView
        photoView.addGestureRecognizer(liftRecognizer)
        photoView.panRecognizer.require(toFail: liftRecognizer)

        photoView.prepareSubjectAnalysis()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if boardView.bounds.isEmpty {
            return
        }
    }

    @objc private func importTapped() {
        onImportPhoto?()
    }

    @objc private func handleSubjectLift(_ recognizer: UILongPressGestureRecognizer) {
        guard let sourceView = recognizer.view as? LiftablePhotoView else {
            return
        }

        switch recognizer.state {
        case .began:
            guard sourceView.isSubjectAnalysisReady else {
                sourceView.prepareSubjectAnalysis()
                showStatus("主体还在识别，稍后再长按一次")
                return
            }

            let requestID = UUID()
            liftRequestID = requestID
            activeLiftSource = sourceView
            let sourcePoint = recognizer.location(in: sourceView)

            sourceView.requestSubjectImage(at: sourcePoint) { [weak self, weak recognizer, weak sourceView] subjectImage in
                guard let self,
                      let recognizer,
                      let sourceView,
                      self.liftRequestID == requestID,
                      self.activeLiftSource === sourceView,
                      recognizer.state == .began || recognizer.state == .changed else {
                    return
                }

                guard let subjectImage else {
                    self.showStatus("这里没有识别到主体")
                    self.resetActiveLift()
                    return
                }

                self.beginLift(subjectImage, from: sourceView, at: recognizer.location(in: self.boardView))
            }

        case .changed:
            guard activeLiftSource === sourceView else {
                return
            }
            activeLiftPreview?.center = recognizer.location(in: boardView)

        case .ended:
            guard activeLiftSource === sourceView, activeLiftPreview != nil else {
                resetActiveLift()
                return
            }
            finishLift(at: recognizer.location(in: boardView))

        case .cancelled, .failed:
            resetActiveLift()

        default:
            break
        }
    }

    private func beginLift(_ subjectImage: UIImage, from sourceView: LiftablePhotoView, at point: CGPoint) {
        activeLiftPreview?.removeFromSuperview()

        let stickerImage = subjectImage.applyingStickerBorder()
        let imageRect = sourceView.displayedImageRect
        let sourceScale = sourceView.currentUniformScale
        let displayScale = imageRect.width / max(sourceView.image?.size.width ?? 1, 1) * sourceScale

        var previewSize = CGSize(
            width: stickerImage.size.width * displayScale,
            height: stickerImage.size.height * displayScale
        )

        let maxDimension = max(previewSize.width, previewSize.height)
        if maxDimension > 280 {
            let factor = 280 / maxDimension
            previewSize.width *= factor
            previewSize.height *= factor
        }
        if max(previewSize.width, previewSize.height) < 72 {
            let factor = 72 / max(max(previewSize.width, previewSize.height), 1)
            previewSize.width *= factor
            previewSize.height *= factor
        }

        let preview = UIImageView(image: stickerImage)
        preview.contentMode = .scaleAspectFit
        preview.bounds = CGRect(origin: .zero, size: previewSize)
        preview.center = point
        preview.layer.shadowColor = UIColor.black.cgColor
        preview.layer.shadowOpacity = 0.22
        preview.layer.shadowRadius = 7
        preview.layer.shadowOffset = CGSize(width: 0, height: 3)
        preview.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)

        boardView.addSubview(preview)
        bringControlsToFront()

        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            preview.transform = .identity
        }

        activeLiftSource = sourceView
        activeLiftPreview = preview
        activeLiftImage = stickerImage
        activeLiftPreviewSize = previewSize
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func finishLift(at point: CGPoint) {
        guard let stickerImage = activeLiftImage else {
            resetActiveLift()
            return
        }

        let stickerView = makeSticker(image: stickerImage, size: activeLiftPreviewSize, center: point, transform: .identity)
        boardView.addSubview(stickerView)
        bringControlsToFront()

        activeLiftPreview?.removeFromSuperview()
        activeLiftPreview = nil
        activeLiftSource?.clearSubjectHighlight()
        activeLiftSource = nil
        activeLiftImage = nil
        activeLiftPreviewSize = .zero
        liftRequestID = nil

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showStatus("已生成贴纸")
    }

    private func makeSticker(
        image: UIImage,
        size: CGSize,
        center: CGPoint,
        transform: CGAffineTransform
    ) -> TransformableImageView {
        let stickerView = TransformableImageView(image: image, kind: .sticker)
        stickerView.bounds = CGRect(origin: .zero, size: size)
        stickerView.center = center
        stickerView.transform = transform
        stickerView.onDelete = { [weak stickerView] in
            stickerView?.removeFromSuperview()
        }
        stickerView.onDuplicate = { [weak self, weak stickerView] in
            guard let self, let stickerView, let image = stickerView.image else {
                return
            }
            let duplicate = self.makeSticker(
                image: image,
                size: stickerView.bounds.size,
                center: CGPoint(x: stickerView.center.x + 24, y: stickerView.center.y + 24),
                transform: stickerView.transform
            )
            self.boardView.addSubview(duplicate)
            self.bringControlsToFront()
        }
        return stickerView
    }

    private func resetActiveLift() {
        activeLiftPreview?.removeFromSuperview()
        activeLiftPreview = nil
        activeLiftSource?.clearSubjectHighlight()
        activeLiftSource = nil
        activeLiftImage = nil
        activeLiftPreviewSize = .zero
        liftRequestID = nil
    }

    private func bringControlsToFront() {
        bringSubviewToFront(importButtonContainer)
        bringSubviewToFront(statusLabel)
    }

    private func configure() {
        backgroundColor = .secondarySystemBackground

        boardView.translatesAutoresizingMaskIntoConstraints = false
        boardView.backgroundColor = .systemBackground
        boardView.layer.cornerRadius = 18
        boardView.layer.masksToBounds = true
        addSubview(boardView)

        importButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        importButtonContainer.layer.cornerRadius = 22
        importButtonContainer.clipsToBounds = true
        addSubview(importButtonContainer)

        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
        importButton.tintColor = .label
        importButton.accessibilityLabel = "Add photo"
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        importButtonContainer.contentView.addSubview(importButton)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .secondaryLabel
        statusLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 14
        statusLabel.clipsToBounds = true
        statusLabel.alpha = 0
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            boardView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            boardView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            boardView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            boardView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),

            importButtonContainer.widthAnchor.constraint(equalToConstant: 44),
            importButtonContainer.heightAnchor.constraint(equalToConstant: 44),
            importButtonContainer.trailingAnchor.constraint(equalTo: boardView.trailingAnchor, constant: -14),
            importButtonContainer.topAnchor.constraint(equalTo: boardView.topAnchor, constant: 14),

            importButton.leadingAnchor.constraint(equalTo: importButtonContainer.contentView.leadingAnchor),
            importButton.trailingAnchor.constraint(equalTo: importButtonContainer.contentView.trailingAnchor),
            importButton.topAnchor.constraint(equalTo: importButtonContainer.contentView.topAnchor),
            importButton.bottomAnchor.constraint(equalTo: importButtonContainer.contentView.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: boardView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: boardView.topAnchor, constant: 18),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: boardView.widthAnchor, multiplier: 0.8)
        ])
    }

    private func showStatus(_ text: String) {
        statusLabel.layer.removeAllAnimations()
        statusLabel.text = "  \(text)  "
        statusLabel.alpha = 1
        UIView.animate(withDuration: 0.22, delay: 1.6, options: [.curveEaseOut, .allowUserInteraction]) {
            self.statusLabel.alpha = 0
        }
    }
}

private final class LiftablePhotoView: TransformableImageView {
    enum AnalysisState {
        case analyzing
        case ready(Int)
        case unsupported
        case failed
    }

    var onAnalysisStateChanged: ((AnalysisState) -> Void)?

    private let analyzer = ImageAnalyzer()
    private let analysisInteraction = ImageAnalysisInteraction()
    private var isAnalyzingSubjects = false
    private(set) var isSubjectAnalysisReady = false

    var displayedImageRect: CGRect {
        guard let image else {
            return bounds
        }
        return image.size.aspectFitRect(in: bounds)
    }

    init(image: UIImage) {
        super.init(image: image, kind: .photo)
        analysisInteraction.preferredInteractionTypes = [.imageSubject]
        analysisInteraction.setSupplementaryInterfaceHidden(true, animated: false)
        addInteraction(analysisInteraction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareSubjectAnalysis() {
        guard !isSubjectAnalysisReady, !isAnalyzingSubjects, let image else {
            return
        }

        guard ImageAnalyzer.isSupported else {
            onAnalysisStateChanged?(.unsupported)
            return
        }

        isAnalyzingSubjects = true
        onAnalysisStateChanged?(.analyzing)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let configuration = ImageAnalyzer.Configuration([.visualLookUp])
                let analysis = try await analyzer.analyze(image, configuration: configuration)
                analysisInteraction.analysis = analysis

                let subjects = await analysisInteraction.subjects
                isSubjectAnalysisReady = true
                isAnalyzingSubjects = false
                onAnalysisStateChanged?(.ready(subjects.count))
            } catch {
                isAnalyzingSubjects = false
                isSubjectAnalysisReady = false
                onAnalysisStateChanged?(.failed)
            }
        }
    }

    func requestSubjectImage(at point: CGPoint, completion: @escaping (UIImage?) -> Void) {
        guard isSubjectAnalysisReady else {
            completion(nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            guard let subject = await analysisInteraction.subject(at: point) else {
                completion(nil)
                return
            }

            analysisInteraction.highlightedSubjects = [subject]

            do {
                let subjectImage = try await analysisInteraction.image(for: Set([subject]))
                completion(subjectImage)
            } catch {
                completion(nil)
            }
        }
    }

    func clearSubjectHighlight() {
        analysisInteraction.highlightedSubjects = []
    }
}

private class TransformableImageView: UIImageView, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    enum Kind {
        case photo
        case sticker
    }

    let kind: Kind
    let panRecognizer: UIPanGestureRecognizer
    private let pinchRecognizer: UIPinchGestureRecognizer
    private let rotationRecognizer: UIRotationGestureRecognizer
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?

    var currentUniformScale: CGFloat {
        hypot(transform.a, transform.c)
    }

    init(image: UIImage, kind: Kind) {
        self.kind = kind
        panRecognizer = UIPanGestureRecognizer()
        pinchRecognizer = UIPinchGestureRecognizer()
        rotationRecognizer = UIRotationGestureRecognizer()
        super.init(image: image)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit
        clipsToBounds = false

        if kind == .photo {
            backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.42)
            layer.cornerRadius = 12
            layer.borderWidth = 1
            layer.borderColor = UIColor.separator.cgColor
        } else {
            backgroundColor = .clear
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.16
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }

        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        rotationRecognizer.addTarget(self, action: #selector(handleRotation(_:)))
        panRecognizer.delegate = self
        pinchRecognizer.delegate = self
        rotationRecognizer.delegate = self

        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(rotationRecognizer)

        if kind == .sticker {
            addInteraction(UIContextMenuInteraction(delegate: self))
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let superview else {
            return
        }

        let translation = recognizer.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        recognizer.setTranslation(.zero, in: superview)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else {
            return
        }

        let proposedScale = currentUniformScale * recognizer.scale
        let clampedScale = min(max(proposedScale, 0.24), 5.5)
        let adjustment = clampedScale / max(currentUniformScale, 0.001)
        transform = transform.scaledBy(x: adjustment, y: adjustment)
        recognizer.scale = 1
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else {
            return
        }

        transform = transform.rotated(by: recognizer.rotation)
        recognizer.rotation = 0
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard kind == .sticker else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return UIMenu(children: [])
            }

            var actions: [UIAction] = []
            if onDuplicate != nil {
                actions.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                    self?.onDuplicate?()
                })
            }
            actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.onDelete?()
            })
            return UIMenu(children: actions)
        }
    }
}

private extension UIImage {
    func normalizedForSubjectLifting() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func applyingStickerBorder() -> UIImage {
        let borderWidth = max(5, min(size.width, size.height) * 0.022)
        let padding = borderWidth * 1.7
        let outputSize = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let silhouette = withTintColor(.white, renderingMode: .alwaysTemplate)

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            let center = CGPoint(x: padding, y: padding)
            let steps = 28
            for step in 0..<steps {
                let angle = CGFloat(step) / CGFloat(steps) * .pi * 2
                let offset = CGPoint(
                    x: cos(angle) * borderWidth,
                    y: sin(angle) * borderWidth
                )
                silhouette.draw(at: CGPoint(x: center.x + offset.x, y: center.y + offset.y))
            }
            draw(at: center)
        }
    }
}

private extension CGSize {
    func aspectFit(in boundingSize: CGSize) -> CGSize {
        guard width > 0, height > 0 else {
            return boundingSize
        }
        let scale = min(boundingSize.width / width, boundingSize.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    func aspectFitRect(in bounds: CGRect) -> CGRect {
        let fittedSize = aspectFit(in: bounds.size)
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}
