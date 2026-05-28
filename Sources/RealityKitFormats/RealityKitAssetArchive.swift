//
//  RealityKitAssetArchive.swift
//  RealityKitFormats
//

import Foundation
import RealityKit

// MARK: - Public Types

/// Metadata stored as `manifest.json` in a RealityKit Asset Archive (.rka).
public struct RealityKitAssetManifest: Codable, Sendable {
    /// Schema version. Current value: 1.
    public let version: Int
    /// Lowercase file extension of the primary model: "obj", "dae", "glb", "usdz", etc.
    public let format: String
    /// Filename of the primary 3D model file inside the ZIP (no path separators).
    public let entryPoint: String
    /// All filenames stored in the archive, for validation on load.
    public let files: [String]
}

/// Errors thrown by RKA archive operations.
public enum RealityKitAssetArchiveError: LocalizedError {
    case missingManifest
    case manifestDecodeFailed(Error)
    case unsupportedManifestVersion(Int)
    case missingEntryPoint(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "RKA archive is missing manifest.json"
        case .manifestDecodeFailed(let e):
            return "RKA manifest could not be decoded: \(e.localizedDescription)"
        case .unsupportedManifestVersion(let v):
            return "RKA manifest version \(v) is not supported"
        case .missingEntryPoint(let name):
            return "RKA entry point '\(name)' was not found in archive"
        }
    }
}

// MARK: - Archive API

public extension Entity {
    /// Serialise a local 3D model file and all its dependencies into a RealityKit Asset Archive.
    ///
    /// The returned `Data` is a standard ZIP archive (STORED, no compression) containing
    /// a `manifest.json` entry followed by the original model file and any referenced sidecars
    /// (MTL, textures, binary buffers) with their relative directory layout preserved.
    ///
    /// Self-contained formats (USDZ, GLB, STL, PLY, ABC) produce a two-entry archive
    /// (manifest + single file). Dependency-bearing formats (OBJ, DAE, GLTF text) include all
    /// discovered sidecars so the model can be reloaded byte-for-byte with textures intact.
    ///
    /// - Parameter url: A local `file://` URL for the 3D model.
    /// - Returns: RKA archive data suitable for storage in a SwiftData `@Attribute(.externalStorage)`.
    @MainActor
    static func archiveAsset(url: URL) async throws -> Data {
        let format = url.pathExtension.lowercased()
        let entries = try assetDependencies(url: url, format: format)

        let filenames = ["manifest.json"] + entries.map(\.path)
        let manifest = RealityKitAssetManifest(
            version: 1,
            format: format,
            entryPoint: url.lastPathComponent,
            files: filenames
        )
        let manifestData = try JSONEncoder().encode(manifest)

        var allEntries = [(path: String, data: Data)]()
        allEntries.append(("manifest.json", manifestData))
        allEntries.append(contentsOf: entries)
        return rkaZIPData(entries: allEntries)
    }

    /// Load a 3D model from a RealityKit Asset Archive produced by ``archiveAsset(url:)``.
    ///
    /// The archive is extracted to a temporary directory, then the entry-point file is loaded
    /// via the same format dispatch as ``from3DAsset(url:)``. If `archive` does not contain
    /// a `manifest.json` entry (e.g. it is a plain USDZ), the bytes are passed to the USDZ loader.
    ///
    /// - Parameter archive: `Data` previously returned by ``archiveAsset(url:)``.
    @MainActor
    static func from3DAsset(archive: Data) async throws -> Entity {
        guard isRKAArchive(archive) else {
            return try await from3DAsset(data: archive, format: "usdz")
        }

        let zipEntries = try rkaZIPExtract(archive)

        guard let manifestData = zipEntries["manifest.json"] else {
            throw RealityKitAssetArchiveError.missingManifest
        }
        let manifest: RealityKitAssetManifest
        do {
            manifest = try JSONDecoder().decode(RealityKitAssetManifest.self, from: manifestData)
        } catch {
            throw RealityKitAssetArchiveError.manifestDecodeFailed(error)
        }
        guard manifest.version == 1 else {
            throw RealityKitAssetArchiveError.unsupportedManifestVersion(manifest.version)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for (path, data) in zipEntries where path != "manifest.json" {
            let destURL = tempDir.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: destURL)
        }

        let entryURL = tempDir.appendingPathComponent(manifest.entryPoint)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw RealityKitAssetArchiveError.missingEntryPoint(manifest.entryPoint)
        }
        return try await from3DAsset(url: entryURL)
    }
}

