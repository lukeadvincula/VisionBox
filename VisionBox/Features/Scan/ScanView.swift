//
//  ScanView.swift
//  VisionBox
//

import SwiftUI

/// The app's main screen: switches between the scan states and hosts
/// navigation to Results (inline) and Settings (sheet).
struct ScanView: View {
    @State private var viewModel: ScanViewModel
    @State private var isShowingSettings: Bool

    init(dependencies: AppDependencies) {
        self.viewModel = ScanViewModel(detectionService: dependencies.detectionService)
        self.isShowingSettings = false
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .analyzing:
                ProgressView("Analyzing…")
            case .results(let image, let objects):
                ResultsView(image: image, objects: objects)
            case .error(let message):
                errorView(message)
            }
        }
        .navigationTitle("VisionBox")
        .toolbar {
            if case .results = viewModel.state {
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
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "Detect Objects in Photos",
                systemImage: "viewfinder",
                description: Text("Photo selection and Gemini analysis arrive in later phases. Preview the Results experience with sample data in the meantime.")
            )
            Button("Preview Sample Results") {
                Task { await viewModel.analyzeSampleImage() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button("Start Over") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        ScanView(dependencies: AppDependencies())
    }
}
