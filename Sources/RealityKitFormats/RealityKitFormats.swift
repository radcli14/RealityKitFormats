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
    /// - **USDZ, USD** — loaded via RealityKit's native loader
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
        case "usdz", "usd", "usdc", "usda":
            return try await Entity(contentsOf: url)
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
    ///   - format: The file format extension (e.g. `"usdz"`, `"glb"`, `"stl"`, `"dae"`).
    /// - Returns: The loaded `Entity`.
    /// - Throws: `RealityKitFormatsError.unsupportedFormat` if the format is not recognised,
    ///   or a loader-specific error if loading fails.
    /// - Note: USDZ/USD loading from `Data` uses `Entity(from:)` on iOS 26+ / macOS 26+.
    ///   On earlier OS versions it falls back to writing a temporary file.
    @MainActor
    static func from3DAsset(data: Data, format: String) async throws -> Entity {
        switch format.lowercased() {
        case "usdz", "usd", "usdc", "usda":
            // Entity(from:) was added in iOS/macOS/visionOS/tvOS 26 (WWDC25 session 287).
            // On older OS versions, write to a temp file and load via the URL-based path.
            if #available(iOS 26, macOS 26, visionOS 26, tvOS 26, *) {
                return try await Entity(from: data)
            } else {
                let ext = format.lowercased()
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                try data.write(to: tempURL)
                return try await Entity(contentsOf: tempURL)
            }
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

    /// Write the entity's mesh data to a local file URL using the format-appropriate serializer.
    ///
    /// Supported formats:
    /// - **STL, OBJ, PLY, ABC, USDZ** — written via ModelIO (radcli14/ModelIO-to-RealityKit)
    /// - **DAE** (Collada) — written via COLLADA serializer (radcli14/DAE-to-RealityKit)
    ///
    /// Usage:
    /// ```swift
    /// try await entity.write3DAsset(to: url)
    /// ```
    ///
    /// - Parameter url: The destination file URL. The file extension determines the format.
    /// - Throws: `RealityKitFormatsError.unsupportedFormat` for unrecognised extensions,
    ///   or a writer-specific error on failure.
    @MainActor
    func write3DAsset(to url: URL) async throws {
        switch url.pathExtension.lowercased() {
        case "stl", "obj", "ply", "abc", "usdz", "usd":
            try await writeMDLAsset(to: url)
        case "dae":
            try await writeDAEAsset(to: url)
        default:
            throw RealityKitFormatsError.unsupportedFormat(url.pathExtension)
        }
    }
}
