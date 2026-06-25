import Testing
import Foundation
import RealityKit
@testable import RealityKitFormats

// MARK: - Scorecard Suite

/// Renders every asset from AssetManifest into a 256×256 PNG thumbnail and writes
/// Tests/Scorecard/<name>.png plus a scorecard.md summary table.
///
/// Run with: swift test --filter ScorecardTests
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
    // A 256×256 solid-white PNG compresses to ~400 bytes; real scene renders are much larger.
    private static let blankThreshold = 2_048

    // MARK: Render

    @MainActor
    @Test("Render thumbnail", arguments: AssetManifest.allAssets)
    func renderThumbnail(asset: AssetManifest.Asset) async throws {
        let entity = try await Entity.from3DAsset(url: asset.url)

        guard let data = await ScorecardGenerator.shared.render(entity: entity) else {
            Issue.record("ARView snapshot unavailable for \(asset.name) — Metal may not be accessible in this environment")
            return
        }

        #expect(
            data.count > Self.blankThreshold,
            "Thumbnail for \(asset.name) appears blank (\(data.count) bytes < \(Self.blankThreshold))"
        )

        let pngURL = Self.scorecardDir.appendingPathComponent("\(asset.name)_\(asset.format).png")
        try data.write(to: pngURL)
    }

    // MARK: Summary

    @Test("Generate scorecard.md")
    func generateScorecard() throws {
        let dir = Self.scorecardDir
        let pngs = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []

        let assetLookup = Dictionary(uniqueKeysWithValues: AssetManifest.allAssets.map { ($0.name, $0) })

        var lines = [
            "# RealityKitFormats Scorecard",
            "",
            "| Model | Format | Thumbnail |",
            "|-------|--------|-----------|",
        ]
        for png in pngs {
            // Filename is "<name>_<format>.png" — split on last underscore to recover both parts.
            let stem = png.deletingPathExtension().lastPathComponent
            let parts = stem.components(separatedBy: "_")
            let format = parts.last?.uppercased() ?? "—"
            let name = parts.dropLast().joined(separator: "_")
            lines.append("| \(name) | \(format) | ![\(stem)](\(png.lastPathComponent)) |")
        }

        let markdown = lines.joined(separator: "\n") + "\n"
        let mdURL = dir.appendingPathComponent("scorecard.md")
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

        #expect(!pngs.isEmpty, "No thumbnails found — run Render thumbnail tests first")
    }
}
