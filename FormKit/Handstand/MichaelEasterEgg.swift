// MichaelEasterEgg.swift
// Shows a looping MichaelHips.mp4 overlay when the hips are the only thing
// keeping the user from a perfect handstand.
//
// Trigger conditions (all must be true):
//   • pose isNearlyAligned (not fully bad)
//   • Torso OR Thighs segment quality is .close or .bad  (hips are the culprit)
//   • all other vertical segments are .good
//   • 5-second cooldown has elapsed since last showing

import SwiftUI
import AVKit
import AVFoundation

// MARK: - Trigger logic

struct MichaelEasterEgg {
    /// Returns true when the hips are the sole alignment issue.
    static func shouldTrigger(alignment: HandstandAlignment) -> Bool {
        guard alignment.isNearlyAligned, !alignment.isFullyAligned else { return false }

        let segMap = Dictionary(uniqueKeysWithValues: alignment.segments.map { ($0.name, $0.quality) })

        // Hips-related segments must be off
        let hipsOff = (segMap["Torso"] == .close || segMap["Torso"] == .bad)
                   || (segMap["Thighs"] == .close || segMap["Thighs"] == .bad)
        guard hipsOff else { return false }

        // All other movement segments must be good
        let others = ["Arms", "Shins", "ArmsStraight"]
        let othersGood = others.allSatisfy { segMap[$0] == .good || segMap[$0] == nil }
        return othersGood
    }
}

// MARK: - Cooldown controller

final class EasterEggController: ObservableObject {
    @Published private(set) var isShowing = false

    private let cooldown: TimeInterval    = 5   // seconds between shows
    private let clipDuration: TimeInterval = 2  // video is ~2 s; hide after this
    private let dwellRequired: TimeInterval = 2 // must hold hip-off position this long
    private var lastShownAt: Date = .distantPast
    private var hideTimer: Timer?
    private var dwellTimer: Timer?              // fires after dwell period

    func considerShowing(alignment: HandstandAlignment) {
        guard !isShowing else { cancelDwell(); return }
        guard Date().timeIntervalSince(lastShownAt) >= cooldown else { cancelDwell(); return }

        if MichaelEasterEgg.shouldTrigger(alignment: alignment) {
            // Start dwell timer only if not already counting
            if dwellTimer == nil {
                dwellTimer = Timer.scheduledTimer(withTimeInterval: dwellRequired,
                                                  repeats: false) { [weak self] _ in
                    self?.dwellTimer = nil
                    self?.show()
                }
            }
        } else {
            // Condition no longer met — cancel any pending dwell
            cancelDwell()
        }
    }

    private func cancelDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    private func show() {
        lastShownAt = Date()
        withAnimation(.spring(duration: 0.35)) { isShowing = true }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: clipDuration,
                                         repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hide()
    }

    private func hide() {
        cancelDwell()
        withAnimation(.easeOut(duration: 0.25)) { isShowing = false }
    }
}

// MARK: - Video overlay view

struct MichaelEasterEggOverlay: View {
    @ObservedObject var controller: EasterEggController

    var body: some View {
        if controller.isShowing {
            ZStack {
                // Semi-transparent backdrop
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Caption
                    Text("🕺 Fix those hips, Michael!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // SinglePlayVideoPlayer creates the AVPlayer exactly once
                    // in its Coordinator and rewinds+plays when isShowing becomes true.
                    SinglePlayVideoPlayer(resourceName: "MichaelHips", fileExtension: "mp4")
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(180))
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 16)

                    Text("Straighten up! 😄")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(24)
            }
            .onTapGesture { controller.dismiss() }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }
}

// MARK: - Single-play video player

/// Plays the clip exactly once per show.
/// The AVPlayer lives in the Coordinator so it is created only once per
/// view lifetime — no duplicate instances, no leaked observers.
private struct SinglePlayVideoPlayer: UIViewControllerRepresentable {
    let resourceName: String
    let fileExtension: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        vc.player = context.coordinator.player
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Called every time SwiftUI re-renders — just restart from the beginning.
        context.coordinator.playFromStart()
    }

    final class Coordinator {
        let player: AVPlayer

        init() {
            // Build the player once; reuse it for every show.
            if let url = Bundle.main.url(forResource: "MichaelHips", withExtension: "mp4") {
                player = AVPlayer(url: url)
            } else {
                player = AVPlayer()
            }
            player.isMuted = false
        }

        func playFromStart() {
            player.seek(to: .zero) { [weak self] _ in
                self?.player.play()
            }
        }

        deinit {
            player.pause()
        }
    }
}
