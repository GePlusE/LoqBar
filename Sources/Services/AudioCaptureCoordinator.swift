import AVFoundation
import Foundation
#if canImport(ScreenCaptureKit)
import CoreMedia
import ScreenCaptureKit
#endif

@MainActor
final class AudioCaptureCoordinator {
    private var activeCapture: ActiveCaptureSession?

    func start(
        sessionID: UUID,
        mode: CaptureMode,
        recordingRootFolderPath: String,
        diagnosticKind: DiagnosticCaptureKind? = nil
    ) async throws -> ActiveCaptureSession {
        guard activeCapture == nil else {
            throw AppError.recordingStartupFailed("Another LoqBar session is already recording.")
        }

        let sessionFolder = StoragePaths.sessionRecordingFolder(rootFolderPath: recordingRootFolderPath, for: sessionID)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)

        let microphoneURL = sessionFolder.appendingPathComponent("microphone.caf")
        let microphoneRecorder: MicrophoneRecorder?
        if diagnosticKind != .systemAudioOnly {
            let recorder = MicrophoneRecorder(outputURL: microphoneURL)
            try recorder.start()
            microphoneRecorder = recorder
        } else {
            microphoneRecorder = nil
        }

        let capture: ActiveCaptureSession
        if mode == .call || diagnosticKind == .systemAudioOnly {
            do {
                let systemAudioURL = sessionFolder.appendingPathComponent("system-audio.caf")
                let screenRecorder = try await ScreenCaptureRecorder.start(outputURL: systemAudioURL)
                capture = ActiveCaptureSession(
                    sessionID: sessionID,
                    mode: mode,
                    diagnosticKind: diagnosticKind,
                    microphoneRecorder: microphoneRecorder,
                    screenRecorder: screenRecorder,
                    microphoneFileURL: microphoneRecorder == nil ? nil : microphoneURL,
                    systemAudioFileURL: systemAudioURL,
                    summary: screenRecorder.summary
                )
            } catch {
                try? microphoneRecorder?.stop()
                throw error
            }
        } else {
            capture = ActiveCaptureSession(
                sessionID: sessionID,
                mode: mode,
                diagnosticKind: diagnosticKind,
                microphoneRecorder: microphoneRecorder,
                screenRecorder: nil,
                microphoneFileURL: microphoneURL,
                systemAudioFileURL: nil,
                summary: diagnosticKind == .microphoneOnly ? "Diagnostic microphone-only recording active." : "Microphone recording active."
            )
        }

        activeCapture = capture
        return capture
    }

    func stop() async throws -> ActiveCaptureSession {
        guard var capture = activeCapture else {
            throw AppError.recordingStopFailed("No active LoqBar recording was found.")
        }

        try capture.microphoneRecorder?.stop()
        if let screenRecorder = capture.screenRecorder {
            try await screenRecorder.stop()
        }

        capture.summary = capture.stopSummary
        activeCapture = nil
        return capture
    }
}

struct ActiveCaptureSession {
    let sessionID: UUID
    let mode: CaptureMode
    let diagnosticKind: DiagnosticCaptureKind?
    let microphoneRecorder: MicrophoneRecorder?
    let screenRecorder: ScreenCaptureRecorder?
    let microphoneFileURL: URL?
    let systemAudioFileURL: URL?
    var summary: String

    var stopSummary: String {
        switch diagnosticKind {
        case .microphoneOnly:
            return "Diagnostic microphone-only test recorded to a local audio file."
        case .systemAudioOnly:
            return "Diagnostic system-audio-only test recorded to a local audio file."
        case nil:
            switch mode {
            case .localMeeting:
                return "Microphone feasibility spike recorded to a local audio file."
            case .call:
                return "Microphone and system audio feasibility spike recorded to local files."
            case .auto:
                return "Recording finished."
            }
        }
    }
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
    let summary: String

    private let stream: SCStream?
    private let streamOutput: ScreenCaptureAudioOutput?

    private init(summary: String, stream: SCStream?, streamOutput: ScreenCaptureAudioOutput?) {
        self.summary = summary
        self.stream = stream
        self.streamOutput = streamOutput
    }

    static func start(outputURL: URL) async throws -> ScreenCaptureRecorder {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AppError.callAudioCaptureUnavailable
        }

        let teamsBundleIdentifiers = ["com.microsoft.teams2", "com.microsoft.teams"]
        let teamsApp = content.applications.first { application in
            teamsBundleIdentifiers.contains(application.bundleIdentifier)
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.width = 2
        configuration.height = 2

        let streamOutput = try ScreenCaptureAudioOutput(outputURL: outputURL)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: streamOutput.queue)
        try await stream.startCapture()

        let summary = teamsApp == nil
            ? "Call capture active. System audio is streaming, but a Teams process was not detected."
            : "Call capture active. Teams was detected and ScreenCaptureKit system audio is streaming."

        return ScreenCaptureRecorder(summary: summary, stream: stream, streamOutput: streamOutput)
        #else
        throw AppError.callAudioCaptureUnavailable
        #endif
    }

    func stop() async throws {
        #if canImport(ScreenCaptureKit)
        if let stream {
            try await stream.stopCapture()
        }
        streamOutput?.finish()
        #endif
    }
}

#if canImport(ScreenCaptureKit)
private final class ScreenCaptureAudioOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "LoqBar.ScreenCaptureAudio")

    private let writer: ScreenCaptureAudioFileWriter

    init(outputURL: URL) throws {
        writer = try ScreenCaptureAudioFileWriter(outputURL: outputURL)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        writer.append(sampleBuffer)
    }

    func finish() {
        writer.finish()
    }
}

private final class ScreenCaptureAudioFileWriter {
    private let outputURL: URL
    private var audioFile: AVAudioFile?

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }

        do {
            let pcmBuffer = try makePCMBuffer(from: sampleBuffer)
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: pcmBuffer.format.settings,
                    commonFormat: pcmBuffer.format.commonFormat,
                    interleaved: pcmBuffer.format.isInterleaved
                )
            }
            try audioFile?.write(from: pcmBuffer)
        } catch {
            NSLog("LoqBar screen audio write failed: \(error.localizedDescription)")
        }
    }

    func finish() {
        audioFile = nil
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AppError.recordingStartupFailed("LoqBar could not read ScreenCaptureKit audio format details.")
        }

        guard let format = AVAudioFormat(streamDescription: streamDescription) else {
            throw AppError.recordingStartupFailed("LoqBar could not convert ScreenCaptureKit audio into an AVAudioFormat.")
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AppError.recordingStartupFailed("LoqBar could not allocate a PCM buffer for system audio.")
        }

        pcmBuffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw AppError.recordingStartupFailed("LoqBar could not copy system audio samples into a writable buffer.")
        }

        return pcmBuffer
    }
}
#endif
