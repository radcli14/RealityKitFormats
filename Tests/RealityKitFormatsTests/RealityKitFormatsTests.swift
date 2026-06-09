import Testing
import CoreGraphics
import Foundation
import ImageIO
import Metal
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

// MARK: - Texture Helpers

/// Reads raw RGBA8 bytes from a TextureResource via Metal. Returns nil if Metal is unavailable.
@MainActor
private func readTextureBytes(_ resource: TextureResource) -> [UInt8]? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: resource.width, height: resource.height, mipmapped: false)
    desc.usage = .shaderWrite
    desc.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: desc) else { return nil }
    try? resource.copy(to: tex)
    let bpr = 4 * resource.width
    var bytes = [UInt8](repeating: 0, count: resource.height * bpr)
    bytes.withUnsafeMutableBytes { ptr in
        tex.getBytes(ptr.baseAddress!, bytesPerRow: bpr,
                     from: MTLRegion(origin: .init(), size: MTLSize(width: resource.width, height: resource.height, depth: 1)),
                     mipmapLevel: 0)
    }
    return bytes
}

/// Computes the mean value of one RGBA channel (0=R,1=G,2=B,3=A) across all pixels.
private func meanChannel(_ bytes: [UInt8], channel: Int) -> Float {
    var sum: Int = 0
    var i = channel
    while i < bytes.count { sum += Int(bytes[i]); i += 4 }
    let pixelCount = bytes.count / 4
    return pixelCount > 0 ? Float(sum) / Float(pixelCount) : 0
}

// MARK: - PNG Encoding Diagnostic

/// Checks whether CGImage/CGImageDestination alters pixel values during PNG encode.
/// Encodes a known pixel value to PNG and decodes it back, comparing input to output.
/// If this fails, the darkening happens inside makePNG (CGImage color space conversion).
/// If this passes, the darkening happens inside GLTFKit2's texture loading pipeline.
@Test func testPNGRoundTripPreservesValues() throws {
    let inputBytes: [UInt8] = [64, 66, 66, 255]  // RGBA matching the DamagedHelmet base color mean

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let provider = CGDataProvider(data: Data(inputBytes) as CFData),
          let cgImage = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: 4, space: colorSpace,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent) else {
        Issue.record("Failed to create CGImage from input bytes")
        return
    }

    let pngData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil) else {
        Issue.record("Failed to create PNG destination")
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        Issue.record("Failed to finalize PNG")
        return
    }

    // Decode the PNG back into a CGContext and read the pixel
    guard let decodeProvider = CGDataProvider(data: pngData as CFData),
          let decoded = CGImage(pngDataProviderSource: decodeProvider, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent) else {
        Issue.record("Failed to decode PNG")
        return
    }
    var outputBytes = [UInt8](repeating: 0, count: 4)
    outputBytes.withUnsafeMutableBytes { ptr in
        // CGContext requires premultiplied alpha; .last (straight) is only valid for CGImage input.
        // With alpha=255 the values are identical either way.
        guard let ctx = CGContext(data: ptr.baseAddress, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)) else { return }
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    #expect(outputBytes[0] == 64, "R after PNG encode/decode: \(outputBytes[0]) (expected 64) — CGImage is altering values")
    #expect(outputBytes[1] == 66, "G after PNG encode/decode: \(outputBytes[1]) (expected 66)")
    #expect(outputBytes[2] == 66, "B after PNG encode/decode: \(outputBytes[2]) (expected 66)")
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
    let baseColorTint: SIMD3<Float>
    let hasBaseColorTexture: Bool
    let hasNormalTexture: Bool
}

