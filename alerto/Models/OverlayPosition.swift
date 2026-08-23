import Foundation
import AppKit

/// Where the overlay window anchors on the active screen.
enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Computes the origin for an overlay of `size` inside `screenFrame`.
    /// `padding` is applied on every edge; `topInset` is an additional offset from
    /// the top edge so the overlay clears the menu bar.
    func origin(in screenFrame: NSRect, size: NSSize, padding: CGFloat, topInset: CGFloat) -> NSPoint {
        let minX = screenFrame.minX + padding
        let maxX = screenFrame.maxX - size.width - padding
        let centerX = screenFrame.minX + (screenFrame.width - size.width) / 2

        let topY = screenFrame.maxY - size.height - padding - topInset
        let bottomY = screenFrame.minY + padding

        switch self {
        case .topLeft:      return NSPoint(x: minX,    y: topY)
        case .topCenter:    return NSPoint(x: centerX, y: topY)
        case .topRight:     return NSPoint(x: maxX,    y: topY)
        case .bottomLeft:   return NSPoint(x: minX,    y: bottomY)
        case .bottomCenter: return NSPoint(x: centerX, y: bottomY)
        case .bottomRight:  return NSPoint(x: maxX,    y: bottomY)
        }
    }
}
