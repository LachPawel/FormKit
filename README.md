# FormKit

> **A minimal, production-ready iOS bootstrap for building vision-based fitness apps.**

---

## ⚠️ USE AT YOUR OWN RISK

> **IMPORTANT — READ BEFORE USE**
>
> FormKit is an **experimental developer tool**. The pose-detection feedback it provides is based on computer-vision estimates and is **not a substitute for professional coaching, medical advice, or physiotherapy guidance**.
>
> - **Handstands and inverted exercises carry a real risk of serious injury**, including falls, wrist fractures, neck injuries, and more.
> - **Never attempt a handstand without a qualified spotter and adequate prior training.**
> - The alignment feedback (green / yellow / red skeleton) is approximate. A green skeleton does **not** mean your form is safe or correct — it only means the pose landmarks are within a programmatic tolerance.
> - The authors and contributors of FormKit **accept no liability** for any injury, loss, or damage arising from use of this software.
>
> **By using FormKit you acknowledge that you do so entirely at your own risk.**

---

FormKit wires together Apple's **Vision framework**, **AVFoundation**, and **SwiftUI** so you can go from zero to a working real-time pose-detection app in minutes — without boilerplate. Clone it, drop in your exercise logic, and ship.

---

## ✨ Features

| Feature | Details |
|---|---|
| 📷 **Live camera feed** | Front/back switchable `AVCaptureSession`, zoom controls, portrait orientation |
| 🦴 **Real-time skeleton overlay** | Glowing stick-figure drawn on top of the camera preview using SwiftUI `Path` |
| 🤸 **Human body pose detection** | Apple Vision `DetectHumanBodyPoseRequest` — 15 joints tracked at up to 30 fps |
| 🟢🟡🔴 **Three-level alignment feedback** | Green / yellow / red per body segment with configurable tolerances |
| 🔔 **Audio alerts** | `AVAudioEngine` beep (bypasses silent switch) when form breaks — with grace period |
| 🔁 **Rep counter engine** | Protocol-based `ExerciseRule` — implement one method to count any exercise |
| 🕺 **Easter eggs** | MJ hips easter egg triggers when hips are the sole alignment issue |
| 📊 **Live debug HUD** | On-screen FPS counter + joint coordinates overlay for rapid iteration |
| ⚡ **Efficient frame processing** | Processes every 3rd frame, drops late frames, avoids redundant work |
| 🔒 **Thread-safe architecture** | `@MainActor` isolation for UI, dedicated session & processing queues for capture |

---

## 📸 Demo

> Real-time pose skeleton rendered over the side camera — green when straight, yellow when close, red when off.

```
┌───────────────────────┐        ┌─────────────────────┐
│  Joints: 15  FPS: 30  │        │   STRAIGHT  ✓       │  ← green banner
│  nose  x=0.51 y=0.82  │        │   ALMOST THERE  ◎   │  ← yellow banner
│  neck  x=0.50 y=0.68  │        │   FIX POSITION      │  ← red banner
│  ...                  │        │   Torso tilted 42°   │
└───────────────────────┘        └─────────────────────┘
```

---

## 🏗️ Architecture

```
FormKit/
├── FormKitApp.swift              # App entry point
├── ContentView.swift             # Root view → HandstandView
│
├── Camera/
│   ├── CameraViewModel.swift     # AVCaptureSession lifecycle, camera switching, zoom
│   ├── CameraView.swift          # SwiftUI session-state router (loading/error/running)
│   ├── CameraPreview.swift       # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   ├── CameraViewWrapper.swift   # Convenience wrapper (session start/stop on appear)
│   ├── PoseEstimator.swift       # @MainActor Vision inference engine + FPS tracking
│   ├── ExerciseRepCounter.swift  # Protocol-driven rep-counting engine
│   ├── CIImage_Extension.swift   # CIImage → CGImage helper
│   └── CMSampleBuffer_Extension.swift  # CMSampleBuffer → CGImage helper
│
├── Handstand/                    # 🤸 Wall handstand trainer feature
│   ├── HandstandView.swift       # Main screen: camera + skeleton + controls + banner
│   ├── HandstandPoseEstimator.swift  # Subclass that publishes HandstandAlignment
│   ├── HandstandAnalyzer.swift   # Alignment engine: 4 vertical segments + 3 extra checks
│   ├── HandstandSkeletonView.swift   # Per-segment green/yellow/red skeleton overlay
│   ├── BeepController.swift      # AVAudioEngine beep — plays through silent switch
│   ├── MichaelEasterEgg.swift    # 🕺 Easter egg: MJ hips video when hips are off
│   └── MichaelHips.mp4           # The clip itself
│
├── Skeleton/
│   ├── FreePostureStickFigureView.swift  # SwiftUI skeleton overlay (bones + joints)
│   └── Stick.swift               # Generic polyline Shape (coordinate flip helper)
│
└── Views/
    └── PoseDetectionView.swift   # Debug screen: camera + skeleton + coordinate HUD
```

### Data flow

