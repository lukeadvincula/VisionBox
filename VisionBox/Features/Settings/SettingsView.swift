//
//  SettingsView.swift
//  VisionBox
//

import SwiftUI

/// Settings shell. Gemini API key entry (Keychain-backed) arrives in a later
/// phase. Demo Mode intentionally has no toggle here yet: with no live
/// detection service to switch away from, "Try Demo Mode" on the main screen
/// is the single, obvious entry point. A persistent mode switch becomes
/// meaningful once the Gemini integration exists.
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
                Label("Demo Mode", systemImage: "sparkles")
            } footer: {
                Text("Demo Mode needs no setup — choose “Try Demo Mode” on the main screen to explore VisionBox without an API key or network access.")
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
