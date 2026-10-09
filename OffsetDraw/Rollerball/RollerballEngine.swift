import Foundation

/// Logical points correspond to CSS pixels in the reference HTML, independent of display scale.
struct RollerballSettings: Codable, Equatable {
    var size: Double = 8
    var pressure: Double = 0.45
    var speed: Double = 240
    var power: Double = 2.6
    var response: Double = 25
    var pool: Double = 0.65
    var color: String = "#203656"

    var isValid: Bool {
        let values = [(size, 1.0...64.0), (pressure, 0.1...1.0), (speed, 60.0...1000.0),
                      (power, 1.0...4.0), (response, 5.0...100.0), (pool, 0.0...1.5)]
        return values.allSatisfy { $0.0.isFinite && $0.1.contains($0.0) }
            && color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }

    func radius(velocity: Double, pressure: Double) -> Double {
        let base = size * 0.5 * min(1, max(0, pressure))
        let scale = 0.3 + 0.7 / (1 + pow(max(0, velocity) / speed, power))
        return max(0.001, base * scale)
    }
}

enum RollerballBrushStyle: Int {
    case rollerball = 0
    case thickEnds

    var title: String {
        switch self {
        case .rollerball: "走珠笔"
        case .thickEnds: "两头粗"
        }
    }
}

struct RollerballPoint {
    var x: Double
    var y: Double
    var time: Double // seconds, UITouch.timestamp / CACurrentMediaTime clock
    var radius: Double
}

struct RollerballStroke {
    let settings: RollerballSettings
    var points: [RollerballPoint]
    var pool: RollerballPoint?
}

/// Faithful port of radiusAt / move / tick / finish from rollerball-brush.html.
final class RollerballEngine {
    private(set) var stroke: RollerballStroke?
    private(set) var velocity: Double = 0
    private(set) var pressure: Double = 0.45
    private(set) var radius: Double = 1.9
    private var previous: RollerballPoint?
    private var inputX: Double = 0
    private var inputY: Double = 0
    private var lastMotion: Double = 0
    private var visualTime: Double = 0
    private var usesPressure = false
    private var brushStyle: RollerballBrushStyle = .rollerball
    private var strokeDistance: Double = 0

    func begin(x: Double, y: Double, time: Double, pressure: Double?, settings: RollerballSettings,
               brushStyle: RollerballBrushStyle = .rollerball) {
        usesPressure = pressure != nil
        self.brushStyle = brushStyle
        strokeDistance = 0
        self.pressure = min(1, max(0, pressure ?? settings.pressure))
        radius = settings.radius(velocity: 0, pressure: self.pressure)
        velocity = 0
        let point = RollerballPoint(x: x, y: y, time: time, radius: radius)
        stroke = RollerballStroke(settings: settings, points: [point])
        previous = point
        inputX = x
        inputY = y
        lastMotion = time
        visualTime = time
    }

    func move(x: Double, y: Double, time: Double, pressure: Double?) {
        guard let previous, let settings = stroke?.settings, time >= previous.time else { return }
        let inputDistance = hypot(x - inputX, y - inputY)
        let oldPressure = self.pressure
        if usesPressure, let pressure { self.pressure = min(1, max(0, pressure)) }
        guard inputDistance >= 0.025 || self.pressure != oldPressure else { return }
        let dt = min(250, max(0.5, (time - previous.time) * 1000))
        if inputDistance >= 0.025 {
            let speed = inputDistance / dt * 1000
            velocity += (speed - velocity) * (1 - exp(-dt / 14))
            lastMotion = time
        }
        // Smooth only the rendered centerline. Faster strokes use a shorter filter
        // so the nib remains close to the Pencil while slow strokes lose hand jitter.
        let positionResponse = 5 + 9 / (1 + velocity / 600)
        let positionMix = 1 - exp(-dt / positionResponse)
        let smoothX = previous.x + (x - previous.x) * positionMix
        let smoothY = previous.y + (y - previous.y) * positionMix
        inputX = x
        inputY = y
        let target = settings.radius(velocity: velocity, pressure: self.pressure)
        radius += (target - radius) * (1 - exp(-dt / settings.response))
        strokeDistance += hypot(smoothX - previous.x, smoothY - previous.y)
        let shapedRadius = radius * startEnvelope(at: strokeDistance)
        let point = RollerballPoint(x: smoothX, y: smoothY, time: time, radius: shapedRadius)
        stroke?.points.append(point)
        self.previous = point
        visualTime = time
    }

    func tick(time: Double) {
        guard let settings = stroke?.settings, let last = stroke?.points.last,
              time - lastMotion > 0.045 else { return }
        let dt = min(50, max(0, (time - visualTime) * 1000))
        velocity *= exp(-dt / 65)
        radius += (settings.radius(velocity: velocity, pressure: pressure) - radius)
            * (1 - exp(-dt / settings.response))
        visualTime = time
        if abs(last.radius - radius) > 0.003 {
            stroke?.points.append(RollerballPoint(x: last.x, y: last.y, time: time,
                                                  radius: radius * startEnvelope(at: strokeDistance)))
        }
    }

    func finish(time: Double, withPool: Bool = true) -> RollerballStroke? {
        guard var result = stroke, let last = result.points.last else { return nil }
        let settings = result.settings

        // The rendered centerline intentionally trails the raw Pencil samples while drawing.
        // On lift, flush that small remainder to the last real input coordinate so short
        // strokes, hooks and flicks are not visually cut off.
        let endpointDistance = hypot(inputX - last.x, inputY - last.y)
        if endpointDistance > 0.001 {
            let finalDistance = strokeDistance + endpointDistance
            result.points.append(RollerballPoint(x: inputX, y: inputY, time: time,
                                                 radius: radius * startEnvelope(at: finalDistance)))
        }

        if brushStyle == .thickEnds, result.points.count > 1 {
            var distances = [Double](repeating: 0, count: result.points.count)
            for index in 1..<result.points.count {
                let previous = result.points[index - 1]
                let point = result.points[index]
                distances[index] = distances[index - 1] + hypot(point.x - previous.x, point.y - previous.y)
            }
            let total = distances.last ?? 0
            for index in result.points.indices {
                let start = distances[index]
                let end = max(0, total - start)
                let originalEnvelope = startEnvelope(at: start)
                let endEnvelope = waistDepth + (1 - waistDepth) * max(exp(-start / capLength), exp(-end / capLength))
                result.points[index].radius = result.points[index].radius / originalEnvelope * endEnvelope
            }
        }
        if withPool && settings.pool > 0, let end = result.points.last {
            let idle = min(1, max(0, (time - lastMotion) / 0.6))
            let slow = 1 / (1 + velocity / settings.speed)
            let deposit = settings.size * 0.5 * pressure * settings.pool * (0.35 + 0.65 * slow + 0.35 * idle)
            result.pool = RollerballPoint(x: end.x, y: end.y, time: time,
                                         radius: sqrt(end.radius * end.radius + deposit * deposit))
        }
        stroke = nil
        previous = nil
        strokeDistance = 0
        return result
    }

    private let waistDepth = 0.78
    private let capLength = 14.0

    private func startEnvelope(at distance: Double) -> Double {
        guard brushStyle == .thickEnds else { return 1 }
        return waistDepth + (1 - waistDepth) * exp(-distance / capLength)
    }
}
