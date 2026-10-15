// Metal source, compiled at runtime so the build needs no Xcode Metal toolchain.
//
// Two passes:
//   geoFrag   traces one Kerr null geodesic per texel (backwards from the camera)
//             and stores where it ends: sky direction, up to two disk crossings,
//             and the lensed nebula colour. Runs only when the view changes.
//   dispFrag  runs every frame. Animates disk turbulence, stars, nebula shimmer
//             and the edge bands on top of the cached geodesic map.
//   edgeFrag  edges-only mode: redraws just the strips along the bars on top of a
//             still picture that dispFrag rendered once.
//
// Units: G = M = c = 1. Boyer-Lindquist coordinates, spin axis = z.

let shaderSource = shaderHead + objectShaderSource + bodyShaderSource + shipShaderSource + lensShaderSource + shaderTail

let shaderHead = #"""
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut vFull(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// Quads over a list of rectangles (target uv, y down): passes split into the tiles object lenses can bend
// and the rest, each drawn with its own variant.
vertex VOut vRects(uint vid [[vertex_id]], uint iid [[instance_id]], constant float4 *rects [[buffer(7)]]) {
    float2 c = float2(float(vid == 1 || vid == 2 || vid == 4), float(vid == 2 || vid == 4 || vid == 5));
    float4 r = rects[iid];
    float2 uv = mix(r.xy, r.zw, c);
    VOut o;
    o.pos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    o.uv = uv;
    return o;
}

// ---------------------------------------------------------------- noise

static float hash13(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

static float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float vnoise3(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i);
    float n100 = hash13(i + float3(1, 0, 0));
    float n010 = hash13(i + float3(0, 1, 0));
    float n110 = hash13(i + float3(1, 1, 0));
    float n001 = hash13(i + float3(0, 0, 1));
    float n101 = hash13(i + float3(1, 0, 1));
    float n011 = hash13(i + float3(0, 1, 1));
    float n111 = hash13(i + float3(1, 1, 1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

static float fbm3(float3 p, int oct) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < oct; i++) {
        s += a * vnoise3(p);
        p = p * 2.03 + float3(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s;
}

// Palette slots: 0..4 warm gradient (dark violet -> cream), 5 cyan, 6 blue, 7 unused.
static float3 grad5(float t, constant float4 *pal) {
    t = clamp(t, 0.0, 1.0) * 4.0;
    int i = min(int(t), 3);
    return mix(pal[i].rgb, pal[i + 1].rgb, t - float(i));
}

// ---------------------------------------------------------------- geodesics

struct GeoParams {
    float4 view;   // screen width, height (px), holeX, holeY (uv)
    float4 cam;    // spin a, inclination (rad), camera distance, M per screen unit
    float4 disk;   // rOut, rHorizon, 1: map of a second hole (sky holds its bend, see traceRay), unused
    float4 region; // screen uv rect this target covers: x0, y0, x1, y1
    float4 jet0;   // jet on, length L, base width w0, shape k
    float4 jet1;   // beta, doppler strength, base height z0, counter jet
    float4 jet2;   // width cap (camera stays outside), slow sheath share, cone start zt, tan of the opening angle
    float4 jet3;   // fall-off exponent along the jet, wobble, sideways shift onto the shadow centre (M), cos(i) / r0
};

struct GeoOut {
    float4 sky [[color(0)]];  // rgba16Unorm: escape direction (octahedral, camera frame), winding / 32, capture metric
    half4 d1  [[color(1)]];   // first disk crossing: r, cos phi, sin phi, redshift g
    half4 d2  [[color(2)]];   // second disk crossing
};

struct KState { float r, th, ph, pr, pth; };

static KState kAdd(KState s, KState d, float h) {
    KState o;
    o.r = s.r + d.r * h; o.th = s.th + d.th * h; o.ph = s.ph + d.ph * h;
    o.pr = s.pr + d.pr * h; o.pth = s.pth + d.pth * h;
    return o;
}

// Hamilton's equations for Kerr null geodesics, E = 1,
// H = [del pr^2 + pth^2 + (L/sin - a sin)^2 - (r^2 + a^2 - aL)^2 / del] / (2 sigma).
static KState kDeriv(KState s, float a, float L) {
    float sn = sin(s.th), cs = cos(s.th);
    float sn2 = max(sn * sn, 1e-12);   // a coarser clamp bends rays that pass close to the pole
    float r2 = s.r * s.r, a2 = a * a;
    float sig = r2 + a2 * cs * cs;
    float del = r2 - 2.0 * s.r + a2;
    KState d;
    d.r = del / sig * s.pr;
    d.th = s.pth / sig;
    d.ph = (2.0 * a * s.r + (sig - 2.0 * s.r) * L / sn2) / (sig * del);
    // -dH/dr on the shell H = 0 (the 1/Sigma prefactor's derivative drops out there).
    float A = r2 + a2 - a * L;
    float dd = 2.0 * s.r - 2.0;
    d.pr = -(dd * s.pr * s.pr - 4.0 * s.r * A / del + A * A * dd / (del * del)) / (2.0 * sig);
    d.pth = sn * cs * (L * L / (sn2 * sn2) - a2) / sig;
    return d;
}

static KState rk4(KState s, float h, float a, float L) {
    KState k1 = kDeriv(s, a, L);
    KState k2 = kDeriv(kAdd(s, k1, h * 0.5), a, L);
    KState k3 = kDeriv(kAdd(s, k2, h * 0.5), a, L);
    KState k4 = kDeriv(kAdd(s, k3, h), a, L);
    KState o;
    o.r   = s.r   + h / 6.0 * (k1.r   + 2.0 * k2.r   + 2.0 * k3.r   + k4.r);
    o.th  = s.th  + h / 6.0 * (k1.th  + 2.0 * k2.th  + 2.0 * k3.th  + k4.th);
    o.ph  = s.ph  + h / 6.0 * (k1.ph  + 2.0 * k2.ph  + 2.0 * k3.ph  + k4.ph);
    o.pr  = s.pr  + h / 6.0 * (k1.pr  + 2.0 * k2.pr  + 2.0 * k3.pr  + k4.pr);
    o.pth = s.pth + h / 6.0 * (k1.pth + 2.0 * k2.pth + 2.0 * k3.pth + k4.pth);
    return o;
}

static float3 toCart(float r, float th, float ph, float a) {
    float R = sqrt(r * r + a * a);
    return float3(R * sin(th) * cos(ph), R * sin(th) * sin(ph), r * cos(th));
}

// Frequency ratio observed/emitted for gas on a prograde circular orbit.
// The traced ray runs camera -> scene, so the physical photon has L = -Lray.
static float redshift(float r, float a, float Lray) {
    float om = 1.0 / (r * sqrt(r) + a);
    float gtt = -(1.0 - 2.0 / r);
    float gtp = -2.0 * a / r;
    float gpp = r * r + a * a + 2.0 * a * a / r;
    float den = -(gtt + 2.0 * om * gtp + om * om * gpp);
    if (den <= 0.0) return 0.25;
    float ut = 1.0 / sqrt(den);
    return 1.0 / (ut * (1.0 + om * Lray));
}


// Octahedral unit-vector encoding, centred on +z (camera forward), so the fold lies
// behind the camera where almost no ray ends up.
static float2 octEncode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    float2 p = n.xy;
    if (n.z < 0.0) p = (1.0 - abs(p.yx)) * select(float2(-1.0), float2(1.0), p >= 0.0);
    return p * 0.5 + 0.5;
}

static float3 octDecode(float2 e) {
    float2 f = e * 2.0 - 1.0;
    float3 n = float3(f, 1.0 - abs(f.x) - abs(f.y));
    float t = saturate(-n.z);
    n.xy += select(float2(t), float2(-t), n.xy >= 0.0);
    return normalize(n);
}

// Minimum over r of the radial potential R(r) / (r^2 + a^2)^2. A ray from outside falls
// in exactly when R stays positive all the way down, so this number crosses zero right
// on the shadow edge. That gives the edge a smooth sub-pixel coverage.
static float captureMetric(float a, float L, float Q, float rH, float r0) {
    float rMax = min(r0, 14.0);
    float k = Q + (L - a) * (L - a);
    float best = 1e9, bestR = rH;
    for (int i = 0; i < 48; i++) {
        float x = float(i) / 47.0;
        float r = mix(rH * 1.0001, rMax, x * x);
        float A = r * r + a * a - a * L;
        float n = r * r + a * a;
        float v = (A * A - (r * r - 2.0 * r + a * a) * k) / (n * n);
        if (v < best) { best = v; bestR = r; }
    }
    // Golden-section refinement around the best sample.
    float lo = max(rH * 1.0001, bestR - 0.4), hi = min(rMax, bestR + 0.4);
    for (int i = 0; i < 14; i++) {
        float m1 = mix(lo, hi, 0.382), m2 = mix(lo, hi, 0.618);
        float A1 = m1 * m1 + a * a - a * L, n1 = m1 * m1 + a * a;
        float A2 = m2 * m2 + a * a - a * L, n2 = m2 * m2 + a * a;
        float v1 = (A1 * A1 - (m1 * m1 - 2.0 * m1 + a * a) * k) / (n1 * n1);
        float v2 = (A2 * A2 - (m2 * m2 - 2.0 * m2 + a * a) * k) / (n2 * n2);
        if (v1 < v2) hi = m2; else lo = m1;
        best = min(best, min(v1, v2));
    }
    return best;
}

// Width of the jet at height z: parabolic from the base (w0 at z0, exponent k), from zt on
// a cone with half opening angle atan(tanO). Like M87: parabolic near the hole, conical further out.
static float jetWidth(float z, constant GeoParams &P) {
    float w0 = P.jet0.z, k = P.jet0.w, z0 = P.jet1.z, zt = P.jet2.z;
    float zp = min(z, zt);
    float w = w0 * exp2(k * log2(max(zp, 1e-3) / z0));
    return min(w + max(z - zt, 0.0) * P.jet2.w, P.jet2.x);
}

// erf with an absolute error below 1.5e-7 (Abramowitz and Stegun 7.1.26).
static float erfApprox(float x) {
    float t = 1.0 / (1.0 + 0.3275911 * abs(x));
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x);
    return copysign(y, x);
}

// Jet emission along one ray segment p0 -> p1 (traced from the camera outwards). The jet
// runs along the spin axis, its axis wobbles a little. The segment is cut into a few pieces
// along the axis; across the jet each piece is integrated exactly (a straight line through a
// Gaussian tube), so neighbouring rays agree and the map is smooth even where one segment
// is many jet widths long. Adds to acc = (emission in front of the first disk crossing,
// behind it, position-weighted sums).
static void jetSegment(float3 p0, float3 p1, int hits, float ringW, constant GeoParams &P, thread float4 &acc) {
    float L = P.jet0.y;
    float z0 = P.jet1.z;
    float za = abs(p0.z), zb = abs(p1.z);
    bool cross = p0.z * p1.z < 0.0;
    if (max(za, zb) < z0) return;
    if (!cross && min(za, zb) > L) return;
    float3 d = p1 - p0;
    float bb = dot(d.xy, d.xy);
    // The axis is moved sideways (along +y, screen right; jet3.z < 0 moves it left) onto the shadow's
    // centre line, scaled with the depth so it stays one vertical line on screen (ObjectSystem.shadowCentre).
    // Behind the hole the lens widens that offset near the base, so the counter jet gets two thirds of it there.
    float2 sh0 = float2(0.0, P.jet3.z * (1.0 - 0.5 * (p0.z + p1.z) * P.jet3.w));
    float2 a0 = p0.xy - sh0;
    float tc = bb > 1e-12 ? saturate(-dot(a0, d.xy) / bb) : 0.0;
    float rho = length(a0 + d.xy * tc);
    float wMax = jetWidth(min(max(za, zb), L), P);
    if (rho > 3.5 * wMax + abs(P.jet3.z * d.z * P.jet3.w)) return;
    float segLen = length(d);
    if (segLen < 1e-6) return;
    float3 ph = -d / segLen;   // the physical photon flies towards the camera
    // Doppler boost of the flow (outwards along the axis) for this photon direction, for the
    // jet (z > 0) and the counter jet; the same for the whole segment.
    float beta = P.jet1.x;
    float gam = 1.0 / sqrt(max(1.0 - beta * beta, 1e-5));
    float bs = min(beta, 0.3);
    float gs = 1.0 / sqrt(1.0 - bs * bs);
    float2 cth = float2(ph.z, -ph.z);
    float2 lS = -log2(gam * (1.0 - beta * cth)), lH = -log2(gs * (1.0 - bs * cth));
    float2 boost = mix(1.0, mix(exp2(2.7 * lS), exp2(2.7 * lH), P.jet2.y), P.jet1.y);
    float lDecay = log2(1.5 * z0);
    // Pieces along the axis: width, fade and fall-off change slowly with height.
    float zLow = cross ? z0 : max(min(za, zb), z0);
    int n = clamp(int(ceil(abs(d.z) / (0.3 * zLow))), 1, 8);
    float inv = 1.0 / float(n);
    float sb = sqrt(bb);
    for (int i = 0; i < n; i++) {
        float ta = float(i) * inv, tb = ta + inv;
        // Where this piece comes closest to the axis: that height sets width, wobble and brightness.
        float tq = bb > 1e-12 ? clamp(-dot(a0, d.xy) / bb, ta, tb) : ta + 0.5 * inv;
        float3 q = p0 + d * tq;
        float zz = abs(q.z);
        if (zz < z0 || zz > L) continue;
        if (q.z < 0.0 && P.jet1.w < 0.5) continue;
        float w = jetWidth(zz, P);
        // Slow helical wobble of the axis, a fraction of the local width. It sets in above the base,
        // so jet and counter jet leave the hole on the axis, symmetric.
        float ang = zz * 0.42 + (q.z > 0.0 ? 0.0 : 2.1);
        float2 c = P.jet3.y * 0.6 * w * smoothstep(z0, 6.0 * z0, zz) * float2(sin(ang), cos(ang * 0.83))
                 + float2(0.0, P.jet3.z * (1.0 - q.z * P.jet3.w)
                               * (q.z < 0.0 ? mix(0.65, 1.0, smoothstep(z0, 4.0 * z0, zz)) : 1.0));
        float2 e0 = p0.xy - c;
        // Mean of exp(-rho^2 / w^2) over the piece, rho^2 = rMin^2 + bb (t - tm)^2.
        float g;
        float k = sb / w;
        if (k * inv < 0.05) {
            float2 rq = e0 + d.xy * (ta + 0.5 * inv);
            g = exp(-dot(rq, rq) / (w * w));
        } else {
            float tm = -dot(e0, d.xy) / bb;
            float2 rm = e0 + d.xy * tm;
            g = exp(-dot(rm, rm) / (w * w)) * 0.88622693 / (k * inv)
              * (erfApprox((tb - tm) * k) - erfApprox((ta - tm) * k));
        }
        if (g < 1e-6) continue;
        float fade = smoothstep(z0, z0 * 2.0, zz) * (1.0 - smoothstep(L * 0.35, L, zz));
        // Same flux through every cross section (the base as bright for any width), falling
        // further off as the jet expands.
        float dens = g * P.jet0.z / (w * w) * fade * exp2(-P.jet3.x * max(log2(zz) - lDecay, 0.0));
        float x = saturate(1.0 - 2.0 / length(q));
        float e = dens * (q.z > 0.0 ? boost.x : boost.y) * x * sqrt(x) * segLen * inv * ringW;
        if (hits == 0) { acc.x += e; acc.z += e * zz / L; } else { acc.y += e; acc.w += e * zz / L; }
    }
}

struct GeoOutJ {
    float4 sky [[color(0)]];
    half4 d1  [[color(1)]];
    half4 d2  [[color(2)]];
    half2 jet [[color(3)]];   // emission in front of / behind the first disk crossing
    float2 jetPos [[color(4)]];   // their mean position along the jet, 0 base, 1 end (16 bit: knots do not step)
};

// One ray per texel. With JET the jet emission is collected on the way; the compiler
// folds the jet code away in geoFrag, so its output stays the same.
template <bool JET>
static GeoOut traceRay(VOut in, constant GeoParams &P, thread float4 &jetOut) {
    float W = P.view.x, H = P.view.y;
    float S = min(W, H);
    float2 px = mix(P.region.xy, P.region.zw, in.uv) * float2(W, H);
    float2 c = P.view.zw * float2(W, H);
    // A spinning hole's shadow sits about 2 a sin(i) off-axis; shift so it lands on the hole position.
    float alpha = (px.x - c.x) / S * P.cam.w - 2.0 * P.cam.x * sin(P.cam.y);
    float beta = -(px.y - c.y) / S * P.cam.w;

    float a = P.cam.x, th0 = P.cam.y, r0 = P.cam.z;
    float rOut = P.disk.x, rH = P.disk.y;

    // Pinhole camera at (r0, th0, phi = 0). Screen right = +phi, screen up = -theta.
    float L = alpha * sin(th0);
    // Rays with almost no angular momentum graze the pole, where Boyer-Lindquist
    // coordinates are singular. Below this they go exactly over it (L = 0), a
    // difference far below one pixel.
    if (abs(L) < 0.005) L = 0.0;
    float Q = beta * beta + cos(th0) * cos(th0) * (alpha * alpha - a * a);
    float D0 = r0 * r0 - 2.0 * r0 + a * a;
    float R0 = r0 * r0 + a * a - a * L;
    R0 = R0 * R0 - D0 * (Q + (L - a) * (L - a));

    KState s;
    s.r = r0; s.th = th0; s.ph = 0.0;
    s.pr = -sqrt(max(R0, 0.0)) / D0;
    s.pth = -beta;

    GeoOut o;
    half4 none = half4(1000.0h, 1.0h, 0.0h, 1.0h);
    o.d1 = none; o.d2 = none;
    int hits = 0;
    float wind = 0.0;
    float4 jacc = float4(0.0);
    float rMin = r0;
    float3 prevP = toCart(s.r, s.th, s.ph, a);
    float3 camDir = normalize(prevP);
    float3 fwd = -camDir;
    float3 right = normalize(cross(fwd, float3(0.0, 0.0, 1.0)));
    float3 up = cross(right, fwd);
    float3 dir = fwd;
    // Map of a second hole: the total turn of the ray, summed step by step, and its axis. Read back from
    // the escape direction, a turn of about half a circle lands on the fold of the octahedral encoding,
    // where filtering between texels gives directions far off; a turn past a full circle wraps.
    bool holeMap = P.disk.z > 0.5;
    float3 turnAxis = float3(0.0);   // sum of the small turns as rotation vectors

    for (int i = 0; i < 900; i++) {
        float h = min(0.06 * s.r, 0.1 * (s.r - rH) + 0.012);
        // Near the poles the L^2/sin^4 term turns violently; limit the theta change per step.
        float sig = s.r * s.r + a * a * cos(s.th) * cos(s.th);
        float snt = sin(s.th);
        h = min(h, (0.08 * abs(snt) + 0.001) * sig / (abs(s.pth) + 1e-4));
        h = min(h, 0.05 * sig * snt * snt / (abs(L) + 1e-3));   // at most ~0.05 rad of phi per step
        h = max(h, 1e-4);
        KState n = rk4(s, h, a, L);
        if (isnan(n.r) || isnan(n.th)) break;

        float c0 = cos(s.th), c1 = cos(n.th);
        if (c0 * c1 < 0.0 && hits < 2) {
            float f = c0 / (c0 - c1);
            float rc = mix(s.r, n.r, f);
            if (rc < rOut && rc > rH) {
                float pc = mix(s.ph, n.ph, f);
                // A ray that went straight over the pole continues with theta < 0 (or > pi)
                // instead of phi + pi. Same point in space, azimuth off by half a turn.
                if (sin(mix(s.th, n.th, f)) < 0.0) pc += M_PI_F;
                half4 hv = half4(half(rc), half(cos(pc)), half(sin(pc)), half(redshift(rc, a, L)));
                if (hits == 0) o.d1 = hv; else o.d2 = hv;
                hits++;
            }
        }
        wind += abs(n.th - s.th) + abs(n.ph - s.ph) * abs(sin(s.th));
        float3 p = toCart(n.r, n.th, n.ph, a);
        if (JET) {
            // Light that reaches us only after the ray grazed the photon orbits (outbound again after a
            // close pass) forms hairline arcs around the shadow. The map cannot resolve them, they showed
            // as dotted arcs, and with the jet on the shadow's centre line they sat on one side only.
            rMin = min(rMin, n.r);
            float ringW = n.r > rMin + 0.05 ? smoothstep(3.6, 5.6, rMin) : 1.0;
            jetSegment(prevP, p, hits, ringW, P, jacc);
        }
        float3 nd = normalize(p - prevP);
        if (holeMap && i > 0) {
            float3 tx = cross(dir, nd);
            float tl = length(tx);
            float ta = atan2(tl, dot(dir, nd));
            if (tl > 1e-9) turnAxis += tx * (ta / tl);
        }
        dir = nd;
        prevP = p;
        s = n;
        if (s.r < rH * 1.1) break;
        if (s.r > r0 * 1.6) break;
    }

    float3 cd = float3(dot(dir, right), dot(dir, up), dot(dir, fwd));
    float cm = captureMetric(a, L, Q, rH, r0);
    o.sky = float4(octEncode(cd), saturate(wind / 32.0), 0.5 + 0.5 * clamp(cm * 8.0, -1.0, 1.0));
    if (holeMap) {
        // xy: axis of the turn in the camera frame (it lies almost in the picture plane), z: the turn / 32.
        // (right, up, fwd) is left-handed: a cross product taken in space flips sign in it.
        float2 ax = -float2(dot(turnAxis, right), dot(turnAxis, up));
        float al = length(ax);
        o.sky.xy = (al > 1e-9 ? ax / al : float2(0.0)) * 0.5 + 0.5;
        o.sky.z = saturate(length(turnAxis) / 32.0);
    }
    if (JET) {
        jetOut = float4(min(jacc.x, 60000.0), min(jacc.y, 60000.0),
                        jacc.x > 1e-6 ? jacc.z / jacc.x : 0.0, jacc.y > 1e-6 ? jacc.w / jacc.y : 0.0);
    }
    return o;
}

fragment GeoOut geoFrag(VOut in [[stage_in]], constant GeoParams &P [[buffer(0)]]) {
    float4 unused;
    return traceRay<false>(in, P, unused);
}

fragment GeoOutJ geoFragJet(VOut in [[stage_in]], constant GeoParams &P [[buffer(0)]]) {
    float4 j = float4(0.0);
    GeoOut g = traceRay<true>(in, P, j);
    GeoOutJ o;
    o.sky = g.sky; o.d1 = g.d1; o.d2 = g.d2; o.jet = half2(j.xy); o.jetPos = j.zw;
    return o;
}

// ---------------------------------------------------------------- baked textures

// Disk gas pattern in co-rotating polar coordinates, baked once into a texture so the
// per-frame pass only does two lookups. u = phi / 2pi (wraps), v = ln r / ln rOut.
// Channels: density, hue offset + 0.5, dust lanes.
fragment float4 bakeDisk(VOut in [[stage_in]], constant float4 &B [[buffer(0)]]) {
    float phi = in.uv.x * 2.0 * M_PI_F;
    float lr = in.uv.y * log(B.x);
    float ps = phi + 1.8 * lr;                       // logarithmic spiral arms
    float n = fbm3(float3(cos(ps) * 1.3, sin(ps) * 1.3, lr * 6.0), 5);
    float f = fbm3(float3(cos(ps) * 4.0, sin(ps) * 4.0, lr * 20.0) + 4.0, 3);
    float dens = smoothstep(0.30, 0.85, n * 0.75 + f * 0.35);
    float hue = fbm3(float3(cos(phi) * 0.9, sin(phi) * 0.9, lr * 2.5 + 3.0), 3);
    float pl = phi + 1.2 * lr;
    float lanes = smoothstep(0.25, 0.6, fbm3(float3(cos(pl) * 2.0, sin(pl) * 2.0, lr * 9.0 + 5.0), 4));
    return float4(dens, hue, lanes, 1.0);
}

// Nebula on the sky in polar coordinates around the point straight behind the hole:
// u = azimuth / 2pi, v = sqrt(angle / pi). Swirl and rotation become a shift in u per
// frame, so the nebula can turn around the hole without tracing rays again.
// Channels: brightness, hue, haze.
fragment float4 bakeNebula(VOut in [[stage_in]], constant float4 &B [[buffer(0)]]) {
    float az = in.uv.x * 2.0 * M_PI_F;
    float ang = in.uv.y * in.uv.y * M_PI_F;
    float3 d = float3(sin(ang) * cos(az), sin(ang) * sin(az), cos(ang));
    float3 q = d * B.x + B.y * float3(13.1, 7.7, 3.3);
    float3 w = float3(fbm3(q + 1.3, 4), fbm3(q + 5.2, 4), fbm3(q + 9.1, 4));
    float n = fbm3(q * 1.3 + w * 2.2, 5);
    float lanes = fbm3(q * 2.6 + w * 3.0 + 3.7, 4);
    float hue = fbm3(q * 0.6 + w * 0.8 + 11.0, 3);
    float dens = smoothstep(0.40, 0.78, n);
    dens *= mix(0.25, 1.0, smoothstep(0.35, 0.62, lanes));
    float focus = 0.2 + 1.3 * exp(-ang * 3.5);
    return float4(saturate(dens * dens * focus * 0.7), hue, n, 1.0);
}

// Noise along the bar edges, periodic in u (256 units over the width), two rows.
fragment float4 bakeEdgeNoise(VOut in [[stage_in]]) {
    float a = in.uv.x * 2.0 * M_PI_F;
    const float R = 256.0 / (2.0 * M_PI_F);
    float row = floor(in.uv.y * 2.0);
    float n = fbm3(float3(cos(a) * R, sin(a) * R, row * 7.0), 3) * 1.33;
    return float4(saturate(n), 0.0, 0.0, 1.0);
}

// ---------------------------------------------------------------- per frame

struct FrameParams {
    float4 view;    // width, height, time (s), holeX
    float4 bars;    // top bar px, bottom bar px, px per point, holeY
    float4 disk;    // rISCO, rOut, spin, disk brightness
    float4 look;    // exposure, stars, nebula, ring glow
    float4 motion;  // disk clock, disk shear, nebula clock, debug view
    float4 box;     // detail map rect in screen uv (x0 < 0: none)
    float4 starp;   // twinkle, density, colourfulness, unused
    float4 nebp;    // swirl, edge band time (s), disk hue variety, output (1 = linear base for edgeFrag)
    float4 mouse;   // x px, y px, Einstein radius px (0 = off), shadow
    float4 edge[8]; // top side 0..3, bottom side 4..7, see edgeLight
    float4 pal[8];
    float4 region;  // part of the screen the target covers, in screen uv (x0, y0, x1, y1)
    float4 objA;    // sky object count, sky mask margin (rad), jet on, unlensed rad per pixel
    float4 jetC;    // jet colour rgb (linear), brightness
    float4 jetK;    // knot contrast, knot phase front, knot phase back, knot spacing
    float4 jetP;    // pulse depth, pulse phase, filaments, jet axis right of the hole position (fraction of the shorter side)
    float4 camA;    // camera distance r0, M per shorter screen side, shadow shift 2 a sin i, depth of the hole
    float4 camP;    // camera position (world), number of path-L bodies
    float4 camR;    // camera right (world), shadow radius (px)
    float4 camU;    // camera up (world), light buffer on
    float4 camF;    // camera forward (world), front pass target: 0 tone mapped, 1 linear
    float4 bodyU;   // union of the screen regions where path-L bodies can show (px): x0 y0 x1 y1
    float4 lightU;  // rectangle the light buffer covers (px): x0 y0 x1 y1
    float4 lensA;   // number of object lenses (second holes, wormholes, gates), unused
    float4 qual;    // quality: jet upsampled bicubic, unused, unused, unused
};

// Object lenses only in the pipelines made for them, so the others stay as fast as before.
constant bool lensesFC [[function_constant(1)]];
constant bool withLenses = is_function_constant_defined(lensesFC) && lensesFC;
// A lens behind the hole plane: its light is drawn inside dispFrag, under the disk and the shadow.
constant bool behindFC [[function_constant(2)]];
constant bool lensesBehind = withLenses && is_function_constant_defined(behindFC) && behindFC;
// Tiles where every lens is seen only in its weak far field: the bends are a few formulas, no ray map, no layers.
constant bool farFC [[function_constant(3)]];
constant bool lensFar = withLenses && is_function_constant_defined(farFC) && farFC;

// One object lens (stage 4), see LensShaders. Thirteen float4.
struct LensObj {
    float4 a;     // type (1 hole, 2 wormhole, 3 gate), centre x, y (px, unlensed), 1 = behind the hole plane
    float4 b;     // hole: px per M2, box half (M2), r0 of its map, shadow shift (M2). wormhole: radius px, Einstein radius px.
                  // gate: inverse of the ring's half axes on the screen (2 x 2, rows)
    float4 c;     // hole: cos, sin of its roll. all: lens weight (behind) or plane share (in front), map slot
    float4 disk;  // hole: rISCO, rOut (0: none), spin, brightness
    float4 dclk;  // hole: disk clock, shear, hue rotation (rad), ring glow. gate: event (9, 10), phase, seed, radius px
    float4 jetC;  // hole: jet colour, brightness. wormhole, gate: other side brightness, stars, normal x, normal y (gate)
    float4 jetK;  // hole: knots, phase front, phase back, spacing
    float4 side;  // wormhole, gate: hue of the other side (rad), mode, rim glow, ripple
    float4 rot0, rot1, rot2;   // other side: rotation (columns), w: time
    float4 rect;  // screen rectangle (px) of what it shows itself
    float4 reach; // radius (px) beyond which it no longer bends anything, unused
};

// Sky direction of a pixel through the object lenses and the hole; defined in LensShaders.
static float3 lensedDir(float2 px, constant FrameParams &P, constant LensObj *L, texture2d<float> tSky, texture2d<float> bSky,
                        texture2d<float> m0, texture2d<float> m1, thread float2 &uvMain, thread float4 &skMain);

struct Maps {
    float4 sky, h1, h2;
    float c1, c2;
};

const constant float inv2pi = 0.15915494;

// Share of a body behind a disk crossing (alpha o, radius r) that the gas hides on top of its alpha.
// The disk's alpha is kept low so stars twinkle through its lanes, but a lit planet is far brighter than
// a star and showed through the bright inner disk as a ghost. In the inner disk (up to 0.25 of its
// radius, soft to 0.4) dense gas (o from 0.25) hides it; the faintest gas and the outer disk as before.
static float bodyHidden(float o, float r, constant FrameParams &P) {
    return (1.0 - smoothstep(0.25 * P.disk.y, 0.4 * P.disk.y, r)) * smoothstep(0.03, 0.25, o);
}

// Returns premultiplied emission, alpha in `alpha`.
static float3 diskShade(float4 hv, float squeeze, constant FrameParams &P,
                        texture2d<float> tex, thread float &alpha) {
    constexpr sampler ps(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    alpha = 0.0;
    float r = hv.x;
    float rIn = P.disk.x, rOut = P.disk.y, a = P.disk.z;
    if (r > rOut || r < 0.8) return float3(0.0);
    float phi = atan2(hv.z, hv.y);
    float g = hv.w;
    float lr = log(r);

    // Angular speed relative to the inner edge. Shear 1 is Kepler (inside fast, outside
    // slow), 0 turns the whole disk like a plate. The clock is scaled so that the inner
    // edge turns once per chosen period.
    float omK = 1.0 / (r * sqrt(r) + a);
    float omI = 1.0 / (rIn * sqrt(rIn) + a);
    float rel = pow(omK / omI, P.motion.y);
    // Reset every 1.5 inner turns and cross-fade, so differential rotation never winds
    // the pattern up into hair-thin streaks.
    const float per = 3.0 * M_PI_F;
    float t1 = fmod(P.motion.x, per), t2 = fmod(P.motion.x + per * 0.5, per);
    float wgt = abs(t1 / per * 2.0 - 1.0);
    float v = lr / log(rOut);
    float4 s1 = tex.sample(ps, float2((phi - rel * t1) * inv2pi, v), level(0.0));
    float4 s2 = tex.sample(ps, float2((phi - rel * t2 + 2.1) * inv2pi, v), level(0.0));
    float4 m = mix(s1, s2, wgt);
    // Where the lens squeezes the disk into a few pixels, fade the texture to its mean
    // instead of letting it alias into speckles.
    float fade = saturate(squeeze);
    float dens = mix(m.x, 0.45, fade);
    float lanes = mix(m.z, 0.6, fade);
    float hueN = m.y - 0.5;

    // Novikov-Thorne-like temperature profile, peak normalised to 1.
    float x = r / rIn;
    float sx = sqrt(x);
    float prof = x > 1.0 ? sqrt(sqrt(1.0 - 1.0 / sx)) / (sx * sqrt(sx)) / 0.488
                         : exp(-(1.0 - x) * 6.0) * 0.25;
    float tObs = prof * g;
    float I = g * g * g * prof;
    float3 col = grad5(0.2 + 0.85 * pow(saturate(tObs), 0.7) + hueN * P.nebp.z, P.pal);
    float outer = 1.0 - smoothstep(rOut * 0.35, rOut, r);
    // Inside the ISCO the gas plunges and thins out; fade it to nothing at the horizon.
    float rH = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    float plunge = x > 1.0 ? 1.0 : 0.6 * smoothstep(0.0, 1.0, (r - rH) / max(rIn - rH, 1e-3));
    alpha = saturate(dens * 1.2) * outer * plunge * mix(0.35, 1.0, lanes);
    float glow = (I * 2.2 + 0.05) * mix(0.25, 1.0, lanes);
    return col * glow * alpha * P.disk.w;
}

// Star colour from surface temperature (Planck curve fit, Tanner Helland), linear RGB.
static float3 blackbody(float T) {
    float t = T / 100.0;
    float r = t <= 66.0 ? 1.0 : saturate(1.292936 * pow(t - 60.0, -0.1332047));
    float g = t <= 66.0 ? saturate(0.39008158 * log(t) - 0.63184144)
                        : saturate(1.129890 * pow(t - 60.0, -0.0755148));
    float b = t >= 66.0 ? 1.0 : (t <= 19.0 ? 0.0 : saturate(0.54320679 * log(t - 10.0) - 1.19625409));
    float3 c = pow(float3(r, g, b), 2.2);
    return c / max(dot(c, float3(0.2126, 0.7152, 0.0722)), 1e-3);
}

static float3 starLayer(float3 d, float density, float thresh, float size, float t, constant FrameParams &P) {
    float3 q = d * density;
    float3 cell = floor(q);
    float h = hash13(cell);
    if (h < thresh) return float3(0.0);
    float3 o = hash33(cell + 17.0) * 0.6 + 0.2;
    float3 dd = q - (cell + o);
    float b = exp(-dot(dd, dd) / (size * size));
    float tw = 1.0 - P.starp.x * (0.5 + 0.5 * sin(t * (0.4 + h * 2.5) + h * 40.0));
    // Most stars are cool and orange, a few hot and blue (skewed like a real sky).
    float u = hash13(cell + 5.0);
    float T = 3000.0 + 22000.0 * u * u * u;
    float3 bb = blackbody(T);
    float3 sc = mix(float3(1.0), bb, P.starp.z);
    return max(sc, 0.0) * b * tw * (0.25 + 1.2 * (h - thresh) / (1.0 - thresh));
}

// Glowing line on a bar boundary. dy > 0 points into the picture, dy < 0 into the bar.
// Per side: e0 = intensity (0 off), line width pt, reach into picture pt, reach into bar pt
//           e1 = darken picture, darken bar, flow speed, flow mode
//           e2 = focus on the hole, colour mode, bar height px, unused
//           e3 = custom colour
// Darkening of the picture near a bar (1 = none), the part of edgeLight that does not move.
static float edgeDarken(float dy, int side, constant FrameParams &P) {
    float4 e0 = P.edge[side * 4], e1 = P.edge[side * 4 + 1], e2 = P.edge[side * 4 + 2];
    if (e0.x <= 0.0) return 1.0;
    float s = P.bars.z;
    bool inPic = dy >= 0.0;
    float darken = inPic ? e1.x : e1.y;
    float extent = inPic ? max(e2.z, 4.0 * s) * 2.5 : max(e2.z, 4.0 * s);
    return 1.0 - darken * (1.0 - smoothstep(0.0, extent, abs(dy)));
}

static float3 edgeLight(float dy, float pxX, float t, int side, constant FrameParams &P,
                        texture2d<float> noise, thread float &darkMul) {
    float4 e0 = P.edge[side * 4], e1 = P.edge[side * 4 + 1], e2 = P.edge[side * 4 + 2], e3 = P.edge[side * 4 + 3];
    darkMul = edgeDarken(dy, side, P);
    if (e0.x <= 0.0) return float3(0.0);
    float s = P.bars.z;
    bool inPic = dy >= 0.0;
    float reach = (inPic ? e0.z : e0.w) * s;
    float w = max(e0.y, 0.2) * s;
    float cutoff = max(reach * 4.0 + 6.0 * s, w * 4.0);
    if (abs(dy) > cutoff) return float3(0.0);

    float W = P.view.x;
    float xN = pxX / W;
    float dx = xN - P.view.w;
    float focus = e2.x;
    float nearHole = exp(-abs(dx) * 2.5 * max(focus, 0.05));
    float3 col;
    if (e2.y > 0.5) {
        col = e3.rgb;
    } else {
        float3 warm = grad5(0.3 + 0.6 * nearHole, P.pal);
        col = mix(P.pal[5].rgb, warm, saturate(nearHole * 1.6));
    }
    float k = W / (80.0 * s);
    float spd = e1.z * 0.25;
    int mode = int(e1.w + 0.5);
    float u = mode == 0 ? abs(dx) * k + t * spd        // towards the hole
            : mode == 1 ? abs(dx) * k - t * spd        // away from the hole
            : mode == 2 ? xN * k - t * spd              // left to right
            :             xN * k + t * spd;             // right to left
    constexpr sampler es(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float row = side == 0 ? 0.25 : 0.75;
    float n = noise.sample(es, float2(u / 256.0, row), level(0.0)).x * 0.65
            + noise.sample(es, float2((u * 0.53 + t * 0.05 * e1.z + 37.0) / 256.0, row), level(0.0)).x * 0.35;
    float inten = (0.2 + 1.1 * n * n) * mix(1.0, 0.35 + 0.65 * nearHole, saturate(focus));
    float core = exp(-(dy * dy) / (w * w));
    float halo = reach > 0.01 ? exp(-abs(dy) / reach) * 0.28 * (1.0 - smoothstep(cutoff * 0.6, cutoff, abs(dy))) : 0.0;
    return col * (core + halo) * inten * e0.x;
}

// Bilinear fetch that only blends texels which actually hit the disk. Plain linear
// filtering would average a real radius with the "no hit" marker (r = 1000) and cut
// the disk edge into stair steps. `cover` is the share of hit texels.
static float4 diskFetch(texture2d<half> t, float2 uv, thread float &cover) {
    float2 size = float2(t.get_width(), t.get_height());
    float2 p = uv * size - 0.5;
    float2 f = fract(p);
    int2 i0 = int2(floor(p));
    int2 mx = int2(size) - 1;
    float4 acc = 0.0;
    cover = 0.0;
    for (int k = 0; k < 4; k++) {
        int2 o = int2(k & 1, k >> 1);
        int2 q = clamp(i0 + o, int2(0), mx);
        float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
        float4 v = float4(t.read(uint2(q)));
        if (v.x < 900.0) { acc += v * w; cover += w; }
    }
    if (cover < 1e-4) return float4(1000.0, 1.0, 0.0, 1.0);
    return acc / cover;
}

static Maps fetchMaps(float2 uv, texture2d<float> tSky, texture2d<half> tD1, texture2d<half> tD2) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    Maps m;
    m.sky = tSky.sample(ls, uv);
    m.h1 = diskFetch(tD1, uv, m.c1);
    m.h2 = diskFetch(tD2, uv, m.c2);
    return m;
}

static float4 nebulaSample(float3 d, constant FrameParams &P, texture2d<float> tex) {
    constexpr sampler ns(filter::linear, s_address::repeat, t_address::clamp_to_edge);
    float ang = acos(clamp(d.z, -1.0, 1.0));
    float az = atan2(d.y, d.x);
    float v = sqrt(ang / M_PI_F);
    float twist = P.nebp.x * exp(-ang * 4.0);
    float w = exp(-ang * 3.0);             // the inside turns faster, like a whirlpool
    const float per = 3.0 * M_PI_F;
    float t1 = fmod(P.motion.z, per), t2 = fmod(P.motion.z + per * 0.5, per);
    float wgt = abs(t1 / per * 2.0 - 1.0);
    float4 a = tex.sample(ns, float2((az + twist - w * t1) * inv2pi, v), level(0.0));
    float4 b = tex.sample(ns, float2((az + twist - w * t2 + 2.3) * inv2pi, v), level(0.0));
    return mix(a, b, wgt);
}

static float3 nebulaColour(float4 nb, constant FrameParams &P) {
    float hue = nb.y;
    float3 cool = mix(P.pal[5].rgb, P.pal[6].rgb, smoothstep(0.25, 0.5, hue));
    float3 warm = grad5(0.25 + 0.55 * smoothstep(0.45, 0.75, hue), P.pal);
    float3 col = mix(cool, warm, smoothstep(0.35, 0.6, hue));
    float3 haze = P.pal[0].rgb * 0.10 * (0.4 + nb.z);
    return haze + col * nb.x * 0.8;
}

static float3 aces(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

// Mouse mode: a small point lens follows the pointer. Picture positions inside it are
// looked up where a lens would have taken their light from.
static float2 lensed(float2 px, constant FrameParams &P, thread float &shadow) {
    shadow = 0.0;
    if (P.mouse.z <= 0.0) return px;
    float2 d = px - P.mouse.xy;
    float r = length(d);
    float re = P.mouse.z;
    float fade = 1.0 - smoothstep(re * 5.0, re * 9.0, r);
    shadow = P.mouse.w * (1.0 - smoothstep(re * 0.42, re * 0.5, r));
    return px - d * (re * re / max(r * r, 1.0)) * fade;
}

static float4 skySample(float2 uv, constant FrameParams &P, texture2d<float> tSky, texture2d<float> bSky) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float2 bmin = P.box.xy, bmax = P.box.zw;
    bool inBox = P.box.x >= 0.0 && all(uv > bmin) && all(uv < bmax);
    return inBox ? bSky.sample(ls, (uv - bmin) / (bmax - bmin)) : tSky.sample(ls, uv);
}

// Bands, tone mapping and dither. Stage 0 does all of it. Stage 1 stops after the
// darkening and returns linear colour: the still base for edgeFrag. Stage 2 starts
// from such a base and adds only the moving light.
static float4 finishPixel(float3 col, float2 px, constant FrameParams &P, texture2d<float> tEdge, int stage, thread float3 &lin) {
    float H = P.view.y, t = P.nebp.y;
    float dmT, dmB;
    float3 lT = edgeLight(px.y - P.bars.x, px.x, t, 0, P, tEdge, dmT);
    float3 lB = edgeLight((H - px.y) - P.bars.y, px.x, t, 1, P, tEdge, dmB);
    if (stage < 2) col *= dmT * dmB;
    lin = col;
    if (stage == 1) return float4(col, 1.0);
    col = aces((col + lT + lB) * P.look.x);
    col = pow(col, float3(1.0 / 2.2));
    col += (hash12(px + fract(t) * 91.0) - 0.5) / 255.0;
    return float4(col, 1.0);
}

// Cell size of the sky object mask in pixels (skyMaskFrag).
constant int maskCell = 8;

// dispFrag and edgeFrag can also write the linear colour (darkened, before the band light) into a
// second, memoryless attachment. Path F then composites in linear light inside the same pass.
constant bool withLinear [[function_constant(0)]];

struct DispOut {
    float4 c [[color(0)]];
    float4 lin [[color(1), function_constant(withLinear)]];
};

static DispOut dispOut(float4 c, float3 lin) {
    DispOut o;
    o.c = c;
    if (withLinear) o.lin = float4(lin, 1.0);
    return o;
}
// Jet light below this (linear, before knots) is invisible and skipped.
constant float jetFloor = 1.5e-4;

// The jet maps at map resolution, upsampled with Catmull-Rom (9 texels in 5 bilinear taps, corners
// dropped) and clamped to the 2 x 2 texels around: smooth like a full-resolution map, without rings
// where the emission jumps at the shadow edge. e: emission front/back, s: their positions along the jet.
static void jetCubic(texture2d<half> tE, texture2d<float> tS, float2 uv, thread float2 &e, thread float2 &s) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float2 size = float2(tE.get_width(), tE.get_height());
    float2 sp = uv * size;
    float2 t1 = floor(sp - 0.5) + 0.5;
    float2 f = sp - t1;
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 w12 = w1 + w2;
    float2 p0 = (t1 - 1.0) / size, p3 = (t1 + 2.0) / size, p12 = (t1 + w2 / w12) / size;
    float4 wt = float4(w0.x * w12.y, w12.x * w0.y, w3.x * w12.y, w12.x * w3.y);
    float wc = w12.x * w12.y;
    float norm = 1.0 / (wc + wt.x + wt.y + wt.z + wt.w);
    float2 q[5] = { p12, float2(p0.x, p12.y), float2(p12.x, p0.y), float2(p3.x, p12.y), float2(p12.x, p3.y) };
    float w[5] = { wc, wt.x, wt.y, wt.z, wt.w };
    float4 acc = float4(0.0);
    for (int i = 0; i < 5; i++) {
        acc += float4(float2(tE.sample(ls, q[i]).xy), tS.sample(ls, q[i]).xy) * w[i];
    }
    acc *= norm;
    float2 c = t1 / size;   // the 2 x 2 texels whose centres surround sp
    float4 ex = float4(tE.gather(ls, c + 0.5 / size, int2(0), component::x));
    float4 ey = float4(tE.gather(ls, c + 0.5 / size, int2(0), component::y));
    float4 sx = tS.gather(ls, c + 0.5 / size, int2(0), component::x);
    float4 sy = tS.gather(ls, c + 0.5 / size, int2(0), component::y);
    float2 eLo = float2(min(min(ex.x, ex.y), min(ex.z, ex.w)), min(min(ey.x, ey.y), min(ey.z, ey.w)));
    float2 eHi = float2(max(max(ex.x, ex.y), max(ex.z, ex.w)), max(max(ey.x, ey.y), max(ey.z, ey.w)));
    float2 sLo = float2(min(min(sx.x, sx.y), min(sx.z, sx.w)), min(min(sy.x, sy.y), min(sy.z, sy.w)));
    float2 sHi = float2(max(max(sx.x, sx.y), max(sx.z, sx.w)), max(max(sy.x, sy.y), max(sy.z, sy.w)));
    e = clamp(acc.xy, eLo, eHi);
    s = clamp(acc.zw, sLo, sHi);
}

// The nebula changes slowly and is soft, so it gets its own pass at half resolution,
// run only about 20 times a second. The main pass then just samples it.
// Alpha: 1 where a sky object or the jet may show, so dispFrag reads their maps only there.
"""#

let shaderTail = #"""
fragment half4 nebFrag(VOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                       texture2d<float> tSky [[texture(0)]],
                       texture2d<float> tNeb [[texture(4)]],
                       texture2d<float> bSky [[texture(5)]],
                       texture2d<half> tJet [[texture(11)]],
                       texture2d<half> bJet [[texture(12)]],
                       texture2d<float> tGal [[texture(13)]],
                       texture2d<uint> tMask [[texture(14)]],
                       texture2d<float> mSky0 [[texture(20)]],
                       texture2d<float> mSky1 [[texture(25)]],
                       constant SkyObj *skyObjs [[buffer(1)]],
                       constant LensObj *lenses [[buffer(3)]]) {
    float2 px = in.uv * float2(P.view.x, P.view.y);
    float shadow;
    float2 uv = lensed(px, P, shadow) / float2(P.view.x, P.view.y);
    float4 sk;
    float3 dir;
    if (withLenses) {
        dir = lensedDir(uv * P.view.xy, P, lenses, tSky, bSky, mSky0, mSky1, uv, sk);
    } else {
        sk = skySample(uv, P, tSky, bSky);
        dir = octDecode(sk.xy);
    }
    half flag = 1.0h;
    // Soft sky light (galaxies, nebula shells) lives here, at half resolution and refreshed with the nebula.
    float3 soft = float3(0.0);
    uint mask = P.objA.x > 0.5 ? tMask.read(uint2(px) / uint(maskCell)).x : 0u;
    float3 dirX = mask != 0u ? dfdx(dir) : float3(0.0), dirY = mask != 0u ? dfdy(dir) : float3(0.0);
    if (mask != 0u) soft = skyObjects(dir, dirX, dirY, uv, sk.z * 32.0, mask, P, skyObjs, tGal, tSky, bSky, 1);
    if (P.objA.x > 0.5 || P.objA.z > 0.5) {
        bool any = mask != 0u;
        if (P.objA.z > 0.5 && !any) {
            constexpr sampler ls(filter::linear, address::clamp_to_edge);
            float2 bmin = P.box.xy, bmax = P.box.zw;
            bool inBox = P.box.x >= 0.0 && all(uv > bmin) && all(uv < bmax);
            half4 j = inBox ? bJet.sample(ls, (uv - bmin) / (bmax - bmin)) : tJet.sample(ls, uv);   // rg16Float: x, y
            any = float(j.x + j.y) * P.jetC.w > jetFloor || P.mouse.z > 0.0;
        }
        flag = any ? 1.0h : 0.0h;
    }
    return half4(half3(nebulaColour(nebulaSample(dir, P, tNeb), P) * P.look.z + soft), flag);
}

fragment DispOut dispFrag(VOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                         texture2d<float> tSky [[texture(0)]],
                         texture2d<half> tD1 [[texture(1)]],
                         texture2d<half> tD2 [[texture(2)]],
                         texture2d<float> tDisk [[texture(3)]],
                         texture2d<float> bSky [[texture(5)]],
                         texture2d<half> bD1 [[texture(6)]],
                         texture2d<half> bD2 [[texture(7)]],
                         texture2d<half> tNebFrame [[texture(8)]],
                         texture2d<float> tEdge [[texture(9)]],
                         texture2d<half> tJet [[texture(11)]],
                         texture2d<half> bJet [[texture(12)]],
                         texture2d<float> tGal [[texture(13)]],
                         texture2d<float> tJetS [[texture(15)]],
                         texture2d<float> bJetS [[texture(16)]],
                         texture2d<uint> tMask [[texture(14)]],
                         texture2d<float> tBody [[texture(18)]],
                         texture2d<float> tLight [[texture(19)]],
                         texture2d<float> tNeb [[texture(4)]],
                         texture2d<float> mSky0 [[texture(20)]],
                         texture2d<half> mD10 [[texture(21)]],
                         texture2d<half> mD20 [[texture(22)]],
                         texture2d<half> mJ0 [[texture(23)]],
                         texture2d<half> mS0 [[texture(24)]],
                         texture2d<float> mSky1 [[texture(25)]],
                         texture2d<half> mD11 [[texture(26)]],
                         texture2d<half> mD21 [[texture(27)]],
                         texture2d<half> mJ1 [[texture(28)]],
                         texture2d<half> mS1 [[texture(29)]],
                         constant SkyObj *skyObjs [[buffer(1)]],
                         constant BodyRef *bodyRefs [[buffer(2)]],
                         constant LensObj *lenses [[buffer(3)]]) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float W = P.view.x, H = P.view.y, t = P.view.z;
    float2 suv = mix(P.region.xy, P.region.zw, in.uv);
    float2 px = suv * float2(W, H);
    float mouseShadow;
    float2 uv = lensed(px, P, mouseShadow) / float2(W, H);

    // Object lenses in front of the hole plane bend the ray before the hole sees it (stage 4).
    int nLens = withLenses && lensNear(uv * float2(W, H), P, lenses) ? int(P.lensA.x + 0.5) : 0;
    float3 lensD = float3(0.0);
    float4 lsk[2];
    float2 lq[2];
    bool lensOff = false;
    bool lensMoved = false;
    if (nLens > 0) {
        float2 sp = frontChain(uv * float2(W, H), P, lenses, mSky0, mSky1, lensD, lsk, lq);
        lensMoved = distance(sp, uv * float2(W, H)) > 0.5;
        uv = sp / float2(W, H);
        lensOff = any(uv < 0.0) || any(uv > 1.0);
    }

    // Near the hole a full-resolution detail map replaces the half-resolution one,
    // so the photon ring and the lensed disk edges stay crisp.
    float2 bmin = P.box.xy, bmax = P.box.zw;
    bool inBox = P.box.x >= 0.0 && all(uv > bmin) && all(uv < bmax);
    Maps m;
    if (lensOff) {
        m.sky = float4(octEncode(dirOfPx(uv * float2(W, H), P)), 0.0, 0.0);
        m.h1 = float4(1000.0, 1.0, 0.0, 1.0); m.h2 = m.h1; m.c1 = 0.0; m.c2 = 0.0;
    } else {
        m = inBox ? fetchMaps((uv - bmin) / (bmax - bmin), bSky, bD1, bD2)
                  : fetchMaps(uv, tSky, tD1, tD2);
    }
    float4 h1 = m.h1, h2 = m.h2;
    float c1 = m.c1, c2 = m.c2;

    float3 dir = octDecode(m.sky.xy);
    if (nLens > 0) {
        float2 sp = uv * float2(W, H);
        dir = behindChain(holeAfter(dirOfPx(sp, P), dir, lensD), sp, P, lenses, mSky0, mSky1, lsk, lq);
    }
    float wind = m.sky.z * 32.0;
    // Shadow coverage from the capture metric: zero exactly on the edge, so this is
    // an analytic anti-aliased edge rather than a yes/no per texel.
    float cm = (m.sky.w - 0.5) * 0.25;
    float captured = saturate(0.5 + cm / max(fwidth(cm), 1e-6));

    // Which sky objects can show here (see skyMaskFrag). The mouse lens looks elsewhere: all of them.
    float4 neb = float4(tNebFrame.sample(ls, suv));
    uint mask = 0u;
    bool near = P.mouse.z > 0.0 && length(px - P.mouse.xy) < P.mouse.z * 9.0;
    if (P.objA.x > 0.5) {
        if (near) mask = 0xffffffffu >> (32u - uint(P.objA.x + 0.5));
        else if (neb.a > 0.0) mask = tMask.read(uint2(px) / uint(maskCell)).x;
    }
    // How far the sky direction moves per pixel (lensing included), for filtering sky objects.
    // The mask is the same for a whole 8 x 8 cell, so every 2 x 2 quad takes this branch together.
    float3 dirX = mask != 0u ? dfdx(dir) : float3(0.0), dirY = mask != 0u ? dfdy(dir) : float3(0.0);

    float3 bg = neb.rgb;
    if (captured < 0.99) {
        float sd = P.starp.y;
        bg += (starLayer(dir, 420.0, 1.0 - 0.035 * sd, 0.10, t, P)
             + starLayer(dir, 140.0, 1.0 - 0.008 * sd, 0.07, t, P) * 1.5) * P.look.y;
        if (mask != 0u) bg += skyObjects(dir, dirX, dirY, uv, wind, mask, P, skyObjs, tGal, tSky, bSky, 2);
    }
    bg += grad5(0.88, P.pal) * smoothstep(4.2, 7.0, wind) * P.look.w * 0.6;
    // Lenses behind the hole plane: what they show is part of the background, under the disk and the shadow.
    for (int i = 0; i < 2; i++) {
        if (!lensesBehind || i >= nLens) break;
        constant LensObj &L = lenses[i];
        if (L.a.w < 0.5 || any(lq[i] < L.rect.xy) || any(lq[i] > L.rect.zw)) continue;
        bg = L.a.x < 1.5 ? holeLayer(bg, L, lq[i], lsk[i], P, mD10, mD20, mJ0, mS0, mD11, mD21, mJ1, mS1, tDisk, tEdge)
                         : wormLayer(bg, L, lq[i], P, tNeb);
    }
    bg *= 1.0 - captured;

    // Jet: emission behind the first disk crossing goes under the disk, the rest on top.
    float4 jet = float4(0.0);
    float jetSide = ((px.x - P.view.w * W) / min(W, H) - P.jetP.w) * 9.0;   // across the jet, 0 on its axis
    if (P.objA.z > 0.5 && (neb.a > 0.0 || near)) {
        if (inBox) {   // twice the screen resolution: bilinear averages 2 x 2 rays
            float2 juv = (uv - bmin) / (bmax - bmin);
            jet.xy = float2(bJet.sample(ls, juv).xy);
            jet.zw = bJetS.sample(ls, juv).xy;
        } else if (P.qual.x > 0.5) {
            float2 e, sj;
            jetCubic(tJet, tJetS, uv, e, sj);
            jet = float4(e, sj);
        } else {
            jet.xy = float2(tJet.sample(ls, uv).xy);
            jet.zw = tJetS.sample(ls, uv).xy;
        }
        bg += jetLight(jet.y, jet.w, P.jetK.z, jetSide, P, tEdge);
    }

    // Bodies near the hole (path L), sorted against the disk crossings and the shadow.
    float4 bl0 = float4(0.0), bl1 = float4(0.0), bl2 = float4(0.0), bl3 = float4(0.0);
    float2 lpx = uv * float2(W, H);
    bool bodies = P.camP.w > 0.5 && (near || (all(lpx > P.bodyU.xy) && all(lpx < P.bodyU.zw)));
    if (bodies) {
        uint bm = near ? (1u << uint(P.camP.w + 0.5)) - 1u : bodyCandidates(lpx, P, bodyRefs);
        bodies = bm != 0u;
        if (bodies) {
            bodyLayers(lpx, dir, wind, captured, h1, m.c1, h2, m.c2, bm, P, bodyRefs, tBody, bl0, bl1, bl2, bl3);
            bg = bl0.rgb + (1.0 - bl0.a) * bg;
        }
    }

    // Squeeze = how fast disk coordinates change per pixel. Computed here, outside any
    // branch, because fwidth needs every pixel of the quad.
    float sq1 = fwidth(log(clamp(h1.x, 0.5, 200.0))) * 20.0 + length(fwidth(h1.yz)) * 2.0;
    float sq2 = fwidth(log(clamp(h2.x, 0.5, 200.0))) * 20.0 + length(fwidth(h2.yz)) * 2.0;
    float a1, a2;
    float3 col = bg;
    if (lensMoved) {
        // A lens in front magnifies the disk here: leave out gas whose redshift turned negative (rays with
        // 1 + omega L below zero, see diskShade2); magnified, those pixels sparkled magenta.
        c1 *= saturate(h1.w * 50.0); h1.w = max(h1.w, 0.0);
        c2 *= saturate(h2.w * 50.0); h2.w = max(h2.w, 0.0);
    }
    if (c2 > 0.0) {
        float3 e2 = diskShade(h2, sq2, P, tDisk, a2) * c2;
        col = e2 + (1.0 - a2 * c2) * col;
    }
    if (bodies) col = bl1.rgb + (1.0 - bl1.a) * col;
    if (c1 > 0.0) {
        float3 e1 = diskShade(h1, sq1, P, tDisk, a1) * c1;
        col = e1 + (1.0 - a1 * c1) * col;
    }
    if (bodies && bl0.a + bl1.a > 0.0) {
        // Bodies behind a disk crossing went under the gas at its alpha above; take away the part of their
        // light that dense inner gas hides (bodyHidden). Before, a planet behind the inner disk looked like a
        // soap bubble. Here, not in the steps above, so the picture without bodies stays as it was.
        float o2 = c2 > 0.0 ? a2 * c2 : 0.0, o1 = c1 > 0.0 ? a1 * c1 : 0.0;
        float k2 = c2 > 0.0 ? bodyHidden(o2, h2.x, P) : 0.0, k1 = c1 > 0.0 ? bodyHidden(o1, h1.x, P) : 0.0;
        col = max(col - (bl0.rgb * (1.0 - o2) * (1.0 - bl1.a) * (k2 * (1.0 - k1) + k1) + bl1.rgb * k1) * (1.0 - o1), 0.0);
    }
    if (bodies) col = bl2.rgb + (1.0 - bl2.a) * col;
    if (P.objA.z > 0.5) col += jetLight(jet.x, jet.z, P.jetK.y, jetSide, P, tEdge);
    if (bodies) col = bl3.rgb + (1.0 - bl3.a) * col;
    col *= 1.0 - mouseShadow;

    if (P.motion.w > 6.5) {   // debug: object lenses, red: main map off screen, green: a lens bends here, blue: uv
        return dispOut(float4(lensOff ? 1.0 : 0.0, nLens > 0 ? 1.0 : 0.0, fract(uv.x * 4.0), 1.0), float3(0.0));
    }
    if (P.motion.w > 5.5) {   // debug: path L, red candidate region, green lookup inside a box, blue lens weight
        uint bm = P.camP.w > 0.5 ? bodyCandidates(uv * float2(W, H), P, bodyRefs) : 0u;
        float inside = 0.0;
        if (P.camP.w > 0.5) {
            float3 th = dirOfPx(uv * float2(W, H), P);
            float w = bodyRefs[0].geo.x;
            float2 q = w > 0.0 ? pxOfDir(normalize(mix(th, dir, w)), P) : px;
            float4 bx = bodyRefs[0].box;
            inside = (all(q > bx.xy) && all(q < bx.zw)) ? 1.0 : 0.0;
        }
        return dispOut(float4(bm != 0u ? 0.6 : 0.0, inside, bodyRefs[0].geo.x, 1.0), float3(0.0));
    }
    if (P.motion.w > 4.5) {   // debug: jet light alone, tone mapped
        float3 jl = jetLight(jet.x, jet.z, P.jetK.y, jetSide, P, tEdge) + jetLight(jet.y, jet.w, P.jetK.z, jetSide, P, tEdge);
        return dispOut(float4(pow(aces(jl * P.look.x), float3(1.0 / 2.2)), 1.0), float3(0.0));
    }
    if (P.motion.w > 3.5) {   // debug: sky object mask, number of candidate objects per cell
        return dispOut(float4(float(popcount(mask)) * 0.25, neb.a, 0.0, 1.0), float3(0.0));
    }
    if (P.motion.w > 2.5) {   // debug: jet emission, log scale: in front of the disk red, behind green, shadow blue
        return dispOut(float4(saturate(log2(1.0 + jet.x) / 6.0), saturate(log2(1.0 + jet.y * 30.0) / 8.0), captured * 0.3, 1.0), float3(0.0));
    }
    if (P.motion.w > 1.5) { return dispOut(float4(fract(dir * 42.0), 1.0), float3(0.0)); }
    if (P.motion.w > 0.5) {   // debug: r of first/second hit, captured in blue
        return dispOut(float4(saturate(h1.x / 20.0) * c1, saturate(h2.x / 20.0) * c2, captured, 1.0), float3(0.0));
    }
    // Soft light drawn forward (star glows, comet tails, dust), at half resolution, inside its rectangle only.
    if (P.camU.w > 0.5 && all(px > P.lightU.xy) && all(px < P.lightU.zw)) col += tLight.sample(ls, (px - P.lightU.xy) / (P.lightU.zw - P.lightU.xy)).rgb;
    float3 lin;
    float4 fin = finishPixel(col, px, P, tEdge, P.nebp.w > 0.5 ? 1 : 0, lin);
    return dispOut(fin, lin);
}

// Strips along the bars in edges-only mode. tBase holds what dispFrag computed there
// before the bands (darkening already applied), so only the moving light is new.
fragment DispOut edgeFrag(VOut in [[stage_in]], constant FrameParams &P [[buffer(0)]],
                         texture2d<float> tEdge [[texture(9)]],
                         texture2d<half> tBase [[texture(10)]]) {
    float2 px = mix(P.region.xy, P.region.zw, in.uv) * P.view.xy;
    float3 col = float3(tBase.read(uint2(in.pos.xy)).rgb);
    float3 lin;
    return dispOut(finishPixel(col, px, P, tEdge, 2, lin), col);
}
"""#
