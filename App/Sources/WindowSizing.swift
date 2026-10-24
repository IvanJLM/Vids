import CoreGraphics

/// Window size math, kept apart from AppKit so it can be tested.
enum WindowSizing {
    /// `size` scaled by `scale`, then shrunk (never grown) to fit in `bounds`,
    /// keeping its aspect ratio.
    static func fit(_ size: CGSize, scale: CGFloat = 1, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let wanted = CGSize(width: size.width * scale, height: size.height * scale)
        let shrink = min(1, bounds.width / wanted.width, bounds.height / wanted.height)
        return CGSize(width: (wanted.width * shrink).rounded(), height: (wanted.height * shrink).rounded())
    }

    /// The smallest content size: the short side at `side` points.
    static func minimum(for size: CGSize, side: CGFloat = 180) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: side, height: side) }
        return size.width >= size.height
            ? CGSize(width: (side * size.width / size.height).rounded(), height: side)
            : CGSize(width: side, height: (side * size.height / size.width).rounded())
    }

    /// `frame` resized to `size` around its own center.
    static func centered(_ size: CGSize, on frame: CGRect) -> CGRect {
        CGRect(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }
}
