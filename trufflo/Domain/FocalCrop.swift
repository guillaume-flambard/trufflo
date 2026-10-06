import CoreGraphics

/// How a photo fills a frame when the subject is not in the middle.
///
/// `scaledToFill` crops around the centre, and a phone photo of a dog almost
/// never has the dog there: on a real photo the head was cut off the top of the
/// Today portrait. The photo is scaled to cover the frame, then shifted so the
/// focus point sits at the frame's centre when it can, and never so far that
/// the frame shows empty space.
public enum FocalCrop {
    public struct Layout: Equatable, Sendable {
        /// The photo's size once scaled to cover the frame.
        public var size: CGSize
        /// Where its top left corner goes, relative to the frame's top left corner.
        public var offset: CGPoint
    }

    /// Where to aim when nothing was detected: horizontally centred, in the
    /// upper third, where the head of a pictured animal usually is.
    public static let fallbackFocus = CGPoint(x: 0.5, y: 0.35)

    /// `focus` is in the photo, from 0 to 1, `y` counted from the top.
    public static func layout(imageSize: CGSize, frame: CGSize, focus: CGPoint) -> Layout {
        guard imageSize.width > 0, imageSize.height > 0, frame.width > 0, frame.height > 0 else {
            return Layout(size: frame, offset: .zero)
        }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        func place(_ focus: CGFloat, _ scaled: CGFloat, _ available: CGFloat) -> CGFloat {
            // The photo may move left or up by at most what it overflows by.
            min(0, max(available - scaled, available / 2 - focus * scaled))
        }
        let clamped = CGPoint(x: min(max(focus.x, 0), 1), y: min(max(focus.y, 0), 1))
        return Layout(size: size,
                      offset: CGPoint(x: place(clamped.x, size.width, frame.width),
                                      y: place(clamped.y, size.height, frame.height)))
    }

    /// The point to aim at for a detected animal: its horizontal middle, and a
    /// point in the upper part of its box, since the box holds the whole body
    /// and the head is what the portrait is about. `box` is Vision's: normalized,
    /// origin at the lower left.
    public static func focus(forAnimalBox box: CGRect) -> CGPoint {
        let top = 1 - box.maxY
        return CGPoint(x: box.midX, y: top + box.height * 0.3)
    }
}
