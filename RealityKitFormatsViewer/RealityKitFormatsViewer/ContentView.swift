//
//  ContentView.swift
//  RealityKitFormatsViewer
//
//  Created by Eliott Radcliffe on 5/26/26.
//

import SwiftUI
import RealityKit
import RealityKitFormats

enum Format3D: String, CaseIterable {
    case glb = "GLB"
    case usdz = "USDZ"
    case dae = "DAE"
    case obj = "OBJ"
    case stl = "STL"
}

struct ContentView: View {

    @State private var urlString: String = "\(khronosBaseGLBURL)/\(khronosGLBFiles[0])"
    @State private var targetFormat: Format3D = .glb
    
    var body: some View {
        NavigationStack {
            RealityViewFromRemote(urlString: urlString, targetFormat: targetFormat)
        }
    }
    
    // -MARK: URL Options
    
    /// Base path on which you can find several GLB sample files hosted by Khronos Group
    private static let khronosBaseGLBURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Box/glTF-Binary"

    /// A list of files available on the Khronos Group path
    private static let khronosGLBFiles = ["Box", "DamagedHelmet"]
    
    /// The array of properly formatted URLs derived from the Khronos Group GLB files
    private lazy var khronosGLBURLs: [URL] = {
        Self.khronosGLBFiles.compactMap { file in
            URL(string: "\(Self.khronosBaseGLBURL)/\(file).glb")
        }
    }()

    /// Base path on which you can find several USDZ sample files from Apple
    private static let appleBaseUSDZURL = "https://developer.apple.com/augmented-reality/quick-look/models"
    
    /// A list of files available on the Apple USDZ path
    private static let appleUSDZFiles = ["teapot", ]

    // Apple AR Quick Look teapot — an official Apple USDZ sample with simple geometry and no skeleton.
    // Downloaded at test runtime; not committed to the repository.
    private static let appleTeapotUSDZURL = "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz"

    private lazy var appleUSDZURLs: [URL] = {
        Self.khronosGLBFiles.compactMap { file in
            URL(string: "\(Self.appleBaseUSDZURL)/\(file)/\(file).usdz")
        }
    }()
}

struct RealityViewFromRemote: View {
    let urlString: String
    let targetFormat: Format3D
    
    @State private var url: URL!
    
    var body: some View {
        RealityView { content in
            do {
                url = URL(string: urlString)
                let entity = try await Entity.from3DAsset(url: url)
                content.add(entity)
            } catch {
                print("Failed to load, \(error.localizedDescription)")
            }
        } placeholder: {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                
                Text("Loading 3D Asset...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .realityViewCameraControls(.orbit)
        .navigationTitle(url?.lastPathComponent ?? "")
        .navigationSubtitle(targetFormat.rawValue)
    }
}

#Preview {
    ContentView()
}
