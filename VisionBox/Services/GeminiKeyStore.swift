//
//  GeminiKeyStore.swift
//  VisionBox
//

import Foundation
import Observation

/// Observable credential state for the user's Gemini API key.
///
/// The single source of truth shared by Settings and Scan: saving or removing
/// a key here updates `isKeyConfigured`, and every observer reacts immediately
/// — no app restart, and no Keychain reads from SwiftUI body evaluation. The
/// Keychain is touched only at init and inside explicit mutations/reads.
@MainActor @Observable
final class GeminiKeyStore {

    /// Whether a key is currently stored. Observable, so views can gate the
    /// live-analysis UI on it without querying the Keychain themselves.
    private(set) var isKeyConfigured: Bool

    /// nil in the in-memory (preview/test) mode.
    private let keychain: KeychainService?
    private var inMemoryKey: String?

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
        self.inMemoryKey = nil
        self.isKeyConfigured = ((try? keychain.readAPIKey())?.isEmpty == false)
    }

    /// In-memory store for previews and unit tests: fixed starting state,
    /// never touches the Keychain.
    init(previewKey: String?) {
        self.keychain = nil
        self.inMemoryKey = previewKey
        self.isKeyConfigured = previewKey != nil
    }

    /// Stores the key (replacing any existing one) and updates availability.
    func save(_ key: String) throws {
        if let keychain {
            try keychain.saveAPIKey(key)
        } else {
            inMemoryKey = key
        }
        isKeyConfigured = true
    }

    /// Deletes the stored key and updates availability.
    func remove() throws {
        if let keychain {
            try keychain.deleteAPIKey()
        } else {
            inMemoryKey = nil
        }
        isKeyConfigured = false
    }

    /// The current key, read fresh so callers constructing a live service
    /// always use the latest credential. Deliberately not a stored property —
    /// the key itself shouldn't linger in observable state.
    func currentKey() -> String? {
        if let keychain {
            return try? keychain.readAPIKey()
        }
        return inMemoryKey
    }
}
