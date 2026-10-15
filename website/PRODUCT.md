# Product

<!-- impeccable:product-schema 1 -->

Quelle: Auftrag vom 2026-10-13, `README.md`, `docs/objekte-plan.md`, `Sources/BlackHoleWallpaper/Settings.swift`. Es gab keine Interview-Runde; was nur aus dem Auftrag abgeleitet ist, steht als „(abgeleitet)“ da.

## Platform

web

## Stack

Statische Seite ohne Build-Server, gehostet über GitHub Pages aus dem Ordner `website/` im Repo `DigitalIQ/blackhole-wallpaper`. Kein Framework. three.js als einzige größere Bibliothek, selbst gehostet. Schriften selbst gehostet. Keine Anfragen an fremde Server, kein Tracking, keine Cookies, kein Formular.

## Users

Mac-Nutzer, die ihren Schreibtisch schön haben wollen und sich für Raumfahrt, Physik oder Science-Fiction begeistern (abgeleitet). Sie landen meist über einen geteilten Link, GitHub, Homebrew, Reddit oder eine Suche nach „black hole wallpaper mac“ auf der Seite (abgeleitet). Sie wissen beim Ankommen nicht, dass die Lichtbiegung echt gerechnet wird. Sie wollen in Sekunden sehen, wie es aussieht, und dann wissen, wie sie es installieren.

Zweite Gruppe: Entwickler und Physik-Interessierte, die den Code lesen und wissen wollen, was echt ist und was künstlerisch (abgeleitet).

## Product Purpose

Black Hole Wallpaper (deutsch „Schwarzes Loch“) ist ein animierter Schreibtisch-Hintergrund für macOS: ein drehendes Kerr-Schwarzes-Loch, bei dem jeder Pixel einem Lichtstrahl durch die Raumzeit folgt, gerechnet in Metal. Die Website soll drei Dinge erreichen, in dieser Reihenfolge: Leute verstehen die App, staunen, laden sie herunter.

Erfolg: Download über GitHub Releases oder Homebrew.

## Positioning

Andere „Black Hole Wallpaper“ für den Mac sind Videoschleifen aus Wallpaper-Bibliotheken. Diese App rechnet das Loch live: Kerr-Metrik, Hamilton-Gleichungen, RK4, Photonenring, Scheibe ab der ISCO mit Doppler-Aufhellung. Objekte am Himmel (Galaxien, Planeten, Schiffe) werden vom Loch echt gebogen, bis zum Einstein-Ring. Dazu ist sie frei und quelloffen (MIT). Die README trennt ehrlich, was echt ist und was künstlerisch: die Farben sind künstlerisch.

## Operating Context

- Läuft als Menüleisten-App, ein Fenster pro Bildschirm auf Schreibtisch-Ebene, dazu ein Bildschirmschoner.
- Mindestens macOS 15 (`Package.swift`, `LSMinimumSystemVersion`).
- Installation: Download aus `https://github.com/DigitalIQ/blackhole-wallpaper/releases/latest` oder mit Homebrew: `brew tap digitaliq/tap`, `brew trust --tap digitaliq/tap`, `brew install --cask blackhole-wallpaper`.
- Nicht von Apple notarisiert: beim ersten Start in Systemeinstellungen > Datenschutz & Sicherheit „Trotzdem öffnen“ klicken oder `xattr -dr com.apple.quarantine` ausführen. Rechtsklick > Öffnen hilft seit macOS 15 nicht mehr.
- Netzwerk: Die App spricht nur mit api.github.com und den Download-Servern von GitHub, um nach Updates zu suchen und sie zu laden. Abschaltbar.
- Repo heute privat, wird bald öffentlich.

## Capabilities and Constraints

Belegt im README:
- Sieben Voreinstellungen: Dein Strudel, Gargantua, M87* wie auf dem Foto, Draufsicht, Eisblau, Sternsystem, SciFi-Hafen.
- Leuchtende Bänder an Menüleiste und Dock.
- Animation in drei Stufen: Alles, Nur Ränder, Aus. Pause im Energiesparmodus und bei verdecktem Schreibtisch.
- Monitor-Auswahl, eigene Voreinstellung pro Schirm.
- Bildschirmschoner, Standbild als echter Hintergrund für Sperrbildschirm und Mission Control.
- Maus-Modus: eine kleine Linse folgt dem Zeiger.
- Objekte: Galaxien (Einstein-Ringe), ferne und nahe Sterne, Jet, Planeten, Monde, Asteroiden und Gürtel, Kometen und Meteore, Raumschiffe und Stationen aus vielen Science-Fiction-Welten, zweites Schwarzes Loch, Wurmloch, Tore.
- Eigene 3D-Modelle: OBJ, USDZ, USD, PLY, STL. glTF ist angekündigt („bald“), nicht als vorhanden darstellen.
- Messwerte (MacBook Air M4, 3440 x 1440): 1,7 bis 2,6 ms GPU-Zeit pro Bild bei „Alles“, 0,12 bis 0,14 ms bei „Nur Ränder“. 30 Bilder pro Sekunde als Standard.

Offen: unterstützte Prozessoren (Apple Silicon und Intel) sind nicht belegt.

## Brand Commitments

- Name: „Black Hole Wallpaper“, auf Deutsch „Schwarzes Loch“.
- App-Symbol: Gargantua schräg von der Seite auf einer Apple-Kachel (`Design/Icon/AppIcon.png`). Menüleisten-Symbol: Ring, Kern, Querstrich (`Design/Icon/MenuBarTemplate.png`).
- Farbwelt der App: Nebel-Palette „Strudel“ `#1A0633 #6A1B7A #D23A78 #FF7A1F #FFE0A0 #2FC6D8 #3A4DD8` auf fast Schwarz.
- Autor ist das GitHub-Konto „DigitalIQ“. Kein voller Name, keine Adresse, kein Bezug zu Arbeitgebern oder Firmen.
- Englisch ist die Hauptsprache, Deutsch unter `/de/`. Deutsch in Du-Form. Keine Gedankenstriche, keine Emojis.

## Evidence on Hand

- Echte Renderings der App über `--snapshot` (alle Voreinstellungen, alle Objektarten), Prüfbilder in `shots/objekte/`.
- Einstellungsfenster als Bild über `--settings-shot`.
- README mit Physik-Erklärung und Messwerten.
- Nicht vorhanden und nicht zu erfinden: Nutzerzahlen, GitHub-Sterne, Downloads, Zitate, Presse, Auszeichnungen, Bewertungen.

## Product Principles

1. Zeigen, nicht behaupten. Jedes Bild auf der Seite ist ein echtes Rendering der App.
2. Ehrlich trennen, was physikalisch echt ist und was künstlerisch.
3. Ruhig im Betrieb: die App soll den Mac nicht belasten. Die Seite auch nicht.
4. Frei und offen: kein Tracking, keine fremden Anfragen, Code zum Nachlesen.

## Accessibility & Inclusion

`prefers-reduced-motion` zeigt Standbilder statt Animation. Ohne WebGL ein Standbild. Text auf dunklem Grund mindestens 4,5:1.
