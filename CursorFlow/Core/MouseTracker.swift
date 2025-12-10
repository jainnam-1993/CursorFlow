import Cocoa
import CoreGraphics

class MouseTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var checkTimer: Timer?

    var onMouseMove: ((NSPoint) -> Void)?

    func start() {
        // First check accessibility permission
        if !AXIsProcessTrusted() {
            NSLog("[CursorFlow] Accessibility not granted, requesting permission...")
            requestAccessibilityPermission()

            // Retry periodically until permission is granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.retryStartIfNeeded()
            }
            return
        }

        // Event mask - only mouse movement events (simpler, more reliable)
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                                      (1 << CGEventType.leftMouseDragged.rawValue) |
                                      (1 << CGEventType.rightMouseDragged.rawValue) |
                                      (1 << CGEventType.otherMouseDragged.rawValue)

        // Create event tap at session level for global access (works without root)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,  // Session level tap - global for user session, no root needed
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let tracker = Unmanaged<MouseTracker>.fromOpaque(refcon).takeUnretainedValue()

                // Handle tap disabled event - immediately re-enable
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    NSLog("[CursorFlow] Event tap disabled by system, re-enabling immediately")
                    if let tap = tracker.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let location = event.location

                // CGEvent location uses Quartz display coordinates (origin at top-left)
                DispatchQueue.main.async {
                    tracker.onMouseMove?(NSPoint(x: location.x, y: location.y))
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            NSLog("[CursorFlow] Failed to create event tap. Check Accessibility permissions.")
            requestAccessibilityPermission()
            return
        }
        NSLog("[CursorFlow] Event tap created successfully")

        // Create run loop source and add to current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            NSLog("[CursorFlow] Mouse tracking started on main run loop")

            // Periodically check if the tap is still enabled and re-enable if needed
            checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.checkAndReenableTap()
            }
        }
    }

    private func checkAndReenableTap() {
        guard let eventTap = eventTap else { return }

        if !CGEvent.tapIsEnabled(tap: eventTap) {
            NSLog("[CursorFlow] Event tap was disabled, re-enabling...")
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func retryStartIfNeeded() {
        if eventTap == nil && AXIsProcessTrusted() {
            NSLog("[CursorFlow] Permission granted, starting mouse tracking")
            start()
        } else if !AXIsProcessTrusted() {
            // Keep retrying until permission is granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.retryStartIfNeeded()
            }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        NSLog("[CursorFlow] Mouse tracking stopped")
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            NSLog("[CursorFlow] Accessibility permission NOT granted - prompting user")
        } else {
            NSLog("[CursorFlow] Accessibility permission already granted")
        }
    }

    deinit {
        stop()
    }
}
