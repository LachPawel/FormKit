// HandstandAnalyzer.swift
// Analyses whether the body is straight in a SIDE-VIEW wall handstand.
//
// ── Setup ────────────────────────────────────────────────────────────────────
//   • Phone is placed to the LEFT or RIGHT of the user, in portrait orientation.
//   • The user faces the wall, inverted, with head at the bottom and feet at top.
//
// ── Vision coordinate system (normalised, origin bottom-left) ────────────────
//   Feet / ankles  →  HIGH y  (top of frame,  y ≈ 1.0)
//   Hips           →  mid-high y
//   Shoulders      →  mid-low  y
//   Head / nose    →  LOW y   (near floor,    y ≈ 0.1–0.2)
//   Wrists / hands →  LOWEST y (on the floor, y < nose.y)
//
// ── Checks ───────────────────────────────────────────────────────────────────
//   1. Body vertical      – every segment deviates < toleranceDeg from vertical
//   2. Head below hips    – nose.y  <  hipMid.y   (inverted position confirmed)
//   3. Arms straight      – elbow angle ≈ 180 °   (locked-out arms)
//   4. Wrists below head  – wristMid.y < nose.y   (hands on floor, below head)
//
// ── Side-view note ───────────────────────────────────────────────────────────
//   From a profile angle Vision may detect both left & right joints stacked
//   on top of each other, or only the near side.  We use bilateral midpoints
//   where both sides fire, and fall back to whichever single side is visible.

import Foundation
import Vision
import CoreGraphics

// MARK: - Public types

/// Three-level quality rating for a single segment or the whole pose.
enum AlignmentQuality {
    case good    // green  — within tight tolerance
    case close   // yellow — within loose tolerance, nearly there
    case bad     // red    — clearly out of alignment
}

/// Alignment result for a single check.
struct SegmentAlignment {
    let name: String
    /// Deviation from the ideal in degrees (0 = perfect).
    let deviationDeg: Double
    /// Three-level quality for this segment.
    let quality: AlignmentQuality
    /// Convenience: true when quality == .good
    var isAligned: Bool { quality == .good }
}

/// Full alignment snapshot for one pose frame.
struct HandstandAlignment {
    let segments: [SegmentAlignment]
    /// True only when every segment is .good.
    let isFullyAligned: Bool
    /// True when every segment is .good or .close (no .bad).
    let isNearlyAligned: Bool
    /// Human-readable description of what is wrong (empty when aligned).
    let feedbackMessage: String
    /// Overall lateral deviation of the whole body from vertical.
    let overallDeviationDeg: Double
}

// MARK: - Analyzer

struct HandstandAnalyzer {
    /// Tight tolerance — segments within this are GREEN (good form).
    var goodTolerance: Double  = 28.0
    /// Loose tolerance — segments within this are YELLOW (close enough, minor tweak needed).
    var closeTolerance: Double = 50.0
    /// Max degrees the elbow may deviate from 180° for a green rating.
    var elbowGoodTolerance: Double  = 32.0
    var elbowCloseTolerance: Double = 52.0
    /// Minimum Vision confidence for a joint to be used.
    var minConfidence: Float = 0.30

