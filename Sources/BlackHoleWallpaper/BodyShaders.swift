// Metal source for bodies near the hole (stage 2), placed after the object shaders and
// before dispFrag in Shaders.swift.
//
//   bakePlanet    one planet surface into two equirectangular textures (albedo, clouds/glow/height)
//   bodyFrag      one body as a sprite into the body atlas, unlensed, lit, premultiplied linear
//   bodyMaskFrag  which path-L bodies can show in each 8 x 8 cell (bit per body)
//   bodyLayers    path L in dispFrag: thin-lens lookup into the atlas with the Kerr deflection
//                 from the ray map, sorted against the disk crossings and the shadow
//   frontVert/Frag  path F: sprites, star glow, diffraction spikes, comet tails, meteors.
//                 Programmable blending: reads the tone-mapped pixel, undoes the tone curve,
//                 composites in linear light and maps again.
//   partVert/Frag particles (belts, dust rings, debris along a band), forward point lens.

let bodyShaderSource = #"""
// ---------------------------------------------------------------- bodies: shared

struct BodyRef {
    float4 box;   // unlensed sprite rect (px): x0 y0 x1 y1
    float4 tile;  // atlas rect (uv)
    float4 geo;   // lens weight w, camera depth, centre px x, y
    float4 ext;   // disk radius px (particle occlusion), lens shift px, reach of the counter image px, radius in M (round bodies, else 0)
    float4 cand;  // where its main image can be (px): the box, widened outwards from the hole by the lens shift
};

// Unlensed camera-frame direction of a pixel, and back. Same impact parameters as traceRay:
// a ray leaving the camera at angle psi from the hole has b = r0 sin(psi).
static float3 dirOfPx(float2 px, constant FrameParams &P) {
    float2 c = float2(P.view.w, P.bars.w) * P.view.xy;
    float k = min(P.view.x, P.view.y) / P.camA.y;
    float2 s = float2((px.x - c.x) / k - P.camA.z, -(px.y - c.y) / k) / P.camA.x;
    return float3(s, sqrt(max(1.0 - dot(s, s), 0.0)));
}

static float2 pxOfDir(float3 d, constant FrameParams &P) {
    float2 c = float2(P.view.w, P.bars.w) * P.view.xy;
    float k = min(P.view.x, P.view.y) / P.camA.y;
    float2 s = d.xy / max(length(d), 1e-6) * P.camA.x;
    return c + float2(s.x + P.camA.z, -s.y) * k;
}

static float3 hueRGB(float h) {
    float3 k = fract(float3(h / 360.0) + float3(0.0, 2.0 / 3.0, 1.0 / 3.0));
    return saturate(abs(k * 6.0 - 3.0) - 1.0);
}

// Rotates a colour's hue by angle a (radians), keeping its luminance roughly.
static float3 hueShift(float3 c, float a) {
    if (a == 0.0) return c;
    const float3 k = float3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

static float2 worley3(float3 p) {
    float3 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int z = -1; z <= 1; z++)
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
        float3 g = float3(x, y, z);
        float3 r = g + hash33(i + g) - f;
        float d = dot(r, r);
        if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
    }
    return sqrt(float2(d1, d2));
}

// ---------------------------------------------------------------- planet surface bake

struct PlanetBake {
    float4 a;   // type, seed, ocean, craters
    float4 b;   // bands, storms, cracks, unused
};

struct PlanetOut {
    float4 a [[color(0)]];   // sqrt(albedo) rgb, specular mask
    float4 b [[color(1)]];   // cloud density, glow (lava, city lights, volcanoes), height, unused
};

// Craters at three scales: x height change, y albedo change (fresh rays and floors).
static float2 craterField(float3 p, float amount, float seed) {
    float h = 0.0, alb = 0.0;
    float sc = 2.5;
    for (int k = 0; k < 4; k++) {
        float3 q = p * sc + float3(seed * 0.37 + float(k) * 11.0);
        float3 i = floor(q), f = fract(q);
        for (int z = -1; z <= 1; z++)
        for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++) {
            float3 g = float3(x, y, z);
            float3 cell = i + g;
            float pr = hash13(cell + 3.1);
            if (pr > 0.25 + 0.55 * amount) continue;
            float3 o = hash33(cell);
            float rad = (0.18 + 0.32 * hash13(cell + 7.7));
            float d = length(g + o - f) / rad;
            if (d > 1.8) continue;
            float bowl = d < 1.0 ? (d * d - 1.0) * 0.9 : 0.0;
            float rim = 0.35 * exp(-(d - 1.0) * (d - 1.0) / 0.05);
            float w = 1.0 / sc;
            h += (bowl + rim) * w;
            // A few young craters with bright floors and rays.
            float young = step(0.85, hash13(cell + 1.3));
            float ang = atan2(f.y - g.y - o.y, f.x - g.x - o.x);
            float rays = smoothstep(0.6, 1.0, vnoise3(float3(ang * 5.0, cell.xy))) * exp(-max(d - 1.0, 0.0) * 1.3);
            alb += young * (d < 1.0 ? 0.25 : rays * 0.35) * w * 2.0;
        }
        sc *= 2.3;
    }
    return float2(h * amount, alb * amount);
}

// Zonal bands of a giant planet: base colour from latitude with turbulent edges.
static float3 giantBands(float3 P, float seed, float bands, float storms, float3 zone, float3 belt, float3 polar, thread float &glow) {
    float lat = asin(clamp(P.z, -1.0, 1.0));
    float lon = atan2(P.y, P.x);
    float3 q = float3(cos(lon) * 1.2, sin(lon) * 1.2, P.z * 9.0) + seed;
    float warp = fbm3(q * float3(1.0, 1.0, 1.0), 4) - 0.5;
    float fine = fbm3(float3(cos(lon) * 4.0, sin(lon) * 4.0, P.z * 40.0) + seed * 1.7, 3) - 0.5;
    float l = lat + warp * 0.10 * bands + fine * 0.02;
    float s = sin(l * (7.0 + 3.0 * hash13(float3(seed))) + seed);
    float s2 = sin(l * 23.0 + seed * 2.0);
    float bandMix = smoothstep(-0.2, 0.3, s) * bands + (1.0 - bands) * 0.5;
    float3 col = mix(belt, zone, bandMix);
    col *= 1.0 + 0.14 * s2 * bands + 0.45 * fine * bands;
    // Festoons and swirls along the band edges.
    float edge = 1.0 - abs(s);
    float sw = fbm3(float3(cos(lon) * 6.0, sin(lon) * 6.0, l * 30.0) + seed * 3.0, 3);
    col = mix(col, zone * 1.05, edge * smoothstep(0.55, 0.75, sw) * 0.5 * bands);
    col = mix(col, polar, smoothstep(0.85, 1.25, abs(lat)));
    glow = bandMix;
    // Storms: one great oval and a few small white ones.
    if (storms > 0.0) {
        float lon0 = seed * 1.3;
        float2 d = float2(atan2(sin(lon - lon0), cos(lon - lon0)) / 0.30, (lat + 0.38) / 0.11);
        float r = length(d);
        float oval = 1.0 - smoothstep(0.6, 1.05, r);
        float spiral = fbm3(float3(d * 2.0 + float2(atan2(d.y, d.x) * 0.6, 0.0), seed), 3);
        col = mix(col, float3(0.78, 0.40, 0.24) * (0.8 + 0.4 * spiral), oval * storms);
        col = mix(col, zone * 1.1, exp(-(r - 1.05) * (r - 1.05) / 0.02) * storms * 0.6);
        for (int k = 0; k < 4; k++) {
            float lk = 0.55 - 0.32 * float(k) + 0.05 * hash13(float3(seed, float(k), 1.0));
            float ok = lon0 + 1.7 * float(k + 1) + hash13(float3(seed, float(k), 2.0));
            float2 e = float2(atan2(sin(lon - ok), cos(lon - ok)) / 0.07, (lat - lk) / 0.04);
            col = mix(col, float3(0.96, 0.94, 0.9), (1.0 - smoothstep(0.5, 1.0, length(e))) * storms);
        }
    }
    return col;
}

