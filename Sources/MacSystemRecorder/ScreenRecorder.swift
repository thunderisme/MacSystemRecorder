@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenRecorder: NSObject {
    private let display: SCDisplay
    private let outputURL: URL
    private let captureSystemAudio: Bool
    private let hideCurrentApp: Bool
    private let cropRect: CGRect?

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let screenQueue = DispatchQueue(label: "MacSystemRecorder.screen")
    private let audioQueue = DispatchQueue(label: "MacSystemRecorder.audio")

    private var stream: SCStream?
    private var didStartSession = false
    private var didAppendVideo = false
    private var didFinish = false

    init(display: SCDisplay, outputURL: URL, captureSystemAudio: Bool, hideCurrentApp: Bool, cropRect: CGRect?) throws {
        self.display = display
        self.outputURL = outputURL
        self.captureSystemAudio = captureSystemAudio
        self.hideCurrentApp = hideCurrentApp
        self.cropRect = cropRect

        let videoSize = Self.videoSize(for: display, cropRect: cropRect)
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        } else {
            throw RecorderError.cannotAddVideoInput
        }

        if captureSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                audioInput = nil
            }
        } else {
            audioInput = nil
        }

        super.init()
    }

    func start() async throws {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let videoSize = Self.videoSize(for: display, cropRect: cropRect)
        configuration.width = Int(videoSize.width)
        configuration.height = Int(videoSize.height)
        if let cropRect {
            configuration.sourceRect = cropRect
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.capturesAudio = captureSystemAudio
        configuration.excludesCurrentProcessAudio = hideCurrentApp
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let nextStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try nextStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        if captureSystemAudio {
            try nextStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.couldNotStartWriter
        }

        stream = nextStream
        try await nextStream.startCapture()
    }

    func stop() async throws {
        guard !didFinish else { return }
        didFinish = true

        if let stream {
            try await stream.stopCapture()
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        let writer = writer
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, mediaType: SCStreamOutputType) {
        guard sampleBuffer.isValid,
              !didFinish,
              writer.status == .writing else {
            return
        }

        guard mediaType != .screen || sampleBuffer.isCompleteFrame else {
            return
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        if !didStartSession {
            writer.startSession(atSourceTime: presentationTime)
            didStartSession = true
        }

        switch mediaType {
        case .screen:
            if videoInput.isReadyForMoreMediaData {
                didAppendVideo = videoInput.append(sampleBuffer) || didAppendVideo
            }
        case .audio:
            guard didAppendVideo, let audioInput, audioInput.isReadyForMoreMediaData else {
                return
            }
            audioInput.append(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    private static func videoSize(for display: SCDisplay, cropRect: CGRect?) -> CGSize {
        let maxWidth: CGFloat = 3_840
        let maxHeight: CGFloat = 2_160
        let source = cropRect?.size ?? CGSize(width: display.width, height: display.height)
        let scale = min(maxWidth / source.width, maxHeight / source.height, 1)
        return CGSize(
            width: makeEven(floor(source.width * scale)),
            height: makeEven(floor(source.height * scale))
        )
    }

    private static func makeEven(_ value: CGFloat) -> CGFloat {
        max(2, value - value.truncatingRemainder(dividingBy: 2))
    }
}

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        append(sampleBuffer, mediaType: type)
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        didFinish = true
    }
}

private extension CMSampleBuffer {
    var isCompleteFrame: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRawValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return false
        }
        return status == .complete
    }
}

enum RecorderError: LocalizedError {
    case cannotAddVideoInput
    case couldNotStartWriter

    var errorDescription: String? {
        switch self {
        case .cannotAddVideoInput:
            "Could not configure the video writer."
        case .couldNotStartWriter:
            "Could not start the MP4 writer."
        }
    }
}
