# Website-Status

Diese Datei hält fest, wo das Projekt steht. Der Skill `website-bauen` liest sie bei jedem Aufruf und macht dort weiter.

Status: ✅ erledigt · 🔄 läuft · ⬜ offen

| Phase | Name | Status | Datum |
|---|---|---|---|
| 0 | Einrichten | ✅ | 2026-10-13 |
| 1 | Fundament | ✅ | 2026-10-13 |
| 2 | Recherche | ✅ | 2026-10-13 |
| 3 | Texte | ✅ | 2026-10-13 |
| 4 | Design-Richtung | ✅ A Missionsakte, mit Bändern aus B | 2026-10-13 |
| 5 | Bauen | ✅ | 2026-10-13 |
| 6 | Prüfen und Feinschliff | 🔄 geprüft, Abnahme durch die Person offen | 2026-10-13 |
| 7 | Livegang | 🔄 Technik fertig, Pages noch nicht eingeschaltet | 2026-10-13 |
| 8 | Danach | ⬜ | |

Abweichung vom Skill: Der Auftrag gab die Phasen 0 bis 4 in einem Auftrag vorgegeben, ohne Abnahme zwischen den Phasen. Die Abnahmen der Phasen 1 bis 4 kommen gesammelt.

## Ausgangslage

- Bestehende Website oder Marke: Marke da (App, App-Symbol, Menüleisten-Symbol, Paletten der App), keine Website.
- Hauptziel der Seite: Leute verstehen die App, staunen und laden sie herunter.
- Hosting: GitHub Pages aus dem Ordner `website/` im Repo `DigitalIQ/blackhole-wallpaper`, statisch, ohne Build-Server.
- Werkzeuge: impeccable ✅ (projektlokal unter `.claude/skills/impeccable`, v4.1.1, v4.5.2 wäre verfügbar) · Playwright ✅ (projektlokal in `.tmp/website/tools`, nutzt das installierte Chrome) · DataForSEO ✖ bewusst nicht · Hosting-MCP ✖ entfällt (GitHub Pages) · Formular-Ziel ✖ entfällt (kein Formular)
- Weitere: three.js 0.170 (selbst gehostet), HyperFrames 0.8.152 (projektlokal in `.tmp/website/hf`), Schriften über Fontsource-Pakete, selbst gehostet.

## Marke

Aus `Sources/BlackHoleWallpaper/Settings.swift` (Palette „Strudel“) und `Design/Icon/`, nicht geschätzt.

| Rolle | Wert |
|---|---|
| Hauptfarbe | fast Schwarz, Nebel `#1A0633` |
| Akzent | Orange `#FF7A1F`, Magenta `#D23A78` |
| weitere | Violett `#6A1B7A`, Gold `#FFE0A0`, Türkis `#2FC6D8`, Blau `#3A4DD8` |
| helle Fläche | keine in der App; Richtung A nutzt Datenblatt-Grau `#E4E6EA` |
| Text | hell auf dunkel |
| Überschriften | keine Markenschrift festgelegt; A: Archivo (Breitenachse), B: Bricolage Grotesque |
| Fließtext | A: Archivo, B: Hanken Grotesk |
| Merkmale | Gargantua-Render als App-Symbol, Ring mit Querstrich als Menüleisten-Symbol, leuchtende Bänder an Menüleiste und Dock |

## Entscheidungen

- 2026-10-13: Richtung A „Missionsakte“, die fließenden Bänder aus B als Linien. Phasen 1 bis 4 freigegeben.
- 2026-10-13: Englische Namen der Voreinstellungen wie in der App: Swirl, Gargantua, M87* as photographed, Top View, Ice Blue, Star System, Sci-Fi Harbor (ID der letzten: `scifi`).
- 2026-10-13: Keine eigene Domain, Seite unter `https://digitaliq.github.io/blackhole-wallpaper/`.
- 2026-10-13: Download-Knöpfe auf `releases/latest`, dort später eine .dmg.
- 2026-10-13: Film ohne Musik, MP4 und WebM mit Poster, Autoplay nur ohne reduzierte Bewegung.
- 2026-10-13: Kein Impressum. Fuß: „Made by DigitalIQ“, MIT, Link zum Repo.

- 2026-10-13 (Auftrag): Englisch Hauptsprache, Deutsch unter `/de/`, Du-Form, keine Gedankenstriche, keine Emojis.
- 2026-10-13 (Auftrag): Kein Tracking, keine Cookies, keine fremden Anfragen, kein Formular, keine AGB.
- 2026-10-13 (Auftrag): Blickfang mit three.js, Standbild bei `prefers-reduced-motion` und ohne WebGL. Promo-Film mit HyperFrames.
- 2026-10-13 (Auftrag): Autor nur „DigitalIQ“, kein Name, keine Adresse, kein Bezug zu Firmen.

