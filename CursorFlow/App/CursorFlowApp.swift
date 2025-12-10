import Cocoa

@main
struct CursorFlowApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Prevent app from showing in Dock (backup for Info.plist)
        app.setActivationPolicy(.accessory)

        app.run()
    }
}
