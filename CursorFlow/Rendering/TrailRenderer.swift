import MetalKit
import simd

class TrailRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?

    // Trail data
    private var trailPoints: [TrailPoint] = []
    private var maxTrailLength = 128
    private var vertices: [TrailVertex] = []
    private var vertexBuffer: MTLBuffer?

    // Uniforms
    private var uniforms = Uniforms()
    private var uniformBuffer: MTLBuffer?

    // Settings
    var isEnabled: Bool = true
    var trailColor: NSColor = .systemRed  // Bright red for visibility
    var trailEffect: TrailEffect = .smooth
    var fadeDuration: Double = 1.0  // seconds

    // Screen info
    private var screenSize: CGSize = .zero
    private var hueOffset: Float = 0
    private var time: Float = 0

    struct Uniforms {
        var screenSize: SIMD2<Float> = SIMD2<Float>(1920, 1080)
        var pointSize: Float = 20.0  // Increased from 8 for visibility testing
        var time: Float = 0
    }

    init(metalView: MTKView, device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        super.init()

        metalView.delegate = self
        metalView.device = device
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.framebufferOnly = false

        setupPipeline()
        setupBuffers()

        // Get screen size - IMPORTANT: must match CGEvent coordinate space
        if let screen = NSScreen.main {
            screenSize = screen.frame.size
            uniforms.screenSize = SIMD2<Float>(Float(screenSize.width), Float(screenSize.height))
            NSLog("[CursorFlow] TrailRenderer init - screen size: %.0fx%.0f", screenSize.width, screenSize.height)
        }
    }

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create shader library")
            return
        }

        let vertexFunction = library.makeFunction(name: "trailVertex")
        let fragmentFunction = library.makeFunction(name: "trailFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable blending for transparency
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func setupBuffers() {
        // Pre-allocate vertex buffer (larger for lightning effect which adds extra points)
        let bufferSize = maxTrailLength * 4 * MemoryLayout<TrailVertex>.stride
        vertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)

        // Uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
    }

    // MARK: - Public Methods

    func setTrailLength(_ length: Int) {
        maxTrailLength = max(16, min(256, length))
    }

    func setFadeDuration(_ duration: Double) {
        fadeDuration = max(0.2, min(3.0, duration))
    }

    private var pointCount = 0

    func addPoint(_ point: NSPoint) {
        guard isEnabled else { return }

        pointCount += 1
        if pointCount % 100 == 1 {
            NSLog("[CursorFlow] addPoint called #%d at (%.0f, %.0f)", pointCount, point.x, point.y)
        }

        let color = calculateColor(for: trailPoints.count)
        let newPoint = TrailPoint(
            x: Float(point.x),
            y: Float(point.y),
            color: color,
            alpha: 1.0
        )

        trailPoints.insert(newPoint, at: 0)

        // Remove excess points
        if trailPoints.count > maxTrailLength {
            trailPoints.removeLast()
        }
    }

    // MARK: - Color Calculation

    private func calculateColor(for index: Int) -> SIMD3<Float> {
        switch trailEffect {
        case .rainbow:
            let hue = fmod(hueOffset + Float(index) * 0.03, 1.0)
            return hslToRgb(h: hue, s: 1.0, l: 0.5)
        case .lightning:
            // White/blue electric color
            return SIMD3<Float>(0.8, 0.9, 1.0)
        case .magic:
            // Purple/pink sparkle
            let hue = fmod(0.8 + Float(index) * 0.01 + sin(time * 3 + Float(index) * 0.2) * 0.1, 1.0)
            return hslToRgb(h: hue, s: 0.8, l: 0.6)
        case .smooth:
            return nsColorToSimd(trailColor)
        }
    }

    private func hslToRgb(h: Float, s: Float, l: Float) -> SIMD3<Float> {
        if s == 0 {
            return SIMD3<Float>(l, l, l)
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hue2rgb(_ p: Float, _ q: Float, _ t: Float) -> Float {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }

        return SIMD3<Float>(
            hue2rgb(p, q, h + 1/3),
            hue2rgb(p, q, h),
            hue2rgb(p, q, h - 1/3)
        )
    }

    private func nsColorToSimd(_ color: NSColor) -> SIMD3<Float> {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return SIMD3<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent)
        )
    }

    // MARK: - Effect-specific vertex generation

    private func generateVertices() -> [TrailVertex] {
        switch trailEffect {
        case .smooth:
            return generateSmoothVertices()
        case .lightning:
            return generateLightningVertices()
        case .rainbow:
            return generateRainbowVertices()
        case .magic:
            return generateMagicVertices()
        }
    }

    private func generateSmoothVertices() -> [TrailVertex] {
        return trailPoints.enumerated().map { index, point in
            var modifiedPoint = point
            let t = Float(index) / Float(max(1, trailPoints.count))
            modifiedPoint.alpha = pow(1.0 - t, 1.5) * point.alpha
            modifiedPoint.color = nsColorToSimd(trailColor)
            return TrailVertex(point: modifiedPoint)
        }
    }

    private func generateLightningVertices() -> [TrailVertex] {
        var result: [TrailVertex] = []

        for (index, point) in trailPoints.enumerated() {
            var modifiedPoint = point
            let t = Float(index) / Float(max(1, trailPoints.count))

            // Add random jitter for lightning effect
            let jitterX = sin(time * 20 + Float(index) * 2.5) * (5.0 + Float(index) * 0.5)
            let jitterY = cos(time * 25 + Float(index) * 3.0) * (5.0 + Float(index) * 0.5)

            modifiedPoint.position.x += jitterX
            modifiedPoint.position.y += jitterY

            // White/blue electric glow
            modifiedPoint.color = SIMD3<Float>(0.8 + sin(time * 30) * 0.2, 0.9, 1.0)
            modifiedPoint.alpha = pow(1.0 - t, 1.2) * point.alpha

            result.append(TrailVertex(point: modifiedPoint))
        }

        return result
    }

    private func generateRainbowVertices() -> [TrailVertex] {
        return trailPoints.enumerated().map { index, point in
            var modifiedPoint = point
            let t = Float(index) / Float(max(1, trailPoints.count))
            modifiedPoint.alpha = pow(1.0 - t, 1.5) * point.alpha

            // Rainbow color based on position
            let hue = fmod(hueOffset + Float(index) * 0.03, 1.0)
            modifiedPoint.color = hslToRgb(h: hue, s: 1.0, l: 0.5)

            return TrailVertex(point: modifiedPoint)
        }
    }

    private func generateMagicVertices() -> [TrailVertex] {
        var result: [TrailVertex] = []

        for (index, point) in trailPoints.enumerated() {
            var modifiedPoint = point
            let t = Float(index) / Float(max(1, trailPoints.count))

            // Sparkle effect - slight random movement
            let sparkleX = sin(time * 10 + Float(index) * 1.7) * 3.0
            let sparkleY = cos(time * 12 + Float(index) * 2.1) * 3.0

            modifiedPoint.position.x += sparkleX
            modifiedPoint.position.y += sparkleY

            // Purple/pink/cyan magic colors
            let hue = fmod(0.75 + Float(index) * 0.015 + sin(time * 2) * 0.1, 1.0)
            modifiedPoint.color = hslToRgb(h: hue, s: 0.9, l: 0.6)

            // Twinkle effect
            let twinkle = 0.7 + sin(time * 15 + Float(index) * 0.8) * 0.3
            modifiedPoint.alpha = pow(1.0 - t, 1.3) * point.alpha * twinkle

            result.append(TrailVertex(point: modifiedPoint))
        }

        return result
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Use actual screen size, not drawable size (to match mouse coordinates)
        if let screen = NSScreen.main {
            screenSize = screen.frame.size
            uniforms.screenSize = SIMD2<Float>(Float(screenSize.width), Float(screenSize.height))
            NSLog("[CursorFlow] Screen size set to: %.0f x %.0f (drawable: %.0f x %.0f)",
                  screenSize.width, screenSize.height, size.width, size.height)
        }
    }

    private var drawCount = 0

    func draw(in view: MTKView) {
        drawCount += 1
        if drawCount % 120 == 1 {
            NSLog("[CursorFlow] draw called #%d, trailPoints: %d, isEnabled: %@, screenSize: %.0fx%.0f",
                  drawCount, trailPoints.count, isEnabled ? "YES" : "NO",
                  Double(uniforms.screenSize.x), Double(uniforms.screenSize.y))
            if let first = trailPoints.first {
                NSLog("[CursorFlow] First point: (%.0f, %.0f) alpha: %.2f", first.position.x, first.position.y, first.alpha)
            }
        }

        guard isEnabled,
              !trailPoints.isEmpty,
              let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Update time
        time += 1.0 / 60.0
        uniforms.time = time

        // Update trail aging
        updateTrailPoints()

        // Update rainbow hue
        hueOffset = fmod(hueOffset + 0.008, 1.0)

        // Generate vertices based on current effect
        vertices = generateVertices()

        guard !vertices.isEmpty else { return }

        // Copy to buffer
        guard let vertexBuffer = vertexBuffer else { return }
        let bufferPointer = vertexBuffer.contents().bindMemory(to: TrailVertex.self, capacity: vertices.count)
        for (index, vertex) in vertices.enumerated() {
            bufferPointer[index] = vertex
        }

        // Update uniforms
        if let uniformBuffer = uniformBuffer {
            uniformBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.stride)
        }

        // Render
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertices.count)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateTrailPoints() {
        // Age points and reduce alpha over time based on fadeDuration
        for i in 0..<trailPoints.count {
            trailPoints[i].age += 1.0 / 60.0
            // Alpha fades from 1 to 0 over fadeDuration seconds
            let ageFade = max(0, 1.0 - trailPoints[i].age / Float(fadeDuration))
            trailPoints[i].alpha = ageFade
        }

        // Remove completely faded points
        trailPoints.removeAll { $0.alpha < 0.01 }
    }
}
