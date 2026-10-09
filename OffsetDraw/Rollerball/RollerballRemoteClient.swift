import Foundation

/// One in-flight request at a time; generations prevent an old host's response from being applied.
final class RollerballRemoteClient {
    var onSettings: ((RollerballSettings) -> Void)?
    var onStatus: ((String) -> Void)?
    private var task: URLSessionDataTask?
    private var pending: DispatchWorkItem?
    private var generation = UUID()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func endpoint(address: String) -> URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = text.hasPrefix("http://") ? text : "http://" + text
        guard var parts = URLComponents(string: input), parts.scheme == "http",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let host = parts.host else { return nil }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && (Int($0).map { (0...255).contains($0) } ?? false)
        }), (1...65535).contains(parts.port ?? 18765) else { return nil }
        parts.port = parts.port ?? 18765
        parts.path = "/api/settings"
        return parts.url
    }

    func start(address: String) {
        stop()
        guard let url = Self.endpoint(address: address) else {
            onStatus?("请输入电脑的 Wi-Fi IP，例如 192.168.0.101:18765")
            return
        }
        onStatus?("正在连接 \(url.host ?? "")…")
        poll(url: url, generation: generation)
    }

    func stop() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        task?.cancel()
        task = nil
    }

    private func poll(url: URL, generation current: UUID) {
        guard generation == current else { return }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.task = nil
                var connected = false
                if error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                   let data, data.count <= 4096,
                   let settings = try? JSONDecoder().decode(RollerballSettings.self, from: data), settings.isValid {
                    connected = true
                    self.onSettings?(settings)
                    self.onStatus?("已连接 · 网页改动将在下一笔生效")
                } else {
                    self.onStatus?("未连接 · 使用上次参数，自动重试中")
                }
                let work = DispatchWorkItem { [weak self] in self?.poll(url: url, generation: current) }
                self.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (connected ? 0.25 : 2), execute: work)
            }
        }
        task?.resume()
    }

    deinit {
        pending?.cancel()
        task?.cancel()
        session.invalidateAndCancel()
    }
}
