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

// A UIView that hosts the AVCaptureVideoPreviewLayer
class CameraPreview: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// A UIViewRepresentable to expose CameraPreview to SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreview {
        let previewView = CameraPreview()
        previewView.videoPreviewLayer.session = session
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        return previewView
    }

    func updateUIView(_ uiView: CameraPreview, context: Context) {
        // Update the view if needed (e.g., session changes, though unlikely in this setup)
        uiView.videoPreviewLayer.session = session
    }
}
