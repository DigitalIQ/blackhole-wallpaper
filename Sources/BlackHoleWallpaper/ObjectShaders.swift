// Metal source for the objects around the hole, placed between the shared helpers
// (noise, FrameParams, blackbody) and dispFrag in Shaders.swift.
//
//   skyObjects  path S: far objects looked up through the cached escape direction, so
//               they get the exact Kerr lensing (Einstein ring, second image) for free.
//   jetLight    per-frame colour, knots and pulse of the jet emission traced in geoFragJet.
//   bakeGalaxy  one galaxy into one tile of the galaxy atlas, as a small volume model.

let objectShaderSource = #"""
// ---------------------------------------------------------------- objects

struct SkyObj {
    float4 pos;   // centre direction (camera frame, unit), cos of the reach
    float4 ax;    // tangent u (unit), kind: 0 star, 1 galaxy, 2 pulsar, 3 nebula shell
    float4 col;   // linear rgb * brightness, core radius (rad)
    float4 tile;  // galaxy: atlas rect. star: glow, reach (rad), 0, 0. pulsar: cone direction (cos, sin), tan half width, cone glow. shell: radius, width (rad), seed, glow
    float4 ext;   // galaxy: radius (rad), tile size px, core brightness, core radius (rad). pulsar: beam north, beam south, glow, reach (rad)
};

// Sky objects only cost where they can be seen: a pass at 1/8 resolution marks, per cell,
// which objects can reach it (one bit each), from the spread of sky directions in the cell.
// nebFrag copies "any bit set" into its alpha, so most pixels skip the mask read entirely.

// With object lenses (stage 4) each sample goes through the whole lens chain.
static float3 maskDir(float2 uv, constant FrameParams &P, texture2d<float> tSky, texture2d<float> bSky,
                      constant LensObj *L, texture2d<float> m0, texture2d<float> m1) {
    if (!withLenses) return octDecode(skySample(uv, P, tSky, bSky).xy);
    float2 um; float4 sk;
    return lensedDir(uv * P.view.xy, P, L, tSky, bSky, m0, m1, um, sk);
}

fragment uint skyMaskFrag(VOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                          texture2d<float> tSky [[texture(0)]], texture2d<float> bSky [[texture(5)]],
                          texture2d<float> mSky0 [[texture(20)]], texture2d<float> mSky1 [[texture(25)]],
                          constant SkyObj *o [[buffer(1)]], constant LensObj *lenses [[buffer(3)]]) {
    float2 cell = float2(maskCell) / P.view.xy;
    float2 uv = (floor(in.pos.xy) + 0.5) * cell;
    float3 dc = maskDir(uv, P, tSky, bSky, lenses, mSky0, mSky1);
    float rad = 0.0;
    for (int k = 0; k < 4; k++) {
        float2 off = float2((k & 1) ? 0.5 : -0.5, (k & 2) ? 0.5 : -0.5) * cell;
        float3 d = maskDir(uv + off, P, tSky, bSky, lenses, mSky0, mSky1);
        rad = max(rad, acos(clamp(dot(d, dc), -1.0, 1.0)));
    }
    rad = rad * 1.5 + P.objA.w * float(maskCell) + P.objA.y;
    uint m = 0u;
    int n = int(P.objA.x + 0.5);
    for (int i = 0; i < n; i++) {
        float a = acos(clamp(dot(dc, o[i].pos.xyz), -1.0, 1.0));
        if (a < acos(clamp(o[i].pos.w, -1.0, 1.0)) + rad) m |= 1u << uint(i);
    }
    return m;
}

