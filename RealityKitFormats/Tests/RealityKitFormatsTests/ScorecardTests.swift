import Testing
import Foundation
import RealityKit
@testable import RealityKitFormats

// MARK: - Scorecard Suite

/// Renders every asset from AssetManifest into 256×256 PNG thumbnails and writes
/// Tests/Scorecard/<name>_<src>_original.png (raw load) and
/// Tests/Scorecard/<name>_<src>_<target>.png (round-trip conversions),
/// plus a scorecard.md summary table.
///
/// Tests are serialized so thumbnails are fully written before scorecard.md is generated.
@Suite("Scorecard", .serialized)
struct ScorecardTests {

    // Derived from #filePath so this works regardless of the working directory.
    private static let scorecardDir: URL = {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // .../Tests/RealityKitFormatsTests/
            .deletingLastPathComponent()    // .../Tests/
            .appendingPathComponent("Scorecard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Minimum PNG size in bytes that constitutes a non-blank render.
    // A 256×256 solid-white PNG compresses to ~200 bytes; real scene renders are typically 10 KB+.
    private static let blankThreshold = 5_000

    // Export formats — order is fixed and matches the scorecard column order.
    private static let exportFormats = ["glb", "usdz", "dae", "obj", "stl"]

    // MARK: Conversion Case

    struct ConversionCase: CustomStringConvertible, Sendable {
        let asset: AssetManifest.Asset
        let targetFormat: String

        var description: String { "\(asset.name)_\(asset.format)_\(targetFormat)" }
    }

    static let allConversions: [ConversionCase] = AssetManifest.allAssets.flatMap { asset in
        exportFormats.map { ConversionCase(asset: asset, targetFormat: $0) }
    }

    // MARK: Render Original

    @MainActor
    @Test("Render original", arguments: AssetManifest.allAssets)
    func renderOriginal(asset: AssetManifest.Asset) async throws {
        // Download data directly so we can record the source file size
        let (fileData, _) = try await URLSession.shared.data(from: asset.url)
        let entity = try await Entity.from3DAsset(data: fileData, format: asset.format)

        guard let png = await ScorecardGenerator.shared.render(entity: entity) else {
            Issue.record("ARView snapshot unavailable for \(asset.name) — Metal may not be accessible")
            return
        }

        #expect(
            png.count > Self.blankThreshold,
            "Thumbnail for \(asset.name) appears blank (\(png.count) bytes < \(Self.blankThreshold))"
        )

        let stem = "\(asset.name)_\(asset.format)_original"
        try png.write(to: Self.scorecardDir.appendingPathComponent("\(stem).png"))
        try "\(fileData.count)".write(
            to: Self.scorecardDir.appendingPathComponent("\(stem).size"),
            atomically: true, encoding: .utf8)
    }

    // MARK: Render Conversion

    @MainActor
    @Test("Render conversion", arguments: allConversions)
    func renderConversion(conversion: ConversionCase) async throws {
        let entity = try await Entity.from3DAsset(url: conversion.asset.url)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(conversion.asset.name).\(conversion.targetFormat)")
        try await entity.write3DAsset(to: tmpURL)
        let convertedSize = (try? FileManager.default.attributesOfItem(atPath: tmpURL.path)[.size] as? Int) ?? 0

        let converted = try await Entity.from3DAsset(url: tmpURL)

        guard let png = await ScorecardGenerator.shared.render(entity: converted) else {
            Issue.record("ARView snapshot unavailable for \(conversion.description) — Metal may not be accessible")
            return
        }

        #expect(
            png.count > Self.blankThreshold,
            "Thumbnail for \(conversion.description) appears blank (\(png.count) bytes < \(Self.blankThreshold))"
        )

        let stem = conversion.description
        try png.write(to: Self.scorecardDir.appendingPathComponent("\(stem).png"))
        try "\(convertedSize)".write(
            to: Self.scorecardDir.appendingPathComponent("\(stem).size"),
            atomically: true, encoding: .utf8)
    }

    // MARK: Summary

    @Test("Generate scorecard.md")
    func generateScorecard() throws {
        let dir = Self.scorecardDir
        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        let pngs = allFiles
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Fixed column key order: original first, then each export format
        let columnOrder = ["original"] + Self.exportFormats

        struct Entry {
            let stem: String
            let filename: String
            let size: String
        }

        // groups["DamagedHelmet_glb"]["usdz"] = Entry(...)
        var groups: [String: [String: Entry]] = [:]
        var groupOrder: [String] = []  // preserves first-seen order (alphabetical via sorted pngs)

        for png in pngs {
            let stem = png.deletingPathExtension().lastPathComponent
            let parts = stem.components(separatedBy: "_")
            guard parts.count >= 3 else { continue }
            let target = parts.last!.lowercased()
            let source = parts[parts.count - 2].lowercased()
            let name = parts.dropLast(2).joined(separator: "_")
            let groupKey = "\(name)_\(source)"

            let sizeURL = dir.appendingPathComponent("\(stem).size")
            let sizeStr = (try? String(contentsOf: sizeURL, encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { formatFileSize($0) } ?? "—"

            if groups[groupKey] == nil {
                groups[groupKey] = [:]
                groupOrder.append(groupKey)
            }
            groups[groupKey]![target] = Entry(stem: stem, filename: png.lastPathComponent, size: sizeStr)
        }

        var lines = [
            "# RealityKitFormats Scorecard",
            "",
            "| Model | Original | GLB | USDZ | DAE | OBJ | STL |",
            "|-------|:--------:|:---:|:----:|:---:|:---:|:---:|",
        ]

        for groupKey in groupOrder {
            guard let entries = groups[groupKey] else { continue }
            let parts = groupKey.components(separatedBy: "_")
            let source = parts.last!.uppercased()
            let name = parts.dropLast().joined(separator: "_")

            // Row 1: thumbnails
            let thumbs = columnOrder.map { key -> String in
                guard let e = entries[key] else { return "—" }
                return "![\(e.stem)](\(e.filename))"
            }
            lines.append("| **\(name)** (\(source)) | \(thumbs.joined(separator: " | ")) |")

            // Row 2: file sizes
            let sizes = columnOrder.map { key in entries[key]?.size ?? "—" }
            lines.append("| | \(sizes.joined(separator: " | ")) |")
        }

        let markdown = lines.joined(separator: "\n") + "\n"
        try markdown.write(
            to: dir.appendingPathComponent("scorecard.md"),
            atomically: true, encoding: .utf8)

        #expect(!pngs.isEmpty, "No thumbnails found — run render tests first")
    }
}

private func formatFileSize(_ bytes: Int) -> String {
    if bytes >= 1_048_576 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    } else if bytes >= 1_024 {
        return String(format: "%.1f KB", Double(bytes) / 1_024)
    }
    return "\(bytes) B"
}
