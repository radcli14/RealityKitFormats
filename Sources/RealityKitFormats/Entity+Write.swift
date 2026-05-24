//
//  Entity+Write.swift
//  RealityKitFormats
//

import Foundation
import RealityKit

// MARK: - Error Type

/// Errors thrown by ``Entity/write(to:)``.
public enum RealityKitFormatsWriteError: Error, LocalizedError {
    /// The file extension is not supported for writing.
    case unsupportedFormat(String)
    /// The format is recognised but the write path has not been implemented yet in an upstream package.
    case notImplemented(String)
    /// Mesh data could not be extracted from the entity tree.
    case meshExtractionFailed
    /// The underlying export call reported failure.
    case exportFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "RealityKitFormats: no writer registered for '\(ext)' format"
        case .notImplemented(let detail):
            return "RealityKitFormats: \(detail)"
        case .meshExtractionFailed:
            return "RealityKitFormats: failed to extract mesh data from the entity tree"
        case .exportFailed(let url):
            return "RealityKitFormats: export to \(url.lastPathComponent) failed"
        }
    }
}

// MARK: - Unified Writer

public extension Entity {
    /// Write this entity to a local file URL. The output format is inferred from the URL's path extension.
    ///
    /// Supported extensions: `stl`, `obj`, `ply`, `abc`, `dae`, `glb`, `gltf`.
    ///
    /// ```swift
    /// try await entity.write(to: documentsURL.appendingPathComponent("model.obj"))
    /// ```
    ///
    /// - Parameter url: Destination file URL. The directory must already exist.
    /// - Throws: ``RealityKitFormatsWriteError`` on failure.
    @MainActor
    func write(to url: URL) async throws {
        switch url.pathExtension.lowercased() {
        case "stl", "obj", "ply", "abc":
            try await writeMDLAsset(to: url)
        case "dae":
            try await writeDAEAsset(to: url)
        case "glb", "gltf":
            try await writeGLTFAsset(to: url)
        default:
            throw RealityKitFormatsWriteError.unsupportedFormat(url.pathExtension)
        }
    }
}

// MARK: - Format-Specific Stubs

private extension Entity {

