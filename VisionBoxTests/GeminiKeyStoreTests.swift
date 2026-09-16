//
//  GeminiKeyStoreTests.swift
//  VisionBoxTests
//

import Testing
@testable import VisionBox

/// Exercises the observable credential state through the in-memory mode, so
/// tests never contend with the real simulator keychain (KeychainService
/// itself has its own serialized round-trip tests).
@MainActor
struct GeminiKeyStoreTests {

    @Test func startsUnconfiguredWithoutAKey() {
        let store = GeminiKeyStore(previewKey: nil)
        #expect(!store.isKeyConfigured)
        #expect(store.currentKey() == nil)
    }

    @Test func startsConfiguredWithAKey() {
        let store = GeminiKeyStore(previewKey: "test-key")
        #expect(store.isKeyConfigured)
        #expect(store.currentKey() == "test-key")
    }

    @Test func savingConfiguresAndExposesTheKey() throws {
        let store = GeminiKeyStore(previewKey: nil)
        try store.save("test-key")
        #expect(store.isKeyConfigured)
        #expect(store.currentKey() == "test-key")
    }

    @Test func savingAgainReplacesTheKey() throws {
        let store = GeminiKeyStore(previewKey: "test-key-old")
        try store.save("test-key-new")
        #expect(store.currentKey() == "test-key-new")
    }

    @Test func removingClearsKeyAndAvailability() throws {
        let store = GeminiKeyStore(previewKey: "test-key")
        try store.remove()
        #expect(!store.isKeyConfigured)
        #expect(store.currentKey() == nil)
    }
}
