# Plan: Promo-Film

Stand 2026-10-13. Länge 26 Sekunden, 1920 x 1080 und eine Hochkant-Fassung 1080 x 1920 für Handys. Ohne Ton (entschieden 2026-10-13).

## Werkzeug

HyperFrames von HeyGen, Version 0.8.152 (npm, Stand 2026-10-13), Apache-2.0. Quelle: README im Repo `heygen-com/hyperframes`. Eine Komposition ist eine HTML-Datei mit `data-start`, `data-duration` und einer pausierten GSAP-Zeitleiste in `window.__timelines`. `npx hyperframes render` macht daraus ein MP4 über Chrome und ffmpeg.

Installiert nur projektlokal in `.tmp/website/hf/` (`npm i hyperframes@0.8.152`), nichts global. Telemetrie aus mit `HYPERFRAMES_NO_TELEMETRY=1` und `DO_NOT_TRACK=1`. `HYPERFRAMES_SKIP_SKILLS=1`, damit `init` keine Agenten-Skills nachlädt. GSAP liegt als Datei neben der Komposition, damit beim Rendern nichts aus dem Netz kommt.

## Probe

`.tmp/website/hf/probe/index.html`: 4 Sekunden, ein echtes Rendering der App (Gargantua) zoomt langsam auf, Titel und Unterzeile blenden ein. `hyperframes lint`: 0 Fehler, 0 Warnungen. `hyperframes render`: 1920 x 1080, 30 Bilder pro Sekunde, 4,0 s, 2,1 MB, gerendert in 8,5 s. Ergebnis `.tmp/website/hf/probe.mp4` (nicht im Repo).

## Bewegtbild aus der App

Die App rendert Standbilder mit `--snapshot ... --time t`. Für Bewegung eine Bildfolge rendern (30 Bilder pro Sekunde, `--time` in Schritten von 1/30 s), mit ffmpeg zu kurzen Clips machen und in HyperFrames als `<video>` einsetzen. Text, Schnitte und Übergänge macht HyperFrames, das Loch selbst kommt immer aus der App.

## Ablauf

| Zeit | Bild (immer aus der App) | Text EN | Text DE |
|---|---|---|---|
| 0 bis 4 s | Schwarz, der Photonenring von Gargantua blendet auf, die Scheibe dreht sich | | |
| 4 bis 9 s | Dein Strudel als ganzer Schreibtisch mit Bändern an Menüleiste und Dock | Your desktop, bent by a black hole. | Dein Schreibtisch, gebogen von einem Schwarzen Loch. |
| 9 bis 14 s | Galaxie wandert hinter das Loch und schließt sich zum Einstein-Ring (`--add galaxy:spiral:az=…`) | Every pixel follows a ray of light. | Jeder Pixel folgt einem Lichtstrahl. |
| 14 bis 19 s | Schnelle Schnitte: Ringplanet taucht hinter der Scheibe ab, Komet, Schiff mit Warp-Ereignis, Wurmloch | Add things. The hole bends them. | Stell etwas dazu. Das Loch biegt es. |
| 19 bis 22 s | Die sieben Voreinstellungen als Raster, eine nach der anderen | Seven presets. Then your own. | Sieben Voreinstellungen. Dann deine eigene. |
| 22 bis 26 s | App-Symbol, Brew-Befehl, Adresse | Free and open source. macOS 15 or later. | Frei und quelloffen. Ab macOS 15. |

Schrift im Film: dieselbe wie auf der gewählten Website-Richtung, als Datei eingebunden.

## Offen

- Musik ja oder nein. Ohne Musik ist der Film leiser, aber nichts muss lizenziert werden.
- Die Adresse im Endbild hängt an der Domain-Entscheidung.

## Ergebnis (2026-10-13)

- Komposition: `.tmp/website/hf/promo/index.html` (nicht im Repo, Quelle der Bildfolgen: `.tmp/website/film/frames.sh`). Abweichung vom Plan: 9 bis 14 s zeigt statt der wandernden Galaxie M87* mit langsamem Zoom und dem Satz „Computed live in Metal“. Die Galaxie verschwand hinter der hellen Scheibe von Gargantua; für einen Einstein-Ring im Film braucht es eine eigene Szene mit dunkler Scheibe.
- Bildfolgen aus der App: 595 Bilder bei 1920 x 1080, je etwa 1,7 s.
- Master 1920 x 1080, 30 Bilder pro Sekunde, 26,0 s, gerendert in 26,5 s.
- Auf der Seite: `assets/film/promo.mp4` (H.264, 1600 x 900, 3,9 MB), `assets/film/promo.webm` (VP9, 1600 x 900, 2,1 MB), `assets/film/poster.jpg` (bei 6,5 s).
