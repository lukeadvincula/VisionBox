//
//  ScanViewModel.swift
//  VisionBox
//

import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Drives the scan flow: pick a photo or a demo scene, analyze, show results.
///
/// Demo scenes always run through `DemoDetectionService`; personal photos run
/// through the live Gemini service, which exists only while the user has a
/// stored API key. Both sides use the same `ObjectDetectionService` seam.
@MainActor @Observable
final class ScanViewModel {

    enum State {
        case idle
        /// A Photos selection is being loaded and decoded.
        case loadingPhoto
        /// A personal photo is loaded and displayed, awaiting live analysis.
        case photoReady(UIImage)
        case analyzing(UIImage)
        case results(image: UIImage, objects: [DetectedObject])
        /// `image` is the personal photo the failure interrupted (nil for
        /// demo/photo-loading failures) — retained so the user can Try Again
        /// without picking or capturing it again.
        case error(message: String, image: UIImage?)
    }

    private(set) var state: State
    /// The in-flight load or analysis, retained so newer actions can cancel it.
    private(set) var analysisTask: Task<Void, Never>?

    private let demoService: any ObjectDetectionService
    /// Shared observable credential state; availability comes from here
    /// without any Keychain access during view updates.
    private let keyStore: GeminiKeyStore
    /// Shared detection preferences, read at analyze time.
    private let settings: DetectionSettings
    /// Builds a live service for the current key and detail level. Called
    /// fresh at analyze time, so a replaced key or changed Detection Detail
    /// applies to the next user-initiated analysis — including Try Again —
    /// while automatic retries inside a running analysis keep the level the
    /// analysis started with.
    private let liveService: (String, DetectionDetail) -> any ObjectDetectionService

    init(
        demoService: any ObjectDetectionService,
        keyStore: GeminiKeyStore,
        settings: DetectionSettings,
        liveService: @escaping (String, DetectionDetail) -> any ObjectDetectionService,
        state: State = .idle
    ) {
        self.demoService = demoService
        self.keyStore = keyStore
        self.settings = settings
        self.liveService = liveService
        self.state = state
    }

    /// Whether the toolbar should offer starting over.
    var canStartOver: Bool {
        if case .idle = state { return false }
        return true
    }

    /// Whether live Gemini analysis is currently possible (a key is stored).
    /// Observable: saving or removing a key in Settings updates this
    /// immediately, with no restart and no Keychain read per body evaluation.
    var isLiveAnalysisAvailable: Bool {
        keyStore.isKeyConfigured
    }

    /// Runs a bundled demo scene through the detection seam.
    func analyzeDemoScene(_ scene: DemoScene) {
        guard let image = scene.image, let imageData = scene.imageData else {
            state = .error(message: "This demo scene couldn't be loaded.", image: nil)
            return
        }
        analysisTask?.cancel()
        state = .analyzing(image)
        analysisTask = Task {
            do {
                let objects = try await demoService.detectObjects(in: imageData)
                guard !Task.isCancelled else { return }
                state = .results(image: image, objects: objects)
            } catch is CancellationError {
                // Superseded by a newer action, which already updated the state.
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(message: "The demo analysis failed. Please try again.", image: nil)
            }
        }
    }

    /// Analyzes the currently selected personal photo with the live Gemini
    /// service: prepare (orientation-normalize, downscale, JPEG) → detect.
    func analyzePhoto() {
        guard case .photoReady(let image) = state else { return }
        guard let apiKey = keyStore.currentKey() else {
            // Unreachable through the UI (no Analyze button without a key),
            // but stays honest if ever called directly.
            state = .error(message: DetectionError.missingAPIKey.userMessage, image: image)
            return
        }
        let service = liveService(apiKey, settings.detectionDetail)
        analysisTask?.cancel()
        state = .analyzing(image)
        analysisTask = Task {
            do {
                let imageData = try await ImageProcessing.prepareForUpload(image)
                let objects = try await service.detectObjects(in: imageData)
                guard !Task.isCancelled else { return }
                state = .results(image: image, objects: objects)
            } catch is CancellationError {
                // Superseded by a newer action, which already updated the state.
            } catch let error as DetectionError {
                guard !Task.isCancelled else { return }
                state = .error(message: error.userMessage, image: image)
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(message: "The analysis failed. Please try again.", image: image)
            }
        }
    }

    /// Re-runs the failed analysis with the retained photo — no need to pick
    /// or capture the image again after a transient failure.
    func retryAnalysis() {
        guard case .error(_, .some(let image)) = state else { return }
        state = .photoReady(image)
        analyzePhoto()
    }

    /// Accepts a camera capture. From here on the image is indistinguishable
    /// from a Photos selection — same `photoReady` state, same analysis path.
    func setCapturedImage(_ image: UIImage) {
        analysisTask?.cancel()
        analysisTask = nil
        state = .photoReady(image)
    }

    /// Shutter flow: capture → analyze immediately when a key is configured;
    /// without one, the capture is retained in the existing setup-required
    /// state so configuring a key doesn't cost another capture.
    func analyzeCapturedImage(_ image: UIImage) {
        setCapturedImage(image)
        if isLiveAnalysisAvailable {
            analyzePhoto()
        }
    }

    /// Loads and decodes a Photos selection into the `photoReady` state.
    func loadPhoto(_ item: PhotosPickerItem) {
        analysisTask?.cancel()
        state = .loadingPhoto
        analysisTask = Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = await Self.decodeImage(from: data) else {
                    guard !Task.isCancelled else { return }
                    state = .error(message: "That photo couldn't be loaded. Try choosing a different one.", image: nil)
                    return
                }
                guard !Task.isCancelled else { return }
                state = .photoReady(image)
            } catch is CancellationError {
                // Superseded by a newer action, which already updated the state.
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(message: "That photo couldn't be loaded. Try choosing a different one.", image: nil)
            }
        }
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        state = .idle
    }

    /// Decoding can be expensive for large photos, so it runs off the main actor.
    @concurrent
    private nonisolated static func decodeImage(from data: Data) async -> UIImage? {
        UIImage(data: data)
    }
}
