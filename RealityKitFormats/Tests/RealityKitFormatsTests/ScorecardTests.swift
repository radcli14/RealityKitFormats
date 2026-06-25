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

    // All export formats exercised in the conversion suite.
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
        let entity = try await Entity.from3DAsset(url: asset.url)

        guard let data = await ScorecardGenerator.shared.render(entity: entity) else {
            Issue.record("ARView snapshot unavailable for \(asset.name) — Metal may not be accessible in this environment")
            return
        }

        #expect(
            data.count > Self.blankThreshold,
            "Thumbnail for \(asset.name) appears blank (\(data.count) bytes < \(Self.blankThreshold))"
        )

        let pngURL = Self.scorecardDir.appendingPathComponent("\(asset.name)_\(asset.format)_original.png")
        try data.write(to: pngURL)
    }

    // MARK: Render Conversion

    @MainActor
    @Test("Render conversion", arguments: allConversions)
    func renderConversion(conversion: ConversionCase) async throws {
        let entity = try await Entity.from3DAsset(url: conversion.asset.url)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(conversion.asset.name).\(conversion.targetFormat)")
        try await entity.write3DAsset(to: tmpURL)

        let converted = try await Entity.from3DAsset(url: tmpURL)

        guard let data = await ScorecardGenerator.shared.render(entity: converted) else {
            Issue.record("ARView snapshot unavailable for \(conversion.description) — Metal may not be accessible")
            return
        }

        #expect(
            data.count > Self.blankThreshold,
            "Thumbnail for \(conversion.description) appears blank (\(data.count) bytes < \(Self.blankThreshold))"
        )

        let pngURL = Self.scorecardDir.appendingPathComponent("\(conversion.description).png")
        try data.write(to: pngURL)
    }

    // MARK: Summary

    @Test("Generate scorecard.md")
    func generateScorecard() throws {
        let dir = Self.scorecardDir
        let pngs = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []

        var lines = [
            "# RealityKitFormats Scorecard",
            "",
            "| Model | Source | Target | Thumbnail |",
            "|-------|--------|--------|-----------|",
        ]
        for png in pngs {
            // Filename is "<name>_<source>_<target>.png" — split from the right.
            let stem = png.deletingPathExtension().lastPathComponent
            let parts = stem.components(separatedBy: "_")
            guard parts.count >= 3 else { continue }
            let target = parts.last!.uppercased()
            let source = parts[parts.count - 2].uppercased()
            let name = parts.dropLast(2).joined(separator: "_")
            lines.append("| \(name) | \(source) | \(target) | ![\(stem)](\(png.lastPathComponent)) |")
        }

        let markdown = lines.joined(separator: "\n") + "\n"
        let mdURL = dir.appendingPathComponent("scorecard.md")
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

        #expect(!pngs.isEmpty, "No thumbnails found — run render tests first")
    }
}
