import Foundation
import Metal
import QuartzCore
import simd

/// Draws the tank: particles are splatted into a low-resolution density field,
/// which the composite pass turns into a smooth refracting liquid over the
/// live desktop image. Everything outside the liquid is left fully transparent
/// so the real desktop shows through the overlay window untouched.
final class LiquidRenderer {
    private struct ParticleUniforms {
        var fieldW: Float = 0
        var fieldH: Float = 0
        var bodyRadius: Float = 0
        var dropRadius: Float = 0
        var bodyWeight: Float = 0
        var dropWeight: Float = 0
        var cellScale: Float = 0
        var pad1: Float = 0
    }

    private struct CompositeUniforms {
        var viewW: Float = 0, viewH: Float = 0, fieldW: Float = 0, fieldH: Float = 0
        var cellPx: Float = 0, threshold: Float = 0, time: Float = 0, hasDesktop: Float = 0
        var columns: Float = 0, maxLOD: Float = 0, pad0: Float = 0, pad1: Float = 0
        var transR: Float = 0, transG: Float = 0, transB: Float = 0, absorption: Float = 0
        var deepR: Float = 0, deepG: Float = 0, deepB: Float = 0, refraction: Float = 0
        var glowR: Float = 0, glowG: Float = 0, glowB: Float = 0, caustics: Float = 0
        var specular: Float = 0, metallic: Float = 0, emissive: Float = 0, depthBlur: Float = 0
        var fallbackOpacity: Float = 0, pad2: Float = 0, pad3: Float = 0, pad4: Float = 0
    }

    static let fieldScale: Double = 0.25

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let particlePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let backdropPipeline: MTLRenderPipelineState

    // Snapshots rotate through a small ring so `prepare` never rewrites a
    // buffer the GPU may still be reading for an in-flight frame.
    private var particleBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var surfaceBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var slot = 0
    private var particleBuffer: MTLBuffer? { particleBuffers[slot] }
    private var surfaceBuffer: MTLBuffer? { surfaceBuffers[slot] }
    private var visibleCount = 0
    private var columns = 1
    private var restDensity: Float = 3
    private var fieldTexture: MTLTexture?
    private(set) var desktopTexture: MTLTexture?
    private var placeholderTexture: MTLTexture?

