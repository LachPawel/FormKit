// HandstandPoseEstimator.swift
// Subclass of PoseEstimator that additionally publishes HandstandAlignment
// by piping every bodyParts update through HandstandAnalyzer.

import Foundation
import Combine
import Vision

@MainActor
final class HandstandPoseEstimator: PoseEstimator {
    @Published var alignment: HandstandAlignment = HandstandAnalyzer().analyse(joints: [:])

    private var analyzer = HandstandAnalyzer()
    private var alignmentSubs = Set<AnyCancellable>()

    override init() {
        super.init()
        // Whenever bodyParts changes, rerun the analyser and publish the result.
        $bodyParts
            .sink { [weak self] parts in
                guard let self else { return }
                self.alignment = self.analyzer.analyse(joints: parts)
            }
            .store(in: &alignmentSubs)
    }
}
