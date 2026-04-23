import AVFoundation
import Foundation

@MainActor
final class AudioCaptureCoordinator {
    private var activeCapture: ActiveCaptureSession?

    func start(sessionID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        guard activeCapture == nil else {
            throw AppError.recordingStartupFailed("Another LoqBar session is already recording.")
        }

        let sessionFolder = StoragePaths.sessionRecordingFolder(for: sessionID)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)

        let microphoneURL = sessionFolder.appendingPathComponent("microphone.caf")
        let microphoneRecorder = MicrophoneRecorder(outputURL: microphoneURL)
        try microphoneRecorder.start()

        let capture = ActiveCaptureSession(
            sessionID: sessionID,
            mode: mode,
            microphoneRecorder: microphoneRecorder,
            screenRecorder: nil,
            microphoneFileURL: microphoneURL,
            systemAudioFileURL: nil,
            summary: "Microphone recording active."
        )

        activeCapture = capture
        return capture
    }

    func stop() async throws -> ActiveCaptureSession {
        guard var capture = activeCapture else {
            throw AppError.recordingStopFailed("No active LoqBar recording was found.")
        }

        try capture.microphoneRecorder.stop()
        if let screenRecorder = capture.screenRecorder {
            try await screenRecorder.stop()
        }

        capture.summary = capture.mode == .localMeeting
            ? "Microphone feasibility spike recorded to a local audio file."
            : "Microphone recording finished."
        activeCapture = nil
        return capture
    }
}

struct ActiveCaptureSession {
    let sessionID: UUID
    let mode: CaptureMode
    let microphoneRecorder: MicrophoneRecorder
    let screenRecorder: ScreenCaptureRecorder?
    let microphoneFileURL: URL
    let systemAudioFileURL: URL?
    var summary: String
}

final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var isRecording = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start() throws {
        guard !isRecording else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let fileFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        ) else {
            throw AppError.recordingStartupFailed("LoqBar could not create a valid microphone file format.")
        }

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: fileFormat.settings,
            commonFormat: fileFormat.commonFormat,
            interleaved: fileFormat.isInterleaved
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: fileFormat) { [weak self] buffer, _ in
            guard let self, let audioFile = self.audioFile else { return }
            do {
                try audioFile.write(from: buffer)
            } catch {
                NSLog("LoqBar microphone write failed: \(error.localizedDescription)")
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() throws {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
    }
}

@MainActor
final class ScreenCaptureRecorder {
    func stop() async throws {}
}
