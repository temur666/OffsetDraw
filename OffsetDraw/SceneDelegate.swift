import UIKit
import PhotosUI
import Vision
import CoreImage

final class DrawingNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private let subjectStickerCoordinator = SubjectStickerCoordinator()

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        updateInteractivePopGesture(for: topViewController)
        updateSubjectStickerOverlay(for: topViewController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        updateInteractivePopGesture(for: viewController)
        updateSubjectStickerOverlay(for: viewController)
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

    private func updateSubjectStickerOverlay(for viewController: UIViewController?) {
        if let drawingController = viewController as? ViewController {
            subjectStickerCoordinator.attach(to: drawingController)
        } else {
            subjectStickerCoordinator.detach()
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

        let window = UIWindow(windowScene: windowScene)
        let store: DrawingDocumentStore
        do {
            store = try DrawingDocumentStore()
        } catch {
            return
        }
        window.rootViewController = DrawingNavigationController(rootViewController: HomeViewController(store: store))
        window.makeKeyAndVisible()
        self.window = window
    }
}

private final class SubjectStickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private weak var hostController: UIViewController?
    private weak var overlayView: SubjectStickerOverlayView?

    func attach(to controller: UIViewController) {
        if hostController === controller, overlayView?.superview != nil {
            return
        }

        detach()
        hostController = controller

        let overlay = SubjectStickerOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onImportPhoto = { [weak self] in
            self?.presentPhotoPicker()
        }
        controller.view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: controller.view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        overlayView = overlay
    }

    func detach() {
        overlayView?.removeFromSuperview()
        overlayView = nil
        hostController = nil
    }

    private func presentPhotoPicker() {
        guard let hostController else {
            return
        }

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        hostController.present(picker, animated: true)
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
                self?.overlayView?.addPhoto(image)
            }
        }
    }
}

private final class SubjectStickerOverlayView: UIView, UIGestureRecognizerDelegate {
    var onImportPhoto: (() -> Void)?

