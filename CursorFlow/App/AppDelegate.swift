import Cocoa
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var overlayWindow: OverlayWindow?
    private var mouseTracker: MouseTracker?
    private var trailRenderer: TrailRenderer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[CursorFlow] App launched")
        loadSettings()
        NSLog("[CursorFlow] Settings loaded")
        setupOverlayWindow()
        NSLog("[CursorFlow] Overlay window setup complete")
        setupMouseTracking()
        NSLog("[CursorFlow] Mouse tracking setup complete")
        setupStatusBar()
        NSLog("[CursorFlow] Status bar setup complete - should be visible now")
    }

    private func loadSettings() {
        // Load saved settings from UserDefaults
        let defaults = UserDefaults.standard

        // Register default values
        defaults.register(defaults: [
            "trailLength": 64,
            "trailDuration": 1.0,
            "trailEffect": "smooth"
        ])
    }

    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow()

        guard let metalView = overlayWindow?.contentView as? MTKView,
              let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        trailRenderer = TrailRenderer(metalView: metalView, device: device)

        // Apply saved settings
        let defaults = UserDefaults.standard
        let length = defaults.integer(forKey: "trailLength")
        if length > 0 {
            trailRenderer?.setTrailLength(length)
        }

        let duration = defaults.double(forKey: "trailDuration")
        if duration > 0 {
            trailRenderer?.setFadeDuration(duration)
        }

        overlayWindow?.orderFrontRegardless()
    }

    private func setupMouseTracking() {
        mouseTracker = MouseTracker()
        mouseTracker?.onMouseMove = { [weak self] point in
            self?.trailRenderer?.addPoint(point)
        }
        mouseTracker?.start()
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController()

        // Toggle trail visibility
        statusBarController?.onToggleTrail = { [weak self] enabled in
            self?.trailRenderer?.isEnabled = enabled
            if enabled {
                self?.overlayWindow?.orderFrontRegardless()
            } else {
                self?.overlayWindow?.orderOut(nil)
            }
        }

        // Change trail color
        statusBarController?.onColorChange = { [weak self] color in
            self?.trailRenderer?.trailColor = color
        }

        // Change trail effect
        statusBarController?.onEffectChange = { [weak self] effect in
            self?.trailRenderer?.trailEffect = effect
            UserDefaults.standard.set(effect.rawValue, forKey: "trailEffect")
        }

        // Change trail length (from preferences)
        statusBarController?.onTrailLengthChange = { [weak self] length in
            self?.trailRenderer?.setTrailLength(length)
        }

        // Change trail duration (from preferences)
        statusBarController?.onTrailDurationChange = { [weak self] duration in
            self?.trailRenderer?.setFadeDuration(duration)
        }

        // Quit
        statusBarController?.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseTracker?.stop()
    }
}
