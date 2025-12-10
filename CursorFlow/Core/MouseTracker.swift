import Cocoa
import CoreGraphics

class MouseTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var checkTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollingTimer: Timer?
    private var lastMouseLocation: NSPoint = .zero

    var onMouseMove: ((NSPoint) -> Void)?

    func start() {
        NSLog("[CursorFlow] Starting mouse tracking...")

        // Try CGEvent tap first (requires accessibility)
        if AXIsProcessTrusted() {
            startEventTap()
        } else {
            NSLog("[CursorFlow] Accessibility not granted, using fallback tracking")
            requestAccessibilityPermission()
        }

        // Always start fallback monitors as backup
        startFallbackTracking()
    }

    private func startEventTap() {
        // Event mask - only mouse movement events
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                                      (1 << CGEventType.leftMouseDragged.rawValue) |
                                      (1 << CGEventType.rightMouseDragged.rawValue) |
                                      (1 << CGEventType.otherMouseDragged.rawValue)

        // Create event tap at session level for global access
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let tracker = Unmanaged<MouseTracker>.fromOpaque(refcon).takeUnretainedValue()

                // Handle tap disabled event - immediately re-enable
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    NSLog("[CursorFlow] Event tap disabled by system, re-enabling")
                    if let tap = tracker.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let location = event.location
                DispatchQueue.main.async {
                    let nsPoint = NSPoint(x: location.x, y: location.y)
                    tracker.onMouseMove?(nsPoint)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            NSLog("[CursorFlow] Failed to create event tap")
            return
        }
        NSLog("[CursorFlow] Event tap created successfully")

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            NSLog("[CursorFlow] Event tap enabled on main run loop")

            // Periodically check if the tap is still enabled
            checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkAndReenableTap()
            }
        }
    }

    private func startFallbackTracking() {
        // NSEvent global monitor - works for mouse events when app is not focused
        // This is more reliable than CGEvent tap for background operation
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }

        // Local monitor for when our app is focused (global doesn't catch these)
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }

        // Polling fallback - catches mouse position even if events are missed
        // Uses lower frequency to reduce CPU usage
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentLocation = NSEvent.mouseLocation

            // Convert from NSScreen coordinates (bottom-left origin) to Quartz (top-left origin)
            if let screenHeight = NSScreen.screens.first?.frame.height {
                let quartzY = screenHeight - currentLocation.y
                let point = NSPoint(x: currentLocation.x, y: quartzY)

                // Only fire if position changed significantly
                let dx = abs(point.x - self.lastMouseLocation.x)
                let dy = abs(point.y - self.lastMouseLocation.y)
                if dx > 0.5 || dy > 0.5 {
                    self.lastMouseLocation = point
                    self.onMouseMove?(point)
                }
            }
        }

        NSLog("[CursorFlow] Fallback tracking started (global monitor + polling)")
    }

    private func handleMouseEvent(_ event: NSEvent) {
        // NSEvent uses screen coordinates with origin at bottom-left
        // Convert to Quartz coordinates (top-left origin) for consistency with CGEvent
        let screenLocation = NSEvent.mouseLocation

        if let screenHeight = NSScreen.screens.first?.frame.height {
            let quartzY = screenHeight - screenLocation.y
            let point = NSPoint(x: screenLocation.x, y: quartzY)
            onMouseMove?(point)
        }
    }

    private func checkAndReenableTap() {
        guard let eventTap = eventTap else { return }

        if !CGEvent.tapIsEnabled(tap: eventTap) {
            NSLog("[CursorFlow] Event tap was disabled, re-enabling...")
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil

        pollingTimer?.invalidate()
        pollingTimer = nil

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }

        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
        NSLog("[CursorFlow] Mouse tracking stopped")
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            NSLog("[CursorFlow] Accessibility permission NOT granted - using fallback only")
        }
    }

    deinit {
        stop()
    }
}
