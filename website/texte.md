# Texte: Black Hole Wallpaper

Stand 2026-10-13, abgenommen. Die gebaute Seite (`werkzeuge/build.py`) ist maßgeblich für kleine Formulierungen wie Bildunterschriften und den Abschnitt „Gerechnet / Künstlerisch“; Änderungen immer in beiden Dateien. Englisch ist die Hauptsprache (`/`), Deutsch liegt unter `/de/`. Jede Aussage ist aus `README.md` oder dem Auftrag belegt. Keine Nutzerzahlen, Sterne, Zitate oder Auszeichnungen.

Aufbau der Seite (One-Pager):

1. Einstieg mit dem Loch im Browser und den zwei Wegen zur Installation
2. Was echt ist (Physik)
3. Sieben Voreinstellungen
4. Was das Loch biegt (Objekte)
5. Lebt mit deinem Mac (Ränder, Energie, Schirme, Bildschirmschoner)
6. Film
7. Installieren
8. Fragen
9. Fuß

---

## 1. Meta

### EN

- Title (57 Zeichen): `Black Hole Wallpaper: a live black hole for your Mac`
- Description (150 Zeichen): `Free, open source animated wallpaper for macOS. A spinning black hole with real light bending, computed in Metal. Download it or install with Homebrew.`
- Vorschaubild-Text: `Black Hole Wallpaper. Real light bending, live on your Mac desktop.`

### DE

- Titel (55 Zeichen): `Schwarzes Loch: animierter Hintergrund für deinen Mac`
- Beschreibung (151 Zeichen): `Freier, quelloffener Live-Hintergrund für macOS: ein drehendes Schwarzes Loch mit echter Lichtbiegung, gerechnet in Metal. Laden oder per Homebrew.`
- Vorschaubild-Text: `Schwarzes Loch. Echte Lichtbiegung, live auf deinem Mac.`

---

## 2. Einstieg

### EN

- H1: `Your desktop, bent by a black hole.`
- Unterzeile: `Black Hole Wallpaper is a live wallpaper for macOS. Every pixel follows a ray of light around a spinning black hole, computed in Metal on your Mac.`
- Button 1: `Download for macOS`
- Button 2 (kopiert die Befehle): `brew tap digitaliq/tap`, `brew trust --tap digitaliq/tap`, `brew install --cask blackhole-wallpaper` (drei Zeilen, kopiert mit `&&` verbunden)
- Kleingedrucktes: `Free and open source, MIT license. macOS 15 or later.`
- Hinweis im Loch (nur bei WebGL): `Move your pointer. The black hole in this page bends light too, a lighter version of the one in the app.`
- Standbild-Hinweis (ohne WebGL oder bei reduzierter Bewegung): `Still image from the app, preset Gargantua.`

### DE

- H1: `Dein Schreibtisch, gebogen von einem Schwarzen Loch.`
- Unterzeile: `Schwarzes Loch ist ein animierter Hintergrund für macOS. Jeder Pixel folgt einem Lichtstrahl um ein drehendes Schwarzes Loch, gerechnet in Metal auf deinem Mac.`
- Button 1: `Für macOS laden`
- Button 2: `brew tap digitaliq/tap`, `brew trust --tap digitaliq/tap`, `brew install --cask blackhole-wallpaper` (drei Zeilen, kopiert mit `&&` verbunden)
- Kleingedrucktes: `Frei und quelloffen, MIT-Lizenz. Ab macOS 15.`
- Hinweis im Loch: `Beweg die Maus. Auch das Loch auf dieser Seite biegt Licht, eine leichtere Fassung des Lochs aus der App.`
- Standbild-Hinweis: `Standbild aus der App, Voreinstellung Gargantua.`

---

## 3. Was echt ist

### EN

- H2: `Real light bending, not a video loop`
- Text: `Most black hole wallpapers are videos. This one is computed. The app traces a ray of light for every pixel through the spacetime of a spinning (Kerr) black hole, step by step. That ray tracing produces the shadow, the thin photon ring, the far side of the disk bent up over the top, and stars smeared into arcs near the Einstein ring.`
- Text: `The disk starts at the innermost stable orbit and turns at Kepler speed. The side moving toward you is brighter and bluer, from Doppler beaming and gravitational redshift.`
- Ehrlich-Zeile: `What is artistic: the colors. A real disk would glow white to orange. The palettes are a choice, and you can change them.`
- Bildunterschriften (Ausschnitte aus Renderings): `Photon ring`, `Far side of the disk, bent over the shadow`, `Einstein ring around a galaxy behind the hole`

