# FormKit

> **A minimal, production-ready iOS bootstrap for building vision-based fitness apps.**

FormKit wires together Apple's **Vision framework**, **AVFoundation**, and **SwiftUI** so you can go from zero to a working real-time pose-detection app in minutes — without boilerplate. Clone it, drop in your exercise logic, and ship.

---

## ✨ Features

| Feature | Details |
|---|---|
| 📷 **Live camera feed** | Front/back switchable `AVCaptureSession` with portrait orientation and mirroring |
| 🦴 **Real-time skeleton overlay** | Glowing stick-figure drawn on top of the camera preview using SwiftUI `Path` |
| 🤸 **Human body pose detection** | Apple Vision `DetectHumanBodyPoseRequest` — 15 joints tracked at up to 30 fps |
| 🔁 **Rep counter engine** | Protocol-based `ExerciseRule` — implement one method to count any exercise |
| 📊 **Live debug HUD** | On-screen FPS counter + joint coordinates overlay for rapid iteration |
| ⚡ **Efficient frame processing** | Processes every 3rd frame, drops late frames, avoids redundant work |
| 🔒 **Thread-safe architecture** | `@MainActor` isolation for UI, dedicated session & processing queues for capture |

---

## 📸 Demo

> Real-time pose skeleton rendered over the front camera feed.

```
┌───────────────────────┐
│  Joints: 15  FPS: 30  │
│  nose  x=0.51 y=0.82  │
│  neck  x=0.50 y=0.68  │
│  ...                  │
└───────────────────────┘
         ●           ← nose
         │
    ●────●────●     ← shoulders
         │
    ●────●────●     ← elbows / wrists
         │
    ●────●────●     ← hips
         │  │
         ●  ●       ← knees
         │  │
         ●  ●       ← ankles
```

---

## 🏗️ Architecture

```
FormKit/
├── FormKitApp.swift              # App entry point
├── ContentView.swift             # Root view → PoseDetectionView
│
├── Camera/
│   ├── CameraViewModel.swift     # AVCaptureSession lifecycle, camera switching
│   ├── CameraView.swift          # SwiftUI session-state router (loading/error/running)
│   ├── CameraPreview.swift       # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   ├── CameraViewWrapper.swift   # Convenience wrapper (session start/stop on appear)
│   ├── PoseEstimator.swift       # @MainActor Vision inference engine + FPS tracking
│   ├── ExerciseRepCounter.swift  # Protocol-driven rep-counting engine
│   ├── CIImage_Extension.swift   # CIImage → CGImage helper
│   └── CMSampleBuffer_Extension.swift  # CMSampleBuffer → CGImage helper
│
├── Skeleton/
│   ├── FreePostureStickFigureView.swift  # SwiftUI skeleton overlay (bones + joints)
│   └── Stick.swift               # Generic polyline Shape (coordinate flip helper)
│
└── Views/
    └── PoseDetectionView.swift   # Main screen: camera + skeleton + debug HUD
```

### Data flow

```
AVCaptureSession
    │  (sample buffer, every 3rd frame)
    ▼
PoseEstimator          ← nonisolated AVCaptureVideoDataOutputSampleBufferDelegate
    │  DetectHumanBodyPoseRequest (Vision)
    │  publishes bodyParts [@MainActor]
    ▼
ExerciseRepCounter     ← called via $bodyParts Combine subscription
    │  ExerciseRule.evaluate(joints:)
    │  publishes currentReps, currentPhase
    ▼
PoseDetectionView      ← @StateObject, redraws on each publish
    ├── CameraView          (live preview)
    ├── FreePostureStickFigureView  (skeleton)
    └── debugOverlay        (HUD)
```

---

## 🚀 Getting Started

### Requirements

- **Xcode 16+**
- **iOS 17+** (uses `DetectHumanBodyPoseRequest` from the Vision v2 API)
- A **physical iPhone or iPad** — the Simulator does not provide a camera feed

### Clone & run

```bash
git clone https://github.com/LachPawel/FormKit.git
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

That's it. `repCounter.currentReps` and `repCounter.currentPhase` are already `@Published` and available in every view that observes `PoseEstimator`.

---

## 🔑 Key Components

### `PoseEstimator`

```
@MainActor class PoseEstimator: ObservableObject
```

- Conforms to `AVCaptureVideoDataOutputSampleBufferDelegate` via a `nonisolated` extension — safe to call from any queue
- Processes every 3rd frame to balance accuracy and battery life
- Calculates live **FPS** using `CACurrentMediaTime`
- Filters joints by `confidence > 0` before publishing

### `CameraViewModel`

```
class CameraViewModel: ObservableObject
```

- Manages `AVCaptureSession` on a dedicated serial `sessionQueue`
- Supports **front ↔ back camera switching** at runtime via `NotificationCenter` (`.switchCamera`)
- Disables the **idle timer** while the session is active to prevent screen sleep
- Exposes `sessionState: CameraSessionState` (`.initializing` / `.running` / `.failed`) for UI feedback

### `FreePostureStickFigureView`

- Draws **bones** as `Path` strokes with a `LinearGradient` and a glow `shadow`
- Draws **joints** as layered `Circle` shapes (glow + white fill + accent border)
- Low-confidence joints (`< 0.5`) show a red debug ring
- Coordinate conversion: Vision's `(0,0)` is bottom-left; the view flips Y to match UIKit

### `ExerciseRule` protocol

```swift
protocol ExerciseRule {
    var name: String { get }
    mutating func evaluate(joints: [...], currentRepCount: Int) -> RepCounterUpdate
    mutating func reset()
}
```

A value type (`struct`) is preferred so phase state is contained inside the rule.

---

## 📐 Joint Map

Apple Vision provides 19 named joints. FormKit uses the following subset:

```
             nose (●)
              │
             neck (●)
            /    \
   leftShoulder  rightShoulder
        |               |
   leftElbow       rightElbow
        |               |
   leftWrist       rightWrist

            root (●)
            /    \
    leftHip      rightHip
        |               |
   leftKnee       rightKnee
        |               |
   leftAnkle     rightAnkle
```

All joint names match `HumanBodyPoseObservation.PoseJointName` from the Vision framework.

---

## 🛡️ Privacy

Add the following key to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>FormKit uses the camera to detect your body pose in real time.</string>
```

No camera data is stored or transmitted. All inference runs **on-device** using Apple Vision.

---

## 🤝 Contributing

1. Fork the repo and create a feature branch: `git checkout -b feature/my-exercise`
2. Add your `ExerciseRule` implementation (and tests if applicable)
3. Open a pull request — please include a short screen recording if the change is visual

---

## 📄 License

MIT © Pawel Kowalewski — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

- [Apple Vision Framework](https://developer.apple.com/documentation/vision) — on-device human body pose detection
- [Apple AVFoundation](https://developer.apple.com/documentation/avfoundation) — camera capture pipeline
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) — declarative UI and reactive state management
