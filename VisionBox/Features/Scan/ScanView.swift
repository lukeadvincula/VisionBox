//
//  ScanView.swift
//  VisionBox
//

import PhotosUI
import SwiftUI

/// The app's main screen: switches between the scan states and hosts the
/// demo-scene picker, the Photos picker, and Settings.
struct ScanView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: ScanViewModel
    @State private var isShowingSettings: Bool
    @State private var isShowingDemoPicker: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?

    init(dependencies: AppDependencies) {
        self.init(
            viewModel: ScanViewModel(
                demoService: dependencies.demoDetectionService,
                keyStore: dependencies.geminiKeyStore,
                liveService: dependencies.liveDetectionService
            ),
            dependencies: dependencies
        )
    }

    /// Lets previews start from a specific state.
    init(viewModel: ScanViewModel, dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.isShowingSettings = false
        self.isShowingDemoPicker = false
        self.selectedPhotoItem = nil
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .loadingPhoto:
                ProgressView("Loading Photo…")
            case .photoReady(let image):
                photoReadyView(image)
            case .analyzing(let image):
                analyzingView(image)
            case .results(let image, let objects):
                ResultsView(image: image, objects: objects)
            case .error(let message):
                errorView(message)
            }
        }
        .navigationTitle("VisionBox")
        .toolbar {
            if viewModel.canStartOver {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Scan", systemImage: "arrow.counterclockwise") {
                        viewModel.reset()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(dependencies: dependencies)
            }
        }
        .sheet(isPresented: $isShowingDemoPicker) {
            NavigationStack {
                DemoScenePicker { scene in
                    isShowingDemoPicker = false
                    viewModel.analyzeDemoScene(scene)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            viewModel.loadPhoto(newItem)
            // Clear the selection so picking the same photo again still works.
            selectedPhotoItem = nil
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "Detect Objects in Photos",
                systemImage: "viewfinder",
                description: Text("Pick a photo to analyze with your own Gemini API key, or explore the detection experience instantly with Demo Mode — no setup needed.")
            )
            VStack(spacing: 12) {
                Button("Try Demo Mode", systemImage: "sparkles") {
                    isShowingDemoPicker = true
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding()
    }

    private func photoReadyView(_ image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.isLiveAnalysisAvailable {
                    Text("Photo ready to analyze.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        Button("Analyze with Gemini", systemImage: "sparkle.magnifyingglass") {
                            viewModel.analyzePhoto()
                        }
                        .buttonStyle(.borderedProminent)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Choose a Different Photo", systemImage: "photo.on.rectangle")
                        }
                    }
                    .controlSize(.large)
                } else {
                    VStack(spacing: 6) {
                        Text("Gemini API Key Required")
                            .font(.headline)
                        Text("Add your own Gemini API key to analyze personal photos.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button("Set Up Gemini", systemImage: "key") {
                            isShowingSettings = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Try Demo Mode", systemImage: "sparkles") {
                            isShowingDemoPicker = true
                        }
                        .buttonStyle(.bordered)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Choose a Different Photo", systemImage: "photo.on.rectangle")
                        }
                    }
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }

    private func analyzingView(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(0.45)
            ProgressView("Analyzing…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            VStack(spacing: 12) {
                Button("Start Over") {
                    viewModel.reset()
                }
                .buttonStyle(.borderedProminent)

                Button("Try Demo Mode", systemImage: "sparkles") {
                    isShowingDemoPicker = true
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding()
    }
}

// MARK: - Previews
// All previews use in-memory key stores and stub services: no Keychain
// access, no networking, no real keys.

private func previewDependencies(keyConfigured: Bool) -> AppDependencies {
    AppDependencies(geminiKeyStore: GeminiKeyStore(previewKey: keyConfigured ? "preview-key" : nil))
}

private func previewViewModel(
    keyConfigured: Bool,
    state: ScanViewModel.State
) -> ScanViewModel {
    ScanViewModel(
        demoService: DemoDetectionService(),
        keyStore: GeminiKeyStore(previewKey: keyConfigured ? "preview-key" : nil),
        liveService: { _ in DemoDetectionService() },
        state: state
    )
}

#Preview("Idle") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(keyConfigured: false, state: .idle),
            dependencies: previewDependencies(keyConfigured: false)
        )
    }
}

#Preview("Photo ready (no API key)") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: false,
                state: .photoReady(DemoScene.everydayCarry.image ?? UIImage())
            ),
            dependencies: previewDependencies(keyConfigured: false)
        )
    }
}

#Preview("Photo ready (key configured)") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: true,
                state: .photoReady(DemoScene.everydayCarry.image ?? UIImage())
            ),
            dependencies: previewDependencies(keyConfigured: true)
        )
    }
}

#Preview("Analyzing") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: true,
                state: .analyzing(DemoScene.desk.image ?? UIImage())
            ),
            dependencies: previewDependencies(keyConfigured: true)
        )
    }
}

#Preview("Gemini error") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: true,
                state: .error(DetectionError.rateLimited.userMessage)
            ),
            dependencies: previewDependencies(keyConfigured: true)
        )
    }
}
