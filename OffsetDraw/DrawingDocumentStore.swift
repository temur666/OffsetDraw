import Foundation

enum DrawingDocumentStoreError: Error {
    case documentsDirectoryUnavailable
}

final class DrawingDocumentStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let documentsDirectory: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        guard let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DrawingDocumentStoreError.documentsDirectoryUnavailable
        }

        documentsDirectory = directory.appendingPathComponent("Drawings", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    }

    func listDocuments() -> [DrawingDocumentSummary] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? loadDocument(from: $0) }
            .map { DrawingDocumentSummary(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createDocument() throws -> DrawingDocument {
        let document = DrawingDocument.new(title: nextUntitledName())
        try save(document)
        return document
    }

    func loadDocument(id: UUID) throws -> DrawingDocument {
        try loadDocument(from: url(for: id))
    }

    func save(_ document: DrawingDocument) throws {
        let data = try encoder.encode(document)
        try data.write(to: url(for: document.id), options: [.atomic])
    }

    private func loadDocument(from url: URL) throws -> DrawingDocument {
        let data = try Data(contentsOf: url)
        return try decoder.decode(DrawingDocument.self, from: data)
    }

    private func url(for id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func nextUntitledName() -> String {
        let titles = Set(listDocuments().map(\.title))
        if !titles.contains("Untitled") {
            return "Untitled"
        }

        var index = 2
        while titles.contains("Untitled \(index)") {
            index += 1
        }
        return "Untitled \(index)"
    }
}
