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

// Khronos Damaged Helmet — a GLB with a single mesh and full image-based PBR materials
// (base color, normal, metallic-roughness, emissive, occlusion). Downloaded at test runtime.
private let khronosDamagedHelmetGLBURL = URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/refs/heads/main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb")!

// MARK: - Asset Cache

/// Downloads each remote test asset exactly once per process, regardless of how many tests
/// request it concurrently. Each asset is backed by a single `Task`; latecomers `await` the
/// already-running task rather than starting a new download.
private actor AssetCache {
    static let shared = AssetCache()
    private init() {}

    private var glbTask: Task<Data, any Error>?
    private var usdzTask: Task<Data, any Error>?
    private var helmetTask: Task<Data, any Error>?

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

    /// Returns the raw bytes of the Khronos Damaged Helmet GLB. Downloaded at most once per process.
    func helmetData() async throws -> Data {
        if helmetTask == nil {
            helmetTask = Task {
                let (data, response) = try await URLSession.shared.data(from: khronosDamagedHelmetGLBURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }
        return try await helmetTask!.value
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

// MARK: - PBR Material Tests

@Test @MainActor func testDamagedHelmetMaterialsLoaded() async throws {
    let data = try await AssetCache.shared.helmetData()
    let entity = try await Entity.from3DAsset(data: data, format: "glb")

    let mesh = try #require(meshSpec(from: entity), "Helmet should contain geometry")
    #expect(mesh.vertexCount > 0)
    #expect(mesh.indexCount > 0)

    let mat = try #require(materialSpec(from: entity), "Helmet should have a PhysicallyBasedMaterial")
    #expect(mat.hasBaseColorTexture, "Helmet albedo texture should be loaded")
    #expect(mat.hasNormalTexture, "Helmet normal map should be loaded")
}

@Test @MainActor func testRoundTripDamagedHelmetToUSDZ() async throws {
    let data = try await AssetCache.shared.helmetData()
    let source = try await Entity.from3DAsset(data: data, format: "glb")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("usdz")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "USDZ file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    let sourceMesh = try #require(meshSpec(from: source), "Source should have geometry")
    let loadedMesh = try #require(meshSpec(from: loaded), "Reloaded USDZ should have geometry")
    #expect(loadedMesh.vertexCount == sourceMesh.vertexCount)
    #expect(loadedMesh.indexCount == sourceMesh.indexCount)

    let sourceMat = try #require(materialSpec(from: source), "Source should have a PBR material")
    let loadedMat = try #require(materialSpec(from: loaded), "Reloaded USDZ should have a PBR material")

    #expect(loadedMat.hasBaseColorTexture == sourceMat.hasBaseColorTexture,
            "Base color texture assignment should survive USDZ round-trip")
    #expect(loadedMat.hasNormalTexture == sourceMat.hasNormalTexture,
            "Normal map assignment should survive USDZ round-trip")

    try expectBoundsPreserved(source: source, loaded: loaded, label: "DamagedHelmet USDZ round-trip")
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

@Test @MainActor func testUnifiedLoaderDispatchesUSDZ() async throws {
    let entity = try await Entity.from3DAsset(url: appleTeapotUSDZURL)
    let spec = meshSpec(from: entity)
    #expect(spec != nil, "Loaded USDZ should contain at least one mesh")
    #expect((spec?.vertexCount ?? 0) > 0)
    #expect((spec?.indexCount ?? 0) > 0)
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

/// Mesh statistics extracted from the first ModelEntity found in an entity tree.
private struct MeshSpec {
    let vertexCount: Int
    let indexCount: Int
    var triangleCount: Int { indexCount / 3 }
}

/// Material statistics extracted from the first PhysicallyBasedMaterial found in an entity tree.
private struct MaterialSpec {
    let roughnessScale: Float
    let hasBaseColorTexture: Bool
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
        hasBaseColorTexture: pbr.baseColor.texture != nil,
        hasNormalTexture: pbr.normal.texture != nil
    )
}

/// World-space axis-aligned bounding box computed from mesh vertex positions.
private struct BoundsSpec {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    var extents: SIMD3<Float> { max - min }
    var diagonalLength: Float { simd_length(extents) }
}

/// Computes the world-space AABB for an entity tree by transforming every vertex
/// by the entity's world transform. Returns nil if no mesh data is found.
@MainActor
private func boundsSpec(from entity: Entity) -> BoundsSpec? {
    var lo = SIMD3<Float>(repeating: Float.infinity)
    var hi = SIMD3<Float>(repeating: -Float.infinity)
    func visit(_ e: Entity) {
        if let me = e as? ModelEntity, let model = me.model {
            let wt = me.transformMatrix(relativeTo: nil)
            for rkModel in model.mesh.contents.models {
                for part in rkModel.parts {
                    for pos in part.positions {
                        let wp = wt * SIMD4<Float>(pos.x, pos.y, pos.z, 1)
                        lo.x = Swift.min(lo.x, wp.x); hi.x = Swift.max(hi.x, wp.x)
                        lo.y = Swift.min(lo.y, wp.y); hi.y = Swift.max(hi.y, wp.y)
                        lo.z = Swift.min(lo.z, wp.z); hi.z = Swift.max(hi.z, wp.z)
                    }
                }
            }
        }
        for child in e.children { visit(child) }
    }
    visit(entity)
    guard lo.x < Float.infinity else { return nil }
    return BoundsSpec(min: lo, max: hi)
}

/// Asserts that the bounding box diagonal of `loaded` matches `source` within a 1% relative tolerance.
@MainActor
private func expectBoundsPreserved(source: Entity, loaded: Entity, label: String = "") throws {
    let src = try #require(boundsSpec(from: source), "Source entity has no geometry for bounds check")
    let ld  = try #require(boundsSpec(from: loaded), "Loaded entity has no geometry for bounds check")
    let ref = src.diagonalLength
    let suffix = label.isEmpty ? "" : " (\(label))"
    #expect(abs(ld.diagonalLength - ref) <= 0.01 * ref,
            "Bounding box scale not preserved within 1%\(suffix): source diagonal \(ref), loaded \(ld.diagonalLength)")
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

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "GLB file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)
    #expect(loaded.children.count == sourceChildrenCountHierarchy)

    let mesh = meshSpec(from: loaded)
    #expect(mesh?.vertexCount == sourceVertexCount)
    #expect(mesh?.indexCount  == sourceIndexCount)

    let mat = materialSpec(from: loaded)
    #expect(mat?.roughnessScale == 1.0)
    #expect(mat?.hasNormalTexture == false)

    try expectBoundsPreserved(source: source, loaded: loaded, label: "GLB round-trip")
}

@Test @MainActor func testRoundTripGLBDamagedHelmet() async throws {
    let data = try await AssetCache.shared.helmetData()
    let source = try await Entity.from3DAsset(data: data, format: "glb")

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("glb")
    defer { try? FileManager.default.removeItem(at: outURL) }

    try await source.write3DAsset(to: outURL)
    #expect(FileManager.default.fileExists(atPath: outURL.path), "GLB file should exist after write")

    let loaded = try await Entity.from3DAsset(url: outURL)

    let srcMesh = try #require(meshSpec(from: source), "Source helmet should have geometry")
    let ldMesh  = try #require(meshSpec(from: loaded), "Re-loaded helmet should have geometry")
    #expect(ldMesh.vertexCount == srcMesh.vertexCount)
    #expect(ldMesh.indexCount  == srcMesh.indexCount)

    let srcMat = try #require(materialSpec(from: source), "Source should have a PBR material")
    let ldMat  = try #require(materialSpec(from: loaded),  "Re-loaded should have a PBR material")
    #expect(ldMat.hasBaseColorTexture == srcMat.hasBaseColorTexture,
            "Base color texture should survive GLB round-trip")
    #expect(ldMat.hasNormalTexture    == srcMat.hasNormalTexture,
            "Normal map should survive GLB round-trip")

    try expectBoundsPreserved(source: source, loaded: loaded, label: "DamagedHelmet GLB round-trip")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "USDZ round-trip")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "OBJ round-trip")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "DAE round-trip")
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
    // Triangle count is the invariant for STL; vertex sharing is a loader implementation detail.
    #expect((mesh?.vertexCount ?? 0) > 0)
    #expect(mesh?.indexCount == sourceIndexCount)

    // STL has no material encoding; ModelIO supplies a default PBR material on load.
    // We don't assert on material values here — they carry no round-trip meaning.

    try expectBoundsPreserved(source: source, loaded: loaded, label: "STL round-trip")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "Teapot→OBJ")
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
    // Triangle count is the invariant for STL; vertex sharing is a loader implementation detail.
    #expect(mesh.vertexCount > 0)
    #expect(mesh.indexCount == sourceMesh.indexCount)
    // STL has no material encoding; ModelIO supplies a default PBR material on load.

    try expectBoundsPreserved(source: source, loaded: loaded, label: "Teapot→STL")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "Teapot→PLY")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "Teapot→ABC")
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

    try expectBoundsPreserved(source: source, loaded: loaded, label: "Teapot→DAE")
}

