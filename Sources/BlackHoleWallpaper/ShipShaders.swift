// Metal source for ships and stations (stage 3): triangle meshes rasterised into a tile with depth and
// 4x MSAA, then copied into the body atlas. Placed after the body shaders in Shaders.swift.
//
//   shipVert   model (x forward, y left, z up, longest side 1) into the sprite frame of the tile
//   shipFrag   physically based: metallic and roughness per part, GGX highlights of the disk and the
//              brightest near star, the sky and the disk mirrored in the hull, baked occlusion, plates
//              with their own tilt and tone, wear; windows, engines and lamps glow. Premultiplied linear.
//   bakeShipEnv  the sky around the hole for reflections: nebula and stars by direction (camera frame),
//              equirectangular, mipmapped for rough surfaces. Baked once per look.

let shipShaderSource = #"""
// ---------------------------------------------------------------- ships

// Blended variant: see-through parts (membranes, cut-out and blended model materials). The opaque variant
// has no blending and never discards, so the GPU shades only the front surface of each pixel.
constant bool shipBlendFC [[function_constant(20)]];
constant bool shipBlend = is_function_constant_defined(shipBlendFC) && shipBlendFC;

struct ShipP {
    float4 r0, r1, r2;   // model -> sprite rows (sprite unit: half the ship's length). w: tile extent, stretch, shrink
    float4 l0, c0, l1, c1;
    float4 amb;          // ambient rgb, panels per length
    float4 hull;         // hull tint rgb, window lights
    float4 glowC;        // glow colour rgb, glow strength
    float4 a;            // seed, time, fade, flash
    float4 s0, s1, s2;   // sprite -> camera frame rows (sky lookup). w: gloss, wear, reflection
    float4 hole;         // hole centre seen from the ship (sprite frame, M), disk inner radius
    float4 dn;           // disk normal (sprite frame), disk outer radius
    float4 dIn;          // disk radiance at the inner edge, sky brightness
    float4 dOut;         // disk radiance at the outer edge, shadow radius (M)
    float4 fin;          // hull metallic, hull roughness, sky key, angular size of the disk light (rad)
};

// Material of a model file part (glTF metallic-roughness); built-in ships draw with tex = 0.
struct ShipM {
    float4 base;         // base colour factor
    float4 emis;         // emissive factor rgb, unused
    float4 pbr;          // metallic, roughness, normal scale, occlusion strength
    float4 tex;          // has base colour, metallic-roughness, normal, emissive texture
    float4 tex2;         // has occlusion texture, alpha cutoff (0 opaque, < 0 blended), unused, unused
};

struct ShipV {
    float4 pos [[position]];
    float3 n;            // sprite frame
    float3 mn;           // model frame
    float3 mp;           // model position
    float3 sp;           // sprite position
    float4 col;
    float2 uv;
    float ao;
    float2 fin [[flat]]; // metallic, roughness of the part (negative: the kind's default)
    float mat [[flat]];
    float win [[flat]];
};

vertex ShipV shipVert(uint vid [[vertex_id]], const device float4 *V [[buffer(0)]], constant ShipP &S [[buffer(1)]]) {
    float4 p = V[vid * 4], n = V[vid * 4 + 1], c = V[vid * 4 + 2], t = V[vid * 4 + 3];
    float3 q = p.xyz;
    // Events: stretch along the flight direction from the tail, shrink towards the centre.
    q.x += (q.x + 0.5) * (S.r1.w - 1.0);
    q *= S.r2.w;
    float3 sp = float3(dot(S.r0.xyz, q), dot(S.r1.xyz, q), dot(S.r2.xyz, q)) * 2.0;
    float ext = S.r0.w;
    ShipV o;
    o.pos = float4(sp.xy / ext, 0.5 - 0.45 * sp.z / ext, 1.0);
    o.n = float3(dot(S.r0.xyz, n.xyz), dot(S.r1.xyz, n.xyz), dot(S.r2.xyz, n.xyz));
    o.mn = n.xyz;
    o.mp = p.xyz;
    o.sp = sp;
    o.col = c;
    o.uv = t.xy;
    o.ao = t.z;
    o.fin = t.w < 0.0 ? float2(-1.0) : float2(floor(t.w / 256.0), fmod(t.w, 256.0)) / 255.0;
    o.mat = p.w;
    o.win = n.w;
    return o;
}

