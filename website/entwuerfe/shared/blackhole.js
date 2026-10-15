// Interaktives Schwarzes Loch für die Website (Entwurf, Phase 4).
// Leichte Fassung der App: Schwarzschild statt Kerr, Lichtstrahlen werden in der
// Ebene mit der Binet-Beschleunigung -3/2 * h^2 * p / r^5 integriert (rs = 1).
// Scheibe ab der ISCO (r = 3), Kepler-Drehung, Doppler-Aufhellung, gebogener Himmel.
// Ohne WebGL oder bei prefers-reduced-motion bleibt das Standbild stehen.
import * as THREE from "./vendor/three.module.min.js";

const frag = /* glsl */ `
precision highp float;
uniform vec2 uRes;
uniform float uTime;
uniform vec3 uCam;      // yaw, pitch, distance
uniform vec3 uHot, uMid, uWarm, uCool, uNebA, uNebB, uNebC;
uniform float uNeb;     // Nebelstärke
uniform vec2 uOff;      // Lage des Lochs im Bild
uniform vec3 uRamp;     // Übergänge der Scheibenfarben
varying vec2 vUv;

float hash(vec3 p){ p = fract(p*0.3183099+.1); p*=17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float noise(vec3 x){
  vec3 i = floor(x); vec3 f = fract(x); f = f*f*(3.0-2.0*f);
  return mix(mix(mix(hash(i+vec3(0,0,0)),hash(i+vec3(1,0,0)),f.x),
                 mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
             mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),
                 mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p){ float a=.5, s=0.; for(int i=0;i<4;i++){ s+=a*noise(p); p*=2.03; a*=.5; } return s; }

vec3 sky(vec3 d){
  // Nebel: drei Töne aus der App-Palette, schwach
  // Wirbel um die Drehachse wie der Strudel der App
  float az = atan(d.z, d.x) + 1.5*d.y + uTime*0.01;
  vec3 w = vec3(cos(az), d.y*2.0, sin(az));
  float n1 = fbm(w*1.8 + 3.1);
  float n2 = fbm(w*3.6 + d*2.0 + 7.3);
  vec3 neb = uNebA*smoothstep(.40,.85,n1)*.9 + uNebB*smoothstep(.45,.9,n2)*1.2 + uNebC*smoothstep(.62,.9,n1*n2*1.7)*.7;
  // Sterne
  vec3 g = d*220.0; vec3 c = floor(g); float h = hash(c);
  float star = step(.985, h) * smoothstep(.5, .0, length(fract(g)-.5)) * (h-.985)*60.0;
  return neb*uNeb + vec3(star);
}

vec3 diskColor(float r, float t){
  // innen heiß, außen kühl
  float x = clamp((r-3.0)/9.0, 0.0, 1.0);
  vec3 c = mix(uHot, uMid, smoothstep(0.0, uRamp.x, x));
  c = mix(c, uWarm, smoothstep(uRamp.x*.8, uRamp.y, x));
  c = mix(c, uCool, smoothstep(uRamp.y*.9, uRamp.z, x));
  return c;
}

void main(){
  vec2 uv = (vUv - .5) * vec2(uRes.x/uRes.y, 1.0) - uOff;
  float yaw = uCam.x, pitch = uCam.y, dist = uCam.z;
  vec3 ro = dist * vec3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch));
  vec3 fw = normalize(-ro);
  vec3 rt = normalize(cross(fw, vec3(0,1,0)));
  vec3 up = cross(rt, fw);
  // leichte Neigung wie in der App
  float roll = -0.12; vec2 ur = mat2(cos(roll),-sin(roll),sin(roll),cos(roll))*uv;
  vec3 v = normalize(fw*1.25 + rt*ur.x + up*ur.y);
  vec3 p = ro;
  vec3 hv = cross(p, v); float h2 = dot(hv, hv);

  vec3 col = vec3(0); float tr = 1.0;
  for(int i=0;i<260;i++){
    float r = length(p);
    float dt = clamp(0.045*r*smoothstep(1.0,4.0,r) + 0.012, 0.012, 1.2);
    vec3 pp = p;
    v += -1.5*h2*p/pow(r,5.0)*dt;
    p += v*dt;
    if(pp.y*p.y < 0.0){
      float k = pp.y/(pp.y-p.y); vec3 q = mix(pp,p,k); float rq = length(q.xz);
      if(rq>3.0 && rq<12.0){
        float ang = atan(q.z,q.x);
        float om = pow(rq,-1.5)*1.6;
        float sw = ang + uTime*om;
        float streaks = fbm(vec3(cos(sw)*rq*.9, sin(sw)*rq*.9, rq*1.7));
        float rings = .7+.3*sin(rq*4.0 + streaks*6.0);
        float dens = smoothstep(3.0,3.6,rq)*smoothstep(12.0,6.0,rq)*(.35+.9*streaks*rings)*(1.0+1.6*exp(-(rq-3.0)*1.1));
        vec3 tang = normalize(vec3(-q.z,0.0,q.x));
        float beam = pow(clamp(1.0 + .75*dot(tang, -normalize(v)), .25, 2.0), 2.6);
        float grav = sqrt(clamp(1.0-1.0/rq, 0.0, 1.0));
        vec3 dc = diskColor(rq, uTime)*dens*beam*grav*2.6;
        float a = clamp(dens*.9, 0.0, 1.0);
        col += tr*dc; tr *= 1.0-a;
      }
    }
    if(r < 1.0){ tr = 0.0; break; }
    if(r > dist*1.6 && dot(p,v) > 0.0) break;
    if(tr < .02) break;
  }
  col += tr*sky(normalize(v));
  col = 1.0 - exp(-col*1.25);           // weiches Abrollen statt Ausbrennen
  col = pow(col, vec3(.92));
  gl_FragColor = vec4(col, 1.0);
}`;