// MARK: - RealityKit Asset Archive Tests

/// Writes GLB bytes to a temp file and returns the URL. Caller must clean up.
private func makeGLBTempURLForArchive() async throws -> URL {
    let data = try await AssetCache.shared.glbData()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("glb")
    try data.write(to: url)
    return url
}

@Test @MainActor func testArchiveRoundTripGLB() async throws {
    let glbURL = try await makeGLBTempURLForArchive()
    defer { try? FileManager.default.removeItem(at: glbURL) }

    let archive = try await Entity.archiveAsset(url: glbURL)
    #expect(!archive.isEmpty, "Archive data should not be empty")

    let loaded = try await Entity.from3DAsset(archive: archive)
    let mesh = try #require(meshSpec(from: loaded), "Loaded entity should contain geometry")
    #expect(mesh.vertexCount == sourceVertexCount)
    #expect(mesh.indexCount == sourceIndexCount)
}

@Test @MainActor func testArchiveManifestContents() async throws {
    let glbURL = try await makeGLBTempURLForArchive()
    defer { try? FileManager.default.removeItem(at: glbURL) }

    let archive = try await Entity.archiveAsset(url: glbURL)
    let manifest = try rkaManifest(from: archive)

    #expect(manifest.version == 1)
    #expect(manifest.format == "glb")
    #expect(manifest.entryPoint == glbURL.lastPathComponent)
    // GLB is self-contained — archive contains manifest.json + the GLB file only.
    #expect(manifest.files.count == 2)
    #expect(manifest.files.contains("manifest.json"))
    #expect(manifest.files.contains(glbURL.lastPathComponent))
}

