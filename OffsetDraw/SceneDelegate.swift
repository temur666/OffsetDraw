import UIKit
import PhotosUI
import VisionKit

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

private final class SubjectStickerOverlayView: UIView {
    var onImportPhoto: (() -> Void)?

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

        addSubview(photoView)
        bringControlsToFront()

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
        liftRecognizer.minimumPressDuration = 0.35
        liftRecognizer.allowableMovement = 18
        liftRecognizer.cancelsTouchesInView = false
        liftRecognizer.delegate = photoView
        photoView.addGestureRecognizer(liftRecognizer)
        photoView.panRecognizer.require(toFail: liftRecognizer)

        photoView.prepareSubjectAnalysis()
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

                self.beginLift(
                    subjectImage,
                    from: sourceView,
                    at: recognizer.location(in: self)
                )
            }

        case .changed:
            guard activeLiftSource === sourceView else {
                return
            }
            activeLiftPreview?.center = recognizer.location(in: self)

        case .ended:
            guard activeLiftSource === sourceView, activeLiftPreview != nil else {
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

        addSubview(preview)
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
            let duplicate = self.makeDuplicate(of: stickerView, image: image)
            self.addSubview(duplicate)
            self.bringControlsToFront()
        }

        addSubview(stickerView)
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

    private func makeDuplicate(of stickerView: TransformableImageView, image: UIImage) -> TransformableImageView {
        let duplicate = TransformableImageView(image: image, kind: .sticker)
        duplicate.bounds = stickerView.bounds
        duplicate.center = CGPoint(x: stickerView.center.x + 24, y: stickerView.center.y + 24)
        duplicate.transform = stickerView.transform
        duplicate.onDelete = { [weak duplicate] in duplicate?.removeFromSuperview() }
        return duplicate
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
        statusLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
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
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
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

        // Context menus also use a long press. Keep them off photos so VisionKit's
        // native image-subject lift owns that gesture. Stickers can still use menus.
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
