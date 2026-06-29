import UIKit
import Photos

final class ViewController: UIViewController, UIColorPickerViewControllerDelegate {
    private let store: DrawingDocumentStore
    private var document: DrawingDocument
    private var isPersistingDocument = false
    private let canvasView = DrawingCanvasView()
    private let undoButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let brushColorButton = UIButton(type: .system)
    private let boardColorButton = UIButton(type: .system)
    private let widthSlider = UISlider()
    private let widthValueLabel = UILabel()
    private let stabilizerSlider = UISlider()
    private let stabilizerValueLabel = UILabel()
    private let movementScaleSlider = UISlider()
    private let movementScaleValueLabel = UILabel()
    private let smoothingSlider = UISlider()
    private let smoothingValueLabel = UILabel()

    init(store: DrawingDocumentStore, document: DrawingDocument) {
        self.store = store
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = document.title

        configureCanvas()
        configureToolbar()
        loadDocument()
    }

    private func configureCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.onDocumentChanged = { [weak self] in
            self?.persistDocument()
        }
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureToolbar() {
        let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 8
        toolbar.clipsToBounds = true
        view.addSubview(toolbar)

        let buttonStack = UIStackView(arrangedSubviews: [
            undoButton,
            clearButton,
            exportButton,
            brushColorButton,
            boardColorButton
        ])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalSpacing
        buttonStack.spacing = 12

        let widthControlStack = makeControlRow(arrangedSubviews: [
            widthSlider,
            widthValueLabel
        ])
        let stabilizerControlStack = makeControlRow(arrangedSubviews: [
            stabilizerSlider,
            stabilizerValueLabel
        ])
        let movementScaleControlStack = makeControlRow(arrangedSubviews: [
            movementScaleSlider,
            movementScaleValueLabel
        ])
        let smoothingControlStack = makeControlRow(arrangedSubviews: [
            smoothingSlider,
            smoothingValueLabel
        ])

        let controlStack = UIStackView(arrangedSubviews: [
            widthControlStack,
            stabilizerControlStack,
            movementScaleControlStack,
            smoothingControlStack
        ])
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.axis = .vertical
        controlStack.alignment = .fill
        controlStack.spacing = 6

        let stack = UIStackView(arrangedSubviews: [
            buttonStack,
            controlStack
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        toolbar.contentView.addSubview(stack)

        configureButton(undoButton, title: "Undo", action: #selector(undoTapped))
        configureButton(clearButton, title: "Clear", action: #selector(clearTapped))
        configureButton(exportButton, title: "Export", action: #selector(exportTapped))
        configureButton(brushColorButton, title: "Brush", action: #selector(brushColorTapped))
        configureButton(boardColorButton, title: "Board", action: #selector(boardColorTapped))

        widthSlider.minimumValue = 1
        widthSlider.maximumValue = 24
        widthSlider.value = Float(canvasView.brush.lineWidth)
        widthSlider.addTarget(self, action: #selector(widthChanged), for: .valueChanged)

        widthValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        widthValueLabel.textColor = .label
        widthValueLabel.textAlignment = .right
        widthValueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        updateWidthLabel()

        stabilizerSlider.minimumValue = 0
        stabilizerSlider.maximumValue = 120
        stabilizerSlider.value = Float(canvasView.brush.stabilizerRadius)
        stabilizerSlider.addTarget(self, action: #selector(stabilizerChanged), for: .valueChanged)

        stabilizerValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        stabilizerValueLabel.textColor = .label
        stabilizerValueLabel.textAlignment = .right
        stabilizerValueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        updateStabilizerLabel()

        movementScaleSlider.minimumValue = 0.05
        movementScaleSlider.maximumValue = 1
        movementScaleSlider.value = Float(canvasView.control.movementScale)
        movementScaleSlider.addTarget(self, action: #selector(movementScaleChanged), for: .valueChanged)

        movementScaleValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        movementScaleValueLabel.textColor = .label
        movementScaleValueLabel.textAlignment = .right
        movementScaleValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        updateMovementScaleLabel()

        smoothingSlider.minimumValue = 0
        smoothingSlider.maximumValue = 1
        smoothingSlider.value = Float(canvasView.control.smoothingAmount)
        smoothingSlider.addTarget(self, action: #selector(smoothingChanged), for: .valueChanged)

        smoothingValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        smoothingValueLabel.textColor = .label
        smoothingValueLabel.textAlignment = .right
        smoothingValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        updateSmoothingLabel()

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: toolbar.contentView.bottomAnchor, constant: -10)
        ])
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector?) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
    }

    private func makeControlRow(arrangedSubviews: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        return stack
    }

    private func updateWidthLabel() {
        widthValueLabel.text = "\(Int(round(widthSlider.value)))pt"
    }

    private func updateStabilizerLabel() {
        stabilizerValueLabel.text = "\(Int(round(stabilizerSlider.value)))pt"
    }

    private func updateMovementScaleLabel() {
        movementScaleValueLabel.text = String(format: "%.2fx", movementScaleSlider.value)
    }

    private func updateSmoothingLabel() {
        smoothingValueLabel.text = "\(Int(round(smoothingSlider.value * 100)))%"
    }

    @objc private func undoTapped() {
        canvasView.undoLastStroke()
    }

    @objc private func clearTapped() {
        canvasView.clearDrawing()
    }

    @objc private func exportTapped() {
        let image = canvasView.renderImage()
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.presentMessage("Photo access is needed to export.")
                }
                return
            }

            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            DispatchQueue.main.async {
                self?.presentMessage("Exported to Photos.")
            }
        }
    }

    @objc private func widthChanged() {
        canvasView.brush.lineWidth = CGFloat(widthSlider.value)
        updateWidthLabel()
        persistDocument()
    }

    @objc private func stabilizerChanged() {
        canvasView.brush.stabilizerRadius = CGFloat(stabilizerSlider.value)
        updateStabilizerLabel()
        persistDocument()
    }

    @objc private func movementScaleChanged() {
        canvasView.control.movementScale = CGFloat(movementScaleSlider.value)
        updateMovementScaleLabel()
        persistDocument()
    }

    @objc private func smoothingChanged() {
        canvasView.control.smoothingAmount = CGFloat(smoothingSlider.value)
        updateSmoothingLabel()
        persistDocument()
    }

    @objc private func brushColorTapped() {
        presentColorPicker(title: "Brush Color", color: canvasView.brush.color, tag: 1)
    }

    @objc private func boardColorTapped() {
        presentColorPicker(title: "Board Color", color: canvasView.boardColor, tag: 2)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        applyPickedColor(from: viewController)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        applyPickedColor(from: viewController)
    }

    private func loadDocument() {
        canvasView.load(
            strokes: document.strokes.map(\.model),
            brush: document.brush.model,
            control: document.control.model,
            boardColor: document.boardColor.uiColor
        )
        widthSlider.value = Float(canvasView.brush.lineWidth)
        stabilizerSlider.value = Float(canvasView.brush.stabilizerRadius)
        movementScaleSlider.value = Float(canvasView.control.movementScale)
        smoothingSlider.value = Float(canvasView.control.smoothingAmount)
        updateWidthLabel()
        updateStabilizerLabel()
        updateMovementScaleLabel()
        updateSmoothingLabel()
        updateColorButton(brushColorButton, color: canvasView.brush.color)
        updateColorButton(boardColorButton, color: canvasView.boardColor)
    }

    private func presentColorPicker(title: String, color: UIColor, tag: Int) {
        let picker = UIColorPickerViewController()
        picker.title = title
        picker.selectedColor = color
        picker.supportsAlpha = true
        picker.delegate = self
        picker.view.tag = tag
        present(picker, animated: true)
    }

    private func applyPickedColor(from picker: UIColorPickerViewController) {
        switch picker.view.tag {
        case 1:
            canvasView.brush.color = picker.selectedColor
            updateColorButton(brushColorButton, color: picker.selectedColor)
        case 2:
            canvasView.boardColor = picker.selectedColor
            updateColorButton(boardColorButton, color: picker.selectedColor)
        default:
            return
        }
        persistDocument()
    }

    private func updateColorButton(_ button: UIButton, color: UIColor) {
        button.tintColor = color
    }

    private func persistDocument() {
        guard !isPersistingDocument else {
            return
        }

        isPersistingDocument = true
        document.updatedAt = Date()
        document.boardColor = CodableColor(canvasView.boardColor)
        document.brush = BrushConfigDTO(brush: canvasView.brush)
        document.control = DrawingControlConfigDTO(control: canvasView.control)
        document.strokes = canvasView.strokes.map(StrokeDTO.init(stroke:))

        do {
            try store.save(document)
        } catch {
            presentMessage("Could not save file.")
        }
        isPersistingDocument = false
    }

    private func presentMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
