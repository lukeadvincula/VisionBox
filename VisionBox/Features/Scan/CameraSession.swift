//
//  CameraSession.swift
//  VisionBox
//

// @preconcurrency: AVFoundation's session/output types aren't Sendable-annotated;
// all mutation is serialized on `sessionQueue` by construction.
@preconcurrency import AVFoundation
import Observation
import UIKit

/// Owns the capture pipeline behind the camera-first Scan screen:
/// authorization, session lifecycle, and still capture. Deliberately
/// minimal — rear camera, live preview, one photo output; no zoom, flash,
/// switching, or video. This is an object-detection showcase, not a camera
/// app.
///
/// All AVFoundation configuration and start/stop runs on a private serial
/// queue; the published `state` is MainActor. Permission is requested only
/// from `start()` — i.e. only once the user reaches the Scan screen.
@MainActor @Observable
final class CameraSession {

    enum State {
        /// Not started (or stopped while leaving the Scan screen).
        case idle
        /// Waiting for the user's answer to the permission prompt.
        case requestingAccess
        /// Live preview running; capture available.
        case running
        /// Permission denied or restricted — guide to Settings.
        case denied
        /// No usable camera hardware (common in Simulator).
        case unavailable
    }

    private(set) var state: State = .idle

    /// Exposed for `CameraPreview`'s layer; mutated only on `sessionQueue`.
    nonisolated let captureSession = AVCaptureSession()

    /// Current preview rotation so the layer stays upright; 90° (portrait)
    /// until the device-backed coordinator exists.
    var previewRotationAngle: CGFloat {
        rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 90
    }

    /// True for the preview/test instances that must never touch AVFoundation.
    let isPreviewInstance: Bool

    private nonisolated let sessionQueue = DispatchQueue(label: "VisionBox.CameraSession")
    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// Retains the in-flight capture delegate until AVFoundation finishes.
    private var activeCaptureDelegate: PhotoCaptureDelegate?

    init() {
        self.isPreviewInstance = false
    }

    /// Preview/testing only: fixed state, no AVFoundation access.
    init(previewState: State) {
        self.isPreviewInstance = true
        self.state = previewState
    }

    /// Ensures authorization, configures once, and starts the preview.
    /// Safe to call repeatedly (e.g. every return to the Scan screen).
    func start() async {
        guard !isPreviewInstance else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            state = .requestingAccess
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        guard let device = await configureIfNeeded() else {
            state = .unavailable
            return
        }
        if rotationCoordinator == nil {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }
        await startRunning()
        state = .running
    }

    /// Stops the preview when the Scan screen goes away. Cheap and safe to
    /// call in any state.
    func stop() {
        guard !isPreviewInstance else { return }
        let session = captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        if state == .running {
            state = .idle
        }
    }

    /// Captures one still, rotated for the current device orientation.
    /// nil when capture isn't possible or fails — never a crash.
    func capturePhoto() async -> UIImage? {
        guard state == .running else { return nil }

        let output = photoOutput
        let captureAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture

        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate { image in
                continuation.resume(returning: image)
            }
            activeCaptureDelegate = delegate
            sessionQueue.async {
                if let captureAngle,
                   let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(captureAngle) {
                    connection.videoRotationAngle = captureAngle
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    // MARK: - Session queue work

    /// Adds the rear camera input and photo output exactly once.
    /// Returns the device on success, nil when no usable camera exists.
    private func configureIfNeeded() async -> AVCaptureDevice? {
        let session = captureSession
        let output = photoOutput

        if isConfigured {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }

        let device: AVCaptureDevice? = await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: camera) else {
                    continuation.resume(returning: nil)
                    return
                }
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    continuation.resume(returning: nil)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                continuation.resume(returning: camera)
            }
        }
        isConfigured = device != nil
        return device
    }

    private func startRunning() async {
        let session = captureSession
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }
}

/// Bridges AVFoundation's delegate callback (arbitrary queue) to one
/// completion call. Decodes via `fileDataRepresentation`, which carries the
/// capture connection's rotation as EXIF orientation — the existing
/// `ImageProcessing` pipeline then normalizes it exactly like a Photos image.
/// @unchecked Sendable: immutable (a single stored closure), and the closure
/// only resumes a checked continuation, which is thread-safe.
private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
