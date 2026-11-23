#if DEBUG && os(macOS)
import AppKit
import AVFoundation

/// App Review screen recording on the Mac: `-recordVideo <file.mp4>` records
/// the app's own windows (the main window and any sheet on it) from the first
/// window on, 10 frames a second, 1440×900. It stops when `<file.mp4>.stop`
/// appears or after 4 minutes, then quits. No Screen Recording access needed:
/// an app may capture its own windows. Debug builds only, unsigned (sandbox).
@MainActor final class DemoRecorder {
    private static var current: DemoRecorder?

    static func startIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard current == nil, let i = args.firstIndex(of: "-recordVideo"), i + 1 < args.count else { return }
        current = DemoRecorder(url: URL(fileURLWithPath: args[i + 1]))
    }

    private let url: URL
    private let size = CGSize(width: 1440, height: 900)
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var start = Date()
    private var timer: Timer?

    private init(url: URL) {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: stopURL)
        Task { @MainActor in self.begin() }
    }

    static func stop() { current?.finish() }

    private var stopURL: URL { url.appendingPathExtension("stop") }

    private var attempts = 0

    private func begin() {
        guard let window = mainWindow else {
            attempts += 1
            // Launched from a script, macOS sometimes opens the app with no
            // window; File → New Window (⌘N) makes one.
            if attempts % 10 == 0, let item = Self.menuItem(key: "n", in: NSApp.mainMenu), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.2)); self.begin() }
            return
        }
        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { exit(5) }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        (self.writer, self.input, self.adaptor) = (writer, input, adaptor)
        start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in DemoRecorder.current?.tick() }
        }
    }

    private static func menuItem(key: String, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.keyEquivalent == key, item.keyEquivalentModifierMask == .command { return item }
            if let found = menuItem(key: key, in: item.submenu) { return found }
        }
        return nil
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.frame.width > 400 }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(start)
        if FileManager.default.fileExists(atPath: stopURL.path) || elapsed > 240 {
            finish()
            return
        }
        guard let window = mainWindow, let input, let adaptor, input.isReadyForMoreMediaData,
              let image = capture(window), let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 600))
    }

    /// The main window with its sheet, composited by the window server.
    private func capture(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray"),
              let screen = window.screen else { return nil }
        let create = unsafeBitCast(sym, to: Fn.self)
        var ids: [UInt] = []
        if let sheet = window.attachedSheet { ids.append(UInt(sheet.windowNumber)) }
        ids.append(UInt(window.windowNumber))
        let pointers = ids.map { UnsafeRawPointer(bitPattern: $0) }
        let array = pointers.withUnsafeBufferPointer { buf in
            CFArrayCreate(nil, UnsafeMutablePointer(mutating: buf.baseAddress), buf.count, nil)!
        }
        var rect = window.frame
        rect.origin.y = screen.frame.maxY - rect.maxY
        // kCGWindowImageBestResolution = 8
        return create(rect, array, 8)?.takeRetainedValue()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        input?.markAsFinished()
        writer?.finishWriting {
            DispatchQueue.main.async { exit(0) }
        }
    }
}
#endif
