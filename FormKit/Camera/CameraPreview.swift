//
//  CameraPreview.swift
//  FormForgeV2
//
//  Created by Pawel Kowalewski on 09/05/2025.
//


//
//  CameraPreviewView.swift
//
//  Created by Lach on 09/05/2025.
//

import SwiftUI
import AVFoundation
import UIKit

/// A UIView subclass whose layer is an AVCaptureVideoPreviewLayer.
/// Must always be created and accessed on the main thread.
class CameraPreview: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

/// UIViewRepresentable wrapper that exposes CameraPreview to SwiftUI.
/// makeUIView is called by SwiftUI on the main thread; we do nothing
/// with UIKit off that thread.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreview {
        // UIView creation must always happen on the main thread.
        // SwiftUI guarantees this for makeUIView, but if something
        // upstream triggers this from a bg thread we catch it here.
        assert(Thread.isMainThread, "CameraPreviewView.makeUIView must be called on the main thread")
        let previewView = CameraPreview()
        previewView.videoPreviewLayer.session = session
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        previewView.videoPreviewLayer.connection?.videoRotationAngle = 90
        return previewView
    }

    func updateUIView(_ uiView: CameraPreview, context: Context) {
        // Only update if the session reference actually changed.
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

