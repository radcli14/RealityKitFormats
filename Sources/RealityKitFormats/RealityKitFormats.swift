//
//  RealityKitFormats.swift
//  RealityKitFormats
//

import Foundation
import RealityKit
import ModelIO_to_RealityKit
import DAE_to_RealityKit

/// Errors thrown by the RealityKitFormats unified loaders.
public enum RealityKitFormatsError: LocalizedError, Equatable {
    /// The file extension or format string is not supported.
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "RealityKitFormats: unsupported 3D file format '\(ext)'"
        }
    }
}

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
    /// let entity = try await Entity.from3DAsset(url: url)
    /// ```
    ///
    /// - Parameter url: A local file URL for the 3D model.
    /// - Returns: The loaded `Entity`.
    /// - Throws: `RealityKitFormatsError.unsupportedFormat` if the extension is not recognised,
    ///   or a loader-specific error if loading fails.
    @MainActor
    static func from3DAsset(url: URL) async throws -> Entity {
        switch url.pathExtension.lowercased() {
        case "stl", "obj", "ply", "abc":
            return try await ModelEntity.fromMDLAsset(url: url)
        case "dae":
            return try await ModelEntity.fromDAEAsset(url: url)
        case "gltf", "glb":
            return try await Entity.fromGLTFAsset(url: url)
        default:
            throw RealityKitFormatsError.unsupportedFormat(url.pathExtension)
        }
    }

    /// Load a 3D model from raw file data, dispatching to the appropriate loader by format extension.
    ///
    /// Useful when the file has been serialized as `Data` (e.g. stored in SwiftData) rather than
    /// written to disk. Supports the same formats as `from3DAsset(url:)`.
    ///
    /// Usage:
    /// ```swift
    /// let entity = try await Entity.from3DAsset(data: data, format: "glb")
    /// ```
    ///
    /// - Parameters:
    ///   - data: The raw file bytes.
    ///   - format: The file format extension (e.g. `"glb"`, `"stl"`, `"dae"`).
    /// - Returns: The loaded `Entity`.
    /// - Throws: `RealityKitFormatsError.unsupportedFormat` if the format is not recognised,
    ///   or a loader-specific error if loading fails.
    @MainActor
    static func from3DAsset(data: Data, format: String) async throws -> Entity {
        switch format.lowercased() {
        case "stl", "obj", "ply", "abc":
            return try await ModelEntity.fromMDLAsset(data: data, format: format)
        case "dae":
            return try await ModelEntity.fromDAEAsset(data: data)
        case "gltf", "glb":
            return try await Entity.fromGLTFAsset(data: data, format: format)
        default:
            throw RealityKitFormatsError.unsupportedFormat(format)
        }
    }
}
