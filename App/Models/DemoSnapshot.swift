#if DEBUG && os(macOS)
import AppKit

/// Mac App Store screenshots: `-snapshot <file.png>` resizes the main window to
/// 1440×900, waits for `-demoScreen` to open, saves the window (title bar and
/// toolbar included) and quits. Debug builds only; use an unsigned build, the
/// sandbox would not let it write the file.
enum DemoSnapshot {
    @MainActor static func scheduleIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            NSApp.appearance = NSAppearance(named: .aqua)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil && $0.frame.width > 400 })
            else { exit(2) }
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1440, height: 900)), display: true)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(3))
            let data = windowImage(window) ?? cachedImage(window)
            do {
                try data?.write(to: url)
                exit(data == nil ? 3 : 0)
            } catch {
                NSLog("DemoSnapshot: %@", "\(error)")
                exit(4)
            }
        }
    }

    /// The window as the window server draws it (sheets and lists included).
    /// `CGWindowListCreateImage` is gone from the SDK but still in the system;
    /// an app may capture its own windows without Screen Recording access.
    @MainActor private static func windowImage(_ window: NSWindow) -> Data? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(sym, to: Fn.self)
        // With a sheet open: the window's area of the screen (onScreenOnly = 1),
        // which has the sheet over it; otherwise just the window
        // (optionIncludingWindow = 8). boundsIgnoreFraming = 1, bestResolution = 8.
        let image: CGImage?
        if window.attachedSheet != nil, let screen = window.screen {
            var rect = window.frame
            rect.origin.y = screen.frame.maxY - rect.maxY
            image = create(rect, 1, 0, 8)?.takeRetainedValue()
        } else {
            image = create(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue()
        }
        guard let image else { return nil }
        NSLog("DemoSnapshot: window server image %dx%d", image.width, image.height)
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @MainActor private static func cachedImage(_ window: NSWindow) -> Data? {
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return nil }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        NSLog("DemoSnapshot: cached view image")
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
