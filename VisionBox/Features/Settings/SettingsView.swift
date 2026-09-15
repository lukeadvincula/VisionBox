//
//  SettingsView.swift
//  VisionBox
//

import SwiftUI

/// Placeholder shell establishing where configuration will live.
/// API key entry (Keychain-backed) and the Demo Mode toggle arrive in later phases.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent("Gemini API Key", value: "Coming soon")
            } footer: {
                Text("You'll be able to add your own Google Gemini API key here to analyze photos.")
            }

            Section {
                LabeledContent("Demo Mode", value: "Coming soon")
            } footer: {
                Text("Demo Mode will let you try VisionBox on sample photos without an API key.")
            }
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
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
