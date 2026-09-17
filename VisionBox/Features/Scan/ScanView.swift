//
//  ScanView.swift
//  VisionBox
//

import PhotosUI
import SwiftUI

/// The app's main screen. In its idle state it is camera-first: the live
/// rear-camera preview fills the background with the scan chrome overlaid —
/// VisionBox top-left, Settings top-right, the Generic/Detailed selector
/// above the bottom row, and Demo / shutter / Photos along the bottom
/// (icons only; meanings come from accessibility labels, never printed
/// captions). All other states (photo ready, analyzing, results, errors)
/// keep their existing presentations.
struct ScanView: View {
    private let dependencies: AppDependencies
    @State private var camera: CameraSession
    @State private var viewModel: ScanViewModel
    @State private var isShowingSettings: Bool
    @State private var isShowingDemoPicker: Bool
    @State private var isShowingPhotosPicker: Bool
    @State private var isShowingScanIntro: Bool
    @State private var isDemoPillExpanded: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies) {
        self.init(
            viewModel: ScanViewModel(
                demoService: dependencies.demoDetectionService,
                keyStore: dependencies.geminiKeyStore,
                settings: dependencies.detectionSettings,
                liveService: { dependencies.liveDetectionService(apiKey: $0, detail: $1) }
            ),
            dependencies: dependencies,
            camera: CameraSession()
        )
    }

    /// Lets previews start from specific analysis/camera states.
    init(viewModel: ScanViewModel, dependencies: AppDependencies, camera: CameraSession) {
        self.dependencies = dependencies
        self.camera = camera
        self.viewModel = viewModel
        self.isShowingSettings = false
        self.isShowingDemoPicker = false
        self.isShowingPhotosPicker = false
        self.isShowingScanIntro = false
        self.isDemoPillExpanded = false
        self.selectedPhotoItem = nil
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                cameraScreen
            case .loadingPhoto:
                ProgressView("Loading Photo…")
            case .photoReady(let image):
                photoReadyView(image)
            case .analyzing(let image):
                analyzingView(image)
            case .results(let image, let objects):
                ResultsView(image: image, objects: objects)
            case .error(let message, let image):
                errorView(message, retainedImage: image)
            }
        }
        // The camera-first idle screen draws its own chrome; the navigation
        // bar (and its title) exists only in the non-idle states.
        .navigationTitle(viewModel.canStartOver ? "VisionBox" : "")
        .toolbar(viewModel.canStartOver ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if viewModel.canStartOver {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Scan", systemImage: "arrow.counterclockwise") {
                        viewModel.reset()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
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
        .photosPicker(isPresented: $isShowingPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            viewModel.loadPhoto(newItem)
            // Clear the selection so picking the same photo again still works.
            selectedPhotoItem = nil
        }
    }

    // MARK: - Camera-first idle screen

    private var cameraScreen: some View {
        ZStack {
            cameraBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if camera.state == .denied {
                    cameraDeniedCard
                        .padding(.top, 24)
                }

                if isShowingScanIntro {
                    scanIntroCard
                        .padding(.top, 24)
                        .transition(.opacity)
                }

                Spacer()

                detailSelector
                    .padding(.bottom, 20)

                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .task {
            await camera.start()
        }
        .task {
            await runFirstUseHints()
        }
        .onDisappear {
            camera.stop()
        }
    }

    @ViewBuilder
    private var cameraBackground: some View {
        if camera.state == .running {
            if camera.isPreviewInstance {
                // Previews stand in for the live feed without AVFoundation.
                LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                CameraPreview(session: camera)
            }
        } else {
            ZStack {
                Color.black
                if camera.state == .unavailable {
                    Label("Camera unavailable", systemImage: "video.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Camera unavailable. You can choose a photo or try Demo Mode.")
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("VisionBox")
                .font(.title3.bold())
                .fixedSize()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    /// One-time "what is this screen" card; fades on its own and never
    /// blocks the controls.
    private var scanIntroCard: some View {
        VStack(spacing: 6) {
            Text("Detect Objects with VisionBox")
                .font(.headline)
            Text("Point your camera at objects and tap Scan, or choose a photo. Choose Detailed to identify brands and models when visible.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 360)
        .accessibilityElement(children: .combine)
    }

    /// Integrated denied state — no alert loop; the rest of the screen
    /// (Photos, Demo, Settings, mode selector) stays fully usable.
    private var cameraDeniedCard: some View {
        VStack(spacing: 10) {
            Label("Camera Access Needed", systemImage: "video.slash")
                .font(.headline)
            Text("Enable camera access in Settings to scan with the camera. You can still choose a photo or use Demo Mode.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 360)
    }

    private var detailSelector: some View {
        Picker("Detection Detail", selection: Bindable(dependencies.detectionSettings).detectionDetail) {
            Text("Generic").tag(DetectionDetail.generic)
            Text("Detailed").tag(DetectionDetail.detailed)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 250)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Detection Detail")
    }

    /// Demo (left, subordinate) — shutter (center, primary) — Photos (right).
    /// Icons only; accessibility labels carry the meanings.
    private var bottomControls: some View {
        ZStack {
            shutterButton

            HStack {
                demoButton
                Spacer()
                photosButton
            }
        }
    }

    private var shutterButton: some View {
        Button {
            scanTapped()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(.white)
                    .frame(width: 60, height: 60)
            }
            .opacity(camera.state == .running ? 1 : 0.4)
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(camera.state != .running)
        .accessibilityLabel("Scan")
        .accessibilityHint("Captures the photo and analyzes visible objects.")
    }

    private var photosButton: some View {
        Button {
            dismissScanIntro()
            isShowingPhotosPicker = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel("Choose Photo")
    }

    /// Expanded pill on first use ("✨ Try Demo Mode"), then a compact icon —
    /// deliberately visually smaller than the Photos button, while the hit
    /// target stays at least 44×44 pt.
    private var demoButton: some View {
        Button {
            dismissScanIntro()
            collapseDemoPill(animated: false)
            isShowingDemoPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                if isDemoPillExpanded {
                    Text("Try Demo Mode")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, isDemoPillExpanded ? 10 : 0)
            // Capped so the expanded pill clears the centered shutter even on
            // the narrowest devices; the capsule clips the text while the
            // width animates down into the icon button.
            .frame(maxWidth: isDemoPillExpanded ? 124 : 44)
            .background(.black.opacity(0.35), in: Capsule())
            .clipShape(Capsule())
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Try Demo Mode")
    }

    // MARK: - Idle-screen behavior

    private func scanTapped() {
        dismissScanIntro()
        Task {
            guard let image = await camera.capturePhoto() else { return }
            viewModel.analyzeCapturedImage(image)
        }
    }

    /// First-use choreography: the intro card and expanded demo pill appear
    /// together, the pill collapses (~3 s), the card fades (~4 s). Flags are
    /// marked when displayed, so returning to Scan never replays onboarding.
    /// The `.task` cancels on disappear, so a stale timer can't mutate a
    /// later Scan screen.
    private func runFirstUseHints() async {
        let hints = dependencies.onboardingHints

        if !hints.hasShownDemoModeHint {
            isDemoPillExpanded = true
            hints.markDemoHintShown()
        }
        if !hints.hasShownScanHint {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                isShowingScanIntro = true
            }
            hints.markScanHintShown()
        }

        if isDemoPillExpanded {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            collapseDemoPill(animated: true)
        }
        if isShowingScanIntro {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            dismissScanIntro()
        }
    }

    private func collapseDemoPill(animated: Bool) {
        guard isDemoPillExpanded else { return }
        if animated && !reduceMotion {
            // A slow width shrink into the icon button (the capsule clips the
            // fading text as the frame narrows).
            withAnimation(.easeInOut(duration: 0.9)) {
                isDemoPillExpanded = false
            }
        } else {
            isDemoPillExpanded = false
        }
    }

    private func dismissScanIntro() {
        guard isShowingScanIntro else { return }
        if reduceMotion {
            isShowingScanIntro = false
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                isShowingScanIntro = false
            }
        }
    }

    // MARK: - Non-idle states (unchanged presentations)

    private func photoReadyView(_ image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 420)
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

    /// One replacement action covering both image sources: retaking sends the
    /// user back to the live camera; choosing opens the Photos picker.
    private var changePhotoButton: some View {
        Menu {
            Button("Take Photo", systemImage: "camera") {
                viewModel.reset()
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

    private func errorView(_ message: String, retainedImage: UIImage?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let retainedImage {
                    Image(uiImage: retainedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(0.85)
                }

                VStack(spacing: 6) {
                    Label("Analysis Failed", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    if retainedImage != nil {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            viewModel.retryAnalysis()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Analyzes the same photo again")

                        changePhotoButton
                    } else {
                        Button("Start Over") {
                            viewModel.reset()
                        }
                        .buttonStyle(.borderedProminent)
                    }

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

/// Restrained shutter press feedback: a subtle scale, nothing theatrical.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Previews
// All previews use in-memory key stores/settings/hints and preview camera
// sessions: no Keychain, no persisted defaults, no networking, no real keys,
// and never a live AVCaptureSession or permission prompt.

private func previewDependencies(keyConfigured: Bool) -> AppDependencies {
    AppDependencies(
        geminiKeyStore: GeminiKeyStore(previewKey: keyConfigured ? "preview-key" : nil),
        detectionSettings: DetectionSettings(previewDetail: .generic),
        onboardingHints: OnboardingHints(previewScanHintShown: true, demoHintShown: true)
    )
}

private func previewViewModel(
    keyConfigured: Bool,
    state: ScanViewModel.State
) -> ScanViewModel {
    ScanViewModel(
        demoService: DemoDetectionService(),
        keyStore: GeminiKeyStore(previewKey: keyConfigured ? "preview-key" : nil),
        settings: DetectionSettings(previewDetail: .generic),
        liveService: { _, _ in DemoDetectionService() },
        state: state
    )
}

#Preview("Camera ready (returning user)") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(keyConfigured: true, state: .idle),
            dependencies: previewDependencies(keyConfigured: true),
            camera: CameraSession(previewState: .running)
        )
    }
}

#Preview("First use (intro + demo pill)") {
    FirstUsePreview()
}

private struct FirstUsePreview: View {
    var body: some View {
        NavigationStack {
            ScanView(
                viewModel: previewViewModel(keyConfigured: false, state: .idle),
                dependencies: AppDependencies(
                    geminiKeyStore: GeminiKeyStore(previewKey: nil),
                    detectionSettings: DetectionSettings(previewDetail: .generic),
                    onboardingHints: OnboardingHints(previewScanHintShown: false, demoHintShown: false)
                ),
                camera: CameraSession(previewState: .running)
            )
        }
    }
}

#Preview("Camera unavailable") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(keyConfigured: false, state: .idle),
            dependencies: previewDependencies(keyConfigured: false),
            camera: CameraSession(previewState: .unavailable)
        )
    }
}

#Preview("Camera access denied") {
    NavigationStack {
        ScanView(
            viewModel: previewViewModel(keyConfigured: false, state: .idle),
            dependencies: previewDependencies(keyConfigured: false),
            camera: CameraSession(previewState: .denied)
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
            dependencies: previewDependencies(keyConfigured: false),
            camera: CameraSession(previewState: .idle)
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
            dependencies: previewDependencies(keyConfigured: true),
            camera: CameraSession(previewState: .idle)
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
            dependencies: previewDependencies(keyConfigured: true),
            camera: CameraSession(previewState: .idle)
        )
    }
}
