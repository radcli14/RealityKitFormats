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
        VStack {
            realityView(url: khronosBoxGLBURL, targetFormat: "GLB")
        }
        .realityViewCameraControls(.orbit)
    }
    
    func realityView(url: URL, targetFormat: String) -> some View {
        RealityView { content in
            do {
                let entity = try await Entity.from3DAsset(url: url)
                content.add(entity)
            } catch {
                print("Failed to load, \(error.localizedDescription)")
            }
        }
        .overlay(alignment: .top) {
            VStack {
                Text(url.lastPathComponent).font(.caption)
                Text(targetFormat).font(.headline)
            }
        }
    }
}

#Preview {
    ContentView()
}