/// Per-part geometry and material-assignment details extracted from the full entity tree.
private struct PartDetailSpec {
    let materialIndex: Int
    let vertexCount: Int
    let uvCount: Int            // 0 if no texture coordinates present
    let firstUV: SIMD2<Float>?  // first vertex UV for V-flip spot-check; nil if no UVs
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

/// Collects per-part material index and UV presence for every mesh part in the entity tree (depth-first).
@MainActor
private func partDetailSpecs(from entity: Entity) -> [PartDetailSpec] {
    var specs: [PartDetailSpec] = []
    func visit(_ e: Entity) {
        if let me = e as? ModelEntity, let model = me.model {
            for rkModel in model.mesh.contents.models {
                for part in rkModel.parts {
                    let uvElements = part.textureCoordinates?.elements
                    specs.append(PartDetailSpec(
                        materialIndex: part.materialIndex,
                        vertexCount: part.positions.count,
                        uvCount: uvElements?.count ?? 0,
                        firstUV: uvElements?.first
                    ))
                }
            }
        }
        for child in e.children { visit(child) }
    }
    visit(entity)
    return specs
}

@MainActor
private func materialSpec(from entity: Entity) -> MaterialSpec? {
    guard let comp = firstModelComponent(in: entity),
          let pbr = comp.materials.first as? PhysicallyBasedMaterial else { return nil }
    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1
    #if os(macOS)
    (pbr.baseColor.tint.usingColorSpace(.sRGB) ?? pbr.baseColor.tint).getRed(&r, green: &g, blue: &b, alpha: nil)
    #else
    pbr.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: nil)
    #endif
    return MaterialSpec(
        roughnessScale: pbr.roughness.scale,
        baseColorTint: SIMD3<Float>(Float(r), Float(g), Float(b)),
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

/// Asserts that the primary (longest) axis of the bounding box is the same between source and loaded.
/// A mismatch means the model was rotated during export — an up-vector or coordinate-system flip.
/// Skips the check when the two largest extents are within 5% of each other (nearly symmetric mesh
/// such as a cube) because float rounding in the round-trip can flip the tie-breaking winner.
@MainActor
private func expectOrientationPreserved(source: Entity, loaded: Entity, label: String = "") throws {
    let src = try #require(boundsSpec(from: source), "Source entity has no geometry for orientation check")
    let ld  = try #require(boundsSpec(from: loaded), "Loaded entity has no geometry for orientation check")
    func primaryAxis(_ ext: SIMD3<Float>) -> Int {
        if ext.y >= ext.x && ext.y >= ext.z { return 1 }
        if ext.x >= ext.y && ext.x >= ext.z { return 0 }
        return 2
    }
    func isAmbiguous(_ ext: SIMD3<Float>) -> Bool {
        let sorted = [ext.x, ext.y, ext.z].sorted(by: >)
        return sorted[0] < 1.05 * sorted[1]
    }
    guard !isAmbiguous(src.extents) else { return }
    let srcAxis = primaryAxis(src.extents)
    let ldAxis  = primaryAxis(ld.extents)
    let names   = ["X", "Y", "Z"]
    let suffix  = label.isEmpty ? "" : " (\(label))"
    #expect(ldAxis == srcAxis,
            "Primary extent axis should match\(suffix): source=\(names[srcAxis]) \(src.extents), loaded=\(names[ldAxis]) \(ld.extents)")
}

/// Collects every UV coordinate from the entire entity tree in depth-first order.
@MainActor
private func allUVCoordinates(from entity: Entity) -> [SIMD2<Float>] {
    var uvs: [SIMD2<Float>] = []
    func visit(_ e: Entity) {
        if let me = e as? ModelEntity, let model = me.model {
            for rkModel in model.mesh.contents.models {
                for part in rkModel.parts {
                    if let partUVs = part.textureCoordinates?.elements {
                        uvs.append(contentsOf: partUVs)
                    }
                }
            }
        }
        for child in e.children { visit(child) }
    }
    visit(entity)
    return uvs
}

/// Samples up to 100 UV coordinates at regular intervals and compares source vs loaded.
/// Detects V-flip, UV region collapse (all vertices mapping to the same texture area),
/// and other systematic UV mapping errors that per-vertex count checks miss.
@MainActor
private func expectUVsPreserved(source: Entity, loaded: Entity, label: String = "") throws {
    let srcUVs = allUVCoordinates(from: source)
    let ldUVs  = allUVCoordinates(from: loaded)
    let suffix = label.isEmpty ? "" : " (\(label))"

    guard !srcUVs.isEmpty else { return }
    #expect(ldUVs.count == srcUVs.count,
            "Total UV count mismatch\(suffix): source=\(srcUVs.count), loaded=\(ldUVs.count)")
    guard ldUVs.count == srcUVs.count else { return }

    let stride = max(1, srcUVs.count / 100)
    var sumU: Float = 0, sumV: Float = 0, n = 0
    var i = 0
    while i < srcUVs.count {
        sumU += abs(ldUVs[i].x - srcUVs[i].x)
        sumV += abs(ldUVs[i].y - srcUVs[i].y)
        n += 1
        i += stride
    }
    let meanUErr = sumU / Float(n)
    let meanVErr = sumV / Float(n)
    #expect(meanUErr < 0.02,
            "Mean absolute U error across \(n) sampled vertices\(suffix): \(meanUErr) — UV mapping error")
    #expect(meanVErr < 0.02,
            "Mean absolute V error across \(n) sampled vertices\(suffix): \(meanVErr) — V-flip or UV mapping error")
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

    let srcParts = partDetailSpecs(from: source)
    let ldParts  = partDetailSpecs(from: loaded)
    #expect(ldParts.count == srcParts.count, "Mesh part count should match after GLB round-trip")
    for (i, (src, ld)) in zip(srcParts, ldParts).enumerated() {
        #expect(ld.materialIndex == src.materialIndex, "Part \(i) material index should survive GLB round-trip")
        if src.uvCount > 0 {
            #expect(ld.uvCount > 0, "Part \(i) texture coordinates should survive GLB round-trip")
            #expect(ld.uvCount == ld.vertexCount, "Part \(i) UV count should equal vertex count")
            if let srcUV = src.firstUV, let ldUV = ld.firstUV {
                #expect(abs(ldUV.y - srcUV.y) < 0.02,
                        "Part \(i) first-vertex V should be preserved (V-flip check): source=\(srcUV.y), loaded=\(ldUV.y)")
            }
        }
    }

    try expectOrientationPreserved(source: source, loaded: loaded, label: "GLB round-trip")
    try expectUVsPreserved(source: source, loaded: loaded, label: "GLB round-trip")
    try expectBoundsPreserved(source: source, loaded: loaded, label: "GLB round-trip")
}

