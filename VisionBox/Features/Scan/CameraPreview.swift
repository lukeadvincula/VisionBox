//
//  CameraPreview.swift
//  VisionBox
//

import AVFoundation
import SwiftUI
import UIKit

/// Hosts the live `AVCaptureVideoPreviewLayer` as the Scan screen's
/// background. Aspect-fill: the preview crops at the edges rather than
/// letterboxing. Contains no capture or Gemini logic.
///
/// This geometry is presentation-only — Results bounding boxes are drawn
/// over the analyzed *still* with the separate `.scaledToFit()` strategy.
struct CameraPreview: UIViewRepresentable {
    let session: CameraSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session.captureSession
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Keeps the preview upright; SwiftUI re-calls this on layout changes.
        let angle = session.previewRotationAngle
        if let connection = uiView.previewLayer?.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }
}
