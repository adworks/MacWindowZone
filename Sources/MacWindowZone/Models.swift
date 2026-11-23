import Foundation
import AppKit

struct Zone: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    // Fraction-based rect (0..1) relative to `ScreenManager.zoneFrame`
    // (display minus menu bar, Dock ignored).
    // This keeps zones consistent across resolution/scale changes.
    var fractionalRect: FractionalRect

    init(id: UUID = UUID(), name: String, fractionalRect: FractionalRect) {
        self.id = id
        self.name = name
        self.fractionalRect = fractionalRect
    }

    func absoluteRect(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + fractionalRect.x * screenFrame.width,
            y: screenFrame.minY + fractionalRect.y * screenFrame.height,
            width: fractionalRect.width * screenFrame.width,
            height: fractionalRect.height * screenFrame.height
        )
    }

    /// Bounding box of `zones` in screen coordinates. Used for multi-zone
    /// drag-snap (two adjacent 2×2 cells become a half, three become fullscreen).
    static func boundingRect(of zones: [Zone], in screenFrame: CGRect) -> CGRect? {
        guard !zones.isEmpty else { return nil }
        return zones.reduce(CGRect.null) { $0.union($1.absoluteRect(in: screenFrame)) }
    }
}

struct FractionalRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let full = FractionalRect(x: 0, y: 0, width: 1, height: 1)

    static func from(absolute: CGRect, in screenFrame: CGRect) -> FractionalRect {
        guard screenFrame.width > 0, screenFrame.height > 0,
              !absolute.isNull, !absolute.isEmpty,
              absolute.width.isFinite, absolute.height.isFinite,
              absolute.minX.isFinite, absolute.minY.isFinite else { return .full }
        return FractionalRect(
            x: (absolute.minX - screenFrame.minX) / screenFrame.width,
            y: (absolute.minY - screenFrame.minY) / screenFrame.height,
            width: absolute.width / screenFrame.width,
            height: absolute.height / screenFrame.height
        )
    }
}

struct ScreenLayout: Codable {
    // Stable identifier for the screen (display UUID or fallback).
    let screenID: String
    var zones: [Zone]
    /// True once `zones` are fractions of `ScreenManager.zoneFrame`. Layouts
    /// saved before that were fractions of `visibleFrame` (which also
    /// excludes the Dock); `ZoneStore` converts them once, keeping their size.
    var dockIndependent: Bool

    init(screenID: String, zones: [Zone], dockIndependent: Bool = true) {
        self.screenID = screenID
        self.zones = zones
        self.dockIndependent = dockIndependent
    }

    private enum CodingKeys: String, CodingKey { case screenID, zones, dockIndependent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenID = try c.decode(String.self, forKey: .screenID)
        zones = try c.decode([Zone].self, forKey: .zones)
        dockIndependent = try c.decodeIfPresent(Bool.self, forKey: .dockIndependent) ?? false
    }
}

struct ZoneConfiguration: Codable {
    var layouts: [String: ScreenLayout] = [:]
    var version: Int = 1
}

/// Remembered placement for a specific (app, window-key) pair.
struct WindowMemoryEntry: Codable {
    /// e.g. "com.apple.Safari"
    let bundleIdentifier: String
    /// Normalised window-key (title hash or title prefix).
    let windowKey: String
    /// Optional zone snap target.
    var zoneID: UUID?
    /// When a window was snapped to the union of several zones, those zone
    /// IDs (used on restore to recompute the bounding box).
    var zoneIDs: [UUID]?
    /// Screen on which the zone lives.
    var screenID: String?
    /// Absolute fallback frame (if no zone, or zone deleted).
    var lastFrame: CGRect?
    var lastSeen: Date
}

struct WindowMemoryStore: Codable {
    var entries: [String: WindowMemoryEntry] = [:]
    static func key(bundleID: String, windowKey: String) -> String {
        "\(bundleID)#\(windowKey)"
    }
}
