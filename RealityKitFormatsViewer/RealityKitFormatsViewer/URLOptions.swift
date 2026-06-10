//
//  URLOptions.swift
//  RealityKitFormatsViewer
//

import Foundation

enum Format3D: String, CaseIterable {
    case glb = "GLB"
    case usdz = "USDZ"
    case dae = "DAE"
    case obj = "OBJ"
    case stl = "STL"
}

enum URLOptions {
    static let allURLs: [URL] = khronosGLBURLs + appleUSDZURLs + khronosDAEURLs + localURLs

    static let localURLs: [URL] = [
        Bundle.main.url(forResource: "left_hand", withExtension: "usdz")
    ].compactMap { $0 }

    private static let khronosBaseGLBURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models"
    private static let khronosGLBFiles = ["DamagedHelmet", "ToyCar", "ABeautifulGame", "ChronographWatch", "CarConcept"]
    static let khronosGLBURLs: [URL] = khronosGLBFiles.compactMap { file in
        URL(string: "\(khronosBaseGLBURL)/\(file)/glTF-Binary/\(file).glb")
    }

    private static let appleBaseUSDZURL = "https://developer.apple.com/augmented-reality/quick-look/models"
    private static let appleUSDZFiles = ["teapot"]
    static let appleUSDZURLs: [URL] = appleUSDZFiles.compactMap { file in
        URL(string: "\(appleBaseUSDZURL)/\(file)/\(file).usdz")
    }

    private static let khronosBaseDAEURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/sourceModels"
    private static let khronosDAEFiles = ["GearboxAssy", "Duck"]
    static let khronosDAEURLs: [URL] = khronosDAEFiles.compactMap { file in
        URL(string: "\(khronosBaseDAEURL)/\(file)/\(file).dae")
    }
}