    // MARK: ModelIO formats (STL, OBJ, PLY, ABC)
    //
    // ─────────────────────────────────────────────────────────────────────────
    // TODO — implement in radcli14/ModelIO-to-RealityKit
    //
    // Suggested new file: Sources/ModelIO-to-RealityKit/Entity+Write.swift
    //
    // Pattern to follow (mirroring Entity+Extensions.swift in the same repo):
    //
    //   import Foundation
    //   import ModelIO
    //   import RealityKit
    //
    //   public extension Entity {
    //       @MainActor
    //       func writeMDLAsset(to url: URL) async throws {
    //           // 1. Collect every ModelEntity leaf in the tree.
    //           let modelEntities = collectModelEntities()   // see step 6
    //           guard !modelEntities.isEmpty else {
    //               throw RealityKitFormatsWriteError.meshExtractionFailed
    //           }
    //
    //           // 2. Build one MDLMesh per MeshResource.Part and accumulate into an MDLAsset.
    //           let asset = MDLAsset()
    //           for modelEntity in modelEntities {
    //               guard let model = modelEntity.model else { continue }
    //               for rkModel in model.mesh.contents.models {
    //                   for part in rkModel.parts {
    //                       // a. Extract typed buffers.
    //                       let positions = Array(part.positions)            // [SIMD3<Float>]
    //                       let normals   = part.normals.map { Array($0) }  // [SIMD3<Float>]?
    //                       let uvs       = part.textureCoordinates.map { Array($0) } // [SIMD2<Float>]?
    //                       let indices   = part.triangleIndices.map { Array($0) }    // [UInt32]?
    //
    //                       // b. Build an interleaved vertex layout: position(12) + normal(12) + uv(8).
    //                       let vertexDescriptor = MDLVertexDescriptor()
    //                       vertexDescriptor.attributes[0] = MDLVertexAttribute(
    //                           name: MDLVertexAttributePosition,
    //                           format: .float3, offset: 0, bufferIndex: 0)
    //                       vertexDescriptor.attributes[1] = MDLVertexAttribute(
    //                           name: MDLVertexAttributeNormal,
    //                           format: .float3, offset: 12, bufferIndex: 0)
    //                       vertexDescriptor.attributes[2] = MDLVertexAttribute(
    //                           name: MDLVertexAttributeTextureCoordinate,
    //                           format: .float2, offset: 24, bufferIndex: 0)
    //                       vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
    //
    //                       // c. Pack interleaved vertex data into Data.
    //                       var vertexData = Data(capacity: positions.count * 32)
    //                       for i in positions.indices {
    //                           vertexData.append(contentsOf: positions[i].bytes)
    //                           vertexData.append(contentsOf: (normals?[i] ?? .zero).bytes)
    //                           vertexData.append(contentsOf: (uvs?[i] ?? .zero).bytes)
    //                       }
    //
    //                       // d. Build index buffer (UInt32).
    //                       var indexData = Data()
    //                       if let idx = indices {
    //                           indexData = Data(bytes: idx, count: idx.count * 4)
    //                       }
    //
    //                       // e. Allocate MDLMeshBufferData and construct MDLMesh + submesh.
    //                       let bufferAllocator = MDLMeshBufferDataAllocator()
    //                       let vertexBuffer = bufferAllocator.newBuffer(with: vertexData, type: .vertex)
    //                       let indexBuffer  = bufferAllocator.newBuffer(with: indexData, type: .index)
    //                       let submesh = MDLSubmesh(indexBuffer: indexBuffer,
    //                                                indexCount: indices?.count ?? 0,
    //                                                indexType: .uInt32,
    //                                                geometryType: .triangles,
    //                                                material: nil)
    //                       let mdlMesh = MDLMesh(vertexBuffer: vertexBuffer,
    //                                             vertexCount: positions.count,
    //                                             descriptor: vertexDescriptor,
    //                                             submeshes: [submesh])
    //                       asset.add(mdlMesh)
    //                   }
    //               }
    //           }
    //
    //           // 3. Export. MDLAsset.export(to:) infers the format from the URL extension
    //           //    and handles STL, OBJ, PLY, and ABC natively.
    //           guard asset.export(to: url) else {
    //               throw RealityKitFormatsWriteError.exportFailed(url)
    //           }
    //       }
    //
    //       // 6. Helper — depth-first ModelEntity collector.
    //       private func collectModelEntities() -> [ModelEntity] {
    //           var result = [ModelEntity]()
    //           if let me = self as? ModelEntity { result.append(me) }
    //           for child in children { result += child.collectModelEntities() }
    //           return result
    //       }
    //   }
    //
    //   // SIMD byte helpers (can go in a private extension in the same file)
    //   private extension SIMD3 where Scalar == Float {
    //       var bytes: [UInt8] { withUnsafeBytes(of: self) { Array($0) } }
    //   }
    //   private extension SIMD2 where Scalar == Float {
    //       var bytes: [UInt8] { withUnsafeBytes(of: self) { Array($0) } }
    //   }
    //
    // Once that method is public, replace the stub body below with:
    //   try await (self as Entity).writeMDLAsset(to: url)
    // and remove this comment block.
    // ─────────────────────────────────────────────────────────────────────────
    @MainActor
    func writeMDLAsset(to url: URL) async throws {
        throw RealityKitFormatsWriteError.notImplemented(
            "MDL write (STL/OBJ/PLY/ABC) is not yet implemented. " +
            "See the TODO in Entity+Write.swift for the full implementation to add " +
            "to radcli14/ModelIO-to-RealityKit."
        )
    }

