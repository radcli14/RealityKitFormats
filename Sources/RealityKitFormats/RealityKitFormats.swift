//
//  RealityKitFormats.swift
//  RealityKitFormats
//

import Foundation
import RealityKit
import ModelIO_to_RealityKit
import DAE_to_RealityKit

/// Load a 3D model from a local file URL, dispatching to the appropriate loader by file extension.
///
/// Supported formats:
/// - **STL, OBJ, PLY, ABC** — loaded via ModelIO (radcli14/ModelIO-to-RealityKit)
/// - **DAE** (Collada) — loaded via a custom COLLADA parser (radcli14/DAE-to-RealityKit)
/// - **GLB, GLTF** — loaded via GLTFKit2 (warrenm/GLTFKit2)
///
/// Usage:
/// ```swift
/// let entity = await loadEntity(from: url)
/// ```
///
/// - Parameter url: A local file URL for the 3D model.
/// - Returns: An `Entity` on success, or `nil` if the format is unsupported or loading failed.
@MainActor
public func loadEntity(from url: URL) async -> Entity? {
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