    private let importButtonContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let importButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private weak var activeLiftSource: LiftablePhotoView?
    private var activeLiftPreview: UIImageView?
    private var activeLiftImage: UIImage?
    private var activeLiftPreviewSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }

        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint, with: event) {
                return hitView
            }
        }

        return nil
    }

    func addPhoto(_ image: UIImage) {
        let normalizedImage = image.normalizedForSubjectLifting()
        let photoView = LiftablePhotoView(image: normalizedImage)
        photoView.onDelete = { [weak photoView] in
            photoView?.removeFromSuperview()
        }
        photoView.prepareSubjectAnalysis()
        addSubview(photoView)
        bringSubviewToFront(importButtonContainer)
        bringSubviewToFront(statusLabel)

        let availableWidth = max(bounds.width - 64, 180)
        let maxWidth = min(availableWidth, 300)
        let maxHeight = min(max(bounds.height * 0.42, 220), 380)
        let fittedSize = normalizedImage.size.aspectFit(in: CGSize(width: maxWidth, height: maxHeight))
        photoView.bounds = CGRect(origin: .zero, size: fittedSize)
        let topInset = safeAreaInsets.top + 74
        photoView.center = CGPoint(
            x: bounds.midX,
            y: max(topInset + fittedSize.height / 2, bounds.midY * 0.72)
        )

        let liftRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleSubjectLift(_:)))
        liftRecognizer.minimumPressDuration = 0.22
        liftRecognizer.allowableMovement = 12
        liftRecognizer.delegate = self
        liftRecognizer.cancelsTouchesInView = true
        photoView.addGestureRecognizer(liftRecognizer)
        photoView.panRecognizer.require(toFail: liftRecognizer)

        showStatus("Hold a subject, then drag it out")
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
                showStatus("Preparing subject…")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            let sourcePoint = recognizer.location(in: sourceView)
            guard let subjectImage = sourceView.subjectImage(at: sourcePoint) else {
                showStatus("No subject here")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            beginLift(subjectImage, from: sourceView, at: recognizer.location(in: self))

        case .changed:
            guard activeLiftSource === sourceView else {
                return
            }
            activeLiftPreview?.center = recognizer.location(in: self)

        case .ended:
            guard activeLiftSource === sourceView else {
                resetActiveLift()
                return
            }
            finishLift(at: recognizer.location(in: self))

        case .cancelled, .failed:
            resetActiveLift()

        default:
            break
        }
    }

    private func beginLift(_ subjectImage: UIImage, from sourceView: LiftablePhotoView, at point: CGPoint) {
        resetActiveLift()
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
        addSubview(preview)
        bringSubviewToFront(importButtonContainer)
        bringSubviewToFront(statusLabel)

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

        let stickerView = TransformableImageView(image: stickerImage, kind: .sticker)
        stickerView.bounds = CGRect(origin: .zero, size: activeLiftPreviewSize)
        stickerView.center = point
        stickerView.onDelete = { [weak stickerView] in
            stickerView?.removeFromSuperview()
        }
        stickerView.onDuplicate = { [weak self, weak stickerView] in
            guard let self, let stickerView, let image = stickerView.image else {
                return
            }
            let duplicate = TransformableImageView(image: image, kind: .sticker)
            duplicate.bounds = stickerView.bounds
            duplicate.center = CGPoint(x: stickerView.center.x + 24, y: stickerView.center.y + 24)
            duplicate.transform = stickerView.transform
            duplicate.onDelete = { [weak duplicate] in duplicate?.removeFromSuperview() }
            self.addSubview(duplicate)
            self.bringSubviewToFront(self.importButtonContainer)
            self.bringSubviewToFront(self.statusLabel)
        }
        addSubview(stickerView)
        bringSubviewToFront(importButtonContainer)
        bringSubviewToFront(statusLabel)

        activeLiftPreview?.removeFromSuperview()
        activeLiftPreview = nil
        activeLiftSource = nil
        activeLiftImage = nil
        activeLiftPreviewSize = .zero
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func resetActiveLift() {
        activeLiftPreview?.removeFromSuperview()
        activeLiftPreview = nil
        activeLiftSource = nil
        activeLiftImage = nil
        activeLiftPreviewSize = .zero
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false

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
        statusLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 14
        statusLabel.clipsToBounds = true
        statusLabel.alpha = 0
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            importButtonContainer.widthAnchor.constraint(equalToConstant: 44),
            importButtonContainer.heightAnchor.constraint(equalToConstant: 44),
            importButtonContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            importButtonContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),

            importButton.leadingAnchor.constraint(equalTo: importButtonContainer.contentView.leadingAnchor),
            importButton.trailingAnchor.constraint(equalTo: importButtonContainer.contentView.trailingAnchor),
            importButton.topAnchor.constraint(equalTo: importButtonContainer.contentView.topAnchor),
            importButton.bottomAnchor.constraint(equalTo: importButtonContainer.contentView.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72)
        ])
    }

    private func showStatus(_ text: String) {
        statusLabel.layer.removeAllAnimations()
        statusLabel.text = "  \(text)  "
        statusLabel.alpha = 1
        UIView.animate(withDuration: 0.22, delay: 1.25, options: [.curveEaseOut, .allowUserInteraction]) {
            self.statusLabel.alpha = 0
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private final class LiftablePhotoView: TransformableImageView {
    private let analysisQueue = DispatchQueue(label: "offsetdraw.subject-analysis", qos: .userInitiated)
    private var subjectAnalysis: SubjectAnalysis?
    private var isAnalyzingSubjects = false

    var isSubjectAnalysisReady: Bool {
        subjectAnalysis != nil
    }

    var displayedImageRect: CGRect {
        guard let image else {
            return bounds
        }
        return image.size.aspectFitRect(in: bounds)
    }

    init(image: UIImage) {
        super.init(image: image, kind: .photo)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareSubjectAnalysis() {
        guard subjectAnalysis == nil, !isAnalyzingSubjects, let image else {
            return
        }

        isAnalyzingSubjects = true
        analysisQueue.async { [weak self] in
            let analysis = try? SubjectAnalysis(image: image)
            DispatchQueue.main.async {
                self?.subjectAnalysis = analysis
                self?.isAnalyzingSubjects = false
            }
        }
    }

    func subjectImage(at point: CGPoint) -> UIImage? {
        guard let analysis = subjectAnalysis, displayedImageRect.contains(point) else {
            return nil
        }

        let normalizedPoint = CGPoint(
            x: (point.x - displayedImageRect.minX) / max(displayedImageRect.width, 1),
            y: 1 - (point.y - displayedImageRect.minY) / max(displayedImageRect.height, 1)
        )
        return analysis.subjectImage(at: normalizedPoint)
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
        addInteraction(UIContextMenuInteraction(delegate: self))
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
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return UIMenu(children: [])
            }

            var actions: [UIAction] = []
            if kind == .sticker, onDuplicate != nil {
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

private final class SubjectAnalysis {
    private let observation: VNInstanceMaskObservation
    private let requestHandler: VNImageRequestHandler
    private let ciContext = CIContext(options: nil)

    init(image: UIImage) throws {
        guard let cgImage = image.cgImage else {
            throw SubjectAnalysisError.missingCGImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw SubjectAnalysisError.noSubjects
        }

        self.observation = observation
        requestHandler = handler
    }

    func subjectImage(at normalizedPoint: CGPoint) -> UIImage? {
        guard let instance = instanceIndex(at: normalizedPoint) else {
            return nil
        }

        do {
            let maskedBuffer = try observation.generateMaskedImage(
                ofInstances: IndexSet(integer: instance),
                from: requestHandler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func instanceIndex(at normalizedPoint: CGPoint) -> Int? {
        let buffer = observation.instanceMask
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else {
            return nil
        }

        let clampedPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let imagePoint = VNImagePointForNormalizedPoint(clampedPoint, width - 1, height - 1)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let x = min(max(Int(imagePoint.x), 0), width - 1)
        let y = min(max(Int(imagePoint.y), 0), height - 1)
        let label = baseAddress.load(fromByteOffset: y * bytesPerRow + x, as: UInt8.self)
        let index = Int(label)
        guard index > 0, observation.allInstances.contains(index) else {
            return nil
        }
        return index
    }
}

private enum SubjectAnalysisError: Error {
    case missingCGImage
    case noSubjects
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
