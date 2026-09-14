import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum MemoryAMemoRenderer {
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

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
