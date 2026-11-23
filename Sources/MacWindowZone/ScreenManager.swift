import AppKit
import CoreGraphics

enum ScreenManager {
    /// A reasonably stable identifier across launches. Uses the display's
    /// CGDirectDisplayID converted to its persistent UUID when available.
    static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) {
                let uuid = uuidRef.takeRetainedValue()
                return CFUUIDCreateString(nil, uuid) as String
            }
            return "display-\(displayID)"
        }
        return screen.localizedName
    }

    static func screen(for id: String) -> NSScreen? {
        NSScreen.screens.first { identifier(for: $0) == id }
    }

    /// The area zones and snaps are laid out in, in *Cocoa* coordinates: the
    /// whole display minus the menu bar. Deliberately ignores the Dock — macOS
    /// moves it to whichever display the cursor last pushed against the
    /// bottom of, so `visibleFrame` shrinks and grows under us and zones would
    /// change size with it. The Dock never sits at the top, so the top of
    /// `visibleFrame` is the menu bar edge (or the display edge if hidden).
    static func zoneFrame(for screen: NSScreen) -> CGRect {
        // A cached NSScreen can hold stale geometry; prefer the live instance.
        let id = identifier(for: screen)
        let live = NSScreen.screens.first { identifier(for: $0) == id } ?? screen
        let frame = live.frame
        let top = min(live.visibleFrame.maxY, frame.maxY)
        return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: top - frame.minY)
    }

    /// Space the Dock reserves right now on whichever display hosts it
    /// (all zero when it is auto-hidden). Only `left`, `bottom`, `right` are used.
    static func currentDockInsets() -> NSEdgeInsets {
        var best = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        for screen in NSScreen.screens {
            let zf = zoneFrame(for: screen)
            let vf = screen.visibleFrame
            let insets = NSEdgeInsets(
                top: 0,
                left: max(0, vf.minX - zf.minX),
                bottom: max(0, vf.minY - zf.minY),
                right: max(0, zf.maxX - vf.maxX)
            )
            if insets.left + insets.bottom + insets.right > best.left + best.bottom + best.right {
                best = insets
            }
        }
        return best
    }

    /// Convert a Cocoa rect to AX/Quartz coordinates (origin top-left, y inverted
    /// relative to the *primary* screen, which is `NSScreen.screens.first`).
    static func cocoaToAX(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenContaining(point: NSPoint) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return hit }
        // CGRect.contains is max-exclusive, so the outer pixel of the last
        // display (where the cursor actually rests) would otherwise miss.
        return NSScreen.screens.first(where: { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x <= frame.maxX &&
                   point.y >= frame.minY && point.y <= frame.maxY
        }) ?? NSScreen.main
    }
}
