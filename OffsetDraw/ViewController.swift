import UIKit
import Photos

final class ViewController: UIViewController, UIColorPickerViewControllerDelegate {
    private enum ColorPickerTarget: Int {
        case brush = 1
        case board = 2
    }

    private enum HandPreset: Int, CaseIterable {
        case precise
        case balanced
        case slow

        var title: String {
            switch self {
            case .precise:
                return "Precise"
            case .balanced:
                return "Balanced"
            case .slow:
                return "Slow"
            }
        }

        var brush: BrushConfig {
            switch self {
            case .precise:
                return BrushConfig(color: .black, lineWidth: BrushConfig.initial.lineWidth, stabilizerRadius: 18, blendMode: .normal)
            case .balanced:
                return BrushConfig(color: .black, lineWidth: BrushConfig.initial.lineWidth, stabilizerRadius: 40, blendMode: .normal)
            case .slow:
                return BrushConfig(color: .black, lineWidth: BrushConfig.initial.lineWidth, stabilizerRadius: 72, blendMode: .normal)
            }
        }

        var control: DrawingControlConfig {
            switch self {
            case .precise:
                return DrawingControlConfig(
                    movementScale: 0.45,
                    smoothingAmount: 0.25,
                    showsStabilizerGuide: true,
                    requiresLongPress: true
                )
            case .balanced:
                return DrawingControlConfig(
                    movementScale: 0.25,
                    smoothingAmount: 0.5,
                    showsStabilizerGuide: true,
                    requiresLongPress: true
                )
            case .slow:
                return DrawingControlConfig(
                    movementScale: 0.16,
                    smoothingAmount: 0.7,
                    showsStabilizerGuide: true,
                    requiresLongPress: false
                )
            }
        }
    }

    private enum BrushPreset: Int, CaseIterable {
        case fine
        case regular
        case bold

        var title: String {
            switch self {
            case .fine:
                return "Fine"
            case .regular:
                return "Regular"
            case .bold:
                return "Bold"
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .fine:
                return 3
            case .regular:
                return 6
            case .bold:
                return 12
            }
        }
    }

    private let store: DrawingDocumentStore
    private var document: DrawingDocument
    private var isPersistingDocument = false
    private let canvasView = DrawingCanvasView()
    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let panelStack = UIStackView()
    private let statusLabel = UILabel()
    private let undoButton = UIButton(type: .system)
    private let toolButton = UIButton(type: .system)
    private let brushColorButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let boardColorButton = UIButton(type: .system)
    private let layerButton = UIButton(type: .system)
    private let layerControl = UISegmentedControl(items: [])
    private let addLayerButton = UIButton(type: .system)
    private let renameLayerButton = UIButton(type: .system)
    private let toggleLayerButton = UIButton(type: .system)
    private let mergeLayerButton = UIButton(type: .system)
    private let moveLayerUpButton = UIButton(type: .system)
    private let moveLayerDownButton = UIButton(type: .system)
    private let deleteLayerButton = UIButton(type: .system)
    private let layerOpacitySlider = UISlider()
    private let layerOpacityValueLabel = UILabel()
    private let calibrationButton = UIButton(type: .system)
    private let calibrationIssuesButton = UIButton(type: .system)
    private let guideSwitch = UISwitch()
    private let calibrationOverlaySwitch = UISwitch()
    private let longPressSwitch = UISwitch()
    private let transparentExportSwitch = UISwitch()
    private let canvasSizeControl = UISegmentedControl(items: ["Phone", "Square", "Wide"])
    private let presetControl = UISegmentedControl(items: HandPreset.allCases.map(\.title))
    private let brushPresetControl = UISegmentedControl(items: BrushPreset.allCases.map(\.title))
    private let toolControl = UISegmentedControl(items: ["Brush", "Eraser"])
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
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 8
        toolbar.clipsToBounds = true
        view.addSubview(toolbar)

        let primaryStack = UIStackView(arrangedSubviews: [
            undoButton,
            toolButton,
            brushColorButton,
            moreButton
        ])
        primaryStack.translatesAutoresizingMaskIntoConstraints = false
        primaryStack.axis = .horizontal
        primaryStack.alignment = .center
        primaryStack.distribution = .fillEqually
        primaryStack.spacing = 12

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1

        panelStack.translatesAutoresizingMaskIntoConstraints = false
        panelStack.axis = .vertical
        panelStack.alignment = .fill
        panelStack.spacing = 8
        panelStack.isHidden = true

