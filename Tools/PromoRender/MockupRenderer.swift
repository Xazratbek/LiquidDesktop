import Foundation
import Metal
import simd

/// Draws a stylised 3D MacBook whose display shows a live texture, with the
/// lid at any angle, over a soft studio backdrop. Used for marketing footage.
final class MockupRenderer {
    struct Frame {
        var lidAngle: Double
        var cameraEye: SIMD3<Float>
        var cameraTarget: SIMD3<Float>
        var fovY: Float
        var glow: SIMD3<Float>
        var overlays: [(texture: MTLTexture, alpha: Float)] = []
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 viewProjection;
        float glowR; float glowG; float glowB; float aspect;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
        float2 size;
        float material;
    };

    struct FSOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex FSOut fullscreenVertex(uint vid [[vertex_id]]) {
        float2 uv = float2((vid << 1) & 2, vid & 2);
        FSOut out;
        out.uv = uv;
        out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
        return out;
    }

    fragment float4 backdropFragment(FSOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 p = in.uv - float2(0.5, 0.52);
        p.x *= u.aspect;
        float glow = exp(-dot(p, p) * 3.2);
        float3 top = float3(0.035, 0.04, 0.09);
        float3 bottom = float3(0.012, 0.012, 0.03);
        float3 c = mix(top, bottom, in.uv.y);
        c += float3(u.glowR, u.glowG, u.glowB) * glow * 0.42;
        float vignette = smoothstep(1.25, 0.35, length(p));
        return float4(c * vignette, 1.0);
    }

