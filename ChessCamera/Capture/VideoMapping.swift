import CoreGraphics

enum VideoMapping {
    /// The letterboxed video rectangle inside a view when using `.resizeAspect`.
    static func aspectFitRect(contentSize: CGSize, in bounds: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let fitted = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: (bounds.width - fitted.width) / 2,
            y: (bounds.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Maps a view point to buffer pixels, including letterbox. Returns `nil` if the point is outside the video.
    static func viewToBuffer(point: CGPoint, viewSize: CGSize, bufferSize: CGSize) -> CGPoint? {
        let videoRect = aspectFitRect(contentSize: bufferSize, in: viewSize)
        guard videoRect.width > 0, videoRect.height > 0, videoRect.contains(point) else {
            return nil
        }
        let nx = (point.x - videoRect.minX) / videoRect.width
        let ny = (point.y - videoRect.minY) / videoRect.height
        return CGPoint(x: nx * bufferSize.width, y: ny * bufferSize.height)
    }

    /// Maps a buffer-pixel point onto the letterboxed video in view coordinates.
    static func bufferToView(point: CGPoint, viewSize: CGSize, bufferSize: CGSize) -> CGPoint {
        let videoRect = aspectFitRect(contentSize: bufferSize, in: viewSize)
        guard bufferSize.width > 0, bufferSize.height > 0 else { return .zero }
        return CGPoint(
            x: videoRect.minX + (point.x / bufferSize.width) * videoRect.width,
            y: videoRect.minY + (point.y / bufferSize.height) * videoRect.height
        )
    }

    /// Maps a buffer-pixel rect onto the letterboxed video in view coordinates.
    static func bufferToView(rect: CGRect, viewSize: CGSize, bufferSize: CGSize) -> CGRect {
        let origin = bufferToView(point: rect.origin, viewSize: viewSize, bufferSize: bufferSize)
        let corner = bufferToView(
            point: CGPoint(x: rect.maxX, y: rect.maxY),
            viewSize: viewSize,
            bufferSize: bufferSize
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: corner.x - origin.x,
            height: corner.y - origin.y
        )
    }

    /// Clamps a view point to the letterboxed video rectangle.
    static func clampToVideo(point: CGPoint, viewSize: CGSize, bufferSize: CGSize) -> CGPoint {
        let videoRect = aspectFitRect(contentSize: bufferSize, in: viewSize)
        return CGPoint(
            x: min(max(point.x, videoRect.minX), videoRect.maxX),
            y: min(max(point.y, videoRect.minY), videoRect.maxY)
        )
    }
}
