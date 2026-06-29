import UIKit

final class HomeViewController: UITableViewController {
    private let store: DrawingDocumentStore
    private var documents: [DrawingDocumentSummary] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: DrawingDocumentStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "OffsetDraw"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(newDocumentTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DocumentCell")
        reloadDocuments()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadDocuments()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        documents.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DocumentCell", for: indexPath)
        let document = documents[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = document.title
        configuration.secondaryText = dateFormatter.string(from: document.updatedAt)
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openDocument(id: documents[indexPath.row].id)
    }

    private func reloadDocuments() {
        documents = store.listDocuments()
        tableView.reloadData()
    }

    @objc private func newDocumentTapped() {
        do {
            let document = try store.createDocument()
            openDocument(id: document.id)
        } catch {
            presentMessage("Could not create file.")
        }
    }

    private func openDocument(id: UUID) {
        do {
            let document = try store.loadDocument(id: id)
            let viewController = ViewController(store: store, document: document)
            navigationController?.pushViewController(viewController, animated: true)
        } catch {
            presentMessage("Could not open file.")
        }
    }

    private func presentMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