    fragment float4 overlayFragment(FSOut in [[stage_in]],
                                    texture2d<float> image [[texture(0)]],
                                    constant float &alpha [[buffer(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return image.sample(s, in.uv) * alpha;
    }

    vertex VOut mockVertex(uint vid [[vertex_id]],
                           constant float *v [[buffer(0)]],
                           constant Uniforms &u [[buffer(1)]]) {
        uint b = vid * 8;
        VOut out;
        out.position = u.viewProjection * float4(v[b], v[b + 1], v[b + 2], 1.0);
        out.uv = float2(v[b + 3], v[b + 4]);
        out.size = float2(v[b + 5], v[b + 6]);
        out.material = v[b + 7];
        return out;
    }

    float roundedBox(float2 uv, float2 size, float radius) {
        float2 p = (uv - 0.5) * size;
        float2 q = abs(p) - (size * 0.5 - radius);
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }

    float boxMask(float2 p, float2 lo, float2 hi, float radius) {
        float2 size = hi - lo;
        float d = roundedBox((p - lo) / size, size, radius);
        float w = max(fwidth(d), 1e-4);
        return 1.0 - smoothstep(-w, w, d);
    }

    fragment float4 mockFragment(VOut in [[stage_in]],
                                 texture2d<float> display [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        int material = int(in.material + 0.5);

        if (material == 0) {
            float3 c = display.sample(s, in.uv).rgb;
            float sheen = exp(-pow((in.uv.x * 0.8 + in.uv.y * 0.6 - 0.35) * 3.5, 2.0)) * 0.045;
            return float4(c + sheen, 1.0);
        }
        if (material == 1) {
            float d = roundedBox(in.uv, in.size, 0.06);
            float w = max(fwidth(d), 1e-4);
            float mask = 1.0 - smoothstep(-w, w, d);
            float3 c = mix(float3(0.07, 0.07, 0.08), float3(0.025, 0.025, 0.03), in.uv.y);
            float rim = smoothstep(-0.012, 0.0, d) * 0.35;
            return float4(c + rim * float3(0.5, 0.52, 0.56), mask);
        }
        if (material == 2) {
            float2 p = in.uv * in.size;
            float d = roundedBox(in.uv, in.size, 0.07);
            float w = max(fwidth(d), 1e-4);
            float mask = 1.0 - smoothstep(-w, w, d);
            float3 alu = mix(float3(0.80, 0.81, 0.84), float3(0.63, 0.64, 0.68), in.uv.y);
            float well = boxMask(p, float2(0.14, 0.07), float2(in.size.x - 0.14, 0.74), 0.03);
            float2 key = fract(p / float2(0.1235, 0.1235));
            float keyShape = step(0.09, key.x) * step(key.x, 0.91) * step(0.09, key.y) * step(key.y, 0.91);
            float3 keyboard = mix(float3(0.10, 0.10, 0.11), float3(0.16, 0.16, 0.18), keyShape);
            float3 c = mix(alu, keyboard, well);
            float pad = boxMask(p, float2(in.size.x * 0.31, 0.83), float2(in.size.x * 0.69, in.size.y - 0.09), 0.04);
            float padEdge = boxMask(p, float2(in.size.x * 0.31 - 0.006, 0.824), float2(in.size.x * 0.69 + 0.006, in.size.y - 0.084), 0.045) - pad;
            c = mix(c, alu * 1.04, pad);
            c -= padEdge * 0.12;
            return float4(c, mask);
        }
        if (material == 3) {
            float3 c = mix(float3(0.55, 0.56, 0.60), float3(0.30, 0.30, 0.33), in.uv.y);
            return float4(c, 1.0);
        }
        float2 q = (in.uv - 0.5) * float2(1.0, 2.0);
        float a = (1.0 - smoothstep(0.08, 0.52, length(q))) * 0.7;
        return float4(0.0, 0.0, 0.0, a);
    }
    """

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var glowR: Float
        var glowG: Float
        var glowB: Float
        var aspect: Float
    }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let width: Int
    let height: Int
    let output: MTLTexture
    private let msaaColor: MTLTexture
    private let msaaDepth: MTLTexture
    private let backdropPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let mockPipeline: MTLRenderPipelineState
    private let overlayPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let noDepthState: MTLDepthStencilState

    private static let sampleCount = 4
    private static let baseDepth: Float = 1.38
    private static let lidHeight: Float = 1.34
    private static let displayWidth: Float = 1.9
    private static let displayHeight: Float = 1.9 / 1.5397
    private static let chin: Float = 0.07

    init(device: MTLDevice, queue: MTLCommandQueue, width: Int, height: Int) throws {
        self.device = device
        self.queue = queue
        self.width = width
        self.height = height

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .shared
        output = device.makeTexture(descriptor: outputDescriptor)!

        let color = MTLTextureDescriptor()
        color.textureType = .type2DMultisample
        color.pixelFormat = .bgra8Unorm
        color.width = width
        color.height = height
        color.sampleCount = Self.sampleCount
        color.usage = [.renderTarget]
        color.storageMode = .private
        msaaColor = device.makeTexture(descriptor: color)!
        let depth = MTLTextureDescriptor()
        depth.textureType = .type2DMultisample
        depth.pixelFormat = .depth32Float
        depth.width = width
        depth.height = height
        depth.sampleCount = Self.sampleCount
        depth.usage = [.renderTarget]
        depth.storageMode = .private
        msaaDepth = device.makeTexture(descriptor: depth)!

        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        func pipeline(_ vertex: String, _ fragment: String, blend: Bool, alphaToCoverage: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.rasterSampleCount = Self.sampleCount
            d.depthAttachmentPixelFormat = .depth32Float
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            d.isAlphaToCoverageEnabled = alphaToCoverage
            if blend {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                d.colorAttachments[0].sourceAlphaBlendFactor = .one
                d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        backdropPipeline = try pipeline("fullscreenVertex", "backdropFragment", blend: false)
        shadowPipeline = try pipeline("mockVertex", "mockFragment", blend: true)
        mockPipeline = try pipeline("mockVertex", "mockFragment", blend: false, alphaToCoverage: true)
        let overlay = MTLRenderPipelineDescriptor()
        overlay.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        overlay.fragmentFunction = library.makeFunction(name: "overlayFragment")
        overlay.rasterSampleCount = Self.sampleCount
        overlay.depthAttachmentPixelFormat = .depth32Float
        overlay.colorAttachments[0].pixelFormat = .bgra8Unorm
        overlay.colorAttachments[0].isBlendingEnabled = true
        overlay.colorAttachments[0].sourceRGBBlendFactor = .one
        overlay.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        overlay.colorAttachments[0].sourceAlphaBlendFactor = .one
        overlay.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        overlayPipeline = try device.makeRenderPipelineState(descriptor: overlay)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!
        let off = MTLDepthStencilDescriptor()
        off.depthCompareFunction = .always
        off.isDepthWriteEnabled = false
        noDepthState = device.makeDepthStencilState(descriptor: off)!
    }

    func render(display: MTLTexture, frame: Frame) {
        let theta = Float(frame.lidAngle * .pi / 180)
        let direction = SIMD3<Float>(0, sin(theta), cos(theta))
        let normal = SIMD3<Float>(0, -cos(theta), sin(theta))
        var vertices: [Float] = []

        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                  uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>), size: SIMD2<Float>, material: Float) {
            for (p, t) in [(a, uv.0), (b, uv.1), (c, uv.2), (a, uv.0), (c, uv.2), (d, uv.3)] {
                vertices += [p.x, p.y, p.z, t.x, t.y, size.x, size.y, material]
            }
        }
        func lidPoint(_ x: Float, _ h: Float, _ offset: Float) -> SIMD3<Float> {
            SIMD3(x, 0, 0) + direction * h + normal * offset
        }

        let depth = Self.baseDepth
        // Floor shadow first (blended, no depth).
        var shadow: [Float] = []
        do {
            let y: Float = -0.047
            let a = SIMD3<Float>(-1.7, y, -0.9), b = SIMD3<Float>(1.7, y, -0.9)
            let c = SIMD3<Float>(1.7, y, depth + 0.7), d = SIMD3<Float>(-1.7, y, depth + 0.7)
            for (p, t) in [(a, SIMD2<Float>(0, 0)), (b, SIMD2(1, 0)), (c, SIMD2(1, 1)), (a, SIMD2(0, 0)), (c, SIMD2(1, 1)), (d, SIMD2(0, 1))] {
                shadow += [p.x, p.y, p.z, t.x, t.y, 1, 1, 4]
            }
        }

        quad(SIMD3(-1, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, depth), SIMD3(-1, 0, depth),
             uv: (SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)), size: SIMD2(2, depth), material: 2)
        quad(SIMD3(-0.985, 0, depth), SIMD3(0.985, 0, depth), SIMD3(0.985, -0.045, depth - 0.01), SIMD3(-0.985, -0.045, depth - 0.01),
             uv: (SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)), size: SIMD2(2, 0.045), material: 3)
        let lidH = Self.lidHeight
        quad(lidPoint(-1, 0, -0.004), lidPoint(1, 0, -0.004), lidPoint(1, lidH, -0.004), lidPoint(-1, lidH, -0.004),
             uv: (SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)), size: SIMD2(2, lidH), material: 1)
        let half = Self.displayWidth / 2
        let bottom = Self.chin
        let top = Self.chin + Self.displayHeight
        quad(lidPoint(-half, bottom, 0.002), lidPoint(half, bottom, 0.002), lidPoint(half, top, 0.002), lidPoint(-half, top, 0.002),
             uv: (SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)), size: SIMD2(Self.displayWidth, Self.displayHeight), material: 0)

        let aspect = Float(width) / Float(height)
        var uniforms = Uniforms(
            viewProjection: Self.perspective(fovY: frame.fovY, aspect: aspect, near: 0.1, far: 50)
                * Self.lookAt(eye: frame.cameraEye, center: frame.cameraTarget, up: SIMD3(0, 1, 0)),
            glowR: frame.glow.x, glowG: frame.glow.y, glowB: frame.glow.z, aspect: aspect
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaColor
        pass.colorAttachments[0].resolveTexture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.depthAttachment.texture = msaaDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare

        let commandBuffer = queue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setDepthStencilState(noDepthState)
        encoder.setRenderPipelineState(backdropPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setVertexBytes(shadow, length: shadow.count * MemoryLayout<Float>.stride, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(display, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        encoder.setDepthStencilState(depthState)
        encoder.setRenderPipelineState(mockPipeline)
        let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)!
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(display, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 8)

        encoder.setDepthStencilState(noDepthState)
        encoder.setRenderPipelineState(overlayPipeline)
        for overlay in frame.overlays where overlay.alpha > 0.001 {
            var alpha = overlay.alpha
            encoder.setFragmentTexture(overlay.texture, index: 0)
            encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0), SIMD4(s.y, u.y, -f.y, 0), SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}
