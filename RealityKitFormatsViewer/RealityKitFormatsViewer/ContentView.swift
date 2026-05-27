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

    @State private var url = Self.khronosGLBURLs.first!
    @State private var targetFormat: Format3D = .glb
    
    @State private var showFilePicker = false
    @State private var showFormatPicker = false
    
    var body: some View {
        NavigationStack {
            RealityViewFromRemote(url: url, targetFormat: targetFormat)
                .id(url)
                .toolbar {
                    ToolbarItemGroup {
                        Menu {
                            Picker("Select Model", selection: $url) {
                                ForEach(Self.allURLs, id: \.self) { assetURL in
                                    Text(assetURL.lastPathComponent).tag(assetURL)
                                }
                            }
                        } label: {
                            Label("Select Model", systemImage: "cube.transparent")
                        }
                    }
                }
        }

    }
    
    // -MARK: URL Options
    
    private static let allURLs: [URL] = khronosGLBURLs + appleUSDZURLs + khronosDAEURLs
    
    /// Base path on which you can find several GLB sample files hosted by Khronos Group
    private static let khronosBaseGLBURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/"

    /// A list of files available on the Khronos Group path
    private static let khronosGLBFiles = ["DamagedHelmet", "ToyCar", "ABeautifulGame", "ChronographWatch", "CarConcept"]
    
    /// The array of properly formatted URLs derived from the Khronos Group GLB files
    private static let khronosGLBURLs: [URL] = Self.khronosGLBFiles.compactMap { file in
        URL(string: "\(Self.khronosBaseGLBURL)/\(file)/glTF-Binary/\(file).glb")
    }

    /// Base path on which you can find several USDZ sample files from Apple
    private static let appleBaseUSDZURL = "https://developer.apple.com/augmented-reality/quick-look/models"
    
    /// A list of files available on the Apple USDZ path
    private static let appleUSDZFiles = ["teapot", ]

    /// The array of properly formatted URLs derived from the Khronos Group GLB files
    private static let appleUSDZURLs: [URL] = Self.appleUSDZFiles.compactMap { file in
        URL(string: "\(Self.appleBaseUSDZURL)/\(file)/\(file).usdz")
    }
    
    private static let khronosBaseDAEURL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/sourceModels"

    // https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/sourceModels/GearboxAssy/GearboxAssy.dae
    
    private static let khronosDAEFiles = ["GearboxAssy", "Duck"]

    private static let khronosDAEURLs: [URL] = Self.khronosDAEFiles.compactMap { file in
        URL(string: "\(Self.khronosBaseDAEURL)/\(file)/\(file).dae")
    }
}

struct RealityViewFromRemote: View {
    let url: URL
    let targetFormat: Format3D
    
    @State private var camera = PerspectiveCamera()
    @State private var error: (any Error)?
    
    var body: some View {
        RealityView { content in
            do {
                let entity = try await Entity.from3DAsset(url: url)
            
                // Sanitize the entire assembly tree, preserving all sub-parts
                entity.sanitizeCameraComponents()
                
                // Re-center the assembly, and add it to the content
                let bounds = entity.visualBounds(relativeTo: nil)
                entity.position = -bounds.center
                
                // Position the camera dynamically based on the full assembly size
                camera.position = 1.57 * bounds.extents
                camera.look(at: .zero, from: bounds.extents, relativeTo: nil)
                
                // Add the assembly and camera to the content
                content.add(entity)
                content.add(camera)
            } catch {
                self.error = error
                print("Failed to load \(url), \(error.localizedDescription)")
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
        .overlay {
            if let error {
                ContentUnavailableView("An Error Occurred", systemImage: "exclamationmark.3", description: Text(error.localizedDescription))
            }
        }
        .realityViewCameraControls(.orbit)
        .navigationTitle(url.lastPathComponent)
        //.navigationSubtitle(targetFormat.rawValue)
        .edgesIgnoringSafeArea(.all)
    }
}

extension Entity {
    
    /// The ToyCar.glb model and others have camera components that block orbit camera gestures, this removes them recursively.
    func sanitizeCameraComponents() {
        // Strip the blocking camera components
        if self.components.has(PerspectiveCameraComponent.self) {
            self.components.remove(PerspectiveCameraComponent.self)
        }
        // Recursively subtract from all children down the assembly tree
        for child in children {
            child.sanitizeCameraComponents()
        }
    }
}

#Preview {
    ContentView()
}
