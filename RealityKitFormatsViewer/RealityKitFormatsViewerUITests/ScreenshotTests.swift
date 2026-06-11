//
//  ScreenshotTests.swift
//  RealityKitFormatsViewerUITests
//
//  Two modes:
//  - testDirectLoadScreenshots / testRoundTripScreenshots: ad-hoc gallery saved
//    to the app sandbox (XCTAttachment + Documents/RealityKitFormatsScreenshots/).
//  - testGenerateScorecard: produces Scorecard/*.png and SCORECARD.md at the
//    repository root, suitable for git check-in.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Test matrix

    private static let remoteURLs: [URL] = {
        let khronosBase = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models"
        let glbFiles = ["DamagedHelmet", "ToyCar", "ABeautifulGame", "ChronographWatch", "CarConcept"]
        let glbURLs = glbFiles.compactMap {
            URL(string: "\(khronosBase)/\($0)/glTF-Binary/\($0).glb")
        }

        let appleBase = "https://developer.apple.com/augmented-reality/quick-look/models"
        let usdzURLs = ["teapot"].compactMap {
            URL(string: "\(appleBase)/\($0)/\($0).usdz")
        }

        let daeBase = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/sourceModels"
        let daeURLs = ["GearboxAssy", "Duck"].compactMap {
            URL(string: "\(daeBase)/\($0)/\($0).dae")
        }

        return glbURLs + usdzURLs + daeURLs
    }()

    private static let formats = ["GLB", "USDZ", "DAE", "OBJ", "STL"]

    // MARK: - Output directories

    // Ad-hoc screenshots → app sandbox Documents folder
    private static let screenshotDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("RealityKitFormatsScreenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Scorecard output → repository root (derived from source file path at compile time)
    private static let scorecardDir: URL = {
        if let envPath = ProcessInfo.processInfo.environment["SCORECARD_DIR"] {
            let dir = URL(fileURLWithPath: envPath)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        // #filePath is a compile-time constant pointing to this source file on the Mac.
        // Go up: UITests/ → RealityKitFormatsViewer/ → RealityKitFormats/ (repo root)
        let sourceFile = URL(fileURLWithPath: #filePath)
        let candidate = sourceFile
            .deletingLastPathComponent()   // .../RealityKitFormatsViewerUITests/
            .deletingLastPathComponent()   // .../RealityKitFormatsViewer/
            .deletingLastPathComponent()   // .../RealityKitFormats/ (repo root)
            .appendingPathComponent("Scorecard")
        do {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
            print("📁 Scorecard dir: \(candidate.path)")
            return candidate
        } catch {
            // Fallback for real-device runs where the project path is not writable
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir = docs.appendingPathComponent("Scorecard")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            print("📁 Scorecard dir (fallback): \(dir.path)")
            return dir
        }
    }()

    private static let scorecardMDURL: URL =
        scorecardDir.deletingLastPathComponent().appendingPathComponent("SCORECARD.md")

    // MARK: - Ad-hoc tests

    /// Generates one 256×256 PNG per (URL, format) pair in direct (non-round-trip) mode.
    func testDirectLoadScreenshots() {
        for url in Self.remoteURLs {
            for format in Self.formats {
                captureScreenshot(url: url, format: format, forceConversion: false)
            }
        }
    }

    /// Generates one 256×256 PNG per URL in round-trip mode using the URL's native format.
    func testRoundTripScreenshots() {
        for url in Self.remoteURLs {
            let nativeFormat = url.pathExtension.uppercased()
            captureScreenshot(url: url, format: nativeFormat, forceConversion: true)
        }
    }

    // MARK: - Scorecard test

    /// Round-trips every remote URL through every target format, captures 256×256 thumbnails,
    /// and writes Scorecard/*.png + SCORECARD.md to the repository root.
    func testGenerateScorecard() {
        var entries: [ScorecardEntry] = []
        for url in Self.remoteURLs {
            let modelName = url.deletingPathExtension().lastPathComponent
            let sourceFormat = url.pathExtension.uppercased()
            for format in Self.formats {
                entries.append(runScorecardCapture(
                    url: url,
                    modelName: modelName,
                    sourceFormat: sourceFormat,
                    targetFormat: format
                ))
            }
            // Write SCORECARD.md after each model so partial progress survives a crash.
            flushScorecard(entries: entries)
        }
    }

    private func flushScorecard(entries: [ScorecardEntry]) {
        let md = buildScorecardMarkdown(entries: entries)
        do {
            try md.write(to: Self.scorecardMDURL, atomically: true, encoding: .utf8)
            print("📝 SCORECARD.md updated (\(entries.count) entries) → \(Self.scorecardMDURL.path)")
        } catch {
            print("❌ Failed to write SCORECARD.md: \(error)")
        }
        if let data = md.data(using: .utf8) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
            attachment.name = "SCORECARD.md"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    // MARK: - Ad-hoc capture helper

    private func captureScreenshot(url: URL, format: String, forceConversion: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_URL"] = url.absoluteString
        app.launchEnvironment["UITEST_FORMAT"] = format
        app.launchEnvironment["UITEST_FORCE_CONVERSION"] = forceConversion ? "true" : "false"
        app.launchEnvironment["UITEST_HIDE_CHROME"] = "true"
        app.launch()

        waitForLoadingToFinish(in: app)

        guard app.state == .runningForeground else {
            app.terminate()
            return
        }

        let modelName = url.deletingPathExtension().lastPathComponent
        let mode = forceConversion ? "roundtrip" : "direct"
        let filename = "\(modelName)_\(format.lowercased())_\(mode).png"

        if let data = screenshotThumbnail(from: app)?.pngData() {
            saveAttachment(data: data, filename: filename)
            let fileURL = Self.screenshotDir.appendingPathComponent(filename)
            try? data.write(to: fileURL)
        }

        app.terminate()
    }

    // MARK: - Scorecard capture helper

    private struct ScorecardEntry {
        let modelName: String
        let sourceFormat: String
        let targetFormat: String
        let fileSize: Int64
        let succeeded: Bool
        let imagePath: URL?
    }

    private func runScorecardCapture(
        url: URL,
        modelName: String,
        sourceFormat: String,
        targetFormat: String
    ) -> ScorecardEntry {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_URL"] = url.absoluteString
        app.launchEnvironment["UITEST_FORMAT"] = targetFormat
        app.launchEnvironment["UITEST_FORCE_CONVERSION"] = "true"
        app.launchEnvironment["UITEST_HIDE_CHROME"] = "true"
        app.launch()

        waitForLoadingToFinish(in: app)

        guard app.state == .runningForeground else {
            app.terminate()
            return ScorecardEntry(modelName: modelName, sourceFormat: sourceFormat,
                                  targetFormat: targetFormat, fileSize: 0,
                                  succeeded: false, imagePath: nil)
        }

        // RealityView is Metal-backed and doesn't reliably propagate accessibilityValue,
        // so detect success by the absence of the error overlay instead.
        let succeeded = !app.staticTexts["An Error Occurred"].exists

        // Read the converted 3D file size from the simulator's app container before terminating.
        let fileSize = convertedFileSize(targetFormat: targetFormat)

        let filename = "\(modelName)_\(targetFormat.lowercased())_roundtrip.png"
        var imagePath: URL? = nil
        if let data = screenshotThumbnail(from: app)?.pngData() {
            let dest = Self.scorecardDir.appendingPathComponent(filename)
            do {
                try data.write(to: dest)
                let sizeStr = fileSize > 0 ? " · 3D file: \(formatFileSize(fileSize))" : ""
                print("🖼 Saved \(filename)\(sizeStr)")
                imagePath = dest
            } catch {
                print("❌ Failed to save \(filename): \(error)")
            }
            saveAttachment(data: data, filename: filename)
        } else {
            print("⚠️ screenshotThumbnail returned nil for \(modelName) → \(targetFormat)")
        }

        app.terminate()
        return ScorecardEntry(modelName: modelName, sourceFormat: sourceFormat,
                              targetFormat: targetFormat, fileSize: fileSize,
                              succeeded: succeeded, imagePath: imagePath)
    }

    // MARK: - Shared wait/query helpers

    private func waitForLoadingToFinish(in app: XCUIApplication, timeout: TimeInterval = 45) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            guard app.state == .runningForeground else { return }
            if !app.activityIndicators.firstMatch.exists {
                Thread.sleep(forTimeInterval: 2.0)
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        print("⏱ Load timed out after \(Int(timeout))s — screenshotting current state")
    }

    /// Crops the full-app screenshot to the centered 256×256 region where
    /// UITEST_HIDE_CHROME mode renders RealityViewFromRemote on a black background.
    /// Because the view is always centered via ZStack, this is device-independent.
    /// The returned image is exactly 256×256 physical pixels (scale forced to 1).
    private func screenshotThumbnail(from app: XCUIApplication) -> PlatformImage? {
        let raw = app.screenshot().image
        let s = raw.size  // logical points
        let side: CGFloat = 256
        let cropRect = CGRect(x: (s.width - side) / 2, y: (s.height - side) / 2,
                              width: side, height: side)
        return raw.cropped(to: cropRect).resized(to: CGSize(width: 256, height: 256))
    }

    /// Reads the byte count of TempAsset.<ext> from the simulator's app container.
    /// Uses SIMULATOR_UDID (set by Xcode) to locate the right device, then searches
    /// the Application containers for the file — no subprocess needed.
    private func convertedFileSize(targetFormat: String) -> Int64 {
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
        let home = NSHomeDirectory()
        print("🔍 SIMULATOR_UDID=\(udid.isEmpty ? "NOT SET" : udid), HOME=\(home)")
        guard !udid.isEmpty else { return 0 }
        let filename = "TempAsset.\(targetFormat.lowercased())"
        let appContainers = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Data/Application")
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: appContainers.path)
        print("🔍 Containers path exists=\(exists): \(appContainers.path)")
        guard let dirs = try? fm.contentsOfDirectory(at: appContainers, includingPropertiesForKeys: nil) else { return 0 }
        print("🔍 Searching \(dirs.count) app containers for \(filename)")
        for dir in dirs {
            let candidate = dir.appendingPathComponent("tmp/\(filename)")
            if let size = (try? fm.attributesOfItem(atPath: candidate.path)[.size] as? NSNumber)?.int64Value {
                print("🔍 Found \(filename): \(size) bytes in \(dir.lastPathComponent)")
                return size
            }
        }
        print("🔍 \(filename) not found in any container")
        return 0
    }

    private func saveAttachment(data: Data, filename: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Markdown generation

    private func buildScorecardMarkdown(entries: [ScorecardEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: Date())

        var md = """
        # RealityKitFormats Scorecard

        Generated by `testGenerateScorecard()`. Each section shows round-trip conversion
        results for one source model across all five target formats.

        ---

        """

        // Group entries by modelName, preserving insertion order
        var seen: [String] = []
        var grouped: [String: [ScorecardEntry]] = [:]
        for entry in entries {
            if grouped[entry.modelName] == nil {
                seen.append(entry.modelName)
                grouped[entry.modelName] = []
            }
            grouped[entry.modelName]!.append(entry)
        }

        for modelName in seen {
            let modelEntries = grouped[modelName]!
            let sourceFormat = modelEntries.first!.sourceFormat
            let ext = sourceFormat.lowercased()

            md += "## \(modelName).\(ext)\n\n"

            // Header row
            let headers = Self.formats.map { f in
                f == sourceFormat ? "\(f) (source)" : f
            }
            md += "| " + headers.joined(separator: " | ") + " |\n"
            md += "|" + String(repeating: ":---:|", count: Self.formats.count) + "\n"

            // Image row
            let imageRow = Self.formats.map { format -> String in
                guard let entry = modelEntries.first(where: { $0.targetFormat == format }) else {
                    return "_(missing)_"
                }
                return imageCell(entry)
            }
            md += "| " + imageRow.joined(separator: " | ") + " |\n"

            // File size row
            let sizeRow = Self.formats.map { format -> String in
                guard let entry = modelEntries.first(where: { $0.targetFormat == format }) else {
                    return "—"
                }
                return formatFileSize(entry.fileSize)
            }
            md += "| " + sizeRow.joined(separator: " | ") + " |\n"

            // Status row
            let statusRow = Self.formats.map { format -> String in
                guard let entry = modelEntries.first(where: { $0.targetFormat == format }) else {
                    return "—"
                }
                return entry.imagePath == nil ? "💥" : (entry.succeeded ? "✅" : "❌")
            }
            md += "| " + statusRow.joined(separator: " | ") + " |\n"

            md += "\n"
        }

        md += "---\n_Last updated: \(dateStr)_\n"
        return md
    }

    private func imageCell(_ entry: ScorecardEntry) -> String {
        guard entry.imagePath != nil else { return "_(no capture)_" }
        let filename = "\(entry.modelName)_\(entry.targetFormat.lowercased())_roundtrip.png"
        let alt = "\(entry.modelName) \(entry.targetFormat)"
        return "![\(alt)](Scorecard/\(filename))"
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1.0 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
}

// MARK: - Platform image helpers
// XCUIScreenshot.image returns UIImage on iOS/Simulator and NSImage on macOS.

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
private extension UIImage {
    /// Crops to a CGRect expressed in the image's logical point coordinate space.
    func cropped(to rect: CGRect) -> UIImage {
        let scaledRect = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
                                width: rect.size.width * scale, height: rect.size.height * scale)
        guard let cg = cgImage?.cropping(to: scaledRect) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    /// Resizes to exactly `size` physical pixels (scale forced to 1).
    func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
private extension NSImage {
    func cropped(to rect: CGRect) -> NSImage {
        guard let srcCG = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let scaleX = CGFloat(srcCG.width) / size.width
        let scaleY = CGFloat(srcCG.height) / size.height
        // NSImage/CGImage use bottom-left origin; flip Y for macOS screenshots
        let flippedY = size.height - rect.maxY
        let pixelRect = CGRect(x: rect.origin.x * scaleX, y: flippedY * scaleY,
                               width: rect.size.width * scaleX, height: rect.size.height * scaleY)
        guard let cropped = srcCG.cropping(to: pixelRect) else { return self }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    func resized(to size: CGSize) -> NSImage {
        guard let srcCG = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info.rawValue) else { return self }
        ctx.interpolationQuality = .high
        ctx.draw(srcCG, in: CGRect(origin: .zero, size: size))
        guard let dstCG = ctx.makeImage() else { return self }
        return NSImage(cgImage: dstCG, size: size)
    }

    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
#endif
