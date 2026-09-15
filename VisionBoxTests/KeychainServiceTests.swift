//
//  KeychainServiceTests.swift
//  VisionBoxTests
//

import Testing
@testable import VisionBox

/// Runs against the simulator keychain through the app host. Every test
/// starts and ends with a clean slate; only obviously fake values are stored.
@Suite(.serialized)
struct KeychainServiceTests {

    private let keychain = KeychainService()

    @Test func readReturnsNilWhenNoKeyIsStored() throws {
        try keychain.deleteAPIKey()
        #expect(try keychain.readAPIKey() == nil)
    }

    @Test func saveAndReadRoundTrip() throws {
        try keychain.deleteAPIKey()
        try keychain.saveAPIKey("test-key-round-trip")
        #expect(try keychain.readAPIKey() == "test-key-round-trip")
        try keychain.deleteAPIKey()
    }

    @Test func savingAgainReplacesThePreviousKey() throws {
        try keychain.deleteAPIKey()
        try keychain.saveAPIKey("test-key-first")
        try keychain.saveAPIKey("test-key-second")
        #expect(try keychain.readAPIKey() == "test-key-second")
        try keychain.deleteAPIKey()
    }

    @Test func deleteRemovesTheKeyAndIsIdempotent() throws {
        try keychain.saveAPIKey("test-key-to-delete")
        try keychain.deleteAPIKey()
        #expect(try keychain.readAPIKey() == nil)
        // Deleting again must not throw.
        try keychain.deleteAPIKey()
    }
}