fragment PlanetOut bakePlanet(VOut in [[stage_in]], constant PlanetBake &G [[buffer(0)]]) {
    float lon = (in.uv.x - 0.5) * 2.0 * M_PI_F;
    float lat = (0.5 - in.uv.y) * M_PI_F;
    float3 P = float3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat));
    int type = int(G.a.x + 0.5);
    float seed = G.a.y;
    float ocean = G.a.z, craters = G.a.w;
    float bands = G.b.x, storms = G.b.y, cracks = G.b.z;
    float3 q = P + float3(seed * 0.173, seed * 0.311, seed * 0.097);
    float3 alb = float3(0.5);
    float spec = 0.0, cloud = 0.0, glow = 0.0, h = 0.5;
    float2 cr = craters > 0.0 ? craterField(P, craters, seed) : float2(0.0);

    // Cloud density (used where the shading turns clouds on): warped fbm with zonal winds.
    // Clouds: two levels of domain warping give swirls; a cosine in latitude gives the
    // cloudy equator and storm belts with clear subtropics in between. 0..1, about uniform.
    float3 cw = float3(fbm3(q * 1.7 + 1.0, 4), fbm3(q * 1.7 + 5.0, 4), fbm3(q * 1.7 + 9.0, 4)) - 0.5;
    float3 cw2 = float3(fbm3(q * 5.0 + cw * 2.0 + 3.0, 3), fbm3(q * 5.0 + cw * 2.0 + 7.0, 3), fbm3(q * 5.0 + 2.0, 3)) - 0.5;
    float c1 = fbm3(q * 4.2 + cw * 2.2 + cw2 * 0.7, 6);
    float c2 = fbm3(q * float3(11.0, 11.0, 22.0) + cw * 4.0 + cw2 * 2.0, 4);
    float cd = c1 * 0.8 + c2 * 0.35 - 0.08;
    cd = saturate((cd - 0.22) / 0.5);
    cd *= 0.7 + 0.3 * cos(lat * 6.0);
    cloud = cd;

    if (type == 0 || type == 10) {   // rocky, grey moon
        float n = fbm3(q * 4.0, 5);
        float maria = smoothstep(0.45, 0.62, fbm3(q * 1.3 + 2.0, 4));
        float3 base = type == 0 ? float3(0.42, 0.38, 0.34) : float3(0.47, 0.46, 0.44);
        float3 dark = type == 0 ? float3(0.24, 0.22, 0.20) : float3(0.17, 0.17, 0.18);
        alb = mix(base, dark, maria * (type == 0 ? 0.5 : 0.85)) * (0.8 + 0.4 * n);
        alb += cr.y;
        h = 0.5 + cr.x * 0.5 + (n - 0.5) * 0.15 - maria * 0.05;
    } else if (type == 1) {          // desert
        float n = fbm3(q * 2.5, 6);
        float dark = smoothstep(0.48, 0.62, fbm3(q * 1.8 + 3.0, 5));
        alb = mix(float3(0.62, 0.32, 0.17), float3(0.30, 0.18, 0.12), dark) * (0.85 + 0.3 * n);
        // A long canyon system.
        float3 ax = normalize(float3(hash13(float3(seed)) - 0.5, 0.4, 0.2));
        float gc = abs(dot(P, ax)) + 0.04 * (fbm3(q * 6.0, 3) - 0.5);
        float canyon = (1.0 - smoothstep(0.0, 0.012, gc)) * smoothstep(-0.2, 0.3, P.x * ax.y - P.y * ax.x);
        alb *= 1.0 - 0.45 * canyon;
        float cap = smoothstep(0.86, 0.92, abs(P.z) + 0.05 * (fbm3(q * 5.0, 3) - 0.5));
        alb = mix(alb, float3(0.92, 0.9, 0.88), cap);
        spec = cap * 0.4;
        alb += cr.y * 0.5;
        h = 0.5 + cr.x * 0.5 + (n - 0.5) * 0.2 - canyon * 0.3;
        cloud = smoothstep(0.55, 0.8, fbm3(q * float3(5.0, 5.0, 2.0) + cw * 3.0, 4));
    } else if (type == 2 || type == 3) {   // earth-like, ocean world
        float c = fbm3(q * 1.5, 6) + 0.18 * (fbm3(q * 6.0, 4) - 0.5);
        float sea = 0.5 + (ocean - 0.5) * 0.36;
        float land = smoothstep(sea - 0.004, sea + 0.004, c);
        float elev = saturate((c - sea) * 5.0);
        float alat = abs(P.z);
        float t = fbm3(q * 3.0 + 7.0, 4);
        float3 green = mix(float3(0.10, 0.20, 0.07), float3(0.06, 0.14, 0.06), t);
        float3 desert = float3(0.62, 0.48, 0.30);
        float dry = smoothstep(0.12, 0.22, alat) * (1.0 - smoothstep(0.38, 0.5, alat)) * smoothstep(0.45, 0.6, t);
        float3 l = mix(green, desert, dry);
        l = mix(l, float3(0.30, 0.26, 0.22), smoothstep(0.35, 0.8, elev));
        l = mix(l, float3(0.30, 0.32, 0.22), smoothstep(0.6, 0.75, alat));
        float3 deep = float3(0.012, 0.045, 0.12), shallow = float3(0.04, 0.16, 0.24);
        float3 w = mix(deep, shallow, smoothstep(sea - 0.06, sea, c));
        alb = mix(w, l, land);
        float ice = smoothstep(0.80, 0.86, alat + 0.05 * (t - 0.5));
        alb = mix(alb, float3(0.88, 0.9, 0.93), ice);
        spec = (1.0 - land) * (1.0 - ice);
        h = 0.5 + 0.3 * elev * land;
        float cities = smoothstep(0.55, 0.95, vnoise3(q * 70.0)) * smoothstep(0.45, 0.7, fbm3(q * 9.0 + 3.0, 3));
        glow = cities * land * (1.0 - ice) * (1.0 - dry) * (1.0 - smoothstep(0.3, 0.6, elev));

    } else if (type == 4 || type == 12) {   // ice, Europa
        float n = fbm3(q * 3.0, 5);
        alb = mix(float3(0.80, 0.76, 0.68), float3(0.92, 0.90, 0.86), n);
        float lines = 0.0;
        for (int k = 0; k < 3; k++) {
            float3 qq = q * (2.0 + 2.7 * float(k)) + float3(float(k) * 5.0);
            float r = abs(fbm3(qq, 4) - 0.5);
            lines = max(lines, (1.0 - smoothstep(0.004, 0.018 / (1.0 + float(k)), r)) * (1.0 - 0.25 * float(k)));
        }
        float chaos = smoothstep(0.6, 0.75, fbm3(q * 2.0 + 4.0, 4));
        float3 brown = float3(0.55, 0.36, 0.22);
        alb = mix(alb, brown, saturate(lines * cracks + chaos * 0.5 * cracks));
        alb += cr.y * 0.3;
        spec = 0.6 * (1.0 - lines * cracks);
        h = 0.5 + lines * cracks * 0.15 + cr.x * 0.3;
    } else if (type == 5) {   // lava
        float n = fbm3(q * 3.0, 5);
        alb = mix(float3(0.035, 0.03, 0.028), float3(0.11, 0.09, 0.08), n);
        float r = abs(fbm3(q * 2.5 + 3.0, 5) - 0.5);
        float r2 = abs(fbm3(q * 6.0 + 9.0, 4) - 0.5);
        float crack = (1.0 - smoothstep(0.0, 0.016 * (0.5 + cracks), r)) * (0.5 + 0.8 * vnoise3(q * 9.0));
        float crack2 = (1.0 - smoothstep(0.0, 0.01 * (0.5 + cracks), r2)) * 0.45;
        float lakes = smoothstep(0.68, 0.75, fbm3(q * 1.6 + 8.0, 4));
        float warm = (1.0 - smoothstep(0.0, 0.08, r)) * 0.12;
        glow = saturate(crack + crack2 * vnoise3(q * 14.0 + 2.0) + lakes * (0.7 + 0.3 * n) + warm);
        alb = mix(alb, float3(0.20, 0.07, 0.03), saturate(glow * 1.5));
        h = 0.5 + (n - 0.5) * 0.3 - glow * 0.1 + cr.x * 0.3;
    } else if (type == 6 || type == 9) {   // gas giant, hot Jupiter
        float g;
        float3 zone = type == 6 ? float3(0.93, 0.86, 0.74) : float3(0.30, 0.17, 0.12);
        float3 belt = type == 6 ? float3(0.64, 0.44, 0.30) : float3(0.14, 0.07, 0.05);
        float3 polar = type == 6 ? float3(0.55, 0.52, 0.50) : float3(0.12, 0.08, 0.07);
        alb = giantBands(P, seed, bands, storms, zone, belt, polar, g);
        glow = type == 9 ? (1.0 - g) * 0.7 + 0.3 : 0.0;
        cloud = 0.0;
    } else if (type == 7) {   // ringed: soft butterscotch bands
        float g;
        alb = giantBands(P, seed, bands * 0.7, storms * 0.5, float3(0.90, 0.80, 0.60), float3(0.74, 0.60, 0.42), float3(0.62, 0.62, 0.62), g);
        cloud = 0.0;
    } else if (type == 8) {   // ice giant
        float g;
        alb = giantBands(P, seed, bands * 0.5, 0.0, float3(0.16, 0.34, 0.86), float3(0.10, 0.22, 0.70), float3(0.14, 0.30, 0.80), g);
        float lon0 = seed * 2.1;
        float2 d = float2(atan2(sin(lon - lon0), cos(lon - lon0)) / 0.22, (lat + 0.35) / 0.09);
        float spot = 1.0 - smoothstep(0.6, 1.0, length(d));
        alb = mix(alb, float3(0.09, 0.15, 0.40), spot * storms);
        float streak = smoothstep(0.7, 0.85, fbm3(float3(cos(lon) * 3.0, sin(lon) * 3.0, P.z * 25.0) + seed, 4));
        alb = mix(alb, float3(0.95, 0.97, 1.0), streak * storms * 0.8);
        alb = mix(alb, float3(0.95), (1.0 - smoothstep(0.4, 0.9, length(d - float2(0.0, 1.6)))) * storms * 0.7);
        cloud = 0.0;
    } else if (type == 11) {   // Io
        float n = fbm3(q * 3.0, 5);
        float3 sulfur = float3(0.88, 0.80, 0.38), orange = float3(0.80, 0.48, 0.20), white = float3(0.92, 0.90, 0.80);
        alb = mix(sulfur, orange, smoothstep(0.42, 0.6, fbm3(q * 2.5 + 2.0, 5)));
        alb = mix(alb, white, smoothstep(0.55, 0.7, fbm3(q * 3.0 + 6.0, 4)) * 0.8);
        alb = mix(alb, float3(0.45, 0.30, 0.16), smoothstep(0.62, 0.72, fbm3(q * 4.0 + 9.0, 4)) * 0.8);
        float2 w = worley3(q * 6.0);
        float vent = 1.0 - smoothstep(0.04, 0.1, w.x);
        float ring = exp(-(w.x - 0.24) * (w.x - 0.24) / 0.006) * step(0.45, hash13(floor(q * 6.0)));
        alb = mix(alb, float3(0.12, 0.08, 0.06), vent);
        alb = mix(alb, float3(0.70, 0.25, 0.15), ring * 0.7);
        glow = vent * smoothstep(0.5, 0.9, hash13(floor(q * 5.0) + 2.0));
        alb *= 0.85 + 0.3 * n;
        h = 0.5 + (n - 0.5) * 0.2;
    } else if (type == 13) {   // Titan
        float n = fbm3(q * 2.0, 4);
        alb = mix(float3(0.62, 0.40, 0.16), float3(0.75, 0.52, 0.22), n);
        cloud = 0.0;
    }
    alb = saturate(alb);
    return PlanetOut{ float4(sqrt(alb), spec), float4(saturate(cloud), saturate(glow), saturate(h), 1.0) };
}

// ---------------------------------------------------------------- body sprites

struct BodyP {
    float4 a;      // kind (0 planet, 1 star, 2 rock, 3 coma, 4 binary), type, half extent (radii), seed
    float4 bx, by, bz;   // body axes in the sprite frame (x right, y up, z to the camera); w: spin, cloud angle, time
    float4 l0, c0; // light 0: direction (sprite frame), source angular radius; colour * irradiance
    float4 l1, c1; // light 1
    float4 amb;    // ambient rgb, hue shift (rad)
    float4 atm;    // atmosphere colour * strength, thickness (radii)
    float4 ring;   // inner, outer (radii), density, Cassini gap
    float4 ringC;  // ring colour, on
    float4 q0;     // planet: specular, night lights, glow, clouds. star: granulation, spots, prominences, corona
    float4 q1;     // planet: cloud colour-free (unused). rock: elongation, craters, rock type, glow. binary: separation, radius B, stream, orbit angle
    float4 e;      // star: colour * brightness, temperature. coma: colour, strength
    float4 e2;     // binary: companion colour, unused. coma: dust colour, nucleus
    float4 tide;   // tidal stretch: direction in the sprite (xy), factor along it, unused
};

// Normal optical depth of a ring at radius r (planet radii): C, B and A ring with Cassini and Encke gaps.
static float ringTau(float r, constant BodyP &B) {
    float x = (r - B.ring.x) / max(B.ring.y - B.ring.x, 1e-3);
    if (x < 0.0 || x > 1.0) return 0.0;
    float gap = B.ring.w;
    float tauC = 0.12, tauB = 1.3, tauA = 0.55;
    float t = mix(tauC, tauB, smoothstep(0.22, 0.27, x));
    t = mix(t, tauA, smoothstep(0.60, 0.62, x));
    float cas = 1.0 - exp(-(x - 0.615) * (x - 0.615) / (0.0004 + 0.0012 * gap));
    t *= mix(1.0, cas, gap);
    t *= 1.0 - 0.9 * exp(-(x - 0.93) * (x - 0.93) / 0.00006) * gap;
    float n = vnoise3(float3(x * 160.0, 0.5, B.a.w)) * 0.5 + vnoise3(float3(x * 520.0, 1.5, B.a.w)) * 0.5;
    t *= 0.55 + 0.9 * n;
    t *= smoothstep(0.0, 0.02, x) * (1.0 - smoothstep(0.985, 1.0, x));
    return t * B.ring.z * 1.4;
}

// Ring brightness: grey faint C ring, bright B ring, a little darker A ring, fine ringlets.
static float3 ringColour(float r, constant BodyP &B) {
    float x = saturate((r - B.ring.x) / max(B.ring.y - B.ring.x, 1e-3));
    float3 c = B.ringC.rgb;
    float alb = mix(0.35, 1.0, smoothstep(0.2, 0.3, x));
    alb = mix(alb, 0.72, smoothstep(0.6, 0.64, x));
    c *= alb * mix(float3(0.8, 0.8, 0.84), float3(1.04, 0.98, 0.92), smoothstep(0.15, 0.35, x));
    c *= 0.6 + 0.4 * vnoise3(float3(x * 70.0, 3.5, B.a.w)) + 0.24 * (vnoise3(float3(x * 300.0, 1.5, B.a.w)) - 0.5);
    return c;
}

// Light reaching a point from one source, with soft wrap for extended sources (the disk).
static float wrapDiffuse(float ndl, float wrap) {
    return saturate((ndl + wrap) / (1.0 + wrap));
}

// Is point X (sprite frame, planet radii) in the planet's shadow towards l? Soft edge.
static float planetShadow(float3 X, float3 l, float soft) {
    float b = dot(X, l);
    if (b > 0.0) return 1.0;
    float d2 = dot(X, X) - b * b;
    return smoothstep(1.0 - soft, 1.0 + soft, sqrt(max(d2, 0.0)));
}

