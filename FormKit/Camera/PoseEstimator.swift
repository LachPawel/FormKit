import Foundation
import AVFoundation
import Combine
import CoreGraphics
import Vision

@MainActor
class PoseEstimator: NSObject, ObservableObject {
    // Published properties - mutated only on MainActor
    @Published var bodyParts = [HumanBodyPoseObservation.PoseJointName: Joint]()
    @Published var jointCount = 0
    @Published var repCounter = ExerciseRepCounter()
    @Published var fps: Double = 0

    // Accessed only from the processing queue via nonisolated methods.
    // nonisolated(unsafe) opts these out of actor-isolation checking;
    // callers are responsible for ensuring no concurrent access.
    nonisolated(unsafe) private var _isAnalyzingFrame = false
    nonisolated(unsafe) private var _frameCounter = 0
    nonisolated(unsafe) private var _fpsFrameCount = 0
    nonisolated(unsafe) private var _fpsLastTimestamp: CFTimeInterval = CACurrentMediaTime()

    private var subscriptions = Set<AnyCancellable>()

    override init() {
        super.init()
        $bodyParts
            .sink { [weak self] parts in
                self?.jointCount = parts.count
                self?.repCounter.processPose(parts)
            }
            .store(in: &subscriptions)
    }

    deinit {
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// Must be nonisolated because AVFoundation calls it on an arbitrary queue.
extension PoseEstimator: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        _frameCounter += 1

        // FPS calculation
        _fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - _fpsLastTimestamp
        if elapsed >= 1.0 {
            let measuredFPS = Double(_fpsFrameCount) / elapsed
            _fpsFrameCount = 0
            _fpsLastTimestamp = now
            Task { @MainActor [weak self] in self?.fps = measuredFPS }
        }

        // Downsample — process every 3rd frame only
        guard _frameCounter % 3 == 0, !_isAnalyzingFrame else {
            CMSampleBufferInvalidate(sampleBuffer)
            return
        }

        _isAnalyzingFrame = true

        Task { [weak self] in
            await self?.analyzeFrame(frame: sampleBuffer)
        }
    }

    // Runs off MainActor; publishes results back via MainActor.run
    nonisolated private func analyzeFrame(frame: CMSampleBuffer) async {
        defer {
            Task { @MainActor [weak self] in self?._isAnalyzingFrame = false }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else {
            CMSampleBufferInvalidate(frame)
            return
        }
        CMSampleBufferInvalidate(frame)

        do {
            var poseRequest = DetectHumanBodyPoseRequest()
            poseRequest.detectsHands = false
            let results = try await poseRequest.perform(on: pixelBuffer)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.bodyParts = results.first?.allJoints() ?? [:]
            }
        } catch {
            await MainActor.run { [weak self] in self?.bodyParts = [:] }
        }
    }
}
