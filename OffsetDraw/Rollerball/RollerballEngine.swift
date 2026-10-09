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

enum RollerballCorrectionMode: Int {
    case raw = 0
    case write

    var title: String {
        switch self {
        case .raw: "RAW"
        case .write: "WRITE"
        }
    }
}

struct RollerballPoint {
    var x: Double
    var y: Double
    var time: Double // seconds, UITouch.timestamp / CACurrentMediaTime clock
    var radius: Double
}

struct RollerballInputSample {
    var x: Double
    var y: Double
    var time: Double
    var pressure: Double?
}

struct RollerballStroke {
    let settings: RollerballSettings
    var points: [RollerballPoint]
    var pool: RollerballPoint?
}

/// Low-latency write engine: real Pencil samples are committed directly. Prediction is preview-only.
final class RollerballEngine {
    private(set) var stroke: RollerballStroke?
    private(set) var velocity: Double = 0
    private(set) var pressure: Double = 0.45
    private(set) var radius: Double = 1.9
    private var previous: RollerballPoint?
    private var inputX: Double = 0
    private var inputY: Double = 0
    private var inputTime: Double = 0
    private var lastMotion: Double = 0
    private var visualTime: Double = 0
    private var usesPressure = false
    private var brushStyle: RollerballBrushStyle = .rollerball
    private var correctionMode: RollerballCorrectionMode = .write
    private var strokeDistance: Double = 0

    func begin(x: Double, y: Double, time: Double, pressure: Double?, settings: RollerballSettings,
               brushStyle: RollerballBrushStyle = .rollerball,
               correctionMode: RollerballCorrectionMode = .write) {
        usesPressure = pressure != nil
        self.brushStyle = brushStyle
        self.correctionMode = correctionMode
        strokeDistance = 0
        self.pressure = min(1, max(0, pressure ?? settings.pressure))
        radius = settings.radius(velocity: 0, pressure: self.pressure)
        velocity = 0
        let point = RollerballPoint(x: x, y: y, time: time, radius: radius)
        stroke = RollerballStroke(settings: settings, points: [point])
        previous = point
        inputX = x
        inputY = y
        inputTime = time
        lastMotion = time
        visualTime = time
    }

    func move(x: Double, y: Double, time: Double, pressure: Double?) {
        guard previous != nil, let settings = stroke?.settings, time >= inputTime else { return }
        let inputDistance = hypot(x - inputX, y - inputY)
        let oldPressure = self.pressure
        if usesPressure, let pressure { self.pressure = min(1, max(0, pressure)) }
        guard inputDistance >= 0.025 || self.pressure != oldPressure else { return }
        let dt = min(250, max(0.5, (time - inputTime) * 1000))
        if inputDistance >= 0.025 {
            let speed = inputDistance / dt * 1000
            velocity += (speed - velocity) * (1 - exp(-dt / 14))
            lastMotion = time
        }

        // Position stays on the real Pencil sample. Only brush physics (velocity/pressure/radius)
        // is smoothed, so the stroke no longer trails behind the nib.
        let target = settings.radius(velocity: velocity, pressure: self.pressure)
        radius += (target - radius) * (1 - exp(-dt / settings.response))
        strokeDistance += inputDistance
        let point = RollerballPoint(x: x, y: y, time: time,
                                    radius: radius * startEnvelope(at: strokeDistance))
        stroke?.points.append(point)
        previous = point
        inputX = x
        inputY = y
        inputTime = time
        visualTime = time
    }

