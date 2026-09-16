//
//  CameraAccess.swift
//  VisionBox
//

import AVFoundation
import UIKit

/// Camera hardware availability and authorization, kept small and local.
///
/// AVFoundation is used only for the authorization check/request —
/// `UIImagePickerController` performs the actual capture. Permission is never
/// requested at launch; only when the user taps Take Photo.
@MainActor
enum CameraAccess {

    enum Readiness {
        /// Hardware present and access authorized — present the camera.
        case ready
        /// Not determined yet — request permission, then present if granted.
        case needsPermission
        /// Denied or restricted — explain and offer Settings.
        case denied
        /// No camera hardware (e.g. the Simulator) — Settings can't help.
        case unavailable
    }

    static var readiness: Readiness {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Prompts for camera permission. Returns whether access was granted.
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