static float3 planetShade(float2 p, float fw, constant BodyP &B, texture2d<float> tA, texture2d<float> tB, thread float &alpha) {
    constexpr sampler ss(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);
    alpha = 0.0;
    float r2 = dot(p, p);
    float r = sqrt(r2);
    int type = int(B.a.y + 0.5);
    bool giant = type >= 6 && type <= 9;
    float3 col = float3(0.0);
    float zs = sqrt(max(1.0 - r2, 0.0));
    float cov = smoothstep(1.0 + fw, 1.0 - fw, r);
    float3 L0 = B.l0.xyz, L1 = B.l1.xyz;
    float3 bz = B.bz.xyz;
    if (cov > 0.0) {
        float3 N = float3(p, zs);
        if (r > 1.0) N = float3(p / r, 0.0);
        float3 nb = float3(dot(N, B.bx.xyz), dot(N, B.by.xyz), dot(N, bz));
        float lon = atan2(nb.y, nb.x) + B.bx.w;
        float lat = asin(clamp(nb.z, -1.0, 1.0));
        float2 uv = float2(lon * inv2pi, 0.5 - lat / M_PI_F);
        // Mip level from the pixel's footprint on the surface (foreshortened towards the limb).
        float lod = log2(max(float(tA.get_width()) * inv2pi * fw / max(zs, 0.15), 1.0));
        float4 A = tA.sample(ss, uv, level(lod));
        float4 Bs = tB.sample(ss, uv, level(lod));
        float3 alb = hueShift(A.rgb * A.rgb, B.amb.w);
        // Relief from the baked height: tilt the normal along the height gradient.
        float3 east = normalize(cross(bz, N) + float3(1e-5, 0.0, 0.0));
        float3 north = cross(N, east);
        float eps = 1.0 / 1024.0;
        float hE = tB.sample(ss, uv + float2(eps, 0.0), level(lod)).b;
        float hN = tB.sample(ss, uv - float2(0.0, eps), level(lod)).b;
        float relief = giant ? 0.0 : 0.6;
        float3 Nb = normalize(N - relief * ((hE - Bs.b) * east * cos(lat) + (hN - Bs.b) * north) * 40.0);
        // Clouds drift against the surface.
        float4 Cs = tB.sample(ss, uv + float2(B.by.w * inv2pi, 0.0), level(lod));
        float cl = B.q0.w > 0.0 ? smoothstep(0.92 - B.q0.w, 1.25 - B.q0.w, Cs.r) * (0.5 + 0.5 * Cs.r) : 0.0;
        float3 light = float3(0.0), lightC = float3(0.0);
        float ndl0 = dot(N, L0);
        for (int k = 0; k < 2; k++) {
            float3 L = k == 0 ? L0 : L1;
            float3 C = k == 0 ? B.c0.rgb : B.c1.rgb;
            float wrap = k == 0 ? B.l0.w : B.l1.w;
            if (dot(C, C) <= 0.0) continue;
            float sh = 1.0;
            // Ring shadow on the planet.
            if (B.ringC.w > 0.5) {
                float dz = dot(L, bz);
                float t = -dot(N, bz) / (abs(dz) > 1e-4 ? dz : 1e-4);
                if (t > 0.0) {
                    float rr = length(N + L * t);
                    sh = exp(-ringTau(rr, B) / max(abs(dz), 0.05));
                }
            }
            float atmW = B.atm.w * 0.3;
            light += C * wrapDiffuse(dot(Nb, L), wrap + atmW * 0.5) * sh;
            lightC += C * wrapDiffuse(dot(N, L), wrap + atmW + 0.04) * sh;
            // Glint on water and ice.
            float3 h = normalize(L + float3(0.0, 0.0, 1.0));
            float fres = 0.04 + 0.96 * pow(1.0 - saturate(zs), 5.0);
            col += C * pow(saturate(dot(N, h)), 260.0) * A.a * B.q0.x * (2.0 + 2.0 * fres) * sh * smoothstep(0.0, 0.25, dot(N, L));
        }
        float3 surf = alb * (light + B.amb.rgb);
        // Twilight: light scattered around the terminator turns warm.
        float tw = exp(-ndl0 * ndl0 / 0.02) * B.atm.w;
        surf += alb * B.c0.rgb * tw * float3(0.25, 0.1, 0.03) * 0.5;
        float3 cloudC = float3(0.95, 0.95, 0.97) * (lightC + B.amb.rgb);
        col += mix(surf, cloudC, cl);
        // City lights, lava, volcanoes, the glowing night side of a hot Jupiter.
        float night = 1.0 - smoothstep(-0.12, 0.12, ndl0);
        col += Bs.g * B.q0.y * float3(1.0, 0.72, 0.38) * 0.35 * night * (1.0 - cl);
        if (type == 9) {
            // Tidally locked: the side facing the light glows, hottest at its centre; the night side a dull red.
            float day = pow(saturate(ndl0), 1.6);
            col += (float3(0.55, 0.08, 0.02) * 0.08 + float3(1.0, 0.42, 0.10) * 0.55 * day) * B.q0.z * (0.4 + 0.9 * Bs.g);
        } else {
            col += Bs.g * Bs.g * B.q0.z * float3(1.0, 0.30, 0.06) * 2.2 * (1.0 - cl * 0.7);
        }
        // Limb darkening on giants, atmosphere haze along the limb.
        if (giant) col *= mix(0.55, 1.0, pow(zs, 0.45));
        float rim = pow(1.0 - zs, 2.5);
        float litRim = smoothstep(-0.25, 0.4, ndl0) + 0.15 * wrapDiffuse(dot(N, L1), 0.3);
        // Backlit: light scattered forward through the atmosphere lights the whole limb.
        float fwdS = pow(saturate(-L0.z), 1.5) * (0.6 + 0.4 * saturate(dot(normalize(p + 1e-5), normalize(L0.xy + 1e-5))));
        col += B.atm.rgb * rim * (litRim * 0.3 + fwdS * 0.9) * length(B.c0.rgb + B.c1.rgb);
        col *= cov;
        alpha = cov;
    }
    // Haze beyond the limb, lit side only.
    if (B.atm.w > 0.0 && r > 1.0 - fw) {
        float h = (r - 1.0) / max(B.atm.w * 0.08, 1e-3);
        float2 rim = p / max(r, 1e-4);
        float lit = smoothstep(-0.35, 0.35, dot(rim, L0.xy) + 0.3 * L0.z) * length(B.c0.rgb) + smoothstep(-0.35, 0.35, dot(rim, L1.xy)) * length(B.c1.rgb);
        // Forward scattering when the light is behind the planet: a glowing ring around the whole limb.
        float fwd = pow(saturate(-L0.z), 1.5) * (0.55 + 0.45 * saturate(dot(rim, normalize(L0.xy + 1e-5)))) * length(B.c0.rgb) * 1.4;
        col += B.atm.rgb * exp(-max(h, 0.0) * 1.6) * (lit * 0.3 + fwd) * (1.0 - cov);
    }
    // Rings: in front of the planet where the ring plane is nearer than the surface.
    if (B.ringC.w > 0.5) {
        float bzz = abs(bz.z) < 0.01 ? (bz.z < 0.0 ? -0.01 : 0.01) : bz.z;
        float zr = -(p.x * bz.x + p.y * bz.y) / bzz;
        float3 X = float3(p, zr);
        float rr = length(X);
        float tau = ringTau(rr, B);
        if (tau > 0.0) {
            float op = 1.0 - exp(-tau / max(abs(bzz), 0.02));
            // Edge-on: the ring becomes a thin line, keep it a pixel wide.
            float3 rc = ringColour(rr, B);
            float3 I = float3(0.0);
            for (int k = 0; k < 2; k++) {
                float3 L = k == 0 ? L0 : L1;
                float3 C = k == 0 ? B.c0.rgb : B.c1.rgb;
                if (dot(C, C) <= 0.0) continue;
                float ld = dot(L, bz);
                float sh = planetShadow(X, L, 0.03);
                bool sameSide = ld * bzz > 0.0;
                // Lit face: single scattering, dense parts brighter. Unlit face: light leaking through.
                float mu0 = max(abs(ld), 0.03), mu = max(abs(bzz), 0.03);
                float lit = sameSide ? mu0 / (mu0 + mu) * (1.0 - exp(-tau * (1.0 / mu0 + 1.0 / mu))) / max(op, 1e-3) * 1.4
                                     : (1.0 - exp(-tau / mu0)) * exp(-tau / mu) / max(op, 1e-3) * 0.5 + 0.03;
                float fwd = pow(saturate(-L.z), 4.0) * 0.3;   // dust glows when the light is behind the ring
                I += C * (lit + fwd) * sh;
            }
            float3 rcol = rc * (I + B.amb.rgb) * op;
            bool front = r >= 1.0 || zr > zs;
            float4 R = float4(rcol, op);
            float4 Pl = float4(col, alpha);
            float4 o = front ? R + (1.0 - R.a) * Pl : Pl + (1.0 - Pl.a) * R;
            col = o.rgb; alpha = o.a;
        }
    }
    return col;
}

// Convection on a star's surface at body-frame point nb: bright granules with dark lanes, slowly
// boiling. scale: cells per radius (dwarfs fine, supergiants a few giant cells).
static float starGranules(float3 nb, float scale, float t, float amount, float mu) {
    // Big cells (giants) get wide soft lanes and read as blotches; small cells as fine mottling.
    float soft = mix(0.16, 1.0, saturate((14.0 - scale) / 8.0));
    // Warped, so the cells differ in size and shape instead of forming a honeycomb.
    float3 q = nb * scale;
    q += float3(vnoise3(q * 0.35), vnoise3(q * 0.35 + 7.0), vnoise3(q * 0.35 + 13.0)) * 1.4 - 0.7;
    float2 w = worley3(q + float3(0.0, 0.0, t * 0.03));
    float lane = 1.0 - smoothstep(0.0, soft, w.y - w.x);
    float2 w2 = worley3(nb * scale * 2.3 + float3(5.0, 1.0, t * 0.05));
    float lane2 = 1.0 - smoothstep(0.0, soft, w2.y - w2.x);
    // Supergranulation: larger brighter and darker patches over the cells.
    float sup = fbm3(nb * scale * 0.3 + float3(t * 0.004, 0.0, 3.0), 3);
    float big = saturate((12.0 - scale) / 6.0);
    float g = (0.16 - 0.08 * big) * lane + 0.07 * lane2 + (0.24 + 0.12 * big) * smoothstep(0.1, 0.9, w.x) + 0.3 * (0.55 - sup);
    return 1.0 - amount * g * (0.4 + 0.6 * mu);
}

// Self-luminous surface: limb darkening (quadratic law) with the cooler, redder light of the higher
// layers towards the limb. e: centre colour, e2: limb colour (both linear, set so the centre does
// not burn out to white). No outside light, no night side.
static float3 starSurface(float3 N, float2 p, constant BodyP &B, thread float &alpha, float fw) {
    float r = length(p);
    float3 col = float3(0.0);
    int type = int(B.a.y + 0.5);
    // Wolf-Rayet: the dense wind blurs the edge of the star.
    float soft = type == 2 ? 0.06 : 0.0;
    float cov = smoothstep(1.0 + fw + soft, 1.0 - fw - soft, r);
    alpha = cov;
    float t = B.bz.w;
    if (cov > 0.0) {
        float mu = sqrt(saturate(1.0 - r * r));
        float m1 = 1.0 - mu;
        float limb = 1.0 - 0.66 * m1 - 0.22 * m1 * m1;
        float3 base = mix(B.e2.rgb, B.e.rgb, pow(mu, 0.45));
        float3 nb = float3(dot(N, B.bx.xyz), dot(N, B.by.xyz), dot(N, B.bz.xyz));
        float ca = cos(B.bx.w), sa = sin(B.bx.w);
        nb.xy = float2(ca * nb.x - sa * nb.y, sa * nb.x + ca * nb.y);
        float surf;
        if (type == 1) {
            // Brown dwarf: no granules, cloud bands like a small Jupiter glowing from inside.
            float warp = fbm3(nb * 2.6 + float3(B.a.w, t * 0.004, 0.0), 3);
            float band = sin(nb.z * 15.0 + warp * 3.2 + B.a.w);
            float band2 = sin(nb.z * 37.0 + warp * 6.0);
            float storm = smoothstep(0.66, 0.74, fbm3(nb * 4.0 + B.a.w * 1.7, 3)) * smoothstep(0.7, 0.2, abs(nb.z));
            surf = 0.78 + 0.20 * band + 0.06 * band2 + 0.25 * storm;
        } else {
            surf = starGranules(nb, B.q1.x, t, B.q0.x, mu);
            // Spots on cool stars: dark umbra in a lighter penumbra; faculae brighten them near the limb.
            float spotN = fbm3(nb * 3.0 + B.a.w, 4);
            float active = smoothstep(0.6, 0.15, abs(nb.z));
            float pen = smoothstep(0.64, 0.69, spotN) * active * B.q0.y;
            float umbra = smoothstep(0.70, 0.74, spotN) * active * B.q0.y;
            float facula = smoothstep(0.56, 0.64, spotN) * (1.0 - smoothstep(0.64, 0.7, spotN)) * active * m1 * B.q0.y;
            surf *= (1.0 - 0.45 * pen - 0.45 * umbra) * (1.0 + 0.7 * facula);
        }
        col = base * limb * surf * cov;
    }
    float rr = max(r, 1.0);
    if (r > 1.0 - fw - soft) {
        float ang = atan2(p.y, p.x);
        float h = rr - 1.0;
        // Inner corona: a thin bright rim with faint streamers. The wide glow is drawn in path F.
        float st = 0.5 + vnoise3(float3(cos(ang) * 3.0, sin(ang) * 3.0, B.a.w)) + 0.5 * vnoise3(float3(cos(ang) * 9.0, sin(ang) * 9.0, B.a.w + 3.0));
        float ext = B.a.z;
        float cor = B.q0.w * (0.06 * exp(-h * 30.0) + 0.10 * exp(-h * 7.0) * st);
        cor *= 1.0 - smoothstep(ext * 0.8, ext * 0.98, rr);
        col += B.e2.rgb * cor * 0.9;
        // Prominences: glowing loops and arches standing on the limb.
        float pr = 0.0;
        for (int k = 0; k < 6; k++) {
            float hk = hash13(float3(B.a.w, float(k), 1.0));
            if (hk > 0.25 + 0.6 * B.q0.z) continue;
            float ak = hash13(float3(B.a.w, float(k), 2.0)) * 6.2831853 + t * 0.002;
            float wk = 0.08 + 0.16 * hash13(float3(B.a.w, float(k), 3.0));
            float da = atan2(sin(ang - ak), cos(ang - ak)) / wk;
            if (abs(da) > 1.2) continue;
            float height = (0.05 + 0.13 * hash13(float3(B.a.w, float(k), 4.0))) * sqrt(saturate(1.0 - da * da));
            float n = vnoise3(float3(da * 6.0, h * 40.0, B.a.w + float(k) + t * 0.05));
            float d = abs(h - height * (0.85 + 0.3 * n));
            float th = 0.0009 * (0.5 + n);
            pr += exp(-d * d / th) * (0.5 + n) * 0.8 + 0.8 * smoothstep(height, height * 0.6, h) * (1.0 - 0.6 * h / max(height, 1e-3)) * n * n;
        }
        // Hot glowing gas: orange-red on cool stars, pink-white on hot ones.
        float3 prc = mix(float3(1.0, 0.14, 0.04), float3(1.0, 0.30, 0.45), saturate(B.e.w / 15000.0));
        col += prc * pr * B.q0.z * max(max(B.e.r, B.e.g), B.e.b) * 0.2 * (1.0 - cov);
    }
    return col;
}