// dirX, dirY: change of the sky direction per screen pixel (lensing included), for filtering.
// A star's glow belongs to the camera, not to the sky: it is measured in screen pixels around
// each image (sky offset mapped back through the local Jacobian of the lens, taken over ten
// pixels so it stays smooth), so a star behind the hole gives two glowing images, no ring.
// part: 0 everything, 1 only the soft light (galaxy bodies, nebula shells: nebFrag at half resolution),
// 2 only the sharp light (stars, pulsars, galaxy cores: dispFrag).
static float3 skyObjects(float3 dir, float3 dirX, float3 dirY, float2 uv, float wind, uint mask, constant FrameParams &P,
                         constant SkyObj *o, texture2d<float> tGal, texture2d<float> tSky, texture2d<float> bSky, int part = 0) {
    float srcAng = max(length(dirX), length(dirY));
    bool haveJ = false;
    float3 jx = dirX, jy = dirY;
    constexpr sampler gs(filter::linear, mip_filter::linear, address::clamp_to_zero);
    float3 sum = float3(0.0);
    float pxA = P.objA.w;
    while (mask != 0u) {
        int i = int(ctz(mask));
        mask &= mask - 1u;
        float3 c0 = o[i].pos.xyz;
        float cd = dot(dir, c0);
        if (cd < o[i].pos.w) continue;
        float3 u = o[i].ax.xyz;
        float3 v = cross(c0, u);
        float2 q = float2(dot(dir, u), dot(dir, v)) / max(cd, 1e-4);   // tangent plane, rad
        int kind = int(o[i].ax.w + 0.5);
        float3 c = o[i].col.rgb;
        float r2 = dot(q, q);
        bool soft = kind == 1 || kind == 3;
        if (part == 1 && !soft) continue;
        if (part == 2 && kind == 3) continue;
        if (kind == 1) {
            float R = o[i].ext.x;
            float2 t = q / R * 0.5 + 0.5;
            if (part != 2 && all(t > 0.0) && all(t < 1.0)) {
                float lod = log2(max(srcAng * o[i].ext.y / (2.0 * R), 1e-6));
                float3 g = tGal.sample(gs, mix(o[i].tile.xy, o[i].tile.zw, t), level(max(lod, 0.0))).rgb;
                sum += c * g * g * 4.0;
            }
            float cr = max(o[i].ext.w, pxA * 0.8);
            float core = o[i].ext.z;
            if (part != 1) sum += c * core * (exp(-2.0 * r2 / (cr * cr)) + 0.06 * exp(-sqrt(r2) / (cr * 4.0)));
        } else if (kind == 3) {
            float Rs = o[i].tile.x, ws = o[i].tile.y;
            float r = sqrt(r2);
            float2 qs = q / Rs;
            float nz = fbm3(float3(qs * 3.0, o[i].tile.z), 3);
            float nh = fbm3(float3(qs * 1.7 + 4.0, o[i].tile.z + 2.0), 2);
            float rr = (r - Rs * (0.85 + 0.3 * nz)) / ws;
            float shell = exp(-rr * rr);
            float3 hc = mix(float3(1.0, 0.30, 0.42), float3(0.25, 0.78, 0.85), smoothstep(0.38, 0.62, nh));
            float fill = 0.10 * (1.0 - smoothstep(0.0, Rs * 1.1, r)) * nz;
            sum += hc * o[i].tile.w * (shell * (0.25 + 1.6 * nz * nz) + fill) * 0.35;
        } else {
            // The star's core. Its camera glow and spikes are drawn in path F at each image.
            float rho = max(o[i].col.w, pxA * 0.75);
            float core = exp(-2.0 * r2 / (rho * rho));
            sum += c * core;
            if (kind == 2) {
                // Lighthouse beams as two faint wedges in the sky plane, measured in screen pixels
                // around the image (sky offset mapped back through the local Jacobian of the lens).
                float reach = o[i].ext.w;
                if (!haveJ) {
                    float2 st = 5.0 / P.view.xy;
                    jx = (octDecode(skySample(uv + float2(st.x, 0.0), P, tSky, bSky).xy)
                        - octDecode(skySample(uv - float2(st.x, 0.0), P, tSky, bSky).xy)) * 0.1;
                    jy = (octDecode(skySample(uv + float2(0.0, st.y), P, tSky, bSky).xy)
                        - octDecode(skySample(uv - float2(0.0, st.y), P, tSky, bSky).xy)) * 0.1;
                    haveJ = true;
                }
                float2x2 J = float2x2(float2(dot(jx, u), dot(jx, v)), float2(dot(jy, u), dot(jy, v))) / max(cd, 1e-4);
                float det = J[0][0] * J[1][1] - J[1][0] * J[0][1];
                float2 sq = abs(det) > 1e-14 ? float2(J[1][1] * q.x - J[1][0] * q.y, -J[0][1] * q.x + J[0][0] * q.y) / det * pxA
                                             : float2(1e3);
                sq.y = -sq.y;   // screen y runs down, the tangent plane's up
                float rs = length(sq);
                float mu = min(pxA * pxA / max(abs(det), 1e-16), 3.0);
                float edge = 1.0 - smoothstep(0.2 * reach, reach, rs);
                edge *= edge;
                float2 e = o[i].tile.xy;
                float tw = o[i].tile.z, len = reach * 0.4;
                float along = dot(sq, e);
                float perp = abs(sq.x * e.y - sq.y * e.x);
                float a = abs(along);
                float wdt = a * tw + rho;
                float beam = along > 0.0 ? o[i].ext.x : o[i].ext.y;
                float wedge = exp(-perp * perp / (wdt * wdt)) * exp(-a / len) * (1.0 - exp(-a / (rho * 2.0)));
                sum += c * o[i].tile.w * beam * wedge * 0.35 * edge * mu;
            }
        }
    }
    return sum * (1.0 - smoothstep(4.0, 6.0, wind));
}