### DE

- H2: `Echte Lichtbiegung statt Videoschleife`
- Text: `Die meisten Schwarzes-Loch-Hintergründe sind Videos. Dieser wird gerechnet. Die App verfolgt für jeden Pixel einen Lichtstrahl durch die Raumzeit eines drehenden Schwarzen Lochs (Kerr), Schritt für Schritt. Daraus entstehen der Schatten, der dünne Photonenring, die Rückseite der Scheibe, die sich über den Schatten biegt, und Sterne, die sich nahe dem Einstein-Ring zu Bögen ziehen.`
- Text: `Die Scheibe beginnt an der innersten stabilen Bahn und dreht sich nach Kepler. Die Seite, die auf dich zukommt, ist heller und blauer, durch Doppler-Effekt und Gravitations-Rotverschiebung.`
- Ehrlich-Zeile: `Künstlerisch sind die Farben. Eine echte Scheibe leuchtet weiß bis orange. Die Paletten sind eine Entscheidung, und du kannst sie ändern.`
- Bildunterschriften: `Photonenring`, `Rückseite der Scheibe, über den Schatten gebogen`, `Einstein-Ring um eine Galaxie hinter dem Loch`

---

## 4. Sieben Voreinstellungen

### EN

- H2: `Seven presets, then make your own`
- Einleitung: `Pick one per display or one for all. Duplicate any preset and change the hole, disk, colors, nebula, stars and edges.`
- `Swirl`: `Magenta and orange disk in a violet nebula. The default.`
- `Gargantua`: `Warm, thin disk seen from the side, like the film.`
- `M87* as photographed`: `Seen from almost straight on, like the first photo of a black hole.`
- `Top View`: `The disk from above.`
- `Ice Blue`: `Cold blue and violet.`
- `Star System`: `Galaxies, a pulsar, an asteroid belt, a ringed planet with a moon and a comet around the hole.`
- `Sci-Fi Harbor`: `A wormhole next to the hole, a space station, a stargate and ships from four universes.`

Entschieden 2026-10-13: Die App bekommt genau diese englischen Namen (Swirl, Gargantua, M87* as photographed, Top View, Ice Blue, Star System, Sci-Fi Harbor). Die deutsche Seite nennt „Dein Strudel“ kurz „Strudel“.

### DE

- H2: `Sieben Voreinstellungen, dann deine eigene`
- Einleitung: `Wähl eine pro Bildschirm oder eine für alle. Dupliziere eine Voreinstellung und ändere Loch, Scheibe, Farben, Nebel, Sterne und Ränder.`
- `Strudel`: `Scheibe in Magenta und Orange in einem violetten Nebel. Der Standard.`
- `Gargantua`: `Warme, dünne Scheibe von der Seite, wie im Film.`
- `M87* wie auf dem Foto`: `Fast von vorn, wie das erste Foto eines Schwarzen Lochs.`
- `Draufsicht`: `Die Scheibe von oben.`
- `Eisblau`: `Kaltes Blau und Violett.`
- `Sternsystem`: `Galaxien, ein Pulsar, ein Asteroidengürtel, ein Ringplanet mit Mond und ein Komet ums Loch.`
- `SciFi-Hafen`: `Ein Wurmloch neben dem Loch, eine Raumstation, ein Sternentor und Schiffe aus vier Universen.`

---

## 5. Was das Loch biegt

### EN

- H2: `Add things. The hole bends them.`
- Text: `Put a galaxy right behind the hole and it becomes a closed Einstein ring. Slightly off, it splits into two arcs. A planet on an orbit dips behind the disk and comes back bent. Comet tails point away from the hole.`
- Liste der Arten (kurz, ohne Schlagwort-Doppelpunkt):
  - `Galaxies, from spirals to quasars`
  - `Distant and nearby stars, pulsars and magnetars`
  - `A relativistic jet along the spin axis`
  - `Planets with rings, clouds and storms, and their moons`
  - `Asteroids, belts, comets and meteors`
  - `Ships and stations from many science fiction worlds, plus real spacecraft like Hubble and James Webb`
  - `A second black hole and a wormhole`
