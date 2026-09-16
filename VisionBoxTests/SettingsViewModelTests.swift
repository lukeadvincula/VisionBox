//
//  SettingsViewModelTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

/// Records validation calls and returns a configurable outcome.
@MainActor
private final class ValidatorSpy {
    private(set) var validatedKeys: [String] = []
    var result: Result<Void, DetectionError> = .success(())

    func validate(_ key: String) async throws {
        validatedKeys.append(key)
        if case .failure(let error) = result {
            throw error
        }
    }
}

@MainActor
struct SettingsViewModelTests {

    private func makeViewModel(
        keyStore: GeminiKeyStore? = nil,
        spy: ValidatorSpy? = nil
    ) -> SettingsViewModel {
        let spy = spy ?? ValidatorSpy()
        return SettingsViewModel(
            keyStore: keyStore ?? GeminiKeyStore(previewKey: nil),
            validator: { try await spy.validate($0) }
        )
    }

    // MARK: - Input handling

    @Test func saveAndTestTrimsWhitespaceAndNewlines() async throws {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let spy = ValidatorSpy()
        let viewModel = makeViewModel(keyStore: keyStore, spy: spy)

        viewModel.draftKey = "  test-key-trimmed\n"
        viewModel.saveAndTest()
        await viewModel.validationTask?.value

        #expect(keyStore.currentKey() == "test-key-trimmed")
        #expect(spy.validatedKeys == ["test-key-trimmed"])
    }

    @Test func whitespaceOnlyDraftIsRejectedWithoutSavingOrTesting() async {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let spy = ValidatorSpy()
        let viewModel = makeViewModel(keyStore: keyStore, spy: spy)

        viewModel.draftKey = "   \n "
        viewModel.saveAndTest()
        await viewModel.validationTask?.value

        #expect(keyStore.currentKey() == nil)
        #expect(!keyStore.isKeyConfigured)
        #expect(spy.validatedKeys.isEmpty)
        #expect(viewModel.status == .untested)
    }

    // MARK: - Save & Test outcomes

    @Test func successfulSaveAndTestConnectsAndClearsDraft() async throws {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let viewModel = makeViewModel(keyStore: keyStore)

        viewModel.draftKey = "test-key"
        viewModel.saveAndTest()
        #expect(viewModel.status == .testing)
        #expect(viewModel.draftKey.isEmpty)

        await viewModel.validationTask?.value
        #expect(viewModel.status == .connected)
        #expect(viewModel.isKeyConfigured)
        #expect(!viewModel.isEditingKey)
    }

    @Test func invalidKeyShowsInvalidStatusButKeepsTheStoredKey() async throws {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let spy = ValidatorSpy()
        spy.result = .failure(.unauthorized)
        let viewModel = makeViewModel(keyStore: keyStore, spy: spy)

        viewModel.draftKey = "test-key"
        viewModel.saveAndTest()
        await viewModel.validationTask?.value

        #expect(viewModel.status == .failed("Invalid API key"))
        // The user decides whether to edit or remove — never auto-deleted.
        #expect(keyStore.currentKey() == "test-key")
        #expect(viewModel.isKeyConfigured)
    }

    @Test func temporaryNetworkFailureKeepsTheStoredKey() async throws {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let spy = ValidatorSpy()
        spy.result = .failure(.network(nil))
        let viewModel = makeViewModel(keyStore: keyStore, spy: spy)

        viewModel.draftKey = "test-key"
        viewModel.saveAndTest()
        await viewModel.validationTask?.value

        #expect(viewModel.status == .failed("Could not connect — check your internet connection"))
        #expect(keyStore.currentKey() == "test-key")
    }

    @Test(arguments: [
        (DetectionError.rateLimited, "Rate limited — wait a moment and try again"),
        (DetectionError.server(statusCode: 503), "Gemini is temporarily unavailable"),
        (DetectionError.invalidResponse, "The connection test failed. Please try again."),
    ])
    func failureStatusesUseSafeConciseWording(error: DetectionError, expected: String) {
        #expect(SettingsViewModel.statusMessage(for: error) == expected)
    }

    // MARK: - Test Connection

    @Test func testConnectionValidatesTheStoredKey() async throws {
        let spy = ValidatorSpy()
        let viewModel = makeViewModel(keyStore: GeminiKeyStore(previewKey: "test-key-stored"), spy: spy)

        viewModel.testConnection()
        await viewModel.validationTask?.value

        #expect(spy.validatedKeys == ["test-key-stored"])
        #expect(viewModel.status == .connected)
    }

    @Test func testConnectionWithoutAKeyFailsWithoutValidating() async {
        let spy = ValidatorSpy()
        let viewModel = makeViewModel(keyStore: GeminiKeyStore(previewKey: nil), spy: spy)

        viewModel.testConnection()
        await viewModel.validationTask?.value

        #expect(spy.validatedKeys.isEmpty)
        #expect(viewModel.status == .failed("No API key is stored"))
    }

    // MARK: - Edit / Remove

    @Test func editingAsksForAReplacementWithoutExposingTheStoredKey() {
        let viewModel = makeViewModel(keyStore: GeminiKeyStore(previewKey: "test-key"))

        viewModel.draftKey = "leftover"
        viewModel.beginEditingKey()
        #expect(viewModel.isEditingKey)
        #expect(viewModel.draftKey.isEmpty)

        viewModel.cancelEditingKey()
        #expect(!viewModel.isEditingKey)
        #expect(viewModel.draftKey.isEmpty)
    }

    @Test func replacementKeyIsSavedAndValidated() async throws {
        let keyStore = GeminiKeyStore(previewKey: "test-key-old")
        let spy = ValidatorSpy()
        let viewModel = makeViewModel(keyStore: keyStore, spy: spy)

        viewModel.beginEditingKey()
        viewModel.draftKey = "test-key-new"
        viewModel.saveAndTest()
        await viewModel.validationTask?.value

        #expect(keyStore.currentKey() == "test-key-new")
        #expect(spy.validatedKeys == ["test-key-new"])
        #expect(!viewModel.isEditingKey)
    }

    @Test func removeKeyClearsCredentialAndStatus() throws {
        let keyStore = GeminiKeyStore(previewKey: "test-key")
        let viewModel = SettingsViewModel(
            keyStore: keyStore,
            validator: { _ in },
            status: .connected
        )

        viewModel.removeKey()

        #expect(!viewModel.isKeyConfigured)
        #expect(keyStore.currentKey() == nil)
        #expect(viewModel.status == .untested)
    }

    // MARK: - Cancellation

    @Test func cancellingAnInFlightTestReturnsToUntested() async throws {
        let keyStore = GeminiKeyStore(previewKey: "test-key")
        let viewModel = SettingsViewModel(
            keyStore: keyStore,
            validator: { _ in try await Task.sleep(for: .seconds(60)) }
        )

        viewModel.testConnection()
        #expect(viewModel.status == .testing)
        let task = try #require(viewModel.validationTask)

        viewModel.cancelValidation()
        #expect(task.isCancelled)
        #expect(viewModel.status == .untested)

        // The cancelled test must not overwrite the status afterwards.
        await task.value
        #expect(viewModel.status == .untested)
    }
}
