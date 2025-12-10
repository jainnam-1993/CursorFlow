import Cocoa
import MetalKit

class OverlayWindow: NSWindow {

    init() {
        // Use the main screen frame - CGEvent coordinates are relative to main display
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        NSLog("[CursorFlow] Creating overlay window with frame: %.0f,%.0f %.0fx%.0f",
              screenFrame.origin.x, screenFrame.origin.y, screenFrame.width, screenFrame.height)

        super.init(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        configureWindow()
        setupMetalView()
    }

    private func configureWindow() {
        // Window level above everything including fullscreen apps
        level = .screenSaver

        // Click-through - all mouse events pass to windows below
        ignoresMouseEvents = true

        // Transparent window
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Appear on all spaces/desktops
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        // Don't show in window lists
        isExcludedFromWindowsMenu = true
    }

    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("[CursorFlow] Metal is not supported on this device")
            return
        }

        // Use the window's content rect for the frame
        let viewFrame = contentRect(forFrameRect: frame)
        let metalView = MTKView(frame: NSRect(origin: .zero, size: viewFrame.size), device: device)
        metalView.autoresizingMask = [.width, .height]

        // MUST set wantsLayer BEFORE accessing layer properties
        metalView.wantsLayer = true

        // Critical for transparent overlay
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = CGColor.clear

        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 120  // Higher FPS for smoother trails
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false

        // Prevent pausing when app loses focus
        metalView.presentsWithTransaction = false

        contentView = metalView

        NSLog("[CursorFlow] Metal view setup complete, bounds: %.0fx%.0f",
              metalView.bounds.width, metalView.bounds.height)
    }

    // Prevent the window from becoming key or main
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