static float shipLight(float3 N, float4 l) { return saturate((dot(N, l.xyz) + l.w) / (1.0 + l.w)); }

// GGX highlight of a light of angular size `size` (rad), times n.l and pi, without Fresnel.
static float shipGGX(float3 N, float3 L, float rough, float size) {
    const float3 V = float3(0.0, 0.0, 1.0);
    float NoL = dot(N, L);
    if (NoL <= 0.0) return 0.0;
    float3 H = normalize(L + V);
    float NoH = saturate(dot(N, H)), NoV = max(N.z, 0.05);
    float a = max(rough * rough, 0.004 + size);
    float a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * d * d);
    float k = (rough + 1.0) * (rough + 1.0) * 0.125;
    float G = NoL / (NoL * (1.0 - k) + k) * NoV / (NoV * (1.0 - k) + k);
    return min(D * G / (4.0 * NoL * NoV) * NoL * M_PI_F, 12.0);
}

// Split-sum environment response (Karis, mobile approximation).
static float3 shipEnvBRDF(float3 F0, float rough, float NoV) {
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = rough * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    float2 AB = float2(-1.04, 1.04) * a004 + r.zw;
    return F0 * AB.x + AB.y;
}

// Sky in a sprite-frame direction: the baked environment, sharper or blurrier by roughness.
static float3 shipSky(float3 R, float rough, constant ShipP &S, texture2d<float> env) {
    constexpr sampler es(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float3 d = float3(dot(S.s0.xyz, R), dot(S.s1.xyz, R), dot(S.s2.xyz, R));
    float2 uv = float2(atan2(d.y, d.x) * 0.15915494 + 0.5, acos(clamp(d.z, -1.0, 1.0)) * 0.31830989);
    float lod = sqrt(saturate(rough)) * float(env.get_num_mip_levels() - 1);
    // The disk's glow around the hole: a broad lobe in the hole's direction, wider on rough surfaces.
    float k = mix(24.0, 3.0, saturate(rough));
    float halo = pow(saturate(dot(R, normalize(S.hole.xyz)) * 0.5 + 0.5), k) * (0.35 + 0.65 * (1.0 - rough));
    return env.sample(es, uv, level(lod)).rgb * S.dIn.w + S.c0.rgb * halo * 0.35;
}

// The hole's disk mirrored along R: a flat ring around the hole, hot inside, and the shadow in front of it.
// Rough surfaces blur its edges; the GGX highlight of the disk light takes over from there.
static float3 shipDisk(float3 R, float rough, constant ShipP &S) {
    float3 H = S.hole.xyz, nD = S.dn.xyz;
    float rin = S.hole.w, rout = S.dn.w, rs = S.dOut.w;
    float tc = dot(H, R);
    float b = length(H - R * tc);
    float dn = dot(R, nD);
    float3 col = float3(0.0);
    if (abs(dn) > 1e-5) {
        float t = dot(H, nD) / dn;
        if (t > 0.0) {
            float r = length(R * t - H);
            float soft = max(t * rough * rough * 0.8, rin * 0.12);
            float m = smoothstep(rin - soft, rin + soft, r) * (1.0 - smoothstep(rout - soft * 2.0, rout + soft * 2.0, r));
            float x = saturate((r - rin) / max(rout - rin, 1e-3));
            // Gas in rings and streaks, like the disk on the screen; smoothed away on rough surfaces.
            float3 P = R * t - H;
            float3 u = normalize(cross(nD, abs(nD.z) < 0.9 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0)));
            float ang = atan2(dot(P, cross(nD, u)), dot(P, u));
            float3 gq = float3(r * 0.45, cos(ang) * 2.2, sin(ang) * 2.2);
            float gas = mix(0.85 * vnoise3(gq) + 0.15, 0.5, saturate(rough * 1.6));
            col = mix(S.dIn.rgb, S.dOut.rgb, sqrt(x)) * pow(rin / max(r, rin), 0.8) * m * (0.35 + 1.3 * gas);
            // Behind the shadow: the ray meets the dark sphere before the disk.
            if (tc > 0.0 && b < rs && tc - sqrt(rs * rs - b * b) < t) col *= smoothstep(rs * 0.85, rs, b);
        }
    }
    // The shadow itself in front of the sky: returned as a negative weight in w would be cleaner; the sky is
    // dimmed by the caller with shipShadow.
    return col * (1.0 - smoothstep(0.25, 0.75, rough));
}

