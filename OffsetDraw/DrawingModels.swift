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

struct Stroke {
    let points: [StrokePoint]
    let brush: BrushConfig
}
