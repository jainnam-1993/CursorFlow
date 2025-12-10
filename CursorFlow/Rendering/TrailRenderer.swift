import MetalKit
import simd

class TrailRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var lightningPipelineState: MTLRenderPipelineState?

    // Trail data
    private var trailPoints: [TrailPoint] = []
    private var maxTrailLength = 128
    private var vertices: [TrailVertex] = []
    private var vertexBuffer: MTLBuffer?

    // Lightning branch system
    private var activeBranches: [LightningBranch] = []
    private var branchCooldown: Float = 0

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
        var pointSize: Float = 10.0  // Default point size
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

        // Setup lightning pipeline with additive blending for glow
        setupLightningPipeline(library: library)
    }

    private func setupLightningPipeline(library: MTLLibrary) {
        let vertexFunction = library.makeFunction(name: "trailLineVertex")
        let fragmentFunction = library.makeFunction(name: "trailLineFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Additive blending for glow effect
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one  // Additive
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            lightningPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create lightning pipeline state: \(error)")
        }
    }

    private func setupBuffers() {
        // Pre-allocate vertex buffer - lightning needs more (2 verts/point * 3 glow layers + branches)
        let bufferSize = maxTrailLength * 16 * MemoryLayout<TrailVertex>.stride
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
        // Skip first few points to keep area near cursor clear
        let skipPoints = 3
        guard trailPoints.count >= skipPoints + 2 else { return [] }

        let userColor = nsColorToSimd(trailColor)

        // Only flame wisps - no base line
        return buildFlameWisps(startIndex: skipPoints, userColor: userColor)
    }

    /// Build straight line following cursor path
    private func buildStraightLine(startIndex: Int, userColor: SIMD3<Float>) -> [TrailVertex] {
        var vertices: [TrailVertex] = []
        let count = trailPoints.count - startIndex

        for i in startIndex..<trailPoints.count {
            let pos = trailPoints[i].position
            let t = Float(i - startIndex) / Float(max(1, count - 1))

            // Calculate perpendicular
            let perpendicular = calculatePerpendicular(at: i)

            // Alpha fades along trail
            let alpha = pow(1.0 - t, 1.5) * trailPoints[i].alpha

            // Color: user color blended with warm orange/yellow
            let flameCore = SIMD3<Float>(1.0, 0.7, 0.3)  // Orange-yellow
            let mixed = userColor * 0.5 + flameCore * 0.5
            let color = SIMD4<Float>(mixed.x, mixed.y, mixed.z, alpha)

            // Width tapers
            let width: Float = 4.0 * (1.0 - t * 0.5)
            let halfWidth = width * 0.5

            let leftPos = pos + perpendicular * halfWidth
            let rightPos = pos - perpendicular * halfWidth

            vertices.append(TrailVertex(position: leftPos, color: color))
            vertices.append(TrailVertex(position: rightPos, color: color))
        }

        return vertices
    }

    /// Build flame wisps rising from the trail
    private func buildFlameWisps(startIndex: Int, userColor: SIMD3<Float>) -> [TrailVertex] {
        var vertices: [TrailVertex] = []

        // Create wisps at intervals along the trail
        let wispSpacing = 3
        for i in stride(from: startIndex, to: trailPoints.count - 2, by: wispSpacing) {
            let basePos = trailPoints[i].position
            let t = Float(i - startIndex) / Float(max(1, trailPoints.count - startIndex - 1))

            // Wisps rise upward (negative Y in screen coords)
            let wispHeight: Float = 15.0 * (1.0 - t)  // Taller near cursor
            let wispWidth: Float = 3.0 * (1.0 - t * 0.5)

            // Animated horizontal sway
            let sway = sin(time * 20 + Float(i) * 0.8) * 4.0 * (1.0 - t)

            // Wisp base (at trail)
            let baseAlpha = 0.8 * trailPoints[i].alpha * (1.0 - t)
            let baseColor = SIMD4<Float>(1.0, 0.6, 0.2, baseAlpha)  // Orange

            // Wisp tip (rising up)
            let tipPos = SIMD2<Float>(basePos.x + sway, basePos.y - wispHeight)
            let tipAlpha = 0.3 * trailPoints[i].alpha * (1.0 - t)
            let tipColor = SIMD4<Float>(1.0, 0.9, 0.5, tipAlpha)  // Yellow-white

            // Build wisp as thin triangle strip
            let perpendicular = SIMD2<Float>(1, 0)  // Horizontal spread

            // Base vertices
            vertices.append(TrailVertex(position: basePos + perpendicular * wispWidth, color: baseColor))
            vertices.append(TrailVertex(position: basePos - perpendicular * wispWidth, color: baseColor))

            // Tip vertices (narrower)
            vertices.append(TrailVertex(position: tipPos + perpendicular * (wispWidth * 0.3), color: tipColor))
            vertices.append(TrailVertex(position: tipPos - perpendicular * (wispWidth * 0.3), color: tipColor))
        }

        return vertices
    }

    // MARK: - Lightning Helpers

    /// Generate zigzag path using perpendicular displacement (like midpoint displacement)
    private func generateZigzagPath(startIndex: Int = 0) -> [SIMD2<Float>] {
        var displaced: [SIMD2<Float>] = []

        for i in startIndex..<trailPoints.count {
            var pos = trailPoints[i].position
            let t = Float(i - startIndex) / Float(max(1, trailPoints.count - startIndex - 1))

            // Calculate perpendicular direction to trail
            let perpendicular = calculatePerpendicular(at: i)

            // Zigzag: alternate direction with decreasing amplitude
            let zigzagSign: Float = (i % 2 == 0) ? 1.0 : -1.0
            let baseDisplacement: Float = 12.0 * (1.0 - t)  // Larger near cursor

            // Add some randomness via sine waves at different frequencies
            let variation = sin(Float(i) * 1.7 + time * 5) * 0.5 + 0.5
            let zigzagAmount = zigzagSign * baseDisplacement * (0.5 + variation)

            // High-frequency jitter for vibration effect
            let jitterFreq: Float = 50.0
            let jitterAmount: Float = 4.0 * (1.0 - t)
            let jitter = sin(time * jitterFreq + Float(i) * 3.0) * jitterAmount

            pos += perpendicular * (zigzagAmount + jitter)
            displaced.append(pos)
        }

        return displaced
    }

    /// Calculate perpendicular vector at a point in the trail
    private func calculatePerpendicular(at index: Int) -> SIMD2<Float> {
        let count = trailPoints.count
        guard count >= 2 else { return SIMD2<Float>(0, 1) }

        let direction: SIMD2<Float>
        if index == 0 {
            direction = trailPoints[0].position - trailPoints[1].position
        } else if index == count - 1 {
            direction = trailPoints[index - 1].position - trailPoints[index].position
        } else {
            direction = trailPoints[index - 1].position - trailPoints[index + 1].position
        }

        let length = simd_length(direction)
        guard length > 0.001 else { return SIMD2<Float>(0, 1) }

        let normalized = direction / length
        return SIMD2<Float>(-normalized.y, normalized.x)  // 90-degree rotation
    }

    /// Build triangle strip from point path with specified width and glow properties
    private func buildTriangleStrip(points: [SIMD2<Float>], width: Float, baseAlpha: Float,
                                    glowLayer: Int, userColor: SIMD3<Float>) -> [TrailVertex] {
        guard points.count >= 2 else { return [] }

        var vertices: [TrailVertex] = []

        for i in 0..<points.count {
            let pos = points[i]
            let t = Float(i) / Float(max(1, points.count - 1))

            // Calculate perpendicular at this point
            let perpendicular: SIMD2<Float>
            if i == 0 {
                let dir = simd_normalize(points[1] - points[0])
                perpendicular = SIMD2<Float>(-dir.y, dir.x)
            } else if i == points.count - 1 {
                let dir = simd_normalize(points[i] - points[i-1])
                perpendicular = SIMD2<Float>(-dir.y, dir.x)
            } else {
                let dir = simd_normalize(points[i+1] - points[i-1])
                perpendicular = SIMD2<Float>(-dir.y, dir.x)
            }

            // Alpha falloff along trail
            let trailIndex = min(i + 8, trailPoints.count - 1)  // Account for skip offset
            let alpha = baseAlpha * pow(1.0 - t, 1.8) * trailPoints[trailIndex].alpha

            // Flicker effect
            let flicker = 0.85 + sin(time * 60 + Float(i) * 2.0) * 0.15

            // Color based on glow layer - blend user color with electric white/blue
            let color: SIMD4<Float>
            switch glowLayer {
            case 0:  // Core - mostly white with hint of user color
                let mixed = userColor * 0.3 + SIMD3<Float>(0.9, 0.95, 1.0) * 0.7
                color = SIMD4<Float>(mixed.x * flicker, mixed.y * flicker, mixed.z, alpha)
            case 1:  // Inner glow - user color tinted
                let mixed = userColor * 0.6 + SIMD3<Float>(0.6, 0.8, 1.0) * 0.4
                color = SIMD4<Float>(mixed.x * flicker, mixed.y * flicker, mixed.z, alpha)
            default:  // Outer glow - faint user color
                let mixed = userColor * 0.4 + SIMD3<Float>(0.3, 0.5, 1.0) * 0.6
                color = SIMD4<Float>(mixed.x * flicker, mixed.y * flicker, mixed.z, alpha)
            }

            // Width tapers toward end
            let halfWidth = width * 0.5 * (1.0 - t * 0.6)

            let leftPos = pos + perpendicular * halfWidth
            let rightPos = pos - perpendicular * halfWidth

            vertices.append(TrailVertex(position: leftPos, color: color))
            vertices.append(TrailVertex(position: rightPos, color: color))
        }

        return vertices
    }

    /// Update lightning branches - spawn new ones and decay existing
    private func updateBranches(mainPath: [SIMD2<Float>]) {
        // Decay cooldown
        branchCooldown -= 1.0 / 60.0

        // Spawn new branch randomly
        if branchCooldown <= 0 && mainPath.count > 10 && Float.random(in: 0...1) < 0.12 {
            let spawnIndex = Int.random(in: 3..<min(mainPath.count - 3, 25))
            var branch = LightningBranch(startIndex: spawnIndex)

            // Generate branch path
            var branchPos = mainPath[spawnIndex]

            // Get main trail direction and branch off at an angle
            let mainDir: SIMD2<Float>
            if spawnIndex > 0 && spawnIndex < mainPath.count - 1 {
                mainDir = simd_normalize(mainPath[spawnIndex - 1] - mainPath[spawnIndex + 1])
            } else {
                mainDir = SIMD2<Float>(1, 0)
            }

            // Branch angle: 30-70 degrees off main direction
            let angle = Float.random(in: 0.5...1.2) * (Float.random(in: 0...1) < 0.5 ? 1 : -1)
            let branchDir = SIMD2<Float>(
                mainDir.x * cos(angle) - mainDir.y * sin(angle),
                mainDir.x * sin(angle) + mainDir.y * cos(angle)
            )

            branch.points.append(branchPos)
            let branchLength = Int.random(in: 4...7)

            for _ in 1...branchLength {
                let segmentLength: Float = 10.0 + Float.random(in: -3...3)
                let jitter = SIMD2<Float>(Float.random(in: -4...4), Float.random(in: -4...4))
                branchPos += branchDir * segmentLength + jitter
                branch.points.append(branchPos)
            }

            activeBranches.append(branch)
            branchCooldown = Float.random(in: 0.08...0.25)
        }

        // Decay and remove old branches
        activeBranches = activeBranches.compactMap { branch in
            var b = branch
            b.decay -= 0.04  // ~25 frames to fully decay
            return b.decay > 0 ? b : nil
        }

        // Limit max branches
        if activeBranches.count > 6 {
            activeBranches.removeFirst()
        }
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

        // Use different pipeline and primitive type for lightning
        if trailEffect == .lightning, let lightningPipeline = lightningPipelineState {
            encoder.setRenderPipelineState(lightningPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        } else {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertices.count)
        }

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
