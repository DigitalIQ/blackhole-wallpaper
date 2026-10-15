// Black Hole Wallpaper: Seite. Keine Anfragen an fremde Server, kein Speicher im Browser.
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
const plate = document.getElementById("plate");
// Das Loch lädt erst nach dem Standbild, damit die Seite sofort steht
if (plate && !reduced) {
  const go = () => import("./blackhole.js").then(({ mountBlackHole }) => {
    const narrow = matchMedia("(max-width: 860px)").matches;
    mountBlackHole(plate, { palette: "gargantua", pitch: 0.09, dist: narrow ? 30 : 34, label: plate.dataset.label });
  });
  const idle = () => ("requestIdleCallback" in window ? requestIdleCallback(go, { timeout: 1500 }) : setTimeout(go, 200));
  document.readyState === "complete" ? idle() : addEventListener("load", idle, { once: true });
}

// Auf Touch-Geräten heißt der Hinweis anders
if (matchMedia("(pointer: coarse)").matches) {
  for (const el of document.querySelectorAll("[data-touch]")) el.textContent = el.dataset.touch;
}

// Befehl kopieren
for (const b of document.querySelectorAll("[data-copy]")) {
  b.addEventListener("click", async () => {
    const k = b.querySelector(".k");
    try {
      await navigator.clipboard.writeText(b.dataset.copy);
      k.textContent = b.dataset.done;
    } catch {
      const r = document.createRange(); r.selectNodeContents(b.querySelector("code"));
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    }
    setTimeout(() => { k.textContent = b.dataset.label; }, 2400);
  });
}

// Film: stumm, spielt nur ohne reduzierte Bewegung und nur sichtbar von selbst
const video = document.getElementById("promo");
const play = document.getElementById("play");
if (video) {
  const start = () => { video.controls = true; play.hidden = true; video.play().catch(() => {}); };
  play.addEventListener("click", start);
  if (!reduced) {
    new IntersectionObserver(([e]) => {
      if (e.isIntersecting) { video.preload = "auto"; play.hidden = true; video.play().catch(() => { play.hidden = false; }); }
      else if (!video.paused) video.pause();
    }, { threshold: 0.4 }).observe(video);
  }
}
