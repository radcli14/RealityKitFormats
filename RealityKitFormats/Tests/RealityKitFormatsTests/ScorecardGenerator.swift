import Foundation
import RealityKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Owns a single off-screen ARView and renders entities into 256×256 PNG snapshots.
/// All methods are MainActor-isolated because ARView requires the main thread.
@MainActor
final class ScorecardGenerator {
    static let shared = ScorecardGenerator()

    private let arView: ARView
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

        // Fixed perspective camera
        let cameraEntity = Entity()
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = 30
        cameraEntity.components.set(camera)
        cameraEntity.look(at: .zero, from: [0, 0.5, 1.5], relativeTo: nil)
        let cameraAnchor = AnchorEntity()
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
    }

    /// Renders `entity` into a 256×256 PNG and returns the data.
    /// Returns `nil` if Metal rendering is unavailable in this environment.
    func render(entity: Entity) async -> Data? {
        entityAnchor?.removeFromParent()
        entityAnchor = nil

        // Center and normalize scale so every model fills the frame
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position = -bounds.center
        let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        if maxExtent > 0.001 {
            entity.scale = SIMD3(repeating: 0.5 / maxExtent)
        }

        let anchor = AnchorEntity()
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        entityAnchor = anchor

        // Allow the RealityKit render loop to tick and textures to stream in
        try? await Task.sleep(for: .milliseconds(1000))

        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                #if canImport(UIKit)
                continuation.resume(returning: image.pngData())
                #else
                let data = image.tiffRepresentation.flatMap {
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                }
                continuation.resume(returning: data)
                #endif
            }
        }
    }
}
