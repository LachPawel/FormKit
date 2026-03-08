// HandstandSkeletonView.swift
// Skeleton overlay for the wall-handstand screen.
// Each bone segment is drawn green when aligned, red when off.
// Segment names match HandstandAnalyzer:
//   Arms, Torso, Thighs, Shins  – vertical alignment
//   ArmsStraight                 – elbow lockout
//   HeadDown                     – head below hips
//   WristsBelowHead              – hands on floor

import SwiftUI
import Vision

struct HandstandSkeletonView: View {
    @ObservedObject var poseEstimator: HandstandPoseEstimator
    var size: CGSize

    var body: some View {
        if !poseEstimator.bodyParts.isEmpty {
            HandstandBones(
                bodyParts: poseEstimator.bodyParts,
                alignment: poseEstimator.alignment,
                size: size
            )
        }
    }
}

// MARK: - Bones

private struct HandstandBones: View {
    let bodyParts: [HumanBodyPoseObservation.PoseJointName: Joint]
    let alignment: HandstandAlignment
    let size: CGSize

    private var sc: [String: Color] {
        var map: [String: Color] = [:]
        for seg in alignment.segments {
            map[seg.name] = Color.forQuality(seg.quality)
        }
        return map
    }

    var body: some View {
        let c = sc
        ZStack {
            // ── Arms: wrist → elbow → shoulder ──────────────────────────
            // Colour = Arms (vertical) + ArmsStraight (elbow lockout) — use worse of the two
            let armsColor = worstColor(c["Arms"], c["ArmsStraight"])

            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftWrist, .leftElbow, .leftShoulder],
                          color: armsColor)
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.rightWrist, .rightElbow, .rightShoulder],
                          color: armsColor)
            // shoulder crossbar
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftShoulder, .rightShoulder],
                          color: armsColor)

            // ── Torso: shoulder → hip ────────────────────────────────────
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftShoulder, .leftHip],
                          color: c["Torso"] ?? .badRed)
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.rightShoulder, .rightHip],
                          color: c["Torso"] ?? .badRed)
            // hip crossbar
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftHip, .rightHip],
                          color: c["Torso"] ?? .badRed)

            // ── Thighs: hip → knee ───────────────────────────────────────
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftHip, .leftKnee],
                          color: c["Thighs"] ?? .badRed)
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.rightHip, .rightKnee],
                          color: c["Thighs"] ?? .badRed)

            // ── Shins: knee → ankle ──────────────────────────────────────
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.leftKnee, .leftAnkle],
                          color: c["Shins"] ?? .badRed)
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.rightKnee, .rightAnkle],
                          color: c["Shins"] ?? .badRed)

            // ── Head stem: nose indicator ────────────────────────────────
            // Draw a line from neck/shoulder midpoint down to nose, colored by HeadDown
            HandstandBone(bodyParts: bodyParts, size: size,
                          joints: [.neck, .nose],
                          color: c["HeadDown"] ?? .badRed, lineWidth: 5)

            // ── Joint dots ───────────────────────────────────────────────
            HandstandJoints(bodyParts: bodyParts, alignment: alignment, size: size)
        }
    }

    /// Returns the worst colour of the two: bad > close > good.
    private func worstColor(_ a: Color?, _ b: Color?) -> Color {
        let rank: (Color?) -> Int = {
            if $0 == .badRed    { return 2 }
            if $0 == .closeYellow { return 1 }
            return 0
        }
        let resolved = [a, b].compactMap { $0 }
        guard !resolved.isEmpty else { return .badRed }
        return resolved.max(by: { rank($0) < rank($1) }) ?? .badRed
    }
}

// MARK: - Single bone path

private struct HandstandBone: View {
    let bodyParts: [HumanBodyPoseObservation.PoseJointName: Joint]
    let size: CGSize
    let joints: [HumanBodyPoseObservation.PoseJointName]
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        let validPts = joints.compactMap { name -> CGPoint? in
            guard let j = bodyParts[name], j.confidence > 0.3 else { return nil }
            return convert(j.cgPoint)
        }
        guard validPts.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            Path { path in
                path.move(to: validPts[0])
                for pt in validPts.dropFirst() { path.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.7), radius: 6)
        )
    }

    private func convert(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
    }
}

// MARK: - Joint dots

private struct HandstandJoints: View {
    let bodyParts: [HumanBodyPoseObservation.PoseJointName: Joint]
    let alignment: HandstandAlignment
    let size: CGSize

    // Each joint maps to the primary segment that governs its colour.
    // Arms + ArmsStraight both affect arm joints — worstColor is applied in HandstandBones above;
    // here we just use Arms as the colour key for arm joints so they stay in sync.
    private static let jointSegment: [HumanBodyPoseObservation.PoseJointName: String] = [
        .leftWrist:    "Arms",   .rightWrist:    "Arms",
        .leftElbow:    "Arms",   .rightElbow:    "Arms",
        .leftShoulder: "Arms",   .rightShoulder: "Arms",
        .neck:         "Torso",  .root:          "Torso",
        .leftHip:      "Torso",  .rightHip:      "Torso",
        .leftKnee:     "Thighs", .rightKnee:     "Thighs",
        .leftAnkle:    "Shins",  .rightAnkle:    "Shins",
        .nose:         "HeadDown",
    ]

    private static let visibleJoints: [HumanBodyPoseObservation.PoseJointName] = [
        .nose,
        .leftShoulder, .rightShoulder,
        .leftElbow,    .rightElbow,
        .leftWrist,    .rightWrist,
        .leftHip,      .rightHip,
        .leftKnee,     .rightKnee,
        .leftAnkle,    .rightAnkle,
        .root,
    ]

    private var segmentColorMap: [String: Color] {
        var map = Dictionary(uniqueKeysWithValues: alignment.segments.map {
            ($0.name, Color.forQuality($0.quality))
        })
        // ArmsStraight demotes arm joint colour to the worse of the two
        if let armsColor = map["Arms"], let straightColor = map["ArmsStraight"] {
            let rank: (Color) -> Int = { $0 == .badRed ? 2 : $0 == .closeYellow ? 1 : 0 }
            map["Arms"] = rank(armsColor) >= rank(straightColor) ? armsColor : straightColor
        }
        return map
    }

    var body: some View {
        let colorMap = segmentColorMap
        ZStack {
            ForEach(Self.visibleJoints, id: \.self) { name in
                if let joint = bodyParts[name], joint.confidence > 0.3 {
                    let pt = convert(joint.cgPoint)
                    let segName = Self.jointSegment[name] ?? "Arms"
                    let color = colorMap[segName] ?? .badRed
                    let isNose = name == .nose
                    let size: CGFloat = isNose ? 14 : 12

                    Circle()
                        .fill(Color.white)
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(color, lineWidth: 2.5))
                        .shadow(color: color.opacity(0.8), radius: isNose ? 8 : 4)
                        .position(pt)
                }
            }
        }
    }

    private func convert(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
    }
}

// MARK: - Semantic colours

private extension Color {
    static let goodGreen    = Color(red: 0.18, green: 1.0,  blue: 0.45)
    static let closeYellow  = Color(red: 1.0,  green: 0.85, blue: 0.0)
    static let badRed       = Color(red: 1.0,  green: 0.25, blue: 0.25)

    static func forQuality(_ q: AlignmentQuality) -> Color {
        switch q {
        case .good:  return .goodGreen
        case .close: return .closeYellow
        case .bad:   return .badRed
        }
    }
}
