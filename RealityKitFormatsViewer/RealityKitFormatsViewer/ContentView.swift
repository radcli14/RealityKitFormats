//
//  ContentView.swift
//  RealityKitFormatsViewer
//
//  Created by Eliott Radcliffe on 5/26/26.
//

import SwiftUI
import RealityKit
import RealityKitFormats

struct ContentView: View {

    @State private var urlString = khronosHelmetGLBURL
    @State private var targetFormat = "GLB"
    
    var body: some View {
        NavigationStack {
            RealityViewFromRemote(urlString: urlString, targetFormat: targetFormat)
        }
    }
    
    // -MARK: URL Options
    
    // Khronos Box sample — a minimal GLB with a single mesh and PBR material.
    // Downloaded at test runtime; not committed to the repository.
    private static let khronosBoxGLBURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Box/glTF-Binary/Box.glb"

    
    private static let khronosHelmetGLBURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/refs/heads/main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb"
    
    // Apple AR Quick Look teapot — an official Apple USDZ sample with simple geometry and no skeleton.
    // Downloaded at test runtime; not committed to the repository.
    private static let appleTeapotUSDZURL = "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz"

}

struct RealityViewFromRemote: View {
    let urlString: String
    let targetFormat: String
    
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
        .navigationSubtitle(targetFormat)
    }
}

#Preview {
    ContentView()
}
