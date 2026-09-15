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
        case error(String)
    }

    private(set) var state: State
    /// The in-flight load or analysis, retained so newer actions can cancel it.
    private(set) var analysisTask: Task<Void, Never>?

    private let demoService: any ObjectDetectionService
    /// Returns the live Gemini service, or nil while no API key is stored.
    /// Resolved per call so a key added or removed mid-session takes effect.
    private let liveService: () -> (any ObjectDetectionService)?

    init(
        demoService: any ObjectDetectionService,
        liveService: @escaping () -> (any ObjectDetectionService)?,
        state: State = .idle
    ) {
        self.demoService = demoService
        self.liveService = liveService
        self.state = state
    }

    /// Whether the toolbar should offer starting over.
    var canStartOver: Bool {
        if case .idle = state { return false }
        return true
    }

    /// Whether live Gemini analysis is currently possible (a key is stored).
    var isLiveAnalysisAvailable: Bool {
        liveService() != nil
    }

    /// Runs a bundled demo scene through the detection seam.
    func analyzeDemoScene(_ scene: DemoScene) {
        guard let image = scene.image, let imageData = scene.imageData else {
            state = .error("This demo scene couldn't be loaded.")
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
                state = .error("The demo analysis failed. Please try again.")
            }
        }
    }

    /// Analyzes the currently selected personal photo with the live Gemini
    /// service: prepare (orientation-normalize, downscale, JPEG) → detect.
    func analyzePhoto() {
        guard case .photoReady(let image) = state else { return }
        guard let service = liveService() else {
            // Unreachable through the UI (the button is disabled without a
            // key), but stays honest if ever called directly.
            state = .error(DetectionError.missingAPIKey.userMessage)
            return
        }
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
                state = .error(error.userMessage)
            } catch {
                guard !Task.isCancelled else { return }
                state = .error("The analysis failed. Please try again.")
            }
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
                    state = .error("That photo couldn't be loaded. Try choosing a different one.")
                    return
                }
                guard !Task.isCancelled else { return }
                state = .photoReady(image)
            } catch is CancellationError {
                // Superseded by a newer action, which already updated the state.
            } catch {
                guard !Task.isCancelled else { return }
                state = .error("That photo couldn't be loaded. Try choosing a different one.")
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