```
AVCaptureSession  (back camera, side profile view)
    │  (sample buffer, every 3rd frame)
    ▼
HandstandPoseEstimator     ← nonisolated AVCaptureVideoDataOutputSampleBufferDelegate
    │  DetectHumanBodyPoseRequest (Vision)
    │  publishes bodyParts [@MainActor]
    │  pipes through HandstandAnalyzer
    │  publishes alignment: HandstandAlignment
    ▼
HandstandAlignment
    ├── segments[]          per-segment AlignmentQuality (.good / .close / .bad)
    ├── isFullyAligned      all segments .good  → green
    ├── isNearlyAligned     no segment .bad     → yellow
    └── feedbackMessage     human-readable hint
    ▼
HandstandView  ← @StateObject, redraws on each publish
    ├── CameraView                  (live preview)
    ├── HandstandSkeletonView       (green/yellow/red bones)
    ├── statusBanner                (STRAIGHT / ALMOST THERE / FIX POSITION)
    ├── BeepController              (beeps when isNearlyAligned is false)
    └── EasterEggController         (MJ video when hips are the sole issue for 2 s)
```

---

## 🤸 Wall Handstand Trainer

The built-in app is a wall handstand alignment trainer. Place your phone to your **left or right** side in portrait orientation, kick up, and the skeleton turns green when you're straight.

### Setup
1. Place the phone on the floor **to your side**, propped up in portrait so the lens faces you
2. Use the **−** zoom button to zoom out until your full body fits in frame
3. Kick up into your handstand
4. The banner at the **bottom of the screen** (nearest your head) tells you your status

### Checks performed
| Check | What it measures |
|---|---|
| **Arms** | Wrist → shoulder line is vertical (±28° green, ±50° yellow) |
| **Torso** | Shoulder → hip line is vertical |
| **Thighs** | Hip → knee line is vertical |
| **Shins** | Knee → ankle line is vertical |
| **HeadDown** | Nose is below hips — confirms you're actually inverted |
| **ArmsStraight** | Elbow angle ≈ 180° — arms locked out |
| **WristsBelowHead** | Hands on floor, below your head |

### Easter egg 🕺
If your hips are the **only** thing stopping a perfect handstand, and you hold that position for 2 seconds, Michael Jackson will appear upside-down to show you how it's done. There is a 5-second cooldown between appearances.

> ⚠️ Seriously though — **use at your own risk**. A green skeleton is not a safety certificate.

---

## 🚀 Getting Started

### Requirements

- **Xcode 16+**
- **iOS 17+** (uses `DetectHumanBodyPoseRequest` from the Vision v2 API)
- A **physical iPhone or iPad** — the Simulator does not provide a camera feed

### Clone & run

```bash
git clone https://github.com/your-username/FormKit.git
cd FormKit
open FormKit.xcodeproj
```

Select your device in Xcode and press **⌘R**.

> **Camera permission** — Xcode will prompt automatically on first launch. Make sure `NSCameraUsageDescription` is set in `Info.plist` (already included).

---

## 🧩 Adding Your Own Exercise

All exercise intelligence lives in one place: **`ExerciseRepCounter.swift`**.

### 1. Implement `ExerciseRule`

```swift
struct BicepCurlRule: ExerciseRule {
    let name = "Bicep Curl"
    private var phase: Phase = .down

    private enum Phase { case up, down }

    mutating func evaluate(
        joints: [HumanBodyPoseObservation.PoseJointName: Joint],
        currentRepCount: Int
    ) -> RepCounterUpdate {

        guard
            let shoulder = joints[.rightShoulder],
            let elbow    = joints[.rightElbow],
            let wrist    = joints[.rightWrist],
            shoulder.confidence > 0.5,
            elbow.confidence    > 0.5,
            wrist.confidence    > 0.5
        else {
            return RepCounterUpdate(didIncrementRep: false, phase: "tracking lost", debugMessage: "low confidence")
        }

        let angle = elbowAngle(shoulder: shoulder.location,
                               elbow:    elbow.location,
                               wrist:    wrist.location)

        switch phase {
        case .down where angle < 50:
            phase = .up
            return RepCounterUpdate(didIncrementRep: false, phase: "up", debugMessage: "angle=\(Int(angle))°")
        case .up where angle > 150:
            phase = .down
            return RepCounterUpdate(didIncrementRep: true,  phase: "down", debugMessage: "rep! angle=\(Int(angle))°")
        default:
            return RepCounterUpdate(didIncrementRep: false, phase: phase == .up ? "up" : "down", debugMessage: "angle=\(Int(angle))°")
        }
    }

    mutating func reset() { phase = .down }
}
```

### 2. Inject the rule

In **`PoseDetectionView.swift`** (or wherever you initialise `PoseEstimator`), pass your rule to the counter:

```swift
// PoseEstimator.swift — inside init()
repCounter = ExerciseRepCounter(rule: BicepCurlRule())
```

---

## 🔑 Key Components

### `HandstandAnalyzer`
Pure value-type alignment engine. Takes a joints dictionary, returns a `HandstandAlignment` with per-segment `AlignmentQuality` (`.good` / `.close` / `.bad`). Tolerances are configurable properties — tweak `goodTolerance` and `closeTolerance` to suit your skill level.

### `PoseEstimator`
`@MainActor` class conforming to `AVCaptureVideoDataOutputSampleBufferDelegate` via a `nonisolated` extension. Processes every 3rd frame, calculates live FPS, filters joints by confidence.

### `CameraViewModel`
Manages `AVCaptureSession` on a dedicated serial queue. Supports front ↔ back switching, configurable starting camera, zoom via `setZoom(factor:)`, and disables idle timer while active.

### `BeepController`
Uses `AVAudioEngine` + a synthesised sine-wave buffer — **not** `AudioServicesPlaySystemSound`, which is silenced by the ringer switch. The engine is created lazily on first beep so it never conflicts with `AVCaptureSession`
