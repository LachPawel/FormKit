//
//  CameraViewModel.swift
//
//  Enhanced with camera switching functionality
//

import Foundation
import SwiftUI
import AVFoundation
import Combine
import UIKit

enum CameraSessionState {
    case initializing
    case running
    case failed
}

class CameraViewModel: ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var currentCameraPosition: AVCaptureDevice.Position = .front
    @Published var sessionState: CameraSessionState = .initializing
    @Published var repCount: Int = 0
    @Published var zoomFactor: CGFloat = 1.0
    
    private let poseEstimator: PoseEstimator?
    
    var captureSession: AVCaptureSession?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInteractive)
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInteractive)
    
    private var isConfigured = false
    private var cancellables = Set<AnyCancellable>()
    private var currentCameraInput: AVCaptureDeviceInput?
    
    init(poseEstimator: PoseEstimator) {
        self.poseEstimator = poseEstimator
        sessionState = .initializing

        // Listen for camera switch notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(switchCameraNotification(_:)),
            name: .switchCamera,
            object: nil
        )
    }
    
    deinit {
        stopSession()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func switchCameraNotification(_ notification: Notification) {
        if let position = notification.object as? AVCaptureDevice.Position {
            switchCamera(to: position)
        }
    }
    
    func switchCamera(to position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            self?.performCameraSwitch(to: position)
        }
    }
    
    private func performCameraSwitch(to position: AVCaptureDevice.Position) {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        // Remove current input
        if let currentInput = currentCameraInput {
            session.removeInput(currentInput)
        }
        
        // Add new camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("Failed to get camera for position: \(position)")
            session.commitConfiguration()
            return
        }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: camera)
            
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentCameraInput = newInput
                
                // Update connection settings
                if let connection = videoOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    connection.isVideoMirrored = (position == .front)
                }
                
                // Update published property on main thread
                DispatchQueue.main.async {
                    self.currentCameraPosition = position
                }
                
                print("Successfully switched to \(position == .front ? "front" : "back") camera")
            } else {
                print("Could not add new camera input")
            }
        } catch {
            print("Failed to create camera input: \(error.localizedDescription)")
        }
        
        session.commitConfiguration()
    }
    
    func setupSession(startingCamera: AVCaptureDevice.Position = .front) {
        // Mark initializing on main thread immediately so UI can react
        DispatchQueue.main.async { self.sessionState = .initializing }
        sessionQueue.async { [weak self] in
            self?.configureSession(position: startingCamera)
        }
    }

    private func configureSession(position: AVCaptureDevice.Position = .front) {
        guard !isConfigured else { return }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("Failed to get camera for position: \(position)")
            DispatchQueue.main.async { self.sessionState = .failed }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentCameraInput = input
            } else {
                print("Could not add camera input")
                DispatchQueue.main.async { self.sessionState = .failed }
                session.commitConfiguration()
                return
            }
        } catch {
            print("Failed to create camera input: \(error.localizedDescription)")
            DispatchQueue.main.async { self.sessionState = .failed }
            session.commitConfiguration()
            return
        }

        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if let poseEstimator = poseEstimator {
            videoOutput.setSampleBufferDelegate(poseEstimator, queue: processingQueue)
        }

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            print("Could not add video output")
            DispatchQueue.main.async { self.sessionState = .failed }
            session.commitConfiguration()
            return
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            connection.isVideoMirrored = (position == .front)
        }

        session.commitConfiguration()
        isConfigured = true

        // Hand fully-configured session to main thread, then start running
        DispatchQueue.main.async {
            self.captureSession = session
            self.currentCameraPosition = position
            self.sessionState = .running
            self.setupFrameCallback()
            // Start the session after captureSession is visible to startSession()
            self.sessionQueue.async {
                session.startRunning()
            }
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔋 Screen sleep disabled - camera is active")
        }
    }
    
    private func setupFrameCallback() {
        NotificationCenter.default.publisher(for: .newCameraFrame)
            .compactMap { notification -> CGImage? in
                guard let imageObject = notification.object else { return nil }
                let imageTypeID = CGImage.typeID
                guard CFGetTypeID(imageObject as CFTypeRef) == imageTypeID else {
                    print("Received unexpected object type for .newCameraFrame notification.")
                    return nil
                }
                return imageObject as! CGImage
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.currentFrame = image
            }
            .store(in: &cancellables)
    }
    
    func startSession() {
        // captureSession is set on main thread after configuration completes.
        // If it's already running (started inside configureSession), this is a no-op.
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func setZoom(factor: CGFloat) {
        guard let input = currentCameraInput else { return }
        let device = input.device
        let clamped = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = clamped }
            } catch {
                print("Zoom error: \(error)")
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, session.isRunning else { return }
            session.stopRunning()
        }
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            print("🔋 Screen sleep re-enabled - camera stopped")
        }
    }
}

// Add notification for camera switching
extension Notification.Name {
    static let newCameraFrame = Notification.Name("newCameraFrame")
    static let switchCamera = Notification.Name("switchCamera")
}