// Jet light of one layer: E = traced emission, s = its mean position along the jet (0 base, 1 end).
static float jetKnots(float s, float phase, float lateral, constant FrameParams &P, texture2d<float> noise) {
    constexpr sampler es(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float u = s / max(P.jetK.w, 0.01) - phase;
    float n = noise.sample(es, float2(u / 256.0, 0.25), level(0.0)).x;
    // A little sideways structure, so a jet seen along its axis shows blobs, not rings.
    float side = noise.sample(es, float2((u * 0.7 + lateral * 1.9) / 256.0, 0.75), level(0.0)).x;
    float kn = saturate(n * mix(0.7, 1.3, side));
    return mix(1.0, 0.3 + 2.4 * kn * kn * kn, P.jetK.x);
}

// Jet light of one layer: E = traced emission, s = its mean position along the jet (0 base, 1 end).
static float3 jetLight(float E, float s, float phase, float lateral, constant FrameParams &P, texture2d<float> noise) {
    if (E * P.jetC.w <= jetFloor) return float3(0.0);
    constexpr sampler es(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float knot = jetKnots(s, phase, lateral, P, noise);
    // Fine streaks along the axis (the jet stands upright on screen), drifting slowly outwards. The
    // finest octave of the noise is a quarter unit: at 4 units per lateral unit it is about S / 144 wide
    // (10 px on a 1440 px screen). At 14 it was 2 to 3 px and showed as pixel-wide columns.
    float fil = noise.sample(es, float2((lateral * 4.0 + 61.0 + s * 0.8) / 256.0, 0.75), level(0.0)).x;
    float streaks = mix(1.0, 0.45 + 1.1 * fil, P.jetP.z);
    float pulse = 1.0 + P.jetP.x * sin(6.2831853 * (P.jetP.y - s * 1.5));
    // Rises from zero at the floor instead of jumping: a hard cut left a faint edge on a dark sky.
    float soft = smoothstep(jetFloor, 4.0 * jetFloor, E * P.jetC.w);
    return P.jetC.rgb * P.jetC.w * E * knot * streaks * max(pulse, 0.0) * soft;
}

// ---------------------------------------------------------------- galaxy bake

struct GalBake {
    float4 a;   // type, seed, arms, winding
    float4 b;   // bar, bulge, unused, dust
    float4 c;   // star forming, young mix, tilt (rad), flatten
    float4 d;   // small jets (quasar), pair: type of galaxy A, type of galaxy B (subtype codes), unused
};

constant float3 galOld = float3(1.0, 0.74, 0.50);
constant float3 galYoung = float3(0.60, 0.74, 1.0);
constant float3 galHII = float3(1.0, 0.40, 0.62);

// Spiral pattern 0..1 at a point of the disk plane.
static float galArms(float2 p, float arms, float pitchT, float r0, float seed, float shift) {
    float R = max(length(p), 1e-3);
    float th = atan2(p.y, p.x);
    float n = fbm3(float3(p * 4.0, seed), 3);
    float ph = arms * (th - log(max(R, r0 * 0.5) / r0) / pitchT) + 3.0 * (n - 0.5) + shift;
    return 0.5 + 0.5 * cos(ph);
}

// Emission (rgb) and dust (w) density of a disk galaxy at a point of its own frame.
// type 0 spiral, 1 barred, 2 edge-on, 4 lenticular, 5 irregular, 6 ring (in a pair: the member's type).
static float4 galDisk(float3 x, constant GalBake &G, float seed, int type) {
    float arms = G.a.z, wind = G.a.w;
    // A barred member of a pair has no slider of its own: a clear bar.
    float bar = int(G.a.x + 0.5) == 7 ? 0.7 : G.b.x, dust = G.b.w;
    float sf = G.c.x, young = G.c.y;
    const float hz = 0.03, hd = 0.014, hR = 0.24;
    float R = length(x.xy);
    float vz = 1.0 / cosh(x.z / hz); vz *= vz;
    float vd = 1.0 / cosh(x.z / hd); vd *= vd;
    float outer = 1.0 - smoothstep(0.62, 0.95, R);
    float pitchT = tan(mix(0.55, 0.14, saturate(wind / 1.5)));
    float barLen = type == 1 ? 0.12 + 0.28 * bar : 0.1;

    float smoothD = exp(-R / hR) * outer;
    float armV = 1.0, armDust = 0.0, knots = 0.0;
    if (type <= 2 || type == 4) {
        float a = galArms(x.xy, arms, pitchT, barLen, seed, 0.0);
        float ad = galArms(x.xy, arms, pitchT, barLen, seed, 0.55);
        float inside = smoothstep(barLen * 0.6, barLen * 1.3, R);
        float a3 = a * a * a;
        armV = type == 4 ? 1.0 : mix(1.0, 0.25 + 2.6 * a3, inside);
        armDust = type == 4 ? 0.3 * smoothstep(0.25, 0.4, R) * (1.0 - smoothstep(0.4, 0.55, R)) : ad * ad * ad * ad * inside;
        float kn = vnoise3(float3(x.xy * 30.0, seed + 5.0));
        knots = type == 4 ? 0.0 : smoothstep(0.66, 0.9, kn) * a3 * inside * smoothstep(0.1, 0.25, R) * exp(-R / 0.4) * outer;
    } else if (type == 5) {
        float2 w = float2(fbm3(float3(x.xy * 2.0, seed), 3), fbm3(float3(x.xy * 2.0 + 7.0, seed), 3)) - 0.5;
        float Rw = length(x.xy + w * 0.5);
        smoothD = exp(-Rw / 0.2) * (1.0 - smoothstep(0.45, 0.85, Rw));
        float cl = fbm3(float3(x.xy * 6.0, seed + 3.0), 4);
        armV = 0.3 + 2.2 * smoothstep(0.35, 0.7, cl);
        armDust = smoothstep(0.5, 0.7, fbm3(float3(x.xy * 5.0, seed + 9.0), 3));
        knots = smoothstep(0.62, 0.88, vnoise3(float3(x.xy * 26.0, seed + 5.0))) * smoothstep(0.4, 0.65, cl) * smoothD * 3.0;
    } else if (type == 6) {
        float n = fbm3(float3(x.xy * 6.0, seed), 3);
        float rr = (R - 0.62 - 0.05 * (n - 0.5)) / 0.065;
        float ring = exp(-rr * rr);
        smoothD = ring * outer * 0.35 + 0.03 * exp(-R / 0.3);
        armV = 0.5 + 1.4 * n;
        knots = smoothstep(0.6, 0.85, vnoise3(float3(x.xy * 34.0, seed + 5.0))) * ring * 0.8;
        armDust = 0.2 * ring;
    }
    float3 col = smoothD * vz * (galOld * mix(1.2, 0.35, young) + galYoung * mix(0.25, 1.3, young) * (armV - 0.25));
    if (type == 1) {
        float bi = bar * exp(-pow(abs(x.x) / barLen, 3.0) - (x.y * x.y) / (barLen * barLen * 0.06));
        col += galOld * bi * vz * 1.4;
    }
    float hii = vnoise3(float3(x.xy * 21.0, seed + 11.0));
    col += knots * vz * sf * mix(galYoung * 1.6, galHII * 1.8, smoothstep(0.45, 0.6, hii));
    float kappa = dust * 26.0 * vd * exp(-R / (hR * 1.25)) * outer * (0.3 + 1.6 * armDust);
    return float4(col * (0.28 / (2.0 * hz)), kappa);
}

// Projected bulge or elliptical light (Sersic), already integrated along the line of sight.
static float galBulge(float2 X, float re, float q, float n) {
    float m = sqrt(X.x * X.x + (X.y / q) * (X.y / q) + 0.0004);
    float k = 2.0 * n - 0.33;
    float I = exp(-k * (pow(m / re, 1.0 / n) - pow(0.02 / re, 1.0 / n)));
    return I * (1.0 - smoothstep(0.55, 1.0, m));
}

// One disk galaxy seen at tilt i: march through its disk with dust, plus its bulge.
static float3 galRender(float2 X, constant GalBake &G, float tilt, float seed, float bulgeAmt, int type) {
    float si = sin(tilt), ci = cos(tilt);
    float rr = 1.1 * 1.1 - dot(X, X);
    float3 col = float3(0.0);
    float3 tau = float3(0.0);
    if (rr > 0.0) {
        float sM = sqrt(rr);
        float s0 = -sM, s1 = sM;
        const float Z = 0.2;
        if (ci > 1e-3) {
            float a = (-Z - X.y * si) / ci, b = (Z - X.y * si) / ci;
            s0 = max(s0, min(a, b)); s1 = min(s1, max(a, b));
        } else if (abs(X.y * si) > Z) { s1 = s0; }
        const int N = 48;
        float ds = (s1 - s0) / float(N);
        if (ds > 0.0) {
            const float3 redden = float3(1.25, 1.0, 0.8);
            for (int i = 0; i < N; i++) {
                float s = s0 + (float(i) + 0.5) * ds;   // s grows away from the viewer
                float3 x = float3(X.x, X.y * ci - s * si, X.y * si + s * ci);
                float4 e = galDisk(x, G, seed, type);
                float3 dt = e.w * ds * redden;
                col += e.rgb * ds * exp(-tau - dt * 0.5);
                tau += dt;
            }
        }
    }
    float qp = sqrt(ci * ci + 0.45 * 0.45 * si * si);
    float b = galBulge(X, 0.05 + 0.12 * bulgeAmt, qp, 2.0) * (0.15 + 0.8 * bulgeAmt);
    float3 bulge = galOld * float3(1.0, 0.95, 0.9) * b;
    col += bulge * (0.5 * exp(-tau * 0.5) + 0.5 * exp(-tau));
    return col;
}

// One member of an interacting pair, in its own frame: 0 spiral, 1 barred, 3 elliptical, 4 lenticular,
// 5 irregular, 6 ring. The same models as the single galaxies.
static float3 galMember(float2 X, constant GalBake &G, int type, float tilt, float seed, float bulgeAmt) {
    if (type == 3) {
        float n = fbm3(float3(X * 3.0, seed), 2);
        return galOld * float3(1.0, 0.93, 0.85) * galBulge(X, 0.3, 0.8, 3.0) * 1.1 * (0.9 + 0.2 * n);
    }
    float3 col = galRender(X, G, tilt, seed, type == 6 ? 0.0 : bulgeAmt, type);
    if (type == 6) col += galOld * galBulge(X, 0.08, 0.9, 3.0) * (0.3 + 0.8 * G.b.y);
    return col;
}

// How the tidal tail of a pair member looks: colour, width factor, how fast it fades, how clumpy it is.
// Disks (spiral, barred, ring) throw long thin tails; an elliptical has no arms to pull out, only a broad,
// short stream of old stars; a lenticular a smooth, reddish tail; an irregular a blue, knotty one.
static float3 galTailStyle(int type, thread float &wide, thread float &fade, thread float &clump) {
    wide = 1.0; fade = 1.0; clump = 0.0;
    if (type == 3) { wide = 2.2; fade = 0.0; return galOld * 0.11; }
    if (type == 4) { wide = 1.3; return galYoung * 0.03 + galOld * 0.08; }
    if (type == 5) { clump = 1.0; return galYoung * 0.17 + galHII * 0.04; }
    return galYoung * 0.1 + galOld * 0.05;
}

// Shells around an elliptical that swallowed a companion: faint arcs on alternate sides.
static float galShells(float2 X, float2 away) {
    float r = length(X);
    float2 dir = X / max(r, 1e-4);
    float s = 0.0;
    for (int k = 0; k < 3; k++) {
        float rk = 0.5 + 0.2 * float(k);
        float side = (k & 1) ? -1.0 : 1.0;
        float arc = smoothstep(0.3, 0.9, dot(dir, away) * side);
        float d = (r - rk) / 0.04;
        s += exp(-d * d) * arc * (1.0 - 0.25 * float(k));
    }
    return s;
}

fragment float4 bakeGalaxy(VOut in [[stage_in]], constant GalBake &G [[buffer(0)]]) {
    float2 X = (in.uv * 2.0 - 1.0) * float2(1.0, -1.0);
    int type = int(G.a.x + 0.5);
    float seed = G.a.y;
    float tilt = G.c.z;
    float3 col = float3(0.0);
    if (type == 3) {
        float q = 1.0 - G.c.w;
        float n = fbm3(float3(X * 3.0, seed), 2);
        col = galOld * float3(1.0, 0.93, 0.85) * galBulge(X, 0.34, q, 3.0) * 0.9 * (0.9 + 0.2 * n);
    } else if (type == 7) {
        // Two galaxies of any type with a tidal bridge and tails. Default: two spirals.
        int ta = int(G.d.y + 0.5), tb = int(G.d.z + 0.5);
        float2 ca = float2(-0.36, 0.14), cb = float2(0.45, -0.22);
        float sa = 0.55, sb = 0.4;
        col += galMember((X - ca) / sa, G, ta, tilt, seed, G.b.y);
        float ang = 1.1;
        float2 xb = (X - cb) / sb;
        xb = float2(cos(ang) * xb.x - sin(ang) * xb.y, sin(ang) * xb.x + cos(ang) * xb.y);
        col += galMember(xb, G, tb, tilt * 0.5 + 0.45, seed + 17.0, G.b.y * 0.8);
        float wA, fA, kA, wB, fB, kB;
        float3 cA = galTailStyle(ta, wA, fA, kA), cB = galTailStyle(tb, wB, fB, kB);
        float wBr = max(wA, wB) > 1.0 ? 1.6 : 1.0;
        float bridge = 0.0, tailA = 0.0, tailB = 0.0;
        for (int i = 0; i < 24; i++) {
            float t = float(i) / 23.0;
            // Bridge from A to B bending up, tail from B curling down and out. An elliptical's stream
            // keeps to the first part of the curve and fades out.
            float2 p1 = mix(mix(ca, float2(0.1, 0.45), t), mix(float2(0.1, 0.45), cb, t), t);
            float2 p2 = mix(mix(cb, float2(0.95, -0.55), t), mix(float2(0.95, -0.55), float2(0.2, -0.85), t), t);
            float2 p3 = mix(mix(ca, float2(-0.95, 0.15), t), mix(float2(-0.95, 0.15), float2(-0.6, 0.75), t), t);
            float w1 = (0.035 + 0.03 * t) * wBr, w2 = (0.03 + 0.05 * t) * wB, w3 = (0.03 + 0.05 * t) * wA;
            float eB = fB > 0.5 ? 1.0 : 1.0 - smoothstep(0.35, 0.8, t);
            float eA = fA > 0.5 ? 1.0 : 1.0 - smoothstep(0.35, 0.8, t);
            bridge = max(bridge, exp(-length_squared(X - p1) / (w1 * w1)) * 0.55);
            tailB = max(tailB, exp(-length_squared(X - p2) / (w2 * w2)) * (1.0 - t * 0.7) * eB);
            tailA = max(tailA, exp(-length_squared(X - p3) / (w3 * w3)) * (1.0 - t * 0.7) * 0.8 * eA);
        }
        float tn = fbm3(float3(X * 9.0, seed + 4.0), 3);
        float3 cBr = (cA + cB) * 0.5;
        if (all(cA == cB) && kA == 0.0 && wA == 1.0) {
            // Two disks with the same tails: the original look, one light for all three streams.
            float tail = max(max(bridge, tailB), tailA);
            col += tail * cA * (0.2 + 1.3 * tn * tn) * (0.4 + G.c.x);
        } else {
            float knots = 0.4 + 1.8 * smoothstep(0.5, 0.8, vnoise3(float3(X * 22.0, seed + 8.0)));
            float3 light = bridge * cBr + tailA * cA * mix(1.0, knots, kA) + tailB * cB * mix(1.0, knots, kB);
            col += light * (0.2 + 1.3 * tn * tn) * (0.4 + G.c.x);
            float2 away = normalize(ca - cb);
            float sn = 0.5 + vnoise3(float3(X * 14.0, seed + 2.0));
            if (ta == 3) col += galOld * 0.012 * sn * galShells((X - ca) / sa, away);
            if (tb == 3) col += galOld * 0.012 * sn * galShells((X - cb) / sb, -away);
        }
    } else if (type == 8) {
        // Quasar: faint host, two thin jets; the bright core is drawn as a point in skyObjects.
        col = galOld * galBulge(X, 0.22, 0.8, 2.0) * 0.35;
        float ang = 0.35;
        float2 r = float2(cos(ang) * X.x + sin(ang) * X.y, -sin(ang) * X.x + cos(ang) * X.y);
        float along = abs(r.y);
        float w = 0.012 + 0.05 * along;
        float kn = vnoise3(float3(along * 14.0, 0.0, seed));
        float jet = exp(-r.x * r.x / (w * w)) * (1.0 - smoothstep(0.3, 0.8, along)) * (0.4 + 1.2 * kn) * smoothstep(0.02, 0.06, along);
        col += galYoung * jet * G.d.x * 0.8;
    } else {
        col = galRender(X, G, tilt, seed, type == 6 ? 0.0 : G.b.y, type);
        if (type == 6) col += galOld * galBulge(X, 0.08, 0.9, 3.0) * (0.3 + 0.8 * G.b.y);
    }
    float edge = 1.0 - smoothstep(0.86, 0.99, max(abs(X.x), abs(X.y)));
    return float4(sqrt(saturate(col * edge / 4.0)), 1.0);
}
"""#