// Distance field of a lumpy rock (body frame, radius about 1).
static float rockSDF(float3 x, constant BodyP &B) {
    float el = max(B.q1.x, 1.0);
    float3 rad = float3(1.0, 1.0 / sqrt(el), 0.85 / el);
    float k0 = length(x / rad), k1 = length(x / (rad * rad));
    float d = k0 * (k0 - 1.0) / max(k1, 1e-4);
    float3 n = normalize(x + 1e-5);
    float lump = fbm3(n * 1.6 + B.a.w, 3) - 0.5;
    float c = 0.0;
    if (B.q1.y > 0.0) {
        float2 w = worley3(n * 3.2 + B.a.w * 0.7);
        c = (smoothstep(0.0, 0.45, w.x) - 1.0) * 0.08 + exp(-(w.x - 0.45) * (w.x - 0.45) / 0.004) * 0.02;
        float2 w2 = worley3(n * 8.0 + B.a.w);
        c += (smoothstep(0.0, 0.4, w2.x) - 1.0) * 0.025;
    }
    return (d - lump * 0.32 - c * B.q1.y) * 0.75;
}

static float3 rockShade(float2 p, float fw, constant BodyP &B, thread float &alpha) {
    alpha = 0.0;
    float3 bx = B.bx.xyz, by = B.by.xyz, bz = B.bz.xyz;
    float3 o = float3(p, 1.6), dir = float3(0.0, 0.0, -1.0);
    float3 ob = float3(dot(o, bx), dot(o, by), dot(o, bz));
    float3 db = float3(dot(dir, bx), dot(dir, by), dot(dir, bz));
    float t = 0.0, dmin = 1e9;
    bool hit = false;
    for (int i = 0; i < 40; i++) {
        float d = rockSDF(ob + db * t, B);
        dmin = min(dmin, d);
        if (d < 0.0015) { hit = true; break; }
        t += max(d, 0.004);
        if (t > 3.2) break;
    }
    float cov = hit ? 1.0 : smoothstep(fw * 1.2, 0.0, dmin);
    if (cov <= 0.0) return float3(0.0);
    float3 x = ob + db * t;
    const float2 e = float2(0.004, -0.004);
    float3 nb = normalize(e.xyy * rockSDF(x + e.xyy, B) + e.yyx * rockSDF(x + e.yyx, B)
                        + e.yxy * rockSDF(x + e.yxy, B) + e.xxx * rockSDF(x + e.xxx, B));
    float3 N = normalize(nb.x * bx + nb.y * by + nb.z * bz);
    int rt = int(B.q1.z + 0.5);
    float3 alb = rt == 0 ? float3(0.12, 0.115, 0.11) : rt == 1 ? float3(0.30, 0.26, 0.21) : rt == 2 ? float3(0.34, 0.33, 0.32) : float3(0.62, 0.66, 0.70);
    float3 xn = normalize(x);
    alb *= 0.75 + 0.5 * fbm3(xn * 6.0 + B.a.w, 4);
    if (B.a.y > 13.5) alb = hueShift(float3(0.38, 0.33, 0.29) * (0.75 + 0.5 * fbm3(xn * 6.0 + B.a.w, 4)), B.amb.w);   // moon (Phobos)
    float3 col = alb * B.amb.rgb;
    for (int k = 0; k < 2; k++) {
        float3 L = k == 0 ? B.l0.xyz : B.l1.xyz;
        float3 C = k == 0 ? B.c0.rgb : B.c1.rgb;
        float ndl = dot(N, L);
        col += alb * C * wrapDiffuse(ndl, 0.03);
        if (rt == 2) col += C * pow(saturate(dot(N, normalize(L + float3(0.0, 0.0, 1.0)))), 40.0) * 0.5 * step(0.0, ndl);
        if (rt == 3) col += C * pow(saturate(dot(N, normalize(L + float3(0.0, 0.0, 1.0)))), 24.0) * 0.25 * step(0.0, ndl);
    }
    alpha = cov;
    return col * cov;
}

static float3 comaShade(float2 p, constant BodyP &B, thread float &alpha) {
    alpha = 0.0;
    float2 l2 = B.l0.xy;
    float2 q = p - l2 * 0.18;
    float r = length(q);
    // Column density of a 1/r^2 coma, cut off smoothly; brighter towards the light.
    float coma = 1.0 / (1.0 + r / 0.035) * exp(-r * r / 0.7) * (1.0 + 0.5 * dot(normalize(q + 1e-5), l2) * smoothstep(0.0, 0.3, r));
    float gas = 1.0 / (1.0 + r / 0.08) * exp(-r * r / 1.6);
    float core = exp(-dot(p, p) / 0.0006) * B.e2.w;
    return (B.e.rgb * coma * 0.9 + B.e2.rgb * gas * 0.7) * B.e.w + float3(1.0, 0.97, 0.9) * core * 3.0;
}

// Two stars with a stream of gas from the bigger one to an accretion disk around the companion.
static float3 binaryShade(float2 p, float fw, constant BodyP &B, thread float &alpha) {
    float sep = B.q1.x, rb = B.q1.y, ph = B.q1.w;
    float3 bx = B.bx.xyz, by = B.by.xyz, bz = B.bz.xyz;
    float3 axis = bx * cos(ph) + by * sin(ph);
    float qa = rb * rb / (1.0 + rb * rb);   // centre of mass closer to the heavier star
    float3 A = -axis * sep * qa, Bc = axis * sep * (1.0 - qa);
    float3 acc = float3(0.0);
    float aacc = 0.0;
    // Elements: star A (stretched towards B), star B, accretion disk, stream. Collected by depth.
    float zA = -1e9, zB = -1e9, zD = -1e9;
    float3 cA = 0.0, cB = 0.0, cD = 0.0; float aA = 0.0, aB = 0.0, aD = 0.0;
    {
        // Star A fills its Roche lobe: round at the back, drawn out into a cusp towards the inner
        // Lagrange point. Self-luminous like a single star, cooler and darker towards the cusp.
        float2 d = p - A.xy;
        float s = B.q1.z;
        float ax2 = length(axis.xy);
        float2 u = ax2 > 1e-4 ? axis.xy / ax2 : float2(1.0, 0.0);
        float dl = max(length(d), 1e-4);
        float c = saturate(dot(d, u) / dl) * ax2;
        float R = 1.0 + (0.3 + 0.7 * s) * (0.12 * c * c + 0.5 * pow(c, 6.0));
        float rr = dl / R;
        float cov = smoothstep(1.0 + fw, 1.0 - fw, rr);
        if (cov > 0.0) {
            float mu = sqrt(saturate(1.0 - rr * rr));
            float m1 = 1.0 - mu;
            float limb = 1.0 - 0.60 * m1 - 0.24 * m1 * m1;
            float tip = c * c * c;
            float3 base = mix(B.q0.rgb, B.e.rgb, pow(mu, 0.6) * (1.0 - 0.5 * tip));
            float3 n3 = float3(d / R, mu);
            float gran = starGranules(n3 + B.a.w, 9.0, B.bz.w, B.q0.w, mu);
            cA = base * limb * gran * (1.0 - 0.25 * tip * (0.3 + 0.7 * s));
            aA = cov; zA = A.z + mu;
        }
    }
    {
        float2 d = p - Bc.xy;
        float rr = length(d) / rb;
        float cov = smoothstep(1.0 + fw / rb, 1.0 - fw / rb, rr);
        if (cov > 0.0) {
            float mu = sqrt(saturate(1.0 - rr * rr));
            cB = B.e2.rgb * (1.0 - 0.45 * (1.0 - mu));
            aB = cov; zB = Bc.z + mu * rb;
        }
    }
    float s = B.q1.z;
    if (s > 0.0) {
        // Disk around B in the orbital plane.
        float bzz = abs(bz.z) < 0.02 ? (bz.z < 0.0 ? -0.02 : 0.02) : bz.z;
        float zz = Bc.z - (dot(p - Bc.xy, bz.xy)) / bzz;
        float3 X = float3(p, zz) - Bc;
        float rr = length(X);
        float rin = rb * 1.3, rout = rb + sep * 0.26;
        if (rr > rin && rr < rout) {
            float x = (rr - rin) / (rout - rin);
            float ang = atan2(dot(X, by), dot(X, bx)) - ph;
            float spiral = 0.7 + 0.3 * sin(ang * 2.0 + log(rr) * 7.0 - B.bz.w * 0.8);
            float rings = 0.8 + 0.2 * vnoise3(float3(rr * 30.0, ang * 0.5, B.a.w));
            // Hot spot where the stream hits the rim.
            float spot = exp(-pow(atan2(sin(ang - 2.04), cos(ang - 2.04)) / 0.35, 2.0)) * smoothstep(0.6, 0.95, x);
            float I = (pow(1.0 - x, 2.2) * spiral * rings + spot * 0.6) * (1.0 - smoothstep(0.88, 1.0, x)) * smoothstep(0.0, 0.06, x);
            float op = saturate(I * 1.1 / max(abs(bzz), 0.2)) * 0.85;
            // Hot and bright: white-blue at the inner edge, yellow-orange at the rim, white hot spot.
            float3 hot = mix(float3(1.0, 0.50, 0.22), float3(0.80, 0.90, 1.0), pow(1.0 - x, 1.3));
            cD = (hot * I + float3(1.0, 0.9, 0.75) * spot * 0.8 * (1.0 - smoothstep(0.85, 1.0, x))) * 3.2 * s;
            aD = op * s; zD = zz;
        }
    }
    // Composite back to front: sort three elements by depth (small, unrolled).
    float zs[3] = { zA, zB, zD };
    float3 cs[3] = { cA * aA, cB * aB, cD };
    float as[3] = { aA, aB, aD };
    for (int i = 0; i < 3; i++) {
        int far = -1; float zf = 1e10;
        for (int j = 0; j < 3; j++) if (as[j] > 0.0 && zs[j] < zf) { zf = zs[j]; far = j; }
        if (far < 0) break;
        acc = cs[far] + (1.0 - as[far]) * acc;
        aacc = as[far] + (1.0 - as[far]) * aacc;
        as[far] = 0.0;
    }
    // The stream: from the inner Lagrange point, curling around the companion into the disk. Additive.
    if (s > 0.0) {
        // Starts at the tip of the lobe-filling star, so the stream leaves its surface.
        float3 L1 = A + axis * min(1.0 + 0.6 * (0.3 + 0.7 * s), sep * 0.58);
        float3 perpA = normalize(cross(bz, axis));
        float best = 1e9, bs = 0.0, bzv = 0.0;
        float3 prev = L1;
        for (int i = 1; i <= 14; i++) {
            float t = float(i) / 14.0;
            // Falls from L1 towards the companion, bent by the orbit, into the rim of the disk.
            float ang = 1.1 * t * t;
            float rad = mix(length(L1 - Bc), (rb + sep * 0.26) * 0.95, sqrt(t));
            float3 dirv = -axis * cos(ang) + perpA * sin(ang);
            float3 cur = Bc + dirv * rad;
            float2 a2 = prev.xy, b2 = cur.xy;
            float2 ab = b2 - a2;
            float h = saturate(dot(p - a2, ab) / max(dot(ab, ab), 1e-6));
            float d = length(p - a2 - ab * h);
            if (d < best) { best = d; bs = t; bzv = mix(prev.z, cur.z, h); }
            prev = cur;
        }
        float w = 0.05 + 0.07 * bs;
        float n = vnoise3(float3(bs * 12.0 - B.bz.w * 0.5, best * 20.0, B.a.w));
        float core = exp(-best * best / (w * w * 0.2));
        float I = (exp(-best * best / (w * w)) * (0.6 + 0.8 * n) + 0.18 * exp(-best * best / (w * w * 6.0))) * (1.0 - bs * 0.3) * s;
        // Hidden behind a star that is in front.
        float hidden = (bzv < zA ? aA : 0.0);
        hidden = max(hidden, bzv < zB ? aB : 0.0);
        // Glowing gas: orange, white-hot along its core, hotter where it falls in.
        float3 gc = mix(float3(1.0, 0.42, 0.15), float3(1.0, 0.80, 0.55), saturate(core * 0.6 + bs * 0.35));
        acc += gc * I * 1.3 * (1.0 - hidden);
    }
    alpha = aacc;
    return acc;
}

