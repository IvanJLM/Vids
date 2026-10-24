import AVFoundation
import UniformTypeIdentifiers

/// What Vids needs to know about a file before showing it: whether macOS can
/// play it, the size its picture is shown at, and its audio and subtitle tracks.
struct VideoInfo {
    /// Size of the picture in points at 100 %, after rotation and pixel aspect.
    /// Nil for files without video.
    var displaySize: CGSize?
    var audioTracks: AVMediaSelectionGroup?
    var subtitles: AVMediaSelectionGroup?

    static func load(_ asset: AVURLAsset) async throws -> VideoInfo {
        let (playable, tracks) = try await asset.load(.isPlayable, .tracks)
        guard playable else { throw PlaybackError.unsupportedFormat }
        var size: CGSize?
        if let track = tracks.first(where: { $0.mediaType == .video }) {
            let (trackPlayable, natural, transform, formats) = try await track.load(
                .isPlayable, .naturalSize, .preferredTransform, .formatDescriptions)
            guard trackPlayable else { throw PlaybackError.unsupportedCodec }
            size = displaySize(natural: natural, transform: transform,
                               pixelAspect: formats.first.map(pixelAspectRatio) ?? 1)
        }
        let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
        let subtitles = try? await asset.loadMediaSelectionGroup(for: .legible)
        return VideoInfo(displaySize: size, audioTracks: audio, subtitles: subtitles)
    }

    /// The stored frame size, stretched by its pixel aspect ratio (anamorphic
    /// DVDs and camcorders) and turned by its rotation (phone videos).
    static func displaySize(natural: CGSize, transform: CGAffineTransform, pixelAspect: CGFloat) -> CGSize {
        let stretched = CGRect(x: 0, y: 0, width: natural.width * pixelAspect, height: natural.height)
        let turned = stretched.applying(transform)
        return CGSize(width: abs(turned.width).rounded(), height: abs(turned.height).rounded())
    }

    private static func pixelAspectRatio(_ format: CMFormatDescription) -> CGFloat {
        guard let ratio = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio) as? [String: Any],
              let h = ratio[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? Double,
              let v = ratio[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? Double,
              h > 0, v > 0 else { return 1 }
        return CGFloat(h / v)
    }
}

/// The file types Vids opens: the ones in its Info.plist, all of which
/// AVFoundation plays natively.
enum VideoTypes {
    static let declared: [UTType] = {
        let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }.compactMap(UTType.init)
    }()
}

enum PlaybackError: LocalizedError {
    case unsupportedFormat
    case unsupportedCodec

    /// Containers people download that macOS has no player for.
    static let foreignExtensions: Set<String> = ["mkv", "webm", "wmv", "asf", "flv", "f4v", "ogv", "ogg", "rm", "rmvb", "divx", "vob"]

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "macOS can't read this file."
        case .unsupportedCodec: "macOS has no decoder for this video's codec."
        }
    }

    /// The message shown when `url` can't be played.
    static func message(for url: URL, error: Error) -> (title: String, detail: String) {
        let title = "Vids can't play “\(url.lastPathComponent)”."
        let ext = url.pathExtension.lowercased()
        if foreignExtensions.contains(ext) {
            return (title, "It is a \(ext.uppercased()) file. Vids plays the video formats built into macOS: MP4, MOV, M4V, AVI, MPEG and TS.")
        }
        return (title, error.localizedDescription)
    }
}
