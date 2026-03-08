import Foundation
import AVFoundation
import Combine
import CoreGraphics
import Vision

class PoseEstimator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    // Published properties - these will update the UI
    @Published var bodyParts = [HumanBodyPoseObservation.PoseJointName: Joint]()
    @Published var jointCount = 0
    @Published var repCounter = ExerciseRepCounter()

    private var isAnalyzingFrame = false
    private var currentTask: Task<Void, Never>?
    private var frameCounter = 0

    private var subscriptions = Set<AnyCancellable>()

    override init() {
        super.init()

        // Subscribe to bodyParts updates
        $bodyParts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] parts in
                self?.jointCount = parts.count
                self?.repCounter.processPose(parts)
            }
            .store(in: &subscriptions)
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - Camera Frame Processing
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1

        // Downsample processing load for smoother preview.
        guard frameCounter % 3 == 0, !isAnalyzingFrame else {
            CMSampleBufferInvalidate(sampleBuffer)
            return
        }

        isAnalyzingFrame = true
        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self = self else { return }
            await self.analyzeFrame(frame: sampleBuffer)
            self.isAnalyzingFrame = false
            self.currentTask = nil
        }
    }

    // Simplified frame analysis
    private func analyzeFrame(frame: CMSampleBuffer) async {
        if Task.isCancelled {
            CMSampleBufferInvalidate(frame)
            return
        }

        // Get pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else {
            CMSampleBufferInvalidate(frame)
            return
        }

        CMSampleBufferInvalidate(frame)

        do {
            // Create pose detection request using new API
            var poseRequest = DetectHumanBodyPoseRequest()
            poseRequest.detectsHands = false
            let results = try await poseRequest.perform(on: pixelBuffer)

            if Task.isCancelled { return }

            // Process results and update UI on main thread
            await MainActor.run {
                if let observation = results.first {
                    self.bodyParts = observation.allJoints()
                } else {
                    self.bodyParts = [:]
                }
            }
        } catch {
            await MainActor.run {
                self.bodyParts = [:]
            }
        }
    }
}
