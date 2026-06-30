import UIKit

enum DrawingDocumentStoreError: Error {
    case documentsDirectoryUnavailable
}

final class DrawingDocumentStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let documentsDirectory: URL
    private let thumbnailsDirectory: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        guard let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DrawingDocumentStoreError.documentsDirectoryUnavailable
        }

        documentsDirectory = directory.appendingPathComponent("Drawings", isDirectory: true)
        thumbnailsDirectory = directory.appendingPathComponent("DrawingThumbnails", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
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
            .map { document in
                if !fileManager.fileExists(atPath: thumbnailURL(for: document.id).path) {
                    try? saveThumbnail(renderThumbnail(for: document), for: document.id)
                }
                return document
            }
            .map {
                DrawingDocumentSummary(
                    id: $0.id,
                    title: $0.title,
                    updatedAt: $0.updatedAt,
                    thumbnailURL: thumbnailURL(for: $0.id)
                )
            }
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

    func renameDocument(id: UUID, title: String) throws {
        var document = try loadDocument(id: id)
        document.title = sanitizedTitle(title, fallback: document.title)
        document.updatedAt = Date()
        try save(document)
    }

    func duplicateDocument(id: UUID) throws -> DrawingDocument {
        let source = try loadDocument(id: id)
        let now = Date()
        var copy = source
        copy.id = UUID()
        copy.title = copyName(for: source.title)
        copy.createdAt = now
        copy.updatedAt = now
        try save(copy)
        if let image = UIImage(contentsOfFile: thumbnailURL(for: source.id).path) {
            try saveThumbnail(image, for: copy.id)
        }
        return copy
    }

    func deleteDocument(id: UUID) throws {
        let documentURL = url(for: id)
        if fileManager.fileExists(atPath: documentURL.path) {
            try fileManager.removeItem(at: documentURL)
        }

        let thumbnailURL = thumbnailURL(for: id)
        if fileManager.fileExists(atPath: thumbnailURL.path) {
            try fileManager.removeItem(at: thumbnailURL)
        }
    }

    func thumbnailURL(for id: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("png")
    }

    func saveThumbnail(_ image: UIImage, for id: UUID) throws {
        guard let data = image.pngData() else {
            return
        }
        try data.write(to: thumbnailURL(for: id), options: [.atomic])
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

    private func copyName(for title: String) -> String {
        let titles = Set(listDocuments().map(\.title))
        let baseTitle = "\(title) Copy"
        if !titles.contains(baseTitle) {
            return baseTitle
        }

        var index = 2
        while titles.contains("\(baseTitle) \(index)") {
            index += 1
        }
        return "\(baseTitle) \(index)"
    }

    private func sanitizedTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func renderThumbnail(for document: DrawingDocument) -> UIImage {
        let size = CGSize(width: 320, height: 426)
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = !(document.canvas?.isTransparentExportEnabled ?? false)

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            let cgContext = context.cgContext
            if document.canvas?.isTransparentExportEnabled == true {
                cgContext.clear(bounds)
            } else {
                document.boardColor.uiColor.setFill()
                cgContext.fill(bounds)
            }

            let visibleLayers = document.resolvedLayers.filter(\.isVisible)
            let canvas = document.canvas ?? .initial
            let scale = min(size.width / max(canvas.width, 1), size.height / max(canvas.height, 1))
            let renderedSize = CGSize(width: canvas.width * scale, height: canvas.height * scale)
            cgContext.translateBy(
                x: (size.width - renderedSize.width) / 2,
                y: (size.height - renderedSize.height) / 2
            )
            cgContext.scaleBy(x: scale, y: scale)
            for layer in visibleLayers {
                let layerStrokes = document.resolvedStrokes.filter { $0.layerID == layer.id }
                cgContext.saveGState()
                cgContext.setAlpha(layer.opacity)
                cgContext.beginTransparencyLayer(auxiliaryInfo: nil)

                for stroke in layerStrokes {
                    draw(stroke: stroke, in: cgContext)
                }

                cgContext.endTransparencyLayer()
                cgContext.restoreGState()
            }
        }
    }

    private func draw(stroke: Stroke, in context: CGContext) {
        guard let firstPoint = stroke.points.first?.position else {
            return
        }

        context.saveGState()
        context.setBlendMode(stroke.brush.blendMode)
        context.setStrokeColor(stroke.brush.color.cgColor)
        context.setLineWidth(stroke.brush.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if stroke.points.count == 1 {
            context.setFillColor(stroke.brush.color.cgColor)
            let radius = stroke.brush.lineWidth / 2
            context.fillEllipse(in: CGRect(
                x: firstPoint.x - radius,
                y: firstPoint.y - radius,
                width: stroke.brush.lineWidth,
                height: stroke.brush.lineWidth
            ))
        } else {
            context.beginPath()
            context.move(to: firstPoint)

            for index in 1..<stroke.points.count {
                let current = stroke.points[index].position
                let previous = stroke.points[index - 1].position
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                context.addQuadCurve(to: midpoint, control: previous)
            }

            if let lastPoint = stroke.points.last?.position {
                context.addLine(to: lastPoint)
            }

            context.strokePath()
        }

        context.restoreGState()
    }
}
