//
//  RealityKitFormats.swift
//  RealityKitFormats
//

import Foundation
import RealityKit
import ModelIO_to_RealityKit
import DAE_to_RealityKit

public extension Entity {
    /// Load a 3D model from a local file URL, dispatching to the appropriate loader by file extension.
    ///
    /// Supported formats:
    /// - **STL, OBJ, PLY, ABC** — loaded via ModelIO (radcli14/ModelIO-to-RealityKit)
    /// - **DAE** (Collada) — loaded via a custom COLLADA parser (radcli14/DAE-to-RealityKit)
    /// - **GLB, GLTF** — loaded via GLTFKit2 (warrenm/GLTFKit2)
    ///
    /// Usage:
    /// ```swift
    /// let entity = await Entity.from3DAsset(url: url)
    /// ```
    ///
    /// - Parameter url: A local file URL for the 3D model.
    /// - Returns: An `Entity` on success, or `nil` if the format is unsupported or loading failed.
    /// Load a 3D model from raw file data, dispatching to the appropriate loader by format extension.
    ///
    /// Useful when the file has been serialized as `Data` (e.g. stored in SwiftData) rather than
    /// written to disk. Supports the same formats as `from3DAsset(url:)`.
    ///
    /// Usage:
    /// ```swift
    /// let entity = await Entity.from3DAsset(data: data, format: "glb")
    /// ```
    ///
    /// - Parameters:
    ///   - data: The raw file bytes.
    ///   - format: The file format extension (e.g. `"glb"`, `"stl"`, `"dae"`).
    /// - Returns: An `Entity` on success, or `nil` if the format is unsupported or loading failed.
    @MainActor
    static func from3DAsset(data: Data, format: String) async -> Entity? {
        switch format.lowercased() {
        case "stl", "obj", "ply", "abc":
            return await ModelEntity.fromMDLAsset(data: data, format: format)
        case "dae":
            return await ModelEntity.fromDAEAsset(data: data)
        case "gltf", "glb":
            return await Entity.fromGLTFAsset(data: data, format: format)
        default:
            print("RealityKitFormats: unsupported file extension '\(format)'")
            return nil
        }
    }

    @MainActor
    static func from3DAsset(url: URL) async -> Entity? {
        switch url.pathExtension.lowercased() {
        case "stl", "obj", "ply", "abc":
            return await ModelEntity.fromMDLAsset(url: url)
        case "dae":
            return await ModelEntity.fromDAEAsset(url: url)
        case "gltf", "glb":
            return await Entity.fromGLTFAsset(url: url)
        default:
            print("RealityKitFormats: unsupported file extension '\(url.pathExtension)'")
            return nil
        }
    }
}
