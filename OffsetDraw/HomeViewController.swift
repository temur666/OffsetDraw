import UIKit

final class HomeViewController: UICollectionViewController {
    private let store: DrawingDocumentStore
    private var documents: [DrawingDocumentSummary] = []
    private let emptyStateLabel = UILabel()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: DrawingDocumentStore) {
        self.store = store
        super.init(collectionViewLayout: HomeViewController.makeLayout())
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
        collectionView.backgroundColor = .systemBackground
        collectionView.register(DocumentCell.self, forCellWithReuseIdentifier: DocumentCell.reuseIdentifier)
        configureEmptyState()
        reloadDocuments()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadDocuments()
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        documents.count
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DocumentCell.reuseIdentifier,
            for: indexPath
        ) as? DocumentCell
        let document = documents[indexPath.item]
        cell?.configure(
            title: document.title,
            subtitle: dateFormatter.string(from: document.updatedAt),
            thumbnail: UIImage(contentsOfFile: document.thumbnailURL.path)
        )
        return cell ?? UICollectionViewCell()
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        openDocument(id: documents[indexPath.item].id)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let document = documents[indexPath.item]
        return UIContextMenuConfiguration(identifier: document.id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return UIMenu()
            }

            return UIMenu(children: [
                UIAction(title: "Rename") { [weak self] _ in
                    self?.presentRename(for: document)
                },
                UIAction(title: "Duplicate") { [weak self] _ in
                    self?.duplicateDocument(id: document.id)
                },
                UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                    self?.confirmDelete(document)
                }
            ])
        }
    }

    private static func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let columns = columnCount(for: environment.container.effectiveContentSize.width)
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(260)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 12, trailing: 6)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(260)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 10, bottom: 16, trailing: 10)
            return section
        }
    }

    private static func columnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<420:
            return 2
        case ..<760:
            return 3
        default:
            return 4
        }
    }

    private func reloadDocuments() {
        documents = store.listDocuments()
        collectionView.backgroundView = documents.isEmpty ? emptyStateLabel : nil
        collectionView.reloadData()
    }

    private func configureEmptyState() {
        emptyStateLabel.frame = collectionView.bounds
        emptyStateLabel.text = "No drawings"
        emptyStateLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
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

    private func presentRename(for document: DrawingDocumentSummary) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = document.title
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text else {
                return
            }

            do {
                try self.store.renameDocument(id: document.id, title: title)
                self.reloadDocuments()
            } catch {
                self.presentMessage("Could not rename file.")
            }
        })
        present(alert, animated: true)
    }

    private func duplicateDocument(id: UUID) {
        do {
            _ = try store.duplicateDocument(id: id)
            reloadDocuments()
        } catch {
            presentMessage("Could not duplicate file.")
        }
    }

    private func confirmDelete(_ document: DrawingDocumentSummary) {
        let alert = UIAlertController(title: nil, message: "Delete this drawing?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteDocument(id: document.id)
        })
        present(alert, animated: true)
    }

    private func deleteDocument(id: UUID) {
        do {
            try store.deleteDocument(id: id)
            reloadDocuments()
        } catch {
            presentMessage("Could not delete file.")
        }
    }

    private func presentMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class DocumentCell: UICollectionViewCell {
    static let reuseIdentifier = "DocumentCell"

    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, subtitle: String, thumbnail: UIImage?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        thumbnailView.image = thumbnail ?? placeholderImage()
    }

    private func configure() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.backgroundColor = .white
        thumbnailView.contentMode = .scaleAspectFit
        thumbnailView.clipsToBounds = true
        contentView.addSubview(thumbnailView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: thumbnailView.widthAnchor, multiplier: 1.28),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func placeholderImage() -> UIImage {
        let size = CGSize(width: 320, height: 426)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemGray5.setStroke()
            let rect = CGRect(x: 16, y: 16, width: size.width - 32, height: size.height - 32)
            UIBezierPath(roundedRect: rect, cornerRadius: 8).stroke()
        }
    }
}
