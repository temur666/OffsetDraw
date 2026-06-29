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

enum DrawingInteractionMode {
    case longPress
    case buttonHold
    case doubleTapHold
}

struct Stroke {
    let points: [StrokePoint]
    let brush: BrushConfig
}
