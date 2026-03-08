// PoseDetectionView.swift
import SwiftUI
import AVFoundation
import Vision

struct PoseDetectionView: View {
    @StateObject private var poseEstimator: PoseEstimator
    @StateObject private var cameraViewModel: CameraViewModel

    init() {
        let estimator = PoseEstimator()
        _poseEstimator = StateObject(wrappedValue: estimator)
        _cameraViewModel = StateObject(wrappedValue: CameraViewModel(poseEstimator: estimator))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // MARK: Camera preview
                CameraView(viewModel: cameraViewModel)
                    .ignoresSafeArea()

                // MARK: Skeleton overlay
                FreePostureStickFigureView(poseEstimator: poseEstimator, size: geometry.size)
                    .ignoresSafeArea()

                // MARK: Debug coordinates overlay
                debugOverlay
            }
        }
        .onAppear {
            cameraViewModel.setupSession()
            cameraViewModel.startSession()
        }
        .onDisappear {
            cameraViewModel.stopSession()
        }
    }

    // MARK: - Debug overlay
    private var debugOverlay: some View {
        let sorted = poseEstimator.bodyParts
            .sorted { $0.key.rawValue < $1.key.rawValue }

        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Joints detected: \(poseEstimator.jointCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                ForEach(Array(sorted.prefix(14)), id: \.key) { name, joint in
                    Text(
                        String(
                            format: "%@  x=%.3f  y=%.3f  c=%.2f",
                            name.rawValue,
                            joint.location.x,
                            joint.location.y,
                            joint.confidence
                        )
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 300, maxHeight: 220)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 56)
        .padding(.leading, 12)
    }
}
