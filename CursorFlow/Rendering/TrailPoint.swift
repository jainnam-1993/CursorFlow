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
}
