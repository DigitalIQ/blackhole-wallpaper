# Schwarzes Loch

[English](README.md) · [Website](https://digitaliq.github.io/blackhole-wallpaper/)

Animierter Schreibtisch-Hintergrund für macOS: ein drehendes Schwarzes Loch mit echter Lichtbiegung, dazu bunte Nebel und ein leuchtendes Band an Menüleiste und Dock. Dazu gibt es einen Bildschirmschoner.

![Voreinstellung Gargantua mit dem Band an Menüleiste und Dock](website/assets/img/hero-still.jpg)

## Was echt ist und was nicht

- **Echt:** Jeder Pixel folgt einem Lichtstrahl durch die Raumzeit eines drehenden Schwarzen Lochs (Kerr-Metrik, Hamilton-Gleichungen, RK4). Daraus entstehen der Schatten, der Photonenring, das gebogene Bild der Scheibenrückseite und die gezogenen Sterne nahe dem Einstein-Ring. Die Scheibe beginnt an der innersten stabilen Bahn (ISCO), dreht sich nach Kepler, und die Seite, die auf dich zukommt, ist heller und blauer (Doppler und Gravitations-Rotverschiebung).
- **Künstlerisch:** die Farben. Echte Scheiben wären weiß bis orange.

## Funktionen

- **7 Voreinstellungen:** Dein Strudel, Gargantua, M87* wie auf dem Foto, Draufsicht, Eisblau, Sternsystem und SciFi-Hafen. Jede lässt sich duplizieren und in jedem Wert ändern.
- **Voreinstellung pro Schirm:** Jeder Monitor zeigt seine eigene Voreinstellung und seine eigene Lage des Lochs.
- **Animation in drei Stufen:** Alles, Nur Ränder und Aus. Bei „Nur Ränder“ steht das Loch still, nur die Bänder an Menüleiste und Dock fließen. Auf einem MacBook Air M4 bei 3440 x 1440 sinkt die GPU-Zeit damit von etwa 2 ms auf etwa 0,13 ms pro Bild.
- **Objekte ums Loch:** Galaxien, ferne und nahe Sterne, Planeten, Monde, Asteroiden und Gürtel, Kometen, Meteore, ein zweites Schwarzes Loch, ein Wurmloch und ein relativistischer Jet. Eine Galaxie genau hinter dem Loch wird zum Einstein-Ring.
- **Schiffe und Stationen aus vielen Science-Fiction-Welten:** Star Trek, Star Wars, Battlestar Galactica, Raumpatrouille Orion, The Expanse, Babylon 5, Firefly, 2001, Interstellar, Mass Effect und weitere, dazu echte Raumfahrt wie Hubble, James Webb und die ISS. Schiffe kommen und gehen mit Warp, Hyperraum und ähnlichen Ereignissen.
- **Echte Bewegung:** Körper laufen auf Kepler-Bahnen, Vorbeiflüge auf Hyperbeln, die das Loch ablenkt. Nahe am Loch strecken die Gezeiten die Körper, ein zweites Loch kreist mit der Summe beider Massen.
- **Qualitätsstufen:** Akku sparen, Ausgewogen, Hoch und Ultra, getrennt für Netzteil und Akku. Standard ist Hoch am Netzteil und Ausgewogen am Akku. Neben jeder Stufe steht die gemessene Last.
- **Eigene 3D-Modelle:** Import von OBJ, USD, USDZ, PLY, STL, glTF und GLB.
- **Oberfläche auf Deutsch und Englisch.** Die App folgt der Systemsprache.
- **Bildschirmschoner** mit demselben Renderer. Er zeigt die Voreinstellung des Hauptschirms.
- **Sparsam:** Pause im Energiesparmodus, wenn Fenster den Schreibtisch ganz verdecken und solange der Mac gesperrt ist, schläft, den Bildschirmschoner zeigt oder auf einen anderen Benutzer umgeschaltet ist. Standard sind 30 Bilder pro Sekunde, 60 und 120 gehen auch. Wird der Mac heiß, halbiert die App die Bildrate und senkt eine Qualitätsstufe, bei kritischer Hitze zeigt sie ein Standbild (Schalter: Energie > Bei Hitze drosseln). Ist in macOS „Bewegung reduzieren“ an, zeigt sie ebenfalls ein Standbild.
- **Updates:** Die App sucht einmal am Tag bei GitHub nach einer neuen Version und installiert sie auf Wunsch. Das lässt sich abschalten.

![Voreinstellung Sternsystem mit Jet, Galaxien, Ringplanet und Komet](website/assets/img/preset-starsystem.jpg)

![Schiffe und eine Station rund ums Loch](website/assets/img/obj-ships.jpg)

## Systemvoraussetzungen

- macOS 15 Sequoia oder neuer
- Ein Mac mit Apple Silicon. Der Release-Build ist nur für arm64 gebaut.

## Installation

### Aus der DMG

1. Die neueste `BlackHoleWallpaper-<Version>.dmg` von der [Release-Seite](https://github.com/DigitalIQ/blackhole-wallpaper/releases/latest) laden.
2. Öffnen und `BlackHoleWallpaper.app` auf den Ordner Programme ziehen.
3. Optional: `Schwarzes Loch.saver` doppelklicken, das installiert den Bildschirmschoner. Er steht dann in den Systemeinstellungen unter Bildschirmschoner.

Die App sitzt in der Menüleiste. Startest du sie ein zweites Mal, etwa über Spotlight, öffnet sich das Einstellungsfenster.

### Erster Start einer nicht signierten App

Die App ist nur ad hoc signiert und nicht von Apple notarisiert. Beim ersten Start blockiert macOS sie deshalb. Seit macOS 15 hilft Rechtsklick > Öffnen nicht mehr. Zwei Wege, die gehen:

- Im Terminal die Quarantäne-Markierung entfernen (liegt die App in `~/Applications`, diesen Pfad nehmen):

```bash
xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app
xattr -dr com.apple.quarantine ~/Library/"Screen Savers/Schwarzes Loch.saver"
```

- Oder die App einmal öffnen, dann in Systemeinstellungen > Datenschutz & Sicherheit auf **Trotzdem öffnen** klicken und bestätigen. Beim Bildschirmschoner genauso.

### Homebrew

Nach dem ersten Release:

```bash
brew tap digitaliq/tap
brew trust --tap digitaliq/tap
brew install --cask blackhole-wallpaper
```

Homebrew 7 lädt Casks aus fremden Taps erst nach `brew trust`. Den Download stellt Homebrew ebenfalls unter Quarantäne, der erste Start braucht also denselben Schritt wie oben: `xattr -dr` oder **Trotzdem öffnen**. Updates kommen dann mit `brew upgrade --cask blackhole-wallpaper`, die App ersetzt sich in dem Fall nicht selbst.

### Aus dem Quellcode bauen

```bash
git clone https://github.com/DigitalIQ/blackhole-wallpaper.git
cd blackhole-wallpaper
./scripts/install.sh
```

Das baut die App, legt sie nach `~/Applications/BlackHoleWallpaper.app`, den Bildschirmschoner nach `~/Library/Screen Savers/` und startet sie. Xcode ist nicht nötig, die Command Line Tools reichen: Der Metal-Shader wird zur Laufzeit übersetzt. `./scripts/make-dmg.sh` baut App und Bildschirmschoner in `build/BlackHoleWallpaper-<Version>.dmg` und installiert nichts. Die Version steht in der Datei `VERSION`.

## Datenschutz

Die App spricht nur mit api.github.com und den Download-Servern von GitHub, um nach Updates zu suchen und sie zu laden. Das kannst du abschalten (Allgemein > Updates > Automatisch nach Updates suchen). Sonst geht nichts übers Netz: keine Statistik, keine Absturzberichte, kein Konto. Die Suche schickt keine Daten über dich oder deinen Mac, nur eine normale Anfrage mit der App-Version im User-Agent. Ohne automatische Suche geht die App nur online, wenn du auf **Jetzt suchen** klickst. Außerdem öffnet sie die Bildschirmschoner-Seite der Systemeinstellungen und die Download-Seite bei GitHub, jeweils nur, wenn du auf den Knopf dafür klickst.

Sie schreibt nur lokale Dateien:

- `~/Library/Application Support/BlackHoleWallpaper/`: Einstellungen (`settings.json`), importierte Modelle (`Models/`), Standbilder für das Hintergrundbild (`Stills/`) und, nur während ein Update installiert wird, die geladene DMG (`Updates/`).
- Wenn du ein Update installierst: die neue App an der Stelle der alten und den neuen Bildschirmschoner in `~/Library/Screen Savers/`, falls dort einer liegt.
- Eine Kopie des Looks vom Hauptschirm für den Bildschirmschoner, in dessen Container unter `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/`.
- Das Hintergrundbild von macOS, nur wenn du das Standbild einschaltest. Das alte Bild merkt sie sich und holt es auf Knopfdruck zurück.

## Logo

Das App-Symbol zeigt Gargantua schräg von der Seite, aus einem Render der App selbst. In der Menüleiste steht ein einfaches Template-Symbol: Ring, Kern und die Scheibe als Querstrich. Beide Dateien und die Skripte zum Neubauen liegen in `Design/Icon/` (siehe dort `README.md`). Der Bildschirmschoner hat ein Vorschaubild unter `Saver/`; `./scripts/render-thumbnail.sh` rendert es neu.

## Bedienung

Beim ersten Start öffnet sich ein kleines Willkommensfenster: Du wählst eine Voreinstellung, entscheidest, ob die App beim Anmelden startet (vorangekreuzt), und siehst, wo die Einstellungen liegen. Es erscheint nur, wenn es vorher keine Einstellungsdatei gab. Wer die App schon nutzt, sieht es nie.

Symbol in der Menüleiste:

- **Animation**: Alles, Nur Ränder oder Aus. Siehe unten.
- **Im Energiesparmodus anhalten**: an ist Standard.
- **Maus-Modus**: Eine kleine Linse mit Mini-Loch folgt dem Zeiger.
- **Voreinstellung für alle Schirme**: schneller Wechsel.
- **Einstellungen …** (⌘,): das große Fenster. Es öffnet sich auch, wenn du die App ein zweites Mal startest, etwa über Spotlight.
- **Nach Updates suchen …**: sucht sofort und zeigt das Ergebnis auf der Seite Allgemein. Hat die tägliche Suche eine neue Version gefunden, steht oben im Menü die Zeile „Version X ist da …“. Ein Fenster öffnet sich nie von selbst.
- **Beim Anmelden starten**
- **Beenden**

Im Einstellungsfenster gibt es links zwölf Seiten: Allgemein, Loch, Scheibe, Farben, Nebel, Sterne, Ränder, Objekte, Bewegung, Schirme, Energie und Qualität. Sieben Voreinstellungen sind eingebaut: Dein Strudel, Gargantua, M87* wie auf dem Foto, Draufsicht, Eisblau, Sternsystem und SciFi-Hafen. Eigene legst du über **Mehr > Duplizieren** an.

Neben jedem Wert setzt ein Rückgängig-Symbol nur diesen Wert zurück. **Mehr > Alles auf Werkseinstellung** stellt den Auslieferungszustand her: die eingebauten Voreinstellungen im Original, eigene gelöscht, alle Einstellungen auf Standard.

Alles wird in `~/Library/Application Support/BlackHoleWallpaper/settings.json` gespeichert.

## Objekte

Jede Voreinstellung hat ihre eigene Szene mit Objekten rund ums Loch, eingestellt auf der Seite **Objekte**. Die fünf klassischen Voreinstellungen haben keine, die Voreinstellung **Sternsystem** zeigt fast alles auf einmal: Jet, zwei Galaxien, Pulsar, einen Asteroidengürtel, einen Ringplaneten mit Mond und einen Kometen. **SciFi-Hafen** zeigt ein Wurmloch neben dem Loch, Babylon 5 und ein Stargate-Tor, dazu Schiffe aus vier Universen auf Bahnen und an den Rändern mit ihren Sprüngen. Die Arten:

- **Galaxien**: Spirale, Balkenspirale, Kantenansicht, Elliptisch, Linsenförmig, Irregulär, Ringgalaxie, Wechselwirkendes Paar und Quasar. Jede wird einmal als kleines Volumenmodell mit Staub gebacken, Arme, Neigung, Staub und Farbe sind Regler.
- **Ferne Sterne**: Hauptreihe O bis M, Riesen und Überriesen, Weißer und Brauner Zwerg, Neutronenstern, Pulsar mit Lichtkegeln und Blitzen, Magnetar mit Ausbrüchen, Wolf-Rayet mit Nebelhülle, Cepheide und Doppelstern. Die Farbe kommt aus der Temperatur.
- **Jet am Hauptloch**: entlang der Drehachse, am Fuß schmal und hell, erst parabolisch, dann als schlanker Kegel, nach außen dunkler und weich auslaufend. Mit Gegenjet, Knoten, die nach außen wandern, feinen Filamenten, leichtem Wackeln der Achse und Pulsieren.
- **Planeten**: Gestein, Wüste, Erdähnlich, Ozeanwelt, Eis, Lava, Gasriese, Ringplanet, Eisriese und Heißer Jupiter. Oberfläche, Wolken, Bänder, Stürme, Ringe mit Cassini-Teilung, Atmosphäre und Nachtlichter sind Regler. Die Scheibe beleuchtet sie, im Gegenlicht leuchtet der Rand der Atmosphäre.
- **Monde**: Grau verkratert, Io-artig, Europa-artig, Titan-artig und eine Knolle wie Phobos. Ein Mond hängt sich beim Hinzufügen an den ersten Planeten.
- **Nahe Sterne** (Untermenü „Sterne nah“): die Klassen der fernen Sterne als selbstleuchtende Kugel. Die Mitte ist hell, der Rand dunkler und röter (Randverdunklung), darauf Granulation und bei kühlen Sternen Flecken. Die Belichtung ist so gewählt, dass die Farbe nach Temperatur bleibt und nichts ins Weiß ausbrennt. Außen leuchten Korona und ein weicher Lichthof, bei heißen Sternen bläulich, am Rand stehen Protuberanzen. Der Braune Zwerg zeigt Wolkenbänder, der Wolf-Rayet-Stern eine Nebelhülle, die Cepheide pulsiert in Größe, Helligkeit und Farbe. Der Doppelstern zeigt einen glühenden, zum Tropfen verzogenen Stern, dessen Gas als leuchtender Strom in eine heiße Scheibe um den Begleiter fließt.
- **Asteroiden und Gürtel**: einzelner Asteroid mit unregelmäßigem Umriss, Gürtel ums Loch aus Tausenden Brocken mit Dunst dazwischen, Trümmerstrom an einem Rand und ein feiner Staub- oder Eisring.
- **Kometen und Meteore**: Komet mit Koma, geradem Ionenschweif und gebogenem Staubschweif, grüner Komet, Sternschnuppe, Meteorschauer und Feuerkugel mit Rauchspur.
- **Raumschiffe** (Untermenü nach Universum): Star Trek (Enterprise NCC-1701, Enterprise-D, Voyager, Defiant, Bird-of-Prey, Romulanischer Warbird, Borg-Würfel), Star Wars (Millennium Falke, X-Wing, TIE Fighter, Sternzerstörer, Tantive IV), Battlestar Galactica (Galactica, Viper Mk II, Basisstern, Cylon Raider, Raptor), Raumpatrouille Orion (Orion VIII, Frog-Raumer), The Expanse (Rocinante, Donnager), Babylon 5 (White Star, Starfury), Firefly (Serenity, Allianz-Kreuzer), 2001 (Discovery One, Monolith), Interstellar (Endurance, Ranger), Mass Effect (Normandy SR-2, Reaper), Echte Raumfahrt (Hubble, James Webb, Voyager-Sonde, Apollo CSM, Starship) und Weitere (TARDIS, Ha'tak, Kugelraumer, Nostromo, Heart of Gold).
- **Stationen**: Deep Space 9, Todesstern, Tycho-Station, Ring-Tor, Babylon 5, Raumstation V, Citadel, Massenportal, ISS und Stargate-Tor. Babylon 5, Raumstation V, Tycho, Citadel und der Todesstern drehen sich langsam um ihre eigene Achse.
- **Zweites Schwarzes Loch** (Untermenü „Exoten“): ohne Scheibe, mit Scheibe oder mit Scheibe und Jet. Es hat einen eigenen Schatten, einen eigenen Photonenring und, mit Scheibe, deren gebogene Rückseite über und unter dem Schatten wie beim Hauptloch, nur kleiner. Ohne Scheibe siehst du nur Schatten, Ring und die gebogenen Sterne und Nebel dahinter. Regler: Masse (im Verhältnis zum Hauptloch), Spin, Blickwinkel, Lage der Achse, Ringleuchten, Außenradius, Helligkeit, Umlaufzeit und Farbton der Scheibe, eigener Jet mit Länge, Tempo und Helligkeit. Standard ist ein Doppelsystem: Es kreist um das Hauptloch, zieht dabei dicht hinter ihm vorbei (das Hauptloch biegt es zu einem Bogen um den Schatten) und vor ihm her (dann biegt es das Hauptloch und dessen Scheibe).
- **Wurmloch** (Exoten): eine Kugel, durch die du einen anderen Himmel siehst, mit eigenen Sternen und eigenem Nebel in kühlen Farben, wahlweise mit einer Galaxie in der Mitte oder unserem eigenen Himmel von hinten. Zum Rand hin wird das Bild immer stärker gestaucht und läuft mehrmals herum, wie das Wurmloch in Interstellar. Außen biegt es Sterne und Nebel wie eine Linse. Regler: Linsenstärke, Andere Seite, Farbton, Helligkeit und Sterne drüben, Randleuchten, Schimmern.
- **Tore**: Im Ring-Tor (The Expanse) und im Stargate-Tor liegt ein Wurmloch. Drinnen siehst du einen anderen Himmel, die Membran wird dafür dünn. Abschaltbar mit „Andere Seite zeigen“.
- **Eigenes Modell**: eine OBJ-, USDZ-, USD-, PLY-, STL-, glTF- oder GLB-Datei. Die App kopiert sie nach `~/Library/Application Support/BlackHoleWallpaper/Models/` (eine `.gltf` mit ihren `.bin`- und Bilddateien in einen eigenen Ordner), setzt sie mittig und bringt sie auf ihre Länge. Die y-Achse der Datei zeigt nach oben, die längere der beiden anderen nach vorn. Materialien kommen aus der Datei: bei glTF Grundfarbe, Metall und Rauheit, Normalen-, Leucht- und Verdeckungskarte samt Bildern (PNG, JPEG, höchstens 1024 Pixel), bei den anderen Formaten Grundfarbe, Metall, Rauheit, Leuchtfarbe und ein Farbbild, soweit vorhanden. Animationen, Skins, Kameras, Lichter und komprimierte Netze (Draco) liest die App nicht; braucht eine Datei so eine Erweiterung, sagt sie es.

Schiffe sind Dreiecksnetze aus einfachen Bausteinen (Kasten, Rohr, Drehkörper, Ellipsoid, Torus, Prisma), gerastert mit Kantenglättung. Jedes Bauteil hat ein physikalisch begründetes Material mit Metallanteil und Rauheit: lackierte Panzerplatten, blankes Aluminium (Apollo), Edelstahl (Starship), Gold- und Silberfolie, Keramik, dunkles Glas. Die Hülle spiegelt den Himmel mit Nebel und Sternen und vor allem die Scheibe des Lochs samt Schatten, an den Kanten stärker (Fresnel). Glanzlichter kommen von der Scheibe und vom hellsten nahen Stern. Ecken und Spalten sind weich verschattet (Umgebungsverdeckung, einmal pro Modell gerechnet). Die Platten sind verschieden groß, jede steht minimal schief und hat ihren eigenen Ton und Glanz, dazu Schmutzspuren je nach Abnutzung. Fensterreihen leuchten als kleine Lichtpunkte mit einem Schein drumherum, Triebwerke, Warpgondeln und Deflektoren glühen in der Glühfarbe, Positionslichter blinken rot und grün. Regler pro Schiff unter **Material**: Glanz, Abnutzung und Spiegelung. Auf einer Bahn fliegt ein Schiff mit der Spitze voran, fest im Bild und am Rand richtest du es mit Drehung, Neigung und Rollen aus.

**Ereignisse** (Abschnitt „Ereignisse“): Warp, Hyperraum, FTL-Sprung, Sprungpunkt, Relais-Sprung, Epstein-Zündung, Transwarp, Tarnung, Materialisieren, Strudelstart, Auftauchen, Zündung, Full Burn, Sternentor, Transition, Unwahrscheinlichkeitssprung und Durchs Wurmloch (die Endurance fliegt ins nächste Wurmloch und verschwindet darin), je nach Schiff. Die Tore haben eigene Ereignisse im Ring: Kawoosh beim Stargate (das Tor schließt kurz, eine helle Fontäne schießt heraus und fällt zurück, dann beruhigt sich die Fläche) und Durchflug beim Ring-Tor (ein Blitz und ein Ring, der über die Fläche läuft). Ein Schiff am Rand kommt mit dem Ereignis an und verlässt den Schirm mit ihm, auf einer Bahn verschwindet es ab und zu und taucht ein paar Sekunden später wieder auf. Jedes Ereignis dauert ein bis drei Sekunden und bleibt dezent.

**Bewegung:** Körper laufen auf einer Kepler-Bahn ums Loch (Radius, Exzentrizität, Neigung, Knoten, Perihel, Phase, Tempo), fliegen einmal vorbei, ziehen an einem Rand entlang oder stehen fest auf dem Schirm (vor oder hinter dem Loch). Randobjekte laufen auch bei „Nur Ränder“ weiter, alles andere steht dann. Beim Bildschirmschoner ohne Menüleiste und Dock gilt eine gedachte Linie bei 3 % der Höhe als Rand. Alles, was die Schwerkraft bewegt, läuft auf der Uhr der Scheibe; der Regler **Zeitraffer** rafft sie für die ganze Szene, die Verhältnisse bleiben nach Kepler. Vorbeiflüge laufen auf Hyperbeln, das Loch lenkt sie ab (unter 4 M stürzen sie hinein), nahe am Loch werden Körper von den Gezeiten gestreckt, Monde sind gebunden, Asteroiden taumeln, ein zweites Loch kreist mit der Summe beider Massen. Prüfen: `--series 0:1400:50 --stack` legt eine Zeitreihe übereinander.

**Was echt ist:** Galaxien und ferne Sterne liegen am Himmel und werden über dieselben Lichtstrahlen gebogen wie die Sterne im Hintergrund. Liegt eine Galaxie genau hinter dem Loch, entsteht ein geschlossener Einstein-Ring, knapp daneben zwei Bögen auf gegenüberliegenden Seiten. Den Jet sammelt jeder Strahl auf seinem Weg ein, auch um das Loch herum. Die Seite, die auf dich zukommt, ist heller (Doppler-Faktor hoch 2,7). Ein Teil des Lichts kommt aus einer langsamen Hülle (0,3 c), wie bei M87 beobachtet. Bei M87* (17°) und Tempo 0,9 c ist der Jet damit an der hellsten Stelle 27-mal heller als der Gegenjet, dessen Licht als Ring um den Schatten herum gebogen ankommt. Der Lichthof eines Sterns gehört zur Kamera, nicht zum Himmel: Er wird in Bildpunkten um jedes Bild des Sterns gezeichnet und so hell wie dieses Bild. Ein Stern hinter dem Loch ergibt deshalb zwei leuchtende Bilder und keinen leuchtenden Ring. Die Knoten im Gegenjet laufen im Verhältnis der scheinbaren Geschwindigkeiten langsamer.

Körper hinter dem Loch werden mit einer dünnen Linse über die echte Strahlenkarte gebogen: Ein Planet genau hinter dem Loch wird zum Einstein-Ring mit Gegenbild, einer auf der Bahn taucht hinter der Scheibe ab und kommt gebogen wieder hervor. Vor dem Loch verdeckt er Scheibe und Schatten. Jeder Körper wird nach seiner Tiefe zwischen die beiden Kreuzungen mit der Scheibe, den Schatten und den Jet sortiert. Licht und Farbe kommen von der Scheibe, auf der zukommenden Seite heller (Doppler hoch 3, abschaltbar mit „Relativistisch“). Kometenschweife zeigen vom Loch weg. Gürtel und Staub liegen als Punkte im Bild, jeder Punkt mit eigener Linse und Gegenbild. Was nicht echt ist: Für Körper und Punkte ist die Linse eine dünne Linse im Abstand des Lochs, für Punkte sogar nur eine Punktlinse, nicht die volle Kerr-Bahn. Nahe am Schatten weicht die Lage der Bilder deshalb etwas ab. Schiffe hinter dem Loch werden genauso gebogen wie Planeten, ein Schiff genau dahinter wird zum Einstein-Ring.

Das zweite Loch hat eine eigene kleine Strahlenkarte (512 x 512, mit Jet 7,9 MB), gerechnet wie die des Hauptlochs mit seinem Spin, Blickwinkel und seiner Scheibe, einmal für eine weit entfernte Kamera. Pro Bild wird daraus die Ablenkung jedes Strahls genommen, egal wie weit das Loch gerade weg ist. Außerhalb der Karte fällt die Ablenkung wie 1/b ab (schwaches Feld, bis zur dritten Ordnung) und läuft im dreifachen Abstand der Karte weich aus. Liegt es vor der Ebene des Hauptlochs, biegt es zuerst und das Hauptloch danach; liegt es dahinter, biegt erst das Hauptloch, dann das zweite. So entstehen beide Bilder eines Doppelsystems: das zweite Loch als Bogen um den Schatten, das Hauptloch als Sichel hinter dem zweiten. Was nicht echt ist: Die beiden Ablenkungen werden hintereinander genommen, nicht als eine Bahn durch zwei Massen, das Hauptloch bleibt fest, und die Bahn ist eine einfache Kepler-Ellipse. Das Wurmloch ist eine Punktlinse mit einer Kugel, durch die eine feste Abbildung auf den anderen Himmel zeigt, keine Strahlenverfolgung durch eine Wurmloch-Metrik.

**Bedienung:** Hinzufügen über das Menü, Duplizieren, Würfeln (neuer Seed und neue Werte), Entfernen. Unter **Mehr** würfelst du eine ganze Szene oder kopierst sie als Text in die Zwischenablage, um sie in eine andere Voreinstellung einzufügen. Die Zeile **Geschätzte Last** zeigt, was die Szene ungefähr kostet. Galaxien und Sterne stehen bei „Nur Ränder“ und „Aus“ still und kosten dann nichts extra. Der Bildschirmschoner zeigt die Szene des Hauptschirms mit.

Gemessen mit `--bench-ab` auf dem MacBook Air M4 bei 3440 x 1440: Sternsystem kostet 0,30 bis 0,36 ms mehr pro Bild (Hochkant 1440 x 2560: 0,20 ms), live auf dem eingebauten Schirm 0,75 bis 0,9 ms bei 30 Bildern pro Sekunde. Einzeln: ein Gürtel mit 7 000 Brocken 0,14 ms, ein Ringplanet 0,07 bis 0,09 ms, ein Komet 0,11 ms, ein naher Stern 0,04 bis 0,1 ms, ein Staubring 0,17 ms. Grafikspeicher für Sternsystem: 34 MB mehr.

Stufe 4 (`--bench-ab`, 3440 x 1440): ein zweites Loch mit Scheibe als Doppelsystem 0,44 ms mehr pro Bild, fest im Bild vor dem Hauptloch 0,65 ms, ein Wurmloch um 0,1 ms, SciFi-Hafen 0,53 ms. Live auf dem eingebauten Schirm (1920 x 1242, 30 Bilder pro Sekunde, `BH_DEBUG=1`): SciFi-Hafen 1,1 bis 1,2 ms mehr als ohne Objekte. Das Loch biegt einen großen Teil des Schirms; nur die Kacheln, in denen eine Linse wirklich etwas biegt, laufen mit dem Linsen-Code. Grafikspeicher: zweites Loch 6,3 MB, mit Jet 7,9 MB, SciFi-Hafen 12 MB. Ohne zweites Loch, Wurmloch und Tor laufen die alten Pässe unverändert.

Drei Schiffe gleichzeitig (Enterprise, Falke, Sternzerstörer, 120 bis 240 Punkte lang): 0,06 bis 0,07 ms mehr pro Bild, mit den neuen Materialien gleich viel wie vorher, Grafikspeicher 11 MB mehr. Ein Schiff wird nur neu gerastert, wenn es sich am Rand um mehr als ein halbes Pixel dreht; drehen sich alle drei in jedem Bild, kosten sie 0,16 bis 0,17 ms (vorher 0,13 bis 0,15 ms).

Stufe 1 allein, drei Galaxien (eine knapp hinter dem Loch, zu zwei Bögen gelinst), vier Sterne, ein Pulsar und ein Jet: 0,23 bis 0,31 ms mehr pro Bild, davon der Jet rund 0,08 ms. Eine einzelne Galaxie oder ein Stern abseits des Lochs kostet um 0,01 ms. Der Jet verlängert das Neuberechnen der Strahlen um 8 bis 13 %. Grafikspeicher: etwa 17 MB mehr.

## Schirme und Animation

### Allgemein und Menüleisten-Symbol

Die Seite **Allgemein** steht ganz oben. Dort liegt alles, was es auch im Menü gibt: Animation, Im Energiesparmodus anhalten, Maus-Modus, Beim Anmelden starten und Beenden. Unten steht der Abschnitt **Updates**: installierte Version, der Schalter **Automatisch nach Updates suchen** (an ist Standard) und der Knopf **Jetzt suchen**. Gibt es eine neue Version, zeigt er „Version X ist da“ mit dem Anfang der Release Notes und den Knöpfen **Installieren**, **Später** und **Diese Version überspringen**. Dazu der Schalter **Menüleisten-Symbol ausblenden**. Er wirkt sofort. Zurück kommst du, indem du die App noch einmal startest, etwa über Spotlight. Dann öffnet sich das Einstellungsfenster. Beim ersten Ausblenden fragt die App einmal nach und nennt genau diesen Weg.

### Schirm oben im Fenster

Oben wählst du zuerst den **Schirm**, dann die **Voreinstellung**. Beim Öffnen ist der Schirm gewählt, auf dem das Fenster liegt. Wählst du einen Schirm, steht sein Name kurz groß in seiner Mitte, damit du weißt, welcher gemeint ist.

- **Ein Schirm gewählt**: Die Voreinstellung gilt nur für ihn. Änderst du einen Wert auf Loch, Scheibe, Farben, Nebel, Sterne, Ränder oder Bewegung und die Voreinstellung nutzt noch ein anderer Schirm, legt die App zuerst eine Kopie an, etwa „Dein Strudel (Ultrawide)“, gibt sie diesem Schirm und ändert die Kopie. Auch Schirme zählen, die gerade nicht angeschlossen sind. Nutzt nur dieser Schirm die Voreinstellung, ändert sich die Voreinstellung selbst.
- **Alle Schirme**: Die Auswahl setzt die Voreinstellung für alle angeschlossenen Schirme, Werte ändern das gemeinsame Preset. Zeigen die Schirme verschiedene Voreinstellungen, sind die Regler gesperrt, bis du einen Schirm oder eine gemeinsame Voreinstellung wählst.

Die Seite **Schirme** zeigt die Lage des Lochs, bei einem gewählten Schirm nur für ihn. Einträge von Schirmen, die gerade fehlen, bleiben in `settings.json` erhalten.

### Animation in drei Stufen

- **Alles**: Scheibe, Nebel, Sterne und Bänder bewegen sich.
- **Nur Ränder**: Loch, Scheibe, Nebel und Sterne stehen still, nur die Bänder an Menüleiste und Dock fließen. Die App zeichnet das stehende Bild einmal und danach pro Bild nur zwei schmale Streifen in eigenen kleinen Metal-Ansichten über den Bändern. Gemessen mit `--bench` auf dem MacBook Air M4 bei 3440 x 1440: 1,7 bis 2,6 ms GPU-Zeit pro Bild für Alles, 0,12 bis 0,14 ms für Nur Ränder. Im Betrieb auf dem eingebauten Schirm (1920 x 1242, 30 Bilder pro Sekunde): etwa 3,2 ms gegen 0,5 ms.
- **Aus**: ein stehendes Bild.

Die Seite **Energie** hat die Bildrate am Netzteil und am Akku, den Schalter **Bei Hitze drosseln** (an ist Standard) und das Standbild für den Sperrbildschirm. Auf der Seite **Allgemein** steht **Bewegung reduzieren beachten** (an ist Standard). Ist „Bewegung reduzieren“ in macOS an, zählt die Animationsstufe als Aus, und ein Hinweis unter der Stufe sagt das. Das Menü nennt den Grund, wenn die App pausiert oder gedrosselt läuft.

Der Maus-Modus läuft bei „Nur Ränder“ weiter. Das Bild wird dann aber nur neu gezeichnet, wenn sich der Zeiger bewegt. Energiesparmodus und Pause bei verdecktem Schreibtisch gelten für alle Stufen. Alte Einstellungsdateien mit `animationOn` laden weiter: an wird Alles, aus wird Aus.

## Hintergrundbild, Bildschirmschoner und Tagesverlauf

- **Standbild als echter Hintergrund** (Energie): Die App legt regelmäßig ein Standbild vom Loch als echtes Hintergrundbild ab. So passen Sperrbildschirm und Mission Control. Das alte Bild merkt sie sich und holt es auf Knopfdruck zurück.
- **Bildschirmschoner**: `./scripts/install.sh` legt `Schwarzes Loch.saver` nach `~/Library/Screen Savers/`. Auswählen in den Systemeinstellungen unter Bildschirmschoner. Er zeigt die Voreinstellung des Hauptschirms.
- **Langsame Veränderung** (Bewegung): Der Blickwinkel pendelt über den Tag, abends wird es dunkler.
- **Video für den Sperrbildschirm**: nicht umgesetzt. Apple zeigt dort nur seine eigenen Aerial-Videos. Die liegen in `/Library/Application Support/com.apple.idleassetsd/Customer/`, gehören root und sind auf diesem Mac nicht heruntergeladen.

Die Standardwerte: 30 Bilder pro Sekunde am Netzteil und am Akku. 60 und 120 gehen unter Energie. Die App pausiert, wenn Fenster den Schreibtisch ganz verdecken.

## Qualität

Vier Stufen wie in Spielen: Akku sparen, Ausgewogen, Hoch und Ultra, getrennt für Netzteil und Akku (Standard: Hoch am Netzteil, Ausgewogen am Akku; eine gespeicherte Wahl bleibt). Unter „Erweitert“ hat jeder Bereich eine eigene Stufe: Loch und Scheibe, Jet, Nebel und Galaxien, Körper und Schiffe, Linsen, Partikel und Schweife. Neben jeder Stufe steht die gemessene Last. Auf 3440 x 1440 mit Sternsystem: Ausgewogen 2,7 ms pro Bild und 108 MB, Hoch etwa +0,05 ms und 193 MB, Ultra etwa +0,25 ms und 258 MB, Akku sparen -0,05 ms und 86 MB. Ein Wechsel wirkt sofort, der Bildschirmschoner nimmt die Stufe am Netzteil. Der Jet ist seit dieser Runde auf jeder Stufe glatt: exakt integriert, Lage in 16 Bit, kubisch hochgerechnet. Details und Messwerte in `docs/objekte-plan.md`, Abschnitt „Qualitätsstufen“. Zum Testen: `--quality 0...3`, `--qa jet=3`, `--bench-q 1`. Ohne `--quality` rendert ein Snapshot mit Ausgewogen. `./scripts/check-referenz.sh <Ordner>` vergleicht die fünf Presets ohne Objekte mit den Referenzbildern, die bei Ausgewogen entstanden sind, und setzt dafür ausdrücklich `--quality 1`.

## Werkzeuge für die Entwicklung

```bash
.build/release/BlackHoleWallpaper --snapshot shots/wide.png --size 3440x1440 --top 24 --bottom 70
.build/release/BlackHoleWallpaper --snapshot x --size 3440x1440 --bench
.build/release/BlackHoleWallpaper --snapshot x --size 3440x1440 --top 24 --bottom 70 --bench --edges
.build/release/BlackHoleWallpaper --snapshot x --size 3440x1440 --top 24 --bottom 70 --edgecheck
```

`--snapshot` rendert ein PNG ohne Fenster. Weitere Schalter: `--preset <id>`, `--hole x,y`, `--time`, `--map` (Auflösung der Strahlenkarte), `--nobox` (ohne scharfe Zone), `--debug 1|2|3|4|5|6|7` (3 Jet-Licht vor und hinter der Scheibe, 4 Maske der Himmelsobjekte, 5 nur das Jet-Licht, 6 Bereich, in dem Körper hinter dem Loch gesucht werden, 7 wo Linsen biegen und wo die Hauptkarte außerhalb des Schirms läge). `--bench` misst die GPU-Zeit pro Bild, mit `--edges` die der Stufe „Nur Ränder“. `--edgecheck` vergleicht die Streifen von „Nur Ränder“ Pixel für Pixel mit dem vollen Bild.

Objekte im Snapshot:

```bash
.build/release/BlackHoleWallpaper --snapshot shots/ring.png --add galaxy:spiral:az=0,el=0,size=1.5
.build/release/BlackHoleWallpaper --snapshot shots/jet.png --preset m87 --add jet:main:beta=0.9
.build/release/BlackHoleWallpaper --snapshot shots/galaxien.png --catalog galaxy
.build/release/BlackHoleWallpaper --diff a.png b.png
```

- `--add art:untertyp[:schlüssel=wert,…]`, mehrfach erlaubt. Schlüssel sind `size`, `brightness`, `seed`, `az`, `el`, `drift`, `driftAngle`, `tint`, `tintAmount` und jeder Regler des Katalogs, etwa `tilt` oder `beta`.
- `--objects datei.json` nimmt eine Szene oder eine Liste von Objekten, `--no-objects` leert die Szene.
- `--catalog galaxy|star|jet|all` zeigt jeden Untertyp als beschriftete Kachel.
- `--motion all|edges|off` rendert wie die Animationsstufe: bei `edges` und `off` steht das Bild bei 20 s, bei `edges` laufen nur die Bänder bis `--time`.
- `--diff a.png b.png` nennt die größte Abweichung pro Kanal und die Zahl abweichender Pixel, `--tol` setzt die erlaubte Abweichung (Standard 1).
- `--add` kennt für Körper zusätzlich `mode` (orbit, flyby, edge, fixed), `radius`, `ecc`, `incl`, `node`, `peri`, `phase`, `tempo`, für feste Körper `x`, `y` und `depth` (front, behind), für Randobjekte `edge`, `dir`, `side`, `offset`, `edgeSpeed`, `edgeGap`, `wobble`, für Vorbeiflüge `passMin`, `passMax`, `interval`, `fly`, für Monde `attach`, und `near=1` macht aus einem Stern einen nahen Stern.
- `--catalog planet|moon|nearstar|asteroid|comet|meteor|belt` zeigt die neuen Arten.
- `--catalog blackHole|wormhole` zeigt zweite Löcher und das Wurmloch. Beim zweiten Loch ist `size` die Masse im Verhältnis zum Hauptloch, auch fest im Bild (`mode=fixed`, mit `depth=behind` hinter der Ebene des Hauptlochs), Regler wie `spin`, `inclination`, `roll`, `jet`.
- `--catalog ship|station` zeigt Schiffe und Stationen, `--only enterprise,falcon` oder `--only "Star Trek"` nur diese Kacheln.
- `--event warp --phase 0.5` friert ein Ereignis ein (mit `--arrival` als Ankunft), `--phases 0.2,0.45,0.7` legt mehrere Phasen nebeneinander. `--vertical` stapelt `--series` und `--phases` untereinander.
- `--add` kennt für Schiffe zusätzlich `events` (0 oder 1), `eventKinds` (etwa `warp+cloak`), `eventInterval` und für eigene Modelle `model` (Dateiname im Ordner Models). `BH_MODELS=/pfad` nimmt einen anderen Modell-Ordner.
- `--export-ship enterprise datei.obj` schreibt ein Bausteinschiff als OBJ, USDA, USDC oder PLY, `--import-check datei` lädt eine Datei wie die App und nennt Dreiecke, Teile, Materialien und Bilder.
- `--series 20,21,22 --crop x,y,b,h` legt mehrere Zeitpunkte nebeneinander in ein Bild, beschriftet, wahlweise auf einen Ausschnitt beschnitten. Mit `--motion edges` läuft dabei nur der Rand weiter.
- `--drop planet,comet` nimmt Arten aus der Szene, etwa um einen Teil einer Voreinstellung zu messen.
- `--bench-ab` misst dieselbe Ansicht ohne und mit Objekten abwechselnd Bild für Bild im selben Lauf und nennt den Median von 480 Bildern, damit Erwärmung und Taktschwankungen beide gleich treffen. `--bench-geo` macht das für das Neuberechnen der Strahlen. `--jet-stats` vergleicht die Helligkeit von Jet und Gegenjet.
- `--bench-passes` misst ebenso abwechselnd, aber pro Pass (Zeitstempel von Metal an den Grenzen jedes Passes), und zeigt, welcher Pass mit Objekten wie viel mehr braucht. `--pace 30` taktet `--bench-ab` und `--bench-passes` wie die laufende App auf 30 Bilder pro Sekunde, dann taktet die GPU zwischen den Bildern herunter wie live. Die Werte streuen damit stark, für Vergleiche besser live messen.

```bash
.build/release/BlackHoleWallpaper --settings-shot shots/einstellungen.png --tab 0
```

Das zeichnet das Einstellungsfenster in ein PNG, Seite 0 bis 11. Es liest `settings.json`, schreibt sie aber nicht. `--all-screens` zeigt die Auswahl „Alle Schirme“, `--locked-demo` dazu einen erfundenen zweiten Schirm mit anderer Voreinstellung, also den gesperrten Zustand. `--objects-demo` legt für das Bild eine feste Szene in die Voreinstellung (Seite 7), `--ships-demo` eine mit Schiffen und einer Station, `--exotics-demo` eine mit zweitem Loch und dem SciFi-Hafen, `--height` macht das Fenster höher.

```bash
.build/release/BlackHoleWallpaper --selftest
```

Spielt die Kopier-Regeln pro Schirm mit zwei erfundenen Schirmen durch, ohne Bildschirm und ohne `settings.json` anzufassen. Dazu die Objekte: alte Dateien ohne Szene, unbekannte Arten, fehlende Schlüssel, kaputte Elemente, Speichern und Laden, Kopie pro Schirm. Mit `--settings-file kopie.json` prüft er zusätzlich, dass eine echte Einstellungsdatei ohne Verlust lädt. Exit-Code 0 heißt bestanden.

Bildrate zum Testen festnageln: `defaults write io.github.digitaliq.blackholewallpaper fpsOverride 30`

## Aufbau

- `Shaders.swift`: Metal-Code. `geoFrag` verfolgt die Strahlen einmal pro Ansicht, `geoFragJet` sammelt dabei zusätzlich das Licht des Jets und speichert das Ergebnis in Texturen: einmal in halber Auflösung für den ganzen Schirm und einmal in voller Auflösung für ein Quadrat um das Loch, wo die scharfen Kanten sind. `bakeDisk` backt das Gasmuster der Scheibe. `dispFrag` läuft jedes Bild und animiert nur noch. `edgeFrag` zeichnet bei „Nur Ränder“ nur die Streifen an den Bändern.
- `Renderer.swift`: Metal-Pipelines und Texturen pro Bildschirm.
- `Wallpaper.swift`: ein Fenster pro Bildschirm auf Schreibtisch-Ebene, dazu die zwei Streifen-Ansichten für „Nur Ränder“.
- `AppDelegate.swift`: Menü, Energiesparen, Bildschirmwechsel.
- `Settings.swift`, `Store.swift`: Voreinstellungen, Paletten, Einstellungen pro Schirm und die JSON-Datei.
- `SettingsView.swift`: das Einstellungsfenster in SwiftUI und die kurze Namensanzeige auf einem Schirm.
- `Objects.swift`: das Datenmodell der Szene, nachsichtig beim Laden.
- `ObjectCatalog.swift`: alle Untertypen mit ihren Reglern, Standardwerten und Würfeln.
- `ObjectSystem.swift`: pro Bild Uhren, Richtungen am Himmel, Pulsar-Blitze und die Werte für die Shader.
- `ObjectShaders.swift`: Metal-Code für Himmelsobjekte, Jet-Licht und das Backen der Galaxien. Eine Maske in 8 x 8 Pixel großen Zellen sagt, wo welches Objekt zu sehen sein kann; nur dort wird gerechnet.
- `Orbits.swift`: Kamera-Rahmen mit derselben Abbildung von Pixel und Richtung wie die Strahlen, Kepler-Bahnen, Vorbeiflug, Randwege, Punktlinse.
- `BodyRenderer.swift`: pro Bild Lage, Licht und Kacheln der Körper, Partikel, Kometenschweife, Meteore, Lichthof und Beugungsstrahlen der Sterne. Ein Kachel-Speicher zeichnet einen Körper nur neu, wenn sich sichtbar etwas geändert hat.
- `BodyShaders.swift`: Metal-Code der Körper. Planeten-Oberflächen werden einmal gebacken, jede Kachel schreibt ein Compute-Kernel in den Atlas. `dispFrag` holt Körper hinter dem Loch über die dünne Linse (Weg L), Körper vor dem Loch, Schweife, Meteore und Lichthöfe zeichnet derselbe Pass gleich danach darüber (Weg F). Weiches Licht wie Dunst und Schweife sammelt ein kleiner Lichtpuffer in halber oder viertel Auflösung.
- `ObjectsTab.swift`: die Seite Objekte.
- `ShipCatalog.swift`: die Bausteinlisten aller Schiffe und Stationen und die Ereignisse.
- `MeshBuilder.swift`: die Bausteine als Dreiecksnetze, Import und Export über ModelIO.
- `ShipSystem.swift`: Ereignis-Fahrplan, Lage der Schiffe im Raum.
- `Lenses.swift`: zweite Löcher, Wurmlöcher und Tore als Linsen: Lage pro Bild, Daten für die Shader, die kleinen Strahlenkarten der Löcher (geteilt zwischen Schirmen).
- `RunPolicy.swift`: Laufzustand aus Einstellungen, Hitze, Bewegung reduzieren und Pausengründen; `SystemWatch` sammelt Sperre, Schlaf, Bildschirmschoner und Sitzungswechsel.
- `Welcome.swift`: das Willkommensfenster beim ersten Start.
- `Profiler.swift`: GPU-Zeit pro Pass aus den Zeitstempeln von Metal, für `--bench-passes` und `BH_PROFILE=1`.
- `LensShaders.swift`: Metal-Code der Linsen: Ablenkung vor und hinter der Ebene des Hauptlochs, Schatten, Ring, Scheibe und Jet des zweiten Lochs, die andere Seite von Wurmloch und Tor, Kawoosh und Durchflug. Die Pässe mit Linsen sind eigene Varianten (Funktionskonstanten), ohne Linsen laufen die alten.
- `ShipShaders.swift`: Metal-Code der Schiffe: Materialien mit Metallanteil und Rauheit, Spiegelung von Himmel und Scheibe, Rumpfplatten, Fenster, Glühen, Folie, Solarzellen, dazu der kleine Himmel für die Spiegelungen (einmal pro Voreinstellung gebacken). Jedes Schiff wird mit Tiefe und vierfacher Kantenglättung in eine Kachel gerastert und in den Körper-Atlas kopiert, undurchsichtige Teile ohne Mischen, damit verdeckte Flächen nichts kosten.
- `ModelStore.swift`: der Ordner Models und die Kopie für den Bildschirmschoner.
- `ModelImage.swift`: Bilder von Modelldateien über ImageIO, höchstens 1024 Pixel.
- `GLTFLoader.swift`: eigener Lader für glTF 2.0 und GLB (ModelIO kann kein glTF): Puffer, Accessoren, Knoten mit Transformationen, mehrere Primitives, Materialien und Bilder.
- `UIText.swift`: die neuen Texte der Oberfläche an einer Stelle, für eine spätere Übersetzung.
- `Quality.swift`: die Qualitätsstufen, was jede Stufe je Bereich bedeutet, die gemessene Last für die Seite „Qualität“ und die Übernahme von `mapScale` aus alten Dateien.
- `SelfTest.swift`: `--selftest`.
- `Updater.swift`: Update-Suche, Download, Prüfsumme, Austausch und Neustart, dazu `--update-check` und `--update-install`.
- `SelfTestUpdate.swift`: Selbsttest des Updaters mit einer Beispielantwort von GitHub.
- `Stills.swift`: Standbild als echter Hintergrund und die Veränderung über den Tag.
- `Saver/BlackHoleSaverView.swift`: der Bildschirmschoner. `scripts/build-saver.sh` baut ihn aus denselben Renderer-Dateien.

Zum Messen: `BH_DEBUG=1 .build/release/BlackHoleWallpaper` schreibt alle fünf Sekunden Bilder pro Sekunde und GPU-Zeit pro Bild ins Log, bei „Nur Ränder“ für jeden Streifen einzeln. Mit `BH_SETTINGS=/pfad/kopie.json` lädt und speichert die App eine andere Einstellungsdatei und lässt den Bildschirmschoner in Ruhe, so misst du eine Voreinstellung live, ohne deine eigenen Einstellungen anzufassen. Mit zusätzlich `BH_PROFILE=1` steht im Log auch die GPU-Zeit pro Pass. Das Log nennt auch jeden Wechsel des Laufzustands (angehalten, gedrosselt, Standbild) und zählt alle fünf Sekunden die gestarteten Bilder, bei Pause null.

Tests für das Willkommensfenster und die Pause: `BH_FORCE_WELCOME=1` zeigt das Willkommensfenster auch mit Einstellungsdatei, `--settings-shot x.png --welcome` macht ein Bild davon (mit `--lang en` oder `de`). Bei einem Lauf mit `BH_SETTINGS` täuscht die verteilte Mitteilung `io.github.digitaliq.blackholewallpaper.test` Zustände vor, ihr Objekt ist `lock`, `unlock`, `heat:nominal|fair|serious|critical`, `heat:off` oder `motion:on|off|auto`. Mit `BH_FAKE_REDUCE_MOTION=1` zeigen die Bilder der Einstellungen den Hinweis zu „Bewegung reduzieren“. Ein Lauf auf einer Einstellungskopie legt nie ein Anmeldeobjekt an.

### Updates

Der Updater fragt `https://api.github.com/repos/DigitalIQ/blackhole-wallpaper/releases/latest`, ignoriert Entwürfe und Vorabversionen und vergleicht `tag_name` mit `CFBundleShortVersionString`. Installiert wird nur `BlackHoleWallpaper-<Version>.dmg` zusammen mit `BlackHoleWallpaper-<Version>.dmg.sha256` aus demselben Release. Ablauf: laden nach `Application Support/BlackHoleWallpaper/Updates`, SHA-256 prüfen, schreibgeschützt einhängen, Bundle-ID, Version und Signatur prüfen, App und Bildschirmschoner neben die alten kopieren, per Umbenennen tauschen, Quarantäne-Markierung entfernen und die neue App starten, sobald die alte beendet ist. Bei jedem Fehler bleibt die alte Version. Eine mit Homebrew installierte Kopie ersetzt sich nicht selbst, eine Kopie in einem Ordner ohne Schreibrecht öffnet die Download-Seite.

```bash
BH_UPDATE_FEED=/pfad/feed.json BH_SETTINGS=/pfad/kopie.json BlackHoleWallpaper.app/Contents/MacOS/BlackHoleWallpaper --update-check
./scripts/e2e-update.sh 1.0.1
```

`--update-check` zeigt, was der Updater tun würde, und ändert nichts. `--update-install` macht es ohne Fenster. `BH_UPDATE_FEED` nimmt einen Dateipfad oder eine http(s)- oder file-URL in der Form der GitHub-Antwort; damit dürfen die Dateien von überall kommen, ohne nur per https von github.com. `BH_SAVER_DIR` ersetzt `~/Library/Screen Savers`; mit `BH_SETTINGS` und ohne `BH_SAVER_DIR` bleibt der installierte Bildschirmschoner unberührt. `scripts/e2e-update.sh` baut die aktuelle Version nach `.tmp/e2e`, baut eine DMG mit höherer Version (`BH_VERSION`, die Datei `VERSION` bleibt), aktualisiert die Kopie über einen lokalen Feed, prüft den Neustart mit der neuen Version und beendet sie.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Copyright 2026 DigitalIQ.

Star Trek, Star Wars, Battlestar Galactica, Babylon 5, Firefly, The Expanse, Mass Effect, Stargate und die anderen genannten Werke gehören ihren Inhabern. Dieses Projekt steht in keiner Verbindung zu ihnen. Die Schiffe sind einfache Formen, im Code gebaut, keine kopierten Modelle.