/// Returns `true` if `data` is a RealityKit Asset Archive (contains a `manifest.json` entry).
///
/// Use this to distinguish an RKA archive from a plain USDZ or GLB blob when both are stored
/// as `Data` in SwiftData and you haven't stored the format string separately.
public func isRKAArchive(_ data: Data) -> Bool {
    (try? rkaZIPExtract(data))?["manifest.json"] != nil
}

/// Decodes and returns the ``RealityKitAssetManifest`` from an RKA archive `Data` blob.
///
/// - Parameter archiveData: `Data` returned by ``Entity/archiveAsset(url:)``.
/// - Throws: ``RealityKitAssetArchiveError`` if the data is not a valid RKA archive.
public func rkaManifest(from archiveData: Data) throws -> RealityKitAssetManifest {
    let zipEntries = try rkaZIPExtract(archiveData)
    guard let manifestData = zipEntries["manifest.json"] else {
        throw RealityKitAssetArchiveError.missingManifest
    }
    do {
        return try JSONDecoder().decode(RealityKitAssetManifest.self, from: manifestData)
    } catch {
        throw RealityKitAssetArchiveError.manifestDecodeFailed(error)
    }
}

// MARK: - Dependency Discovery

private extension Entity {
    static func assetDependencies(url: URL, format: String) throws -> [(path: String, data: Data)] {
        switch format {
        case "obj":  return try objFileDependencies(url: url)
        case "dae":  return try daeFileDependencies(url: url)
        case "gltf": return try gltfFileDependencies(url: url)
        default:
            // Self-contained: glb, usdz, stl, ply, abc, etc.
            return [(url.lastPathComponent, try Data(contentsOf: url))]
        }
    }

    // MARK: OBJ

    static func objFileDependencies(url: URL) throws -> [(path: String, data: Data)] {
        let objData = try Data(contentsOf: url)
        let baseDir = url.deletingLastPathComponent()
        var result = [(path: String, data: Data)]()
        result.append((url.lastPathComponent, objData))

        let objText = String(data: objData, encoding: .utf8) ?? ""
        for mtlName in parseMTLNamesFromOBJ(objText) {
            let mtlURL = baseDir.appendingPathComponent(mtlName)
            guard let mtlData = try? Data(contentsOf: mtlURL) else { continue }
            result.append(((mtlName as NSString).lastPathComponent, mtlData))

            let mtlText = String(data: mtlData, encoding: .utf8) ?? ""
            for texRelPath in parseTexturePathsFromMTL(mtlText) {
                // Normalise leading "./" so archive paths match what the MTL references.
                let normalised = texRelPath.hasPrefix("./") ? String(texRelPath.dropFirst(2)) : texRelPath
                let texURL = baseDir.appendingPathComponent(normalised)
                guard let texData = try? Data(contentsOf: texURL) else { continue }
                if !result.contains(where: { $0.path == normalised }) {
                    result.append((normalised, texData))
                }
            }
        }
        return result
    }

    // MARK: DAE

    static func daeFileDependencies(url: URL) throws -> [(path: String, data: Data)] {
        let daeData = try Data(contentsOf: url)
        let baseDir = url.deletingLastPathComponent()
        var result = [(path: String, data: Data)]()
        result.append((url.lastPathComponent, daeData))

        for rawPath in daeImagePaths(from: daeData) {
            let relPath: String
            if rawPath.hasPrefix("file://") {
                // Absolute file:// URL from some exporters — keep only the last path component.
                relPath = URL(string: rawPath)?.lastPathComponent ?? (rawPath as NSString).lastPathComponent
            } else if rawPath.hasPrefix("./") {
                relPath = String(rawPath.dropFirst(2))
            } else {
                relPath = rawPath
            }
            let fileURL = baseDir.appendingPathComponent(relPath)
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            if !result.contains(where: { $0.path == relPath }) {
                result.append((relPath, fileData))
            }
        }
        return result
    }

    // MARK: GLTF text

