# RealityKitFormats

Swift package providing RealityKit entity loaders for STL, OBJ, DAE, GLB/GLTF, and USDZ formats, for use in robotics and AR applications.

## Supported Formats

| Extension | Format | Loader |
|-----------|--------|--------|
| `.usdz` `.usd` `.usdc` `.usda` | Universal Scene Description | RealityKit (native) |
| `.stl` | Stereolithography | ModelIO |
| `.obj` | Wavefront OBJ | ModelIO |
| `.ply` | Polygon File Format | ModelIO |
| `.abc` | Alembic | ModelIO |
| `.dae` | COLLADA | Custom COLLADA parser |
| `.glb` | Binary glTF 2.0 | GLTFKit2 |
| `.gltf` | JSON glTF 2.0 | GLTFKit2 |

## Requirements

- iOS 18+ / macOS 15+
- Swift 6.0+

## Installation

Add the package via Swift Package Manager:

```swift
.package(url: "https://github.com/radcli14/RealityKitFormats", from: "0.5.2")
```

Then add `RealityKitFormats` to your target dependencies.

## Usage

### Loading from a URL

`Entity.from3DAsset(url:)` dispatches automatically based on the file extension. Both local `file://` URLs and remote `http(s)://` URLs are accepted:

```swift
import RealityKitFormats

// Local file
let entity = try await Entity.from3DAsset(url: localURL)

// Remote file — downloaded transparently
let entity = try await Entity.from3DAsset(url: URL(string: "https://example.com/model.usdz")!)
```

`ModelEntity` is a subclass of `Entity`, so cast the result if you need it:

```swift
let model = try await Entity.from3DAsset(url: url) as? ModelEntity
```

### Remote URL handling

Remote URLs are handled per format to preserve external asset references:

- **DAE** — the URL is passed directly to the COLLADA parser, which resolves texture image URLs relative to the remote base path.
- **GLTF** (text) — the URL is passed directly to GLTFKit2.
- **OBJ** — the `.obj`, its `.mtl` sidecar, and all referenced textures are downloaded into a temporary directory so that ModelIO can resolve relative paths correctly.
- **USDZ, GLB, STL, PLY, ABC** — self-contained or geometry-only formats are downloaded to a single temporary file.

### Loading from Data

If the file is stored as `Data` (e.g. retrieved from SwiftData), use the data overload and pass the format extension explicitly:

```swift
let entity = try await Entity.from3DAsset(data: data, format: "glb")
```

On iOS 26+ / macOS 26+, USDZ/USD loading from `Data` uses RealityKit's native `Entity(from:)` API. On earlier OS versions it falls back to a temporary file.

### Writing to a file

`write3DAsset(to:)` serializes an entity's mesh data to a local file URL. The format is determined by the destination file extension:

```swift
try await entity.write3DAsset(to: outputURL)
```

Supported output formats:

| Extension | Serializer |
|-----------|------------|
| `.stl` `.obj` `.ply` `.abc` `.usdz` `.usd` | ModelIO |
| `.dae` | COLLADA serializer |

### Format-specific loaders

Each format also exposes its own static loader if you want to call it directly:

```swift
// STL, OBJ, PLY, ABC
let entity = try await ModelEntity.fromMDLAsset(url: url)

// DAE / COLLADA
let entity = try await ModelEntity.fromDAEAsset(url: url)

// GLB / GLTF
let entity = try await Entity.fromGLTFAsset(url: url)
```

All loaders are `async` and run on the `@MainActor`. They throw on failure rather than returning `nil`. `RealityKitFormatsError.unsupportedFormat` is thrown for unrecognised file extensions.

## Acknowledgements

RealityKitFormats aggregates three upstream packages:

- **[ModelIO-to-RealityKit](https://github.com/radcli14/ModelIO-to-RealityKit)** by Eliott Radcliffe — STL, OBJ, PLY, and ABC loading and writing via Apple's ModelIO framework
- **[DAE-to-RealityKit](https://github.com/radcli14/DAE-to-RealityKit)** by Eliott Radcliffe — COLLADA DAE loading and writing via a custom XML parser backed by [XMLCoder](https://github.com/MaxDesiatov/XMLCoder)
- **[GLTFKit2](https://github.com/warrenm/GLTFKit2)** by Warren Moore — glTF 2.0 / GLB loading with full PBR material, animation, and scene hierarchy support

## License

MIT — see [LICENSE](LICENSE) for details.
