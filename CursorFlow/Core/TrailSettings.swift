import Cocoa

struct TrailSettings {
    var isEnabled: Bool = true
    var effect: TrailEffect = .smooth
    var primaryColor: NSColor = .magenta
    var trailLength: Int = 64  // Number of trail points (16-256)
    var trailWidth: CGFloat = 8.0
    var fadeDuration: Double = 1.0  // Seconds for trail to fade

    static let `default` = TrailSettings()
}
