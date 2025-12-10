import Cocoa
import ServiceManagement

class PreferencesWindowController: NSWindowController {

    // Callbacks
    var onTrailLengthChange: ((Int) -> Void)?
    var onTrailDurationChange: ((Double) -> Void)?

    // UI Elements
    private var trailLengthSlider: NSSlider!
    private var trailLengthLabel: NSTextField!
    private var trailDurationSlider: NSSlider!
    private var trailDurationLabel: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CursorFlow Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        var yOffset: CGFloat = 220

        // Title
        let titleLabel = NSTextField(labelWithString: "Trail Settings")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: padding, y: yOffset, width: 360, height: 20)
        contentView.addSubview(titleLabel)
        yOffset -= 40

        // Trail Length
        let lengthTitleLabel = NSTextField(labelWithString: "Trail Length:")
        lengthTitleLabel.frame = NSRect(x: padding, y: yOffset, width: 100, height: 20)
        contentView.addSubview(lengthTitleLabel)

        trailLengthSlider = NSSlider(value: 64, minValue: 16, maxValue: 256, target: self, action: #selector(trailLengthChanged(_:)))
        trailLengthSlider.frame = NSRect(x: padding + 110, y: yOffset, width: 180, height: 20)
        trailLengthSlider.numberOfTickMarks = 5
        trailLengthSlider.allowsTickMarkValuesOnly = false
        contentView.addSubview(trailLengthSlider)

        trailLengthLabel = NSTextField(labelWithString: "64")
        trailLengthLabel.frame = NSRect(x: padding + 300, y: yOffset, width: 50, height: 20)
        trailLengthLabel.alignment = .right
        contentView.addSubview(trailLengthLabel)
        yOffset -= 35

        // Trail Duration (Fade Time)
        let durationTitleLabel = NSTextField(labelWithString: "Fade Duration:")
        durationTitleLabel.frame = NSRect(x: padding, y: yOffset, width: 100, height: 20)
        contentView.addSubview(durationTitleLabel)

        trailDurationSlider = NSSlider(value: 1.0, minValue: 0.2, maxValue: 3.0, target: self, action: #selector(trailDurationChanged(_:)))
        trailDurationSlider.frame = NSRect(x: padding + 110, y: yOffset, width: 180, height: 20)
        trailDurationSlider.numberOfTickMarks = 5
        contentView.addSubview(trailDurationSlider)

        trailDurationLabel = NSTextField(labelWithString: "1.0s")
        trailDurationLabel.frame = NSRect(x: padding + 300, y: yOffset, width: 50, height: 20)
        trailDurationLabel.alignment = .right
        contentView.addSubview(trailDurationLabel)
        yOffset -= 50

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: padding, y: yOffset, width: 360, height: 1)
        contentView.addSubview(separator)
        yOffset -= 30

        // Startup section title
        let startupLabel = NSTextField(labelWithString: "Startup")
        startupLabel.font = NSFont.boldSystemFont(ofSize: 14)
        startupLabel.frame = NSRect(x: padding, y: yOffset, width: 360, height: 20)
        contentView.addSubview(startupLabel)
        yOffset -= 35

        // Launch at Login
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch CursorFlow at Login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchAtLoginCheckbox.frame = NSRect(x: padding, y: yOffset, width: 300, height: 20)
        contentView.addSubview(launchAtLoginCheckbox)
        yOffset -= 50

        // Info text
        let infoLabel = NSTextField(wrappingLabelWithString: "Tip: Use shorter trail length and faster fade for better performance.")
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.frame = NSRect(x: padding, y: yOffset, width: 360, height: 30)
        contentView.addSubview(infoLabel)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        let length = defaults.integer(forKey: "trailLength")
        if length > 0 {
            trailLengthSlider.integerValue = length
            trailLengthLabel.stringValue = "\(length)"
        }

        let duration = defaults.double(forKey: "trailDuration")
        if duration > 0 {
            trailDurationSlider.doubleValue = duration
            trailDurationLabel.stringValue = String(format: "%.1fs", duration)
        }

        // Check if launch at login is enabled
        if #available(macOS 13.0, *) {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            // For older macOS, check using legacy API
            launchAtLoginCheckbox.state = defaults.bool(forKey: "launchAtLogin") ? .on : .off
        }
    }

    @objc private func trailLengthChanged(_ sender: NSSlider) {
        let value = sender.integerValue
        trailLengthLabel.stringValue = "\(value)"
        UserDefaults.standard.set(value, forKey: "trailLength")
        onTrailLengthChange?(value)
    }

    @objc private func trailDurationChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        trailDurationLabel.stringValue = String(format: "%.1fs", value)
        UserDefaults.standard.set(value, forKey: "trailDuration")
        onTrailDurationChange?(value)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let enabled = sender.state == .on

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
                // Revert checkbox state on failure
                sender.state = enabled ? .off : .on

                let alert = NSAlert()
                alert.messageText = "Could not update login settings"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        } else {
            // Legacy approach for older macOS
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        }
    }
}
