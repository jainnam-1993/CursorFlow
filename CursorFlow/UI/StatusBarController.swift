import Cocoa

enum TrailEffect: String, CaseIterable {
    case smooth = "Smooth"
    case lightning = "Lightning"
    case rainbow = "Rainbow"
    case magic = "Magic"
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var preferencesWindow: PreferencesWindowController?

    // Callbacks
    var onToggleTrail: ((Bool) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    var onEffectChange: ((TrailEffect) -> Void)?
    var onTrailLengthChange: ((Int) -> Void)?
    var onTrailDurationChange: ((Double) -> Void)?
    var onQuit: (() -> Void)?

    // State
    private var isTrailEnabled = true
    private var selectedColor: String = "Rainbow"
    private var selectedEffect: TrailEffect = .smooth

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Try different SF Symbols in order of preference
            let symbolNames = ["cursorarrow.motionlines", "arrow.up.left.and.arrow.down.right", "wand.and.stars", "sparkles"]
            var imageSet = false

            for symbolName in symbolNames {
                if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CursorFlow") {
                    image.isTemplate = true
                    button.image = image
                    imageSet = true
                    break
                }
            }

            if !imageSet {
                button.title = "✨"
            }
            button.toolTip = "CursorFlow - Click for options"
        }
    }

    private func setupMenu() {
        menu = NSMenu()

        // Toggle Mouse Trail
        let toggleTrailItem = NSMenuItem(
            title: "Disable Mouse Trail",
            action: #selector(toggleTrail),
            keyEquivalent: ""
        )
        toggleTrailItem.target = self
        toggleTrailItem.tag = 100
        menu?.addItem(toggleTrailItem)

        menu?.addItem(NSMenuItem.separator())

        // Mouse Trail Color submenu
        let colorMenu = NSMenu()
        let colors: [(String, String, NSColor)] = [
            ("🔴 Red", "Red", .systemRed),
            ("🟡 Yellow", "Yellow", .systemYellow),
            ("🟢 Green", "Green", .systemGreen),
            ("⚪ White", "White", .white),
            ("⚫ Black", "Black", .black),
            ("🎨 Custom", "Custom", .magenta)
        ]

        for (title, name, color) in colors {
            let item = NSMenuItem(title: title, action: #selector(selectColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["name": name, "color": color]
            colorMenu.addItem(item)
        }

        let colorItem = NSMenuItem(title: "Mouse Trail Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu?.addItem(colorItem)

        // Mouse Trail Effect submenu
        let effectMenu = NSMenu()
        for effect in TrailEffect.allCases {
            let item = NSMenuItem(title: effect.rawValue, action: #selector(selectEffect(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = effect
            if effect == .smooth {
                item.state = .on
            }
            effectMenu.addItem(item)
        }

        let effectItem = NSMenuItem(title: "Mouse Trail Effect", action: nil, keyEquivalent: "")
        effectItem.submenu = effectMenu
        menu?.addItem(effectItem)

        menu?.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu?.addItem(prefsItem)

        menu?.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        menu?.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleTrail(_ sender: NSMenuItem) {
        isTrailEnabled.toggle()
        sender.title = isTrailEnabled ? "Disable Mouse Trail" : "Enable Mouse Trail"
        onToggleTrail?(isTrailEnabled)
    }

    @objc private func selectColor(_ sender: NSMenuItem) {
        guard let colorMenu = sender.menu else { return }

        // Uncheck all
        for item in colorMenu.items {
            item.state = .off
        }
        sender.state = .on

        if let info = sender.representedObject as? [String: Any],
           let name = info["name"] as? String,
           let color = info["color"] as? NSColor {
            selectedColor = name

            if name == "Custom" {
                // Show color picker
                let colorPanel = NSColorPanel.shared
                colorPanel.setTarget(self)
                colorPanel.setAction(#selector(colorPanelChanged(_:)))
                colorPanel.makeKeyAndOrderFront(nil)
            } else {
                onColorChange?(color)
            }
        }
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        onColorChange?(sender.color)
    }

    @objc private func selectEffect(_ sender: NSMenuItem) {
        guard let effectMenu = sender.menu else { return }

        // Uncheck all
        for item in effectMenu.items {
            item.state = .off
        }
        sender.state = .on

        if let effect = sender.representedObject as? TrailEffect {
            selectedEffect = effect
            onEffectChange?(effect)
        }
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
            preferencesWindow?.onTrailLengthChange = onTrailLengthChange
            preferencesWindow?.onTrailDurationChange = onTrailDurationChange
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "CursorFlow"
        alert.informativeText = "A beautiful cursor trail effect for macOS.\n\nVersion 1.0.0\n\nBuilt with Swift + Metal"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        onQuit?()
    }
}