    // MARK: DAE / COLLADA
    //
    // ─────────────────────────────────────────────────────────────────────────
    // TODO — implement in radcli14/DAE-to-RealityKit
    //
    // Suggested new file: Sources/DAE-to-RealityKit/RealityKit/Entity+Write.swift
    //
    // The package already depends on XMLCoder and defines Codable Collada structs,
    // so encoding is straightforward once the Collada tree is built.
    //
    //   import Foundation
    //   import RealityKit
    //   import XMLCoder
    //
    //   public extension Entity {
    //       @MainActor
    //       func writeDAEAsset(to url: URL) async throws {
    //           var geometries  = [Collada.Geometry]()
    //           var sceneNodes  = [Collada.VisualScene.Node]()
    //           var geoIndex    = 0
    //
    //           // Walk the entity tree depth-first.
    //           func visit(_ entity: Entity, parentTransform: simd_float4x4 = .init(1)) {
    //               let localTransform = entity.transform.matrix
    //
    //               if let me = entity as? ModelEntity, let model = me.model {
    //                   for rkModel in model.mesh.contents.models {
    //                       for part in rkModel.parts {
    //                           let geoId = "geometry-\(geoIndex)"
    //                           geoIndex += 1
    //
    //                           // Build <source> for positions.
    //                           let positions = Array(part.positions)
    //                           let posFloats = positions.flatMap { [$0.x, $0.y, $0.z] }
    //                           let posSource = Collada.Geometry.Mesh.Source(
    //                               id: "\(geoId)-positions",
    //                               floatArray: Collada.FloatArray(id: "\(geoId)-positions-array",
    //                                                              count: posFloats.count,
    //                                                              values: posFloats),
    //                               technique: .positions(count: positions.count))
    //
    //                           // Build <source> for normals (if present).
    //                           var normalSource: Collada.Geometry.Mesh.Source? = nil
    //                           if let normals = part.normals.map({ Array($0) }) {
    //                               let nrmFloats = normals.flatMap { [$0.x, $0.y, $0.z] }
    //                               normalSource = Collada.Geometry.Mesh.Source(
    //                                   id: "\(geoId)-normals",
    //                                   floatArray: Collada.FloatArray(id: "\(geoId)-normals-array",
    //                                                                  count: nrmFloats.count,
    //                                                                  values: nrmFloats),
    //                                   technique: .normals(count: normals.count))
    //                           }
    //
    //                           // Build <source> for UVs (if present).
    //                           var uvSource: Collada.Geometry.Mesh.Source? = nil
    //                           if let uvs = part.textureCoordinates.map({ Array($0) }) {
    //                               let uvFloats = uvs.flatMap { [$0.x, $0.y] }
    //                               uvSource = Collada.Geometry.Mesh.Source(
    //                                   id: "\(geoId)-map",
    //                                   floatArray: Collada.FloatArray(id: "\(geoId)-map-array",
    //                                                                  count: uvFloats.count,
    //                                                                  values: uvFloats),
    //                                   technique: .texcoord(count: uvs.count))
    //                           }
    //
    //                           // Build <triangles>.
    //                           let indices = part.triangleIndices.map { Array($0) } ?? []
    //                           // COLLADA triangles interleave vertex/normal/uv indices on one <p>.
    //                           let hasNormals = normalSource != nil
    //                           let hasUVs     = uvSource != nil
    //                           let stride = 1 + (hasNormals ? 1 : 0) + (hasUVs ? 1 : 0)
    //                           var pValues = [Int]()
    //                           for idx in indices {
    //                               pValues.append(Int(idx))        // VERTEX
    //                               if hasNormals { pValues.append(Int(idx)) } // NORMAL (same index)
    //                               if hasUVs     { pValues.append(Int(idx)) } // TEXCOORD (same index)
    //                           }
    //                           var sources = [posSource]
    //                           if let n = normalSource { sources.append(n) }
    //                           if let u = uvSource     { sources.append(u) }
    //                           let triangles = Collada.Geometry.Mesh.Triangles(
    //                               count: indices.count / 3,
    //                               p: pValues)
    //
    //                           let mesh = Collada.Geometry.Mesh(
    //                               sources: sources,
    //                               vertices: Collada.Geometry.Mesh.Vertices(
    //                                   id: "\(geoId)-vertices",
    //                                   input: .init(semantic: "POSITION", source: "#\(geoId)-positions")),
    //                               triangles: [triangles],
    //                               polylist: nil)
    //                           geometries.append(Collada.Geometry(geometryId: geoId,
    //                                                              name: entity.name.isEmpty ? geoId : entity.name,
    //                                                              mesh: mesh))
    //
    //                           // Build scene node with local transform and geometry instance.
    //                           let t = localTransform
    //                           sceneNodes.append(Collada.VisualScene.Node(
    //                               id: "node-\(geoId)",
    //                               name: entity.name,
    //                               matrix: [t[0][0],t[1][0],t[2][0],t[3][0],
    //                                        t[0][1],t[1][1],t[2][1],t[3][1],
    //                                        t[0][2],t[1][2],t[2][2],t[3][2],
    //                                        t[0][3],t[1][3],t[2][3],t[3][3]],
    //                               instanceGeometry: .init(url: "#\(geoId)")))
    //                       }
    //                   }
    //               }
    //               for child in entity.children { visit(child) }
    //           }
    //           visit(self)
    //
    //           guard !geometries.isEmpty else {
    //               throw RealityKitFormatsWriteError.meshExtractionFailed
    //           }
    //
    //           let collada = Collada(
    //               version: "1.4.1",
    //               asset: Collada.Asset(upAxis: "Y_UP"),
    //               libraryImages: nil,
    //               libraryEffects: nil,
    //               libraryMaterials: nil,
    //               libraryGeometries: Collada.LibraryGeometries(geometries: geometries),
    //               libraryVisualScenes: Collada.LibraryVisualScenes(
    //                   visualScenes: [Collada.VisualScene(id: "Scene", name: "Scene", nodes: sceneNodes)]),
    //               scene: Collada.Scene(instanceVisualScene: .init(url: "#Scene")))
    //
    //           let encoder = XMLEncoder()
    //           encoder.outputFormatting = .prettyPrinted
    //           let data = try encoder.encode(collada, withRootKey: "COLLADA",
    //                                         rootAttributes: ["xmlns": "http://www.collada.org/2005/11/COLLADASchema",
    //                                                           "version": "1.4.1"])
    //           try data.write(to: url)
    //       }
    //   }
    //
    // Note: the Collada sub-types (Source, Vertices, Triangles, VisualScene, Node, etc.) may need
    // Encodable conformances and CodingKeys added if they currently only implement Decodable.
    // Check Geometries.swift, VisualScenes.swift, and Transforms.swift in DAE-to-RealityKit.
    //
    // Once that method is public, replace the stub body below with:
    //   try await (self as Entity).writeDAEAsset(to: url)
    // ─────────────────────────────────────────────────────────────────────────
    @MainActor
    func writeDAEAsset(to url: URL) async throws {
        throw RealityKitFormatsWriteError.notImplemented(
            "DAE write is not yet implemented. " +
            "See the TODO in Entity+Write.swift for the full implementation to add " +
            "to radcli14/DAE-to-RealityKit."
        )
    }

