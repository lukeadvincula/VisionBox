//
//  SettingsView.swift
//  VisionBox
//

import SwiftUI

/// BYOK settings plus detection preferences. The API key is never displayed
/// once stored — only a masked placeholder.
struct SettingsView: View {
    private let settings: DetectionSettings
    @State private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(dependencies: AppDependencies) {
        self.settings = dependencies.detectionSettings
        self.viewModel = SettingsViewModel(
            keyStore: dependencies.geminiKeyStore,
            validator: { try await dependencies.validateAPIKey($0) }
        )
    }

    /// Lets previews start from a specific state.
    init(viewModel: SettingsViewModel, settings: DetectionSettings) {
        self.settings = settings
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            statusSection
            if viewModel.isKeyConfigured && !viewModel.isEditingKey {
                configuredActionsSection
            } else {
                keyEntrySection
            }
            detectionDetailSection
            getKeySection
            demoModeSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert(
            "Remove Gemini API Key?",
            isPresented: $viewModel.isShowingRemoveConfirmation
        ) {
            Button("Remove Key", role: .destructive) {
                viewModel.removeKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to add a Gemini API key again to analyze personal photos. Demo Mode will keep working.")
        }
        .onDisappear {
            viewModel.cancelValidation()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Status", value: viewModel.isKeyConfigured ? "Configured" : "Not Set Up")
            if viewModel.isKeyConfigured && !viewModel.isEditingKey {
                LabeledContent("API Key", value: "••••••••••••••••")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("API key stored")
            }
            connectionStatusRow
        } header: {
            Text("Gemini API")
        } footer: {
            Text("VisionBox doesn't include its own Gemini API key — you provide your own. It's stored securely in the Keychain on this device and sent only to Google's Gemini API.")
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch viewModel.status {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Testing connection…")
            }
            .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var keyEntrySection: some View {
        Section {
            SecureField("Paste your Gemini API key", text: $viewModel.draftKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Gemini API key")
            Button("Save & Test") {
                viewModel.saveAndTest()
            }
            .disabled(!viewModel.canSaveDraft)
            if viewModel.isEditingKey {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelEditingKey()
                }
            }
        } header: {
            Text(viewModel.isEditingKey ? "Replace API Key" : "Add Your API Key")
        } footer: {
            Text("The key is saved to the Keychain, then verified with a minimal request to Gemini — no photo is sent.")
        }
    }

    private var configuredActionsSection: some View {
        Section {
            Button("Test Connection") {
                viewModel.testConnection()
            }
            .disabled(viewModel.status == .testing)
            Button("Edit Key") {
                viewModel.beginEditingKey()
            }
            Button("Remove Key…", role: .destructive) {
                viewModel.isShowingRemoveConfirmation = true
            }
        }
    }

    private var detectionDetailSection: some View {
        Section {
            Picker("Detection Detail", selection: Bindable(settings).detectionDetail) {
                Text("Standard").tag(DetectionDetail.standard)
                Text("Detailed").tag(DetectionDetail.detailed)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Detection Detail")
        } footer: {
            Text(detectionDetailDescription)
        }
    }

    private var detectionDetailDescription: String {
        switch settings.detectionDetail {
        case .standard:
            "Identifies the general product or object — for example, Game Controller. Applies to Gemini analysis of your photos; Demo Mode's sample results are unaffected."
        case .detailed:
            "Identifies brand, model, color, or variant when the photo visibly supports it — for example, DualSense Wireless Controller. Applies to Gemini analysis of your photos; Demo Mode's sample results are unaffected."
        }
    }

    private var getKeySection: some View {
        Section {
            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                Label("Get a Gemini API Key", systemImage: "arrow.up.right")
            }
            .accessibilityHint("Opens Google AI Studio in the browser")
        } footer: {
            Text("Create a free API key in Google AI Studio.")
        }
    }

    private var demoModeSection: some View {
        Section {
            Label("Demo Mode", systemImage: "sparkles")
        } footer: {
            Text("Demo Mode needs no API key or network — choose “Try Demo Mode” on the main screen.")
        }
    }
}

// MARK: - Previews
// All previews use in-memory key stores/settings and no-op validators:
// no Keychain access, no UserDefaults writes, no networking, no real keys.

#Preview("First setup") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: nil),
                validator: { _ in }
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}

#Preview("Configured, Standard detail") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in }
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}

#Preview("Configured, Detailed detail") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in }
            ),
            settings: DetectionSettings(previewDetail: .detailed)
        )
    }
}

#Preview("Testing") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in },
                status: .testing
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}

#Preview("Connected") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in },
                status: .connected
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}

#Preview("Invalid key") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in },
                status: .failed("Invalid API key")
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}

#Preview("Editing key") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                keyStore: GeminiKeyStore(previewKey: "preview-key"),
                validator: { _ in },
                isEditingKey: true
            ),
            settings: DetectionSettings(previewDetail: .standard)
        )
    }
}
