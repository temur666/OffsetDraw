import Foundation

@main
struct RollerballEngineTests {
    static func close(_ actual: Double, _ expected: Double, _ message: String) {
        precondition(abs(actual - expected) < 1e-9, "\(message): \(actual) != \(expected)")
    }
    static func main() {
        precondition(RollerballRemoteClient.endpoint(address: "192.168.0.101")?.absoluteString == "http://192.168.0.101:18765/api/settings")
        precondition(RollerballRemoteClient.endpoint(address: "http://192.168.0.105:9999/")?.port == 9999)
        for address in ["", "example.com", "999.1.1.1", "http://user:pass@192.168.0.101", "192.168.0.101/path", "192.168.0.101:70000"] {
            precondition(RollerballRemoteClient.endpoint(address: address) == nil, address)
        }
        let settings = RollerballSettings()
        precondition(settings.isValid)
        close(settings.radius(velocity: 0, pressure: 1), 4.0, "stationary")
        close(settings.radius(velocity: 240, pressure: 1), 4.0 * 0.65, "threshold 65%")
        close(settings.radius(velocity: 240, pressure: 0.5), 4.0 * 0.65 * 0.5, "pressure linear")
        close(settings.radius(velocity: 1e12, pressure: 1), 4.0 * 0.3, "30% floor")
        var invalid = settings
        invalid.size = .nan
        precondition(!invalid.isValid)
        invalid = settings; invalid.color = "red"
        precondition(!invalid.isValid)
        let engine = RollerballEngine()
        engine.begin(x: 0, y: 0, time: 1, pressure: nil, settings: settings)
        engine.move(x: 50, y: 0, time: 1.02, pressure: nil)
        precondition(engine.radius < 4.0)
        let fastRadius = engine.radius
        for i in 1...60 { engine.tick(time: 1.02 + Double(i) / 60) }
        precondition(engine.radius > fastRadius)
        close(engine.radius, 4.0, "stationary recovery")
        let stroke = engine.finish(time: 2.02)!
        precondition(stroke.pool!.radius > stroke.points.last!.radius)
        precondition(engine.stroke == nil)
        engine.begin(x: 0, y: 0, time: 3, pressure: 0.4, settings: settings)
        engine.move(x: 1, y: 0, time: 3.01, pressure: nil)
        close(engine.pressure, 0.4, "release retains pressure")
        precondition(engine.finish(time: 3.01, withPool: false)!.pool == nil)
        var noPool = settings; noPool.pool = 0
        engine.begin(x: 0, y: 0, time: 4, pressure: nil, settings: noPool)
        precondition(engine.finish(time: 4)!.pool == nil)
        // Run sample traces captured by executing the reference JavaScript, not a second Swift formula.
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let traces = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [[String: Any]]
        for trace in traces {
            let events = trace["events"] as! [[String: Any]]
            let first = events[0]
            engine.begin(x: first["x"] as! Double, y: first["y"] as! Double,
                         time: (first["t"] as! Double) / 1000, pressure: (first["pressure"] as? Double).map { pow(max(0.2, $0), 0.55) }, settings: settings)
            for event in events.dropFirst() {
                let time = (event["t"] as! Double) / 1000
                if event["kind"] as? String == "tick" { engine.tick(time: time) }
                else { engine.move(x: event["x"] as! Double, y: event["y"] as! Double,
                                   time: time, pressure: (event["pressure"] as? Double).map { pow(max(0.2, $0), 0.55) }) }
            }
            let result = engine.finish(time: (trace["endTime"] as! Double) / 1000)!
            let expected = trace["points"] as! [[String: Double]]
            precondition(result.points.count == expected.count)
            for (point, reference) in zip(result.points, expected) {
                close(point.x, reference["x"]!, "x")
                close(point.y, reference["y"]!, "y")
                close(point.radius, reference["r"]!, "reference radius")
            }
            close(result.pool!.radius, (trace["pool"] as! [String: Double])["r"]!, "reference pool")
        }
        print("Rollerball engine: defaults, pressure, speed, recovery, cancellation and \(traces.count) HTML traces passed")
    }
}