// One body sprite into its tile of the atlas. A compute kernel writes only the tile's pixels; a render
// pass would load and store the whole atlas every frame.
kernel void bodyKernel(texture2d<float, access::write> atlas [[texture(2)]], constant BodyP &B [[buffer(0)]],
                       constant uint4 &rect [[buffer(1)]],
                       texture2d<float> tA [[texture(0)]], texture2d<float> tB [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= rect.z || gid.y >= rect.w) return;
    float2 uv = (float2(gid) + 0.5) / float2(rect.zw);
    float ext = B.a.z;
    float2 p = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0) * ext;
    float fw = 2.0 * ext / float(rect.z);
    if (B.tide.z > 1.001) {
        // Stretched along the radius, squeezed across it, volume kept.
        float a = dot(p, B.tide.xy);
        p = B.tide.xy * (a / B.tide.z) + (p - a * B.tide.xy) * sqrt(B.tide.z);
    }
    int kind = int(B.a.x + 0.5);
    float alpha = 0.0;
    float3 col;
    if (kind == 0) {
        col = planetShade(p, fw, B, tA, tB, alpha);
    } else if (kind == 1) {
        float r2 = dot(p, p);
        float3 N = float3(p, sqrt(max(1.0 - r2, 0.0)));
        col = starSurface(N, p, B, alpha, fw);
    } else if (kind == 2) {
        col = rockShade(p, fw, B, alpha);
    } else if (kind == 3) {
        col = comaShade(p, B, alpha);
    } else {
        col = binaryShade(p, fw, B, alpha);
    }
    // Nothing may reach the tile border: the lookup clamps to zero outside.
    float2 b = abs(uv * 2.0 - 1.0);
    float border = 1.0 - smoothstep(0.93, 0.99, max(b.x, b.y));
    atlas.write(float4(col, alpha) * border, rect.xy + gid);
}

// ---------------------------------------------------------------- path L

static float hitDepth(float4 h, constant FrameParams &P) {
    float R = sqrt(h.x * h.x + P.disk.z * P.disk.z);
    return dot(R * h.yz, P.camF.xy) + P.camA.w;
}

// Bodies at this pixel, premultiplied, in four layers: behind both disk crossings, between them,
// in front of the disk but behind the hole (under the jet's front light), in front of everything.
// Which bodies can show at a pixel: inside the sprite's box widened by the body's Einstein radius
// (primary image), or near the hole (counter image). ext.y: Einstein radius (px), ext.z: hole reach (px).
static uint bodyCandidates(float2 px, constant FrameParams &P, constant BodyRef *b) {
    int n = int(P.camP.w + 0.5);
    float2 lc = float2(P.view.w, P.bars.w) * P.view.xy;
    float r2 = length_squared(px - lc);
    uint m = 0u;
    for (int i = 0; i < n; i++) {
        float4 cr = b[i].cand;
        float e = b[i].ext.y;
        if (all(px > cr.xy) && all(px < cr.zw)) m |= 1u << uint(i);
        else if (e > 0.0 && r2 < b[i].ext.z * b[i].ext.z) m |= 1u << uint(i);
    }
    return m;
}

// A body tile at a point t (0...1) of its screen box. Tiles drawn finer than the screen (quality High and
// Ultra) are averaged down with four taps a quarter pixel apart, so their edges come out smooth, not sharper
// and more stepped; tiles at screen resolution or coarser take one tap as before.
static float4 atlasTap(texture2d<float> atlas, float4 tile, float4 box, float2 t) {
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float2 uv = mix(tile.xy, tile.zw, t);
    float2 perPx = (tile.zw - tile.xy) / (box.zw - box.xy);   // atlas uv per screen px
    float2 dens = perPx * float2(atlas.get_width(), atlas.get_height());
    if (max(dens.x, dens.y) < 1.25) return atlas.sample(s, uv, level(0.0));
    float2 d = 0.25 * perPx;
    return 0.25 * (atlas.sample(s, uv - d, level(0.0)) + atlas.sample(s, uv + d, level(0.0))
                 + atlas.sample(s, uv + float2(d.x, -d.y), level(0.0)) + atlas.sample(s, uv + float2(-d.x, d.y), level(0.0)));
}

static void bodyLayers(float2 px, float3 dir, float wind, float captured, float4 h1, float c1, float4 h2, float c2,
                       uint bits, constant FrameParams &P, constant BodyRef *b, texture2d<float> atlas,
                       thread float4 &l0, thread float4 &l1, thread float4 &l2, thread float4 &l3) {
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float3 th = dirOfPx(px, P);
    float z1 = c1 > 0.01 ? hitDepth(h1, P) : 1e9;
    float z2 = c2 > 0.01 ? hitDepth(h2, P) : 1e9;
    float fade = 1.0 - smoothstep(4.0, 6.0, wind);
    while (bits != 0u) {
        int i = int(ctz(bits));
        bits &= bits - 1u;
        float w = b[i].geo.x;
        float2 q = w > 0.0 ? pxOfDir(normalize(mix(th, dir, w)), P) : px;
        float4 bx = b[i].box;
        if (any(q < bx.xy) || any(q > bx.zw)) continue;
        float2 t = (q - bx.xy) / (bx.zw - bx.xy);
        float4 c = atlasTap(atlas, b[i].tile, bx, t);
        if (w > 0.0) c *= (1.0 - captured) * fade;
        float z = b[i].geo.y;
        float rM = b[i].ext.w;
        float soft = max(rM * 0.2, 0.1);
        if (rM <= 0.0 || (abs(z - z1) > rM + 2.0 * soft && abs(z - z2) > rM + 2.0 * soft)) {
            if (z > z2) l0 = c + (1.0 - c.a) * l0;
            else if (z > z1) l1 = c + (1.0 - c.a) * l1;
            else if (z > P.camA.w) l2 = c + (1.0 - c.a) * l2;
            else l3 = c + (1.0 - c.a) * l3;
            continue;
        }
        // A round body (ext.w: radius in M) that a disk crossing cuts: sort the front surface of the sphere at
        // this pixel, not its centre, with a cut as soft as a fifth of the radius. With one depth for the whole
        // body the disk plane cut a planet along a straight screen line and one half sat under the disk's glow.
        float rho = length(q - b[i].geo.zw) / max(b[i].ext.x, 1e-3);
        float zs = z - rM * sqrt(max(1.0 - rho * rho, 0.0));
        float f1 = smoothstep(-soft, soft, z1 - zs);              // 1: in front of the near crossing
        float f2 = max(smoothstep(-soft, soft, z2 - zs), f1);     // 1: in front of the far crossing
        float4 cb = c * (1.0 - f2), cm = c * (f2 - f1), cf = c * f1;
        l0 = cb + (1.0 - cb.a) * l0;
        l1 = cm + (1.0 - cm.a) * l1;
        if (z > P.camA.w) l2 = cf + (1.0 - cf.a) * l2;
        else l3 = cf + (1.0 - cf.a) * l3;
    }
}

// ---------------------------------------------------------------- path F

struct FrontInst {
    float4 box;   // quad (px): x0 y0 x1 y1
    float4 a;     // kind (0 sprite, 1 glow, 2 spikes, 3 comet tail, 4 meteor, 5 smoke), depth, hide in the shadow, seed
    float4 b, c, d, e;
};

struct FOut {
    float4 pos [[position]];
    float2 px;
    uint inst [[flat]];
    float3 centre [[flat]];   // refined image centre (px) and magnification, for glows and spikes
};

// Glows and spikes of far stars: find the image in the ray map itself, so it sits exactly on the
// star's core. Newton steps on the escape direction, starting from the CPU estimate; the
// magnification comes from the map's Jacobian. One pixel per front instance.
fragment float4 glowRefine(VOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                           constant FrontInst *f [[buffer(4)]],
                           texture2d<float> tSky [[texture(0)]], texture2d<float> bSky [[texture(5)]]) {
    constant FrontInst &I = f[uint(in.pos.x)];
    int kind = int(I.a.x + 0.5);
    float4 dd = kind == 1 ? I.d : I.e;
    if ((kind != 1 && kind != 2) || dd.w < 0.5) return float4(I.b.xy, I.e.y, 0.0);
    float3 d = normalize(dd.xyz);
    float3 e1 = normalize(cross(d, abs(d.y) < 0.9 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0)));
    float3 e2 = cross(d, e1);
    float2 p = I.b.xy;
    float2 start = p;
    float pxA = P.objA.w;
    float mu = I.e.y;
    bool ok = false;
    for (int k = 0; k < 7; k++) {
        float2 uv = p / P.view.xy;
        float2 st = 2.0 / P.view.xy;
        float3 c0 = octDecode(skySample(uv, P, tSky, bSky).xy);
        float3 cx = octDecode(skySample(uv + float2(st.x, 0.0), P, tSky, bSky).xy) - octDecode(skySample(uv - float2(st.x, 0.0), P, tSky, bSky).xy);
        float3 cy = octDecode(skySample(uv + float2(0.0, st.y), P, tSky, bSky).xy) - octDecode(skySample(uv - float2(0.0, st.y), P, tSky, bSky).xy);
        float2 g = float2(dot(c0, e1), dot(c0, e2));
        float2x2 J = float2x2(float2(dot(cx, e1), dot(cx, e2)), float2(dot(cy, e1), dot(cy, e2))) * 0.25;
        float det = J[0][0] * J[1][1] - J[1][0] * J[0][1];
        if (abs(det) < 1e-14 || dot(c0, d) < 0.0) break;
        float2 step = float2(J[1][1] * g.x - J[1][0] * g.y, -J[0][1] * g.x + J[0][0] * g.y) / det;
        p -= clamp(step, -40.0, 40.0);
        mu = min(pxA * pxA / abs(det), 3.0);
        ok = length(step) < 0.25;
        if (ok) break;
    }
    if (!ok || length(p - start) > 80.0) return float4(start, I.e.y, 0.0);
    return float4(p, mu, 1.0);
}

