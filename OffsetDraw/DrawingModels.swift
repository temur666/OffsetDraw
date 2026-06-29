import UIKit

struct StrokePoint {
    let position: CGPoint
    let timestamp: TimeInterval
}

struct BrushConfig {
    var color: UIColor
    var lineWidth: CGFloat
    var stabilizerRadius: CGFloat

    static let initial = BrushConfig(color: .black, lineWidth: 6, stabilizerRadius: 40)
}

struct DrawingControlConfig {
    var movementScale: CGFloat
    var smoothingAmount: CGFloat

    static let initial = DrawingControlConfig(movementScale: 0.25, smoothingAmount: 0.5)
}

struct Stroke {
    let points: [StrokePoint]
    let brush: BrushConfig
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

    init(brush: BrushConfig) {
        color = CodableColor(brush.color)
        lineWidth = brush.lineWidth
        stabilizerRadius = brush.stabilizerRadius
    }

    var model: BrushConfig {
        BrushConfig(color: color.uiColor, lineWidth: lineWidth, stabilizerRadius: stabilizerRadius)
    }
}

struct DrawingControlConfigDTO: Codable {
    var movementScale: CGFloat
    var smoothingAmount: CGFloat

    init(control: DrawingControlConfig) {
        movementScale = control.movementScale
        smoothingAmount = control.smoothingAmount
    }

    var model: DrawingControlConfig {
        DrawingControlConfig(movementScale: movementScale, smoothingAmount: smoothingAmount)
    }
}

struct StrokeDTO: Codable {
    var points: [StrokePointDTO]
    var brush: BrushConfigDTO

    init(stroke: Stroke) {
        points = stroke.points.map(StrokePointDTO.init(point:))
        brush = BrushConfigDTO(brush: stroke.brush)
    }

    var model: Stroke {
        Stroke(points: points.map(\.model), brush: brush.model)
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

    static func new(title: String) -> DrawingDocument {
        let now = Date()
        return DrawingDocument(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            boardColor: CodableColor(.white),
            brush: BrushConfigDTO(brush: .initial),
            control: DrawingControlConfigDTO(control: .initial),
            strokes: []
        )
    }
}

struct DrawingDocumentSummary {
    let id: UUID
    let title: String
    let updatedAt: Date
}