@Test @MainActor func testRKADistinctFromUSDZ() async throws {
    let usdzData = try await AssetCache.shared.usdzData()
    #expect(!isRKAArchive(usdzData), "Plain USDZ data should not be identified as an RKA archive")

    let glbURL = try await makeGLBTempURLForArchive()
    defer { try? FileManager.default.removeItem(at: glbURL) }
    let archive = try await Entity.archiveAsset(url: glbURL)
    #expect(isRKAArchive(archive), "GLB archive should be identified as an RKA archive")
}

@Test @MainActor func testArchiveRoundTripUSDZ() async throws {
    // Write the teapot USDZ data to a temp file so archiveAsset has a local URL to work with.
    let usdzData = try await AssetCache.shared.usdzData()
    let usdzURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("usdz")
    try usdzData.write(to: usdzURL)
    defer { try? FileManager.default.removeItem(at: usdzURL) }

    let archive = try await Entity.archiveAsset(url: usdzURL)
    let manifest = try rkaManifest(from: archive)
    #expect(manifest.format == "usdz")
    #expect(manifest.files.count == 2)

    let loaded = try await Entity.from3DAsset(archive: archive)
    let mesh = try #require(meshSpec(from: loaded), "Loaded entity should contain geometry")
    #expect(mesh.vertexCount > 0)
    #expect(mesh.indexCount > 0)
}

@Test @MainActor func testArchiveRoundTripDAE() async throws {
    // Write Box GLB → DAE, then archive and reload the DAE.
    let source = try await loadBoxEntity()
    let daeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("dae")
    defer { try? FileManager.default.removeItem(at: daeURL) }

    try await source.write3DAsset(to: daeURL)

    let archive = try await Entity.archiveAsset(url: daeURL)
    let manifest = try rkaManifest(from: archive)
    #expect(manifest.format == "dae")

    let loaded = try await Entity.from3DAsset(archive: archive)
    let mesh = try #require(meshSpec(from: loaded), "Loaded entity should contain geometry")
    #expect(mesh.vertexCount == sourceVertexCount)
    #expect(mesh.indexCount == sourceIndexCount)

    try expectBoundsPreserved(source: source, loaded: loaded, label: "DAE archive round-trip")
}
