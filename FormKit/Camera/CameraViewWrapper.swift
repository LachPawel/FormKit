//
//  CameraViewWrapper.swift
//
//  Created by Pawel Lach on 09/05/2025.
//

import SwiftUI

struct CameraViewWrapper: View {
    @StateObject private var cameraViewModel: CameraViewModel

    init(poseEstimator: PoseEstimator) {
        // Use StateObject to create the view model with the pose estimator
        _cameraViewModel = StateObject(wrappedValue: CameraViewModel(poseEstimator: poseEstimator))
    }

    var body: some View {
        // CameraView now displays the live preview using CameraPreviewView
        // and can optionally overlay processed frames or drawings.
        CameraView(viewModel: cameraViewModel)
            .onAppear {
                // Start capturing when view appears
                cameraViewModel.startSession()
            }
            .onDisappear {
                // Stop capturing when view disappears
                cameraViewModel.stopSession()
            }
    }
}
