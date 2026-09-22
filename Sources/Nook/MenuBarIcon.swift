import AppKit

/// The menu bar icon: the app icon's booth, an arch with a stool under it,
/// reduced to lines.
///
/// Drawn in code rather than kept in the asset catalog: the catalog belongs to
/// the Xcode build only, and a `swift run` would be left with a blank menu bar
/// item. A template image, so macOS tints it for the menu bar's appearance.
enum MenuBarIcon {
    static let image: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.set()

            let width = side * 0.72, left = (side - width) / 2
            let bottom = side * 0.06, top = side * 0.94
            let arch = NSBezierPath()
            arch.move(to: NSPoint(x: left, y: bottom))
            arch.line(to: NSPoint(x: left, y: top - width / 2))
            arch.appendArc(
                withCenter: NSPoint(x: side / 2, y: top - width / 2), radius: width / 2,
                startAngle: 180, endAngle: 0, clockwise: true
            )
            arch.line(to: NSPoint(x: left + width, y: bottom))
            arch.lineWidth = side * 0.1
            arch.stroke()

            // The stool: a seat and two legs.
            NSBezierPath(
                roundedRect: NSRect(x: side * 0.34, y: side * 0.36, width: side * 0.32, height: side * 0.08),
                xRadius: side * 0.04, yRadius: side * 0.04
            ).fill()
            NSBezierPath(rect: NSRect(x: side * 0.37, y: bottom, width: side * 0.065, height: side * 0.32)).fill()
            NSBezierPath(rect: NSRect(x: side * 0.565, y: bottom, width: side * 0.065, height: side * 0.32)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nook"
        return image
    }()
}