- Bewegung, H3 `Motion follows physics`:
  - `Bodies run on Kepler orbits. Fast visitors swing by or plunge in.`
  - `Tides stretch them near the hole. Their light shifts red or blue.`
  - `Moons stay locked to their planet. Asteroids tumble. Meteors slow down.`
  - `Ships accelerate and bank. A second hole has real mass.`
  - `A Time-lapse slider speeds it all up.`
- Eigene Modelle: `Bring your own 3D model as OBJ, USDZ, USD, PLY, STL, glTF or GLB.`
- Fußnote zu den Schiffen: `Ships are simple shapes built in the app as a fan tribute. Not affiliated with any studio or franchise.`

### DE

- H2: `Stell etwas dazu. Das Loch biegt es.`
- Text: `Steht eine Galaxie genau hinter dem Loch, wird sie zum geschlossenen Einstein-Ring. Knapp daneben teilt sie sich in zwei Bögen. Ein Planet auf seiner Bahn taucht hinter der Scheibe ab und kommt gebogen wieder hervor. Kometenschweife zeigen vom Loch weg.`
- Liste:
  - `Galaxien, von der Spirale bis zum Quasar`
  - `Ferne und nahe Sterne, Pulsare und Magnetare`
  - `Ein Jet entlang der Drehachse`
  - `Planeten mit Ringen, Wolken und Stürmen, dazu ihre Monde`
  - `Asteroiden, Gürtel, Kometen und Meteore`
  - `Schiffe und Stationen aus vielen Science-Fiction-Welten, dazu echte Raumfahrt wie Hubble und James Webb`
  - `Ein zweites Schwarzes Loch und ein Wurmloch`
- Bewegung, H3 `Die Bewegung folgt der Physik`:
  - `Körper laufen auf Kepler-Bahnen. Schnelle Besucher schwingen vorbei oder stürzen hinein.`
  - `Gezeiten ziehen sie nahe am Loch in die Länge. Ihr Licht wird röter oder blauer.`
  - `Monde bleiben an ihren Planeten gebunden. Asteroiden taumeln. Meteore werden langsamer.`
  - `Schiffe beschleunigen und gehen in die Kurve. Ein zweites Loch hat echte Masse.`
  - `Ein Zeitraffer-Regler beschleunigt alles.`
- Eigene Modelle: `Bring dein eigenes 3D-Modell mit, als OBJ, USDZ, USD, PLY, STL, glTF oder GLB.`
- Fußnote: `Die Schiffe sind einfache Formen, in der App gebaut, als Hommage von Fans. Keine Verbindung zu einem Studio oder einer Marke.`

---

## 6. Lebt mit deinem Mac

### EN

- H2: `Made to sit behind your work`
- `Glowing bands run along the menu bar and the Dock.`
- `Three animation levels: everything moves, only the edges move, or a still image.`
- `It pauses in Low Power Mode and when windows cover the desktop.`
- `Pick a preset per display. A screen saver and a still for the lock screen come with it.`
- `Four quality levels: Battery Saver, Balanced, High and Ultra. One level for the power adapter, one for battery, and six areas can be set separately. The jet is smooth already at Balanced.`
- `The app is in English and German. It follows the system language, or you choose on the General page.`
- Messzeile: `Measured on a MacBook Air M4 at 3440 x 1440: 1.7 to 2.6 ms of GPU time per frame with everything moving, 0.12 to 0.14 ms with only the edges. 30 frames per second by default.`

### DE

- H2: `Gemacht, um hinter deiner Arbeit zu bleiben`
- `Leuchtende Bänder laufen an Menüleiste und Dock entlang.`
- `Drei Stufen: alles bewegt sich, nur die Ränder, oder ein Standbild.`
- `Im Energiesparmodus und bei verdecktem Schreibtisch hält es an.`
- `Wähl eine Voreinstellung pro Bildschirm. Ein Bildschirmschoner und ein Standbild für den Sperrbildschirm sind dabei.`
- `Vier Qualitätsstufen: Akku sparen, Ausgewogen, Hoch und Ultra. Eine Stufe fürs Netzteil, eine für den Akku, sechs Bereiche lassen sich einzeln einstellen. Der Jet ist schon bei Ausgewogen glatt.`
- `Die App gibt es auf Deutsch und Englisch. Sie folgt der Systemsprache, oder du wählst auf der Seite „Allgemein“.`
- Messzeile: `Gemessen auf einem MacBook Air M4 bei 3440 x 1440: 1,7 bis 2,6 ms GPU-Zeit pro Bild, wenn sich alles bewegt, 0,12 bis 0,14 ms bei nur den Rändern. Standard sind 30 Bilder pro Sekunde.`

