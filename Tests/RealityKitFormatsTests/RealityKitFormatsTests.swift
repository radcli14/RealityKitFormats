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

// MARK: - Asset Cache

/// Downloads each remote test asset exactly once per process, regardless of how many tests
/// request it concurrently. Each asset is backed by a single `Task`; latecomers `await` the
/// already-running task rather than starting a new download.
private actor AssetCache {
    static let shared = AssetCache()
    private init() {}

    private var glbTask: Task<Data, any Error>?
    private var usdzTask: Task<Data, any Error>?

    /// Returns the raw bytes of the Khronos Box GLB. Downloaded at most once per process.
    func glbData() async throws -> Data {
        if glbTask == nil {
            glbTask = Task {
                let (data, response) = try await URLSession.shared.data(from: khronosBoxGLBURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }
        return try await glbTask!.value
    }

    /// Returns the raw bytes of the Apple teapot USDZ. Downloaded at most once per process.
    func usdzData() async throws -> Data {
        if usdzTask == nil {
            usdzTask = Task {
                let (data, response) = try await URLSession.shared.data(from: appleTeapotUSDZURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }
        return try await usdzTask!.value
    }
}

/// Writes the cached GLB bytes to a fresh temp file. Caller is responsible for cleanup.
/// Use this when a test specifically needs a file URL (e.g. to exercise `fromGLTFAsset(url:)`).
private func makeGLBTempURL() async throws -> URL {
    let data = try await AssetCache.shared.glbData()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("glb")
    try data.write(to: url)
    return url
}

// MARK: - GLB Loader Tests

@Test @MainActor func testGLBLoaderProducesEntity() async throws {
    let tempURL = try await makeGLBTempURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = try await Entity.fromGLTFAsset(url: tempURL)
    #expect(entity.children.count == 1)
}

@Test @MainActor func testGLBLoaderFromData() async throws {
    let data = try await AssetCache.shared.glbData()
    let entity = try await Entity.fromGLTFAsset(data: data, format: "glb")
    #expect(entity.children.count == 1)
}

// MARK: - Unified Loader Tests

@Test @MainActor func testUnifiedLoaderDispatchesGLB() async throws {
    let tempURL = try await makeGLBTempURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let entity = try await Entity.from3DAsset(url: tempURL)
    #expect(entity.children.count == 1)
}

@Test @MainActor func testUnifiedLoaderDispatchesGLBFromData() async throws {
    let data = try await AssetCache.shared.glbData()
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
// Hierarchy-preserving formats (GLB, USDZ, DAE) return root → Node1 → mesh, so children = 1.
// Flat formats (OBJ, STL) return a single ModelEntity directly, so children = 0.
private let sourceChildrenCountHierarchy = 1
private let sourceChildrenCountFlat = 0
private let sourceVertexCount = 24
private let sourceIndexCount = 36
// STL does not share vertices across triangles, so vertex count = triangles × 3 = 36.
private let stlVertexCount = 36

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

/// Returns a Khronos Box entity loaded from the cached GLB bytes.
private func loadBoxEntity() async throws -> Entity {
    let data = try await AssetCache.shared.glbData()
    return try await Entity.from3DAsset(data: data, format: "glb")
}

/// Returns an Apple teapot entity loaded from the cached USDZ bytes.
private func loadTeapotEntity() async throws -> Entity {
    let data = try await AssetCache.shared.usdzData()
    return try await Entity.from3DAsset(data: data, format: "usdz")
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

    #expect(loaded.children.count == sourceChildrenCountHierarchy)

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

    // OBJ is a flat format — the loader returns a single ModelEntity with no children.
    #expect(loaded.children.count == sourceChildrenCountFlat)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    let mat = materialSpec(from: loaded)
    // OBJ/MTL uses Phong shading, not PBR. Roughness survives as an approximation
    // via the Phong specular exponent (Ns) conversion — exact 1.0 is not preserved.
    #expect(mat?.roughnessScale == 0.9)
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

    #expect(loaded.children.count == sourceChildrenCountHierarchy)

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

    // STL is a flat format — the loader returns a single ModelEntity with no children.
    #expect(loaded.children.count == sourceChildrenCountFlat)

    let mesh = meshSpec(from: loaded)
    // STL does not share vertices across triangles, so vertex count is higher than the source.
    #expect(mesh?.vertexCount == stlVertexCount)
    #expect(mesh?.indexCount == sourceIndexCount)

    // STL has no material encoding; ModelIO supplies a default PBR material on load.
    // We don't assert on material values here — they carry no round-trip meaning.
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
    // STL creates one vertex per triangle corner (no sharing), so vertex count = index count.
    #expect(mesh.vertexCount == sourceMesh.indexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
    // STL has no material encoding; ModelIO supplies a default PBR material on load.
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
    // ABC may introduce vertex duplication at attribute seams; triangle count is the invariant.
    #expect(mesh.vertexCount >= sourceMesh.vertexCount)
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
    // DAE may introduce vertex duplication at attribute seams; triangle count is the invariant.
    #expect(mesh.vertexCount >= sourceMesh.vertexCount)
    #expect(mesh.indexCount == sourceMesh.indexCount)
}
