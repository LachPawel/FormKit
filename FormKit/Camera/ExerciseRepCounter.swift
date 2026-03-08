import Foundation
import CoreGraphics
import Vision

struct RepCounterUpdate {
    let didIncrementRep: Bool
    let phase: String
    let debugMessage: String
}

protocol ExerciseRule {
    var name: String { get }
    mutating func evaluate(joints: [HumanBodyPoseObservation.PoseJointName: Joint], currentRepCount: Int) -> RepCounterUpdate
    mutating func reset()
}

/// Template implementation showing where custom exercise logic should live.
/// Replace the TODO in `evaluate` with your own phase/threshold rules.
struct TemplateExerciseRule: ExerciseRule {
    let name: String = "Template"

    mutating func evaluate(
        joints: [HumanBodyPoseObservation.PoseJointName: Joint],
        currentRepCount: Int
    ) -> RepCounterUpdate {
        // TODO: Example hook for future exercises.
        // 1) Read joints you need (hip/knee/shoulder, etc.)
        // 2) Compute angles/distances
        // 3) Transition exercise phase and increment reps
        _ = joints
        _ = currentRepCount
        return RepCounterUpdate(didIncrementRep: false, phase: "idle", debugMessage: "Template rule active")
    }

    mutating func reset() {}
}

final class ExerciseRepCounter: ObservableObject {
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var currentPhase: String = "idle"
    @Published private(set) var lastDebugMessage: String = "No movement analyzed yet"

    private var rule: any ExerciseRule

    init(rule: any ExerciseRule = TemplateExerciseRule()) {
        self.rule = rule
    }

    func processPose(_ joints: [HumanBodyPoseObservation.PoseJointName: Joint]) {
        let update = rule.evaluate(joints: joints, currentRepCount: currentReps)
        currentPhase = update.phase
        lastDebugMessage = update.debugMessage

        if update.didIncrementRep {
            currentReps += 1
        }
    }

    func reset() {
        currentReps = 0
        currentPhase = "idle"
        lastDebugMessage = "Counter reset"
        rule.reset()
    }
}