static float shipShadow(float3 R, float rough, constant ShipP &S) {
    float3 H = S.hole.xyz;
    float tc = dot(H, R);
    if (tc <= 0.0) return 1.0;
    float b = length(H - R * tc);
    float rs = S.dOut.w * (1.0 + rough * 2.0);
    return mix(1.0, smoothstep(rs * 0.8, rs * 1.05, b), 1.0 - smoothstep(0.3, 0.8, rough));
}

fragment float4 shipFrag(ShipV in [[stage_in]], constant ShipP &S [[buffer(1)]], constant ShipM &M [[buffer(2)]],
                         texture2d<float> tBase [[texture(0)]], texture2d<float> tMR [[texture(1)]],
                         texture2d<float> tNorm [[texture(2)]], texture2d<float> tEmis [[texture(3)]],
                         texture2d<float> tOcc [[texture(4)]], texture2d<float> tEnv [[texture(5)]]) {
    constexpr sampler ts(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(4));
    const float3 V = float3(0.0, 0.0, 1.0);
    float3 N = normalize(in.n);
    float3 mn = normalize(in.mn);
    // Two-sided: a visible surface faces the camera.
    bool back = N.z < 0.0;
    if (back) { N = -N; mn = -mn; }
    int mat = int(in.mat + 0.5);
    float3 mp = in.mp;
    float seed = S.a.x;
    float gloss = S.s0.w, wear = S.s1.w, refl = S.s2.w;
    float3 base = in.col.rgb;
    if (mat == 0 || mat == 12) base *= S.hull.rgb;
    float ao = in.ao;

    // Plates: a lattice in model space cut by the surface. Lines only along the surface's own axes,
    // faded out where the plates get smaller than a few pixels.
    // Panels come in two sizes: a coarse lattice whose cells split in half along some axes, so the hull
    // reads as plates of different lengths, not as tiles.
    float dens = S.amb.w;
    float3 q = mp * dens;
    float3 qa = q * 0.5;
    float3 cellA = floor(qa);
    float3 fa = fract(qa);
    float3 split = step(0.42, hash33(cellA + seed * 0.53 + 2.0));
    float3 cell = cellA * 2.0 + floor(fa * 2.0) * split;
    float3 fw = fwidth(q);
    float tone = hash13(cell + seed * 0.37);
    float3 dEdge = min(fa, 1.0 - fa) * 2.0;
    float3 dMid = mix(float3(9.0), abs(fa - 0.5) * 2.0, split);
    float3 wgt = 1.0 - abs(mn);
    float fine = 1.0 - smoothstep(0.25, 0.6, max(max(fw.x, fw.y), fw.z));
    float3 lnE = (1.0 - smoothstep(float3(0.0), max(fw * 1.2, 0.03), dEdge)) * wgt;
    float3 lnM = (1.0 - smoothstep(float3(0.0), max(fw * 1.0, 0.025), dMid)) * wgt * 0.6;
    float3 ln = max(lnE, lnM) * fine;
    float lines = max(max(ln.x, ln.y), ln.z);
    float tone2 = hash13(cellA + seed * 0.11 + 5.0);
    // Wear: grime streaks run along the ship, gather in corners; plates differ more in tone.
    float streak = vnoise3(mp * float3(dens * 0.25, dens * 2.5, dens * 2.5) + seed);
    float grime = saturate((streak - 0.35) * 1.6) * (0.5 + 0.8 * (1.0 - ao));
    float var = 0.45 + 0.7 * wear;
    float3 alb = base * (1.0 + var * (0.2 * tone + 0.12 * tone2 - 0.16)) * (1.0 - (0.22 + 0.25 * wear) * lines) * (1.0 - wear * 0.55 * grime);

    // Finish: the part's own, else by kind; the hull takes the design's.
    float metal = 0.0, rough = 0.5;
    bool plated = true;
    float3 emit = float3(0.0);
    float alpha = 1.0;
    bool lit = true;
    switch (mat) {
        case 0: metal = S.fin.x; rough = S.fin.y; break;
        case 1: metal = 0.8; rough = 0.34; break;
        case 2: metal = 0.0; rough = 0.36; alb = base * (1.0 + var * (0.1 * tone - 0.05)) * (1.0 - 0.25 * lines) * (1.0 - wear * 0.25 * grime); break;
        case 4: {
            // Insulation foil: crinkled, metallic, the crinkles catch the light in facets.
            float3 cq = mp * dens * 1.3 + seed;
            float cr = vnoise3(cq) - 0.5, cr2 = vnoise3(cq * 2.7 + 4.0) - 0.5;
            float3 bend = float3(cr + 0.4 * cr2, -cr + 0.4 * cr2, 0.0) * 0.45 * (1.0 - smoothstep(0.4, 0.9, fw.x * 1.3));
            N = normalize(N + bend);
            alb = base * (0.75 + 0.3 * tone);
            metal = 1.0; rough = 0.26; plated = false;
            break;
        }
        case 5: {
            // Solar cells: dark blue under glass with a fine silver grid.
            float3 g = abs(fract(mp * dens * 2.0) - 0.5);
            float grid = 1.0 - smoothstep(0.0, max(fwidth(mp.x * dens * 2.0) * 1.5, 0.04), min(min(0.5 - g.x, 0.5 - g.y), 0.5 - g.z) + 0.02);
            alb = base * (1.0 + 0.6 * grid * (1.0 - smoothstep(0.3, 0.6, fw.x)));
            metal = 0.0; rough = 0.14; plated = false;
            break;
        }
        case 6: alb = base; metal = 0.0; rough = 0.04; plated = false; break;
        case 7: {
            // Borg: dark machinery. The light comes from the mesh: the core and the foot of every wall carry
            // emission in the vertex, so channels glow from inside, in the glow colour.
            alb = base * (0.8 + 0.4 * tone) * (1.0 - 0.2 * lines);
            float gw = in.col.w * in.col.w;
            emit = S.glowC.rgb * gw * gw * 0.3 * S.glowC.w;
            metal = 0.75; rough = 0.5;
            break;
        }
        case 8: {
            // Death Star: equatorial trench, superlaser dish in the northern half.
            float3 d = normalize(mp);
            float trench = 1.0 - smoothstep(0.004, 0.012, abs(d.z));
            float3 dc = normalize(float3(0.3, -0.62, 0.55));
            float cd = dot(d, dc);
            float dish = smoothstep(0.955, 0.962, cd);
            float ring = exp(-pow((cd - 0.958) / 0.003, 2.0));
            alb *= (1.0 - 0.55 * trench) * (1.0 - 0.35 * dish + 0.25 * ring);
            // The dish is concave: shade it as if lit from the other side.
            if (dish > 0.0) N = normalize(mix(N, reflect(-N, float3(0.0, 0.0, 1.0)) * float3(-1.0, -1.0, 1.0), 0.5 * dish));
            emit = float3(0.4, 1.0, 0.4) * exp(-pow((cd - 1.0) / 0.0006, 2.0)) * 2.0 * S.glowC.w;
            // Lights in the city-like surface.
            float lt = step(0.93, hash13(floor(q * 2.0) + 11.0)) * (1.0 - smoothstep(0.3, 0.7, fw.x * 2.0));
            emit += float3(1.0, 0.85, 0.6) * lt * 0.5 * S.hull.w;
            metal = 0.5; rough = 0.55;
            break;
        }
        case 3: case 10: {
            // Engines, nacelles, deflectors: glowing, a hot core where they face the camera.
            float3 gc = mat == 10 ? S.glowC.rgb : base;
            float k = (mat == 10 ? 1.0 : in.col.w) * S.glowC.w;
            float flick = 0.92 + 0.08 * sin(S.a.y * 9.0 + seed);
            emit = gc * k * (1.3 + 0.9 * N.z) * flick + float3(0.25) * k * pow(N.z, 4.0);
            lit = false;
            break;
        }
        case 9: {
            // Shimmering membrane (ring gate, stargate): light only, partly transparent.
            float r = length(mp.yz) * 6.0;
            float n = vnoise3(mp * 60.0 + S.a.y * 0.3) - 0.5;
            float w = 0.5 + 0.5 * sin(r * 14.0 - S.a.y * 2.5 + n * 2.0);
            float rim = smoothstep(0.55, 0.95, r / 3.0);
            emit = base * (0.12 + 0.18 * w * w + 0.35 * rim + 0.1 * n) * in.col.w * S.glowC.w;
            alpha = 0.3 + 0.3 * rim;
            // A gate open onto the other side (stage 4): a thin, watery skin over it.
            if (S.c0.w > 0.0) { alpha *= S.c0.w; emit *= 0.5 + 0.5 * S.c0.w; }
            lit = false;
            break;
        }
        case 11:
            // Lamp: always on, blinking softly.
            emit = base * in.col.w * (0.7 + 0.3 * sin(S.a.y * 3.0));
            lit = false;
            break;
        case 12: {
            // Model file: its own material, textures where it has them; a light touch of wear, no plates.
            float4 bc = M.base * float4(in.col.rgb, 1.0);
            if (M.tex.x > 0.5) {
                float4 t = tBase.sample(ts, in.uv);
                bc *= float4(pow(t.rgb, 2.2), t.a);
            }
            if (shipBlend) {
                alpha = bc.a;
                if (M.tex2.y > 0.0 && alpha < M.tex2.y) discard_fragment();
                if (M.tex2.y >= 0.0) alpha = 1.0;
            }
            alb = bc.rgb * (1.0 + var * 0.06 * (tone - 0.5)) * (1.0 - wear * 0.2 * grime);
            metal = M.pbr.x; rough = M.pbr.y;
            if (M.tex.y > 0.5) { float4 t = tMR.sample(ts, in.uv); rough *= t.g; metal *= t.b; }
            if (M.tex2.x > 0.5) ao = min(ao, mix(1.0, tOcc.sample(ts, in.uv).r, M.pbr.w));
            emit = M.emis.rgb;
            if (M.tex.w > 0.5) emit *= pow(tEmis.sample(ts, in.uv).rgb, 2.2);
            if (M.tex.z > 0.5) {
                // Normal map in a tangent frame from the derivatives of position and texture coordinates.
                float3 tn = tNorm.sample(ts, in.uv).xyz * 2.0 - 1.0;
                tn.xy *= M.pbr.z;
                float3 dp1 = dfdx(in.sp), dp2 = dfdy(in.sp);
                float2 du1 = dfdx(in.uv), du2 = dfdy(in.uv);
                float3 Ng = back ? -normalize(in.n) : normalize(in.n);
                float3 p2 = cross(dp2, Ng), p1 = cross(Ng, dp1);
                float3 T = p2 * du1.x + p1 * du2.x;
                float3 B = p2 * du1.y + p1 * du2.y;
                float im = rsqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
                // glTF: green points up in the picture, towards smaller v.
                N = normalize(T * im * tn.x - B * im * tn.y + N * max(tn.z, 0.05));
                if (N.z < 0.0) N = normalize(N - float3(0.0, 0.0, N.z * 1.05));
            }
            plated = false;
            break;
        }
        default: break;
    }
    if (in.fin.x >= 0.0) { metal = in.fin.x; rough = in.fin.y; }
    // Gloss slider: 1 keeps the finish, higher polishes, lower dulls. Wear roughens in patches.
    // Plates differ in sheen as in tone: some were polished, some not.
    if (plated) rough *= 0.8 + 0.4 * tone2;
    rough = clamp(rough * (1.5 - 0.5 * gloss) + wear * 0.18 * (streak - 0.3) + 0.08 * lines, 0.03, 1.0);

    if (plated && lit) {
        // Each plate sits at its own slight angle; seams bend in; fine hammered detail where it shows.
        float3 dm = (hash33(cell + seed * 0.21) - 0.5) * (0.03 + 0.04 * wear) * fine;
        dm -= mn * dot(dm, mn);
        float3 ds = float3(dot(S.r0.xyz, dm), dot(S.r1.xyz, dm), dot(S.r2.xyz, dm));
        N = normalize(N + ds * (back ? -1.0 : 1.0));
        if (N.z < 0.02) N = normalize(float3(N.xy, 0.02));
    }

    float3 col = emit;
    if (lit) {
        float NoV = max(N.z, 0.04);
        float3 F0 = mix(float3(0.04), alb, metal);
        float3 diff = alb * (1.0 - metal);
        // Diffuse: the disk and the near star, the sky around (from the blurriest level), a soft fill from
        // the camera side so the dark side keeps its shape.
        constexpr sampler ms(filter::linear, mip_filter::nearest);
        float3 skyN = tEnv.sample(ms, float2(0.5), level(float(tEnv.get_num_mip_levels() - 1))).rgb * S.dIn.w
                    + S.c0.rgb * 0.06 * saturate(dot(N, normalize(S.hole.xyz)) * 0.5 + 0.5);
        float aoD = mix(1.0, ao * ao, 0.55);
        float3 irr = (S.c0.rgb * shipLight(N, S.l0) + S.c1.rgb * shipLight(N, S.l1)) * aoD
                   + (S.amb.rgb + skyN * 0.6 + (S.c0.rgb * 0.03 + float3(0.012, 0.015, 0.022)) * (0.4 + 0.6 * N.z)) * ao;
        col += diff * irr;
        // Highlights of the two lights, Fresnel by the half vector.
        float3 H0 = normalize(S.l0.xyz + V), H1 = normalize(S.l1.xyz + V);
        float3 Fa = F0 + (1.0 - F0) * pow(1.0 - saturate(dot(V, H0)), 5.0);
        float3 Fb = F0 + (1.0 - F0) * pow(1.0 - saturate(dot(V, H1)), 5.0);
        float sharpDisk = smoothstep(0.2, 0.55, rough);
        col += (S.c0.rgb * Fa * shipGGX(N, S.l0.xyz, rough, S.fin.w) * mix(0.45, 1.0, sharpDisk)
             + S.c1.rgb * Fb * shipGGX(N, S.l1.xyz, rough, S.l1.w)) * aoD;
        // Reflections: sky and disk along R, weighted by the split-sum response; occluded in corners.
        float3 R = reflect(-V, N);
        // A faint even sky on top keeps polished metal from going black where nothing bright is mirrored.
        float3 env = (shipSky(R, rough, S, tEnv) + S.amb.rgb * 2.0 + S.c0.rgb * 0.015) * shipShadow(R, rough, S) + shipDisk(R, rough, S);
        float specOcc = saturate(ao * ao * (1.0 + NoV) + NoV * 0.2);
        col += env * shipEnvBRDF(F0, rough, NoV) * specOcc * refl;
    }

    // Window lights: points on every other deck of a finer lattice, averaged once they get tiny; a soft
    // pool of light around each on the hull.
    if (in.win > 0.0 && S.hull.w > 0.0) {
        float k = dens * 1.7;
        float3 wq = mp * k;
        float3 wc = floor(wq) + 0.5;
        float3 dv = wq - wc;
        dv -= mn * dot(dv, mn);
        float d = length(dv * float3(1.0, 1.0, 1.6));
        // Windows sit in walls, not on decks facing up or down.
        float wall = 1.0 - smoothstep(0.45, 0.8, abs(mn.z));
        float on = step(hash13(wc + 17.0 + seed), in.win * S.hull.w * 0.5) * step(fract(wc.z * 0.5), 0.5) * wall;
        float px = max(max(fwidth(wq.x), fwidth(wq.y)), fwidth(wq.z));
        float spot = 1.0 - smoothstep(0.08, 0.08 + px, d);
        float pool = exp(-d * d * 18.0) * 0.12;
        float lightv = mix(spot + pool, 0.045, smoothstep(0.3, 0.9, px));
        col += float3(1.0, 0.86, 0.62) * on * lightv * 2.4;
    }
    col = mix(col, float3(0.85, 0.92, 1.0) * 1.2, saturate(S.a.w));
    float fade = S.a.z;
    return float4(col * alpha * fade, alpha * fade);
}

