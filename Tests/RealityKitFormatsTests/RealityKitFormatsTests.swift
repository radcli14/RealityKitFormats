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

@Test func testGLBLoaderProducesEntity() async throws {
    let tempURL = try await downloadToTemp(from: khronosBoxGLBURL, extension: "glb")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = await Entity.fromGLTFAsset(url: tempURL)
    #expect(entity != nil, "Entity.fromGLTFAsset should return a non-nil entity for Box.glb")
}

@Test func testGLBLoaderFromData() async throws {
    let (data, response) = try await URLSession.shared.data(from: khronosBoxGLBURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }

    let entity = await Entity.fromGLTFAsset(data: data, format: "glb")
    #expect(entity != nil, "Entity.fromGLTFAsset(data:format:) should return a non-nil entity for Box.glb data")
}

// MARK: - Unified Loader Tests

@Test func testUnifiedLoaderDispatchesGLB() async throws {
    let tempURL = try await downloadToTemp(from: khronosBoxGLBURL, extension: "glb")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = await Entity.from3DAsset(url: tempURL)
    #expect(entity != nil, "Entity.from3DAsset should dispatch GLB to the GLTF loader and return a non-nil entity")
}

@Test func testUnifiedLoaderRejectsUnsupportedExtension() async {
    let fakeURL = URL(fileURLWithPath: "/tmp/model.xyz")
    let entity = await Entity.from3DAsset(url: fakeURL)
    #expect(entity == nil, "Entity.from3DAsset should return nil for an unsupported file extension")
}
