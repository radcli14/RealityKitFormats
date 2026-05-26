import Testing
import Foundation
@preconcurrency import RealityKit
@testable import RealityKitFormats

// Khronos Box sample — a minimal GLB with a single mesh and PBR material.
// Downloaded at test runtime; not committed to the repository.
private let khronosBoxGLBURL = URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Box/glTF-Binary/Box.glb")!

// Apple AR Quick Look teapot — an official Apple USDZ sample with simple geometry and no skeleton.
// Downloaded at test runtime; not committed to the repository.
private let appleTeapotUSDZURL = URL(string: "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz")!

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

// MARK: - Round-Trip Helpers

// Expected mesh specification for the Khronos Box GLB source model.
private let sourceChildrenCount = 1
private let sourceVertexCount = 24
private let sourceIndexCount = 36

/// Mesh statistics extracted from the first ModelEntity found in an entity tree.
private struct MeshSpec {
    let vertexCount: Int
    let indexCount: Int
    var triangleCount: Int { indexCount / 3 }
}

/// Material statistics extracted from the first PhysicallyBasedMaterial found in an entity tree.
private struct MaterialSpec {
    let roughnessScale: Float
    let hasNormalTexture: Bool
}

/// Finds the first ModelComponent anywhere in the entity tree (depth-first).
@MainActor
private func firstModelComponent(in entity: Entity) -> ModelComponent? {
    if let model = entity as? ModelEntity, let comp = model.model { return comp }
    for child in entity.children {
        if let found = firstModelComponent(in: child) { return found }
    }
    return nil
}

@MainActor
private func meshSpec(from entity: Entity) -> MeshSpec? {
    guard let comp = firstModelComponent(in: entity) else { return nil }
    var vertices = 0
    var indices = 0
    for model in comp.mesh.contents.models {
        for part in model.parts {
            vertices += part.positions.count
            indices += part.triangleIndices?.count ?? 0
        }
    }
    return MeshSpec(vertexCount: vertices, indexCount: indices)
}

@MainActor
private func materialSpec(from entity: Entity) -> MaterialSpec? {
    guard let comp = firstModelComponent(in: entity),
          let pbr = comp.materials.first as? PhysicallyBasedMaterial else { return nil }
    return MaterialSpec(
        roughnessScale: pbr.roughness.scale,
        hasNormalTexture: pbr.normal.texture != nil
    )
}

