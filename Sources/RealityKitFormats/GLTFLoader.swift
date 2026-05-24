//
//  GLTFLoader.swift
//  RealityKitFormats
//

import Foundation
import RealityKit
import GLTFKit2

public extension Entity {

    /// Load an Entity from a GLTF or GLB file at the specified URL.
    ///
    /// GLTF scenes may contain multiple meshes, lights, and cameras as a full
    /// scene hierarchy, so this returns `Entity` rather than `ModelEntity` to
    /// preserve the complete structure produced by GLTFKit2.
    ///
    /// ```swift
    /// let entity = await Entity.fromGLTFAsset(url: url)
    /// ```
    @MainActor
    static func fromGLTFAsset(url: URL) async -> Entity? {
        do {
            return try await GLTFRealityKitLoader.load(from: url)
        } catch {
            print("Entity.fromGLTFAsset(url:) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Load an Entity from GLTF or GLB data bytes.
    /// - Parameters:
    ///   - data: The raw file data
    ///   - format: File format extension, either `"glb"` (default) or `"gltf"`
    @MainActor
    static func fromGLTFAsset(data: Data, format: String = "glb") async -> Entity? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format)
        do {
            try data.write(to: tempURL)
            let entity = await Entity.fromGLTFAsset(url: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            return entity
        } catch {
            print("Entity.fromGLTFAsset(data:format:) failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }
}
