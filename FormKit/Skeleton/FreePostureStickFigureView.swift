//
//  FreePostureStickFigureView.swift
//
//  Enhanced skeleton visualization with better aesthetics
//

import SwiftUI
import Vision

struct FreePostureStickFigureView: View {
    @ObservedObject var poseEstimator: PoseEstimator
    var size: CGSize

    private let skeletonColor: Color = Color(red: 117/255, green: 255/255, blue: 158/255)
    private let jointColor: Color = .white

    var body: some View {
        if !poseEstimator.bodyParts.isEmpty {
            ZStack {
                SkeletonBones(
                    bodyParts: poseEstimator.bodyParts,
                    size: size,
                    color: skeletonColor
                )

                SkeletonJoints(
                    bodyParts: poseEstimator.bodyParts,
                    size: size,
                    jointColor: jointColor,
                    highlightColor: skeletonColor
                )
            }
        }
    }
}

// MARK: - Skeleton Bones
struct SkeletonBones: View {
    let bodyParts: [HumanBodyPoseObservation.PoseJointName: Joint]
    let size: CGSize
    let color: Color
    
    var body: some View {
        ZStack {
            // Spine (root to neck to nose)
            drawPolyBone(from: .root, through: [.neck], to: .nose, lineWidth: 6)
            
            // Right arm
            drawPolyBone(from: .neck, through: [.rightShoulder, .rightElbow], to: .rightWrist, lineWidth: 5)
            
            // Left arm
            drawPolyBone(from: .neck, through: [.leftShoulder, .leftElbow], to: .leftWrist, lineWidth: 5)
            
            // Right leg
            drawPolyBone(from: .root, through: [.rightHip, .rightKnee], to: .rightAnkle, lineWidth: 5.5)
            
            // Left leg
            drawPolyBone(from: .root, through: [.leftHip, .leftKnee], to: .leftAnkle, lineWidth: 5.5)
            
            // Shoulders connection
            drawSimpleBone(from: .rightShoulder, to: .leftShoulder, lineWidth: 4)
            
            // Hips connection
            drawSimpleBone(from: .rightHip, to: .leftHip, lineWidth: 4)
        }
    }
    
    private func drawPolyBone(
        from start: HumanBodyPoseObservation.PoseJointName,
        through middle: [HumanBodyPoseObservation.PoseJointName] = [],
        to end: HumanBodyPoseObservation.PoseJointName,
        lineWidth: CGFloat = 5
    ) -> some View {
        // Collect points first
        let startJoint = bodyParts[start]
        let endJoint = bodyParts[end]
        let middleJoints = middle.compactMap { bodyParts[$0] }
        
        // Check if we have valid joints
        let hasValidJoints = (startJoint?.confidence ?? 0) > 0.3 &&
                            (endJoint?.confidence ?? 0) > 0.3
        
        return Group {
            if hasValidJoints,
               let start = startJoint,
               let end = endJoint {
                
                Path { path in
                    let startPoint = convertPoint(start.cgPoint)
                    path.move(to: startPoint)
                    
                    // Add middle points
                    for joint in middleJoints where joint.confidence > 0.3 {
                        path.addLine(to: convertPoint(joint.cgPoint))
                    }
                    
                    // Add end point
                    path.addLine(to: convertPoint(end.cgPoint))
                }
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.9), color],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 0)
            }
        }
    }
    
    @ViewBuilder
    private func drawSimpleBone(
        from start: HumanBodyPoseObservation.PoseJointName,
        to end: HumanBodyPoseObservation.PoseJointName,
        lineWidth: CGFloat = 5
    ) -> some View {
        if let startJoint = bodyParts[start],
           let endJoint = bodyParts[end],
           startJoint.confidence > 0.3,
           endJoint.confidence > 0.3 {
            
            let startPoint = convertPoint(startJoint.cgPoint)
            let endPoint = convertPoint(endJoint.cgPoint)
            
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(
                LinearGradient(
                    colors: [color.opacity(0.9), color],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 0)
        }
    }
    
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        // Convert normalized coordinates to view coordinates
        // Note: Vision coordinates are normalized (0-1) and need to be flipped vertically
        return CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}

// MARK: - Skeleton Joints
struct SkeletonJoints: View {
    let bodyParts: [HumanBodyPoseObservation.PoseJointName: Joint]
    let size: CGSize
    let jointColor: Color
    let highlightColor: Color
    
    // Define which joints to show as circles
    private let visibleJoints: [HumanBodyPoseObservation.PoseJointName] = [
        .nose,
        .neck,
        .rightShoulder, .leftShoulder,
        .rightElbow, .leftElbow,
        .rightWrist, .leftWrist,
        .rightHip, .leftHip,
        .rightKnee, .leftKnee,
        .rightAnkle, .leftAnkle,
        .root
    ]
    
    // Define important joints that should be larger
    private let majorJoints: Set<HumanBodyPoseObservation.PoseJointName> = [
        .neck, .root,
        .rightShoulder, .leftShoulder,
        .rightHip, .leftHip,
        .rightKnee, .leftKnee
    ]
    
    var body: some View {
        ZStack {
            ForEach(visibleJoints, id: \.self) { jointName in
                if let joint = bodyParts[jointName], joint.confidence > 0.3 {
                    let point = convertPoint(joint.cgPoint)
                    let isMajor = majorJoints.contains(jointName)
                    let radius: CGFloat = isMajor ? 8 : 6
                    
                    // Outer glow
                    Circle()
                        .fill(highlightColor.opacity(0.3))
                        .frame(width: radius * 2.5, height: radius * 2.5)
                        .position(point)
                        .blur(radius: 2)
                    
                    // Joint circle with border
                    ZStack {
                        Circle()
                            .fill(jointColor)
                            .frame(width: radius * 2, height: radius * 2)
                        
                        Circle()
                            .stroke(highlightColor, lineWidth: 2)
                            .frame(width: radius * 2, height: radius * 2)
                    }
                    .position(point)
                    .shadow(color: highlightColor.opacity(0.6), radius: 3, x: 0, y: 0)
                    
                    // Add confidence indicator for debugging (optional)
                    if joint.confidence < 0.5 {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            .frame(width: radius * 3, height: radius * 3)
                            .position(point)
                    }
                }
            }
        }
    }
    
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}

// MARK: - Enhanced Stick Shape (for fallback)
struct EnhancedStick: Shape {
    var points: [CGPoint]
    var size: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        guard points.count >= 2 else { return path }
        
        // Convert points to view coordinates
        let convertedPoints = points.map { point in
            CGPoint(
                x: point.x * size.width,
                y: (1 - point.y) * size.height
            )
        }
        
        path.move(to: convertedPoints[0])
        
        // Create smooth curves through points
        if convertedPoints.count == 2 {
            path.addLine(to: convertedPoints[1])
        } else {
            for i in 1..<convertedPoints.count {
                let controlPoint = CGPoint(
                    x: (convertedPoints[i-1].x + convertedPoints[i].x) / 2,
                    y: (convertedPoints[i-1].y + convertedPoints[i].y) / 2
                )
                path.addQuadCurve(to: convertedPoints[i], control: controlPoint)
            }
        }
        
        return path
    }
}

// MARK: - Joint Location Extension
extension Joint {
    var cgPoint: CGPoint {
        CGPoint(x: self.location.x, y: self.location.y)
    }
}
