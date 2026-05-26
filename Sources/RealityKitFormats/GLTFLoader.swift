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
    /// let entity = try await Entity.fromGLTFAsset(url: url)
    /// ```
    ///
    /// - Throws: Any error thrown by `GLTFRealityKitLoader`.
    @MainActor
    static func fromGLTFAsset(url: URL) async throws -> Entity {
        try await GLTFRealityKitLoader.load(from: url)
    }

    /// Load an Entity from GLTF or GLB data bytes.
    ///
    /// Writes the data to a temporary file, loads it, then cleans up.
    ///
    /// - Parameters:
    ///   - data: The raw file data
    ///   - format: File format extension, either `"glb"` (default) or `"gltf"`
    /// - Throws: Any file I/O error or error thrown by `GLTFRealityKitLoader`.
    @MainActor
    static func fromGLTFAsset(data: Data, format: String = "glb") async throws -> Entity {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await fromGLTFAsset(url: tempURL)
    }
}