    /// Produces a temporary continuation using the same pressure × speed brush physics without
    /// mutating the committed stroke. Callers must discard these points when real samples arrive.
    func predictedPoints(for samples: [RollerballInputSample]) -> [RollerballPoint] {
        guard let settings = stroke?.settings, !samples.isEmpty else { return [] }

        var previewX = inputX
        var previewY = inputY
        var previewTime = inputTime
        var previewVelocity = velocity
        var previewPressure = pressure
        var previewRadius = radius
        var previewDistance = strokeDistance
        var result: [RollerballPoint] = []
        result.reserveCapacity(samples.count)

        for sample in samples {
            guard sample.time >= previewTime else { continue }
            let distance = hypot(sample.x - previewX, sample.y - previewY)
            let oldPressure = previewPressure
            if usesPressure, let pressure = sample.pressure {
                previewPressure = min(1, max(0, pressure))
            }
            guard distance >= 0.025 || previewPressure != oldPressure else { continue }

            let dt = min(250, max(0.5, (sample.time - previewTime) * 1000))
            if distance >= 0.025 {
                let speed = distance / dt * 1000
                previewVelocity += (speed - previewVelocity) * (1 - exp(-dt / 14))
            }
            let target = settings.radius(velocity: previewVelocity, pressure: previewPressure)
            previewRadius += (target - previewRadius) * (1 - exp(-dt / settings.response))
            previewDistance += distance
            result.append(RollerballPoint(x: sample.x, y: sample.y, time: sample.time,
                                          radius: previewRadius * startEnvelope(at: previewDistance)))
            previewX = sample.x
            previewY = sample.y
            previewTime = sample.time
        }
        return result
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

        // Normally direct-position rendering already reaches the final Pencil sample. Keep this
        // as a safety flush for a final touch location that was not present in the coalesced batch.
        let endpointDistance = hypot(inputX - last.x, inputY - last.y)
        if endpointDistance > 0.001 {
            let finalDistance = strokeDistance + endpointDistance
            result.points.append(RollerballPoint(x: inputX, y: inputY, time: time,
                                                 radius: radius * startEnvelope(at: finalDistance)))
        }

        if correctionMode == .write {
            result.points = correctedEndpoints(result.points)
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

    /// WRITE correction deliberately touches only tiny endpoint regions. It does not smooth the
    /// full centerline, so Pencil latency and intentional curves remain unchanged.
    private func correctedEndpoints(_ points: [RollerballPoint]) -> [RollerballPoint] {
        guard points.count >= 4 else { return points }
        var result = points
        correctStart(in: &result)
        correctEnd(in: &result)
        return result
    }

    /// If the first ~1 pt points in a very different direction from the established ~5 pt
    /// direction, treat that as glass-slip and gently pull only the first 2.5 pt toward the guide.
    private func correctStart(in points: inout [RollerballPoint]) {
        let distances = cumulativeDistances(points)
        guard let earlyIndex = firstIndex(atLeast: 1.0, in: distances),
              let guideIndex = firstIndex(atLeast: 5.0, in: distances),
              guideIndex > earlyIndex else { return }

        let origin = points[0]
        let earlyDX = points[earlyIndex].x - origin.x
        let earlyDY = points[earlyIndex].y - origin.y
        let guideDX = points[guideIndex].x - origin.x
        let guideDY = points[guideIndex].y - origin.y
        let guideLength = hypot(guideDX, guideDY)
        guard guideLength > 0.001,
              angleBetween(ax: earlyDX, ay: earlyDY, bx: guideDX, by: guideDY) > .pi * 35 / 180 else { return }

        let ux = guideDX / guideLength
        let uy = guideDY / guideLength
        let correctionLength = 2.5
        for index in 1..<guideIndex where distances[index] < correctionLength {
            let point = points[index]
            let px = point.x - origin.x
            let py = point.y - origin.y
            let along = px * ux + py * uy
            let projectedX = origin.x + ux * along
            let projectedY = origin.y + uy * along
            let progress = min(1, max(0, distances[index] / correctionLength))
            let strength = 0.8 * pow(1 - progress, 1.5)
            points[index].x += (projectedX - point.x) * strength
            points[index].y += (projectedY - point.y) * strength
        }
    }

    /// Only removes a tiny final back-track: <= ~1.6 pt and >110° against the preceding motion.
    /// Sideways hooks and normal turnarounds are intentionally left alone.
    private func correctEnd(in points: inout [RollerballPoint]) {
        guard points.count >= 4 else { return }
        let fromEnd = reverseDistances(points)
        guard let tailIndex = lastIndex(atLeastFromEnd: 0.9, in: fromEnd),
              let anchorIndex = lastIndex(atLeastFromEnd: 4.0, in: fromEnd),
              anchorIndex < tailIndex,
              let end = points.last else { return }

        let tailLength = hypot(end.x - points[tailIndex].x, end.y - points[tailIndex].y)
        guard tailLength <= 1.6 else { return }

        let mainDX = points[tailIndex].x - points[anchorIndex].x
        let mainDY = points[tailIndex].y - points[anchorIndex].y
        let tailDX = end.x - points[tailIndex].x
        let tailDY = end.y - points[tailIndex].y
        guard angleBetween(ax: mainDX, ay: mainDY, bx: tailDX, by: tailDY) > .pi * 110 / 180 else { return }

        var terminal = points[tailIndex]
        terminal.time = end.time
        terminal.radius = end.radius
        points.removeSubrange((tailIndex + 1)..<points.count)
        points[tailIndex] = terminal
    }

    private func cumulativeDistances(_ points: [RollerballPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            result[index] = result[index - 1]
                + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return result
    }

    private func reverseDistances(_ points: [RollerballPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: points.count)
        if points.count > 1 {
            for index in stride(from: points.count - 2, through: 0, by: -1) {
                result[index] = result[index + 1]
                    + hypot(points[index + 1].x - points[index].x, points[index + 1].y - points[index].y)
            }
        }
        return result
    }

    private func firstIndex(atLeast distance: Double, in distances: [Double]) -> Int? {
        distances.firstIndex { $0 >= distance }
    }

    private func lastIndex(atLeastFromEnd distance: Double, in distances: [Double]) -> Int? {
        for index in stride(from: distances.count - 1, through: 0, by: -1) where distances[index] >= distance {
            return index
        }
        return nil
    }

    private func angleBetween(ax: Double, ay: Double, bx: Double, by: Double) -> Double {
        let aLength = hypot(ax, ay)
        let bLength = hypot(bx, by)
        guard aLength > 0.001, bLength > 0.001 else { return 0 }
        let cosine = min(1, max(-1, (ax * bx + ay * by) / (aLength * bLength)))
        return acos(cosine)
    }

    private let waistDepth = 0.78
    private let capLength = 14.0

    private func startEnvelope(at distance: Double) -> Double {
        guard brushStyle == .thickEnds else { return 1 }
        return waistDepth + (1 - waistDepth) * exp(-distance / capLength)
    }
}
