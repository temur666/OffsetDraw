import UIKit
import Photos

final class ViewController: UIViewController {
    private let canvasView = DrawingCanvasView()
    private let undoButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let widthSlider = UISlider()
    private let widthValueLabel = UILabel()
    private let stabilizerSlider = UISlider()
    private let stabilizerValueLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        configureCanvas()
        configureToolbar()
    }

    private func configureCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
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
            exportButton
        ])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalSpacing
        buttonStack.spacing = 12

        let controlStack = UIStackView(arrangedSubviews: [
            widthSlider,
            widthValueLabel,
            stabilizerSlider,
            stabilizerValueLabel
        ])
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.axis = .horizontal
        controlStack.alignment = .center
        controlStack.spacing = 10

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

        widthSlider.minimumValue = 1
        widthSlider.maximumValue = 24
        widthSlider.value = Float(canvasView.brush.lineWidth)
        widthSlider.widthAnchor.constraint(equalToConstant: 112).isActive = true
        widthSlider.addTarget(self, action: #selector(widthChanged), for: .valueChanged)

        widthValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        widthValueLabel.textColor = .label
        widthValueLabel.textAlignment = .right
        widthValueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        updateWidthLabel()

        stabilizerSlider.minimumValue = 0
        stabilizerSlider.maximumValue = 120
        stabilizerSlider.value = Float(canvasView.brush.stabilizerRadius)
        stabilizerSlider.widthAnchor.constraint(equalToConstant: 112).isActive = true
        stabilizerSlider.addTarget(self, action: #selector(stabilizerChanged), for: .valueChanged)

        stabilizerValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        stabilizerValueLabel.textColor = .label
        stabilizerValueLabel.textAlignment = .right
        stabilizerValueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        updateStabilizerLabel()

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

    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateWidthLabel() {
        widthValueLabel.text = "\(Int(round(widthSlider.value)))pt"
    }

    private func updateStabilizerLabel() {
        stabilizerValueLabel.text = "\(Int(round(stabilizerSlider.value)))pt"
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
    }

    @objc private func stabilizerChanged() {
        canvasView.brush.stabilizerRadius = CGFloat(stabilizerSlider.value)
        updateStabilizerLabel()
    }

    private func presentMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