## Dateien

- `PRODUCT.md`: Produkt-Kontext für impeccable
- `referenzen/notizen.md`, `recherche/keywords-geo.md`, `recherche/wettbewerber.md`
- `texte.md`: alle Texte EN und DE
- `film-plan.md`: Plan für den Promo-Film, Ergebnis der HyperFrames-Probe
- `richtungen.md`: sieben Kandidaten, Los, zwei Richtungen, Empfehlung
- `entwuerfe/index.html`: Auswahlseite; `entwuerfe/a-missionsakte/`, `entwuerfe/b-schreibtisch/`, `entwuerfe/shared/` (Shader, Schriften, Bilder), `entwuerfe/bilder/` (Screenshots)

Lokal ansehen: `cd website && python3 -m http.server 8765`, dann `http://localhost:8765/entwuerfe/`.

## Prüfung (2026-10-13, zwei Durchgänge)

- Lighthouse 12 (lokal mit gzip wie GitHub Pages): Handy 96 / 100 / 100 / 100 (Leistung, Barrierefreiheit, Best Practices, SEO), LCP 2,9 s, CLS 0, TBT 0 ms. Desktop 100 / 100 / 100 / 100, LCP 0,6 s. Deutsch gleich.
- Übertragung beim Laden: etwa 0,6 MB (Handy) bis 0,7 MB (Desktop), three.js wird erst nach dem Laden nachgeholt.
- Loch: hält 30 Bilder pro Sekunde (33,9 ms) bei halber Pixeldichte, gemessen in Chrome mit Metal auf Apple M4, 1440 x 900 und 390 x 844. Nicht auf einem MacBook Air gemessen. Fällt die Rate zweimal in Folge, sinkt die Auflösung bis 30 %.
- Desktop 1440, Tablet 820, Handy 390, Englisch, Deutsch, 404: kein seitliches Scrollen, keine Konsolenfehler, keine fehlenden Dateien, keine Anfragen an fremde Server, alle Bilder mit Alt-Text.
- Reduzierte Bewegung und ohne WebGL: Standbild bleibt, Film wartet auf Klick.
- Hell und dunkel: Die Seite hat bewusst nur das helle Datenblatt (`color-scheme: light`).
- `impeccable detect` lief nur eingeschränkt (Parser-Module fehlen), ohne Befund. Die Abnahme mit dem Agenten `impeccable-finish-reviewer` ist laut Auftrag entfallen; eigene Prüfung nach `craft-floor.md` und `phasen/6-pruefen.md`.

Screenshots: `pruefung/desktop.jpg`, `pruefung/handy.jpg`, `pruefung/desktop-ganz.jpg`.

## Lokal ansehen

`.tmp/website/site.sh` stellt dieselben Dateien zusammen wie der Workflow. Danach `cd .tmp/website/serve && python3 -m http.server 8766` und `http://localhost:8766/blackhole-wallpaper/` öffnen. Texte ändern: `website/werkzeuge/build.py` und `texte.md`, dann `python3 website/werkzeuge/build.py`.

## Offene Fragen an die Person

1. Abnahme der Seite (Phase 6).
2. Pages einschalten: Repo öffentlich machen, unter Settings, Pages die Quelle „GitHub Actions“ wählen. Der Workflow `.github/workflows/pages.yml` liegt bereit.
3. Im Repo fehlt eine `LICENSE`-Datei. Der Fuß verlinkt deshalb auf den MIT-Text bei opensource.org.
4. Prozessoren (nur Apple Silicon?) sind weiter nicht belegt, die Seite nennt nur macOS 15.

## Update-Ablauf nach dem Livegang

1. Änderung in der Seite und in `texte.md`
2. Kein Build-Schritt (statische Seite)
3. Upload: Commit und Push, GitHub Pages veröffentlicht aus `website/`
4. Cache leeren: entfällt
5. Live prüfen

2026-10-13: Texte aktualisiert (Branch website-texte): glTF/GLB statt "geplant", Qualitätsstufen, echtere Bewegung und App-Sprachen in Objekte- und Mac-Abschnitt und FAQ (EN und DE), `build.py`, `texte.md` und `llms.txt` gleichgezogen.
Nachtrag: Bewegung als eigener Block "Motion" im Objekte-Abschnitt, Silbentrennung für h1 und h2 (kein seitliches Scrollen bei 360 und 390 px).