        panelStack.addArrangedSubview(makeSegmentRow(title: "Tool", control: toolControl))
        panelStack.addArrangedSubview(makeSegmentRow(title: "Brush", control: brushPresetControl))
        panelStack.addArrangedSubview(makeSegmentRow(title: "Preset", control: presetControl))
        panelStack.addArrangedSubview(makeControlRow(title: "Width", control: widthSlider, valueLabel: widthValueLabel))
        panelStack.addArrangedSubview(makeControlRow(title: "Stabilizer", control: stabilizerSlider, valueLabel: stabilizerValueLabel))
        panelStack.addArrangedSubview(makeControlRow(title: "Movement", control: movementScaleSlider, valueLabel: movementScaleValueLabel))
        panelStack.addArrangedSubview(makeControlRow(title: "Smoothing", control: smoothingSlider, valueLabel: smoothingValueLabel))
        panelStack.addArrangedSubview(makeSegmentRow(title: "Canvas", control: canvasSizeControl))
        panelStack.addArrangedSubview(makeSegmentRow(title: "Layer", control: layerControl))
        panelStack.addArrangedSubview(makeControlRow(title: "Opacity", control: layerOpacitySlider, valueLabel: layerOpacityValueLabel))
        panelStack.addArrangedSubview(makeSwitchRow(title: "Guide", toggle: guideSwitch))
        panelStack.addArrangedSubview(makeSwitchRow(title: "Calib. grid", toggle: calibrationOverlaySwitch))
        panelStack.addArrangedSubview(makeSwitchRow(title: "Hold", toggle: longPressSwitch))
        panelStack.addArrangedSubview(makeSwitchRow(title: "Transparent", toggle: transparentExportSwitch))
        panelStack.addArrangedSubview(makeLayerActionRow())
        panelStack.addArrangedSubview(makeActionRow())

