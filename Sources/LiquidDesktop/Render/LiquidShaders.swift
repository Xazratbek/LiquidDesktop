import Foundation

/// Metal source compiled at runtime (the offline `metal` compiler ships only
/// with Xcode, so this keeps the project buildable with Command Line Tools).
enum LiquidShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

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

    fragment float4 backdropFragment(FSOut in [[stage_in]],
                                     texture2d<float> desktop [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return float4(desktop.sample(s, in.uv).rgb, 1.0);
    }

    // MARK: particles -> density field

    struct ParticleUniforms {
        float fieldW;
        float fieldH;
        float bodyRadius;
        float dropRadius;
        float bodyWeight;
        float dropWeight;
        float cellScale;
        float pad1;
    };

    struct ParticleOut {
        float4 position [[position]];
        float2 local;
        float foam;
    };

    vertex ParticleOut particleVertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      constant float *particles [[buffer(0)]],
                                      constant ParticleUniforms &u [[buffer(1)]]) {
        const float2 corners[4] = { float2(-1.0, -1.0), float2(1.0, -1.0),
                                    float2(-1.0,  1.0), float2(1.0,  1.0) };
        float2 center = float2(particles[iid * 3], particles[iid * 3 + 1]) * u.cellScale;
        float2 corner = corners[vid];
        float2 p = center + corner * u.bodyRadius;
        ParticleOut out;
        out.position = float4(p.x / u.fieldW * 2.0 - 1.0, 1.0 - p.y / u.fieldH * 2.0, 0.0, 1.0);
        out.local = corner;
        out.foam = particles[iid * 3 + 2];
        return out;
    }

    fragment float4 particleFragment(ParticleOut in [[stage_in]],
                                     constant ParticleUniforms &u [[buffer(0)]]) {
        float r2 = dot(in.local, in.local);
        if (r2 > 1.0) { discard_fragment(); }
        float body = exp(-r2 * 4.0) * u.bodyWeight;
        float ratio = u.bodyRadius / max(u.dropRadius, 0.001);
        float drop = exp(-r2 * ratio * ratio * 3.0) * in.foam * u.dropWeight;
        return float4(body, drop, 0.0, 0.0);
    }

    // MARK: composite

    struct CompositeUniforms {
        float viewW;  float viewH;  float fieldW;  float fieldH;
        float cellPx; float threshold; float time; float hasDesktop;
        float columns; float maxLOD; float pad0; float pad1;
        float transR; float transG; float transB; float absorption;
        float deepR;  float deepG;  float deepB;  float refraction;
        float glowR;  float glowG;  float glowB;  float caustics;
        float specular; float metallic; float emissive; float depthBlur;
        float fallbackOpacity; float pad2; float pad3; float pad4;
    };

    float4 cubicWeights(float v) {
        float4 n = float4(1.0, 2.0, 3.0, 4.0) - v;
        float4 s = n * n * n;
        float x = s.x;
        float y = s.y - 4.0 * s.x;
        float z = s.z - 4.0 * s.y + 6.0 * s.x;
        float w = 6.0 - x - y - z;
        return float4(x, y, z, w) * (1.0 / 6.0);
    }

    // B-spline bicubic filtering from four bilinear taps; turns the
    // low-resolution density field into a smooth, round-edged surface.
    float4 sampleBicubic(texture2d<float> t, sampler s, float2 uv) {
        float2 size = float2(t.get_width(), t.get_height());
        float2 inv = 1.0 / size;
        float2 p = uv * size - 0.5;
        float2 f = fract(p);
        p -= f;
        float4 xc = cubicWeights(f.x);
        float4 yc = cubicWeights(f.y);
        float4 c = p.xxyy + float2(-0.5, 1.5).xyxy;
        float4 sums = float4(xc.xz + xc.yw, yc.xz + yc.yw);
        float4 offset = (c + float4(xc.yw, yc.yw) / sums) * inv.xxyy;
        float4 s0 = t.sample(s, offset.xz);
        float4 s1 = t.sample(s, offset.yz);
        float4 s2 = t.sample(s, offset.xw);
        float4 s3 = t.sample(s, offset.yw);
        float sx = sums.x / (sums.x + sums.y);
        float sy = sums.z / (sums.z + sums.w);
        return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
    }

    float fieldValue(texture2d<float> t, sampler s, float2 uv) {
        float4 v = t.sample(s, uv);
        return max(v.r, v.g);
    }

    float ripple(float2 q, float t) {
        return sin(q.x * 0.55 + t * 1.7 + sin(q.y * 0.40 - t * 0.9) * 1.3) * 0.5
             + sin(q.y * 0.70 - t * 1.3 + sin(q.x * 0.33 + t * 0.8) * 1.5) * 0.5
             + sin((q.x + q.y) * 1.10 + t * 2.3) * 0.25;
    }

    float2 hash2(float2 p) {
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        return fract(sin(p) * 43758.5453);
    }

    // Animated Worley (F2 - F1) edge network, warped by the ripple field:
    // thin bright lines for water caustics, cracks for the lava crust.
    float caustic(float2 uv, float t) {
        float total = 0.0;
        float scale = 1.0;
        float weight = 1.0;
        for (int octave = 0; octave < 2; octave++) {
            float2 p = uv * scale
                     + float2(ripple(uv * 0.55 * scale, t * 0.45), ripple(uv.yx * 0.5 * scale + 7.0, t * 0.38)) * 0.7;
            float2 cell = floor(p);
            float2 local = fract(p);
            float f1 = 8.0;
            float f2 = 8.0;
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float2 o = float2(x, y);
                    float2 h = hash2(cell + o);
                    float2 site = o + 0.5 + 0.42 * sin(t * 0.6 + 6.2831 * h);
                    float d = length(site - local);
                    if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
                }
            }
            float line = 1.0 - smoothstep(0.0, 0.07, f2 - f1);
            total += weight * line * line * line;
            scale *= 2.3;
            weight *= 0.35;
        }
        return total;
    }

    fragment float4 compositeFragment(FSOut in [[stage_in]],
                                      texture2d<float> field [[texture(0)]],
                                      texture2d<float> desktop [[texture(1)]],
                                      constant CompositeUniforms &u [[buffer(0)]],
                                      constant float *surface [[buffer(1)]]) {
        constexpr sampler lin(filter::linear, address::clamp_to_edge);
        constexpr sampler mip(filter::linear, mip_filter::linear, address::clamp_to_edge);

        float2 uv = in.uv;
        float2 view = float2(u.viewW, u.viewH);
        float2 px = uv * view;
        float2 texel = 1.0 / float2(u.fieldW, u.fieldH);

        float4 f = sampleBicubic(field, lin, uv);
        float value = max(f.r, f.g);
        float aa = max(fwidth(value) * 0.8, 0.003);
        float mask = smoothstep(u.threshold - aa, u.threshold + aa, value);
        if (mask <= 0.0005) { return float4(0.0); }

        float3 transmission = float3(u.transR, u.transG, u.transB);
        float3 deep = float3(u.deepR, u.deepG, u.deepB);
        float3 glow = float3(u.glowR, u.glowG, u.glowB);
        float t = u.time;

        float gx = fieldValue(field, lin, uv + float2(texel.x * 1.5, 0.0))
                 - fieldValue(field, lin, uv - float2(texel.x * 1.5, 0.0));
        float gy = fieldValue(field, lin, uv + float2(0.0, texel.y * 1.5))
                 - fieldValue(field, lin, uv - float2(0.0, texel.y * 1.5));
        float2 grad = float2(gx, gy);
        float edge = 1.0 - smoothstep(u.threshold, u.threshold + 0.45, value);

        float columns = u.columns;
        float colF = clamp(px.x / u.cellPx - 0.5, 0.0, columns - 1.0);
        int i0 = int(floor(colF));
        int i1 = min(i0 + 1, int(columns) - 1);
        float surfaceY = mix(surface[i0], surface[i1], fract(colF)) * u.cellPx;
        float depthPx = max(px.y - surfaceY, 0.0);
        float depthN = depthPx / u.viewH;
        float detached = step(px.y, surfaceY - u.cellPx * 0.9);

        float2 q = px / u.cellPx;
        float r0 = ripple(q, t);
        float2 rippleN = float2(ripple(q + float2(0.35, 0.0), t) - r0,
                                ripple(q + float2(0.0, 0.35), t) - r0);
        float settled = smoothstep(0.0, u.cellPx * 2.0, depthPx);

        float2 lens = -grad * edge * u.refraction * u.cellPx * 3.0
                    + rippleN * u.refraction * u.cellPx * 0.25 * settled;
        float3 normal = normalize(float3(-grad * 3.0 * edge + rippleN * 0.45 * settled, 1.0));

        float3 color;
        if (u.hasDesktop > 0.5) {
            float lod = min(depthN * u.depthBlur * 12.0 + edge * 0.8, u.maxLOD);
            float2 duv = lens / view;
            float2 ca = duv * 0.12;
            float3 bg = float3(desktop.sample(mip, uv + duv + ca, level(lod)).r,
                               desktop.sample(mip, uv + duv,      level(lod)).g,
                               desktop.sample(mip, uv + duv - ca, level(lod)).b);
            float3 absorb = (1.0 - transmission) * u.absorption;
            float3 transmit = exp(-absorb * (depthN * 3.0 + 0.1));
            color = bg * transmit + deep * (1.0 - transmit);
        } else {
            color = mix(deep * 1.5, deep * 0.7, saturate(depthN * 3.0));
        }

        float patches = smoothstep(0.05, 0.95, ripple(q * 0.045, t * 0.3));
        float causticLight = caustic(px / (u.cellPx * 7.0), t * 0.9 + 23.0)
                           * u.caustics * patches * exp(-depthN * 2.6) * (1.0 - detached);
        color += glow * causticLight * 0.2;

        float meniscus = exp(-depthPx / (u.cellPx * 0.45)) * (1.0 - detached);
        color = mix(color, glow, meniscus * 0.32);
        float rim = edge * edge;
        color += glow * rim * 0.22;

        float3 light = normalize(float3(-0.35, -0.8, 0.5));
        float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
        float spec = pow(saturate(dot(normal, halfway)), 70.0) * u.specular;
        color += glow * spec;

        if (u.metallic > 0.0) {
            // Liquid chrome: a sharp, lens-warped mirror of the desktop above
            // the surface, flattened to steel tones, over horizontal
            // reflection bands that follow the depth and the surface slope.
            float2 warp = lens * 2.5 / view;
            float2 ruv = float2(uv.x + warp.x, (surfaceY * 2.0 - px.y) / u.viewH + warp.y);
            ruv = clamp(ruv, float2(0.001), float2(0.999));
            float3 env = u.hasDesktop > 0.5 ? desktop.sample(mip, ruv, level(1.2)).rgb : float3(0.55);
            float lum = dot(env, float3(0.3, 0.59, 0.11));
            float bandPhase = depthPx / (u.cellPx * 3.2) + normal.y * 6.0 + normal.x * 2.0;
            float bands = 0.5 + 0.5 * sin(bandPhase);
            float horizon = exp(-depthPx / (u.cellPx * 2.5));
            float tone = lum * 0.55 + bands * 0.35 + horizon * 0.45 - depthN * 0.9 + (1.0 - normal.z) * 1.6;
            float3 steel = mix(deep, transmission, smoothstep(0.08, 0.92, tone));
            steel = mix(steel, env * transmission, 0.12);
            steel += glow * (spec * 1.6 + pow(rim, 1.5) * 0.55 + horizon * 0.15);
            color = mix(color, steel, u.metallic);
        }

        if (u.emissive > 0.0) {
            // Magma: dark cooling crust broken by slowly drifting glowing
            // veins, hotter near the surface and wherever the flow is fast.
            float cracks = caustic(px / (u.cellPx * 11.0) + float2(0.0, t * 0.01), t * 0.15 + 5.0);
            float smoulder = 0.10 + 0.08 * ripple(q * 0.12, t * 0.3);
            float hotspots = saturate(0.3 + 0.7 * ripple(q * 0.09 + 11.0, t * 0.25));
            float heat = saturate(cracks * 0.8 * hotspots + smoulder + rim * 0.7 + meniscus * 0.55
                                  + f.g * 0.8 + exp(-depthN * 5.0) * 0.18 - depthN * 0.3);
            float3 ember = mix(deep, float3(0.72, 0.08, 0.02), smoothstep(0.0, 0.35, heat));
            ember = mix(ember, glow, smoothstep(0.3, 0.75, heat));
            ember = mix(ember, float3(1.0, 0.92, 0.55), smoothstep(0.75, 1.0, heat));
            color = mix(color, ember + glow * spec * 0.25, u.emissive);
        }

        float alpha = mask;
        if (u.hasDesktop < 0.5) {
            alpha *= mix(u.fallbackOpacity, 1.0, saturate(meniscus + rim + spec));
        }
        return float4(saturate(color) * alpha, alpha);
    }
    """
}
