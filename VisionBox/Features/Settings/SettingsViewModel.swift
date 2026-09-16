//
//  SettingsViewModel.swift
//  VisionBox
//

import Foundation
import Observation

/// Drives the BYOK Settings experience: key entry, Save & Test, Test
/// Connection, Edit, and Remove.
///
/// Credential presence (`isKeyConfigured`, from the shared `GeminiKeyStore`)
/// is deliberately separate from the last connection-test outcome (`status`):
/// a stored key remains stored even when a test fails — a temporary network
/// problem must never silently delete the user's key.
@MainActor @Observable
final class SettingsViewModel {

    enum ConnectionStatus: Equatable {
        case untested
        case testing
        case connected
        case failed(String)
    }

    /// Key text while the user types. Exists only in memory and is cleared
    /// as soon as the key is saved to the Keychain.
    var draftKey = ""
    var isEditingKey: Bool
    var isShowingRemoveConfirmation = false
    private(set) var status: ConnectionStatus
    /// The in-flight connection test, retained so it can be cancelled and so
    /// repeated taps can't stack concurrent validations.
    private(set) var validationTask: Task<Void, Never>?

    private let keyStore: GeminiKeyStore
    private let validator: (String) async throws -> Void

    init(
        keyStore: GeminiKeyStore,
        validator: @escaping (String) async throws -> Void,
        status: ConnectionStatus = .untested,
        isEditingKey: Bool = false
    ) {
        self.keyStore = keyStore
        self.validator = validator
        self.status = status
        self.isEditingKey = isEditingKey
    }

    var isKeyConfigured: Bool {
        keyStore.isKeyConfigured
    }

    var trimmedDraftKey: String {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSaveDraft: Bool {
        !trimmedDraftKey.isEmpty && status != .testing
    }

    /// Saves the entered key to the Keychain, then validates it remotely.
    /// Saving and validation are related but distinct: a save that succeeds
    /// followed by a failed test leaves the key stored.
    func saveAndTest() {
        let key = trimmedDraftKey
        guard !key.isEmpty else { return }
        do {
            try keyStore.save(key)
        } catch {
            // Keep the draft so the user can retry.
            status = .failed("The key couldn't be saved to the Keychain. Please try again.")
            return
        }
        draftKey = ""
        isEditingKey = false
        runValidation(of: key)
    }

    /// Validates the currently stored key.
    func testConnection() {
        guard let key = keyStore.currentKey() else {
            status = .failed("No API key is stored")
            return
        }
        runValidation(of: key)
    }

    func beginEditingKey() {
        // Ask for the replacement rather than exposing the stored key.
        draftKey = ""
        isEditingKey = true
    }

    func cancelEditingKey() {
        draftKey = ""
        isEditingKey = false
    }

    func removeKey() {
        do {
            try keyStore.remove()
            status = .untested
        } catch {
            status = .failed("The key couldn't be removed from the Keychain. Please try again.")
        }
    }

    /// Called when Settings disappears so an abandoned test doesn't linger.
    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
        if status == .testing {
            status = .untested
        }
    }

    private func runValidation(of key: String) {
        validationTask?.cancel()
        status = .testing
        validationTask = Task {
            do {
                try await validator(key)
                guard !Task.isCancelled else { return }
                status = .connected
            } catch is CancellationError {
                // Superseded or abandoned; state was handled by the canceller.
            } catch let error as DetectionError {
                guard !Task.isCancelled else { return }
                status = .failed(Self.statusMessage(for: error))
            } catch {
                guard !Task.isCancelled else { return }
                status = .failed("The connection test failed. Please try again.")
            }
        }
    }

    /// Short, safe status wording for connection-test outcomes. Never exposes
    /// provider error text, response bodies, or the key.
    static func statusMessage(for error: DetectionError) -> String {
        switch error {
        case .unauthorized:
            "Invalid API key"
        case .rateLimited:
            "Rate limited — wait a moment and try again"
        case .network:
            "Could not connect — check your internet connection"
        case .server:
            "Gemini is temporarily unavailable"
        case .missingAPIKey:
            "No API key is stored"
        case .invalidResponse, .decoding, .imagePreparation:
            "The connection test failed. Please try again."
        }
    }
}
