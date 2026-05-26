import Testing
import Foundation
@preconcurrency import RealityKit
@testable import RealityKitFormats

// Khronos Box sample — a minimal GLB with a single mesh and PBR material.
// Downloaded at test runtime; not committed to the repository.
private let khronosBoxGLBURL = URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Box/glTF-Binary/Box.glb")!

// MARK: - Helpers

/// Download a file to a temporary path, returning the URL. Caller is responsible for cleanup.
private func downloadToTemp(from remoteURL: URL, extension ext: String) async throws -> URL {
    let (data, response) = try await URLSession.shared.data(from: remoteURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    try data.write(to: tempURL)
    return tempURL
}

// MARK: - GLB Loader Tests

@Test @MainActor func testGLBLoaderProducesEntity() async throws {
    let tempURL = try await downloadToTemp(from: khronosBoxGLBURL, extension: "glb")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = try await Entity.fromGLTFAsset(url: tempURL)
    #expect(entity.children.count == 1)
}

@Test @MainActor func testGLBLoaderFromData() async throws {
    let (data, response) = try await URLSession.shared.data(from: khronosBoxGLBURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }

    let entity = try await Entity.fromGLTFAsset(data: data, format: "glb")
    #expect(entity.children.count == 1)
}

// MARK: - Unified Loader Tests

@Test @MainActor func testUnifiedLoaderDispatchesGLB() async throws {
    let tempURL = try await downloadToTemp(from: khronosBoxGLBURL, extension: "glb")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = try await Entity.from3DAsset(url: tempURL)
    #expect(entity.children.count == 1)
}

@Test @MainActor func testUnifiedLoaderDispatchesGLBFromData() async throws {
    let (data, response) = try await URLSession.shared.data(from: khronosBoxGLBURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }

    let entity = try await Entity.from3DAsset(data: data, format: "glb")
    #expect(entity.children.count == 1)
}

@Test func testUnifiedLoaderRejectsUnsupportedExtension() async throws {
    let fakeURL = URL(fileURLWithPath: "/tmp/model.xyz")
    await #expect(throws: RealityKitFormatsError.unsupportedFormat("xyz")) {
        _ = try await Entity.from3DAsset(url: fakeURL)
    }
}

@Test func testUnifiedLoaderDataRejectsUnsupportedFormat() async throws {
    await #expect(throws: RealityKitFormatsError.unsupportedFormat("xyz")) {
        _ = try await Entity.from3DAsset(data: Data(), format: "xyz")
    }
}