/// Verifies that the base color texture content is preserved through a GLB round-trip.
/// Compares the mean R, G, B pixel values of the source and loaded base color textures.
/// Fails if the wrong image ends up in the base color slot (e.g. the ORM or normal map).
@Test @MainActor func testRoundTripGLBDamagedHelmetBaseColorTexture() async throws {
    let data = try await AssetCache.shared.helmetData()
    let source = try await Entity.from3DAsset(data: data, format: "glb")

    guard let srcComp = firstModelComponent(in: source),
          let srcPBR  = srcComp.materials.first as? PhysicallyBasedMaterial,
          let srcBC   = srcPBR.baseColor.texture?.resource,
          let srcBytes = readTextureBytes(srcBC) else {
        Issue.record("Could not read source base color texture")
        return
    }

    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("glb")
    defer { try? FileManager.default.removeItem(at: outURL) }
    try await source.write3DAsset(to: outURL)
    let loaded = try await Entity.from3DAsset(url: outURL)

    guard let ldComp = firstModelComponent(in: loaded),
          let ldPBR  = ldComp.materials.first as? PhysicallyBasedMaterial,
          let ldBC   = ldPBR.baseColor.texture?.resource,
          let ldBytes = readTextureBytes(ldBC) else {
        Issue.record("Could not read loaded base color texture")
        return
    }

    let srcR = meanChannel(srcBytes, channel: 0)
    let srcG = meanChannel(srcBytes, channel: 1)
    let srcB = meanChannel(srcBytes, channel: 2)
    let ldR  = meanChannel(ldBytes,  channel: 0)
    let ldG  = meanChannel(ldBytes,  channel: 1)
    let ldB  = meanChannel(ldBytes,  channel: 2)

    #expect(abs(ldR - srcR) < 10, "Base color mean R should be preserved: src=\(srcR), loaded=\(ldR)")
    #expect(abs(ldG - srcG) < 10, "Base color mean G should be preserved: src=\(srcG), loaded=\(ldG)")
    #expect(abs(ldB - srcB) < 10, "Base color mean B should be preserved: src=\(srcB), loaded=\(ldB)")
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

    let srcParts = partDetailSpecs(from: source)
    let ldParts  = partDetailSpecs(from: loaded)
    #expect(ldParts.count == srcParts.count, "Mesh part count should match after GLB round-trip")
    for (i, (src, ld)) in zip(srcParts, ldParts).enumerated() {
        #expect(ld.materialIndex == src.materialIndex, "Part \(i) material index should survive GLB round-trip")
        if src.uvCount > 0 {
            #expect(ld.uvCount > 0, "Part \(i) texture coordinates should survive GLB round-trip")
            #expect(ld.uvCount == ld.vertexCount, "Part \(i) UV count should equal vertex count")
            if let srcUV = src.firstUV, let ldUV = ld.firstUV {
                #expect(abs(ldUV.y - srcUV.y) < 0.02,
                        "Part \(i) first-vertex V should be preserved (V-flip check): source=\(srcUV.y), loaded=\(ldUV.y)")
            }
        }
    }

    try expectOrientationPreserved(source: source, loaded: loaded, label: "DamagedHelmet GLB round-trip")
    try expectUVsPreserved(source: source, loaded: loaded, label: "DamagedHelmet GLB round-trip")
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

    let sourceMat = materialSpec(from: source)
    let mat = materialSpec(from: loaded)
    // We write Ns = 2/roughness²−2 and read back roughness = sqrt(2/(Ns+2)), which
    // gives exact round-trip. For source roughness=1.0 → Ns=0 → loaded roughness=1.0.
    #expect(mat?.roughnessScale == 1.0)
    #expect(mat?.hasNormalTexture == false)
    // Kd is now written from baseColorTint and read back via the .diffuse semantic fallback.
    if let src = sourceMat, let ld = mat {
        #expect(abs(ld.baseColorTint.x - src.baseColorTint.x) < 0.05,
                "OBJ round-trip should preserve base color R: src=\(src.baseColorTint.x), loaded=\(ld.baseColorTint.x)")
        #expect(abs(ld.baseColorTint.y - src.baseColorTint.y) < 0.05,
                "OBJ round-trip should preserve base color G: src=\(src.baseColorTint.y), loaded=\(ld.baseColorTint.y)")
        #expect(abs(ld.baseColorTint.z - src.baseColorTint.z) < 0.05,
                "OBJ round-trip should preserve base color B: src=\(src.baseColorTint.z), loaded=\(ld.baseColorTint.z)")
    }

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
