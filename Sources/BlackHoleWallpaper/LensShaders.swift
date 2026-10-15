// Metal source for the object lenses of stage 4, placed after the ship shaders and before dispFrag.
//
//   holeBend    second hole: the direction a ray leaves in, from the hole's own small ray map (exact Kerr
//               inside its box, the point-lens fall-off 1/b outside, matched at the edge)
//   wormBend    wormhole: bends like a lens outside the throat; inside, the other side
//   lensedDir   the whole chain for one pixel: lenses in front of the hole plane, the hole, lenses behind it
//   lensLayer   what a lens adds on top: the second hole's shadow, photon ring, disk and jet; the other side
//               of a wormhole or a gate, the gates' kawoosh and transit

let lensShaderSource = #"""
// ---------------------------------------------------------------- object lenses

// Rotates v about the unit axis k by ang (Rodrigues).
static float3 rotAxis(float3 v, float3 k, float ang) {
    float c = cos(ang), s = sin(ang);
    return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// Applies the rotation that takes unit a to unit b to v.
static float3 rotTo(float3 a, float3 b, float3 v) {
    float3 k = cross(a, b);
    float s = length(k);
    if (s < 1e-7) return dot(a, b) > 0.0 ? v : -v;
    return rotAxis(v, k / s, atan2(s, dot(a, b)));
}

// Second hole: map coordinates of a pixel. ab: impact parameters (M2) in the hole's frame, rr their length.
static float2 holeMapUV(float2 q, constant LensObj &L, thread float2 &ab, thread float &rr) {
    float2 d = (q - L.a.yz) / L.b.x;
    float2 s = float2(d.x, -d.y);
    float cr = L.c.x, sr = L.c.y;
    ab = float2(cr * s.x + sr * s.y, -sr * s.x + cr * s.y);
    rr = length(ab);
    float rc = L.b.y * 0.98;
    float2 abS = rr > rc ? ab * (rc / rr) : ab;
    return float2(abS.x, -abS.y) / (2.0 * L.b.y) + 0.5;
}

// The map texel holeBend reads at pixel q, without the bend itself (for what the hole shows).
static float4 holeSkyAt(float2 q, constant LensObj &L, texture2d<float> mSky) {
    if (length(q - L.a.yz) > L.reach.z * 1.25) return float4(0.5, 0.5, 0.0, 0.0);
    float2 ab; float rr;
    float2 muv = holeMapUV(q, L, ab, rr);
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float4 sk = mSky.sample(ls, muv);
    if (rr > L.b.y * 0.98) sk.zw = float2(0.0);
    return sk;
}

// Direction a ray through pixel q leaves the second hole in (camera frame). The map holds the ray's turn
// for a camera far away (angle and axis), applied to the pixel's own direction. Outside the map the turn falls off like 1/b from its value at the edge.
static float3 holeBend(float2 q, constant LensObj &L, constant FrameParams &P, texture2d<float> mSky, thread float4 &sk) {
    float2 v = q - L.a.yz;
    float rpx = length(v), rcPx = L.reach.z;
    // Far out the weak-field bend 1/b as a shift on the screen, no map lookup; faded towards the reach.
    float far = L.reach.y * rcPx / max(rpx, 1.0) * (1.0 - smoothstep(0.45 * L.reach.x, L.reach.x, rpx));
    if (rpx > rcPx * 1.25) {
        sk = float4(0.5, 0.5, 0.0, 0.0);
        return dirOfPx(q - v / rpx * far, P);
    }
    float2 ab; float rr;
    float2 muv = holeMapUV(q, L, ab, rr);
    float rc = L.b.y * 0.98;
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    sk = mSky.sample(ls, muv);
    // The map holds the ray's total turn and its axis (traceRay with disk.z = 1).
    float2 axv = sk.xy * 2.0 - 1.0;
    float sn = length(axv);
    float ang = sk.z * 32.0;
    // Outside: 1/b from the edge, faded out towards the lens's reach (beyond it the bend is a few pixels).
    float reachM = L.reach.x / L.b.x;
    if (rr > rc) { ang *= rc / rr * (1.0 - smoothstep(0.45 * reachM, reachM, rr)); sk.zw = float2(0.0); }
    float3 th = dirOfPx(q, P);
    float3 d = th;
    if (sn > 1e-4) {
        axv /= sn;
        float cr = L.c.x, sr = L.c.y;
        d = rotAxis(th, float3(cr * axv.x - sr * axv.y, sr * axv.x + cr * axv.y, 0.0), ang);
    }
    // Between the map's edge and the far field: blend over to the shift.
    if (rpx > rcPx) d = normalize(mix(d, dirOfPx(q - v / rpx * far, P), smoothstep(rcPx, rcPx * 1.25, rpx)));
    return d;
}

// diskFetch for a second hole, whose small map is magnified on the screen. Texels of another image of
// the disk (radius far off) are left out instead of averaged, but still count as cover. split: the texels
// show different images, or the redshift jumps between them (it blows up and flips sign near the horizon).
static float4 holeDiskFetch(texture2d<half> t, float2 uv, thread float &cover, thread bool &split) {
    float2 size = float2(t.get_width(), t.get_height());
    float2 p = uv * size - 0.5;
    float2 f = fract(p);
    int2 i0 = int2(floor(p));
    int2 mx = int2(size) - 1;
    float4 v[4];
    float w[4];
    float rb = 1000.0, wb = -1.0, gb = 1.0;
    for (int k = 0; k < 4; k++) {
        int2 o = int2(k & 1, k >> 1);
        w[k] = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
        v[k] = float4(t.read(uint2(clamp(i0 + o, int2(0), mx))));
        if (v[k].x < 900.0 && w[k] > wb) { wb = w[k]; rb = v[k].x; gb = v[k].w; }
    }
    cover = 0.0;
    split = false;
    if (wb < 0.0) return float4(1000.0, 1.0, 0.0, 1.0);
    float4 acc = 0.0;
    float ws = 0.0;
    for (int k = 0; k < 4; k++) {
        if (v[k].x > 900.0) continue;
        cover += w[k];
        bool same = v[k].x > rb * 0.67 && v[k].x < rb * 1.5;
        if (same) { acc += v[k] * w[k]; ws += w[k]; }
        split = split || !same || abs(v[k].w - gb) > 1.5;
    }
    return acc / ws;
}

// How log r (xy) and cos, sin phi (zw: along x, along y) change per texel within the image holeDiskFetch
// chose. Where images meet, fwidth across them saw a jump and faded a dark line into the disk.
static void holeDiskGrad(texture2d<half> t, float2 uv, thread float4 &g, thread float4 &gyz) {
    float2 size = float2(t.get_width(), t.get_height());
    float2 p = uv * size - 0.5;
    float2 f = fract(p);
    int2 i0 = int2(floor(p));
    int2 mx = int2(size) - 1;
    float4 v[4];
    float rb = 1000.0, wb = -1.0;
    for (int k = 0; k < 4; k++) {
        int2 o = int2(k & 1, k >> 1);
        float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
        v[k] = float4(t.read(uint2(clamp(i0 + o, int2(0), mx))));
        if (v[k].x < 900.0 && w > wb) { wb = w; rb = v[k].x; }
    }
    bool in[4];
    for (int k = 0; k < 4; k++) in[k] = v[k].x < 900.0 && v[k].x > rb * 0.67 && v[k].x < rb * 1.5;
    // Differences along x (texels 0-1, 2-3) and y (0-2, 1-3) where both ends are in this image.
    float3 dx = 0.0, dy = 0.0;
    float nx = 0.0, ny = 0.0;
    for (int k = 0; k < 2; k++) {
        int a = k * 2, b = a + 1;
        if (in[a] && in[b]) { dx += float3(v[b].x - v[a].x, v[b].yz - v[a].yz); nx += 1.0; }
        a = k; b = k + 2;
        if (in[a] && in[b]) { dy += float3(v[b].x - v[a].x, v[b].yz - v[a].yz); ny += 1.0; }
    }
    dx /= max(nx, 1.0); dy /= max(ny, 1.0);
    dx.x /= rb; dy.x /= rb;   // d log r = dr / r
    g = float4(dx.x, dy.x, 0.0, 0.0);
    gyz = float4(dx.yz, dy.yz);
}

// Squeeze (as in dispFrag) and how far r moves per pixel, from the texel differences of holeDiskFetch.
// tx, ty: texels per pixel step along x and y.
static float2 holeSqueeze(float4 h, float4 g, float4 gyz, float2 tx, float2 ty) {
    float lx = abs(g.x * tx.x + g.y * tx.y), ly = abs(g.x * ty.x + g.y * ty.y);
    float2 px = abs(gyz.xy * tx.x + gyz.zw * tx.y) + abs(gyz.xy * ty.x + gyz.zw * ty.y);
    return float2((lx + ly) * 20.0 + length(px) * 2.0, min(h.x, 200.0) * (lx + ly));
}

// Wormhole outside its throat: a point lens with Einstein radius b.y (px).
static float3 wormBend(float2 q, constant LensObj &L, constant FrameParams &P) {
    float3 th = dirOfPx(q, P);
    float r = length(q - L.a.yz);
    float re = L.b.y;
    if (r < L.b.x || re <= 0.0) return th;
    float px = re * re / r * (1.0 - smoothstep(0.5 * L.reach.x, L.reach.x, r));
    float ang = px * P.camA.y / (min(P.view.x, P.view.y) * P.camA.x);
    float3 k = cross(dirOfPx(L.a.yz, P), th);
    float s = length(k);
    return s > 1e-7 ? rotAxis(th, k / s, -ang) : th;
}

static float3 lensBend(constant LensObj &L, float2 q, constant FrameParams &P, texture2d<float> m0, texture2d<float> m1,
                       thread float4 &sk) {
    int type = int(L.a.x + 0.5);
    sk = float4(0.5, 0.5, 0.0, 0.0);
    if (distance(q, L.a.yz) > L.reach.x) return dirOfPx(q, P);
    if (type == 1 && lensFar) {
        // As holeBend beyond 1.25 map radii (the CPU only picks this variant where that holds).
        float2 v = q - L.a.yz;
        float rpx = length(v);
        float far = L.reach.y * L.reach.z / max(rpx, 1.0) * (1.0 - smoothstep(0.45 * L.reach.x, L.reach.x, rpx));
        return dirOfPx(q - v / rpx * far, P);
    }
    if (type == 1) return L.c.w < 0.5 ? holeBend(q, L, P, m0, sk) : holeBend(q, L, P, m1, sk);
    if (type == 2) return wormBend(q, L, P);
    return dirOfPx(q, P);
}

// Lenses in front of the hole plane: direction after them (D) and where the ray meets the hole plane
// (returned, px). A lens right at the plane moves nothing there, one near the camera moves it fully.
static float2 frontChain(float2 px, constant FrameParams &P, constant LensObj *L, texture2d<float> m0, texture2d<float> m1,
                         thread float3 &D, thread float4 *lsk, thread float2 *lq) {
    int n = int(P.lensA.x + 0.5);
    float3 th = dirOfPx(px, P);
    D = th;
    float2 off = float2(0.0);
    bool first = true;
    for (int i = 0; i < 2; i++) {
        if (i >= n) break;
        if (L[i].a.w > 0.5) continue;
        lq[i] = px;
        lsk[i] = float4(0.5, 0.5, 0.0, 0.0);
        if (L[i].a.x > 2.5) continue;   // gates do not bend
        float4 sk;
        float3 d = lensBend(L[i], px, P, m0, m1, sk);
        lsk[i] = sk;
        D = first ? d : rotTo(th, d, D);
        first = false;
        float k = L[i].c.z;
        // As a difference of the same mapping: far out (more than 90 degrees off the hole) dirOfPx is not unit.
        if (k > 0.0) off += dot(normalize(d), normalize(th)) > 0.5 ? k * (pxOfDir(d, P) - pxOfDir(th, P)) : float2(1e6);
    }
    return px + off;
}

// Lenses behind the hole plane: the hole bends the ray first (dir), then they do.
static float3 behindChain(float3 dir, float2 sp, constant FrameParams &P, constant LensObj *L, texture2d<float> m0,
                          texture2d<float> m1, thread float4 *lsk, thread float2 *lq) {
    int n = int(P.lensA.x + 0.5);
    float3 thp = dirOfPx(sp, P);
    for (int i = 0; i < 2; i++) {
        if (i >= n) break;
        if (L[i].a.w < 0.5) continue;
        float3 dL = normalize(mix(thp, dir, L[i].c.z));
        lq[i] = float2(-1e6);
        lsk[i] = float4(0.5, 0.5, 0.0, 0.0);
        if (dL.z < 0.1) continue;
        float2 q = pxOfDir(dL, P);
        float4 sk;
        float3 d = lensBend(L[i], q, P, m0, m1, sk);
        dir = rotTo(dirOfPx(q, P), d, dir);
        lq[i] = q;
        lsk[i] = sk;
    }
    return dir;
}

// The hole's bend (thp -> md) applied to the direction D the lenses in front left the ray in. Small
// bends add like vectors; only near the hole a real rotation is needed.
static float3 holeAfter(float3 thp, float3 md, float3 D) {
    float3 tn = normalize(thp);
    return dot(md, tn) > 0.98 ? normalize(D + md - thp) : rotTo(tn, md, normalize(D));
}

// Can any lens bend this pixel? Those behind the hole plane also wherever the hole images them.
static bool lensNear(float2 px, constant FrameParams &P, constant LensObj *L) {
    int n = int(P.lensA.x + 0.5);
    float2 hc = float2(P.view.w, P.bars.w) * P.view.xy;
    bool near = false;
    for (int i = 0; i < 2; i++) {
        if (i >= n) break;
        near = near || distance(px, L[i].a.yz) < L[i].reach.x || (L[i].a.w > 0.5 && distance(px, hc) < P.camR.w * 4.5);
    }
    return near;
}

static float3 lensedDir(float2 px, constant FrameParams &P, constant LensObj *L, texture2d<float> tSky, texture2d<float> bSky,
                        texture2d<float> m0, texture2d<float> m1, thread float2 &uvMain, thread float4 &skMain) {
    if (!lensNear(px, P, L)) {
        uvMain = px / P.view.xy;
        skMain = skySample(uvMain, P, tSky, bSky);
        return octDecode(skMain.xy);
    }
    float3 D;
    float4 lsk[2];
    float2 lq[2];
    float2 sp = frontChain(px, P, L, m0, m1, D, lsk, lq);
    uvMain = sp / P.view.xy;
    bool off = any(uvMain < 0.0) || any(uvMain > 1.0);
    skMain = off ? float4(octEncode(dirOfPx(sp, P)), 0.0, 0.0) : skySample(uvMain, P, tSky, bSky);
    float3 dir = holeAfter(dirOfPx(sp, P), octDecode(skMain.xy), D);
    return behindChain(dir, sp, P, L, m0, m1, lsk, lq);
}

// ---------------------------------------------------------------- what the lenses add

// Disk of a second hole: diskShade with its own radii, spin, clock and hue.
// dr: how far r moves per pixel. The map is magnified, so the inner edge at the ISCO gets a soft
// edge one pixel wide; hard, it showed the steps of the interpolated map there.
static float3 diskShade2(float4 hv, float squeeze, float dr, constant LensObj &L, constant FrameParams &P,
                         texture2d<float> tex, thread float &alpha) {
    constexpr sampler ps(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    alpha = 0.0;
    float r = hv.x;
    float rIn = L.disk.x, rOut = L.disk.y, a = L.disk.z;
    if (r > rOut || r < 0.8) return float3(0.0);
    float phi = atan2(hv.z, hv.y);
    // Near the horizon rays with 1 + omega L near or below zero make the redshift formula blow up and flip
    // sign. Magnified, those texels sparkled magenta and black and cut hard edges into the plunging gas;
    // such light is left out, the bright rim before it stays.
    float g = clamp(hv.w, 0.0, 6.0);
    float gOk = saturate(hv.w * 50.0) * (1.0 - smoothstep(4.0, 6.0, hv.w));
    float omK = 1.0 / (r * sqrt(r) + a);
    float omI = 1.0 / (rIn * sqrt(rIn) + a);
    float rel = pow(omK / omI, L.dclk.y);
    const float per = 3.0 * M_PI_F;
    float t1 = fmod(L.dclk.x, per), t2 = fmod(L.dclk.x + per * 0.5, per);
    float wgt = abs(t1 / per * 2.0 - 1.0);
    float v = log(r) / log(rOut);
    float4 s1 = tex.sample(ps, float2((phi - rel * t1) * inv2pi, v), level(0.0));
    float4 s2 = tex.sample(ps, float2((phi - rel * t2 + 2.1) * inv2pi, v), level(0.0));
    float4 m = mix(s1, s2, wgt);
    float fade = saturate(squeeze);
    float dens = mix(m.x, 0.45, fade);
    float lanes = mix(m.z, 0.6, fade);
    float x = r / rIn;
    float sx = sqrt(x);
    float out = saturate((r - rIn) / max(dr, 1e-4) + 0.5);
    float prof = mix(exp(-(1.0 - min(x, 1.0)) * 6.0) * 0.25,
                     x > 1.0 ? sqrt(sqrt(1.0 - 1.0 / sx)) / (sx * sqrt(sx)) / 0.488 : 0.0, out);
    float tObs = prof * g;
    float I = g * g * g * prof;
    float3 col = grad5(0.2 + 0.85 * pow(saturate(tObs), 0.7) + (m.y - 0.5) * P.nebp.z, P.pal);
    col = max(hueShift(col, L.dclk.z), 0.0);
    float outer = 1.0 - smoothstep(rOut * 0.35, rOut, r);
    float rH = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    float plunge = mix(0.6 * smoothstep(0.0, 1.0, (r - rH) / max(rIn - rH, 1e-3)), 1.0, out);
    alpha = saturate(dens * 1.2) * outer * plunge * mix(0.35, 1.0, lanes) * gOk;
    float glow = (I * 2.2 + 0.05) * mix(0.25, 1.0, lanes);
    return col * glow * alpha * L.disk.w;
}

static float3 jetLight2(float E, float s, float phase, constant LensObj &L, texture2d<float> noise) {
    if (E * L.jetC.w <= jetFloor) return float3(0.0);
    constexpr sampler es(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float u = s / max(L.jetK.w, 0.01) - phase;
    float kn = saturate(noise.sample(es, float2(u / 256.0, 0.25), level(0.0)).x);
    return L.jetC.rgb * L.jetC.w * E * mix(1.0, 0.3 + 2.4 * kn * kn * kn, L.jetK.x) * smoothstep(jetFloor, 4.0 * jetFloor, E * L.jetC.w);
}

// Colours of the other side: its own cool ramp from deep blue over cyan to white, turned by the hue slider.
static float3 otherRamp(float x, float hue) {
    float3 c = mix(float3(0.03, 0.06, 0.22), float3(0.12, 0.48, 0.95), smoothstep(0.0, 0.55, x));
    c = mix(c, float3(0.85, 0.9, 1.0), smoothstep(0.6, 1.0, x));
    return max(hueShift(c, hue), 0.0);
}

// The sky on the other side. lo: direction in the lens's own frame (z through its middle), blur 0..1
// where the picture gets too fine to resolve (near the rim).
static float3 otherSky(float3 lo, float blur, constant LensObj &L, constant FrameParams &P, texture2d<float> tNeb) {
    int mode = int(L.side.y + 0.5);
    float3x3 R = float3x3(L.rot0.xyz, L.rot1.xyz, L.rot2.xyz);
    float3 o = R * lo;
    if (mode == 1) o = float3(-lo.x, lo.y, -lo.z);   // our own sky, seen from behind
    float3 nc;
    float band = 0.0;
    if (mode == 1) {
        float4 nb = nebulaSample(o, P, tNeb);
        nc = mix(nebulaColour(nb, P), nebulaColour(float4(0.32, 0.5, 0.5, 0.5), P), blur) * max(P.look.z, 0.35);
    } else {
        // Another galaxy's sky: a bright band of gas and dust (its galactic plane), clouds around it,
        // in cool colours. The band is what wraps into rings near the rim.
        float n1 = fbm3(o * 4.5 + 11.0, 4), n2 = fbm3(o * 12.0 + 3.0, 3);
        band = exp(-pow((o.z + 0.12 * (n1 - 0.5)) / 0.17, 2.0));
        float gas = saturate(band * (0.25 + 1.2 * n1 * n1) + 0.22 * pow(n1, 3.0) - 0.02);
        float dust = smoothstep(0.48, 0.7, n2) * band;
        float d = mix(gas * (1.0 - 0.75 * dust), 0.17, blur);
        float h = mix(n2, 0.5, blur);
        nc = otherRamp(saturate(0.1 + d * 0.95 + (h - 0.5) * 0.3), L.side.x) * (0.05 + 1.1 * d * (0.6 + 0.4 * d));
    }
    float3 col = nc * L.jetC.x;
    float t = L.rot0.w;
    float st = (1.0 - smoothstep(0.0, 0.25, blur)) * L.jetC.y * max(P.look.y, 0.4) * (1.0 + band);
    if (st > 0.0) {
        float3 so = mode == 1 ? o : o.yzx;
        col += (starLayer(so, 420.0, 0.93, 0.10, t, P) + starLayer(so, 140.0, 0.98, 0.07, t, P) * 1.6) * st;
    }
    if (mode == 2) {
        // A spiral galaxy straight through the middle, tilted.
        float2 g = lo.xy / max(lo.z, 0.05);
        float ct = 0.5, sa = 0.6, ca = 0.8;
        float2 p = float2(ca * g.x + sa * g.y, (-sa * g.x + ca * g.y) / ct) / 0.22;
        float r = length(p);
        float arms = 0.5 + 0.5 * cos(2.0 * (atan2(p.y, p.x) - log(max(r, 0.02)) / 0.32));
        float body = exp(-r * 2.6) * (0.35 + 0.65 * arms * arms) * (1.0 - smoothstep(1.2, 1.8, r));
        float core = exp(-r * r * 60.0);
        float3 gc = mix(float3(0.62, 0.74, 1.0), float3(1.0, 0.82, 0.6), saturate(1.0 - r * 1.5));
        col += (gc * body * 0.9 + float3(1.0, 0.9, 0.75) * core * 1.6) * L.jetC.x * mix(1.0, 0.5, blur);
    }
    return col;
}

// What one lens shows at pixel q (its own, unlensed position), added to col. sk: its map texel there.
// Second hole: shadow, photon ring, the two disk images, the jet.
static float3 holeLayer(float3 col, constant LensObj &L, float2 q, float4 sk, constant FrameParams &P,
                        texture2d<half> d10, texture2d<half> d20, texture2d<half> jE0, texture2d<half> jS0,
                        texture2d<half> d11, texture2d<half> d21, texture2d<half> jE1, texture2d<half> jS1,
                        texture2d<float> tDisk, texture2d<float> tEdge) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float2 ab; float rr;
    float2 muv = holeMapUV(q, L, ab, rr);
    bool inside = rr < L.b.y * 0.98;
    float cm = inside ? (sk.w - 0.5) * 0.25 : -0.125;   // outside: the map's value far from the shadow, no step at its edge
    float cap = saturate(0.5 + cm / max(fwidth(cm), 1e-6));
    float4 h1 = float4(1000.0, 1.0, 0.0, 1.0), h2 = h1;
    float c1 = 0.0, c2 = 0.0;
    float2 je = float2(0.0), js = float2(0.0);
    bool s1 = L.c.w > 0.5;
    bool sp1 = false, sp2 = false;
    if (inside && L.disk.y > 0.0) {
        h1 = s1 ? holeDiskFetch(d11, muv, c1, sp1) : holeDiskFetch(d10, muv, c1, sp1);
        h2 = s1 ? holeDiskFetch(d21, muv, c2, sp2) : holeDiskFetch(d20, muv, c2, sp2);
    }
    if (inside && L.jetC.w > 0.0) {
        je = float2(s1 ? jE1.sample(ls, muv).xy : jE0.sample(ls, muv).xy);
        js = float2(s1 ? jS1.sample(ls, muv).xy : jS0.sample(ls, muv).xy);
    }
    float msz = float(s1 ? d11.get_width() : d10.get_width());
    float sq1 = fwidth(log(clamp(h1.x, 0.5, 200.0))) * 20.0 + length(fwidth(h1.yz)) * 2.0;
    float sq2 = fwidth(log(clamp(h2.x, 0.5, 200.0))) * 20.0 + length(fwidth(h2.yz)) * 2.0;
    float dr1 = fwidth(min(h1.x, 200.0)), dr2 = fwidth(min(h2.x, 200.0));
    if (quad_any(sp1 || sp2)) {
        // Some pixel of this quad sits where images meet: measure within each image instead.
        float2 tpx = dfdx(muv) * msz, tpy = dfdy(muv) * msz;
        float4 g1 = 0.0, g2 = 0.0, y1 = 0.0, y2 = 0.0;
        if (c1 > 0.0) { if (s1) holeDiskGrad(d11, muv, g1, y1); else holeDiskGrad(d10, muv, g1, y1); }
        if (c2 > 0.0) { if (s1) holeDiskGrad(d21, muv, g2, y2); else holeDiskGrad(d20, muv, g2, y2); }
        float2 q1 = holeSqueeze(h1, g1, y1, tpx, tpy), q2 = holeSqueeze(h2, g2, y2, tpx, tpy);
        sq1 = q1.x; sq2 = q2.x; dr1 = q1.y; dr2 = q2.y;
    }
    // The photon ring from the ray's turn (the map's winding counts the long way in from its far camera).
    float wind = inside ? M_PI_F + sk.z * 32.0 : 0.0;
    col += hueShift(grad5(0.88, P.pal), L.dclk.z) * smoothstep(4.2, 7.0, wind) * P.look.w * 0.6 * L.dclk.w;
    col *= 1.0 - cap;
    col += jetLight2(je.y, js.y, L.jetK.z, L, tEdge);
    float a1, a2;
    // Where an image of the disk moves from one crossing to the other (the near disk's rim ends in front of
    // the far image) or the redshift jumps, the four texels show different stacks: composite each texel's
    // stack on its own and blend the colours. Blending the crossings separately left a dark line there.
    bool split = sp1 || sp2;
    float2 tp = muv * msz - 0.5;
    float2 tf = fract(tp);
    int2 t0 = int2(floor(tp));
    float3 base = col;
    col = split ? float3(0.0) : col;
    for (int k = 0; k < (split ? 4 : 1); k++) {
        float4 v1 = h1, v2 = h2;
        float k1 = c1, k2 = c2, w = 1.0;
        if (split) {
            int2 o = int2(k & 1, k >> 1);
            w = (o.x == 1 ? tf.x : 1.0 - tf.x) * (o.y == 1 ? tf.y : 1.0 - tf.y);
            uint2 q = uint2(clamp(t0 + o, int2(0), int2(msz) - 1));
            v1 = float4(s1 ? d11.read(q) : d10.read(q));
            v2 = float4(s1 ? d21.read(q) : d20.read(q));
            k1 = v1.x < 900.0 ? 1.0 : 0.0;
            k2 = v2.x < 900.0 ? 1.0 : 0.0;
        }
        float3 c = base;
        if (k2 > 0.0) { float3 e2 = diskShade2(v2, sq2, dr2, L, P, tDisk, a2) * k2; c = e2 + (1.0 - a2 * k2) * c; }
        if (k1 > 0.0) { float3 e1 = diskShade2(v1, sq1, dr1, L, P, tDisk, a1) * k1; c = e1 + (1.0 - a1 * k1) * c; }
        col = split ? col + c * w : c;
    }
    col += jetLight2(je.x, js.x, L.jetK.y, L, tEdge);
    return col;
}

// Wormhole: the throat looks like a ball with the other side inside.
static float3 wormLayer(float3 col, constant LensObj &L, float2 q, constant FrameParams &P, texture2d<float> tNeb) {
    float t = L.rot0.w;
    float2 v = q - L.a.yz;
    // Wormhole: the throat looks like a ball. Inside, the other side, squeezed towards the rim
    // where it wraps around several times (like the wormhole in Interstellar).
    float R = L.b.x;
    float r = length(v);
    float x = r / R;
    float cov = saturate((R - r) / max(fwidth(r), 1e-3) + 0.5);
    float xc = min(x, 0.9995);
    float rip = L.side.w * 0.035 * sin(xc * 17.0 - t * 1.7 + 2.0 * sin(atan2(v.y, v.x) * 3.0 + t * 0.6));
    float psi = 0.55 * xc / sqrt(1.0 - xc * xc + 0.012) * (1.0 + rip);
    float blur = smoothstep(0.03, 0.25, fwidth(psi));
    float3 lo = float3(sin(psi) * normalize(float2(v.x, -v.y) + 1e-6), cos(psi));
    if (cov > 0.0) col = mix(col, otherSky(lo, blur, L, P, tNeb), cov);
    float3 rc = otherRamp(0.75, L.side.x);
    col += rc * L.side.z * (exp(-pow((x - 1.0) / 0.012, 2.0)) + 0.2 * exp(-max(x - 1.0, 0.0) * 18.0) * step(1.0, x)) * 0.5;
    return col;
}

static float3 gateLayer(float3 col, constant LensObj &L, float2 q, constant FrameParams &P, texture2d<float> tNeb) {
    float t = L.rot0.w;
    float2 v = q - L.a.yz;
    // Gate: the ring's inside shows the other side; a flat portal, bent only a little.
    float2x2 M = float2x2(float2(L.b.x, L.b.z), float2(L.b.y, L.b.w));
    float2 e = M * v;
    float rho = length(e);
    float cov = saturate((1.0 - rho) / max(fwidth(rho), 1e-3) + 0.5);
    int ev = int(L.dclk.x + 0.5);
    float p = L.dclk.y;
    float open = 1.0;
    float3 add = float3(0.0);
    float3 wc = float3(0.55, 0.78, 1.0);
    if (ev == 9) {
        // Kawoosh: the window closes for a moment, a bright plume bursts out towards you and falls back,
        // then the surface settles and the other side shows again.
        open = 1.0 - smoothstep(0.0, 0.05, p) + smoothstep(0.42, 0.8, p);
        float2 N = L.jetC.zw;
        float Lh = 1.5 * pow(sin(M_PI_F * saturate((p - 0.07) / 0.42)), 0.7);
        float dens = 0.0;
        if (Lh > 0.01) {
            float jit = hash12(q);
            for (int k = 0; k < 14; k++) {
                float h = (float(k) + jit) / 14.0 * Lh;
                float2 ee = M * (v - N * h);
                float prof = sqrt(max(1.0 - (h / Lh) * (h / Lh), 0.0)) * (0.95 - 0.25 * h / max(Lh, 0.01));
                float rr = length(ee);
                float n = vnoise3(float3(ee * 3.0, h * 2.0 - p * 9.0 + L.dclk.z));
                dens += smoothstep(prof, prof * 0.6, rr) * (0.3 + 0.9 * n * n);
            }
            dens /= 14.0;
        }
        float flash = exp(-pow((p - 0.08) / 0.05, 2.0));
        float settle = smoothstep(0.35, 0.6, p) * (1.0 - smoothstep(0.6, 1.0, p));
        float wave = 0.5 + 0.5 * sin(rho * 26.0 - p * 30.0);
        float swirl = 0.5 + 0.5 * sin(atan2(e.y, e.x) * 3.0 + rho * 9.0 - p * 20.0);
        add = wc * (dens * 0.8 + flash * 0.45 * cov * (0.6 + 0.4 * swirl) + settle * wave * wave * 0.08 * cov)
            + float3(0.9, 0.95, 1.0) * flash * 0.15 * cov;
    } else if (ev == 10) {
        // Transit: something passes through; a flash and a ring running out over the surface.
        float2 c0 = float2(fract(L.dclk.z * 0.37) - 0.5, fract(L.dclk.z * 0.71) - 0.5) * 0.7;
        float d = length(e - c0);
        float flash = exp(-pow((p - 0.32) / 0.07, 2.0));
        float rr = max(p - 0.3, 0.0) * 2.2;
        float ring = exp(-pow((d - rr) / 0.035, 2.0)) * step(0.3, p) * (1.0 - smoothstep(0.5, 1.0, p));
        add = (wc * (ring * 0.22 + flash * exp(-d * d * 30.0) * 0.8) + float3(1.0) * flash * exp(-d * d * 120.0) * 0.4) * cov;
    }
    float psi = 0.42 * rho * (1.0 + 0.25 * rho * rho) * (1.0 + L.side.w * 0.03 * sin(rho * 20.0 - t * 2.0));
    float blur = smoothstep(0.03, 0.25, fwidth(psi));
    float3 lo = float3(sin(psi) * normalize(float2(e.x, -e.y) + 1e-6), cos(psi));
    if (cov > 0.0 && open > 0.0) col = mix(col, otherSky(lo, blur, L, P, tNeb), cov * saturate(open));
    return col + add;
}

// Lenses in front of the hole plane: their own light over the finished picture, one quad per lens over
// what it shows. Reads the linear colour of the pixel (programmable blending) like path F.
struct LensVOut {
    float4 pos [[position]];
    float2 px;
    uint inst [[flat]];
};

vertex LensVOut lensVert(uint vid [[vertex_id]], uint iid [[instance_id]], constant FrameParams &P [[buffer(0)]],
                         constant LensObj *lenses [[buffer(3)]]) {
    LensVOut o;
    constant LensObj &L = lenses[iid];
    float4 r = L.a.w > 0.5 ? float4(0.0) : L.rect;   // behind the hole plane: drawn inside dispFrag
    float2 px = mix(r.xy, r.zw, quadCorner[vid]);
    o.pos = regionPos(px, P);
    o.px = px;
    o.inst = iid;
    return o;
}

static float3 lensFront(float3 col, LensVOut in, constant FrameParams &P, constant LensObj *lenses,
                        texture2d<float> m0, texture2d<float> m1,
                        texture2d<half> d10, texture2d<half> d20, texture2d<half> jE0, texture2d<half> jS0,
                        texture2d<half> d11, texture2d<half> d21, texture2d<half> jE1, texture2d<half> jS1,
                        texture2d<float> tDisk, texture2d<float> tNeb, texture2d<float> tEdge) {
    constant LensObj &L = lenses[in.inst];
    float ms;
    float2 q = lensed(in.px, P, ms);   // the mouse lens sits at the hole: it bends what is behind it too
    int type = int(L.a.x + 0.5);
    if (type == 1) {
        float4 sk = L.c.w > 0.5 ? holeSkyAt(q, L, m1) : holeSkyAt(q, L, m0);
        return holeLayer(col, L, q, sk, P, d10, d20, jE0, jS0, d11, d21, jE1, jS1, tDisk, tEdge);
    }
    if (type == 2) return wormLayer(col, L, q, P, tNeb);
    return gateLayer(col, L, q, P, tNeb);
}

fragment FrontOut lensFrontFrag(LensVOut in [[stage_in]], float4 lin [[color(1)]], constant FrameParams &P [[buffer(0)]],
                                constant LensObj *lenses [[buffer(3)]],
                                texture2d<float> tDisk [[texture(3)]], texture2d<float> tNeb [[texture(4)]],
                                texture2d<float> tEdge [[texture(9)]],
                                texture2d<float> m0 [[texture(20)]], texture2d<half> d10 [[texture(21)]], texture2d<half> d20 [[texture(22)]],
                                texture2d<half> jE0 [[texture(23)]], texture2d<half> jS0 [[texture(24)]],
                                texture2d<float> m1 [[texture(25)]], texture2d<half> d11 [[texture(26)]], texture2d<half> d21 [[texture(27)]],
                                texture2d<half> jE1 [[texture(28)]], texture2d<half> jS1 [[texture(29)]]) {
    float3 col = lensFront(lin.rgb, in, P, lenses, m0, m1, d10, d20, jE0, jS0, d11, d21, jE1, jS1, tDisk, tNeb, tEdge);
    return frontFinish(float4(0.0), col, in.px, P, tEdge);
}

// Over a linear target (the still under the strips of edges-only mode).
fragment float4 lensLinFrag(LensVOut in [[stage_in]], float4 dst [[color(0)]], constant FrameParams &P [[buffer(0)]],
                            constant LensObj *lenses [[buffer(3)]],
                            texture2d<float> tDisk [[texture(3)]], texture2d<float> tNeb [[texture(4)]],
                            texture2d<float> tEdge [[texture(9)]],
                            texture2d<float> m0 [[texture(20)]], texture2d<half> d10 [[texture(21)]], texture2d<half> d20 [[texture(22)]],
                            texture2d<half> jE0 [[texture(23)]], texture2d<half> jS0 [[texture(24)]],
                            texture2d<float> m1 [[texture(25)]], texture2d<half> d11 [[texture(26)]], texture2d<half> d21 [[texture(27)]],
                            texture2d<half> jE1 [[texture(28)]], texture2d<half> jS1 [[texture(29)]]) {
    return float4(lensFront(dst.rgb, in, P, lenses, m0, m1, d10, d20, jE0, jS0, d11, d21, jE1, jS1, tDisk, tNeb, tEdge), 1.0);
}
"""#
