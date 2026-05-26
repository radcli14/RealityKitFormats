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

    // Khronos Box sample — a minimal GLB with a single mesh and PBR material.
    // Downloaded at test runtime; not committed to the repository.
    private let khronosBoxGLBURL = URL(string: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Box/glTF-Binary/Box.glb")!

    var body: some View {
        RealityView { content in
            do {
                let entity = try await Entity.from3DAsset(url: khronosBoxGLBURL)
                content.add(entity)
            } catch {
                print("Failed to load GLTF, \(error.localizedDescription)")
            }
        }
        .overlay(alignment: .top) {
            VStack {
                Text("Box.glb").font(.caption)
                Text("GLB").font(.headline)
            }
        }
        .realityViewCameraControls(.orbit)
    }
}

#Preview {
    ContentView()
}
