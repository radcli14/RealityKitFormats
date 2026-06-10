//
//  ScreenshotTests.swift
//  RealityKitFormatsViewerUITests
//
//  Iterates every remote URL × target format combination, launches the app with
//  launch-environment overrides, waits for the 3D asset to finish loading, and
//  saves a 256×256 PNG of the RealityView to both an XCTAttachment (visible in
//  Xcode's test report) and ~/Documents/RealityKitFormatsScreenshots/ on the host.
//

import XCTest

final class ScreenshotTests: XCTestCase {

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

    // MARK: - Output directory

    private static let screenshotDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/RealityKitFormatsScreenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Tests

    /// Generates one 256×256 PNG per (URL, format) pair in direct (non-round-trip) mode.
    func testDirectLoadScreenshots() {
        for url in Self.remoteURLs {
            for format in Self.formats {
                captureScreenshot(url: url, format: format, forceConversion: false)
            }
        }
    }

    /// Generates one 256×256 PNG per URL in round-trip mode, using the URL's native format.
    func testRoundTripScreenshots() {
        for url in Self.remoteURLs {
            let nativeFormat = url.pathExtension.uppercased()
            captureScreenshot(url: url, format: nativeFormat, forceConversion: true)
        }
    }

    // MARK: - Helpers

    private func captureScreenshot(url: URL, format: String, forceConversion: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_URL"] = url.absoluteString
        app.launchEnvironment["UITEST_FORMAT"] = format
        app.launchEnvironment["UITEST_FORCE_CONVERSION"] = forceConversion ? "true" : "false"
        app.launch()

        waitForLoadingToFinish(in: app)

        let element = realityViewElement(in: app)
        let raw = element.screenshot().image
        let thumbnail = raw.resized(to: CGSize(width: 256, height: 256))

        let modelName = url.deletingPathExtension().lastPathComponent
        let mode = forceConversion ? "roundtrip" : "direct"
        let filename = "\(modelName)_\(format.lowercased())_\(mode).png"

        if let data = thumbnail.pngData() {
            saveAttachment(data: data, filename: filename)
            saveToDisk(data: data, filename: filename)
        }

        app.terminate()
    }

    private func waitForLoadingToFinish(in app: XCUIApplication) {
        let spinner = app.activityIndicators.firstMatch
        guard spinner.waitForExistence(timeout: 10) else { return }
        let gone = NSPredicate(format: "exists == false")
        let expectation = expectation(for: gone, evaluatedWith: spinner)
        wait(for: [expectation], timeout: 60)
        // Allow RealityKit one extra render pass after the loading closure completes
        Thread.sleep(forTimeInterval: 2.0)
    }

    private func realityViewElement(in app: XCUIApplication) -> XCUIElement {
        let element = app.otherElements["realityView"]
        return element.waitForExistence(timeout: 5) ? element : app
    }

    private func saveAttachment(data: Data, filename: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func saveToDisk(data: Data, filename: String) {
        let fileURL = Self.screenshotDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)
    }
}

// MARK: - UIImage resize

private extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
