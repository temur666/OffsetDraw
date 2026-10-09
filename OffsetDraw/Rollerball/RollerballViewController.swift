import UIKit

final class RollerballViewController: UIViewController, UITextFieldDelegate, UIScrollViewDelegate {
    private let canvas = RollerballCanvasView()
    private let remote = RollerballRemoteClient()
    private let address = UITextField()
    private let status = UILabel()
    private let parameters = UILabel()
    private let readout = UILabel()
    private let hint = UILabel()
    private var undoButton: UIBarButtonItem!
    private var redoButton: UIBarButtonItem!
    private var clearButton: UIBarButtonItem!
    private var lastSettings = RollerballSettings()
    private var visible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "走珠笔"
        view.backgroundColor = UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        navigationItem.largeTitleDisplayMode = .never
        undoButton = UIBarButtonItem(title: "撤销", style: .plain, target: self, action: #selector(undo))
        redoButton = UIBarButtonItem(title: "重做", style: .plain, target: self, action: #selector(redo))
        clearButton = UIBarButtonItem(title: "清空", style: .plain, target: self, action: #selector(clear))
        navigationItem.rightBarButtonItems = [clearButton, redoButton, undoButton]

        if let data = UserDefaults.standard.data(forKey: "rollerball.settings"),
           let saved = try? JSONDecoder().decode(RollerballSettings.self, from: data), saved.isValid {
            lastSettings = saved
        }
        canvas.settings = lastSettings
        address.text = UserDefaults.standard.string(forKey: "rollerball.address") ?? "192.168.0.101:18765"
        address.placeholder = "电脑的 Wi-Fi IP:端口"
        address.borderStyle = .roundedRect
        address.keyboardType = .numbersAndPunctuation
        address.autocorrectionType = .no
        address.autocapitalizationType = .none
        address.returnKeyType = .go
        address.delegate = self
        address.accessibilityLabel = "网页调参服务器 IP 和端口"
        address.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let connect = UIButton(type: .system)
        connect.setTitle("连接", for: .normal)
        connect.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        connect.setContentHuggingPriority(.required, for: .horizontal)
        let connection = UIStackView(arrangedSubviews: [address, connect])
        connection.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        parameters.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        parameters.textColor = .secondaryLabel
        parameters.numberOfLines = 0
        readout.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        readout.textColor = .secondaryLabel
        readout.numberOfLines = 0
        hint.text = "在这里试着写、画\n慢一点，再快一点，最后停笔。"
        hint.textColor = UIColor.white.withAlphaComponent(0.48)
        hint.font = .systemFont(ofSize: 17, weight: .regular)
        hint.textColor = .tertiaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.isUserInteractionEnabled = false
        canvas.addSubview(hint)
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -24)
        ])
        let viewport = UIScrollView()
        viewport.delegate = self
        viewport.backgroundColor = canvas.backgroundColor
        viewport.layer.cornerRadius = 16
        viewport.clipsToBounds = true
        viewport.showsHorizontalScrollIndicator = false
        viewport.showsVerticalScrollIndicator = false
        viewport.minimumZoomScale = 0.5
        viewport.maximumZoomScale = 4
        viewport.panGestureRecognizer.minimumNumberOfTouches = 2
        viewport.panGestureRecognizer.maximumNumberOfTouches = 2
        viewport.addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: viewport.contentLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: viewport.contentLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: viewport.contentLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: viewport.contentLayoutGuide.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: viewport.frameLayoutGuide.widthAnchor),
            canvas.heightAnchor.constraint(equalTo: viewport.frameLayoutGuide.heightAnchor)
        ])
        let stack = UIStackView(arrangedSubviews: [connection, status, parameters, viewport, readout])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            connection.heightAnchor.constraint(equalToConstant: 36)
        ])
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
        canvas.onChange = { [weak self] in self?.updateReadout() }
        remote.onStatus = { [weak self] message in self?.status.text = message }
        remote.onSettings = { [weak self] settings in
            guard let self, settings != self.lastSettings else { return }
            self.lastSettings = settings
            self.canvas.settings = settings
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "rollerball.settings")
            }
            self.updateReadout()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        updateReadout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        connectTapped()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        remote.stop()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func background() { remote.stop() }
    @objc private func foreground() { if visible { connectTapped() } }

    @objc private func connectTapped() {
        view.endEditing(true)
        let input = address.text ?? ""
        if RollerballRemoteClient.endpoint(address: input) != nil {
            UserDefaults.standard.set(input, forKey: "rollerball.address")
        }
        remote.start(address: input)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { connectTapped(); return true }
    @objc private func undo() { canvas.undo() }
    @objc private func redo() { canvas.redo() }
    @objc private func clear() { canvas.clear() }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    private func updateReadout() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        clearButton.isEnabled = !canvas.isDrawing && !canvas.strokes.isEmpty
        hint.isHidden = canvas.isDrawing || !canvas.strokes.isEmpty
        let settings = canvas.engine.stroke?.settings ?? lastSettings
        let pressure = canvas.isDrawing ? canvas.engine.pressure : settings.pressure
        let diameter = canvas.isDrawing ? canvas.engine.radius * 2 : settings.size * settings.pressure
        let speed = canvas.isDrawing ? canvas.engine.velocity : 0
        readout.text = String(format: "%d 笔 · 压力 %.0f%% · %.0f pt/s · 直径 %.2f pt", canvas.strokes.count, pressure * 100, speed, diameter)
        parameters.text = String(format: "笔尖 %.1f · 压力 %.0f%% · 变细速度 %.0f\n强度 %.1f · 响应 %.0f ms · 积墨 %.2f · %@", lastSettings.size, lastSettings.pressure * 100, lastSettings.speed, lastSettings.power, lastSettings.response, lastSettings.pool, lastSettings.color)
    }
}
