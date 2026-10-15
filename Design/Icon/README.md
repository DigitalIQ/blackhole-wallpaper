# Logo

App-Symbol (Variante 1) und Menüleisten-Symbol (Variante A) für Schwarzes Loch.

## Was wo liegt

- `AppIcon.png`: App-Symbol, 1024 x 1024 px. Ausschnitt aus einem Gargantua-Render auf einer Apple-Kachel.
- `AppIcon.icns`: dasselbe als Symbol-Datei mit allen Größen von 16 bis 1024 px. `scripts/build-app.sh` legt sie ins App-Bundle.
- `MenuBarTemplate.png` und `MenuBarTemplate@2x.png`: Menüleisten-Symbol, 18 pt, Schwarz mit Alpha als Template-Bild. macOS färbt es je nach hellem oder dunklem Modus.
- `varianten.png` und `menueleiste.png`: Übersichten der vier App-Symbole und der drei Menüleisten-Entwürfe. Sie belegen die Auswahl: Variante 1 und A.
- `iconkit.swift`: zeichnet App-Symbol und Menüleisten-Symbol.
- `render.sh`: rendert das Rohbild mit der gebauten App (`.build/release/BlackHoleWallpaper`) nach `work/renders/`.
- `build.sh`: baut alles neu.

## Neu bauen

```bash
./Design/Icon/build.sh
```

Das rendert bei Bedarf das Rohbild, baut `iconkit` und schreibt die vier Dateien oben neu. Zwischenstände liegen in `work/` und sind nicht im Repository. Danach `./scripts/install.sh`, damit die App das neue Symbol bekommt.

Die verworfenen Entwürfe (Varianten 2 bis 4, B und C) gibt es nur noch als Bild in den Übersichten. Ihr Code ist entfernt.
