import UIKit

struct StrokePoint {
    let position: CGPoint
    let timestamp: TimeInterval
}

struct BrushConfig {
    var color: UIColor
    var lineWidth: CGFloat
    var stabilizerRadius: CGFloat
    var blendMode: CGBlendMode

    static let initial = BrushConfig(color: .black, lineWidth: 6, stabilizerRadius: 40, blendMode: .normal)
}

struct DrawingControlConfig {
    var movementScale: CGFloat
    var smoothingAmount: CGFloat
    var showsStabilizerGuide: Bool
    var requiresLongPress: Bool

    static let initial = DrawingControlConfig(
        movementScale: 0.25,
        smoothingAmount: 0.5,
        showsStabilizerGuide: true,
        requiresLongPress: true
    )
}

struct Stroke {
    let points: [StrokePoint]
    let brush: BrushConfig
    let layerID: UUID
}

struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(red: red, green: green, blue: blue, alpha: alpha)
        } else {
            self.init(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct StrokePointDTO: Codable {
    var x: CGFloat
    var y: CGFloat
    var timestamp: TimeInterval

    init(point: StrokePoint) {
        x = point.position.x
        y = point.position.y
        timestamp = point.timestamp
    }

    var model: StrokePoint {
        StrokePoint(position: CGPoint(x: x, y: y), timestamp: timestamp)
    }
}

struct BrushConfigDTO: Codable {
    var color: CodableColor
    var lineWidth: CGFloat
    var stabilizerRadius: CGFloat
    var blendMode: StrokeBlendMode?

    init(brush: BrushConfig) {
        color = CodableColor(brush.color)
        lineWidth = brush.lineWidth
        stabilizerRadius = brush.stabilizerRadius
        blendMode = StrokeBlendMode(blendMode: brush.blendMode)
    }

    var model: BrushConfig {
        BrushConfig(
            color: color.uiColor,
            lineWidth: lineWidth,
            stabilizerRadius: stabilizerRadius,
            blendMode: blendMode?.cgBlendMode ?? .normal
        )
    }
}

struct DrawingControlConfigDTO: Codable {
    var movementScale: CGFloat
    var smoothingAmount: CGFloat
    var showsStabilizerGuide: Bool?
    var requiresLongPress: Bool?

    init(control: DrawingControlConfig) {
        movementScale = control.movementScale
        smoothingAmount = control.smoothingAmount
        showsStabilizerGuide = control.showsStabilizerGuide
        requiresLongPress = control.requiresLongPress
    }

    var model: DrawingControlConfig {
        DrawingControlConfig(
            movementScale: movementScale,
            smoothingAmount: smoothingAmount,
            showsStabilizerGuide: showsStabilizerGuide ?? true,
            requiresLongPress: requiresLongPress ?? true
        )
    }
}

enum StrokeBlendMode: String, Codable {
    case normal
    case clear

    init(blendMode: CGBlendMode) {
        switch blendMode {
        case .clear:
            self = .clear
        default:
            self = .normal
        }
    }

    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:
            return .normal
        case .clear:
            return .clear
        }
    }
}

struct StrokeDTO: Codable {
    var points: [StrokePointDTO]
    var brush: BrushConfigDTO
    var layerID: UUID?

    init(stroke: Stroke) {
        points = stroke.points.map(StrokePointDTO.init(point:))
        brush = BrushConfigDTO(brush: stroke.brush)
        layerID = stroke.layerID
    }

    func model(defaultLayerID: UUID) -> Stroke {
        Stroke(points: points.map(\.model), brush: brush.model, layerID: layerID ?? defaultLayerID)
    }
}

struct DrawingLayer: Identifiable, Equatable {
    var id: UUID
    var title: String
    var isVisible: Bool
    var opacity: CGFloat
}

struct DrawingLayerDTO: Codable {
    var id: UUID
    var title: String
    var isVisible: Bool
    var opacity: CGFloat?

    init(layer: DrawingLayer) {
        id = layer.id
        title = layer.title
        isVisible = layer.isVisible
        opacity = layer.opacity
    }

    var model: DrawingLayer {
        DrawingLayer(id: id, title: title, isVisible: isVisible, opacity: opacity ?? 1)
    }
}

struct DrawingDocument: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var boardColor: CodableColor
    var brush: BrushConfigDTO
    var control: DrawingControlConfigDTO
    var strokes: [StrokeDTO]
    var canvas: CanvasConfigDTO?
    var layers: [DrawingLayerDTO]?
    var activeLayerID: UUID?

    static func new(title: String) -> DrawingDocument {
        let now = Date()
        let baseLayer = DrawingLayer(id: UUID(), title: "Layer 1", isVisible: true, opacity: 1)
        return DrawingDocument(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            boardColor: CodableColor(.white),
            brush: BrushConfigDTO(brush: .initial),
            control: DrawingControlConfigDTO(control: .initial),
            strokes: [],
            canvas: CanvasConfigDTO.initial,
            layers: [DrawingLayerDTO(layer: baseLayer)],
            activeLayerID: baseLayer.id
        )
    }

    var resolvedLayers: [DrawingLayer] {
        if let layers, !layers.isEmpty {
            return layers.map(\.model)
        }

        let fallbackID = activeLayerID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        return [DrawingLayer(id: fallbackID, title: "Layer 1", isVisible: true, opacity: 1)]
    }

    var resolvedActiveLayerID: UUID {
        let layers = resolvedLayers
        if let activeLayerID, layers.contains(where: { $0.id == activeLayerID }) {
            return activeLayerID
        }
        return layers[0].id
    }

    var resolvedStrokes: [Stroke] {
        strokes.map { $0.model(defaultLayerID: resolvedActiveLayerID) }
    }
}

struct DrawingDocumentSummary {
    let id: UUID
    let title: String
    let updatedAt: Date
    let thumbnailURL: URL
}

struct CanvasConfigDTO: Codable {
    var width: CGFloat
    var height: CGFloat
    var isTransparentExportEnabled: Bool
    var calibrationNotes: String?
    var calibration: CalibrationCheckDTO?

    static let initial = CanvasConfigDTO(
        width: 1080,
        height: 1440,
        isTransparentExportEnabled: false,
        calibrationNotes: nil,
        calibration: CalibrationCheckDTO.initial
    )
}

struct CalibrationCheckDTO: Codable {
    var longPressFeelsSlow: Bool
    var stabilizerFeelsHeavy: Bool
    var movementFeelsWrong: Bool
    var smoothingFeelsLaggy: Bool
    var guideFeelsDistracting: Bool
    var cursorFeelsUnclear: Bool

    static let initial = CalibrationCheckDTO(
        longPressFeelsSlow: false,
        stabilizerFeelsHeavy: false,
        movementFeelsWrong: false,
        smoothingFeelsLaggy: false,
        guideFeelsDistracting: false,
        cursorFeelsUnclear: false
    )
}