    static func gltfFileDependencies(url: URL) throws -> [(path: String, data: Data)] {
        let gltfData = try Data(contentsOf: url)
        let baseDir = url.deletingLastPathComponent()
        var result = [(path: String, data: Data)]()
        result.append((url.lastPathComponent, gltfData))

        guard let json = try? JSONSerialization.jsonObject(with: gltfData) as? [String: Any] else {
            return result
        }
        var externalURIs = [String]()
        if let buffers = json["buffers"] as? [[String: Any]] {
            externalURIs += buffers.compactMap { buf -> String? in
                guard let uri = buf["uri"] as? String, !uri.hasPrefix("data:") else { return nil }
                return uri
            }
        }
        if let images = json["images"] as? [[String: Any]] {
            externalURIs += images.compactMap { img -> String? in
                guard let uri = img["uri"] as? String, !uri.hasPrefix("data:") else { return nil }
                return uri
            }
        }
        for uri in externalURIs {
            let fileURL = baseDir.appendingPathComponent(uri)
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            result.append((uri, fileData))
        }
        return result
    }
}

// MARK: - DAE Image Path Extraction

private final class DAEImagePathParser: NSObject, XMLParserDelegate {
    private var inLibraryImages = false
    private var inInitFrom = false
    private var buffer = ""
    private(set) var paths = [String]()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "library_images" { inLibraryImages = true }
        if inLibraryImages && elementName == "init_from" {
            inInitFrom = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inInitFrom { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "init_from" && inLibraryImages {
            let path = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { paths.append(path) }
            inInitFrom = false
            buffer = ""
        }
        if elementName == "library_images" { inLibraryImages = false }
    }
}

private func daeImagePaths(from data: Data) -> [String] {
    let parser = XMLParser(data: data)
    let delegate = DAEImagePathParser()
    parser.delegate = delegate
    parser.parse()
    return delegate.paths
}

// MARK: - ZIP Writer

/// Builds a STORED (uncompressed) ZIP archive from an ordered list of (archivePath, data) pairs.
private func rkaZIPData(entries: [(path: String, data: Data)]) -> Data {
    var zip = Data()
    var centralDirectory = Data()
    var fileCount: UInt16 = 0

    for entry in entries {
        let fileData = entry.data
        let filenameBytes = Data(entry.path.utf8)
        let crc = rkaCRC32(fileData)
        let size = UInt32(fileData.count)
        let offset = UInt32(zip.count)

        // Local file header (30 bytes fixed, method 0 = STORED)
        zip.rkaAppendLE(UInt32(0x04034b50))
        zip.rkaAppendLE(UInt16(20))
        zip.rkaAppendLE(UInt16(0))
        zip.rkaAppendLE(UInt16(0))   // compression: STORED
        zip.rkaAppendLE(UInt16(0))   // mod time
        zip.rkaAppendLE(UInt16(0))   // mod date
        zip.rkaAppendLE(crc)
        zip.rkaAppendLE(size)        // compressed size
        zip.rkaAppendLE(size)        // uncompressed size
        zip.rkaAppendLE(UInt16(filenameBytes.count))
        zip.rkaAppendLE(UInt16(0))   // extra field length
        zip.append(filenameBytes)
        zip.append(fileData)

        // Central directory entry (46 bytes fixed)
        centralDirectory.rkaAppendLE(UInt32(0x02014b50))
        centralDirectory.rkaAppendLE(UInt16(20))  // version made by
        centralDirectory.rkaAppendLE(UInt16(20))  // version needed
        centralDirectory.rkaAppendLE(UInt16(0))   // flags
        centralDirectory.rkaAppendLE(UInt16(0))   // compression: STORED
        centralDirectory.rkaAppendLE(UInt16(0))   // mod time
        centralDirectory.rkaAppendLE(UInt16(0))   // mod date
        centralDirectory.rkaAppendLE(crc)
        centralDirectory.rkaAppendLE(size)        // compressed size
        centralDirectory.rkaAppendLE(size)        // uncompressed size
        centralDirectory.rkaAppendLE(UInt16(filenameBytes.count))
        centralDirectory.rkaAppendLE(UInt16(0))   // extra field length
        centralDirectory.rkaAppendLE(UInt16(0))   // file comment length
        centralDirectory.rkaAppendLE(UInt16(0))   // disk start
        centralDirectory.rkaAppendLE(UInt16(0))   // internal attributes
        centralDirectory.rkaAppendLE(UInt32(0))   // external attributes
        centralDirectory.rkaAppendLE(offset)      // local header offset
        centralDirectory.append(filenameBytes)
        fileCount += 1
    }

    let cdOffset = UInt32(zip.count)
    let cdSize = UInt32(centralDirectory.count)
    zip.append(centralDirectory)

    // End of central directory record
    zip.rkaAppendLE(UInt32(0x06054b50))
    zip.rkaAppendLE(UInt16(0))       // disk number
    zip.rkaAppendLE(UInt16(0))       // start disk
    zip.rkaAppendLE(fileCount)       // entries on this disk
    zip.rkaAppendLE(fileCount)       // total entries
    zip.rkaAppendLE(cdSize)
    zip.rkaAppendLE(cdOffset)
    zip.rkaAppendLE(UInt16(0))       // comment length

    return zip
}

// MARK: - ZIP Reader

private enum RKAZIPError: Error { case invalidZIP, invalidEntry }

/// Extracts all STORED entries from `data` into a `[filename: bytes]` dictionary.
///
/// Only STORED (uncompressed) entries are supported, matching what ``rkaZIPData(entries:)``
/// produces. USDZ archives are also STORED and can be read, but will have no `manifest.json`.
private func rkaZIPExtract(_ data: Data) throws -> [String: Data] {
    guard data.count >= 22 else { throw RKAZIPError.invalidZIP }

    // Locate EOCD by scanning backwards for signature 0x06054b50.
    var eocdOffset: Int? = nil
    let searchStart = max(0, data.count - 22 - 65535)
    for i in stride(from: data.count - 22, through: searchStart, by: -1) {
        if rkaReadUInt32(data, at: i) == 0x06054b50 {
            eocdOffset = i
            break
        }
    }
    guard let eocdOffset else { throw RKAZIPError.invalidZIP }

    let totalEntries = Int(rkaReadUInt16(data, at: eocdOffset + 10))
    let cdOffset     = Int(rkaReadUInt32(data, at: eocdOffset + 16))

    var result = [String: Data]()
    var cdPos = cdOffset

    for _ in 0..<totalEntries {
        guard cdPos + 46 <= data.count,
              rkaReadUInt32(data, at: cdPos) == 0x02014b50 else {
            throw RKAZIPError.invalidEntry
        }

        let uncompressedSize = Int(rkaReadUInt32(data, at: cdPos + 24))
        let filenameLen      = Int(rkaReadUInt16(data, at: cdPos + 28))
        let extraLen         = Int(rkaReadUInt16(data, at: cdPos + 30))
        let commentLen       = Int(rkaReadUInt16(data, at: cdPos + 32))
        let localOffset      = Int(rkaReadUInt32(data, at: cdPos + 42))

        let nameStart = cdPos + 46
        guard nameStart + filenameLen <= data.count else { throw RKAZIPError.invalidEntry }
        let filename = String(data: data[nameStart..<(nameStart + filenameLen)], encoding: .utf8) ?? ""

        // Local file header: 30 bytes fixed + local filename length + local extra length
        guard localOffset + 30 <= data.count else { throw RKAZIPError.invalidEntry }
        let localFilenameLen = Int(rkaReadUInt16(data, at: localOffset + 26))
        let localExtraLen    = Int(rkaReadUInt16(data, at: localOffset + 28))
        let dataStart = localOffset + 30 + localFilenameLen + localExtraLen
        let dataEnd   = dataStart + uncompressedSize

        guard dataEnd <= data.count else { throw RKAZIPError.invalidEntry }
        if !filename.isEmpty {
            result[filename] = Data(data[dataStart..<dataEnd])
        }

        cdPos += 46 + filenameLen + extraLen + commentLen
    }
    return result
}

// MARK: - ZIP Byte Helpers

private func rkaReadUInt16(_ data: Data, at offset: Int) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func rkaReadUInt32(_ data: Data, at offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return UInt32(data[offset])
         | (UInt32(data[offset + 1]) << 8)
         | (UInt32(data[offset + 2]) << 16)
         | (UInt32(data[offset + 3]) << 24)
}

/// CRC-32 using the IEEE 802.3 polynomial, as required by the ZIP specification.
private func rkaCRC32(_ data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        table[i] = c
    }
    return data.reduce(UInt32(0xFFFFFFFF)) {
        table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8)
    } ^ 0xFFFFFFFF
}

private extension Data {
    mutating func rkaAppendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