constant float2 quadCorner[6] = { float2(0, 0), float2(1, 0), float2(1, 1), float2(0, 0), float2(1, 1), float2(0, 1) };

static float4 regionPos(float2 px, constant FrameParams &P) {
    float2 r = (px / P.view.xy - P.region.xy) / (P.region.zw - P.region.xy);
    return float4(r.x * 2.0 - 1.0, 1.0 - r.y * 2.0, 0.0, 1.0);
}

vertex FOut frontVert(uint vid [[vertex_id]], uint iid [[instance_id]], constant FrameParams &P [[buffer(0)]],
                      constant FrontInst *f [[buffer(4)]], texture2d<float> refined [[texture(0)]],
                      constant uint2 &base [[buffer(5)]]) {
    FOut o;
    // base.x: offset of this draw in the refined texels, base.y: refinement ran this frame.
    float4 r = base.y != 0u ? refined.read(uint2(iid + base.x, 0)) : float4(0.0);
    float2 shift = r.w > 0.5 ? r.xy - f[iid].b.xy : float2(0.0);
    float2 px;
    int kind = int(f[iid].a.x + 0.5);
    if ((kind >= 2 && kind <= 5) || kind >= 7) {
        // Spikes, tails, meteors, smoke, ship events and plumes: a thin quad along the line. box = start (xy), end (zw); a.y = half width.
        float2 s0 = f[iid].box.xy + shift, s1 = f[iid].box.zw + shift;
        float2 ax = s1 - s0;
        float2 nrm = normalize(float2(-ax.y, ax.x) + 1e-6) * f[iid].a.y;
        float2 cq = quadCorner[vid];
        px = s0 + ax * cq.x + nrm * (cq.y * 2.0 - 1.0);
    } else {
        px = mix(f[iid].box.xy, f[iid].box.zw, quadCorner[vid]) + shift;
    }
    o.pos = regionPos(px, P);
    o.px = px;
    o.inst = iid;
    o.centre = float3(f[iid].b.xy + shift, r.w > 0.5 ? r.z : f[iid].e.y);
    return o;
}

// How far into the picture a bar's light and darkening reach (px), so most pixels skip them.
static float bandReach(int side, constant FrameParams &P) {
    float4 e0 = P.edge[side * 4], e2 = P.edge[side * 4 + 2];
    if (e0.x <= 0.0) return -1e4;
    float s = P.bars.z;
    return max(max(e0.z * s * 4.0 + 6.0 * s, max(e0.y, 0.2) * s * 4.0), max(e2.z, 4.0 * s) * 2.5) + 2.0;
}

// Darkening near the bars at a pixel, as dispFrag applies it.
static float barDarken(float2 px, constant FrameParams &P) {
    float dT = px.y - P.bars.x, dB = (P.view.y - px.y) - P.bars.y;
    float m = 1.0;
    if (dT < bandReach(0, P)) m *= edgeDarken(dT, 0, P);
    if (dB < bandReach(1, P)) m *= edgeDarken(dB, 1, P);
    return m;
}

// Path F output: the instance's light (premultiplied, linear) over the linear colour of the pixel,
// then band light and tone mapping as finishPixel does. Both attachments are written.
struct FrontOut {
    float4 c [[color(0)]];
    float4 lin [[color(1)]];
};

static FrontOut frontFinish(float4 src, float3 lin, float2 px, constant FrameParams &P, texture2d<float> tEdge) {
    src.rgb *= barDarken(px, P);
    float3 l = src.rgb + (1.0 - src.a) * lin;
    float H = P.view.y, t = P.nebp.y;
    float dmT, dmB;
    float3 band = float3(0.0);
    float dT = px.y - P.bars.x, dB = (H - px.y) - P.bars.y;
    if (dT < bandReach(0, P)) band += edgeLight(dT, px.x, t, 0, P, tEdge, dmT);
    if (dB < bandReach(1, P)) band += edgeLight(dB, px.x, t, 1, P, tEdge, dmB);
    float3 col = pow(aces((l + band) * P.look.x), float3(1.0 / 2.2));
    col += (hash12(px + fract(t) * 91.0) - 0.5) / 255.0;
    FrontOut o;
    o.c = float4(col, 1.0);
    o.lin = float4(l, 1.0);
    return o;
}

static float capturedAt(float2 px, constant FrameParams &P, texture2d<float> tSky, texture2d<float> bSky) {
    float4 s = skySample(px / P.view.xy, P, tSky, bSky);
    return smoothstep(0.49, 0.51, s.w);
}

// How much of a far star's image at c shows: not in the shadow, not behind the bright disk.
// The glow belongs to the camera, but a hidden star makes none.
static float glowVisible(float2 c, constant FrameParams &P, texture2d<float> tSky, texture2d<float> bSky,
                         texture2d<half> tD1, texture2d<half> bD1) {
    float2 uv = c / P.view.xy;
    float cap = capturedAt(c, P, tSky, bSky);
    float2 bmin = P.box.xy, bmax = P.box.zw;
    bool inBox = P.box.x >= 0.0 && all(uv > bmin) && all(uv < bmax);
    float cov;
    float4 h = inBox ? diskFetch(bD1, (uv - bmin) / (bmax - bmin), cov) : diskFetch(tD1, uv, cov);
    float disk = (h.x < P.disk.y && h.x > 0.8) ? cov * (1.0 - smoothstep(P.disk.y * 0.35, P.disk.y, h.x)) * 0.85 : 0.0;
    return (1.0 - cap) * (1.0 - disk);
}

static float tailNoise(float2 x) { return vnoise3(float3(x, 0.5)); }

// Light of a ship event (path F, additive). b: centre, ship radius (px), effect. c: colour, phase of the
// departure (0...1). d: flight direction on the screen, rainbow, arrival. Kept faint: short and elegant.
static float3 shipEventLight(float2 px, constant FrontInst &I) {
    float2 c = I.b.xy, dir = I.d.xy;
    float R = max(I.b.z, 1.0);
    int fx = int(I.b.w + 0.5);
    float ph = I.c.w;
    float2 v = px - c;
    float along = dot(v, dir), perp = dir.x * v.y - dir.y * v.x;
    float r = length(v);
    float3 col = I.c.rgb;
    float3 sum = float3(0.0);
    if (fx == 0 || fx == 1) {
        // Streaks running ahead of the ship, a short flash where it vanishes.
        float life = smoothstep(0.32, 0.48, ph) * (1.0 - smoothstep(0.5, 1.0, ph));
        float L = R * (2.0 + 22.0 * smoothstep(0.35, 0.8, ph));
        float s = along / L;
        float lane = smoothstep(-0.02, 0.06, s) * pow(saturate(1.0 - s), 1.5);
        for (int k = 0; k < 6; k++) {
            float h = hash12(float2(float(k), I.a.w));
            float off = (h - 0.5) * R * (fx == 0 ? 0.7 : 1.1);
            float w = R * 0.01 + 0.55;
            float line = exp(-(perp - off) * (perp - off) / (w * w)) * (0.4 + 0.6 * hash12(float2(float(k), 7.0)));
            float3 lc = I.d.z > 0.5 ? mix(hueRGB(float(k) * 55.0 + s * 160.0), float3(1.0), 0.5) : col;
            sum += lc * line;
        }
        sum *= lane * life * 0.45;
        float fl = exp(-pow((ph - (fx == 0 ? 0.48 : 0.43)) / 0.06, 2.0));
        sum += mix(col, float3(1.0), 0.5) * fl * (exp(-r * r / (R * R * 0.025)) * 0.8 + exp(-r / (R * 0.35)) * 0.08);
    } else if (fx == 2) {
        // A bluish flash where the ship contracts, then a thin ring of distorted light running out.
        float fl = exp(-pow((ph - 0.4) / 0.07, 2.0));
        float t = saturate((ph - 0.38) / 0.62);
        float rr = R * (0.3 + 2.6 * t);
        float ring = exp(-pow((r - rr) / (R * 0.05 + 0.8), 2.0)) * step(0.38, ph) * (1.0 - t);
        sum = col * (fl * (exp(-r * r / (R * R * 0.03)) * 0.9 + exp(-r / (R * 0.4)) * 0.08) + ring * 0.3);
    } else if (fx == 3) {
        // A spiral vortex opening ahead of the ship and closing behind it.
        float open = smoothstep(0.0, 0.3, ph) * (1.0 - smoothstep(0.62, 1.0, ph));
        float rad = R * 1.5 * open + 0.5;
        float a = atan2(perp, along);
        float sp = 0.5 + 0.5 * sin(a * 3.0 + log(r / R + 0.05) * 7.0 - ph * 14.0);
        float body = exp(-r * r / (rad * rad)) * (0.35 + 0.65 * sp * sp);
        float core = exp(-r * r / (rad * rad * 0.04)) * open;
        sum = col * (body * 0.7 + core * 0.9) * open;
    } else if (fx == 4) {
        // Cloak: a faint ripple of bent light where the hull was.
        float rr = R * (0.75 + 0.35 * ph);
        float n = vnoise3(float3(v / R * 5.0, ph * 6.0));
        float sh = exp(-pow((r - rr) / (R * 0.1), 2.0)) * (0.3 + 0.7 * n * n);
        sum = col * sh * 0.14 * sin(ph * 3.14159);
    } else if (fx == 5) {
        // Pulsing glow; multicoloured flicker for the improbability drive.
        float pulse = 0.5 + 0.5 * cos(ph * 6.0 * 3.14159);
        float g = exp(-r * r / (R * R * 0.7)) * pulse * sin(ph * 3.14159);
        float3 cc = I.d.z > 0.5 ? hueRGB(ph * 900.0 + r * 3.0) : col;
        sum = cc * g * 0.8;
    } else if (fx == 6) {
        // Light tunnel: thin coloured streaks rushing out from the ship.
        float a = atan2(v.y, v.x) / 6.2831853 + 0.5;
        float k = floor(a * 48.0);
        float h = hash12(float2(k, I.a.w));
        float f = fract(a * 48.0) - 0.5;
        float head = R * (0.4 + 3.0 * ph * (0.6 + 0.8 * h));
        float streak = exp(-f * f / 0.02) * smoothstep(R * 0.3, R * 0.6, r) * exp(-pow((r - head) / (R * 0.9), 2.0)) * step(0.5, h);
        sum = (I.d.z > 0.5 ? mix(hueRGB(h * 360.0), float3(1.0), 0.3) : col) * streak * sin(ph * 3.14159) * 0.5;
    }
    // Round soft edge well inside the quad (half size a.y around c): the glows never reach its sides,
    // which showed as straight edges of the vortex field.
    return sum * (1.0 - smoothstep(0.62, 0.97, r / max(I.a.y, 1.0)));
}

