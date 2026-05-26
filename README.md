# RealityKitFormats

Swift package providing RealityKit entity loaders for STL, OBJ, DAE, and GLB/GLTF formats, extending Apple's native USDZ support for use in robotics and AR applications.

## Supported Formats

| Extension | Format | Loader |
|-----------|--------|--------|
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
.package(url: "https://github.com/radcli14/RealityKitFormats", from: "0.1.0")
```

Then add `RealityKitFormats` to your target dependencies.

## Usage

### Unified loader (recommended)

`Entity.from3DAsset(url:)` dispatches automatically based on the file extension:

```swift
import RealityKitFormats

let entity = try await Entity.from3DAsset(url: url)
```

`ModelEntity` is a subclass of `Entity`, so cast the result if you need it:

```swift
let model = try await Entity.from3DAsset(url: url) as? ModelEntity
```

If the file is stored as `Data` (e.g. retrieved from SwiftData) rather than on disk, use the data overload and pass the format extension explicitly:

```swift
let entity = try await Entity.from3DAsset(data: data, format: "glb")
```

Both methods throw `RealityKitFormatsError.unsupportedFormat` for unrecognised extensions, or a loader-specific error if loading fails.

### Format-specific loaders

Each format also has its own static loader if you want to call it directly:

```swift
// STL, OBJ, PLY, ABC
let entity = try await ModelEntity.fromMDLAsset(url: url)

// DAE / COLLADA
let entity = try await ModelEntity.fromDAEAsset(url: url)

// GLB / GLTF
let entity = try await Entity.fromGLTFAsset(url: url)
```

All loaders are `async` and run on the `@MainActor`. They throw on failure rather than returning `nil`.

## Acknowledgements

RealityKitFormats aggregates three upstream packages:

- **[ModelIO-to-RealityKit](https://github.com/radcli14/ModelIO-to-RealityKit)** by Eliott Radcliffe — STL, OBJ, PLY, and ABC loading via Apple's ModelIO framework
- **[DAE-to-RealityKit](https://github.com/radcli14/DAE-to-RealityKit)** by Eliott Radcliffe — COLLADA DAE loading via a custom XML parser backed by [XMLCoder](https://github.com/MaxDesiatov/XMLCoder)
- **[GLTFKit2](https://github.com/warrenm/GLTFKit2)** by Warren Moore — glTF 2.0 / GLB loading with full PBR material, animation, and scene hierarchy support

## License

MIT — see [LICENSE](LICENSE) for details.
