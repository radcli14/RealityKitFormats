import Foundation
import RealityKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Owns a single off-screen ARView and renders entities into 256×256 PNG snapshots.
/// Camera framing matches RealityKitFormatsViewer: entity centered at origin, camera
/// placed at bounds.extents looking toward zero — no entity rescaling.
@MainActor
final class ScorecardGenerator {
    static let shared = ScorecardGenerator()

    private let arView: ARView
    private let camera: PerspectiveCamera
    private let cameraAnchor: AnchorEntity
    private var entityAnchor: AnchorEntity?

    private init() {
        arView = ARView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        arView.environment.background = .color(.white)
        #if os(iOS)
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField,
                                .disableHDR, .disableGroundingShadows]
        arView.cameraMode = .nonAR
        #endif

        // Fixed directional light
        let lightEntity = Entity()
        var light = DirectionalLightComponent()
        light.intensity = 1000
        lightEntity.components.set(light)
        lightEntity.look(at: .zero, from: [1, 2, 1], relativeTo: nil)
        let lightAnchor = AnchorEntity()
        lightAnchor.addChild(lightEntity)
        arView.scene.addAnchor(lightAnchor)

        // Camera — transform is updated per-entity in render()
        camera = PerspectiveCamera()
        cameraAnchor = AnchorEntity()
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
    }

    /// Renders `entity` into a 256×256 PNG and returns the data.
    /// Returns `nil` if Metal rendering is unavailable in this environment.
    func render(entity: Entity) async -> Data? {
        entityAnchor?.removeFromParent()
        entityAnchor = nil

        // Remove any camera entities baked into the asset so our camera controls the view
        entity.sanitizeCameraComponents()

        // Center entity and position camera from bounds extents — mirrors viewer logic
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position = -bounds.center
        let extents = bounds.extents
        let cameraFrom: SIMD3<Float> = (extents.x < 0.001 && extents.y < 0.001 && extents.z < 0.001)
            ? [0.5, 0.5, 0.5]
            : extents
        camera.look(at: .zero, from: cameraFrom, relativeTo: nil)

        let anchor = AnchorEntity()
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        entityAnchor = anchor

        // Allow the RealityKit render loop to tick and textures to stream in
        try? await Task.sleep(for: .milliseconds(2000))

        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                #if canImport(UIKit)
                // Force 1:1 pixel scale so output is exactly 256×256 on Retina devices
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                let renderer = UIGraphicsImageRenderer(
                    size: CGSize(width: 256, height: 256), format: format)
                let scaled = renderer.image { _ in
                    image.draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
                }
                continuation.resume(returning: scaled.pngData())
                #else
                // Scale to exactly 256×256 pixels (Retina displays render at 2× by default)
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: 256, pixelsHigh: 256,
                    bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false,
                    colorSpaceName: .calibratedRGB,
                    bytesPerRow: 0, bitsPerPixel: 0) else {
                    continuation.resume(returning: nil)
                    return
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
                NSGraphicsContext.restoreGraphicsState()
                continuation.resume(returning: rep.representation(using: .png, properties: [:]))
                #endif
            }
        }
    }
}

private extension Entity {
    func sanitizeCameraComponents() {
        components.remove(PerspectiveCameraComponent.self)
        for child in children { child.sanitizeCameraComponents() }
    }
}
