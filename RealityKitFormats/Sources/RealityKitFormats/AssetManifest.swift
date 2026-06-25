import Foundation

/// A catalog of publicly available remote 3D assets that demonstrate RealityKitFormats capabilities.
public struct AssetManifest {
    /// A single remote 3D asset.
    public struct Asset: Sendable, CustomStringConvertible {
        public let name: String
        public let url: URL
        public let format: String

        public var description: String { "\(name) (\(format.uppercased()))" }
    }

    /// Khronos glTF Sample Assets in GLB (binary glTF) format.
    public static let glbAssets: [Asset] = [
        "DamagedHelmet", "ToyCar", "ABeautifulGame", "ChronographWatch", "CarConcept",
    ].compactMap { name in
        URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/\(name)/glTF-Binary/\(name).glb")
            .map { Asset(name: name, url: $0, format: "glb") }
    }

    /// Apple AR Quick Look sample assets in USDZ format.
    public static let usdzAssets: [Asset] = [
        "teapot",
    ].compactMap { name in
        URL(string: "https://developer.apple.com/augmented-reality/quick-look/models/\(name)/\(name).usdz")
            .map { Asset(name: name, url: $0, format: "usdz") }
    }

    /// Khronos glTF Sample Models in COLLADA (DAE) format.
    public static let daeAssets: [Asset] = [
        "GearboxAssy", "Duck",
    ].compactMap { name in
        URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/sourceModels/\(name)/\(name).dae")
            .map { Asset(name: name, url: $0, format: "dae") }
    }

    /// All remote sample assets across all supported formats.
    public static let allAssets: [Asset] = glbAssets + usdzAssets + daeAssets
}
