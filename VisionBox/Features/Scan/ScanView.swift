//
//  ScanView.swift
//  VisionBox
//

import PhotosUI
import SwiftUI

/// The app's main screen: switches between the scan states and hosts the
/// demo-scene picker, the Photos picker, and Settings.
struct ScanView: View {
    @State private var viewModel: ScanViewModel
    @State private var isShowingSettings: Bool
    @State private var isShowingDemoPicker: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?

    init(dependencies: AppDependencies) {
        self.init(viewModel: ScanViewModel(
            demoService: dependencies.demoDetectionService,
            liveService: dependencies.liveDetectionService
        ))
    }

    /// Lets previews start from a specific state.
    init(viewModel: ScanViewModel) {
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
                SettingsView()
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
                description: Text("Pick a photo from your library, or explore the detection experience instantly with Demo Mode — no API key needed.")
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
        let canAnalyze = viewModel.isLiveAnalysisAvailable
        return ScrollView {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(canAnalyze
                    ? "Photo ready to analyze with Gemini."
                    : "Photo ready. Analyzing your own photos requires a Gemini API key — key setup arrives in Settings next. Try Demo Mode to see detection in action today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button("Analyze", systemImage: "sparkle.magnifyingglass") {
                        viewModel.analyzePhoto()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAnalyze)

                    Button("Try Demo Mode Instead", systemImage: "sparkles") {
                        isShowingDemoPicker = true
                    }
                    .buttonStyle(.bordered)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose a Different Photo", systemImage: "photo.on.rectangle")
                    }
                }
                .controlSize(.large)
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

#Preview("Idle") {
    NavigationStack {
        ScanView(dependencies: AppDependencies())
    }
}

#Preview("Photo ready (no API key)") {
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            demoService: DemoDetectionService(),
            liveService: { nil },
            state: .photoReady(DemoScene.everydayCarry.image ?? UIImage())
        ))
    }
}

#Preview("Photo ready (key configured)") {
    // The demo service stands in for the live one — previews never perform
    // real networking and never need a real API key.
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            demoService: DemoDetectionService(),
            liveService: { DemoDetectionService() },
            state: .photoReady(DemoScene.everydayCarry.image ?? UIImage())
        ))
    }
}

#Preview("Analyzing") {
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            demoService: DemoDetectionService(),
            liveService: { nil },
            state: .analyzing(DemoScene.desk.image ?? UIImage())
        ))
    }
}

#Preview("Gemini error") {
    NavigationStack {
        ScanView(viewModel: ScanViewModel(
            demoService: DemoDetectionService(),
            liveService: { nil },
            state: .error(DetectionError.rateLimited.userMessage)
        ))
    }
}
