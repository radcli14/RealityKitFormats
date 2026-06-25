//
//  ContentView.swift
//  RealityKitFormatsViewer
//

import SwiftUI
import RealityKit
import RealityKitFormats

struct ContentView: View {

    @State private var url: URL = Self.testURL ?? URLOptions.allURLs.first!
    @State private var targetFormat: Format3D = Self.testFormat ?? .glb
    @State private var forceConversion: Bool = ProcessInfo.processInfo.environment["UITEST_FORCE_CONVERSION"] == "true"

    @State private var showFilePicker = false
    @State private var showFormatPicker = false

    var body: some View {
        if Self.hideChrome {
            // Screenshot mode: render RealityViewFromRemote at exactly 256×256, like a preview,
            // so the screenshot is device-independent.
            ZStack {
                Color.black.ignoresSafeArea()
                RealityViewFromRemote(url: url, targetFormat: targetFormat, forceConversion: forceConversion)
                    .frame(width: 256, height: 256)
            }
        } else {
            NavigationStack {
                RealityViewFromRemote(url: url, targetFormat: targetFormat, forceConversion: forceConversion)
                    .id(url.absoluteString + targetFormat.rawValue + (forceConversion ? "1" : "0"))
                    .toolbar {
                        ToolbarItemGroup {
                            Menu {
                                Picker("Select Model", selection: $url) {
                                    ForEach(URLOptions.allURLs, id: \.self) { assetURL in
                                        Text(assetURL.lastPathComponent).tag(assetURL)
                                    }
                                }
                            } label: {
                                Label("Select Model", systemImage: "cube.transparent")
                            }
                        }
                        ToolbarItemGroup(placement: topBarPlacement) {
                            Menu {
                                Picker("Target Format", selection: $targetFormat) {
                                    ForEach(Format3D.allCases, id: \.self) { format in
                                        Text(format.rawValue).tag(format)
                                    }
                                }
                            } label: {
                                Label(targetFormat.rawValue, systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        ToolbarItemGroup(placement: bottomBarPlacement) {
                            Picker("Load Mode", selection: $forceConversion) {
                                Text("Direct").tag(false)
                                Text("Round-trip").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
            }
        }
    }

    private var topBarPlacement: ToolbarItemPlacement {
#if os(iOS)
        .topBarTrailing
#else
        .automatic
#endif
    }

    private var bottomBarPlacement: ToolbarItemPlacement {
#if os(iOS)
        .bottomBar
#else
        .automatic
#endif
    }

    private static var hideChrome: Bool {
        ProcessInfo.processInfo.environment["UITEST_HIDE_CHROME"] == "true"
    }

    private static var testURL: URL? {
        guard let str = ProcessInfo.processInfo.environment["UITEST_URL"] else { return nil }
        return URL(string: str)
    }

    private static var testFormat: Format3D? {
        guard let str = ProcessInfo.processInfo.environment["UITEST_FORMAT"] else { return nil }
        return Format3D(rawValue: str)
    }
}

struct RealityViewFromRemote: View {
    let url: URL
    let targetFormat: Format3D
    let forceConversion: Bool

    @State private var camera = PerspectiveCamera()
    @State private var error: (any Error)?
    @State private var loadState: LoadState = .loading

    var body: some View {
        RealityView { content in
            do {
                var entity = try await Entity.from3DAsset(url: url)

                let ext = targetFormat.rawValue.lowercased()
                if ext != url.pathExtension || forceConversion {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("TempAsset.\(ext)")
                    try await entity.write3DAsset(to: tempURL)
                    let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                    await MainActor.run { self.loadState = .ready(fileSize: size) }
                    entity = try await Entity.from3DAsset(url: tempURL)
                } else {
                    await MainActor.run { self.loadState = .ready(fileSize: 0) }
                }

                entity.sanitizeCameraComponents()

                let bounds = entity.visualBounds(relativeTo: nil)
                entity.position = -bounds.center

                camera.position = 1.57 * bounds.extents
                camera.look(at: .zero, from: bounds.extents, relativeTo: nil)

                content.add(entity)
                content.add(camera)
            } catch {
                self.error = error
                await MainActor.run { self.loadState = .error }
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
#if os(iOS)
        .navigationSubtitle(subtitle)
#endif
        .edgesIgnoringSafeArea(.all)
        .accessibilityIdentifier("realityView")
        .accessibilityValue(loadState.accessibilityString)
    }

    private var subtitle: String {
        let ext = targetFormat.rawValue.lowercased()
        if ext != url.pathExtension { return "Converted to \(targetFormat.rawValue)" }
        if forceConversion { return "Round-tripped as \(targetFormat.rawValue)" }
        return "Original"
    }
}

private enum LoadState {
    case loading
    case ready(fileSize: Int64)
    case error

    var accessibilityString: String {
        switch self {
        case .loading:           return "loading"
        case .ready(let size):   return "ready:\(size)"
        case .error:             return "error"
        }
    }
}

extension Entity {
    func sanitizeCameraComponents() {
        if self.components.has(PerspectiveCameraComponent.self) {
            self.components.remove(PerspectiveCameraComponent.self)
        }
        for child in children {
            child.sanitizeCameraComponents()
        }
    }
}

#Preview {
    ContentView()
}