/// Loads the Khronos Box as a Data round-trip to avoid temp-file lifetime issues across async steps.
private func loadBoxEntity() async throws -> Entity {
    let (data, response) = try await URLSession.shared.data(from: khronosBoxGLBURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    return try await Entity.from3DAsset(data: data, format: "glb")
}

/// Downloads the Apple teapot USDZ to a temp file and loads it as an Entity.
/// USDZ requires a file URL for loading (RealityKit has no data-based USDZ path),
/// so a temp file is unavoidable. The file is removed once the entity is in memory.
private func loadTeapotEntity() async throws -> Entity {
    let tempURL = try await downloadToTemp(from: appleTeapotUSDZURL, extension: "usdz")
    let entity = try await Entity.from3DAsset(url: tempURL)
    try? FileManager.default.removeItem(at: tempURL)
    return entity
}

// MARK: - Round-Trip Tests

@Test @MainActor func testRoundTripGLB() async throws {
    let source = try await loadBoxEntity()

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("glb")
    defer { try? FileManager.default.removeItem(at: outURL) }

    // GLB write is not yet supported — expected to throw unsupportedFormat.
    await withKnownIssue("GLB export is not supported") {
        try await source.write3DAsset(to: outURL)
    }
}

@Test @MainActor func testRoundTripUSDZ() async throws {
    let source = try await loadBoxEntity()

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("usdz")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "USDZ file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    #expect(loaded.children.count == sourceChildrenCount)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    let mat = materialSpec(from: loaded)
    #expect(mat?.roughnessScale == 1.0)
    #expect(mat?.hasNormalTexture == false)
}

@Test @MainActor func testRoundTripOBJ() async throws {
    let source = try await loadBoxEntity()

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("obj")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "OBJ file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    #expect(loaded.children.count == sourceChildrenCount)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    let mat = materialSpec(from: loaded)
    #expect(mat?.roughnessScale == 1.0)
    #expect(mat?.hasNormalTexture == false)
}

@Test @MainActor func testRoundTripDAE() async throws {
    let source = try await loadBoxEntity()

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("dae")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "DAE file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    #expect(loaded.children.count == sourceChildrenCount)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    let mat = materialSpec(from: loaded)
    #expect(mat?.roughnessScale == 1.0)
    #expect(mat?.hasNormalTexture == false)
}

@Test @MainActor func testRoundTripSTL() async throws {
    let source = try await loadBoxEntity()

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("stl")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "STL file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    #expect(loaded.children.count == sourceChildrenCount)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    // STL has no material support — material spec will be nil.
    let mat = materialSpec(from: loaded)
    #expect(mat == nil, "STL format does not encode material data")
}

// MARK: - Apple USDZ Round-Trip Tests
//
// These tests load the official Apple AR Quick Look teapot USDZ and export it to
// each of the alternate writable formats, then reload and verify that geometry
// survived the round-trip. Exact vertex/index counts are not asserted because
// different formats (and their loaders) may alter vertex sharing; instead we check
// that the counts are positive and consistent with having received mesh data.

@Test @MainActor func testAppleUSDZLoaderProducesEntity() async throws {
    let entity = try await loadTeapotEntity()
    let spec = meshSpec(from: entity)
    #expect(spec != nil, "Teapot should contain at least one mesh")
    #expect((spec?.vertexCount ?? 0) > 0, "Teapot mesh should have vertices")
    #expect((spec?.indexCount ?? 0) > 0, "Teapot mesh should have triangle indices")
}

@Test @MainActor func testRoundTripAppleUSDZToOBJ() async throws {
    let source = try await loadTeapotEntity()
    let sourceMesh = try #require(meshSpec(from: source), "Source teapot must have geometry")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("obj")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "OBJ file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    let mesh = try #require(meshSpec(from: loaded), "Loaded OBJ should contain geometry")
    #expect(mesh.vertexCount == sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
}

@Test @MainActor func testRoundTripAppleUSDZToSTL() async throws {
    let source = try await loadTeapotEntity()
    let sourceMesh = try #require(meshSpec(from: source), "Source teapot must have geometry")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("stl")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "STL file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    let mesh = try #require(meshSpec(from: loaded), "Loaded STL should contain geometry")
    #expect(mesh.vertexCount == sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)

    // STL encodes no material data.
    #expect(materialSpec(from: loaded) == nil, "STL format does not encode material data")
}

@Test @MainActor func testRoundTripAppleUSDZToPLY() async throws {
    let source = try await loadTeapotEntity()
    let sourceMesh = try #require(meshSpec(from: source), "Source teapot must have geometry")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("ply")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "PLY file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    let mesh = try #require(meshSpec(from: loaded), "Loaded PLY should contain geometry")
    #expect(mesh.vertexCount == sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
}

@Test @MainActor func testRoundTripAppleUSDZToABC() async throws {
    let source = try await loadTeapotEntity()
    let sourceMesh = try #require(meshSpec(from: source), "Source teapot must have geometry")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("abc")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "ABC file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    let mesh = try #require(meshSpec(from: loaded), "Loaded ABC should contain geometry")
    #expect(mesh.vertexCount == sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
}

@Test @MainActor func testRoundTripAppleUSDZToDAE() async throws {
    let source = try await loadTeapotEntity()
    let sourceMesh = try #require(meshSpec(from: source), "Source teapot must have geometry")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("dae")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "DAE file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    let mesh = try #require(meshSpec(from: loaded), "Loaded DAE should contain geometry")
    #expect(mesh.vertexCount == sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
}
