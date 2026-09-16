//
//  ScanView.swift
//  VisionBox
//

import PhotosUI
import SwiftUI

/// The app's main screen: switches between the scan states and hosts the
/// camera, the Photos picker, the demo-scene picker, and Settings.
struct ScanView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: ScanViewModel
    @State private var isShowingSettings: Bool
    @State private var isShowingDemoPicker: Bool
    @State private var isShowingPhotosPicker: Bool
    @State private var isShowingCamera: Bool
    @State private var isShowingCameraDeniedAlert: Bool
    @State private var isShowingCameraUnavailableAlert: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?

    @Environment(\.openURL) private var openURL

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
        self.isShowingPhotosPicker = false
        self.isShowingCamera = false
        self.isShowingCameraDeniedAlert = false
        self.isShowingCameraUnavailableAlert = false
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
            case .error(let message, let image):
                errorView(message, image: image)
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
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { capturedImage in
                isShowingCamera = false
                // nil means the user cancelled — the previous state stays.
                if let capturedImage {
                    viewModel.setCapturedImage(capturedImage)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isShowingPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            viewModel.loadPhoto(newItem)
            // Clear the selection so picking the same photo again still works.
            selectedPhotoItem = nil
        }
        .alert("Camera Access Needed", isPresented: $isShowingCameraDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable camera access in Settings to take photos with VisionBox. You can still choose an existing photo or use Demo Mode.")
        }
        .alert("Camera Unavailable", isPresented: $isShowingCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Camera capture isn't available on this device. You can choose a photo instead.")
        }
    }

    /// Take Photo flow: hardware and permission are checked only here — never
    /// at launch, and never for Photos or Demo Mode.
    private func takePhoto() {
        switch CameraAccess.readiness {
        case .ready:
            isShowingCamera = true
        case .needsPermission:
            Task {
                if await CameraAccess.requestAccess() {
                    isShowingCamera = true
                } else {
                    isShowingCameraDeniedAlert = true
                }
            }
        case .denied:
            isShowingCameraDeniedAlert = true
        case .unavailable:
            isShowingCameraUnavailableAlert = true
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "Detect Objects in Photos",
                systemImage: "viewfinder",
                description: Text("Take or pick a photo to analyze with your own Gemini API key, or explore the detection experience instantly with Demo Mode — no setup needed.")
            )
            VStack(spacing: 12) {
                Button("Take Photo", systemImage: "camera") {
                    takePhoto()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isShowingPhotosPicker = true
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Button("Try Demo Mode", systemImage: "sparkles") {
                    isShowingDemoPicker = true
                }
                .buttonStyle(.bordered)
                .padding(.top, 12)
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

                        changePhotoButton
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

                        changePhotoButton
                    }
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }

    /// One replacement action covering both image sources.
    private var changePhotoButton: some View {
        Menu {
            Button("Take Photo", systemImage: "camera") {
                takePhoto()
            }
            Button("Choose from Photos", systemImage: "photo.on.rectangle") {
                isShowingPhotosPicker = true
            }
        } label: {
            Label("Change Photo", systemImage: "photo.on.rectangle.angled")
        }
        .accessibilityHint("Take a new photo or choose one from your library")
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

    /// When the failure interrupted a personal-photo analysis, the photo is
    /// retained and Try Again re-runs it — no re-picking after a transient
    /// API failure. Demo Mode stays an explicit option; it is never an
    /// automatic fallback.
    @ViewBuilder
    private func errorView(_ message: String, image: UIImage?) -> some View {
        if let image {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(0.7)

                    VStack(spacing: 6) {
                        Label("Analysis Failed", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            viewModel.retryAnalysis()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Analyzes the same photo again")

                        changePhotoButton

                        Button("Try Demo Mode", systemImage: "sparkles") {
                            isShowingDemoPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                .padding()
            }
        } else {
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
}

// MARK: - Previews
// All previews use in-memory key stores and stub services: no Keychain
// access, no networking, no real keys, no camera presentation or permission
// prompts (the camera path only runs from an explicit Take Photo tap).

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

#Preview("Gemini error (photo retained)") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: true,
                state: .error(
                    message: DetectionError.rateLimited.userMessage,
                    image: DemoScene.everydayCarry.image ?? UIImage()
                )
            ),
            dependencies: previewDependencies(keyConfigured: true)
        )
    }
}

#Preview("Photo load error") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(
                keyConfigured: false,
                state: .error(
                    message: "That photo couldn't be loaded. Try choosing a different one.",
                    image: nil
                )
            ),
            dependencies: previewDependencies(keyConfigured: false)
        )
    }
}