// Light of one front instance at a pixel (linear, premultiplied).
static float4 frontSource(FOut in, constant FrontInst &I, constant FrameParams &P,
                          texture2d<float> tSky, texture2d<float> bSky, texture2d<half> tD1, texture2d<half> bD1,
                          texture2d<float> atlas) {
    float2 px = in.px;
    int kind = int(I.a.x + 0.5);
    float4 src = float4(0.0);
    if (kind == 0) {
        float2 t = (px - I.box.xy) / (I.box.zw - I.box.xy);
        src = atlasTap(atlas, I.d, I.box, t);
    } else if (kind == 1) {
        // Camera glow around one image of a star, as bright as that image.
        float rs = length(px - in.centre.xy);
        float rho = I.b.z, glow = I.b.w, reach = I.e.x, mu = in.centre.z;
        float halo;
        if (I.e.z > 0.0) {
            // Near star: corona glow from the limb out into space, nothing over the disc itself.
            float R = I.e.z;
            float x = max(rs / R - 1.0, 0.0);
            float rim = smoothstep(0.88, 1.0, rs / R);
            halo = glow * (0.06 * exp(-x / 0.06) + 0.10 * exp(-x / 0.3) + 0.04 * exp(-x / 1.2)) * rim
                 * (1.0 - smoothstep(0.5 * reach, reach, rs)) * mu;
        } else {
            float edge = 1.0 - smoothstep(0.2 * reach, reach, rs);
            edge *= edge;
            halo = glow * (0.10 * exp(-rs / (rho * 3.0)) + 0.03 * exp(-rs / (rho * 9.0))) * edge * mu;
        }
        src = float4(I.c.rgb * halo, 0.0);
    } else if (kind == 2) {
        // Diffraction spikes: thin lines through the image, slowly falling off, red reaching further.
        float2 v = px - in.centre.xy;
        int n = int(I.d.x + 0.5);
        float ang0 = I.d.y, L = I.d.z, w = I.d.w;
        float3 sum = float3(0.0);
        for (int k = 0; k < n; k++) {
            float a = ang0 + 3.14159265 * float(k) / float(n);
            float2 dk = float2(cos(a), sin(a));
            float along = abs(dot(v, dk));
            float perp = abs(v.x * dk.y - v.y * dk.x);
            float3 Lc = L * float3(1.12, 1.0, 0.88);
            float3 fall = pow(1.0 + along / (0.05 * Lc), float3(-1.5)) * (1.0 - smoothstep(0.4 * Lc, Lc, float3(along)));
            float ripple = 0.8 + 0.2 * cos(along * 0.8);
            sum += exp(-perp * perp / (w * w)) * fall * ripple * smoothstep(w * 1.5, w * 4.0, along);
        }
        src = float4(I.c.rgb * sum, 0.0);
    } else if (kind == 3) {
        // Comet tails: ion tail straight away from the light, dust tail curved along the orbit.
        float2 N = I.b.xy;
        float time = I.e.w;
        float3 sum = float3(0.0);
        {
            float2 E = I.b.zw;
            float2 u = E - N;
            float len = max(length(u), 1.0);
            u /= len;
            float2 v = px - N;
            float s = dot(v, u) / len;
            float perp = v.x * u.y - v.y * u.x;
            if (s > -0.02) {
                float sc = saturate(s);
                float w = mix(I.c.w, I.d.z, sc);
                float rays = tailNoise(float2(perp / max(w, 1.0) * 3.0 + 7.0, sc * 2.0 - time * 0.15));
                float rays2 = tailNoise(float2(perp / max(w, 1.0) * 9.0, sc * 5.0 - time * 0.35));
                float g = exp(-perp * perp / (w * w)) * pow(1.0 - sc, 1.3) * smoothstep(-0.02, 0.03, s);
                sum += I.c.rgb * g * (0.35 + 0.9 * rays * rays + 0.4 * rays2);
            }
        }
        {
            // Quadratic Bezier N -> C -> D. In the frame along N -> D it is x(t) = 2 t (1-t) cx + t^2 L,
            // y(t) = 2 t (1-t) cy: solve t from x, take the offset in y as the distance.
            float2 C = I.e.xy, D = I.d.xy;
            float2 ax = D - N;
            float L = max(length(ax), 1.0);
            ax /= L;
            float2 ay = float2(-ax.y, ax.x);
            float2 q = float2(dot(px - N, ax), dot(px - N, ay));
            float cx = dot(C - N, ax), cy = dot(C - N, ay);
            float a = L - 2.0 * cx, b2 = 2.0 * cx;
            float t = abs(a) < 1e-3 ? q.x / max(b2, 1e-3) : (-b2 + sqrt(max(b2 * b2 + 4.0 * a * q.x, 0.0))) / (2.0 * a);
            if (t > -0.05 && t < 1.0) {
                float bs = saturate(t);
                float yc = 2.0 * bs * (1.0 - bs) * cy;
                float best = abs(q.y - yc);
                float side = sign(q.y - yc) * sign(cy + 1e-3);
                float w = mix(I.c.w * 1.4, I.d.w, pow(bs, 0.7));
                float striae = 0.65 + 0.35 * tailNoise(float2(bs * 14.0 + side * best / max(w, 1.0) * 1.5, 3.0));
                float g = exp(-best * best / (w * w)) * pow(1.0 - bs, 1.2) * (1.0 + 0.35 * side * min(best / max(w, 1.0), 1.0))
                        * smoothstep(-0.05, 0.02, t);
                sum += g * striae * float3(1.0, 0.86, 0.62) * I.e.z;
            }
        }
        src = float4(sum, 0.0);
    } else if (kind == 4 || kind == 5) {
        // Meteor: bright head, a trail that fades behind it. Smoke: a wide faint wisp left behind.
        float2 H = I.b.xy, T = I.b.zw;
        float2 u = T - H;
        float len = max(length(u), 1.0);
        u /= len;
        float2 v = px - H;
        float s = dot(v, u) / len;
        float perp = v.x * u.y - v.y * u.x;
        float w = I.d.x;
        if (kind == 4) {
            float trail = exp(-perp * perp / (w * w)) * pow(saturate(1.0 - s), 2.2) * step(0.0, s);
            float head = exp(-dot(v, v) / (w * w * 4.0)) * 1.2 + exp(-dot(v, v) / (w * w * 30.0)) * 0.12;
            src = float4(I.c.rgb * (trail + head) * I.c.w, 0.0);
        } else {
            float sc = saturate(s);
            float n = tailNoise(float2(sc * 8.0 + I.a.w, perp / w * 0.7));
            float ww = w * (1.0 + sc * 1.5);
            float g = exp(-perp * perp / (ww * ww)) * smoothstep(0.0, 0.15, s) * (1.0 - smoothstep(0.6, 1.0, s));
            src = float4(I.c.rgb * g * (0.4 + 0.9 * n) * I.c.w, 0.0);
        }
    } else if (kind == 6) {
        // Nebula shell around a Wolf-Rayet star: clumpy, filamentary gas thrown off by the wind,
        // pink hydrogen with teal oxygen at the outer edge.
        float2 v = (px - I.b.xy) / I.b.z;
        float r = length(v);
        float3 dv = float3(v * 2.2, I.a.w);
        float nz = fbm3(dv, 3);
        float rr = (r - (0.78 + 0.34 * nz)) / (0.07 + 0.06 * nz);
        float shell = exp(-rr * rr);
        float clump = fbm3(float3(v * 7.0, I.a.w + 5.0), 3);
        float fil = 1.0 - abs(vnoise3(float3(v * 6.0, I.a.w + 9.0)) * 2.0 - 1.0);
        // Brighter arcs and gaps along the ring, clumps within.
        float arc = smoothstep(0.3, 0.7, fbm3(float3(normalize(v + 1e-5) * 1.6, I.a.w + 13.0), 2));
        float lumpy = (smoothstep(0.3, 0.8, clump) * 1.4 + 0.15 * fil * fil) * (0.25 + 1.3 * arc);
        float oxy = smoothstep(0.0, 0.8, (r - (0.8 + 0.3 * nz)) / 0.1);
        float3 hc = mix(float3(1.0, 0.32, 0.40), float3(0.30, 0.80, 0.85), saturate(oxy * 0.8));
        float fill = 0.08 * (1.0 - smoothstep(0.0, 1.0, r)) * clump * clump;
        src = float4(hc * I.c.rgb * (shell * lumpy + fill) * (1.0 - smoothstep(1.15, 1.45, r)), 0.0);
    } else if (kind == 7) {
        src = float4(shipEventLight(px, I), 0.0);
    } else if (kind == 8) {
        // Exhaust plume: a tapered glow along the thrust, white-hot near the nozzle, with shock diamonds.
        float2 a = I.b.xy, u = I.d.xy;
        float L = max(I.d.z, 1.0), w = I.d.w;
        float2 v = px - a;
        float s = dot(v, u) / L;
        float perp = v.x * u.y - v.y * u.x;
        if (s > -0.08) {
            float sc = saturate(s);
            float ww = w * (1.0 + 1.2 * sc);
            float g = exp(-perp * perp / (ww * ww)) * pow(1.0 - sc, 1.6) * smoothstep(-0.08, 0.02, s);
            float core = exp(-perp * perp / (ww * ww * 0.12)) * pow(1.0 - sc, 3.0) * smoothstep(-0.05, 0.02, s);
            float dia = 0.8 + 0.2 * cos(sc * 38.0 - I.e.x * 3.0);
            float flick = 0.9 + 0.1 * tailNoise(float2(sc * 6.0 - I.e.x * 4.0, perp / max(w, 1.0)));
            src = float4((I.c.rgb * g * 0.7 * dia + mix(I.c.rgb, float3(1.0), 0.6) * core * 1.2) * flick * I.c.w * 0.6, 0.0);
        }
    }
    if (I.a.z > 1.5) src *= glowVisible(in.centre.xy, P, tSky, bSky, tD1, bD1);
    else if (I.a.z > 0.5) src *= 1.0 - capturedAt(px, P, tSky, bSky);
    return src;
}

fragment FrontOut frontFrag(FOut in [[stage_in]], float4 lin [[color(1)]], constant FrameParams &P [[buffer(0)]],
                            constant FrontInst *f [[buffer(4)]],
                            texture2d<float> tSky [[texture(0)]], texture2d<float> bSky [[texture(5)]],
                            texture2d<half> tD1 [[texture(1)]], texture2d<half> bD1 [[texture(6)]],
                            texture2d<float> tEdge [[texture(9)]], texture2d<float> atlas [[texture(18)]]) {
    float4 src = frontSource(in, f[in.inst], P, tSky, bSky, tD1, bD1, atlas);
    if (max(max(src.r, src.g), max(src.b, src.a)) < 1e-4) discard_fragment();
    return frontFinish(src, lin.rgb, in.px, P, tEdge);
}

// Soft additive light into the light buffer (half resolution, added blending), read by dispFrag
// before tone mapping: no framebuffer reads, no ordering between overlapping blobs.
fragment float4 lightFrag(FOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                          constant FrontInst *f [[buffer(4)]],
                          texture2d<float> tSky [[texture(0)]], texture2d<float> bSky [[texture(5)]],
                          texture2d<half> tD1 [[texture(1)]], texture2d<half> bD1 [[texture(6)]],
                          texture2d<float> atlas [[texture(18)]]) {
    float4 src = frontSource(in, f[in.inst], P, tSky, bSky, tD1, bD1, atlas);
    return float4(src.rgb, 1.0);
}

// Over a linear target (the still under the strips of edges-only mode).
fragment float4 frontLinFrag(FOut in [[stage_in]], float4 dst [[color(0)]], constant FrameParams &P [[buffer(0)]],
                             constant FrontInst *f [[buffer(4)]],
                             texture2d<float> tSky [[texture(0)]], texture2d<float> bSky [[texture(5)]],
                             texture2d<half> tD1 [[texture(1)]], texture2d<half> bD1 [[texture(6)]],
                             texture2d<float> atlas [[texture(18)]]) {
    float4 src = frontSource(in, f[in.inst], P, tSky, bSky, tD1, bD1, atlas);
    src.rgb *= barDarken(in.px, P);
    return float4(src.rgb + (1.0 - src.a) * dst.rgb, 1.0);
}

// ---------------------------------------------------------------- particles

struct PartSys {
    float4 a;     // type (0 belt, 1 dust ring, 2 edge stream), count, seed, orbit clock (rad at the ISCO, wrapped at 2 pi 1024)
    float4 geo;   // r inner, r outer (M), thickness (rad), clumping
    float4 ax, ay, az;   // world axes of the belt plane (az = normal)
    float4 sz;    // size min, size max (px at the hole's depth), dust glow, ISCO (M)
    float4 col;   // albedo rgb, spin a
    float4 lit;   // light colour * gain, alpha scale
    float4 edge;  // edge stream: band line y (px), into the picture (+1 down, -1 up), speed (px/s), spread (px)
    float4 edge2; // edge stream: time (s), offset (px), wobble (px), unused
};

// Particles are point sprites: one vertex each, the rasterizer makes the square.
struct POut {
    float4 pos [[position]];
    float pointSize [[point_size]];
    float4 col [[flat]];   // premultiplied linear colour (rock) or additive (dust, alpha 0)
    float3 ls [[flat]];    // light direction in the sprite frame
    float size [[flat]];
    float rock [[flat]];   // 1..2 rock shading (fraction seeds the outline), 0 soft dot
};

static float gauss2(float u, float v) { return sqrt(-2.0 * log(max(u, 1e-6))) * cos(6.2831853 * v); }

// Lambert sphere seen at phase angle a (cos given): 1 full, 0 new.
static float lambertPhase(float ca) {
    float a = acos(clamp(ca, -1.0, 1.0));
    return (sin(a) + (3.14159265 - a) * cos(a)) / 3.14159265;
}

static float hg(float c, float g) { return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5) * 0.0796; }

