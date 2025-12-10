import Cocoa
import CoreGraphics

class MouseTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onMouseMove: ((NSPoint) -> Void)?

    func start() {
        // Event mask for mouse moved and dragged events
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                                      (1 << CGEventType.leftMouseDragged.rawValue) |
                                      (1 << CGEventType.rightMouseDragged.rawValue) |
                                      (1 << CGEventType.otherMouseDragged.rawValue)

        // Create event tap
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // We only listen, don't modify events
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let tracker = Unmanaged<MouseTracker>.fromOpaque(refcon).takeUnretainedValue()
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
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("Mouse tracking started")
        }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        print("Mouse tracking stopped")
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