const vert = /* glsl */ `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const PALETTES = {
  strudel: { hot:"#FFE0A0", mid:"#FF7A1F", warm:"#D23A78", cool:"#6A1B7A", a:"#3A4DD8", b:"#6A1B7A", c:"#2FC6D8", neb:1.8, ramp:[.08,.3,.8] },
  gargantua: { hot:"#FFF4E0", mid:"#F2A04A", warm:"#B8561A", cool:"#5A2A0C", a:"#2A3550", b:"#5A2A0C", c:"#8FA8C8", neb:.35, ramp:[.25,.6,1.0] },
};

export function mountBlackHole(host, opts = {}) {
  const still = host.querySelector("img");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || opts.forceStill) return { still: true };
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: "low-power" });
  } catch (e) { return { still: true }; }
  if (!renderer.getContext()) return { still: true };

  const pal = PALETTES[opts.palette || "strudel"];
  const col = (h) => new THREE.Color(h).convertSRGBToLinear();
  const uniforms = {
    uRes: { value: new THREE.Vector2(1, 1) }, uTime: { value: 0 },
    uCam: { value: new THREE.Vector3(opts.yaw ?? 0.0, opts.pitch ?? 0.10, opts.dist ?? 24) },
    uHot: { value: col(pal.hot) }, uMid: { value: col(pal.mid) }, uWarm: { value: col(pal.warm) }, uCool: { value: col(pal.cool) },
    uNebA: { value: col(pal.a) }, uNebB: { value: col(pal.b) }, uNebC: { value: col(pal.c) }, uNeb: { value: pal.neb }, uRamp: { value: new THREE.Vector3(...pal.ramp) }, uOff: { value: new THREE.Vector2(...(opts.offset || [0, 0])) },
  };
  const scene = new THREE.Scene();
  const cam = new THREE.Camera();
  scene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({ vertexShader: vert, fragmentShader: frag, uniforms })));
  const canvas = renderer.domElement;
  canvas.setAttribute("aria-hidden", "true");
  host.appendChild(canvas);
  host.classList.add("is-live");

  // Auflösung: halbe Pixeldichte, reicht für Nebel und Scheibe, schont das MacBook Air
  let scale = opts.scale ?? 0.5;
  function resize() {
    const w = host.clientWidth, h = host.clientHeight;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2) * scale);
    renderer.setSize(w, h, false);
    canvas.style.width = w + "px"; canvas.style.height = h + "px";
    uniforms.uRes.value.set(w, h);
  }
  resize(); new ResizeObserver(resize).observe(host);

  const base = uniforms.uCam.value.clone();
  const target = base.clone();
  window.addEventListener("pointermove", (e) => {
    const nx = e.clientX / innerWidth - .5, ny = e.clientY / innerHeight - .5;
    target.x = base.x + nx * 0.5;
    target.y = Math.max(0.03, base.y - ny * 0.35);
  }, { passive: true });
  if (opts.scrollZoom) window.addEventListener("scroll", () => {
    const k = Math.min(1, scrollY / innerHeight);
    target.z = base.z * (1 - 0.35 * k);
  }, { passive: true });

  let visible = true, t0 = performance.now(), last = 0;
  new IntersectionObserver(([en]) => { visible = en.isIntersecting; }).observe(host);
  const fps = opts.fps ?? 30;
  function frame(now) {
    requestAnimationFrame(frame);
    if (!visible || document.hidden) return;
    if (now - last < 1000 / fps - 2) return;
    last = now;
    const c = uniforms.uCam.value;
    c.x += (target.x - c.x) * .06; c.y += (target.y - c.y) * .06; c.z += (target.z - c.z) * .06;
    uniforms.uTime.value = opts.time ?? (now - t0) / 1000 + 20;
    renderer.render(scene, cam);
  }
  requestAnimationFrame(frame);
  if (still) still.setAttribute("aria-hidden", "true");
  return { still: false };
}