vertex POut partVert(uint iid [[vertex_id]], constant FrameParams &P [[buffer(0)]],
                     constant PartSys &S [[buffer(3)]], constant BodyRef *bodies [[buffer(2)]]) {
    POut o;
    o.pos = float4(-9.0, -9.0, 0.0, 1.0);
    o.pointSize = 0.0;
    o.col = 0.0; o.ls = float3(0.0, 0.0, 1.0); o.size = 0.0; o.rock = 0.0;
    uint i = iid >> 1, img = iid & 1u;
    int type = int(S.a.x + 0.5);
    float seed = S.a.z;
    float fi = float(i);
    float h1 = hash13(float3(fi, seed, 1.7)), h2 = hash13(float3(fi, seed, 2.9)), h3 = hash13(float3(fi, seed, 4.1));
    float h4 = hash13(float3(fi, seed, 5.3)), h5 = hash13(float3(fi, seed, 6.7)), h6 = hash13(float3(fi, seed, 8.3));
    float h7 = hash13(float3(fi, seed, 9.1)), h8 = hash13(float3(fi, seed, 10.9));
    float2 p;
    float sizePx;
    float3 col;
    float alpha = S.lit.w;
    bool dust = false;
    float3 ls = float3(0.0, 0.0, 1.0);
    float bright = 1.0;
    float2 c = float2(P.view.w, P.bars.w) * P.view.xy;
    if (type == 2) {
        if (img == 1u) return o;
        float W = P.view.x;
        float m = S.sz.y * 2.0 + 10.0;
        float spd = S.edge.z * (0.6 + 0.8 * h4);
        float x = fract(h1 + S.edge2.x * spd / (W + 2.0 * m)) * (W + 2.0 * m) - m;
        if (S.edge.z < 0.0) x = W - x;
        float y = S.edge.x + S.edge.y * (S.edge2.y + abs(gauss2(h2, h3)) * S.edge.w * 0.6 + gauss2(h5, h6) * S.edge.w * 0.25
                  + S.edge2.z * sin(S.edge2.x * 0.9 + x * 0.004 + h7));
        p = float2(x, y);
        float sz = mix(S.sz.x, S.sz.y, pow(h8, 5.0));
        sizePx = sz;
        float3 alb = S.col.rgb * (0.7 + 0.6 * h7);
        float2 toHole = normalize(c - p);
        ls = normalize(float3(toHole.x, -toHole.y, 0.35));
        col = alb * S.lit.rgb * 0.8;
        o.rock = sz > 2.5 ? 1.0 + 0.999 * h1 : 0.0;
        bright = 1.0;
    } else {
        float rin = S.geo.x, rout = S.geo.y;
        float r = mix(rin, rout, h1);
        // Ringlets and gaps, and a soft profile across the belt.
        float x = (r - rin) / max(rout - rin, 1e-3);
        float dens = smoothstep(0.0, 0.15, x) * (1.0 - smoothstep(0.75, 1.0, x));
        dens *= 0.55 + 0.45 * vnoise3(float3(x * 9.0, seed, 0.5));
        dens *= 1.0 - 0.85 * exp(-(x - 0.37) * (x - 0.37) / 0.0008) - 0.7 * exp(-(x - 0.71) * (x - 0.71) / 0.0004);
        if (h2 > dens) return o;
        dust = type == 1 || h8 < 0.16;
        float phi0 = h3 * 6.2831853;
        if (h4 < S.geo.w && !dust) {
            float k = floor(h5 * 9.0);
            phi0 = hash13(float3(k, seed, 3.3)) * 6.2831853 + gauss2(h6, h7) * 0.18;
        }
        float a = S.col.w, isco = S.sz.w;
        float f = (pow(isco, 1.5) + a) / (pow(r, 1.5) + a);
        f = floor(f * 1024.0 + 0.5) / 1024.0;
        float phi = phi0 + f * S.a.w;
        float z = gauss2(h6, h5) * S.geo.z * r * 0.5;
        float3 X = S.ax.xyz * (r * cos(phi)) + S.ay.xyz * (r * sin(phi)) + S.az.xyz * z;
        float3 rel = X - P.camP.xyz;
        float3 q = float3(dot(rel, P.camR.xyz), dot(rel, P.camU.xyz), dot(rel, P.camF.xyz));
        if (q.z < 4.0) return o;
        float zh = P.camA.w;
        float dls = q.z - zh;
        float2 beta = q.xy / q.z;
        float2 th = beta;
        float mu = 1.0;
        if (dls > 0.0) {
            float te2 = 4.0 * dls / (zh * q.z);
            float bl = length(beta);
            float root = sqrt(bl * bl + 4.0 * te2);
            float t = img == 0u ? (bl + root) * 0.5 : (bl - root) * 0.5;
            th = beta / max(bl, 1e-7) * t;
            float u = bl / sqrt(te2);
            float m0 = (u * u + 2.0) / max(u * sqrt(u * u + 4.0), 1e-5);
            mu = img == 0u ? (m0 + 1.0) * 0.5 : (m0 - 1.0) * 0.5;
            mu = min(mu, 8.0);
        } else if (img == 1u) return o;
        p = pxOfDir(float3(th, 1.0), P);
        if (dls > 0.0 && length(p - c) < P.camR.w * 1.04) return o;
        if (mu < 0.02) return o;
        // Hidden behind a nearer body.
        int nb = int(P.camP.w + 0.5);
        for (int k = 0; k < nb; k++) {
            if (bodies[k].geo.y < q.z && length(p - bodies[k].geo.zw) < bodies[k].ext.x) return o;
        }
        // Seen through the accretion disk: dimmed.
        float3 cp = P.camP.xyz;
        if (cp.z * X.z < 0.0) {
            float tt = cp.z / (cp.z - X.z);
            float rd = length((cp + (X - cp) * tt).xy);
            if (rd < P.disk.y && rd > P.disk.x * 0.8) bright *= 1.0 - 0.6 * (1.0 - smoothstep(P.disk.y * 0.6, P.disk.y, rd));
        }
        float3 toL = normalize(-X), toC = normalize(cp - X);
        float ca = dot(toL, toC);
        float fall = min(3600.0 / max(dot(X, X), 100.0), 1.6);
        float sc = zh / q.z;
        float3 alb = S.col.rgb * (0.65 + 0.7 * h7);
        if (dust && (type == 0 || h8 < 0.5)) {
            // Haze between the rocks: big faint blobs that add up to a continuous glowing band,
            // brighter in forward scattering (the near side, backlit by the disk).
            // A dust ring takes half of its grains as haze, so it reads as a band, not as salt.
            sizePx = min((22.0 + 30.0 * h5) * sc, 60.0);
            float scat = hg(-ca, 0.55) * 1.6 + 0.45 * lambertPhase(ca);
            // Ice tinted by the orange disk light turns olive; keep the ring's own hue.
            float3 lit = type == 0 ? S.lit.rgb : mix(S.lit.rgb, float3(dot(S.lit.rgb, float3(0.333))), 0.7);
            float3 tint = type == 0 ? float3(1.0, 0.92, 0.82) : S.col.rgb * 0.3;
            // The same total haze for any number of particles.
            col = lit * tint * scat * fall * S.sz.z * 0.012 * (0.6 + 0.4 * dens) * min(7000.0 / max(S.a.y, 1.0), 2.0);
            alpha = 0.0;
        } else if (dust) {
            // Fine dust: faint and small, it adds up to a translucent glowing ring, brightest in forward scattering.
            sizePx = mix(S.sz.x, S.sz.y, h5) * sc + 0.8;
            float scat = hg(-ca, 0.6) * 2.5 + 0.2 * lambertPhase(ca);
            col = mix(S.lit.rgb, float3(dot(S.lit.rgb, float3(0.333))), 0.7) * alb * scat * fall * S.sz.z * 0.13;
            alpha = 0.0;
        } else {
            sizePx = mix(S.sz.x, S.sz.y, pow(h5, 4.0)) * sc;
            float3 lc = float3(dot(toL, P.camR.xyz), dot(toL, P.camU.xyz), -dot(toL, P.camF.xyz));
            ls = normalize(lc);
            o.rock = sizePx > 2.5 ? 1.0 + 0.999 * h7 : 0.0;
            // Big rocks are shaded per pixel (phase and rim come from that); small ones take the phase here.
            col = alb * S.lit.rgb * fall * (o.rock > 0.5 ? 0.55 : lambertPhase(ca));
        }
        bright *= mu;
        sizePx *= min(sqrt(mu), 2.0);
    }
    // Rocks and fine dust are drawn over the picture, haze into the light buffer (quarter resolution;
    // edge2.z scales the haze so it covers the same part of the screen as it did at half resolution).
    int pass = int(S.edge2.w + 0.5);
    bool haze = dust && (type == 0 || h8 < 0.5);
    if ((pass == 1 && haze) || (pass == 2 && !haze)) { o.pos = float4(-9.0, -9.0, 0.0, 1.0); return o; }
    if (pass == 2 && S.edge2.z > 0.0) sizePx *= S.edge2.z;
    // Fine dust used to go through the half-resolution buffer: as large on the screen as it was there.
    if (dust && !haze && pass == 1) sizePx *= 2.0;
    // Sub-pixel particles: keep a quad of 1.5 px and lower the brightness instead.
    float drawn = min(max(sizePx, 1.5), 120.0);
    float energy = (sizePx * sizePx) / (drawn * drawn);
    o.pos = regionPos(p, P);
    o.pointSize = drawn;
    o.size = drawn;
    o.ls = ls;
    float a = dust ? 0.0 : alpha * min(energy * 1.4, 1.0);
    o.col = float4(col * bright * (dust ? energy : 1.0), a);
    return o;
}

static float4 partSource(POut in, float2 uv) {
    float r2 = dot(uv, uv);
    if (in.col.a <= 0.0) {
        return float4(in.col.rgb * exp(-r2 * 3.0), 0.0);
    } else if (in.rock > 0.5) {
        // A lumpy rock: lit like a sphere, ragged outline.
        float ang = atan2(uv.y, uv.x);
        float sd = fract(in.rock) * 6.2831853;
        float rim = 0.84 + 0.09 * sin(ang * 2.0 + sd) + 0.06 * sin(ang * 3.0 + sd * 2.7) + 0.04 * sin(ang * 5.0 + sd * 4.1);
        float cov = smoothstep(rim, rim - 2.0 / max(in.size, 1.0), sqrt(r2));
        float3 n = float3(uv.x, -uv.y, sqrt(max(1.0 - r2, 0.0)));
        float d = saturate(dot(n, in.ls) * 0.95 + 0.05);
        // Backlit rocks keep a thin bright rim on the side towards the light.
        float rimL = pow(1.0 - n.z, 3.0) * saturate(-in.ls.z) * saturate(dot(normalize(n.xy + 1e-4), normalize(in.ls.xy + 1e-4)));
        return float4(in.col.rgb * (d * 2.2 + rimL * 1.5 + 0.06), 1.0) * cov * in.col.a;
    }
    return float4(in.col.rgb, 1.0) * exp(-r2 * 2.5) * in.col.a;
}

fragment float4 partLightFrag(POut in [[stage_in]], float2 pc [[point_coord]]) {
    float2 uv = pc * 2.0 - 1.0;
    if (dot(uv, uv) > 1.0) discard_fragment();
    return float4(partSource(in, uv).rgb, 1.0);
}

fragment FrontOut partFrag(POut in [[stage_in]], float2 pc [[point_coord]], float4 lin [[color(1)]],
                           constant FrameParams &P [[buffer(0)]], texture2d<float> tEdge [[texture(9)]]) {
    float2 uv = pc * 2.0 - 1.0;
    if (dot(uv, uv) > 1.0) discard_fragment();
    float2 px = in.pos.xy + P.region.xy * P.view.xy;
    return frontFinish(partSource(in, uv), lin.rgb, px, P, tEdge);
}

fragment float4 partLinFrag(POut in [[stage_in]], float2 pc [[point_coord]], float4 dst [[color(0)]],
                            constant FrameParams &P [[buffer(0)]]) {
    float2 uv = pc * 2.0 - 1.0;
    if (dot(uv, uv) > 1.0) discard_fragment();
    float2 px = in.pos.xy + P.region.xy * P.view.xy;
    float4 src = partSource(in, uv);
    src.rgb *= barDarken(px, P);
    return float4(src.rgb + (1.0 - src.a) * dst.rgb, 1.0);
}
"""#