    // MARK: GLB / GLTF
    //
    // ─────────────────────────────────────────────────────────────────────────
    // TODO — implement once GLTFKit2 export API stabilises
    //
    // GLTFKit2's README notes export as WIP (https://github.com/warrenm/GLTFKit2).
    // When the API is ready, the implementation should:
    //
    //   1. Build a GLTFDocument / GLTFAsset from the Entity tree:
    //      - For each ModelEntity leaf: create GLTFMesh with one GLTFMeshPrimitive per
    //        MeshResource.Part. Populate POSITION / NORMAL / TEXCOORD_0 accessors from
    //        part.positions, part.normals, part.textureCoordinates, and INDICES from
    //        part.triangleIndices. Store binary buffer data in a GLTFBuffer.
    //      - For each PhysicallyBasedMaterial: map base color, metallic, roughness, normal,
    //        emissive, and occlusion to GLTFMaterial (KHR_materials_pbrMetallicRoughness).
    //      - For entity transforms: create GLTFNode with translation/rotation/scale (or matrix),
    //        mirroring the node hierarchy of the Entity tree.
    //      - Wrap everything in a GLTFScene and set it as the asset's defaultScene.
    //
    //   2. Export:
    //      - GLB (.glb):  GLTFKit2 should provide a GLTFBinaryWriter or similar that
    //        packs the JSON + BIN chunk into a single file.
    //      - GLTF (.gltf): write the JSON manifest; external buffer .bin file written
    //        alongside (or embed as base-64 data URIs).
    //
    //   3. Error handling: map any GLTFKit2 export errors to
    //      RealityKitFormatsWriteError.exportFailed(url).
    //
    // Once GLTFKit2 exposes a stable exporter, replace the stub body below with the
    // actual GLTFRealityKitExporter call (or equivalent).
    // ─────────────────────────────────────────────────────────────────────────
    @MainActor
    func writeGLTFAsset(to url: URL) async throws {
        throw RealityKitFormatsWriteError.notImplemented(
            "GLB/GLTF write is not yet available: GLTFKit2 export is currently WIP. " +
            "See the TODO in Entity+Write.swift for the implementation plan."
        )
    }
}