        let stack = UIStackView(arrangedSubviews: [
            primaryStack,
            statusLabel,
            panelStack
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        toolbar.contentView.addSubview(stack)

        configureButton(undoButton, title: "Undo", action: #selector(undoTapped))
        configureButton(toolButton, title: "Brush", action: #selector(toolTapped))
        configureButton(brushColorButton, title: "Color", action: #selector(brushColorTapped))
        configureButton(moreButton, title: "More", action: #selector(moreTapped))
        configureButton(clearButton, title: "Clear", action: #selector(clearTapped))
        configureButton(exportButton, title: "Export", action: #selector(exportTapped))
        configureButton(boardColorButton, title: "Board", action: #selector(boardColorTapped))
        configureButton(layerButton, title: "Layer", action: #selector(addLayerTapped))
        configureButton(addLayerButton, title: "Add Layer", action: #selector(addLayerTapped))
        configureButton(renameLayerButton, title: "Rename", action: #selector(renameLayerTapped))
        configureButton(toggleLayerButton, title: "Hide Layer", action: #selector(toggleLayerTapped))
        configureButton(mergeLayerButton, title: "Merge Down", action: #selector(mergeLayerTapped))
        configureButton(moveLayerUpButton, title: "Move Up", action: #selector(moveLayerUpTapped))
        configureButton(moveLayerDownButton, title: "Move Down", action: #selector(moveLayerDownTapped))
        configureButton(deleteLayerButton, title: "Delete Layer", action: #selector(deleteLayerTapped))
        configureButton(calibrationButton, title: "Calibrate", action: #selector(calibrationTapped))
        configureButton(calibrationIssuesButton, title: "Issues", action: #selector(calibrationIssuesTapped))

        toolControl.selectedSegmentIndex = 0
        toolControl.addTarget(self, action: #selector(toolControlChanged), for: .valueChanged)
        brushPresetControl.selectedSegmentIndex = BrushPreset.regular.rawValue
        brushPresetControl.addTarget(self, action: #selector(brushPresetChanged), for: .valueChanged)
        presetControl.selectedSegmentIndex = HandPreset.balanced.rawValue
        presetControl.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        canvasSizeControl.selectedSegmentIndex = 0
        canvasSizeControl.addTarget(self, action: #selector(canvasSizeChanged), for: .valueChanged)
        layerControl.addTarget(self, action: #selector(layerChanged), for: .valueChanged)

        configureSlider(widthSlider, minimum: 1, maximum: 24, action: #selector(widthChanged))
        configureSlider(stabilizerSlider, minimum: 0, maximum: 120, action: #selector(stabilizerChanged))
        configureSlider(movementScaleSlider, minimum: 0.05, maximum: 1, action: #selector(movementScaleChanged))
        configureSlider(smoothingSlider, minimum: 0, maximum: 1, action: #selector(smoothingChanged))
        configureSlider(layerOpacitySlider, minimum: 0, maximum: 1, action: #selector(layerOpacityChanged))

        configureValueLabel(widthValueLabel, width: 42)
        configureValueLabel(stabilizerValueLabel, width: 46)
        configureValueLabel(movementScaleValueLabel, width: 52)
        configureValueLabel(smoothingValueLabel, width: 48)
        configureValueLabel(layerOpacityValueLabel, width: 48)

        guideSwitch.addTarget(self, action: #selector(guideChanged), for: .valueChanged)
        calibrationOverlaySwitch.addTarget(self, action: #selector(calibrationOverlayChanged), for: .valueChanged)
        longPressSwitch.addTarget(self, action: #selector(longPressChanged), for: .valueChanged)
        transparentExportSwitch.addTarget(self, action: #selector(transparentExportChanged), for: .valueChanged)

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
        button.setContentHuggingPriority(.required, for: .horizontal)
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
    }

    private func configureSlider(_ slider: UISlider, minimum: Float, maximum: Float, action: Selector) {
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.addTarget(self, action: action, for: .valueChanged)
    }

    private func configureValueLabel(_ label: UILabel, width: CGFloat) {
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.textAlignment = .right
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func makeControlRow(title: String, control: UIView, valueLabel: UILabel) -> UIStackView {
        let label = makeRowLabel(title)
        let stack = UIStackView(arrangedSubviews: [label, control, valueLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        return stack
    }

    private func makeSegmentRow(title: String, control: UISegmentedControl) -> UIStackView {
        let label = makeRowLabel(title)
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        return stack
    }

    private func makeSwitchRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = makeRowLabel(title)
        let stack = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        return stack
    }

    private func makeActionRow() -> UIStackView {
        let firstRow = UIStackView(arrangedSubviews: [
            calibrationButton,
            calibrationIssuesButton,
            layerButton
        ])
        firstRow.translatesAutoresizingMaskIntoConstraints = false
        firstRow.axis = .horizontal
        firstRow.alignment = .center
        firstRow.distribution = .fillEqually
        firstRow.spacing = 8

        let secondRow = UIStackView(arrangedSubviews: [
            boardColorButton,
            exportButton,
            clearButton
        ])
        secondRow.translatesAutoresizingMaskIntoConstraints = false
        secondRow.axis = .horizontal
        secondRow.alignment = .center
        secondRow.distribution = .fillEqually
        secondRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [firstRow, secondRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        return stack
    }

    private func makeLayerActionRow() -> UIStackView {
        let firstRow = UIStackView(arrangedSubviews: [
            addLayerButton,
            renameLayerButton,
            toggleLayerButton
        ])
        firstRow.translatesAutoresizingMaskIntoConstraints = false
        firstRow.axis = .horizontal
        firstRow.alignment = .center
        firstRow.distribution = .fillEqually
        firstRow.spacing = 8

        let secondRow = UIStackView(arrangedSubviews: [
            mergeLayerButton,
            moveLayerUpButton,
            moveLayerDownButton
        ])
        secondRow.translatesAutoresizingMaskIntoConstraints = false
        secondRow.axis = .horizontal
        secondRow.alignment = .center
        secondRow.distribution = .fillEqually
        secondRow.spacing = 8

        let thirdRow = UIStackView(arrangedSubviews: [
            deleteLayerButton
        ])
        thirdRow.translatesAutoresizingMaskIntoConstraints = false
        thirdRow.axis = .horizontal
        thirdRow.alignment = .center
        thirdRow.distribution = .fillEqually
        thirdRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [firstRow, secondRow, thirdRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        return stack
    }

    private func makeRowLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        return label
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

    private func updateStatusLabel() {
        let tool = canvasView.brush.blendMode == .clear ? "Eraser" : "Brush"
        let hold = canvasView.control.requiresLongPress ? "Hold" : "Direct"
        let visibility = canvasView.isActiveLayerVisible ? "" : " Off"
        statusLabel.text = "\(tool) | \(Int(round(canvasView.brush.lineWidth)))pt | \(canvasView.activeLayerTitle)\(visibility) | \(hold)"
    }

    private func updateUndoState() {
        undoButton.isEnabled = !canvasView.strokes.isEmpty
        undoButton.alpha = undoButton.isEnabled ? 1 : 0.45
    }

    private func updateToolState() {
        let isEraser = canvasView.brush.blendMode == .clear
        toolButton.setTitle(isEraser ? "Eraser" : "Brush", for: .normal)
        toolControl.selectedSegmentIndex = isEraser ? 1 : 0
        brushColorButton.isEnabled = !isEraser
        brushColorButton.alpha = isEraser ? 0.45 : 1
        updateStatusLabel()
    }

    private func updateLayerControls() {
        layerControl.removeAllSegments()
        for (index, layer) in canvasView.layers.enumerated() {
            let visibility = layer.isVisible ? "" : " Off"
            layerControl.insertSegment(withTitle: "\(index + 1)\(visibility)", at: index, animated: false)
        }

        let selectedIndex = canvasView.layers.firstIndex(where: { $0.id == canvasView.activeLayerID }) ?? 0
        layerControl.selectedSegmentIndex = selectedIndex
        layerButton.setTitle(canvasView.activeLayerTitle, for: .normal)
        let activeLayer = canvasView.layers.first(where: { $0.id == canvasView.activeLayerID })
        let activeLayerIndex = canvasView.layers.firstIndex(where: { $0.id == canvasView.activeLayerID }) ?? 0
        layerOpacitySlider.value = Float(activeLayer?.opacity ?? 1)
        updateLayerOpacityLabel()
        toggleLayerButton.setTitle(activeLayer?.isVisible == true ? "Hide Layer" : "Show Layer", for: .normal)
        mergeLayerButton.isEnabled = activeLayerIndex > 0
        mergeLayerButton.alpha = activeLayerIndex > 0 ? 1 : 0.45
        moveLayerUpButton.isEnabled = activeLayerIndex < canvasView.layers.count - 1
        moveLayerUpButton.alpha = moveLayerUpButton.isEnabled ? 1 : 0.45
        moveLayerDownButton.isEnabled = activeLayerIndex > 0
        moveLayerDownButton.alpha = moveLayerDownButton.isEnabled ? 1 : 0.45
        deleteLayerButton.isEnabled = canvasView.layers.count > 1
        deleteLayerButton.alpha = canvasView.layers.count > 1 ? 1 : 0.45
    }

    private func updateLayerOpacityLabel() {
        layerOpacityValueLabel.text = "\(Int(round(layerOpacitySlider.value * 100)))%"
    }

    @objc private func undoTapped() {
        canvasView.undoLastStroke()
        updateUndoState()
    }

    @objc private func toolTapped() {
        canvasView.ensureActiveLayerVisible()
        canvasView.brush.blendMode = canvasView.brush.blendMode == .clear ? .normal : .clear
        updateToolState()
        persistDocument()
    }

    @objc private func moreTapped() {
        panelStack.isHidden.toggle()
        moreButton.setTitle(panelStack.isHidden ? "More" : "Done", for: .normal)
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(title: nil, message: "Clear this drawing?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.canvasView.clearDrawing()
        })
        present(alert, animated: true)
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

            if self?.canvasView.canvasConfig.isTransparentExportEnabled == true {
                self?.savePNGToPhotos(image)
            } else {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                DispatchQueue.main.async {
                    self?.presentMessage("Exported to Photos.")
                }
            }
        }
    }

    @objc private func toolControlChanged() {
        canvasView.ensureActiveLayerVisible()
        canvasView.brush.blendMode = toolControl.selectedSegmentIndex == 1 ? .clear : .normal
        updateToolState()
        persistDocument()
    }

    @objc private func presetChanged() {
        guard let preset = HandPreset(rawValue: presetControl.selectedSegmentIndex) else {
            return
        }

        let previousColor = canvasView.brush.color
        let previousBlendMode = canvasView.brush.blendMode
        let previousLineWidth = canvasView.brush.lineWidth
        var brush = preset.brush
        brush.color = previousColor
        brush.blendMode = previousBlendMode
        brush.lineWidth = previousLineWidth
        canvasView.brush = brush
        canvasView.control = preset.control
        syncControlsFromCanvas()
        persistDocument()
    }

    @objc private func brushPresetChanged() {
        guard let preset = BrushPreset(rawValue: brushPresetControl.selectedSegmentIndex) else {
            return
        }

        canvasView.brush.lineWidth = preset.lineWidth
        syncControlsFromCanvas()
        persistDocument()
    }

    @objc private func widthChanged() {
        canvasView.ensureActiveLayerVisible()
        canvasView.brush.lineWidth = CGFloat(widthSlider.value)
        updateWidthLabel()
        updateStatusLabel()
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

    @objc private func guideChanged() {
        canvasView.control.showsStabilizerGuide = guideSwitch.isOn
        persistDocument()
    }

    @objc private func longPressChanged() {
        canvasView.control.requiresLongPress = longPressSwitch.isOn
        persistDocument()
    }

    @objc private func calibrationOverlayChanged() {
        canvasView.showsCalibrationOverlay = calibrationOverlaySwitch.isOn
    }

    @objc private func transparentExportChanged() {
        canvasView.canvasConfig.isTransparentExportEnabled = transparentExportSwitch.isOn
        persistDocument()
    }

    @objc private func canvasSizeChanged() {
        switch canvasSizeControl.selectedSegmentIndex {
        case 1:
            canvasView.canvasConfig.width = 1080
            canvasView.canvasConfig.height = 1080
        case 2:
            canvasView.canvasConfig.width = 1440
            canvasView.canvasConfig.height = 1080
        default:
            canvasView.canvasConfig.width = 1080
            canvasView.canvasConfig.height = 1440
        }
        persistDocument()
    }

    @objc private func layerChanged() {
        canvasView.selectLayer(at: layerControl.selectedSegmentIndex)
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func addLayerTapped() {
        canvasView.addLayer()
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func toggleLayerTapped() {
        canvasView.toggleActiveLayerVisibility()
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func renameLayerTapped() {
        let alert = UIAlertController(title: "Rename Layer", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.text = self?.canvasView.activeLayerTitle
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text else {
                return
            }

            canvasView.renameActiveLayer(to: title)
            updateLayerControls()
            updateStatusLabel()
            persistDocument()
        })
        present(alert, animated: true)
    }

    @objc private func layerOpacityChanged() {
        canvasView.setActiveLayerOpacity(CGFloat(layerOpacitySlider.value))
        updateLayerOpacityLabel()
        persistDocument()
    }

    @objc private func mergeLayerTapped() {
        canvasView.mergeActiveLayerDown()
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func moveLayerUpTapped() {
        canvasView.moveActiveLayer(up: true)
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func moveLayerDownTapped() {
        canvasView.moveActiveLayer(up: false)
        updateLayerControls()
        updateStatusLabel()
        persistDocument()
    }

    @objc private func deleteLayerTapped() {
        guard canvasView.layers.count > 1 else {
            return
        }

        let alert = UIAlertController(title: nil, message: "Delete this layer?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.canvasView.deleteActiveLayer()
            self?.updateLayerControls()
            self?.updateStatusLabel()
            self?.persistDocument()
        })
        present(alert, animated: true)
    }

    @objc private func calibrationTapped() {
        let alert = UIAlertController(title: "Calibration", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.placeholder = "Hand feel notes"
            textField.text = self?.canvasView.canvasConfig.calibrationNotes
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else {
                return
            }

            let note = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            canvasView.canvasConfig.calibrationNotes = note?.isEmpty == false ? note : nil
            persistDocument()
        })
        present(alert, animated: true)
    }

    @objc private func calibrationIssuesTapped() {
        var calibration = canvasView.canvasConfig.calibration ?? .initial
        let alert = UIAlertController(title: "Calibration Issues", message: nil, preferredStyle: .actionSheet)
        let items: [(String, WritableKeyPath<CalibrationCheckDTO, Bool>)] = [
            ("Long press", \.longPressFeelsSlow),
            ("Stabilizer", \.stabilizerFeelsHeavy),
            ("Movement", \.movementFeelsWrong),
            ("Smoothing", \.smoothingFeelsLaggy),
            ("Guide", \.guideFeelsDistracting),
            ("Cursor", \.cursorFeelsUnclear)
        ]

        for item in items {
            let isOn = calibration[keyPath: item.1]
            alert.addAction(UIAlertAction(title: "\(isOn ? "On: " : "")\(item.0)", style: .default) { [weak self] _ in
                calibration[keyPath: item.1].toggle()
                self?.canvasView.canvasConfig.calibration = calibration
                self?.persistDocument()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = calibrationIssuesButton
        alert.popoverPresentationController?.sourceRect = calibrationIssuesButton.bounds
        present(alert, animated: true)
    }

    @objc private func brushColorTapped() {
        presentColorPicker(title: "Brush Color", color: canvasView.brush.color, target: .brush)
    }

    @objc private func boardColorTapped() {
        presentColorPicker(title: "Board Color", color: canvasView.boardColor, target: .board)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        applyPickedColor(from: viewController)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        applyPickedColor(from: viewController)
    }

    private func loadDocument() {
        canvasView.load(
            strokes: document.resolvedStrokes,
            brush: document.brush.model,
            control: document.control.model,
            boardColor: document.boardColor.uiColor,
            canvas: document.canvas ?? .initial,
            layers: document.resolvedLayers,
            activeLayerID: document.resolvedActiveLayerID
        )
        syncControlsFromCanvas()
    }

    private func syncControlsFromCanvas() {
        widthSlider.value = Float(canvasView.brush.lineWidth)
        stabilizerSlider.value = Float(canvasView.brush.stabilizerRadius)
        movementScaleSlider.value = Float(canvasView.control.movementScale)
        smoothingSlider.value = Float(canvasView.control.smoothingAmount)
        guideSwitch.isOn = canvasView.control.showsStabilizerGuide
        calibrationOverlaySwitch.isOn = canvasView.showsCalibrationOverlay
        longPressSwitch.isOn = canvasView.control.requiresLongPress
        transparentExportSwitch.isOn = canvasView.canvasConfig.isTransparentExportEnabled
        canvasSizeControl.selectedSegmentIndex = selectedCanvasSizeIndex()
        brushPresetControl.selectedSegmentIndex = selectedBrushPresetIndex()
        updateWidthLabel()
        updateStabilizerLabel()
        updateMovementScaleLabel()
        updateSmoothingLabel()
        updateToolState()
        updateLayerControls()
        updateUndoState()
        updateColorButton(brushColorButton, color: canvasView.brush.color)
        updateColorButton(boardColorButton, color: canvasView.boardColor)
        updateStatusLabel()
    }

    private func presentColorPicker(title: String, color: UIColor, target: ColorPickerTarget) {
        let picker = UIColorPickerViewController()
        picker.title = title
        picker.selectedColor = color
        picker.supportsAlpha = true
        picker.delegate = self
        picker.view.tag = target.rawValue
        present(picker, animated: true)
    }

    private func selectedCanvasSizeIndex() -> Int {
        let canvas = canvasView.canvasConfig
        if abs(canvas.width - canvas.height) < 1 {
            return 1
        }

        if canvas.width > canvas.height {
            return 2
        }

        return 0
    }

    private func selectedBrushPresetIndex() -> Int {
        let width = canvasView.brush.lineWidth
        let closest = BrushPreset.allCases.min {
            abs($0.lineWidth - width) < abs($1.lineWidth - width)
        }
        return closest?.rawValue ?? BrushPreset.regular.rawValue
    }

    private func applyPickedColor(from picker: UIColorPickerViewController) {
        guard let target = ColorPickerTarget(rawValue: picker.view.tag) else {
            return
        }

        switch target {
        case .brush:
            canvasView.brush.color = picker.selectedColor
            updateColorButton(brushColorButton, color: picker.selectedColor)
        case .board:
            canvasView.boardColor = picker.selectedColor
            updateColorButton(boardColorButton, color: picker.selectedColor)
        }
        persistDocument()
    }

    private func updateColorButton(_ button: UIButton, color: UIColor) {
        button.tintColor = color
    }

    private func savePNGToPhotos(_ image: UIImage) {
        guard let data = image.pngData() else {
            DispatchQueue.main.async { [weak self] in
                self?.presentMessage("Could not export file.")
            }
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        } completionHandler: { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.presentMessage(success ? "Exported to Photos." : "Could not export file.")
            }
        }
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
        document.canvas = canvasView.canvasConfig
        document.layers = canvasView.layers.map(DrawingLayerDTO.init(layer:))
        document.activeLayerID = canvasView.activeLayerID
        document.strokes = canvasView.strokes.map(StrokeDTO.init(stroke:))

        do {
            try store.save(document)
            try store.saveThumbnail(canvasView.renderImage(thumbnailSize: CGSize(width: 320, height: 426)), for: document.id)
            updateUndoState()
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
