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
/// Demo scenes run through the same `ObjectDetectionService` seam that live
/// Gemini analysis will use in a later phase. Personal photos can be selected
/// and displayed, but not yet analyzed — that requires the Gemini integration.
@MainActor @Observable
final class ScanViewModel {

    enum State {
        case idle
        /// A Photos selection is being loaded and decoded.
        case loadingPhoto
        /// A personal photo is loaded and displayed; live analysis becomes
        /// available with the Gemini integration (next phase).
        case photoReady(UIImage)
        case analyzing(UIImage)
        case results(image: UIImage, objects: [DetectedObject])
        case error(String)
    }

    private(set) var state: State
    /// The in-flight load or analysis, retained so newer actions can cancel it.
    private(set) var analysisTask: Task<Void, Never>?
    private let detectionService: any ObjectDetectionService

    init(detectionService: any ObjectDetectionService, state: State = .idle) {
        self.detectionService = detectionService
        self.state = state
    }

    /// Whether the toolbar should offer starting over.
    var canStartOver: Bool {
        if case .idle = state { return false }
        return true
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
                let objects = try await detectionService.detectObjects(in: imageData)
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

    /// Loads and decodes a Photos selection. The photo is displayed but not
    /// analyzed — see `State.photoReady`.
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
