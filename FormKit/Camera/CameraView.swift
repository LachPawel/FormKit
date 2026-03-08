//
//  CameraView.swift
//
//  Created by Pawel Lach on 09/05/2025.
//


import SwiftUI
import AVFoundation

struct CameraView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch viewModel.sessionState {
                case .initializing:
                    ProgressView("Starting camera...")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.black.opacity(0.7))
                case .failed:
                    ContentUnavailableView(
                        "Camera Setup Failed",
                        systemImage: "video.slash.fill",
                        description: Text("The camera session could not be set up.")
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                case .running:
                    if let captureSession = viewModel.captureSession {
                        CameraPreviewView(session: captureSession)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        ProgressView("Starting camera...")
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .background(Color.black.opacity(0.7))
                    }
                }
            }
        }
    }
}
