# DESIGN: Black Hole Wallpaper, Missionsakte

Aus der gebauten Seite abgeleitet (2026-10-13), nicht aus Absichten. Quelle der Werte: `assets/css/site.css`.

## Idee

Die Seite ist das technische Datenblatt der App. Belege stehen als Bildplatten mit Abbildungsnummer („Fig. 1“ bis „Fig. 8“), Leitlinien und Messwerten. Die fließenden Bänder der App laufen als Linien durch das Blatt.

## Farben

| Token | Wert | Einsatz |
|---|---|---|
| `--paper` | `#E4E6EA` | Grund |
| `--paper-2` | `#D5D9DF` | getönte Abschnitte (Mac, Fragen) |
| `--ink` | `#0B0A10` | Text, Linien, Fuß |
| `--ink-2` | `#3A3846` | Nebentext |
| `--spot` | `#FF7A1F` | Download-Felder, Abschnitt Objekte, Warnschritt, Balken |
| `--plate` | `#050308` | Bildplatten, dunkle Abschnitte (Physik, Film) |
| `--on-plate` / `--on-plate-2` | `#F3EDE6` / `#B9B2C4` | Text auf Platte |
| Bänder | `#FF7A1F #D23A78 #FFE0A0 #2FC6D8 #3A4DD8` | 2 px Verlauf, fließt in 16 s |

Orange ist Fläche oder Linie, nie Text auf hellem Grund.

## Schrift

Archivo (Variable, `wdth` 62 bis 125, `wght` 100 bis 900), selbst gehostet. Titel: 125 % Breite, 800, Versalien, Laufweite -0,035em. Etiketten: 112 %, 700, Versalien, +0,08em. Text: 100 %, 16 bis 18 px. Befehle: System-Monospace.

## Formen

- Linien 2 px schwarz, Trennlinien in Listen 1 px.
- Bildplatte: 2 px Rahmen, schwarze Fläche, Bildunterschrift-Leiste auf Papier mit „Fig. n“.
- Knöpfe: rechteckig, 2 px Rahmen, Orange, Hover kehrt zu Schwarz mit orangem Text.
- Abläufe: nummerierte Kästchen an einer senkrechten Linie, Warnschritt orange.
- Keine Rundungen, keine Schatten, keine Etiketten über Überschriften.

## Rhythmus

Einstieg (Papier), Spezifikation, Physik (Platte), Voreinstellungen (Papier), Objekte (Orange), Mac (getönt), Film (Platte), Installieren (Papier), Fragen (getönt), Fuß (Tinte). Bänder trennen Kopf, Spezifikation, Physik, Film und Fuß.

## Bewegung

Das Loch in Fig. 1 (three.js, `assets/js/blackhole.js`), die fließenden Bänder, der Film. Sonst nichts. Bei `prefers-reduced-motion` stehen Bänder und Loch, der Film wartet auf Klick.

## Bilder und Herkunft

Alle Bilder sind Renderings der App (`BlackHoleWallpaper --snapshot`) oder Prüfbilder aus `shots/`:

| Datei | Quelle |
|---|---|
| `preset-*.webp/.jpg` | `--snapshot --size 3440x1440 --preset <id> --top 24 --bottom 70 --time 20` |
| `hero-still` | Gargantua wie oben, Ausschnitt 1900 x 1440 |
| `fig-close` | `shots/stufe3-loch-nah.png` |
| `fig-ring` | `shots/objekte/stufe1/s1-ring.png`, Ausschnitt |
| `fig-planet` | `shots/objekte/stufe2/s2-planet-hinten.png`, Ausschnitt |
| `obj-ships` | `shots/objekte/stufe3/s3-szene-ultrawide.png`, Ausschnitt |
| `obj-wormhole`, `obj-second`, `obj-planet` | `shots/objekte/stufe4/s4-wurmloch.png`, `s4-zweites-loch-jet.png`, `shots/objekte/stufe2/s2-erde-nah.png` |
| `og.jpg` | `werkzeuge/og.html`, mit Playwright aufgenommen |
| Favicons, `icon-64.png` | `Design/Icon/AppIcon.png` |
| `assets/film/*` | siehe `film-plan.md` |