// ---------------------------------------------------------------- sky for ship reflections

struct ShipEnvP {
    float4 pal[7];
    float4 k;            // nebula scale, seed, swirl, star amount
};

fragment float4 bakeShipEnv(VOut in [[stage_in]], constant ShipEnvP &E [[buffer(0)]]) {
    // Equirectangular in the camera frame: u = azimuth around the forward axis, v = angle from it.
    float3 acc = float3(0.0);
    float2 res = float2(256.0, 128.0);
    for (int s = 0; s < 4; s++) {
        float2 o = (float2(s & 1, s >> 1) - 0.5) * 0.5 / res;
        float az = (in.uv.x + o.x - 0.5) * 2.0 * M_PI_F;
        float ang = clamp(in.uv.y + o.y, 0.0, 1.0) * M_PI_F;
        float3 d = float3(sin(ang) * cos(az), sin(ang) * sin(az), cos(ang));
        // The nebula as on the screen: same noise as bakeNebula, swirled the same way, coloured the same way.
        float twist = E.k.z * exp(-ang * 4.0);
        float a2 = atan2(d.y, d.x) + twist;
        float3 dd = float3(sin(ang) * cos(a2), sin(ang) * sin(a2), cos(ang));
        float3 qn = dd * E.k.x + E.k.y * float3(13.1, 7.7, 3.3);
        float3 w = float3(fbm3(qn + 1.3, 3), fbm3(qn + 5.2, 3), fbm3(qn + 9.1, 3));
        float n = fbm3(qn * 1.3 + w * 2.2, 4);
        float lanes = fbm3(qn * 2.6 + w * 3.0 + 3.7, 3);
        float hue = fbm3(qn * 0.6 + w * 0.8 + 11.0, 3);
        float dens = smoothstep(0.40, 0.78, n) * mix(0.25, 1.0, smoothstep(0.35, 0.62, lanes));
        float focus = 0.2 + 1.3 * exp(-ang * 3.5);
        float nb = saturate(dens * dens * focus * 0.7);
        float3 cool = mix(E.pal[5].rgb, E.pal[6].rgb, smoothstep(0.25, 0.5, hue));
        float3 warm = grad5(0.25 + 0.55 * smoothstep(0.45, 0.75, hue), E.pal);
        float3 c = mix(cool, warm, smoothstep(0.35, 0.6, hue));
        acc += E.pal[0].rgb * 0.10 * (0.4 + n) + c * nb * 0.8;
    }
    float3 col = acc * 0.25;
    // Stars: a few bright points per texel row, white to warm.
    float2 cellp = floor(in.uv * res);
    float h = hash12(cellp + 3.1);
    float star = step(0.985, h) * pow((h - 0.985) / 0.015, 3.0) * 6.0 * E.k.w;
    col += star * mix(float3(1.0, 0.9, 0.75), float3(0.8, 0.88, 1.0), hash12(cellp + 9.7));
    return float4(col, 1.0);
}
"""#
