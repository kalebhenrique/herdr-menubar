import AppKit

// MenuBarExtra exposes no open/closed binding, so this backs up an inert `dismiss`.
// Match by class AND visibility: the other window is the status item, and closing it removes the icon.
@MainActor
enum MenuPanel {
    private static let panelClassMarker = "MenuBarExtra"

    static func close() {
        guard let panel = NSApp.windows.first(where: isMenuBarExtraPanel),
              panel.isVisible
        else { return }

        Log.debug("closing the panel as a fallback")
        panel.close()
    }

    /// MenuBarExtra's window keeps a stale frame when the SwiftUI content shrinks
    /// while the panel is visible (e.g. chats deleted in Herdr drop the list from
    /// the scrolling size down to a few rows): the old height stays and the panel
    /// ends in blank space below the content. Re-fit the frame to the content's
    /// height, keeping the top edge pinned under the status item.
    static func resizeToFit() {
        guard let panel = NSApp.windows.first(where: isMenuBarExtraPanel),
              panel.isVisible,
              let content = panel.contentView
        else { return }

        let fitting = content.fittingSize
        guard fitting.height > 1 else { return }

        let frame = panel.frame
        let chrome = frame.height - panel.contentRect(forFrameRect: frame).height
        let newHeight = fitting.height + chrome
        guard abs(newHeight - frame.height) > 0.5 else { return }

        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - newHeight,
                              width: frame.width, height: newHeight), display: true)
    }

    private static func isMenuBarExtraPanel(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains(panelClassMarker)
    }
}
