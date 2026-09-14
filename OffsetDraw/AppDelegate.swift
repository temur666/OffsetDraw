import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

private enum MemoryAMemoRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(
        source: UIImage,
        canvasBounds: CGRect,
        points: [CGPoint]
    ) -> UIImage? {
        guard points.count > 2,
              canvasBounds.width > 0,
              canvasBounds.height > 0,
              let sourceCI = CIImage(image: source) else {
            return nil
        }

        let extent = sourceCI.extent
        let coreMaskImage = makeMask(
            bounds: canvasBounds,
            points: points,
            alpha: 1
        )
        let wideMaskImage = makeMask(
            bounds: canvasBounds,
            points: points,
            alpha: 0.36
        )

        guard let coreMaskCI = CIImage(image: coreMaskImage),
              let wideMaskCI = CIImage(image: wideMaskImage),
              let innerMask = blurred(coreMaskCI, radius: 12, extent: extent),
              let wideMask = blurred(wideMaskCI, radius: 54, extent: extent),
              let blurredSource = blurred(sourceCI, radius: 10, extent: extent) else {
            return nil
        }

        let clear = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: extent)

        let controls = CIFilter.colorControls()
        controls.inputImage = blurredSource
        controls.saturation = 0.40
        controls.contrast = 0.85
        controls.brightness = 0.04

        guard let fadedSource = controls.outputImage?.cropped(to: extent),
              let contextLayer = blend(
                source: fadedSource,
                background: clear,
                mask: wideMask
              ),
              let halo = warmHalo(
                mask: wideMask,
                clear: clear,
                extent: extent,
                alpha: 0.15
              ) else {
            return nil
        }

        let expandedBase = contextLayer
            .composited(over: halo)
            .cropped(to: extent)

        guard let final = blend(
            source: sourceCI,
            background: expandedBase,
            mask: innerMask
        )?.cropped(to: extent),
              let fullCG = context.createCGImage(final, from: extent) else {
            return nil
        }

        let full = UIImage(cgImage: fullCG)
        let crop = regionBounds(points)
            .insetBy(dx: -96, dy: -96)
            .intersection(canvasBounds)
            .integral

        guard crop.width > 1,
              crop.height > 1,
              let cropped = full.cgImage?.cropping(to: crop) else {
            return full
        }

        return UIImage(cgImage: cropped)
    }

    private static func makeMask(
        bounds: CGRect,
        points: [CGPoint],
        alpha: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            UIColor.white.withAlphaComponent(alpha).setFill()
            closedPath(points).fill()
        }
    }

    private static func closedPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 2 else {
            if let last = points.last {
                path.addLine(to: last)
            }
            path.close()
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) * 0.5,
                y: (previous.y + current.y) * 0.5
            )
            path.addQuadCurve(to: midpoint, controlPoint: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        path.close()
        return path
    }

    private static func regionBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func blurred(
        _ image: CIImage,
        radius: Float,
        extent: CGRect
    ) -> CIImage? {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image
        filter.radius = radius
        return filter.outputImage?.cropped(to: extent)
    }

    private static func blend(
        source: CIImage,
        background: CIImage,
        mask: CIImage
    ) -> CIImage? {
        let filter = CIFilter.blendWithAlphaMask()
        filter.inputImage = source
        filter.backgroundImage = background
        filter.maskImage = mask
        return filter.outputImage
    }

    private static func warmHalo(
        mask: CIImage,
        clear: CIImage,
        extent: CGRect,
        alpha: CGFloat
    ) -> CIImage? {
        let yellow = CIImage(
            color: CIColor(color: UIColor.systemYellow.withAlphaComponent(alpha))
        ).cropped(to: extent)

        return blend(
            source: yellow,
            background: clear,
            mask: mask
        )?.cropped(to: extent)
    }
}

private final class MemoryAMemoPreviewCoordinator: NSObject {
    static let shared = MemoryAMemoPreviewCoordinator()

    private weak var rootViewController: UIViewController?
    private var displayLink: CADisplayLink?
    private var lastRegionSignature: String?

    func installWhenReady(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }

            if self.installIfPossible() {
                return
            }

            if attempt < 20 {
                self.installWhenReady(attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    private func installIfPossible() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController,
              root.viewIfLoaded?.window != nil else {
            return false
        }

        rootViewController = root

        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(refreshMemoPreview))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        return true
    }

    @objc private func refreshMemoPreview() {
        guard let rootViewController else { return }

        guard let points = mirroredValue(
            named: "latestRegion",
            from: rootViewController
        ) as? [CGPoint],
              points.count > 2 else {
            lastRegionSignature = nil
            return
        }

        let signature = regionSignature(points)
        guard signature != lastRegionSignature else { return }

        guard let paperImageView = mirroredValue(
            named: "paperImageView",
            from: rootViewController
        ) as? UIImageView,
              let memoPreview = mirroredValue(
                named: "memoPreview",
                from: rootViewController
              ) as? UIImageView,
              paperImageView.bounds.width > 0,
              paperImageView.bounds.height > 0 else {
            return
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let source = UIGraphicsImageRenderer(
            bounds: paperImageView.bounds,
            format: format
        ).image { renderer in
            UIColor.clear.setFill()
            renderer.fill(paperImageView.bounds)
            paperImageView.layer.render(in: renderer.cgContext)
        }

        guard let rendered = MemoryAMemoRenderer.render(
            source: source,
            canvasBounds: paperImageView.bounds,
            points: points
        ) else {
            return
        }

        memoPreview.image = rendered
        lastRegionSignature = signature
    }

    private func regionSignature(_ points: [CGPoint]) -> String {
        guard let first = points.first,
              let last = points.last else {
            return "empty"
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return [
            String(points.count),
            String(format: "%.2f", first.x),
            String(format: "%.2f", first.y),
            String(format: "%.2f", last.x),
            String(format: "%.2f", last.y),
            String(format: "%.2f", minX),
            String(format: "%.2f", minY),
            String(format: "%.2f", maxX),
            String(format: "%.2f", maxY)
        ].joined(separator: "|")
    }

    private func mirroredValue(named name: String, from object: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: object)

        while let current = mirror {
            for child in current.children where child.label == name {
                return unwrapOptional(child.value)
            }
            mirror = current.superclassMirror
        }

        return nil
    }

    private func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        MemoryAMemoPreviewCoordinator.shared.installWhenReady()

        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        MemoryAMemoPreviewCoordinator.shared.installWhenReady()
    }
}
