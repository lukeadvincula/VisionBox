//
//  CameraPicker.swift
//  VisionBox
//

import SwiftUI
import UIKit

/// The native camera, wrapped for SwiftUI.
///
/// Presents `UIImagePickerController` with the `.camera` source and hands the
/// captured image straight back. Deliberately dumb: no processing, no state,
/// no persistence — the capture flows into the same pipeline as a Photos
/// selection (`photoReady` → `ImageProcessing` → Gemini). Building a custom
/// AVFoundation capture stack would add nothing this app needs.
///
/// No `#Preview`: the camera requires real hardware and a permission grant,
/// so an Xcode preview would only ever render a black placeholder.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured image, or nil when the user cancels.
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // A missing image is treated like a cancellation — never a crash.
            onComplete(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}