    func analyse(
        joints: [HumanBodyPoseObservation.PoseJointName: Joint]
    ) -> HandstandAlignment {

        // ── helpers ──────────────────────────────────────────────────────────
        func pt(_ name: HumanBodyPoseObservation.PoseJointName) -> CGPoint? {
            guard let j = joints[name], j.confidence >= minConfidence else { return nil }
            return CGPoint(x: j.location.x, y: j.location.y)
        }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        func bilateral(
            _ left: HumanBodyPoseObservation.PoseJointName,
            _ right: HumanBodyPoseObservation.PoseJointName
        ) -> CGPoint? {
            switch (pt(left), pt(right)) {
            case let (l?, r?): return mid(l, r)
            case let (l?, nil): return l
            case let (nil, r?): return r
            default: return nil
            }
        }

        func angleFromVertical(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            guard abs(dx) > 1e-6 || abs(dy) > 1e-6 else { return 0 }
            return atan2(abs(dx), abs(dy)) * 180 / .pi
        }

        func angleAtJoint(a: CGPoint, vertex: CGPoint, b: CGPoint) -> Double {
            let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
            let v2 = CGPoint(x: b.x - vertex.x, y: b.y - vertex.y)
            let dot = v1.x * v2.x + v1.y * v2.y
            let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
            let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
            guard mag1 > 1e-6, mag2 > 1e-6 else { return 180 }
            return acos(max(-1, min(1, dot / (mag1 * mag2)))) * 180 / .pi
        }

        func verticalQuality(_ dev: Double) -> AlignmentQuality {
            if dev <= goodTolerance  { return .good  }
            if dev <= closeTolerance { return .close }
            return .bad
        }

        // ── derive centre-line points ────────────────────────────────────────
        let wristPt    = bilateral(.leftWrist,    .rightWrist)
        let elbowPt    = bilateral(.leftElbow,    .rightElbow)
        let shoulderPt = bilateral(.leftShoulder, .rightShoulder)
        let hipPt      = bilateral(.leftHip,      .rightHip)
        let kneePt     = bilateral(.leftKnee,     .rightKnee)
        let anklePt    = bilateral(.leftAnkle,    .rightAnkle)
        let nosePt     = pt(.nose)

        // ── HARD GATE: body must be inverted ─────────────────────────────────
        // In Vision coords y=0 is bottom, y=1 is top of frame.
        // When upright:   ankles.y < hips.y  (ankles lower in frame)
        // When inverted:  ankles.y > hips.y  (feet above hips, near top of frame)
        // If this gate fails we return immediately — no segment checks run.
        guard let anklePtGate = anklePt, let hipPtGate = hipPt,
              anklePtGate.y > hipPtGate.y + 0.05 else {
            return HandstandAlignment(
                segments: [],
                isFullyAligned: false,
                isNearlyAligned: false,
                feedbackMessage: "Get inverted first – feet must be above hips",
                overallDeviationDeg: 0
            )
        }

        var segments: [SegmentAlignment] = []
        var messages: [String] = []

        // ── 1. Vertical alignment ────────────────────────────────────────────
        func addVertical(name: String, from a: CGPoint?, to b: CGPoint?) {
            guard let a, let b else { return }
            let dev = angleFromVertical(a, b)
            let q   = verticalQuality(dev)
            segments.append(SegmentAlignment(name: name, deviationDeg: dev, quality: q))
            if q == .bad   { messages.append("\(name) tilted \(Int(dev))°") }
        }

        addVertical(name: "Arms",   from: wristPt,    to: shoulderPt)
        addVertical(name: "Torso",  from: shoulderPt, to: hipPt)
        addVertical(name: "Thighs", from: hipPt,      to: kneePt)
        addVertical(name: "Shins",  from: kneePt,     to: anklePt)

        // ── 2. Head below hips ───────────────────────────────────────────────
        if let nose = nosePt, let hip = hipPt {
            let headBelowHips = nose.y < hip.y
            let dev = headBelowHips ? 0.0 : abs(nose.y - hip.y) * 100
            let q: AlignmentQuality = headBelowHips ? .good : .bad
            segments.append(SegmentAlignment(name: "HeadDown", deviationDeg: dev, quality: q))
            if !headBelowHips { messages.append("Head not below hips – are you inverted?") }
        }

        // ── 3. Arms straight (elbow angle ≈ 180°) ────────────────────────────
        func elbowQuality(
            wristName: HumanBodyPoseObservation.PoseJointName,
            elbowName: HumanBodyPoseObservation.PoseJointName,
            shoulderName: HumanBodyPoseObservation.PoseJointName
        ) -> (AlignmentQuality, Double)? {
            guard let w = pt(wristName), let e = pt(elbowName), let s = pt(shoulderName) else { return nil }
            let bend = 180 - angleAtJoint(a: w, vertex: e, b: s)
            let q: AlignmentQuality
            if bend <= elbowGoodTolerance  { q = .good  }
            else if bend <= elbowCloseTolerance { q = .close }
            else { q = .bad }
            return (q, bend)
        }

        let leftElbowResult  = elbowQuality(wristName: .leftWrist,  elbowName: .leftElbow,  shoulderName: .leftShoulder)
        let rightElbowResult = elbowQuality(wristName: .rightWrist, elbowName: .rightElbow, shoulderName: .rightShoulder)

        if let (q, dev) = leftElbowResult ?? rightElbowResult {
            segments.append(SegmentAlignment(name: "ArmsStraight", deviationDeg: dev, quality: q))
            if q == .bad { messages.append("Bend in elbows – straighten your arms") }
        }

        // ── 4. Wrists below head ─────────────────────────────────────────────
        if let wrist = wristPt, let nose = nosePt {
            let ok = wrist.y < nose.y
            let dev = ok ? 0.0 : abs(wrist.y - nose.y) * 100
            let q: AlignmentQuality = ok ? .good : .bad
            segments.append(SegmentAlignment(name: "WristsBelowHead", deviationDeg: dev, quality: q))
            if !ok { messages.append("Hands should be below your head") }
        }

        // ── Overall banana check ─────────────────────────────────────────────
        var overallDev: Double = 0
        if let top = wristPt ?? shoulderPt, let bottom = anklePt ?? kneePt {
            overallDev = angleFromVertical(top, bottom)
            if overallDev > closeTolerance + 4, messages.isEmpty {
                messages.append("Body curved – engage your core")
            }
        }

        // ── Decision ─────────────────────────────────────────────────────────
        guard !segments.isEmpty else {
            return HandstandAlignment(
                segments: [],
                isFullyAligned: false,
                isNearlyAligned: false,
                feedbackMessage: "Cannot see your body – position the camera to the side",
                overallDeviationDeg: 0
            )
        }

        let worstQuality = segments.map(\.quality).max { a, b in
            // bad > close > good
            let rank: (AlignmentQuality) -> Int = { $0 == .bad ? 2 : $0 == .close ? 1 : 0 }
            return rank(a) < rank(b)
        } ?? .good

        let isFullyAligned  = worstQuality == .good  && overallDev <= goodTolerance + 4
        let isNearlyAligned = worstQuality != .bad   && overallDev <= closeTolerance + 4

        return HandstandAlignment(
            segments: segments,
            isFullyAligned: isFullyAligned,
            isNearlyAligned: isNearlyAligned,
            feedbackMessage: messages.joined(separator: " · "),
            overallDeviationDeg: overallDev
        )
    }
}