---

## 7. Film

### EN

- H2: `26 seconds in motion`
- Unterzeile: `Rendered from the app, no sound.`
- Video-Fallback: `Your browser cannot play this video. Download the MP4.`

### DE

- H2: `26 Sekunden in Bewegung`
- Unterzeile: `Aus der App gerendert, ohne Ton.`
- Video-Fallback: `Dein Browser kann das Video nicht abspielen. MP4 herunterladen.`

---

## 8. Installieren

### EN

- H2: `Install`
- Weg 1: `Download the latest release from GitHub, open the disk image and drag the app to Applications.` Button: `Download latest release`
- Weg 2: `Or use Homebrew:` Code: `brew tap digitaliq/tap`, `brew trust --tap digitaliq/tap`, `brew install --cask blackhole-wallpaper` (drei Zeilen, kopiert mit `&&` verbunden) Button: `Copy` / nach dem Klick `Copied`
- Erster Start: `The app is not notarized by Apple, so macOS blocks the first start. Open it once, then click Open Anyway in System Settings > Privacy & Security. Or run xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app in Terminal.` (Seit macOS 15 umgeht Rechtsklick > Öffnen Gatekeeper nicht mehr, Stand Oktober 2026.)
- Danach: `It lives in the menu bar. Open Settings from there, or launch the app again from Spotlight.`

Entschieden 2026-10-13: Download-Knöpfe zeigen auf `releases/latest`, dort liegt später eine .dmg. Der Text bleibt ohne Formatangabe.

### DE

- H2: `Installieren`
- Weg 1: `Lade die neueste Version von GitHub und leg die App in den Ordner Programme.` Button: `Neueste Version laden`
- Weg 2: `Oder mit Homebrew:` Button: `Kopieren` / danach `Kopiert`
- Erster Start: `Die App ist nicht von Apple notarisiert, deshalb blockiert macOS den ersten Start. Öffne sie einmal und klicke in Systemeinstellungen > Datenschutz & Sicherheit auf „Trotzdem öffnen“. Oder im Terminal: xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app`
- Danach: `Sie sitzt in der Menüleiste. Dort öffnest du die Einstellungen, oder du startest die App noch einmal über Spotlight.`

---

## 9. Fragen

### EN

- `Is it free?` `Yes. Free and open source under the MIT license.`
- `Will it drain my battery?` `It pauses in Low Power Mode and when windows cover the desktop. With only the edges moving it needs less than a tenth of the GPU time. Numbers are in the README. On battery you can pick a lighter quality level.`
- `Which Macs does it run on?` `macOS 15 or later.` (Prozessoren offen)
- `Why does macOS warn me on first launch?` `The app is not notarized by Apple. Since macOS 15, right-click and Open no longer helps. Click Open Anyway in System Settings > Privacy & Security once, or remove the quarantine flag with xattr. Homebrew quarantines its download too.`
- `Is the physics real?` `The light bending is: the app integrates light rays through Kerr spacetime. The colors are artistic. The README lists exactly what is real and what is approximated.`
- `Can I use my own 3D models?` `Yes: OBJ, USDZ, USD, PLY, STL, glTF and GLB.`
- `Which languages does the app speak?` `English and German. It follows the system language, or you pick one on the General page.`
- `Does the app go online?` `Only for updates. It asks api.github.com at most once a day and loads updates from GitHub's download servers. You can switch the check off on the General page. No analytics.`
- `Does this website track me?` `No. No cookies, no analytics, no requests to other servers.`

### DE

