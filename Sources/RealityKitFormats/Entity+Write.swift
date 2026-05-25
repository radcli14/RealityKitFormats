//
//  Entity+Write.swift
//  RealityKitFormats
//

import Foundation
import RealityKit
import ModelIO_to_RealityKit
import DAE_to_RealityKit

// MARK: - Error Type

/// Errors thrown by ``Entity/write(to:)``.
public enum RealityKitFormatsWriteError: Error, LocalizedError {
    /// The file extension is not supported for writing.
    case unsupportedFormat(String)
    /// The format is recognised but the write path has not been implemented yet.
    case notImplemented(String)
    /// Mesh data could not be extracted from the entity tree.
    case meshExtractionFailed
    /// The underlying export call reported failure.
    case exportFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "RealityKitFormats: no writer registered for '\(ext)' format"
        case .notImplemented(let detail):
            return "RealityKitFormats: \(detail)"
        case .meshExtractionFailed:
            return "RealityKitFormats: failed to extract mesh data from the entity tree"
        case .exportFailed(let url):
            return "RealityKitFormats: export to \(url.lastPathComponent) failed"
        }
    }
}

// MARK: - Unified Writer

public extension Entity {
    /// Write this entity to a local file URL. The output format is inferred from the URL's path extension.
    ///
    /// Supported extensions: `stl`, `obj`, `ply`, `abc` (via ModelIO), `dae` (via DAE-to-RealityKit),
    /// `glb`/`gltf` (not yet available).
    ///
    /// ```swift
    /// try await entity.write(to: documentsURL.appendingPathComponent("model.obj"))
    /// ```
    ///
    /// - Parameter url: Destination file URL. The directory must already exist.
    /// - Throws: ``RealityKitFormatsWriteError`` on failure, or a format-specific error from an
    ///   upstream package.
    @MainActor
    func write(to url: URL) async throws {
        switch url.pathExtension.lowercased() {
        case "stl", "obj", "ply", "abc":
            try await writeMDLAsset(to: url)
        case "dae":
            try await writeDAEAsset(to: url)
        case "glb", "gltf":
            try await writeGLTFAsset(to: url)
        default:
            throw RealityKitFormatsWriteError.unsupportedFormat(url.pathExtension)
        }
    }
}

// MARK: - GLB / GLTF (stub)

private extension Entity {
    // GLTFKit2 export is WIP (https://github.com/warrenm/GLTFKit2).
    // When the API stabilises, build a GLTFAsset from the entity tree and call the exporter here.
    @MainActor
    func writeGLTFAsset(to url: URL) async throws {
        throw RealityKitFormatsWriteError.notImplemented(
            "GLB/GLTF write is not yet available: GLTFKit2 export is currently WIP."
        )
    }
}
