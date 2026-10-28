import AVFoundation
import CoreVideo
import XCTest
@testable import Vids

/// Writes small test videos with AVAssetWriter, so the repository needs no
/// binary fixtures.
enum Fixtures {
    /// Gives the player windows empty settings of their own, so the tests
    /// neither read nor change yours.
    @MainActor
    static func emptySettings() {
        let suite = "com.ivanjlm.vids.tests"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        PlayerWindowController.defaults = UserDefaults(suiteName: suite)!
    }

    static func folder(_ test: XCTestCase) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VidsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// A `seconds`-long H.264 video at 10 frames per second, `width`×`height`
    /// pixels as stored, shown with `transform` (a phone video turned upright,
    /// for example).
    static func video(in folder: URL, name: String = "clip.mp4", width: Int = 160, height: Int = 90, seconds: Int = 1,
                      transform: CGAffineTransform = .identity, codec: AVVideoCodecType = .h264) async throws -> URL {
        let url = folder.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: name.hasSuffix(".mov") ? .mov : .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(10 * seconds) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 25 % 256), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