- `Kostet es etwas?` `Nein. Frei und quelloffen unter der MIT-Lizenz.`
- `Zieht es meinen Akku leer?` `Im Energiesparmodus und bei verdecktem Schreibtisch hält es an. Wenn sich nur die Ränder bewegen, braucht es weniger als ein Zehntel der GPU-Zeit. Am Akku wählst du eine leichtere Qualitätsstufe. Die Messwerte stehen in der README.`
- `Auf welchen Macs läuft es?` `Ab macOS 15.`
- `Warum warnt macOS beim ersten Start?` `Die App ist nicht von Apple notarisiert. Seit macOS 15 hilft Rechtsklick und Öffnen nicht mehr. Klicke einmal in Systemeinstellungen > Datenschutz & Sicherheit auf „Trotzdem öffnen“ oder entferne die Quarantäne-Markierung mit xattr. Auch Homebrew stellt den Download unter Quarantäne.`
- `Ist die Physik echt?` `Die Lichtbiegung ja: Die App rechnet Lichtstrahlen durch die Kerr-Raumzeit. Die Farben sind künstlerisch. Die README sagt genau, was echt ist und was genähert.`
- `Kann ich eigene 3D-Modelle nutzen?` `Ja, als OBJ, USDZ, USD, PLY, STL, glTF und GLB.`
- `Welche Sprachen kann die App?` `Deutsch und Englisch. Sie folgt der Systemsprache, oder du wählst auf der Seite „Allgemein“.`
- `Geht die App ins Internet?` `Nur für Updates. Sie fragt höchstens einmal am Tag bei api.github.com nach und lädt Updates von den Download-Servern von GitHub. Die Prüfung schaltest du auf der Seite „Allgemein“ ab. Keine Statistik.`
- `Trackt mich diese Seite?` `Nein. Keine Cookies, keine Statistik, keine Anfragen an andere Server.`

---

## 10. Fuß

### EN

`Made by DigitalIQ. MIT license. Source on GitHub. Deutsch`

### DE

`Made by DigitalIQ. MIT-Lizenz. Quellcode auf GitHub. English`

Entschieden 2026-10-13: kein Impressum. Im Fuß nur „Made by DigitalIQ“, Lizenz MIT und der Link zum Repo.

---

## 11. Faktensätze

- Black Hole Wallpaper (German name: Schwarzes Loch) is a free, open source animated desktop wallpaper for macOS, released under the MIT license by the GitHub account DigitalIQ.
- The app renders a spinning Kerr black hole live in Metal. For every pixel it integrates a light ray with Hamilton's equations and a fourth-order Runge-Kutta method.
- The accretion disk starts at the innermost stable circular orbit, rotates at Kepler speed and is brighter on the side moving toward the viewer.
- The app ships seven presets: Swirl, Gargantua, M87* as photographed, Top View, Ice Blue, Star System and Sci-Fi Harbor.
- Objects such as galaxies, planets, comets and spaceships are lensed by the black hole; a galaxy directly behind it appears as an Einstein ring.
- Users can import their own 3D models as OBJ, USDZ, USD, PLY, STL, glTF or GLB files.
- The app pauses in Low Power Mode and when windows cover the desktop, and offers three animation levels: all, edges only, off, and four quality levels from Battery Saver to Ultra (one for the power adapter, one for battery). Bodies move on Kepler orbits with flybys, tidal stretching and gravitational red and blue shift. The app is in English and German.
- On a MacBook Air M4 at 3440 x 1440 the full animation costs 1.7 to 2.6 ms of GPU time per frame; edges only costs 0.12 to 0.14 ms.
- It requires macOS 15 or later and is installed from GitHub Releases or with Homebrew: `brew tap digitaliq/tap`, `brew trust --tap digitaliq/tap`, `brew install --cask blackhole-wallpaper`.
- The app is not notarized by Apple; on first launch, click Open Anyway in System Settings > Privacy & Security, or run `xattr -dr com.apple.quarantine`.
- The app only contacts api.github.com and GitHub's download servers to check for and fetch updates, and you can switch it off.

---

## 12. Offene Fragen

1. Erledigt 2026-10-13: englische Namen wie in der App (Swirl, Gargantua, M87* as photographed, Top View, Ice Blue, Star System, Sci-Fi Harbor).
2. Erledigt 2026-10-13: Download über `releases/latest`, später als .dmg.
3. Prozessoren: nur Apple Silicon oder auch Intel?
4. Erledigt 2026-10-13: kein Impressum.
5. Erledigt 2026-10-13: keine eigene Domain, `https://digitaliq.github.io/blackhole-wallpaper/`.
