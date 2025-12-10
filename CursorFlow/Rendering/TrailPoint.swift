import simd

struct TrailPoint {
    var position: SIMD2<Float>  // Screen position (normalized 0-1)
    var color: SIMD3<Float>     // RGB color
    var alpha: Float            // Opacity (0-1)
    var age: Float              // Age in seconds

    init(x: Float, y: Float, color: SIMD3<Float> = SIMD3<Float>(1, 0, 1), alpha: Float = 1.0) {
        self.position = SIMD2<Float>(x, y)
        self.color = color
        self.alpha = alpha
        self.age = 0
    }
}

// For passing to Metal shaders
struct TrailVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>  // RGBA

    init(point: TrailPoint) {
        self.position = point.position
        self.color = SIMD4<Float>(point.color.x, point.color.y, point.color.z, point.alpha)
    }

    init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}

// Lightning branch structure for electric arc forks
struct LightningBranch {
    var startIndex: Int              // Index in main trail where branch starts
    var points: [SIMD2<Float>]       // Branch point positions
    var decay: Float                 // Fade factor (1.0 → 0.0)

    init(startIndex: Int) {
        self.startIndex = startIndex
        self.points = []
        self.decay = 1.0
    }
}
