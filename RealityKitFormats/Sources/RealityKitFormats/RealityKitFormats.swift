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
    /// Load a 3D model from a file URL, dispatching to the appropriate loader by file extension.
    ///
    /// Both local `file://` URLs and remote `http(s)://` URLs are accepted. Remote URLs are
    /// downloaded to a temporary file automatically; the caller does not need to handle that.
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
    /// - Parameter url: A local or remote URL for the 3D model.
    /// - Returns: The loaded `Entity`.
    /// - Throws: `RealityKitFormatsError.unsupportedFormat` if the extension is not recognised,
    ///   or a loader-specific error if loading fails.
    @MainActor
    static func from3DAsset(url: URL) async throws -> Entity {
        // Format-aware remote URL dispatch: formats whose loaders resolve external assets
        // from the remote base URL are passed through directly; self-contained or
        // geometry-only formats are downloaded to a single temp file first.
        if url.scheme == "http" || url.scheme == "https" {
            switch url.pathExtension.lowercased() {
            case "dae":
                // DAE-to-RealityKit resolves texture refs relative to the remote base URL.
                return try await ModelEntity.fromDAEAsset(url: url)
            case "gltf":
                // GLTFKit2 receives the remote URL directly.
                return try await Entity.fromGLTFAsset(url: url)
            case "obj":
                // OBJ references external .mtl and textures — download the full dependency
                // tree into a temp directory so MDLAsset can resolve relative paths.
                return try await fromRemoteOBJAsset(url: url)
            default:
                // Self-contained archives (USDZ, GLB) and geometry-only formats (STL, PLY, ABC):
                // a single temp file is sufficient.
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try data.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                return try await from3DAsset(url: tempURL)
            }
        }

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

    /// Download a remote OBJ file along with its MTL sidecars and all referenced textures
    /// into a single temp directory, then load via MDLAsset so relative paths resolve correctly.
    @MainActor
    private static func fromRemoteOBJAsset(url: URL) async throws -> Entity {
        let baseURL = url.deletingLastPathComponent()

        let (objData, objResponse) = try await URLSession.shared.data(from: url)
        guard let objHTTP = objResponse as? HTTPURLResponse, objHTTP.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempOBJURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try objData.write(to: tempOBJURL)

        let objText = String(data: objData, encoding: .utf8) ?? ""
        for mtlName in parseMTLNamesFromOBJ(objText) {
            let mtlRemoteURL = baseURL.appendingPathComponent(mtlName)
            guard let (mtlData, mtlResp) = try? await URLSession.shared.data(from: mtlRemoteURL),
                  (mtlResp as? HTTPURLResponse)?.statusCode == 200 else { continue }

            let mtlLocalURL = tempDir.appendingPathComponent(
                (mtlName as NSString).lastPathComponent)
            try? mtlData.write(to: mtlLocalURL)

            guard let mtlText = String(data: mtlData, encoding: .utf8) else { continue }
            for texRelPath in parseTexturePathsFromMTL(mtlText) {
                let texRemoteURL = baseURL.appendingPathComponent(texRelPath)
                guard let (texData, texResp) = try? await URLSession.shared.data(from: texRemoteURL),
                      (texResp as? HTTPURLResponse)?.statusCode == 200 else { continue }

                let texLocalURL = tempDir.appendingPathComponent(texRelPath)
                try? FileManager.default.createDirectory(
                    at: texLocalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try? texData.write(to: texLocalURL)
            }
        }

        return try await ModelEntity.fromMDLAsset(url: tempOBJURL)
    }

    /// Extracts `mtllib` filenames from OBJ text. Used by both the remote loader and the archiver.
    static func parseMTLNamesFromOBJ(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("mtllib ") else { return nil }
                return String(trimmed.dropFirst("mtllib ".count))
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// Extracts texture relative paths from MTL text. Used by both the remote loader and the archiver.
    static func parseTexturePathsFromMTL(_ text: String) -> [String] {
        let directives = ["map_kd", "map_ks", "map_ka", "map_ns", "map_d",
                          "map_bump", "bump", "disp", "decal", "refl"]
        return text.components(separatedBy: .newlines).compactMap { line -> String? in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
            guard parts.count >= 2,
                  directives.contains(parts[0].lowercased()),
                  let path = parts.last, !path.isEmpty else { return nil }
            return path
        }
    }

    /// Write the entity's mesh data to a local file URL using the format-appropriate serializer.
    ///
    /// Supported formats:
    /// - **GLB, GLTF** — written via GLTFKit2 (radcli14/GLTFKit2)
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
    func write3DAsset(to url: URL, mergeSubmeshes: Bool = false) async throws {
        switch url.pathExtension.lowercased() {
        case "glb", "gltf":
            try await writeGLTFAsset(to: url)
        case "stl", "obj", "ply", "abc", "usdz", "usd":
            try await writeMDLAsset(to: url, mergeSubmeshes: mergeSubmeshes)
        case "dae":
            try await writeDAEAsset(to: url)
        default:
            throw RealityKitFormatsError.unsupportedFormat(url.pathExtension)
        }
    }
}