    /// Desktop image to refract; nil draws the untextured fallback look.
    var hasDesktop: Bool { desktopTexture != nil }

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.noCommandQueue }
        commandQueue = queue

        let library = try device.makeLibrary(source: LiquidShaders.source, options: nil)
        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat,
                      additive: Bool = false, over: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            if additive || over {
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        particlePipeline = try pipeline("particleVertex", "particleFragment",
                                        format: .rg16Float, additive: true)
        compositePipeline = try pipeline("fullscreenVertex", "compositeFragment",
                                         format: .bgra8Unorm, over: true)
        backdropPipeline = try pipeline("fullscreenVertex", "backdropFragment", format: .bgra8Unorm)
    }

    /// Copies a captured screen frame into a private, mipmapped texture so the
    /// liquid can blur what it refracts by depth.
    func updateDesktop(from source: MTLTexture) {
        var destination = desktopTexture
        if destination == nil || destination!.width != source.width || destination!.height != source.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: true
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .private
            destination = device.makeTexture(descriptor: descriptor)
        }
        guard let destination, let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, to: destination,
                  destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
        blit.generateMipmaps(for: destination)
        blit.endEncoding()
        buffer.commit()
        desktopTexture = destination
    }

    func clearDesktop() {
        desktopTexture = nil
    }

    /// Copies what the next frames need out of the simulation. Call only
    /// while the simulation is not stepping; `encode` never touches the tank,
    /// so drawing can continue while the next step runs on another thread.
    func prepare(from tank: Tank) {
        let simulation = tank.simulation
        columns = tank.columns
        restDensity = max(simulation.restDensity, 1)

        let next = (slot + 1) % particleBuffers.count
        let capacity = simulation.particleCount * 3 * MemoryLayout<Float>.stride
        if particleBuffers[next] == nil || particleBuffers[next]!.length < capacity {
            particleBuffers[next] = device.makeBuffer(length: capacity, options: .storageModeShared)
        }
        let surfaceLength = tank.columns * MemoryLayout<Float>.stride
        if surfaceBuffers[next] == nil || surfaceBuffers[next]!.length < surfaceLength {
            surfaceBuffers[next] = device.makeBuffer(length: surfaceLength, options: .storageModeShared)
        }
        guard let particleBuffer = particleBuffers[next], let surfaceBuffer = surfaceBuffers[next] else { return }

        // Positions are stored in cells measured from the screen's top-left;
        // the shaders scale them to whatever resolution is being drawn.
        let out = particleBuffer.contents().bindMemory(to: Float.self, capacity: simulation.particleCount * 3)
        let bottom = tank.screenBottom - 1.5
        let top = tank.screenTop + 1.5
        let screenTop = tank.screenTop
        var visible = 0
        for p in 0..<simulation.particleCount {
            let y = simulation.posY[p]
            guard y > bottom && y < top else { continue }
            let vx = simulation.velX[p]
            let vy = simulation.velY[p]
            let speed = (vx * vx + vy * vy).squareRoot()
            out[visible * 3] = simulation.posX[p] - 1
            out[visible * 3 + 1] = screenTop - y
            out[visible * 3 + 2] = min(max((speed - 55) / 140, 0), 1)
            visible += 1
        }
        visibleCount = visible

        let surface = surfaceBuffer.contents().bindMemory(to: Float.self, capacity: tank.columns)
        for i in 0..<tank.columns {
            surface[i] = screenTop - tank.surface[i]
        }
        slot = next
    }

    /// Encodes a frame from the last prepared snapshot into `target`. When
    /// `drawBackdrop` is true the desktop image is drawn underneath first
    /// (offscreen previews); the live overlay leaves it transparent instead.
    func encode(theme: LiquidTheme, time: Double, into target: MTLTexture,
                commandBuffer: MTLCommandBuffer, drawBackdrop: Bool = false) {
        let viewW = target.width
        let viewH = target.height
        let fieldW = max(Int(Double(viewW) * Self.fieldScale), 8)
        let fieldH = max(Int(Double(viewH) * Self.fieldScale), 8)
        guard let field = ensureField(width: fieldW, height: fieldH) else { return }

        let fieldCell = Float(fieldW) / Float(columns)
        let viewCell = Float(viewW) / Float(columns)

        let fieldPass = MTLRenderPassDescriptor()
        fieldPass.colorAttachments[0].texture = field
        fieldPass.colorAttachments[0].loadAction = .clear
        fieldPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        fieldPass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: fieldPass) {
            if visibleCount > 0, let particleBuffer {
                let bodyRadius: Float = 1.15
                let sigma = bodyRadius * 0.5
                var uniforms = ParticleUniforms(
                    fieldW: Float(fieldW), fieldH: Float(fieldH),
                    bodyRadius: bodyRadius * fieldCell, dropRadius: 0.42 * fieldCell,
                    bodyWeight: 1 / (restDensity * .pi * sigma * sigma),
                    dropWeight: 0.95, cellScale: fieldCell
                )
                encoder.setRenderPipelineState(particlePipeline)
                encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                       instanceCount: visibleCount)
            }
            encoder.endEncoding()
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let desktop = desktopTexture ?? placeholder()
        if drawBackdrop, let desktop {
            encoder.setRenderPipelineState(backdropPipeline)
            encoder.setFragmentTexture(desktop, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if visibleCount > 0, let surfaceBuffer, let desktop {
            var uniforms = CompositeUniforms()
            uniforms.viewW = Float(viewW)
            uniforms.viewH = Float(viewH)
            uniforms.fieldW = Float(fieldW)
            uniforms.fieldH = Float(fieldH)
            uniforms.cellPx = viewCell
            uniforms.threshold = 0.5
            uniforms.time = Float(time.truncatingRemainder(dividingBy: 3600))
            uniforms.hasDesktop = desktopTexture != nil ? 1 : 0
            uniforms.columns = Float(columns)
            uniforms.maxLOD = Float(max(desktop.mipmapLevelCount - 1, 0))
            uniforms.transR = theme.transmission.x
            uniforms.transG = theme.transmission.y
            uniforms.transB = theme.transmission.z
            uniforms.absorption = theme.absorption
            uniforms.deepR = theme.deep.x
            uniforms.deepG = theme.deep.y
            uniforms.deepB = theme.deep.z
            uniforms.refraction = theme.refraction
            uniforms.glowR = theme.glow.x
            uniforms.glowG = theme.glow.y
            uniforms.glowB = theme.glow.z
            uniforms.caustics = theme.caustics
            uniforms.specular = theme.specular
            uniforms.metallic = theme.metallic
            uniforms.emissive = theme.emissive
            uniforms.depthBlur = theme.depthBlur
            uniforms.fallbackOpacity = theme.fallbackOpacity

            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(field, index: 0)
            encoder.setFragmentTexture(desktop, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            encoder.setFragmentBuffer(surfaceBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// True when the last snapshot has any liquid on screen.
    var hasVisibleLiquid: Bool { visibleCount > 0 }

    private func ensureField(width: Int, height: Int) -> MTLTexture? {
        if let fieldTexture, fieldTexture.width == width, fieldTexture.height == height {
            return fieldTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        fieldTexture = device.makeTexture(descriptor: descriptor)
        return fieldTexture
    }

    private func placeholder() -> MTLTexture? {
        if let placeholderTexture { return placeholderTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        placeholderTexture = device.makeTexture(descriptor: descriptor)
        return placeholderTexture
    }

    enum RendererError: LocalizedError {
        case noCommandQueue
        var errorDescription: String? { "Could not create a Metal command queue." }
    }
}
