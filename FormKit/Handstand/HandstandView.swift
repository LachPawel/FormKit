// HandstandView.swift
// Main screen for the wall-handstand trainer.
//
// Setup:
//   • Place the phone to your LEFT or RIGHT, in portrait orientation.
//   • The phone should see you from the side — full body in frame.
//   • Kick up into your handstand. The banner shows at the BOTTOM of the screen
//     which is closest to your head on the floor.
//
// Checks performed live:
//   Arms vertical + elbows locked · Torso vertical · Thighs vertical
//   Shins vertical · Head below hips · Hands below head

import SwiftUI
import AVFoundation

struct HandstandView: View {
    @StateObject private var poseEstimator: HandstandPoseEstimator
    @StateObject private var cameraViewModel: CameraViewModel
    @StateObject private var beepHolder = BeepHolder()
    @StateObject private var easterEgg = EasterEggController()

    init() {
        let estimator = HandstandPoseEstimator()
        _poseEstimator = StateObject(wrappedValue: estimator)
        _cameraViewModel = StateObject(wrappedValue: CameraViewModel(poseEstimator: estimator))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // ── Camera feed ──────────────────────────────────────────
                CameraView(viewModel: cameraViewModel)
                    .ignoresSafeArea()

                // ── Skeleton overlay ─────────────────────────────────────
                HandstandSkeletonView(poseEstimator: poseEstimator, size: geo.size)
                    .ignoresSafeArea()

                // ── Camera controls (top-right) ──────────────────────────
                VStack {
                    cameraControls
                        .padding(.top, 56)
                        .padding(.trailing, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // ── Status banner (bottom = near head when inverted) ─────
                statusBanner
                    .padding(.bottom, 48)
            }
        }
        // ── Easter egg overlay (outside GeometryReader so it's truly fullscreen) ──
        .overlay {
            MichaelEasterEggOverlay(controller: easterEgg)
                .animation(.spring(duration: 0.35), value: easterEgg.isShowing)
        }
        .onAppear {
            // Start directly on the back camera — phone sits to the side facing you
            cameraViewModel.setupSession(startingCamera: .back)
            cameraViewModel.startSession()
            // Zoom out so the full body fits in frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                cameraViewModel.setZoom(factor: 0.7)
            }
        }
        .onDisappear {
            cameraViewModel.stopSession()
            beepHolder.controller.stopAll()
        }
        // Drive beep only when pose is clearly bad (not just nearly aligned)
        .onReceive(poseEstimator.$alignment) { alignment in
            let shouldBeep = !alignment.isNearlyAligned
            beepHolder.controller.update(isAligned: !shouldBeep)
            easterEgg.considerShowing(alignment: alignment)
        }
    }

    // MARK: - Camera controls overlay

    private var cameraControls: some View {
        VStack(spacing: 12) {
            // Flip camera
            Button {
                let next: AVCaptureDevice.Position =
                    cameraViewModel.currentCameraPosition == .back ? .front : .back
                NotificationCenter.default.post(name: .switchCamera, object: next)
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .controlButton()
            }

            // Zoom in
            Button {
                cameraViewModel.setZoom(factor: cameraViewModel.zoomFactor + 0.3)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .controlButton()
            }

            // Zoom out
            Button {
                cameraViewModel.setZoom(factor: cameraViewModel.zoomFactor - 0.3)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .controlButton()
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        let aligned       = poseEstimator.alignment.isFullyAligned
        let nearly        = poseEstimator.alignment.isNearlyAligned
        let bodyEmpty     = poseEstimator.bodyParts.isEmpty

        Group {
            if bodyEmpty {
                Label("Position camera to your side", systemImage: "arrow.left.and.right.square")
                    .bannerStyle(color: .gray)
            } else if aligned {
                Label("STRAIGHT  ✓", systemImage: "checkmark.circle.fill")
                    .bannerStyle(color: Color(red: 0.18, green: 1.0, blue: 0.45))
            } else if nearly {
                Label("ALMOST THERE  ◎", systemImage: "circle.dotted")
                    .font(.headline.bold())
                    .bannerStyle(color: Color(red: 0.95, green: 0.75, blue: 0.0))
            } else {
                VStack(spacing: 4) {
                    Label("FIX POSITION", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    if !poseEstimator.alignment.feedbackMessage.isEmpty {
                        Text(poseEstimator.alignment.feedbackMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.90))
                            .multilineTextAlignment(.center)
                    }
                }
                .bannerStyle(color: Color(red: 1.0, green: 0.25, blue: 0.25))
            }
        }
    }
}

// MARK: - Beep holder

private final class BeepHolder: ObservableObject {
    let controller = BeepController()
}

// MARK: - Modifiers

private extension View {
    func bannerStyle(color: Color) -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(color.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: color.opacity(0.6), radius: 8)
    }
}

private extension Image {
    func controlButton() -> some View {
        self
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .shadow(radius: 4)
    }
}
