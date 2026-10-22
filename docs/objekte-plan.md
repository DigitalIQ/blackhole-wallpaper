# Plan: Objekte im Umfeld des Schwarzen Lochs

Stand 2026-10-11. Nur Plan, kein App-Code. Grundlage: Code im Arbeitsbaum (inklusive der noch nicht committeten Änderungen des parallelen Agenten: Monitor-Auswahl, `AnimationMode`, Band-Streifen), README, Archiv-Notiz `06 Archiv/Schwarzes Loch Hintergrund.md`.

## 0. Ausgangslage im Code

**Was die Strahlenkarte pro Texel speichert** (`geoFrag`, `Shaders.swift`):

| Ziel | Format | Inhalt |
| --- | --- | --- |
| `sky` (color 0) | rgba16Unorm | xy: Fluchtrichtung des Strahls, oktaedrisch kodiert, **im Kamerasystem** (z = Blick aufs Loch). z: Windung / 32 (Photonenring). w: Fangzahl aus R(r), null genau an der Schattenkante |
| `d1` (color 1) | rgba16Float | erster Scheibentreffer: r, cos φ, sin φ, Frequenzverhältnis g (Doppler plus Gravitation). r = 1000 heißt kein Treffer |
| `d2` (color 2) | rgba16Float | zweiter Scheibentreffer, gleich aufgebaut |

Kein Strahlweg, keine Austrittsposition, kein freier Kanal. Die Fluchtrichtung ist die Richtung beim Abbruch bei r > 1,6 r0 (r0 = Kamera-Abstand, Standard 90 M). Karte in halber Auflösung, dazu die scharfe Box (2 x 2 Strahlen pro Pixel) um das Loch.

**Pässe heute:** `geoFrag` (nur bei Ansichtswechsel, gedrosselt 0,12 s), `bakeDisk`, `bakeNebula`, `bakeEdgeNoise` (einmalig), `nebFrag` (halbe Auflösung, etwa 20 Hz), `dispFrag` (jedes Bild). Neu vom parallelen Agenten: `dispFrag` liest `P.region` und hat eine Stufe 1 (lineare Basis ohne Bandlicht), `edgeFrag` zeichnet in „Nur Ränder“ nur die Bandstreifen über einer gecachten Basis, die Streifen sind eigene `MTKView`s (`BandStrip`), Bandzeit ist `P.nebp.y = time + edgeLead`. `FrameParams` endet jetzt mit `region` nach `pal[8]`.

**Pixel und Richtung:** `geoFrag` setzt pro Pixel Stoßparameter `alpha = (px.x - c.x) / S * cam.w - 2 a sin i`, `beta = -(px.y - c.y) / S * cam.w` mit `S = min(W, H)`, `cam.w = 5,2 / holeSize` (M pro kurzer Schirmseite). Ohne Loch zeigt dieses Pixel in Richtung `flatDir(px) = (alpha / r0, beta / r0, sqrt(1 - (alpha² + beta²) / r0²))` im Kamerasystem. Diese Abbildung und ihre Umkehrung `pxOf(dir)` sind die Brücke zwischen Bildschirm und 3D-Szene.

**Weitere Fakten, die der Plan nutzt:** `Look` ist pro Preset; der parallele Agent gibt jedem Monitor beim ersten Bearbeiten eine eigene Preset-Kopie (`Store.willEditLook()`, `store.binding(_:)` ruft es auf, `store.lookLocked`). `Look.decodeLenient` mischt JSON mit Standardwerten. Der Bildschirmschoner läuft in einer Sandbox und bekommt `saver.json` kopiert. `--snapshot`, `--bench`, `--mem`, `--settings-shot --tab`, `--selftest` existieren. Bench zeigt etwa ein Drittel der Live-GPU-Zeit (1,1 bis 1,4 ms gegen 3,6 ms).

## 1. Architektur-Entscheidungen

1. **Objekte leben im `Look`** als `look.objects: ObjectScene`. Damit hat jedes Preset und über die Monitor-Kopien jeder Monitor seine eigene Szene, der Schoner bekommt sie mit `SaverConfig.look`, Werkseinstellung und Preset-Reset funktionieren ohne Zusatzcode.
2. **Drei Darstellungswege** je nach Lage des Objekts, pro Bild auf der CPU entschieden:
   - **S (Himmel):** ferne Objekte (Galaxien, ferne Sterne, Pulsare). Nachschlag über die gecachte Fluchtrichtung in `dispFrag`. Exakte Kerr-Biegung inklusive Einstein-Ring und Gegenbild, fast ohne Kosten.
   - **L (Linsen-Nachschlag):** Körper in der Nähe des Lochs (Planeten, Monde, nahe Sterne, Schiffe auf Bahnen). Werden ungebogen in einen Sprite-Atlas gerendert, `dispFrag` schlägt sie pro Pixel an der gelinsten Stelle nach: `β = normalize(mix(θ, dir, w))` mit `θ = flatDir(px)`, `dir` = Fluchtrichtung aus der Karte, `w = clamp(D_ls / D_s, 0, 1)` (D_ls = Tiefe hinter der Lochebene, D_s = Tiefe ab Kamera). Das ist die Dünne-Linse-Näherung, gespeist mit der echten Kerr-Ablenkung aus der Karte. Mehrfachbilder entstehen von selbst. Verdeckung durch Schatten (`1 - captured`) und durch die Scheibe (Tiefe des Scheibentreffers pro Pixel gegen Objekttiefe).
   - **F (Vordergrund):** alles vor dem Loch ohne Überlappung mit der Lochzone, Randobjekte, Partikel, Meteore, Effekte. Instanzierte Quads nach `dispFrag`, mit Alpha auf das Drawable geblendet, eigenes Tone-Mapping (`aces`, Gamma) im Shader.
   Ein Körper kann pro Bild zwischen L und F wechseln, weil beide aus demselben Atlas-Sprite lesen.
3. **Jet beim Strahlverfolgen sammeln:** zweite Variante von `geoFrag` mit viertem Ziel `jet` (rgba16Float): Emission vor dem ersten Scheibentreffer, Emission danach, emissionsgewichtete Lage entlang der Achse (je 0 bis 1). Doppler-Verstärkung wird pro Strahlsegment mit der echten Photonenrichtung eingerechnet. Pro Bild nur Farbe, Knoten, Pulsieren. Jet-Geometrie, Tempo β und Doppler-Stärke lösen eine Neuberechnung aus wie heute Spin oder Blickwinkel.
4. **Zweites Loch und Wurmloch als Bildschirm-Linsen** wie die Maus-Linse, verallgemeinert zu einer Linsenliste (Maus plus höchstens zwei Objekt-Linsen), angewandt in `dispFrag` und `nebFrag` vor dem Kartenzugriff. Das zweite Loch bekommt eine eigene kleine Strahlenkarte (gleiche `geoFrag`, eigene Parameter, eigener Jet), damit Schatten, Photonenring und gebogene Scheibe echt aussehen.
5. **Raumschiffe und Stationen als Dreiecksnetze aus Bausteinen** (Kapsel, Zylinder, Torus, Keil, Ellipsoid …), im Code erzeugt, gerastert in den Sprite-Atlas mit Tiefenpuffer und 4x MSAA (memoryless). Gleicher Weg für eigene OBJ/USDZ-Modelle über ModelIO. Begründung: Rasterung kostet bei 50 bis 300 px großen Schiffen einen Bruchteil von SDF-Raymarching (24 Bausteine x 48 Schritte pro Pixel), Kanten sind sauber, eigene Modelle brauchen ohnehin Rasterung. Die Bausteinlisten bleiben SDF-tauglich (nur Vereinigung), ein späterer SDF-Weg könnte sie lesen. Weicht von „etwa als SDF-Modelle“ ab, deshalb offene Frage 1.
6. **Bewegung ist eine reine Funktion von Uhr, Seed und Parametern.** Keine gespeicherten Zustände, keine Zufallszahlen zur Laufzeit. Ereignisse (Warp, Meteore) kommen aus `hash(seed, Intervallnummer)`. Damit sind `--snapshot --time`, Standbild, Schoner und Wallpaper deterministisch gleich.
7. **Parameter pro Typ als Wörterbuch** `params: [String: Float]` plus Katalog mit `ParamSpec` (Schlüssel, Titel, Bereich, Standard, Format, Hilfe, Gruppe, Flags). Die Einstellungsseite wird aus dem Katalog erzeugt, Rückgängig-Symbole nehmen den Katalog-Standard, unbekannte Schlüssel werden beim Laden ignoriert, fehlende mit Standard gefüllt.
8. **Neue Dateien statt großer Eingriffe** in die vom parallelen Agenten geänderten Dateien. In `SettingsView.swift` nur Seiteneintrag und `case`, in `AppDelegate.swift` nur der Modell-Export für den Schoner (Stufe 3).

### Bewertung der Denkrichtung aus dem Auftrag

| Idee | Urteil |
| --- | --- |
| Ferne Objekte über gecachte Fluchtrichtung | Trägt. Exakt für Quellen im Unendlichen. Im Photonenring (Windung > 5) springt die Richtung von Texel zu Texel, dort Objekte ausblenden wie heute das Ringleuchten, sonst Rauschen. |
| Jet beim Verfolgen sammeln und cachen | Trägt. Einschränkungen: Jet-Länge höchstens 1,5 r0 (Integration endet bei 1,6 r0); Präzession des Hauptjets bräuchte Neuberechnung pro Bild, entfällt; Kamera darf nicht im Jet sitzen (Breite auf 0,6 x Achsabstand der Kamera kappen). Tempo-Regler kostet eine Neuberechnung. |
| Doppler pro Bild | Teilweise. Pro Bild nur Knotentempo und Pulsieren. Doppler-Helligkeit hängt am Strahl und wird gecacht. Folge der echten Physik: bei 66° Blickwinkel und β = 0,99 sind beide Jets abgeschwächt, erst bei kleinen Winkeln (M87*, 17°) leuchtet der zulaufende Jet hell. Standard β = 0,8. |
| Nahe Objekte mit Schwachfeld-Näherung | Trägt besser als gedacht: Dünne-Linse mit der Kerr-Ablenkung aus der Karte statt Formel. Fehlerhaft nur bei Objekten, die durch den Photonenring wandern (ausblenden). |
| Objekte vor dem Loch und an den Rändern ungebogen | Trägt (Weg F). |
| 3D-Objekte per SDF-Raymarching im Bildausschnitt | Trägt technisch, ist aber der größte GPU-Posten. Ersetzt durch Rasterung (Entscheidung 5). |
| Zweites Loch und Wurmloch als Bildschirm-Linse | Trägt. Zweites Loch zusätzlich mit eigener Mini-Strahlenkarte (wenige MB, nur bei Änderung neu). Wird es vom Hauptloch gelinst (Doppelsystem), wird nur seine Mittelposition verschoben und im Schatten verdeckt, nicht vervielfacht. |
| Partikel instanziert | Trägt. Bahnen im Vertex-Shader, Linsung als Punktlinse vorwärts (Haupt- und Gegenbild als zwei Instanzen), Verdeckung durch Schatten und Scheibe analytisch. |

## 2. Datenmodell

Neue Datei `Objects.swift`. Alle Typen mit eigenem `init(from:)`, das jeden Schlüssel per `decodeIfPresent` mit Standard liest. Enums mit String-Rohwert, unbekannte Werte fallen auf den Standard zurück.

```swift
/// All objects of one look. Lives in Look, so each preset (and via the monitor copies each screen) has its own.
struct ObjectScene: Codable, Equatable {
    var on = true
    var speed: Float = 1              // tempo factor for all object motion
    var detail = 1                    // 0 sparsam, 1 normal, 2 hoch (atlas scale, particle counts, caps)
    var items: [SpaceObject] = []
}

enum ObjectKind: String, Codable, CaseIterable {
    case galaxy, star, jet, planet, moon, asteroid, belt, comet, meteor, blackHole, wormhole, ship, station, model
}

struct SpaceObject: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var on = true
    var kind = "planet"               // ObjectKind raw value as String: unknown kinds survive a round trip, are not drawn
    var variant = ""                  // catalog id, e.g. "ringed", "G", "enterpriseD"
    var seed: UInt32 = 1
    var size: Float = 1               // unit depends on motion.mode, see below
    var brightness: Float = 1
    var tint = "#FFFFFF"
    var tintAmount: Float = 0
    var motion = Motion()
    var params: [String: Float] = [:] // missing key = catalog default
    var events = ObjectEvents()
    var attach = ""                   // jet: "main" or id of a blackHole; moon: id of its planet
    var model = ""                    // kind model: file name in Models/
}

enum MotionMode: String, Codable { case orbit, flyby, edge, fixed, sky, attached }

struct Motion: Codable, Equatable {
    var mode = MotionMode.orbit
    // orbit, in M and degrees, relative to the disk plane of the main hole
    var radius: Float = 40, eccentricity: Float = 0, inclination: Float = 0
    var node: Float = 0, periapsis: Float = 0, phase: Float = 0, tempo: Float = 1
    var precession = true
    // flyby
    var passMin: Float = 15, passMax: Float = 60, interval: Float = 90, flySpeed: Float = 1
    var side = "both"                 // front, behind, both
    // edge band
    var edge = "bottom"               // top, bottom, both
    var direction = "right"           // left, right, alternate, random
    var offset: Float = 10            // pt, positive into the picture
    var edgeSpeed: Float = 60         // pt/s
    var edgeGap: Float = 30           // s between passes
    var wobble: Float = 0
    // fixed
    var x: Float = 0.75, y: Float = 0.3   // screen uv
    var depth = "front"               // front, behind
    var spin: Float = 0               // deg/s
    // sky, camera frame, degrees from the line of sight through the hole
    var azimuth: Float = 0, elevation: Float = 0
    var drift: Float = 0, driftAngle: Float = 0   // deg/min, direction of drift
}

struct ObjectEvents: Codable, Equatable {
    var on = false
    var kinds: [String] = []          // subset of the variant's allowed events
    var interval: Float = 120         // mean seconds between events
}
```

**Einheit von `size`:** orbit, flyby, attached: Radius in M (Schiffe: Länge in M; zweites Loch: Masse relativ zum Hauptloch). edge, fixed: Höhe in pt. sky: Winkeldurchmesser in Grad. Beim Wechsel der Bewegungsart rechnet die UI `size` so um, dass die scheinbare Größe gleich bleibt.

**Seeds:** `UInt32`, steuern Aussehen (Oberfläche, Ringe, Galaxienform, Schiffs-Lichter) und Ereigniszeiten. Würfel-Knopf setzt neuen Seed und würfelt die Parameter mit `randomRange` aus dem Katalog.

**Einbindung in `Look` (`Settings.swift`):**
- `var objects = ObjectScene()`.
- `geometryKey` hängt `objects.jetGeometryKey` an: Werte des Hauptloch-Jets (on, length, width, shape, base, beta, doppler, counterJet), leer wenn kein Jet. Ab Stufe 4 zusätzlich nichts, die Mini-Karten des zweiten Lochs haben einen eigenen Schlüssel im Renderer.
- `decodeLenient`: `"objects"` in die Liste der verschachtelt gemischten Schlüssel aufnehmen (wie `edgeTop`). `items` dekodiert `SpaceObject.init(from:)` einzeln; ein kaputtes Element wird übersprungen, nicht die ganze Szene.
- Eingebaute Presets bekommen keine Objekte. Alte `settings.json` laden unverändert, Szene leer.

**JSON-Beispiel:**

```json
"objects": { "on": true, "speed": 1, "detail": 1, "items": [
  { "id": "6F1C…", "name": "Ringplanet", "on": true, "kind": "planet", "variant": "ringed",
    "seed": 4711, "size": 4, "brightness": 1, "tint": "#FFFFFF", "tintAmount": 0,
    "motion": { "mode": "orbit", "radius": 60, "eccentricity": 0.2, "inclination": 12, "phase": 0.3 },
    "params": { "ringInner": 1.4, "ringOuter": 2.4, "bands": 0.6 } } ] }
```

**Katalog (`ObjectCatalog.swift`):**

```swift
struct ParamSpec {
    let key: String, title: String
    let range: ClosedRange<Float>, def: Float
    var format = "%.2f", unit = "", help: String? = nil, group = "Aussehen"
    var bake = false        // change re-bakes a texture (galaxy, planet surface)
    var geometry = false    // change re-traces rays (main jet)
    var random: ClosedRange<Float>? = nil   // range for the dice, nil = range
    var toggle = false      // shown as Toggle, 0/1
    var options: [String]? = nil            // shown as Picker, index as Float
}
enum Cost { case leicht, mittel, schwer }
struct VariantSpec {
    let id: String, title: String, kind: ObjectKind
    let menu: [String]                 // submenu path, e.g. ["Raumschiffe", "Star Trek"]
    let params: [ParamSpec]            // shared kind params + variant params
    let modes: [MotionMode]            // allowed motion modes, first = default
    let events: [String]
    let cost: Cost, stage: Int
    let make: (UInt32) -> SpaceObject  // defaults incl. demo placement that is visible in frame
}
```

## 3. Katalog

Gemeinsam für alle: Größe, Helligkeit, Tönung (Farbe und Stärke), Seed, Bewegung. Unten nur die typspezifischen Regler. Schlüssel in Klammern.

### 3.1 Galaxien (Weg S, gebacken in Galaxie-Atlas)

Untertypen: Spirale (Sa, Sb, Sc über Windung), Balkenspirale, Kantenansicht (Spirale, Neigung 86°, Staubband), Elliptisch (E0 bis E7 über Abplattung), Linsenförmig (S0), Irregulär, Ringgalaxie (Hoag-artig), Wechselwirkendes Paar (zwei Galaxien mit Gezeitenbrücke), Quasar (heller Kern, kleine Jets, schwacher Wirt).

Regler: Arme (`arms` 2 bis 6), Windung (`winding`), Balken (`bar`), Kern (`bulge`), Kernhelligkeit (`core`), Staubbahnen (`dust`), Sternentstehung (`starForming`, blaue Knoten, rosa HII-Flecken), Farbe jung/alt (`youngMix`), Neigung (`tilt` 0 bis 90°), Drehwinkel (`angle`), Abplattung (`flatten`, elliptisch). Alles außer `angle` ist `bake`. Bewegung: nur `sky`, Drift für Linsen-Durchgänge.

### 3.2 Sterne und Sonnen (fern: Weg S analytisch; nah: Körper ab Stufe 2)

Untertypen: Hauptreihe O, B, A, F, G, K, M; Roter Riese; Roter Überriese; Blauer Überriese; Weißer Zwerg; Brauner Zwerg; Neutronenstern; Pulsar; Magnetar; Wolf-Rayet mit Nebelhülle; Cepheide; Doppelstern.

Regler: Temperatur (`temperature` K, Standard aus Klasse, Farbe über vorhandenes `blackbody`), Glühen (`glow`), Beugungsstrahlen (`spikes` 0, 4, 6, 8 als Picker; Kamera-Effekt, deshalb ungebogen im Weg F und nur außerhalb von 3 Schattenradien; ab Stufe 2), Pulsieren (`pulseDepth`, `pulsePeriod`, Cepheide), Pulsar: Drehperiode (`spinPeriod` s), Strahlbreite (`beamWidth`), Strahlneigung (`beamTilt`), sichtbare Lichtkegel (`coneGlow`); Magnetar: Ausbrüche (`flareRate`); Doppelstern: Abstand (`separation`), Periode, zweite Temperatur (`temperature2`), Massenstrom (`stream`, ab Stufe 2). Nah zusätzlich: Granulation (`granulation`), Flecken (`spots`), Protuberanzen (`prominences`), Korona (`corona`). Nahe Sterne beleuchten Planeten und Schiffe.

### 3.3 Relativistischer Jet (Stufe 1 am Hauptloch, Stufe 4 am zweiten Loch)

Regler (alle mit `geometry`, außer Farbe, Knoten, Pulsieren, Helligkeit): Länge (`length` M, 10 bis 1,5 r0), Breite an der Basis (`width` M), Form (`shape` 0,3 bis 1, 0,5 parabolisch wie M87, 1 Kegel), Basis-Höhe (`base` M), Tempo (`beta` 0,1 bis 0,995), Doppler-Stärke (`doppler` 0 bis 1, 1 = echt), Gegenjet (`counterJet`). Pro Bild: Farbe (`colourMode`: Synchrotron blauweiß, Palette, eigene über `tint`), Knoten-Kontrast (`knots`), Knotenabstand (`knotSpacing`), Knotentempo (`knotPeriod` s pro Durchlauf), Pulsieren (`pulse`, `pulsePeriod`). Knotentempo von Jet und Gegenjet im Verhältnis der scheinbaren Geschwindigkeiten `β sinθ / (1 ∓ β cosθ)`, bei M87* also scheinbar überlichtschnell.

### 3.4 Planeten und Monde (Körper, ab Stufe 2)

Untertypen Planet: Gestein (verkratert, Merkur-artig), Wüste (Mars-artig), Erdähnlich, Ozeanwelt, Eis (Europa-artig, Risse), Lava, Gasriese (Jupiter-Bänder, Sturmflecken), Ringplanet (Gasriese mit Ringen), Eisriese (Neptun-artig), Heißer Jupiter (glühende Tagseite).
Untertypen Mond (`attach` = Planet-ID, Bahn in Planetenradien): Grau verkratert, Io-artig vulkanisch, Europa-artig, Titan-artig dunstig, Knolle (Phobos).

Regler: Tageslänge (`rotation` s), Achsneigung (`axialTilt`), Atmosphäre (`atmosphere`, `atmoHue`), Wolken (`clouds`, `cloudSpeed`), Ozeanhöhe (`ocean`), Krater (`craters`), Bänder (`bands`), Stürme (`storms`), Eisglanz (`specular`), Stadtlichter Nachtseite (`nightLights`), Glut (`emissive`, Lava und Heißer Jupiter), Farbton (`hueShift`), Ringe (`rings` an/aus für jeden Typ, `ringInner`, `ringOuter` in Planetenradien, `ringDensity`, `ringHue`, Cassini-Lücke `ringGap`; Ringe liegen in der Äquatorebene, Schatten Planet auf Ring und Ring auf Planet). Oberfläche wird je Seed in eine Rektangular-Textur gebacken (`bake`).

### 3.5 Asteroiden, Gürtel, Kometen, Meteore (ab Stufe 2)

- **Einzelner Asteroid** (Körper): Streckung (`elongation`), Krater, Drehung, Gesteinsart (`rockType`: kohlig dunkel, silikatisch, metallisch, Eis).
- **Gürtel ums Loch** (Partikel): Innen- und Außenradius (`rInner`, `rOuter` M), Dicke (`thickness` °), Neigung (Bewegung `inclination`), Anzahl (`count` bis 20 000), Größenverteilung (`sizeMin`, `sizeMax` px), Klumpung (`clumping`), Gesteinsart, Staubglühen (`dustGlow`). Bahnen nach Kepler, innen schneller.
- **Trümmerstrom am Rand** (Partikel, `edge`): Anzahl, Streuung (`spread`), Tempo.
- **Staub- oder Eisring** (Partikel sehr fein, additiv): Dichte, Farbton.
- **Komet** (Körper plus Schweif-Sprite): Kerngröße, Koma (`coma`), Ionenschweif (`ionTail`, blau, zeigt exakt vom Licht weg), Staubschweif (`dustTail`, gelblich, gekrümmt entlang der Bahn), Bahn stark exzentrisch (e 0,7 bis 0,95). Lichtquelle ist die Scheibe des Hauptlochs oder der hellste Stern.
- **Meteore** (Weg F, flüchtig): Sternschnuppe (`rate` pro Minute, `trail` Länge, Tempo, Farbe), Schauer (Radiant `radiantX`, `radiantY`, Ausbruchsdauer), Feuerkugel (Helligkeit, Zerfall in Fragmente `fragments`, Rauchspur `smoke` s).

### 3.6 Zweites Schwarzes Loch (Stufe 4)

Untertypen: Ohne Scheibe (nur Schatten und Linse), Mit Scheibe, Mit Scheibe und Jet (legt ein `jet`-Objekt mit `attach` an). Regler: Spin (`spin`), eigener Blickwinkel (`inclination`), Scheiben-Außenradius (`diskOuter`), Scheibenhelligkeit, Scheibentempo (`diskPeriod`), Farbton gegen Hauptpalette (`hueShift`), Ringleuchten (`ringGlow`). Bewegung: Bahn ums Hauptloch (Doppelsystem; das Hauptloch bleibt fest, künstlerisch), Vorbeiflug, fest.

### 3.7 Wurmloch (Stufe 4)

Untertypen: Kugel (Interstellar-artig), Ring-Tor (Rahmen aus Torus wie Expanse-Ring oder Stargate). Regler: Kehlenradius (`size`), Linsenstärke (`lens`), Andere Seite (`otherSide`: fremder Nebel, eigener Himmel gespiegelt, Galaxie in der Mitte), Farbton der anderen Seite (`otherHue`), eigener Nebel (`ownNebula`, kostet 8 MB), Randleuchten (`rimGlow`), Schimmern (`ripple`).

### 3.8 Raumschiffe und Stationen (Stufe 3)

Bausteine: K Kapsel, Z Zylinder, Ke Kegelstumpf, S Kugel, E Ellipsoid, Q Quader, Keil (extrudiertes Dreieck), P Sechseck-Prisma, T Torus (auch Segment), X Extrusion aus 2D-Umriss. Materialien: Hülle hell, Hülle dunkel, Akzent, Fenster (Lichtpunkte per Hash), Glühen (Farbe), Gold-Folie, Solarpaneel. Maße in Schiffslängen, Längsachse +x.

Gemeinsame Regler: Hüllenfarbe (`hullHue`, `hullBright`), Glühfarbe (`glowHue`), Glühen (`glow`), Fensterlichter (`windows`), Eigendrehung (`selfSpin` °/s, Stationen), Ereignisse.

| Universum | Objekt | Grobform aus Bausteinen | Ereignis |
| --- | --- | --- | --- |
| Star Trek | Enterprise NCC-1701 | Untertasse X-Ellipse flach mit S-Kuppel, Hals Q schräg, Rumpf Z mit Deflektor Ke (orange), 2 Gondeln Z auf Pylonen Q, Bussard-Kappen S rot | Warp |
| | Enterprise-D | Untertasse E breit flach, kurzer Hals Q, Rumpf E flach, Gondeln Z lang mit blauem Seitenglühen | Warp |
| | Voyager | Pfeil-Untertasse aus Keil + E, Rumpf Q flach, 2 Gondeln an Schwenk-Pylonen (klappen beim Warp hoch) | Warp |
| | Defiant | Keil flach, 2 Gondel-Wülste K, Deflektor rot | Warp |
| | Bird-of-Prey | Kopf E an Hals K, 2 Flügel Keil nach unten geneigt, Disruptoren Z | Tarnung, Warp |
| | Romulanischer Warbird | 2 Bogen-Segmente T oben und unten, vorn Kopf E, Mitte offen, grün | Tarnung, Warp |
| | Borg-Würfel | Kern mit Schale aus Blöcken, geteilt per Zufall mit Seed, Gräben, grünes Glühen (siehe „Borg-Würfel und Galaxienpaar“) | Transwarp |
| | Deep Space 9 (Station) | 3 Ringe T, 3 Bögen K oben und unten, Kern Z | keins |
| Star Wars | Millennium Falcon | Scheibe Z flach, Gabel 2 Q vorn, Cockpit-Röhre Z seitlich, Antriebsstreifen hinten blau, Schüssel klein | Hyperraum |
| | X-Wing | Rumpf Keil lang, 4 Flügel Q in X, 4 Triebwerke Z rot glühend, Kanonen Z dünn | Hyperraum |
| | TIE Fighter | Cockpit S, Achse Z, 2 Sechseck-Flügel P flach dunkel mit Streben | keins |
| | Sternzerstörer | Dreieck-Keil flach mit Stufe, Brückenturm Q + 2 S, 3 große und 4 kleine Triebwerke Z blauweiß | Hyperraum |
| | Tantive IV | Hammerkopf Q, Rumpf Z, Bündel aus 11 Triebwerken Z | Hyperraum |
| | Todesstern (Station) | S groß, Äquatorgraben und Superlaser-Mulde als Shader-Detail, Lichterpunkte | keins |
| Battlestar Galactica | Galactica | Kopf Q verjüngt, Mittelrumpf Q, 2 Flugdecks Q seitlich, Heck Q mit 6 Z-Triebwerken orange | FTL-Sprung |
| | Viper Mk II | Rumpf K mit Spitze Ke, 3 Triebwerke Z, kleine Flügel Q | keins |
| | Basisstern (2004) | 2 dreiarmige Sterne aus gebogenen K, 60° versetzt, Säule Z | FTL-Sprung |
| | Raider | Sichel aus T-Segment, rotes Lauflicht-Auge | FTL-Sprung |
| | Raptor | Kasten Q mit Keil-Nase, 2 Triebwerke | FTL-Sprung |
| Raumpatrouille Orion | Orion VIII | Untertasse E mit Ringwulst T, Kuppel S oben und unten, leuchtendes Fensterband | Strudelstart: steigt am Dock-Band aus einem Wasserwirbel auf |
| | Frog-Raumer | Vorschlag: flache rotierende Scheibe mit gezacktem Leuchtrand, pulsierender Kern. Form vor dem Bau an Standbildern prüfen | Auftauchen |
| The Expanse | Rocinante | Keil lang spitz, 2 Seitenbuckel Q, PDC-Türme S, Düse Ke mit langer blauer Epstein-Fahne | Epstein-Zündung |
| | Donnager | 5 Q-Segmente mit Verjüngung, Düse | Epstein-Zündung |
| | Tycho-Station | Rad T groß, Gitterkugel S (Muster) | keins |
| | Ring-Tor (Station) | T groß mit Strukturrauschen, schimmernde Fläche; in Stufe 4 echte Wurmloch-Linse | Durchflug |
| Babylon 5 | Babylon 5 (Station) | Zylinder Z lang rotierend, vorn Kugel-Bucht S mit 6 Rippen Q, hinten Mast und 2 Paneele | keins |
| | White Star | E gestreckt, 2 Keil-Flügel nach vorn gebogen, blauviolett | Sprungpunkt |
| | Starfury | Kern Q, 4 Arme Q in X mit Triebwerken Z | keins |
| Firefly | Serenity | Kopf S, Hals K, Bauch E, 2 Gondeln Z seitlich schwenkbar, Heckring T orange pulsierend | Full Burn |
| 2001 | Discovery One | Kugel S, Wirbelsäule aus 8 Z, Triebwerksblock Q mit 3 Düsen | keins |
| | Raumstation V | 2 Räder T an Achse Z, 4 Speichen Z | keins |
| | Monolith | Q im Verhältnis 1 : 4 : 9, schwarz, Glanzkante | Sternentor |
| Interstellar | Endurance | Ring aus 12 Q-Modulen um Nabe Z, Drehung | Durchs Wurmloch (Stufe 4) |
| | Ranger | Keil flach, 2 Düsen | keins |
| Mass Effect | Normandy SR-2 | Pfeil-Keil, 2 Gondeln K hinten unten mit Flügeln, blau | Relais-Sprung |
| | Citadel (Station) | Ring T, 5 Arme Q als Blüte, Lichtpunkte | keins |
| | Massenportal (Station) | 2 gebogene T-Segmente in C-Form um glühenden Kern S | Relais-Sprung |
| Echte Raumfahrt | ISS | Truss Q lang, 8 Solarflügel Q, Module Z, Radiatoren Q | keins |
| | Hubble | Z mit Klappe, 2 Paneele Q | keins |
| | James Webb | 18 Sechsecke P gold, Sonnenschild aus 5 flachen Rauten | keins |
| | Voyager-Sonde | Schüssel Ke flach, Ausleger Z, RTG Z | keins |
| | Apollo CSM | Ke + Z + Düse Ke | keins |
| | Starship | Z lang, Spitze Ke, 4 Klappen Q, 6 Düsen | Zündung |
| Weitere | TARDIS (Doctor Who) | Q blau mit Lampe, taumelt | Materialisieren |
| | Stargate-Tor (Station) | T mit 9 Chevrons; Stufe 4 als Wurmloch-Rahmen | Kawoosh |
| | Ha'tak (Stargate) | Pyramide im Ringgerüst | Hyperraum |
| | Kugelraumer (Perry Rhodan) | S mit Ringwulst T, Lichter | Transition |
| | Nostromo (Alien) | Q-Block mit Türmen, dunkel | keins |
| | Heart of Gold (Per Anhalter) | weiße Turnschuh-Form aus E + Q | Unwahrscheinlichkeitssprung |
| Eigenes Modell | OBJ, USDZ, USD, PLY, STL | ModelIO-Import, zentriert, auf Einheitslänge skaliert, Materialfarben und Texturen falls vorhanden | frei wählbar |

**Ereignisse** (Weg F, Bildschirm-Effekte, Dauer 0,5 bis 2 s): Warp (Schiff streckt sich bis 20-fach in Flugrichtung, Regenbogenstreifen, blauweißer Blitz), Hyperraum (kurzes Zurückweichen, Streifen, Blitz), FTL-Sprung (Zusammenziehen auf einen Punkt, bläulicher Blitz, kurze Raumwelle als lokale Bildverzerrung), Sprungpunkt (orangeroter Spiralwirbel öffnet und schließt), Relais-Sprung (blauer Lichtbogen, Schiff wird Lichtstreif), Epstein-Zündung (Fahne flammt auf, Beschleunigung), Strudelstart, Sternentor (Lichttunnel-Streifen), Materialisieren (pulsierendes Ein- und Ausblenden), Tarnung (Brechungsflimmern, Ausblenden), Transwarp (grüner Tunnelblitz), Kawoosh (Wasserflächen-Wirbel im Torring), Transition (Lichtblitz), Unwahrscheinlichkeitssprung (Farb- und Formflackern). Ein Schiff auf einem Randweg kommt mit einem Ankunftsereignis und verlässt den Schirm mit einem Abflugereignis, wenn Ereignisse an sind.

## 4. Bewegung

Neue Datei `Orbits.swift` (Stufe 2; Stufe 1 braucht nur `sky`).

- **Uhren:** `Renderer` bekommt `objectClock` (läuft nur bei `AnimationMode.all`) und nutzt für Randobjekte die vorhandene Bandzeit `time + edgeLead`. Pro Objekt eine Phase `phase[id] += dt * speed(id)`, damit Tempo-Änderungen nichts springen lassen (gleiche Regel wie heute bei Scheibe und Nebel). `setTime(t)` setzt Phasen auf `t * speed`.
- **Bahn (orbit):** Kepler-Ellipse mit großer Halbachse `radius`, Exzentrizität, Neigung, Knoten, Periapsis, Phase. Kepler-Gleichung pro Bild mit 5 Newton-Schritten. Umlaufzeit an die Scheibe gekoppelt: `T = diskPeriod * (a / rISCO)^1,5 / tempo / speed`, damit Scheibe und Objekte im selben Zeitmaß laufen; `tempo` bis 200. GR-Periapsis-Drehung pro Umlauf `6 π M / (a (1 - e²))` wenn `precession` an (bei a = 20 M fast 1 rad, sichtbare Rosette). Monde: Bahn um den Elternplaneten.
- **Vorbeiflug (flyby):** Gerade oder Hyperbel am Loch vorbei, kleinster Abstand zufällig zwischen `passMin` und `passMax`, Seite vor/hinter dem Loch, Wartezeit exponentiell verteilt mit Mittelwert `interval`, alles aus `hash(seed, n)`.
- **Randweg (edge):** 2D in Bildpunkten. y = Bandlinie plus `offset` (positiv ins Bild, negativ in die Leiste), x läuft mit `edgeSpeed`, dann Pause `edgeGap`. Richtung fest, abwechselnd oder zufällig. `wobble` als langsame Sinusschwingung. Abdunkelung des Bandes wird im Shader nachgebildet (gemeinsame Funktion `edgeDarken` aus `edgeLight` herauslösen).
- **Fest (fixed):** Bildschirmposition, Tiefe vor oder hinter der Lochebene (hinter heißt Weg L mit Linsung), Eigendrehung.
- **Himmel (sky):** Richtung im Kamerasystem aus Azimut und Elevation, optionale Drift. Az = El = 0 liegt genau hinter dem Loch.
- **Doppler für enge Bahnen:** Geschwindigkeit aus der Bahn, `δ = 1 / (γ (1 - β cos θ))`, Helligkeit mal `δ³`, bei Sternen Farbtemperatur mal δ. Schalter „Relativistische Effekte“ in der Szene, Standard an.
- **Nahebene:** Objekte näher als 5 M an der Kamera werden ausgeblendet.
- **Kappen:** höchstens 32 aktive Objekte, 8 im Weg L, 4 Netz-Körper größer als 200 px gleichzeitig, 20 000 Partikel (Detail „Hoch“ 40 000).

## 5. Rendering

### 5.1 Pässe pro Bild (Endausbau)

1. Bei Ansichtswechsel: `geoFrag` oder `geoFragJet` (Hauptkarte und Box), Mini-Karten der zweiten Löcher.
2. Bei Parameteränderung: `bakeGalaxy` in den Galaxie-Atlas, `bakePlanet` je Planet.
3. `bodyPass`: alle sichtbaren Körper als Sprites in den Atlas (Planeten analytisch per Strahl-Kugel-Schnitt mit Kamera-Strahl je Atlas-Pixel; Netze gerastert).
4. `nebFrag` wie heute, Linsenliste statt `lensed`.
5. `dispFrag`: Linsenliste, Weg S, Weg L, Jet, zweites Loch.
6. `frontPass`: Weg-F-Sprites aus dem Atlas, Partikel, Meteore, Schweife, Effekte, Beugungsstrahlen. Blend `one, oneMinusSourceAlpha`, vormultipliert, Tone-Mapping im Shader.

### 5.2 Shader-Schnittstellen

- `FrameParams` **nur hinten erweitern** (nach `region`): `float4 objA; // sky count, L count, jet on, objects time` `float4 jetC; // colour rgb, brightness` `float4 jetK; // knot contrast, knot speed front, knot speed back, knot spacing` `float4 jetP; // pulse depth, pulse period, unused, unused` `float4 lens[6]; // Stufe 4`. Swift-Reihenfolge in `frameParams` entsprechend anhängen.
- Puffer: `buffer(1)` Himmelsobjekte `SkyObj[]`, `buffer(2)` L-Körper `BodyRef[]`, `buffer(3)` Linsen (Stufe 4).
- Texturen in `dispFrag`: 0 bis 9 wie heute, 10 bleibt für `edgeFrag`, **11 Jet Hauptkarte, 12 Jet Box, 13 Galaxie-Atlas, 14 Körper-Atlas, 15 bis 20 Mini-Karten zweites Loch** (Stufe 4). Fehlt etwas, eine 1 x 1 Nulltextur binden; die Zweige hängen an Zählern in `objA`, sind also pro Bild einheitlich.

```metal
struct SkyObj {
    float4 pos;   // centre direction (camera frame, unit), angular radius (rad)
    float4 ax;    // tangent u (unit), kind: 0 star, 1 galaxy, 2 pulsar
    float4 col;   // linear rgb * brightness, core share
    float4 tile;  // galaxy: atlas rect u0 v0 u1 v1. pulsar: beam angle (rad), beam width, cone glow, unused
};
struct BodyRef {
    float4 box;   // unlensed screen rect px: x0 y0 x1 y1
    float4 tile;  // atlas rect uv
    float4 geo;   // lens weight w, camera depth, 0 front / 1 behind, wind fade
};
```

### 5.3 Weg S in `dispFrag`

Im Zweig `captured < 0.99` nach den Sternen: Schleife über `objA.x` Himmelsobjekte. Test `dot(dir, pos.xyz) > cos(Radius)`, dann Tangentialkoordinaten `(dot(dir, u), dot(dir, cross(pos, u))) / tan(Radius)`. Stern: Kern `exp(-2 (x/ρ)²)` plus Halo, Farbe `blackbody(T)`. Pulsar: Kern mit Helligkeit aus der CPU (Blitz, wenn ein Strahl die Sichtlinie überstreicht) plus zwei schwache Lichtkegel als Keile in Tangentialebene. Galaxie: Atlas-Probe. Ausblenden mit `1 - smoothstep(4, 6, wind)`. Sterne werden mindestens 1,5 Pixel breit gezeichnet, damit Mikrolinsen-Verstärkung als Fläche sichtbar wird.

### 5.4 Jet in `geoFragJet`

- `geoFrag` wird zu `static inline GeoOut traceRay(VOut in, constant GeoParams &P, bool jet, thread half4 &jo)`; zwei Einstiege `geoFrag` (3 Ziele) und `geoFragJet` (Struktur `GeoOutJ` mit `[[color(3)]]`), zwei Pipelines in `GPU`, beide aus der `.safe`-Bibliothek. Der Compiler faltet `jet == false` weg; Pixelgleichheit ohne Jet ist Abnahmekriterium.
- `GeoParams` hinten: `float4 jet0; // on, length L, base width w0, shape k` `float4 jet1; // beta, doppler strength, base height z0, counter jet`.
- Pro RK4-Schritt: Segment `prevP → p`. Kommt es der Achse näher als `2 w(|z|)`, 4 Teilpunkte, sonst keiner. Pro Teilpunkt: `zz = |z|`, `ρ = length(xy)`, nur wenn `z0 ≤ zz ≤ L` und Gegenjet erlaubt; `w = min(w0 (zz / z0)^k, 0,6 * Achsabstand der Kamera)`; `dens = exp(-(ρ/w)²) * (w0 / w)² * Enden-Ausblendung`; Photonenrichtung zur Kamera `-segDir`; `cosθ = dot(-segDir, sign(z) ẑ)`; `δ = 1 / (γ (1 - β cosθ))`; `boost = mix(1, δ^2,7, doppler)`; Gravitation `(1 - 2/r)^1,5`. Beitrag `dens * boost * grav * Segmentlänge / 4` in `Ef` (solange `hits == 0`) sonst `Eb`; Lage `zz / L` gewichtet aufsummieren.
- Ausgabe `jet = (Ef, Eb, sf / Ef, sb / Eb)` als rgba16Float. Strahlen, die eingefangen werden, behalten ihre Emission vor dem Horizont (Jet vor dem Schatten ist sichtbar).
- In `dispFrag`: Jet-Karte wie `sky` holen (Box oder Hauptkarte, linear). `bg = bg * (1 - captured) + jetCol * Eb * knot(sb, kb)`; nach den beiden Scheibenschichten `col += jetCol * Ef * knot(sf, kf)`. `knot(s, v) = 1 + knots * (n(s / spacing - v t) - 0,5) * 2` mit `n` aus der vorhandenen `edgeNoise`-Textur, Pulsieren als Faktor.
- Speicher: 8 Byte pro Texel nur wenn ein Hauptjet existiert (Ultrawide halbe Auflösung etwa 10 MB plus Box).

### 5.5 Weg L in `dispFrag` (Stufe 2)

Pro Pixel einmal: `θ = flatDir(px_gelinst)`, `dir` aus der Karte, Scheibentiefe aus `h1`, `h2` (Punkt `(R cos φ, R sin φ, 0)`, `R = sqrt(r² + a²)`, Tiefe `dot(X - camPos, fwd)`). Pro `BodyRef`: `β = normalize(mix(θ, dir, w))`, `q = pxOf(β)`, Box-Test, Atlas-Probe (vormultipliert). Sammeln in drei Töpfen: hinter allem (vor `d2`), zwischen `d2` und `d1`, vor allem; Tiefe des Körpers gegen Tiefe der Scheibentreffer. Hinter-Töpfe mal `1 - captured`. Ausblenden bei großer Windung wie in 5.3.

### 5.6 Körper-Atlas und Weg F (Stufe 2, Netze Stufe 3)

- Atlas: `GPU.shared`, 2048 x 2048 rgba16Float (32 MB) nur bei Detail „Hoch“, sonst 1024 x 1024 (8 MB); Tiefe depth32Float gleicher Größe, MSAA-Ziele `memoryless`. Regal-Packer auf der CPU pro Bild, Kachel = Bildschirm-Box mal Detailfaktor, höchstens 512 px (Hoch 1024). Mehrere Schirme teilen den Atlas, ihre Command Buffer laufen nacheinander auf derselben Queue.
- Planeten: gebackene Rektangular-Textur 1024 x 512 rgba8 (Albedo, Ozeanmaske) plus zweite (Wolken, Glut, Höhe), kleine Planeten 512 x 256. Cache mit Schlüssel wie `GPU.bakedTexture`. Beleuchtung: Scheibe des Hauptlochs als Licht aus Richtung Loch, Farbe `grad5(0,75)`, Stärke `diskBrightness * gain * (rISCO * k / d)²`, mal `0,25 + 0,75 |n_Scheibe · l|` (flache Scheibe strahlt wenig in ihre Ebene); dazu bis zu zwei hellste Sterne; Umgebung aus Palette 5 und 6, schwach. Atmosphärenrand per Fresnel, Ringe analytisch mit Schatten.
- Weg F: ein instanzierter Pass, Instanz-Typen Sprite, Partikel, Streifen, Effekt. Partikel-Bahnen im Vertex-Shader aus Index, Seed und Uhr; Punktlinse vorwärts mit `θE² = 4 D_ls / (r0 D_s)` (Einheiten M), Gegenbild als zweite Instanz, im Schatten verworfen, hinter der Scheibenebene mit Sichtlinie durch den Scheibenring um 0,6 abgedunkelt.

### 5.7 Linsenliste (Stufe 4)

`lensed(px)` wird zu `lensAll(px, shadow)`: Maus-Linse wie heute, dann je Objekt-Linse. Typ zweites Loch: innerhalb seiner Box Umlenkung über die Mini-Karte (`src = c2 + pxOf2(dir2)`), Schatten aus deren Fangzahl, eigene Scheibenschichten mit einer parametrisierten Kopie von `diskShade` (eigene Uhr, Radius, Helligkeit, Farbton); außerhalb Punktlinse `α(b) = α_Rand * b_Rand / b`, weich übergeblendet. Mini-Karte: Box 8 Schattenradien, höchstens 512 x 512, mit Jet-Ziel wenn Jet angehängt. Typ Wurmloch: außen Umlenkung `k R² / r²`, innen andere Seite: Richtung `rotate(θ, π (1 - r/R))`, Nebel-Textur gedreht mit `otherHue`, Sterne aus `starLayer` mit versetztem Hash, Rand als heller Ring. Gilt in `nebFrag` und `dispFrag`, damit Nebel mitgebogen wird.

## 6. Zusammenspiel

- **„Alles“:** alles bewegt sich.
- **„Nur Ränder“:** nur Objekte mit Bewegung `edge` bewegen sich, auf der Bandzeit. Alle anderen stehen und sind Teil der Basis: `dispFrag` Stufe 1 enthält S, L und Jet von selbst; zusätzlich läuft der Weg F in einer linearen Variante (ohne Tone-Mapping) auf die Basis-Textur, ohne Randobjekte und ohne flüchtige Objekte (Meteore, Ereignisse). In jedem `BandStrip` zeichnet nach `edgeFrag` ein Weg-F-Pass nur die Randobjekte, verschoben um `region`. `Renderer.stripRows` nimmt die Hülle der Randobjekte (Offset plus Größe) in die Zeilen auf.
- **„Aus“:** Standbild ohne flüchtige Objekte.
- **Maus-Modus:** Maus-Linse biegt Himmel, Weg L und Jet (sie wirkt vor dem Kartenzugriff), Weg F nicht. Passt, weil die Mini-Linse in Lochtiefe gedacht ist.
- **Bildschirmschoner:** Szene kommt über `SaverConfig.look`. Randobjekte laufen an einer gedachten Linie 3 % vom oberen und unteren Rand. Eigene Modelle kopiert die App zusätzlich in den Schoner-Container (`…/Data/Library/Application Support/BlackHoleWallpaper/Models/`), wie `saver.json`. `scripts/build-saver.sh` bekommt alle neuen Dateien und `-framework ModelIO`.
- **Standbild als echter Hintergrund:** `Renderer.stillMode = true` blendet flüchtige Objekte und Ereignisse aus, Rest zur aktuellen Zeit.
- **Langsame Veränderung über den Tag:** ändert den Blickwinkel, Objekte folgen über das Kamerasystem, Jet wird mit der Karte neu gerechnet.
- **`--snapshot`-Schalter (Snapshot.swift):**
  - `--objects datei.json` ersetzt `look.objects` (Szene oder Liste von Objekten).
  - `--add art:untertyp[:schlüssel=wert,…]` mehrfach erlaubt, Katalog-Standard mit sichtbarer Demo-Platzierung, zum Beispiel `--add galaxy:spiral:tilt=40` oder `--add jet:main:beta=0.95`.
  - `--no-objects` für Vergleiche.
  - `--catalog art` rendert jede Variante dieser Art als Kachel (860 x 360) mit Beschriftung (CoreText) in ein Rasterbild; `--catalog all` alle.
  - `--event name --phase 0.5` friert ein Ereignis in einer Phase ein (Stufe 3).
  - `--motion all|edges|off` setzt die Animationsstufe für den Snapshot.
  - `--diff a.png b.png` gibt größte Kanalabweichung und Zahl abweichender Pixel aus.
  - `--bench-geo` misst einen Strahlen-Pass.
- **Selbsttest (`SelfTest.swift`):** Objekte-Prüfungen ergänzen: alte Datei ohne `objects`, Datei mit unbekannter Art, mit fehlenden Schlüsseln, mit kaputtem Element, Hin-und-zurück-Kodierung, Monitor-Kopie übernimmt Objekte.

## 7. Einstellungsseite „Objekte“

Neue Datei `ObjectsTab.swift`. In `SettingsView.swift` nur: Eintrag `("Objekte", "globe.europe.africa")` nach „Ränder“ in `pages`, `case` im `switch`, Indizes der folgenden Seiten nachziehen, README-Hinweis zu `--tab` anpassen. Lokaler Zustand in `final class ObjectsTabModel: ObservableObject { @Published var selected: String?; @Published var confirmDelete = false }` (kein `@State`). Alle Schreibzugriffe über `store.binding(\.objects)`, damit `willEditLook()` greift. Bei `store.lookLocked` ist die Seite gesperrt wie die anderen.

Aufbau als `Page { … }` (Form, grouped):

1. **Section „Objekte“:** Toggle „Objekte zeigen“, Slider „Tempo aller Objekte“, Picker „Detail“ (Sparsam, Normal, Hoch), Zeile „Geschätzte Last“ (leicht, mittel, schwer mit Millisekunden aus Katalog-Kosten, ab Stufe 2 aus Messungen kalibriert).
2. **Section „Liste“:** Zeile pro Objekt: Checkbox (an/aus), Symbol nach Art, Name, rechts Kostenmarke grau. Tippen wählt aus (Hervorhebung). Darunter Knopfzeile: `Menu("Hinzufügen")` mit Untermenüs aus `VariantSpec.menu` (Galaxien, Sterne, Jets, Planeten, Monde, Asteroiden und Gürtel, Kometen und Meteore, Exoten, Raumschiffe ▸ Universum, Stationen ▸ Universum, Eigenes Modell …; nur Arten, deren `stage` gebaut ist), „Duplizieren“, „Würfeln“ (Seed und Parameter), „Entfernen“ (Bestätigung), `Menu("Mehr")`: „Szene würfeln“ (Rezept: 1 bis 2 Galaxien, 1 Planet, 1 Gürtel, gelegentlich Jet), „Szene kopieren“ und „Szene einfügen“ (JSON in der Zwischenablage, praktisch zwischen Monitoren), „Alle entfernen …“.
3. **Section „Allgemein“** (gewähltes Objekt): Name, Picker Untertyp (Varianten derselben Art), Seed mit Würfel, Größe mit Einheit je Bewegungsart, Helligkeit, Tönung (ColorPicker plus Stärke).
4. **Section „Bewegung“:** Picker Bewegungsart (nur erlaubte `modes`), darunter nur die Regler dieser Art.
5. **Sections je `ParamSpec.group`:** aus dem Katalog erzeugt. `SliderRow` mit `defaultValue` aus dem Katalog (Rückgängig-Symbol), `toggle` als Toggle, `options` als Picker.
6. **Section „Ereignisse“** (Schiffe): Toggle, Mehrfachauswahl der erlaubten Ereignisse, Slider mittlerer Abstand.
7. **Section „Modell“** (eigenes Modell): Dateiname, „Datei wählen …“ (`NSOpenPanel`, Typen obj, usdz, usd, usda, usdc, ply, stl), Dreieckszahl, Warnung über 200 000.

Eingebaute Presets bleiben unverändert. Neue Vorzeige-Presets in `Preset.factory` (der Loader ergänzt fehlende eingebaute, das muss nach dem Umbau des parallelen Agenten so bleiben):
- **„Sternsystem“** (Stufe 2): Strudel-Look, Jet am Hauptloch (β 0,8), Ringplanet auf geneigter Bahn mit Mond, Asteroidengürtel, Komet auf exzentrischer Bahn, zwei Galaxien am Himmel (eine knapp hinter dem Loch mit Bögen), ein Pulsar. Dies ist der Standard-Objektsatz fürs Budget.
- **„SciFi-Hafen“** (Stufe 4): Wurmloch neben dem Loch, Station (Deep Space 9 oder Babylon 5) fest, Schiffe aus vier Universen auf Rand- und Bahnwegen mit Sprung-Ereignissen.

## 8. GPU-Budget und Messweg

**Ziel:** Standard-Objektsatz („Sternsystem“) höchstens **+1,0 ms GPU pro Bild und Schirm live** (heute 3,6 ms), im Benchmark höchstens **+0,35 ms** auf 3440 x 1440 (Live/Bench etwa 3 : 1). Speicher höchstens **+40 MB pro Schirm**. Strahlen-Pass mit Jet höchstens +30 %. Größere Szenen dürfen mehr kosten, die Lastanzeige sagt es vorher.

Richtwerte je Teil (Bench, 3440 x 1440, zu messen): Weg S mit 8 Objekten 0,03 ms; Jet pro Bild 0,03 ms; Weg L mit 4 Körpern 0,08 ms; Atlas-Pass mit 3 Planeten 0,08 ms; 3 000 Partikel 0,03 ms; Schiff gerastert 0,02 ms; zweites Loch 0,1 ms.

**Messweg:**
1. `--bench` mit und ohne `--no-objects`, Preset `sternsystem`, Größen 3440 x 1440 und 1440 x 2560, je drei Läufe, Median.
2. `--bench-geo` mit und ohne Jet.
3. Live: `BH_DEBUG=1`, 30 fps, beide Schirme, je 60 s Objekte an und aus, Median der Log-Zeilen. Vorher GPU-Fresser schließen (FluidVoice, Teams, siehe Archiv-Notiz). Log-Zeile um Objektzahlen je Weg und Atlas-Füllung erweitern.
4. Speicher: `--mem` und `footprint` der laufenden App.
5. Bei Überschreitung zuerst Detailstufe und Kappen anpassen, nicht die Optik.

## 9. Stufen

Voraussetzung vor Stufe 1: Änderungen des parallelen Agenten sind committet. Arbeitsbaum lesen, insbesondere `FrameParams`, `finishPixel`, `encodeStrip`, `Store.willEditLook`, Seitenliste. Vor Stufe 1 Referenz-Snapshots aller eingebauten Presets (3440 x 1440 und 1440 x 2560, `--time 20`) nach `shots/objekte/referenz/` legen.

Prüfbilder je Stufe nach `shots/objekte/stufeN/`, Look-Freigabe durch den Nutzer nach jeder Stufe.

### Stufe 1: Fundament, Himmelsobjekte, Jet

**Umfang:** Datenmodell mit Abwärtskompatibilität; Katalog-Gerüst mit Galaxien (alle Untertypen), fernen Sternen (alle Klassen inklusive Pulsar, Magnetar, Cepheide; ohne Beugungsstrahlen) und Jet am Hauptloch; Weg S; Galaxie-Bake; Jet in `geoFragJet` mit Doppler, Knoten, Pulsieren; `objectClock` und Animationsstufen (Himmelsobjekte stehen in „Nur Ränder“ und „Aus“); Einstellungsseite „Objekte“ vollständig, aber nur mit diesen drei Arten im Hinzufügen-Menü; Snapshot-Schalter `--objects`, `--add`, `--no-objects`, `--catalog`, `--motion`, `--diff`, `--bench-geo`; Selbsttest-Ergänzung.

**Neue Dateien:** `Objects.swift` (Modell), `ObjectCatalog.swift` (Spezifikationen, Demo-Platzierung, Würfel), `ObjectSystem.swift` (pro Bild: Uhr, Himmelsrichtungen, Pulsar-Blitz, Packen von `SkyObj`, Jet-Uniforms, Bake-Schlüssel), `ObjectShaders.swift` (Metal-Quelltext: `skyObjects()`, `bakeGalaxy`, Jet-Kompositing, `flatDir`/`pxOf`), `ObjectsTab.swift`.

**Geänderte Dateien:** `Settings.swift` (`Look.objects`, `geometryKey`, `decodeLenient`), `Shaders.swift` (Quelltext in Kopf und Bildteil teilen, `ObjectShaders` dazwischen einfügen; `traceRay` mit Jet; `GeoParams` und `FrameParams` hinten erweitern; Haken in `dispFrag`), `Renderer.swift` (Pipelines `geoJetPipeline`, `bakeGalaxyPipeline`; Jet-Karten bei Bedarf in `makeMaps`; Galaxie-Atlas 2048 x 1024 rgba8 mit 8 Kacheln zu 512 nur wenn Galaxien da; Puffer `buffer(1)`; Texturen 11 bis 13; `objectClock` in `advance`), `Snapshot.swift`, `SettingsView.swift` (Seiteneintrag), `SelfTest.swift`, `scripts/build-saver.sh`, `README.md`.

**Abnahme:**
1. `swift build -c release` und `scripts/build-saver.sh` ohne neue Warnungen; `--selftest` grün.
2. Alle eingebauten Presets ohne Objekte: `--diff` gegen Referenz, größte Abweichung höchstens 1/255 pro Kanal, beide Größen.
3. Eine aktuelle `settings.json` (Kopie aus `~/Library/Application Support/BlackHoleWallpaper/`) lädt ohne Verlust, Szene leer.
4. Einstein-Ring: Galaxie mit Az = El = 0, 1,5°, ergibt einen geschlossenen Ring um den Schatten; bei Az 0,5° zwei Bögen auf gegenüberliegenden Seiten. Prüfbilder `s1-ring.png`, `s1-boegen.png`.
5. Jet: Preset M87* mit Jet β 0,9: zulaufender Jet mindestens fünfmal heller als Gegenjet, Gegenjet sichtbar um den Schatten gebogen (`s1-jet-m87.png`). Strudel mit β 0,8 (`s1-jet-strudel.png`). Drei Zeitpunkte `--time 20, 21, 22` zeigen nach außen wandernde Knoten (`s1-jet-zeit.png`).
6. Kataloge: `--catalog galaxy` und `--catalog star` (`s1-galaxien.png`, `s1-sterne.png`), Pulsar knapp hinter dem Loch (`s1-pulsar.png`), Hochkant 1440 x 2560 (`s1-hochkant.png`).
7. Einstellungsseite: `--settings-shot … --tab <Objekte>` mit Liste und Detail einer Galaxie (`s1-einstellungen.png`).
8. Budget: Bench-Zuwachs mit 3 Galaxien, 4 Sternen, Pulsar und Jet höchstens 0,15 ms; `--bench-geo` mit Jet höchstens +30 %; `--mem` höchstens +20 MB.
9. „Nur Ränder“ live: Himmelsobjekte stehen, kein Mehrverbrauch gegenüber ohne Objekte; Schoner zeigt die Objekte.

**Stand 2026-10-11: gebaut.** Commits `7c9dd3c`, `2f61438` und der Abschluss-Commit danach. Prüfbilder in `shots/objekte/stufe1/`.

Abnahme, gemessen auf dem MacBook Air M4:

| Nr. | Kriterium | Ergebnis |
| --- | --- | --- |
| 1 | Build, Schoner, Selbsttest | erfüllt. Keine neuen Warnungen (die zwei `ld`-Suchpfad-Warnungen gab es schon vorher), `--selftest` grün |
| 2 | Presets ohne Objekte gleich | erfüllt. Alle fünf Presets, beide Größen: 0 abweichende Pixel |
| 3 | `settings.json` lädt ohne Verlust | erfüllt. `--selftest --settings-file` mit einer Kopie: jeder Schlüssel aller fünf Voreinstellungen gleich, Szenen leer |
| 4 | Einstein-Ring und Bögen | erfüllt. `s1-ring.png`, `s1-boegen.png`, Anteil der Galaxie allein in `s1-ring-boegen-anteil.png` |
| 5 | Jet | erfüllt mit Einschränkung. M87* mit 0,9 c: Jet an der hellsten Stelle 27-mal heller als Gegenjet (`--jet-stats`; 99,9. Perzentil 10,6). Der Gegenjet liegt als Ring um den Schatten, aber unter der dichten M87-Scheibe; im Endbild nur schwach, deutlich im Differenzbild `s1-jet-m87-gegenjet.png`. Knoten wandern nach außen (`s1-jet-zeit.png`, unten das Jet-Licht allein) |
| 6 | Kataloge, Pulsar, Hochkant | erfüllt. `s1-galaxien.png`, `s1-sterne.png`, `s1-pulsar.png` (Blitz und Pause, zwei Bilder auf gegenüberliegenden Seiten), `s1-hochkant.png` |
| 7 | Einstellungsseite | erfüllt. `s1-einstellungen.png` |
| 8 | Budget | teilweise. Bench (`--bench-ab`) +0,23 bis +0,31 ms statt höchstens 0,15 ms (nach der Look-Nachbesserung, Szene wie `s1-szene-ultrawide.png`; vorher +0,18 bis +0,24). Jet allein rund 0,08 ms, eine Galaxie knapp hinter dem Loch kostet am meisten, weil die Linse sie zu großen Bögen streckt. Strahlen-Pass mit Jet +8 % (Strudel) bis +13 % (M87*). Speicher +17,1 MB (Ultrawide), +14,9 MB (Hochkant) |
| 9 | Nur Ränder, Schoner | erfüllt im Benchmark, nicht live gemessen. `--bench-ab --edges`: kein Mehrverbrauch (Differenz unter 0,01 ms). `--motion edges` zu zwei Zeiten: außerhalb der Bänder nur Dither-Rauschen, kein Objekt bewegt sich. `--edgecheck` mit Objekten: größte Abweichung 2 von 255. Der Schoner bekommt die Szene über `saver.json` (Selbsttest); im laufenden Schoner nicht angesehen |

Abweichungen vom Plan:

- **Jet:** Neuer Regler „Langsame Hülle“ (`sheath`, Standard 0,75): Ein Teil des Lichts kommt aus einer Hülle mit 0,3 c. Mit reinem schnellen Kern wäre der Gegenjet bei M87* über 100-mal schwächer und unsichtbar; mit Hülle liegt das Verhältnis bei gut 20 zu 1, wie in M87 beobachtet. Die Helligkeit wird durch die Doppler-Verstärkung des zulaufenden Jets im aktuellen Blickwinkel geteilt, sonst wäre derselbe Regler bei 17° gleißend und bei 66° kaum zu sehen. Die Emission fällt entlang des Jets zusätzlich mit (z / 2,5 z0)^-0,6 ab. Standard: Länge 45 M, Breite 1 M, Form 0,62, Basis 4 M, Einblendung von z0 bis 2,5 z0.
- **Jet-Karte:** statt eines rgba16Float-Ziels zwei, `rg16Float` (Emission vor und hinter der Scheibe) und `rg8Unorm` (Lage entlang des Jets): 6 statt 8 Byte pro Texel. Texturen 15 und 16 in `dispFrag`. Pro Strahlsegment ein bis vier Teilpunkte, je nach Breite des Jets, Doppler einmal pro Segment.
- **Kosten der Himmelsobjekte:** Die Schleife über alle Objekte in jedem Pixel kostete 0,08 ms pro Objekt. Neu: Pass `skyMaskFrag` in Zellen von 8 x 8 Pixeln (Bit pro Objekt, `r32Uint`, Textur 14), nur neu bei Strahlen-Neuberechnung oder wenn ein Objekt mehr als 0,17° wandert. `nebFrag` schreibt „hier könnte etwas sein“ in sein Alpha, `dispFrag` liest Maske und Jet-Karte nur dort. `FrameParams.objA.y` ist der Rand der Maske.
- **SkyObj** hat fünf statt vier `float4` (`ext`: Galaxienradius, Kachelgröße, Kern; beim Pulsar Strahlen und Reichweite).
- **Galaxie-Atlas** wächst mit der Zahl der Galaxien (bis vier Kacheln pro Zeile), Kachel 256, 512 oder 1024 je nach Detail, mit Mipmaps. Geteilt zwischen Schirmen mit denselben Galaxien.
- **Lichthof der Sterne** (Nachbesserung): Er wird in Bildpunkten um jedes Bild gemessen. Der Versatz am Himmel geht über die örtliche Jacobi-Matrix der Linse (Differenzen über zehn Pixel, nur bei Sternen) zurück auf den Schirm, die Helligkeit wächst mit der Vergrößerung (höchstens dreifach). Ein Stern hinter dem Loch gibt so zwei leuchtende Bilder statt eines leuchtenden Rings. Beugungsstrahlen bleiben Stufe 2.
- **Jet-Look** (Nachbesserung): neue Regler „Öffnungswinkel außen“ (`opening`, 3,5°; Parabel geht in einen Kegel über, Übergang aus gleicher Steigung), „Abklingen“ (`falloff`, 1,5), „Wackeln“ (`wobble`, 0,3; leichte Schraube der Achse) und „Filamente“ (`filaments`, 0,35; Streifen entlang der Achse, pro Bild). Standard jetzt Länge 26 M, Breite 0,45 M, Form 0,55, Basis 3 M, Knoten 0,6. Die Fußhelligkeit hängt nicht mehr von der Breite ab. `GeoParams` hat dafür hinten `jet3`.
- **Demo-Szene**: Die Galaxie hinter dem Loch liegt 3° neben der Achse und ist 4,5° groß, sie gibt zwei dicke Bögen mit Struktur statt eines dünnen Rings. Der Pulsar sitzt standardmäßig 2,5 bis 4,5° neben der Achse.
- **Zusätzliche Werkzeuge:** `--bench-ab` (mit und ohne Objekte abwechselnd im selben Lauf; einzelne `--bench`-Läufe streuen durch die Erwärmung um ±0,3 ms), `--bench-geo` ebenfalls abwechselnd, `--jet-stats`, `--debug 3|4|5`, `--dump-atlas`, `--settings-shot … --objects-demo --height`, `--selftest --settings-file`.
- **Szene würfeln** nimmt mangels Planeten und Gürtel: ein bis zwei Galaxien, zwei bis vier Sterne, manchmal ein besonderer Stern, gelegentlich einen Jet.

Offen für Stufe 2: Budget der Himmelsobjekte hinter dem Loch (etwa Kosten pro Zelle der Maske begrenzen oder die Linsenringe bei „Sparsam“ weglassen), Kamera-Lichthof und Beugungsstrahlen in Weg F, live mit `BH_DEBUG=1` messen sobald die Voreinstellungen des Nutzers Objekte haben, Bildschirmschoner mit Objekten ansehen.

### Stufe 2: Körper, Bewegung, Partikel

**Umfang:** Körper-Atlas und `bodyPass`; Weg L mit Scheibentiefe; Weg F mit Tone-Mapping und linearer Variante für die Band-Basis; Planeten (alle Untertypen, Ringe), Monde, nahe Sterne (Granulation, Korona, Protuberanzen, Doppelstern mit Massenstrom), einzelne Asteroiden (Ellipsoid mit Rauschnormalen und unregelmäßigem Rand, keine Netze), Gürtel, Trümmerstrom, Staubring, Komet, Meteore; Beugungsstrahlen der Sterne; Bewegungsarten orbit, flyby, edge, fixed mit Präzession und Doppler; Randobjekte in den `BandStrip`s; Vorzeige-Preset „Sternsystem“; `--catalog` für die neuen Arten.

**Neue Dateien:** `Orbits.swift`, `BodyRenderer.swift` (Atlas, Packer, Planeten-Bake, Pässe), `BodyShaders.swift`.
**Geänderte Dateien:** `Shaders.swift` (Weg L, `edgeDarken` herauslösen), `Renderer.swift`, `ObjectSystem.swift`, `ObjectCatalog.swift`, `ObjectsTab.swift` (Bewegungs-Section vollständig), `Wallpaper.swift` (Strips zeichnen Randobjekte, Zeilenhülle), `Settings.swift` (Preset), `Snapshot.swift`, `Saver/BlackHoleSaverView.swift` (gedachte Randlinie), `scripts/build-saver.sh`.

**Abnahme:** Katalogbilder aller Planeten, Monde, nahen Sterne, Asteroiden und Kometen; Ringplanet hinter dem Loch mit gebogenem Hauptbild und Gegenbild (`s2-planet-hinten.png`); Planet zwischen Kamera und Loch verdeckt Scheibe und Schatten (`s2-planet-vorn.png`); Planet auf Bahn taucht hinter der Scheibe ab (Zeitreihe); Gürtel mit Bögen hinter dem Loch; Komet mit Schweif vom Licht weg; Randobjekt in „Nur Ränder“ bewegt sich, Rest steht (Bildschirmaufnahme live); „Sternsystem“ beide Schirme; Budget nach Abschnitt 8 (Bench +0,35 ms, live +1,0 ms, +40 MB).

**Stand 2026-10-12: gebaut.** Commits `fb38556`, `9876b1c`, `3f05461`, `324977b`, `00d0779`, `903384c` und der Abschluss-Commit danach. Prüfbilder in `shots/objekte/stufe2/`.

Abnahme, gemessen auf dem MacBook Air M4:

| Kriterium | Ergebnis |
| --- | --- |
| Build, Schoner, Selbsttest | erfüllt. Keine neuen Warnungen, `--selftest --settings-file` mit einer Kopie grün, Sternsystem kommt als sechste Voreinstellung dazu |
| Presets ohne Objekte gleich | erfüllt. Alle fünf Presets, beide Größen: 0 abweichende Pixel gegen `shots/objekte/referenz/` |
| Katalogbilder | erfüllt. `s2-planeten.png`, `s2-monde.png`, `s2-sterne-nah.png`, `s2-asteroiden.png`, `s2-kometen.png`, dazu `s2-doppelstern.png`, `s2-staubring.png`, `s2-meteore.png`, `s2-erde-nah.png` |
| Ringplanet hinter dem Loch | erfüllt. `s2-planet-hinten.png`: Einstein-Ring mit Gegenbild, `s2-planet-hinten-schraeg.png`: gebogenes Hauptbild und Gegenbild am Schatten |
| Planet vor dem Loch | erfüllt. `s2-planet-vorn.png` verdeckt Scheibe und Schatten, im Gegenlicht mit leuchtendem Atmosphärenrand |
| Abtauchen hinter die Scheibe | erfüllt. `s2-abtauchen.png`, sechs Zeitpunkte, in der Mitte als Einstein-Ring |
| Gürtel mit Bögen hinter dem Loch | erfüllt. `s2-guertel.png` (Gargantua) |
| Komet | erfüllt. `s2-komet.png`, fünf Zeitpunkte, Ionenschweif gerade vom Loch weg, Staubschweif gebogen |
| Randobjekt bei „Nur Ränder“ | erfüllt im Bild, nicht als Bildschirmaufnahme. `s2-nur-raender.png` (`--series --motion edges`): Asteroid und Strom wandern im Dock-Band, der Rest steht. Live bei „Nur Ränder“ kein Mehrverbrauch (Streifen 0,17 bis 0,28 ms mit, 0,22 bis 0,33 ms ohne Objekte, Rauschen). Schoner-Ansicht ohne Leisten mit Randlinie bei 3 %: `s2-schoner.png` |
| Sternsystem beide Schirme | erfüllt. `s2-sternsystem-ultrawide.png`, `s2-sternsystem-hochkant.png`. Im Hochkant-Bild steht der Ringplanet bei 20 s außerhalb, er kommt auf seiner Bahn ins Bild |
| Budget Bench | knapp. Sternsystem +0,353 bis +0,37 ms bei 3440 x 1440 (Ziel 0,35), +0,20 ms bei 1440 x 2560. Himmelsobjekte allein (Jet, zwei Galaxien, Pulsar mit Strahlen) +0,134 ms, damit ist der offene Punkt aus Stufe 1 (0,15 ms) erfüllt |
| Budget live | erfüllt, knapp. `BH_DEBUG=1` auf dem eingebauten Schirm (1920 x 1242, 30 fps), je 75 s, Median der Log-Zeilen: mit Objekten 4,10 und 3,96 ms, ohne 3,06 ms, also +0,9 bis +1,0 ms. Gemessen mit `BH_SETTINGS` auf einer Kopie, andere Programme liefen weiter. Ein zweiter Schirm war nicht angeschlossen |
| Speicher | erfüllt. `--mem`: +33,6 MB (Ultrawide), +23,9 MB (Hochkant). `footprint` der laufenden App nicht gemessen |
| Strahlen-Pass | erfüllt. `--bench-geo` Sternsystem mit Jet +10 % |

Abweichungen vom Plan:

- **Kein `bodyPass` als Render-Pass:** Ein Compute-Kernel schreibt nur die Pixel der Kachel. Ein Render-Pass lädt und speichert den ganzen Atlas und kostete das Mehrfache. Ein Kachel-Speicher zeichnet einen Körper nur neu, wenn sich etwas sichtbar ändert (Drehung um 0,4 Pixel am Rand, Oberflächenzeit um 0,25 s, sonst 0,2 %). Die Koma eines Kometen hängt nicht an Drehung und Zeit und wird deshalb selten neu gezeichnet.
- **Keine Maske für Weg L:** `dispFrag` prüft Körper nur in einem umschließenden Rechteck und darin pro Pixel gegen das Rechteck jedes Körpers. Der Bereich ist die Kachel, verbreitert um die Linsenverschiebung θE²/β (nicht den ganzen Einstein-Radius), plus ein Kreis um das Loch für Gegenbilder. Sichtbar mit `--debug 6`.
- **Weg F im selben Pass:** Vordere Körper, Schweife, Meteore, Lichthöfe und Beugungsstrahlen zeichnet derselbe Render-Pass direkt nach `dispFrag`, über ein lineares Zweitziel (memoryless) und programmierbares Blending. Ein eigener Pass hätte das Bild noch einmal geladen. Für die Band-Basis gibt es die lineare Variante über die Funktionskonstante `withLinear`.
- **Lichtpuffer:** Weiches Licht (Ionen- und Staubschweif, Rauch, Gürteldunst, Staubring) sammelt ein `rg11b10Float`-Puffer in viertel oder halber Auflösung, nur so groß wie das umschließende Rechteck, additiv. Kleine Lichtflächen ohne Staub gehen direkt in Weg F.
- **Partikel als Point-Sprites** mit Punktlinse (Haupt- und Gegenbild), Verdeckung durch Körper, Abdunklung durch die Scheibe, Henyey-Greenstein-Streuung. Die Uhr läuft modulo 2π · 1024, Bahnfrequenzen sind auf 1/1024 gerastert, damit nichts nach Stunden springt. Ein Staubring nimmt die Hälfte seiner Körner als Dunst, sonst sieht er aus wie Salz.
- **Lichthof und Beugungsstrahlen ferner Sterne** liegen in Weg F. Ihre Lage sucht ein kleiner Newton-Schritt auf der Strahlenkarte (`glowRefine`), gespeichert bis zur nächsten Strahlen-Neuberechnung. Weg S zeichnet nur noch den Kern. Damit sanken die Kosten der Himmelsobjekte hinter dem Loch unter 0,15 ms.
- **Pixel und Richtung** werden wie in `traceRay` abgebildet (sin ψ = b / r0), sonst lagen Lichthöfe neben den Kernen.
- **Licht der Körper:** Farbe aus der Palette der Scheibe, Stärke mit dem Abstand, weiche Kante, weil die Scheibe eine ausgedehnte Quelle ist. Nahe Sterne leuchten Körper mit an. Doppler δ³ für Körper, abschaltbar mit dem Szenen-Schalter „Relativistisch“.
- **Doppelstern:** Spender als Roche-Tropfen mit Schwerkraftverdunklung zur Spitze, Begleiter mit Radius 0,2, Scheibe bis 0,26 des Abstands, Strom ab der Spitze des Spenders mit Heißfleck am Scheibenrand.
- **Schoner:** `BlackHoleSaverView.swift` brauchte keine Änderung. Die gedachte Randlinie bei 3 % der Höhe gilt in `Orbits.edgeLine`, sobald ein Band schmaler als 3 Punkte ist.
- **Zusätzliche Werkzeuge:** `--series` mit `--crop`, `--drop`, `--debug 6`, neue `--add`-Schlüssel für Bahnen und Ränder, `BH_SETTINGS` für Live-Messungen auf einer Kopie. `--bench-ab` misst jetzt Bild für Bild abwechselnd und wartet auf jedes Bild (Median von 480), blockweise streute es zu stark.
- **Sternsystem:** Jet 0,8 c, Bögen einer Galaxie hinter dem Loch, Balkenspirale, Pulsar mit Strahlen, Gürtel 50 bis 58 M mit 7 000 Brocken, Ringplanet bei 66 M mit Mond, Komet auf exzentrischer Bahn.

Offen für Stufe 3:

- Bench liegt mit 0,35 bis 0,37 ms genau an der Grenze. Reserve gäbe es bei den Galaxien (in `nebFrag` statt `dispFrag`) und bei den Planetenkacheln (halbe Auflösung bei großen Körpern).
- Ein Staubring kostet allein 0,26 ms, der Dunst im Lichtpuffer ist der größte Teil.
- Live-Bildschirmaufnahme von „Nur Ränder“ mit Randobjekt und Messung mit zwei Schirmen, dazu `footprint` der laufenden App.
- Linse der Körper und Punkte ist eine dünne Linse im Abstand des Lochs. Nahe am Schatten weicht die Lage der Bilder von der Kerr-Bahn ab.
- Look-Freigabe durch den Nutzer, besonders nahe Sterne (Granulation), Staubring und Doppelstern.

### Stufe 3: Raumschiffe und Stationen

**Umfang:** Netz-Pipeline in den Atlas (Tiefe, MSAA memoryless, Licht wie Planeten, Fenster und Glühen als Materialien, Triebwerks-Halo im Weg F); Bausteine und Generatoren; Katalog mindestens zwei Schiffe je Universum plus alle Stationen der Tabelle, Rest der Tabelle nachziehbar; Ereignisse mit Ankunft und Abflug auf Randwegen; eigene Modelle (Import, Kopie nach `Models/`, Normalisierung, Schoner-Export); `--event … --phase`.

**Neue Dateien:** `ShipCatalog.swift` (Bausteinlisten), `MeshBuilder.swift` (Generatoren, ModelIO-Import, Dreiecksgrenze), `ModelStore.swift` (Ordner, Import, Schoner-Kopie), Effekt-Shader in `BodyShaders.swift`.
**Geänderte Dateien:** `BodyRenderer.swift`, `ObjectSystem.swift` (Ereignis-Fahrplan), `ObjectCatalog.swift`, `ObjectsTab.swift` (Universum-Menüs, Ereignisse, Modell-Section), `AppDelegate.swift` (Modelle beim Schoner-Export mitkopieren), `scripts/build-saver.sh`.

**Abnahme:** `--catalog ship` und `--catalog station` als Raster mit Namen (der Nutzer prüft die Wiedererkennbarkeit); je Ereignis drei Phasenbilder; eine OBJ- und eine USD-Datei, zum Test per `MDLAsset.export` aus einem Bausteinschiff erzeugt, importiert und gezeigt; Schiff auf Bahn hinter dem Loch gelinst; Budget mit drei Schiffen gleichzeitig ≤ +0,1 ms Bench zusätzlich.

**Stand 2026-10-12: gebaut.** Commits `2cc3e0f`, `30d9236`, `e4cfdfd`, `ef3851b` und der Abschluss-Commit danach. Vorher, eigener Commit `5537c85`: nahe Sterne nachgebessert (selbstleuchtend, Randverdunklung, Lichthof, Farbe nach Temperatur, Nebelhülle beim Wolf-Rayet, pulsierende Cepheide, glühender Doppelstern), Bilder in `shots/objekte/stufe2/`, die alten in `stufe2/vorher/`. Prüfbilder der Stufe 3 in `shots/objekte/stufe3/`.

Abnahme, gemessen auf dem MacBook Air M4:

| Kriterium | Ergebnis |
| --- | --- |
| Katalog Schiffe und Stationen | erfüllt. `s3-schiffe.png` (42 Schiffe), `s3-stationen.png` (10 Stationen), mindestens zwei Schiffe je Universum, alle Stationen der Tabelle. Wiedererkennbarkeit prüft der Nutzer |
| Je Ereignis drei Phasenbilder | erfüllt. 16 Ereignisse, `s3-ereignis-<name>.png`, dazu Ankunft und Abflug am Rand in `s3-rand-ereignisse.png` |
| OBJ und USD importiert | erfüllt. `--export-ship` schreibt OBJ, USDA, USDC und PLY, `--import-check` lädt sie (Falke 2132, Enterprise 3316 Dreiecke), `s3-import.png` zeigt alle vier. USDZ kann ModelIO hier nur lesen, nicht schreiben |
| Schiff auf Bahn hinter dem Loch gelinst | erfüllt. `s3-schiff-hinten.png` (Gargantua, polare Bahn): Hauptbild und Gegenbild, in der Mitte ein Einstein-Ring aus der Enterprise. Bei „Dein Strudel“ verdeckt die dichte Scheibe die Bilder größtenteils |
| Budget drei Schiffe ≤ +0,1 ms | erfüllt. Enterprise, Falke, Sternzerstörer fest im Bild (120 bis 240 Punkte): +0,089 bis +0,090 ms in drei Läufen. Grafikspeicher +11 MB. Drehen sich alle drei in jedem Bild, kostet das +0,23 bis +0,29 ms |
| Presets ohne Objekte gleich | erfüllt. Alle fünf, beide Größen: 0 abweichende Pixel |
| `settings.json` lädt ohne Verlust | erfüllt. `--selftest --settings-file` mit einer Kopie grün |
| Nur Ränder | erfüllt im Bild. `--edgecheck` mit Schiff am Rand: größte Abweichung 2 von 255. Bench der Streifen mit Schiff: kein Mehrverbrauch |

Offene Punkte aus Stufe 2:

- **Reserve beim Bench:** Galaxien und Nebelhüllen der Himmelsobjekte laufen jetzt in `nebFrag` (halbe Auflösung, mit dem Nebel aufgefrischt), Sterne, Pulsare und Galaxienkerne bleiben scharf in `dispFrag`. Wechsellauf alt gegen neu, je sechs Läufe: Sternsystem +0,385 ms alt, +0,365 ms neu (Median). Der Rechner maß an diesem Tag insgesamt höher als bei Stufe 2 (damals +0,353 bis +0,37 ms für dieselbe alte Version). Das Ziel 0,35 ms ist damit nur unter den damaligen Bedingungen erreicht, heute nicht sicher.
- **Staubring:** Der Dunst liegt im Lichtpuffer in viertel statt halber Auflösung, die Flecken so groß auf dem Schirm wie vorher, der feine Staub geht direkt ins Bild. Der Lichtpuffer ist nur so groß wie Gürtel und Ringe auf dem Schirm. +0,253 ms alt, +0,174 ms neu (je drei Läufe im Wechsel).

Abweichungen vom Plan:

- **Kein Weg über den Atlas als Render-Ziel:** Jedes Schiff wird in einen eigenen kleinen Render-Pass gerastert (Farbe und Tiefe 4x MSAA, `memoryless`), in eine Kachel aufgelöst und per Blit an seinen Platz im Atlas kopiert. Ein Pass direkt auf den Atlas hätte ihn ganz geladen und gespeichert.
- **Neue Datei `ShipSystem.swift`** (Ereignis-Fahrplan, Lage im Raum) und **`ShipShaders.swift`** (Netz-Shader) statt Teile in `ObjectSystem.swift` und `BodyShaders.swift`. Die Licht-Effekte der Ereignisse und die Abgasfahnen stehen wie geplant in `BodyShaders.swift` (Weg F, Arten 7 und 8).
- **Bausteine:** Kasten, Balken, Rohr und Kegelstumpf, Drehkörper aus einem Profil, Ellipsoid, Kapsel, Torus und Torus-Bogen, Prisma mit schrägen Seiten (für Keile, Pyramiden, Sternzerstörer), Platte. Statt einer eigenen Extrusion aus einem 2D-Umriss deckt das Prisma das ab.
- **Materialien:** Hülle mit Platten, dunkles Metall, Lack, Glühen (eigene Farbe oder Glühfarbe des Objekts), Gold-Folie, Solarzellen, Glas, Borg-Maschinerie, Todesstern-Oberfläche mit Graben und Superlaser-Schüssel, durchscheinende Membran (Ring-Tor, Stargate), Lampe. Fensterlichter als Punkte in einem Gitter im Modellraum, nur auf Wänden, nicht auf Decks.
- **Triebwerks-Halo, Positionslichter und Abgasfahnen** stehen im Netz als Marken und werden in Weg F gezeichnet. Positionslichter blinken rot (Backbord) und grün (Steuerbord), wo das Schiff sie hat.
- **Weg F für Schiffe:** Ein Schiff ohne Linse, das nichts verdecken kann (über dem Loch, seitlich außerhalb der Scheibe oder näher als die ganze Scheibe), kommt als Sprite über das Bild statt in Weg L. Das senkt die Kosten pro Schiff.
- **Kachel-Speicher für Schiffe:** neu gerastert nur bei einer Drehung um mehr als ein halbes Pixel am Rand, einem Ereignis oder viermal pro Sekunde für animierte Lichter.
- **Ereignisse:** 16 Arten in acht Darstellungen (Streifen, Hyperraum, Blitz mit Ring, Wirbel, Tarnschimmer, Pulsieren, Lichttunnel, Triebwerksflamme). Ein Ereignis spielt den Abflug, eine Ankunft denselben Ablauf rückwärts. Am Rand kommt ein Schiff mit 8 bis 22 % der Breite an und geht bei 68 bis 84 %. Kawoosh (Stargate) und Durchflug (Ring-Tor) fehlen, die Stationen haben in Stufe 3 keine Ereignisse; die Membran schimmert dafür ständig.
- **Zusätzliche Schiffe:** Allianz-Kreuzer (Firefly) und Reaper (Mass Effect), damit jedes Universum zwei Schiffe hat. Monolith zählt als Schiff (er hat ein Ereignis).
- **Frog-Raumer:** nach dem Vorschlag im Plan (rotierende Scheibe mit gezacktem Leuchtrand, pulsierender Kern), nicht an Standbildern geprüft.
- **Eigenes Modell:** Import über `NSOpenPanel` in den Ordner Models, OBJ bringt seine MTL-Datei mit, Farbe aus der Grundfarbe des Materials, keine Texturen. Achsen: y der Datei nach oben, die längere der beiden anderen nach vorn. Ab 200 000 Dreiecken eine Warnung, ab 1 000 000 lädt die App das Modell nicht.
- **Zusätzliche Werkzeuge:** `--only`, `--event … --phase … --arrival`, `--phases`, `--vertical`, `--export-ship`, `--import-check`, `--ships-demo`, `BH_MODELS`.

Offen für Stufe 4:

- Look-Freigabe durch den Nutzer, vor allem Romulanischer Warbird, Cylon Raider, Frog-Raumer und Heart of Gold, die am wenigsten sicher getroffen sind.
- Ereignisse Kawoosh und Durchflug, wenn Ring-Tor und Stargate echte Wurmloch-Linsen werden; Ereignis „Durchs Wurmloch“ für die Endurance.
- Vorzeige-Preset „SciFi-Hafen“ (Stufe 4 laut Plan).
- Schiffe werfen keine Schatten auf sich selbst; Untertasse und Rumpf beleuchten sich gegenseitig nicht.
- Budget Sternsystem unter wechselnden Bedingungen neu messen, live mit `BH_DEBUG=1`.
- Live-Bildschirmaufnahme von „Nur Ränder“ mit einem Schiff am Rand, Schoner mit eigenem Modell ansehen.

### Stufe 4: Zweites Loch, Wurmloch, Jet am zweiten Loch

**Umfang:** Linsenliste in `dispFrag` und `nebFrag`; Mini-Strahlenkarten mit eigenem Schlüssel und Jet; zweites Loch mit und ohne Scheibe, Doppelsystem-Bahn; Wurmloch Kugel und Ring-Tor mit anderer Seite; Ring-Tor und Stargate-Tor als Rahmen des Wurmlochs; Ereignis „Durchs Wurmloch“; Vorzeige-Preset „SciFi-Hafen“.

**Neue Dateien:** `Lenses.swift` (Linsen packen, Mini-Karten verwalten).
**Geänderte Dateien:** `Shaders.swift` (`lensAll`, parametrisierte `diskShade`), `ObjectShaders.swift`, `Renderer.swift`, `ObjectCatalog.swift`, `ObjectsTab.swift`, `Settings.swift` (Preset).

**Abnahme:** zweites Loch mit Scheibe zeigt eigenen Photonenring und gebogene Scheibenrückseite (`s4-zweites-loch.png`); Doppelsystem-Zeitreihe; Wurmloch zeigt andere Seite mit Rand-Ring und biegt Nebel und Sterne außen (`s4-wurmloch.png`); Maus-Linse und zweites Loch gleichzeitig ohne Artefakte; „SciFi-Hafen“ beide Schirme; Budget: zweites Loch ≤ +0,1 ms Bench, Mini-Karte ≤ 8 MB.

**Stand 2026-10-12: gebaut.** Commits `96b8cdc`, `bf027f1`, `4168cf7` und der Abschluss-Commit danach. Vorher, eigener Commit `c194926`: Galactica nachgebessert (Alligatorkopf, schmaler Hals, zwei Flugdecks, die vorn und hinten über den Mittelteil ragen, Triebwerksgruppe, Panzerplatten), Katalog neu in `shots/objekte/stufe3/s3-schiffe.png`, das alte Bild in `stufe3/vorher/`. Prüfbilder der Stufe 4 in `shots/objekte/stufe4/`.

Abnahme, gemessen auf dem MacBook Air M4:

| Kriterium | Ergebnis |
| --- | --- |
| Zweites Loch mit Scheibe: eigener Photonenring, gebogene Scheibenrückseite | erfüllt. `s4-zweites-loch.png`: Schatten mit dünnem Ring, die Rückseite der Scheibe biegt sich über und unter den Schatten, die zukommende Seite heller. Ohne Scheibe `s4-zweites-loch-ohne-scheibe.png`, mit Jet `s4-zweites-loch-jet.png` |
| Doppelsystem-Zeitreihe | erfüllt. `s4-doppelsystem.png`, zwölf Zeitpunkte einer Bahn: hinter dem Hauptloch als dünner Einstein-Bogen um den Schatten (`s4-hinter-dem-loch.png`), davor biegt es den Schatten des Hauptlochs zur Sichel und die Scheibe um sich herum (`s4-vor-dem-loch.png`) |
| Wurmloch: andere Seite, Rand-Ring, biegt außen | erfüllt. `s4-wurmloch.png`, `s4-wurmloch-galaxie.png`, `s4-wurmloch-unser-himmel.png`; auf einer Bahn hinter dem Loch als Einstein-Ring, davor biegt es das Loch (`s4-wurmloch-bahn.png`) |
| Maus-Linse und zweites Loch gleichzeitig | erfüllt. `s4-maus.png`: keine Nähte, keine Lücken. Die Maus-Linse sitzt in der Ebene des Hauptlochs und biegt auch das zweite Loch |
| SciFi-Hafen beide Schirme | erfüllt. `s4-scifi-hafen-ultrawide.png`, `s4-scifi-hafen-hochkant.png` |
| Mini-Karte ≤ 8 MB | erfüllt. 512 x 512: 6,3 MB, mit Jet 7,9 MB (`--mem`), Selbsttest prüft es |
| Budget zweites Loch ≤ +0,1 ms Bench | nicht erfüllt. `--bench-ab` 3440 x 1440: fest im Bild +0,63 bis +0,68 ms, Standard-Doppelsystem +0,78 bis +0,91 ms (je nach Abstand zur Kamera), ohne Scheibe gleich. Wurmloch +0,19 bis +0,23 ms, SciFi-Hafen +0,70 ms. Grund: Ein Loch mit 0,3 Massen hat bei 90 M Kamera-Abstand einen Einstein-Radius von mehreren hundert Pixeln, ein großer Teil des Schirms muss pro Pixel abgelenkt werden. Der 0,1-ms-Richtwert ging von einer Linse nur in der Box des Lochs aus |
| Presets ohne Objekte gleich | erfüllt. Alle fünf, beide Größen: 0 abweichende Pixel |
| `settings.json` lädt ohne Verlust | erfüllt. `--selftest --settings-file` mit einer Kopie grün, SciFi-Hafen kommt als siebte Voreinstellung dazu |
| Nur Ränder | erfüllt im Bild. `--edgecheck` mit SciFi-Hafen und mit zweitem Loch: größte Abweichung 2 von 255 |
| Live mit `BH_DEBUG=1` | gemessen, über dem Richtwert. Eingebauter Schirm 1920 x 1242, 30 fps, je 70 s auf einer Kopie der Einstellungen (`BH_SETTINGS`), Median der Log-Zeilen, im Wechsel: Dein Strudel 3,99 und 3,95 ms, SciFi-Hafen 5,33 und 5,47 ms (+1,4 bis +1,5 ms), Sternsystem 5,12 ms (+1,15 ms; bei Stufe 2 waren es +0,9 bis +1,0 ms). Andere Programme liefen weiter, ein zweiter Schirm war nicht angeschlossen |

Abweichungen vom Plan:

- **Linsenliste:** höchstens zwei Objekt-Linsen plus Maus-Linse, davon höchstens zwei Löcher mit eigener Karte. Ein Loch oder Wurmloch vor der Ebene des Hauptlochs biegt den Strahl zuerst, das Hauptloch danach; eins dahinter biegt danach. Wie stark eine Linse vor der Ebene die Lage auf der Ebene des Hauptlochs verschiebt (Scheibe, Schatten), hängt von ihrem Abstand ab: an der Ebene gar nicht, nah an der Kamera ganz. Beim Wechsel durch die Ebene sind beide Wege gleich, nichts springt.
- **Mini-Karte unabhängig vom Abstand:** Sie wird einmal für eine Kamera in 400 M (des zweiten Lochs) gerechnet und speichert die Fluchtrichtung; pro Bild wird daraus die Drehung des Strahls genommen und auf die Richtung des Pixels angewandt. So muss die Karte nur neu gerechnet werden, wenn sich Spin, Blickwinkel, Scheibe oder Jet ändern, nicht auf jedem Schritt der Bahn. Die Windung der Karte taugt für den Photonenring nicht (von 400 M aus zählt sie den langen Weg mit), das Ringleuchten kommt aus dem Ablenkwinkel.
- **Fernfeld:** außerhalb der Karte nicht die Punktlinse aus dem Randwert, sondern die Ablenkung im schwachen Feld bis zur dritten Ordnung als Verschiebung auf dem Schirm, ohne Kartenzugriff, zwischen Kartenrand und 1,25-fachem Radius übergeblendet. Sie läuft bis zum 3,2-fachen Radius der Karte weich aus (bei „Sparsam“ 2,4-fach), sonst würde jedes Pixel des Schirms gerechnet.
- **Eigene Pass-Varianten:** dispFrag, nebFrag und die Himmelsmaske mit Linsen sind über Funktionskonstanten eigene Pipelines, die nur laufen, wenn ein zweites Loch oder Wurmloch da ist. Mit dem Linsen-Code im gemeinsamen Shader war jedes Bild ohne Linsen 0,5 ms langsamer und um 1/255 anders. Ein Loch hinter der Ebene braucht noch eine Variante (Licht im Hintergrund, unter Scheibe und Schatten).
- **Licht der Linsen vor der Ebene als eigener Zeichenschritt:** Schatten, Ring, Scheibe und Jet des zweiten Lochs, die andere Seite von Wurmloch und Tor und die Tor-Ereignisse zeichnet ein Quadrat pro Linse direkt nach dispFrag im selben Pass (programmierbares Blending über die lineare Kopie, wie Weg F). Körper aus Weg L, die vor dem zweiten Loch liegen müssten, liegen deshalb darunter.
- **Jet am zweiten Loch** als Schalter mit Länge, Tempo und Helligkeit am Loch selbst statt eines eigenen Jet-Objekts mit `attach`. Form wie der Standard des Hauptjets.
- **Wurmloch:** Punktlinse außen (Einstein-Radius 1,25 Kehlenradien mal Linsenstärke), innen eine Abbildung ψ = 0,55 x / √(1 − x² + 0,012), die zum Rand mehrfach herumläuft. Andere Seite: eigener kühler Nebel aus Rauschen mit einem Band wie einer Milchstraße, eigene Sterne, wahlweise eine Galaxie in der Mitte (Standard) oder unser Himmel von hinten. Wo das Bild zu fein wird, mittelt es. Ein Wurmloch auf einer Bahn dahinter wird vom Hauptloch zum Einstein-Ring.
- **Tore:** keine eigene Wurmloch-Art „Ring-Tor“, sondern Ring-Tor und Stargate-Tor bekommen eine flache Pforte in ihrem Ring (Ellipse aus der Lage der Station), mit Schalter „Andere Seite zeigen“. Nur vor der Ebene des Hauptlochs. Die Membran wird dafür dünn (Stargate 45 %, Ring-Tor 20 %).
- **Ereignisse:** Kawoosh (Stargate) und Durchflug (Ring-Tor) laufen im Ring, die Station bleibt stehen. Durchs Wurmloch (Endurance): das Schiff fliegt zur Mitte des nächsten Wurmlochs auf dem Schirm, schrumpft und verschwindet mit einem Blitz. Ohne Wurmloch schrumpft es an Ort und Stelle. `s4-kawoosh.png`, `s4-durchflug.png`, `s4-durchs-wurmloch.png`.
- **SciFi-Hafen:** Wurmloch mit Galaxie rechts oben, Babylon 5 links oben, Stargate-Tor rechts unten mit Kawoosh, Enterprise-D, Endurance und Galactica auf Bahnen, Millennium Falke und White Star am Dock, Rocinante an der Menüleiste.
- **Lastanzeige:** zweites Loch „schwer“ mit 0,75 ms, Wurmloch „mittel“ mit 0,2 ms, nach den Messungen oben.
- **Zusätzliche Werkzeuge:** `--debug 7` (wo Linsen biegen), `--catalog blackHole|wormhole`, `--settings-shot … --exotics-demo`.

Offen:

- Budget des zweiten Lochs und live von SciFi-Hafen (siehe oben). Weiter sparen ginge über eine kleinere Reichweite, eine Ablenkung in halber Auflösung für den Hintergrund oder eine Karte der Ablenkung pro Bild in viertel Auflösung.
- Bei großen Massen (ab etwa 0,6) sieht man an der Innenkante des unteren Scheibenbilds Treppen, die Karte hat dort zu wenig Auflösung. Behoben am 2026-10-13, siehe „Naht bei zwei Löchern“.
- Sterne mit Lichthof (Weg F) und die Bilder der Körper und Partikel werden vom zweiten Loch nicht verschoben, nur Himmel, Nebel, Scheibe und Weg L.
- Look-Freigabe durch den Nutzer, besonders Wurmloch, Kawoosh und Doppelsystem.

### Sparrunde nach Stufe 4

**Stand 2026-10-12.** Ziel: live höchstens +1,0 ms pro Bild für Sternsystem und SciFi-Hafen gegenüber Dein Strudel ohne Objekte, zweites Loch im Benchmark höchstens etwa +0,3 ms, Look gleich.

**Messweg.** Neu: `--bench-passes` (GPU-Zeit pro Pass aus den Zeitstempeln von Metal an den Pass-Grenzen, mit und ohne Objekte im Wechsel), `--pace 30` (taktet die Bench-Läufe wie die App, die GPU taktet dann herunter; streut stark), `BH_PROFILE=1` mit `BH_DEBUG=1` (Zeit pro Pass im Live-Log). Live gemessen wie bisher mit `BH_SETTINGS` auf einer Kopie, eingebauter Schirm 1920 x 1242, 30 fps, je 60 s, alter und neuer Stand im Wechsel, drei Runden. Der Rechner lief an diesem Tag schneller als bei Stufe 4 (Strudel 2,4 statt 4,0 ms); verglichen werden nur Differenzen aus derselben Runde.

**Wo die Zeit vorher hinging.**

| Posten | Messung |
| --- | --- |
| Sternsystem, Bench 1920 x 1242 | +0,28 ms: `dispFrag` mit Weg F +0,19, Lichtpuffer 0,10, Körperkacheln 0,02 (in 30 % der Bilder), `glowRefine` 0,01 (in 20 % der Bilder), Nebel 0,01 |
| Sternsystem, getaktet auf 30 fps | Lichtpuffer 0,4 bis 0,7 ms, Körperkacheln 0,2, `glowRefine` 0,15: kleine Pässe kosten bei niedrigem Takt ein Vielfaches |
| Sternsystem je Art (`--drop`, Bench) | Planet mit Mond 0,05, Gürtel 0,04, Jet 0,035, Galaxien 0,03, Komet 0,02, Pulsar 0,01 ms |
| SciFi-Hafen, Bench 1920 x 1242 | +0,64 ms: `dispFrag` mit Linsen und Weg F +0,58, Schiffe 0,10 plus Kopie 0,014 (in 55 % der Bilder neu gerastert, je Schiff ein eigener Pass), Nebel mit Linse +0,01 |
| SciFi-Hafen je Art | Wurmloch 0,18, Schiffe 0,14, Stationen 0,04 ms |
| SciFi-Hafen, getaktet | Schiffe 0,9 ms im Mittel: jeder Schiffspass hat einen festen Preis, bei niedrigem Takt mehr als das Zeichnen |
| Zweites Loch (Doppelsystem), Bench 3440 x 1440 | +0,78 ms, fast alles in `dispFrag`: die Linsen-Variante lief über den ganzen Schirm. Der Code der Lochschicht im Shader kostete allein 0,2 ms (Register), der Kreis um das Hauptloch 0,26, der Fernfeld-Ring 0,2 bis 0,26, das Innere 0,12 |

**Was geändert ist.**

1. **Linsen-Pässe in Kacheln.** `dispFrag` und `nebFrag` laufen bei Linsen in Kacheln zu 32 Pixeln, je Kachel eine von drei Varianten: ohne Linsen, wo `lensNear` überall falsch wäre; Fernfeld (Funktionskonstante `lensFar`, ohne Strahlenkarte und Lochschicht), wo jede Linse nur mit ihrem schwachen Fernfeld wirkt; volle Variante nahe an Loch und Wurmloch. Für Linsen hinter der Ebene schätzt die CPU, wohin der Strahl nach dem Hauptloch zeigt (schwaches Feld bis zur dritten Ordnung, mit 30 % Rand), und nimmt um das Hauptloch nur die Kacheln mit, deren Strahlen die Linse treffen können. Gleiche Kacheln werden zu Rechtecken zusammengefasst und als Quadrate gezeichnet (`vRects`), drei Zeichenaufrufe pro Pass. Bei der Maus-Linse läuft die volle Variante überall wie bisher.
2. **Schiffe in einem Pass.** Alle neu zu rasternden Schiffe eines Bilds liegen nebeneinander in einem Zwischenbild (Regal-Packung, wenige feste Größen), ein Render-Pass, eine Kopie ins Atlas. Vorher ein Pass und eine Kopie je Schiff.
3. **Lichtpuffer etwa 20-mal pro Sekunde** wie der Nebel, statt in jedem Bild. Darin liegen nur langsame Dinge: Gürteldunst, Schweife, Meteorrauch, Nebelhüllen.
4. **`glowRefine` nur, wenn sich seine Eingaben ändern** (Startpunkt, Richtung), nicht schon, wenn ein Lichthof seine Größe ändert. Beim Pulsar lief es vorher in jedem fünften Bild.
5. **Suchbereich von Weg L** nur nach außen erweitert: Die Linse schiebt das Hauptbild vom Loch weg, nie zu ihm hin. Das Rechteck rechnet die CPU (`BodyRef.cand`).
6. **Lastanzeige:** zweites Loch 0,5 statt 0,75 ms, Wurmloch 0,12 statt 0,2 ms.

**Messwerte nachher.**

| | vorher | nachher |
| --- | --- | --- |
| Live Sternsystem (drei Runden) | +0,97, +1,42, +0,96 ms | +0,84, +0,74, +0,90 ms |
| Live SciFi-Hafen (drei Runden) | +1,34, +1,35, +1,42 ms | +1,13, +1,23, +1,15 ms |
| Bench zweites Loch, Doppelsystem bei `--time 20` | +0,77 bis +0,78 ms | +0,44 ms |
| Bench zweites Loch fest vor der Ebene (`mode=fixed`, x 0,75) | +0,62 ms | +0,65 ms |
| Bench Wurmloch | +0,19 ms | +0,11 ms |
| Bench SciFi-Hafen 3440 x 1440 | +0,68 ms | +0,53 ms |
| Bench Sternsystem 3440 x 1440 | +0,38 ms | +0,30 bis +0,36 ms |
| Grafikspeicher Sternsystem, SciFi-Hafen | 83 MB | 83 MB |

Look: Presets ohne Objekte pixelgleich zu `shots/objekte/referenz/` (beide Größen, `--top 24 --bottom 70`, Hochkant mit `--hole 0.5,0.3`). Sternsystem, Schiffe und Körper hinter dem Loch pixelgleich zum alten Stand. Szenen mit Linsen weichen um 1 von 255 im Dither ab (die Quadrate interpolieren die Bildkoordinate minimal anders als das Vollbild-Dreieck), höchstens ein Pixel pro Bild mehr als 8 von 255 (ein Stern an einer Zellgrenze). Mit bloßem Auge kein Unterschied. `--selftest` grün, `--edgecheck` 1 bis 2 von 255.

**Was nicht erreicht ist.**

- SciFi-Hafen live +1,15 statt höchstens +1,0 ms. Der größte Rest ist `dispFrag` mit Weg F (live um +0,5 ms), darin das Fernfeld des Wurmlochs, dann das Rastern der Schiffe (live 0,17 ms plus 0,06 ms Kopie; Babylon 5 dreht sich und wird jedes dritte Bild neu gerastert).
- Zweites Loch: Doppelsystem +0,44 statt etwa +0,3 ms. Ein Loch fest vor der Ebene des Hauptlochs bleibt bei +0,65 ms: sein Fernfeld reicht über 966 Pixel, und dort kostet nicht die Formel, sondern die Kette danach (Kartenzugriff an verschobener Stelle, `holeAfter`). Versuche ohne Erfolg: eine eigene schlanke Fernfeld-Kette und eine Verschiebung ohne Rechnung änderten die Zeit nicht messbar.
- Eine Verschiebungs-Textur in niedriger Auflösung würde nach diesen Versuchen nur die Formeln sparen, nicht den Rest der Kette. Der nächste Hebel wäre die Lochschicht aus der vollen Variante in eine eigene Textur im Raum der Linse auszulagern (Messung: 0,2 ms, als die volle Variante den ganzen Schirm deckte) und die Reichweite des Fernfelds; beides ändert Code oder Look stärker.

### Materialien und glTF

**Stand 2026-10-13.** Ziel: Schiffe und Stationen sehen aus wie gute Film-Modelle statt wie graue Kunststoffmodelle, ohne dass drei Schiffe mehr als +0,15 ms im Benchmark kosten. Danach ein eigener glTF-Lader.

**Materialien (Teil A).**

- Jedes Bauteil hat Metallanteil und Rauheit. Die Hülle nimmt das Finish ihres Entwurfs (`ShipDesign.finish`, je Schiff gesetzt, etwa Enterprise satinierter Lack, Orion VIII fast Chrom, Galactica stumpfe Panzerung), einzelne Teile ein eigenes (`PartMat.steel`, `.paint`, `.ceramic`, `.foil`). Apollo ist blankes Aluminium, Starship Edelstahl, Hubble Silberfolie. Im Eckpunkt steckt das Finish gepackt in einem Float (`MeshData`: vier statt drei float4 pro Ecke, dazu Texturkoordinaten und Verdeckung).
- Licht: GGX mit Schlick-Fresnel für Scheibe und nahen Stern, Größe des Glanzlichts nach dem Winkel, unter dem die Scheibe erscheint. Umgebung über die Split-Sum-Näherung (Karis).
- Spiegelung: ein kleiner Himmel 256 x 128 (rgba16Float, mit Mipmaps für raue Flächen) aus demselben Nebel-Rauschen wie `bakeNebula`, gefärbt wie `nebulaColour`, mit Sternen, gebacken einmal pro Look (Schlüssel: Palette, Nebel, Sterne). Die Scheibe des Lochs kommt analytisch dazu: Schnitt des Spiegelstrahls mit der Scheibenebene, innen heiß, außen in der Palettenfarbe, mit Gasstreifen, davor die Schattenkugel. Dazu ein breiter Schein in Richtung des Lochs.
- Verdeckung: pro Modell einmal ein Voxelgitter (56 pro Kante), aus jeder Ecke 14 Strahlen über die Halbkugel. Wirkt auf Umgebung, Spiegelung und zur Hälfte auch auf das direkte Licht.
- Platten: zwei Größen (grobe Zellen, die sich zufällig längs einzelner Achsen teilen), jede Platte leicht schief, mit eigenem Ton und Glanz. Abnutzung: Schmutzstreifen längs des Schiffs, mehr in Ecken, dunklere Fugen, rauere Stellen.
- Glühen: Fenster mit einem schwachen Lichtschein um jeden Punkt, Triebwerke und Gondeln wie bisher als Emission, Halos weiter in Weg F.
- Regler pro Schiff, Gruppe „Material“: Glanz (Faktor auf die Rauheit), Abnutzung (Standard je Entwurf), Spiegelung. Die Texte stehen in `UIText.swift`.
- Undurchsichtige Teile rastern ohne Mischen und ohne `discard`, durchsichtige (Membranen, Modelle mit Alpha) danach in einer zweiten Variante (Funktionskonstante 20). So rechnet die GPU verdeckte Flächen nicht mehr.

Messwerte (`--bench-ab`, 3440 x 1440, alter und neuer Stand im Wechsel, je zwei Läufe):

| | vorher | nachher |
| --- | --- | --- |
| Drei Schiffe fest im Bild (Enterprise 200, Falke 120, Sternzerstörer 240 Punkte) | +0,058, +0,060 ms | +0,064, +0,071, +0,063 ms |
| Dieselben drei, drehen sich in jedem Bild | +0,148, +0,133 ms | +0,158, +0,169 ms |
| Zwischenstand ohne Trennung undurchsichtig/durchsichtig, drehend | | +0,351, +0,367 ms |
| Presets ohne Objekte gegen `referenz/` | 0 Pixel | 0 Pixel, beide Größen |

Speicher: der Himmel für Spiegelungen 0,35 MB pro Look, Ecken 16 statt 12 Byte mehr. Prüfbilder in `shots/objekte/material/` (vorher in `vorher/`).

Abweichungen:

- Der gespiegelte Nebel ist der Nebel der Voreinstellung, aber ruhend (ohne die Drehung über die Zeit) und ohne Linsenwirkung. Die Scheibe in der Spiegelung ist eine flache Scheibe ohne Lichtbiegung.
- Keine Schlagschatten, nur weiche Verdeckung pro Ecke. Große flache Dreiecke bekommen sie deshalb grob.
- Kein echtes Bloom in der Kachel: Glühen ist Emission mit Lichtschein auf der Hülle, die Halos zeichnet wie bisher Weg F.
- Ein Schiff, das bei einem Ereignis ausblendet, zeigt seine verdeckten Teile nicht mehr durch sich hindurch (Folge der Trennung undurchsichtig/durchsichtig).
- Polierte Metalle bleiben dunkel, wo sie nur schwarzen Himmel spiegeln. Ein schwacher gleichmäßiger Himmel verhindert reines Schwarz.

**glTF (Teil B).**

- Eigener Lader `GLTFLoader.swift` ohne Fremdcode: `.gltf` mit externen oder eingebetteten (Data-URI) Puffern und Bildern, `.glb` mit JSON- und Binärteil. Accessoren aller Komponententypen, auch normalisiert und mit Stride, Knotenbaum mit Matrix oder Verschiebung, Drehung, Skalierung, mehrere Primitives pro Mesh (Dreiecke, Streifen und Fächer), Indizes, Normalen (fehlen sie, als flächengewichtete Mittel berechnet), erste Texturkoordinaten, Eckfarben.
- Materialien: baseColor (Faktor und Bild), metallicRoughness (Faktor und Bild), emissive (mit `KHR_materials_emissive_strength`), normalTexture mit Skala, occlusionTexture mit Stärke, alphaMode MASK und BLEND. Pro Primitive ein Teil mit eigenem Material; im Shader die Materialart 12, Tangenten aus den Ableitungen von Lage und Texturkoordinaten. Abnutzung wirkt dort nur leicht, ohne Platten.
- Bilder über ImageIO, beim Dekodieren verkleinert: Grundfarbe und Normalen höchstens 1024 Pixel, die übrigen 512. Auf der GPU rgba8 mit Mipmaps.
- `extensionsRequired` mit etwas anderem als Emissionsstärke, IOR oder Specular: deutsche Meldung mit dem Namen der Erweiterung und dem Hinweis, ohne Kompression zu exportieren.
- Gleicher Weg wie die anderen Formate: `ModelImport.load` (Ausrichtung, Normalisierung, Grenze von 1 000 000 Dreiecken), `ModelStore` (eine `.gltf` mit externen Dateien kommt in einen eigenen Ordner `Models/<Name>/`, der Bildschirmschoner bekommt den Ordner mit). ModelIO-Importe lesen jetzt ebenfalls Metall, Rauheit, Leuchtfarbe und ein Farbbild.
- Selbsttest: ein Dreieck unter zwei Knoten als `.gltf` mit Data-URI und als `.glb`, im Code erzeugt; Draco als Pflicht-Erweiterung; Accessor außerhalb des Puffers; Import mit externer `.bin` in den eigenen Ordner und die Kopie für den Schoner.

Getestet mit den Khronos-Beispielen Box, BoxTextured und DamagedHelmet (je `.glb`) und einer selbst erzeugten `.gltf` mit externer `.bin` und externem PNG (Rohr mit Karo-Bild, zwei Kind-Knoten mit leuchtendem Material). Prüfbilder in `shots/objekte/gltf/`.

| Messung | Ergebnis |
| --- | --- |
| DamagedHelmet, 15 452 Dreiecke, fest im Bild (220 Punkte), `--bench-ab` | +0,047 und +0,089 ms |
| Grafikspeicher DamagedHelmet (5 Bilder) | +31 MB mit allen Bildern bei 1024, +18,5 MB mit 512 für die Nebenkarten |

Abweichungen:

- Nur die ersten Texturkoordinaten; eine Karte, die `texCoord: 1` will, liest trotzdem die ersten. Sampler-Einstellungen werden ignoriert (immer Wiederholen, linear mit Mipmaps). `KHR_texture_transform` wird nicht gelesen.
- Sparse Accessoren werden nicht ausgewertet (die Grundwerte gelten).
- Durchsichtige Materialien (BLEND) werden nicht nach Tiefe sortiert.
- Die Ausrichtung folgt der Regel der anderen Formate (längere der Achsen x und z nach vorn); glTF schaut nach +z, ein Modell kann deshalb rückwärts fliegen. Drehung richtet es aus.

### Echtere Bewegung

**Stand 2026-10-13: gebaut.** Zeitreihen vorher und nachher in `shots/bewegung/vorher/` und `nachher/` (neues Werkzeug `--stack` legt eine Zeitreihe übereinander, `--series a:b:n` verteilt n Zeitpunkte).

Bestandsaufnahme, was unecht war:

- Vorbeiflüge liefen gerade und mit festen 10 M pro Sekunde, im Zeitmaß der Scheibe schneller als Licht, ohne Ablenkung, ohne Gezeiten, ohne Absturz. Ihr Doppler kam aus einer Schätzung.
- Doppelsystem: das zweite Loch lief, als hätte es keine eigene Masse.
- Monde drehten sich frei, Asteroiden nur um eine feste Achse.
- Meteore flogen mit gleichem Tempo und gleicher Helligkeit schnurgerade.
- Schiffe am Rand: festes Tempo, Nase immer waagrecht, bei Ankunft mit Schub (Full Burn, Strudel) kamen sie rückwärts herein, weil die Ankunft den Abflug rückwärts abspielte.
- Keine Rotverschiebung durch Schwerkraft, Doppler nur als Helligkeit.
- Komet, Gürtel und Kepler-Bahnen waren schon echt (Vis-viva, Periheldrehung, innen schneller, Ionenschweif vom Licht weg, Staubschweif gebogen).

Geändert:

- **Eine Uhr:** Alles, was die Schwerkraft bewegt, läuft auf der Uhr der Scheibe (`Orbits.secondsPerM`: am ISCO genau eine Umlaufzeit der Scheibe). Regler „Zeitraffer“ der Szene (vorher „Tempo aller Objekte“, jetzt bis 10×), pro Körper „Eigener Zeitraffer“ (Standard 1). Komet und zweites Loch haben jetzt Standard 1 statt 3, der Komet im Sternsystem 1 statt 2: die Verhältnisse untereinander sind physikalisch.
- **Vorbeiflug auf einer Kepler-Hyperbel** (`Orbits.Hyperbola`): Tempo weit draußen 0,1 c × Regler, Swing-by um 2 asin(1/e), mit Periheldrehung als gestreckter Winkel (Faktor 1/(1 − 3 M/p)) noch stärker. Unter 4 M stürzt der Körper und wird zum Horizont dunkel. Kleinster Abstand jetzt ab 2 M.
- **Gezeiten:** innerhalb von etwa 20 M wird ein Körper längs des Radius gestreckt und quer gestaucht (Kachel-Kernel, `BodyP.tide`), bis 2,6-fach, Schiffe nicht.
- **Rotverschiebung durch Schwerkraft** zusätzlich zum Doppler, und das Licht färbt sich mit: auf uns zu bläulicher, weg und tief im Trichter rötlicher.
- **Doppelsystem** mit der Summe beider Massen (Umlaufzeit, Tempo, Periheldrehung). Das Hauptloch bleibt stehen: Die Kamera reist mit ihm. Die Bahn relativ zum Hauptloch ist dabei exakt die Kepler-Bahn um die Gesamtmasse; ließe man stattdessen das Hauptloch um den Schwerpunkt wandern, bräuchte die Strahlenkarte jedes Bild neu.
- **Monde gebunden** (Schalter „Gebunden“, Standard an): dieselbe Seite zum Planeten, eine Knolle mit der Längsachse zu ihm. **Asteroiden taumeln:** die Drehachse wandert auf einem Kegel um den Drehimpuls.
- **Meteore** bremsen in der Luft, glühen spät am hellsten, eine Feuerkugel endet mit einem Aufblitzen, das Loch krümmt die Bahn ein wenig zu sich.
- **Schiffe:** Ankunft mit der Nase voran von hinten, bremsend. Am Rand mit Ereignissen: nach dem Sprung schnell und abbremsend, vor dem Sprung 2,5 s Beschleunigen mit stärkerem Triebwerk. Die Nase folgt dem Weg, in Kurven leichte Schräglage wie im Film, Steuerdüsen pusten in engen Kurven. Auf Bahnen keine Schräglage: im freien Fall gibt es keine Kurvenkraft.
- **Selbsttest** (`SelfTestMotion.swift`): Energie und Drehimpuls der Ellipse, Umlaufzeit nach a^1,5, Doppelsystem, Uhr gleich Scheibe, Energie und Ablenkung der Hyperbel, Periheldrehung, Absturz, unter Lichtgeschwindigkeit, reine Funktion der Uhr, Gezeiten, Ankunft, gebundene Monde.

Kosten (`--bench-ab`, 3440 x 1440, alter und neuer Stand im Wechsel): Sternsystem +0,31 und +0,38 ms alt, +0,32 und +0,36 ms neu; SciFi-Hafen +0,55 und +0,77 ms alt, +0,61 und +0,54 ms neu. Im Rauschen gleich. Die Rechnung ist CPU (einige Newton-Schritte pro Vorbeiflug), auf der GPU nur ein Zweig im Kachel-Kernel. Presets ohne Objekte pixelgleich zu `referenz/`, `--selftest --settings-file` mit einer Kopie grün.

Offen:

- Anflug und Abflug an Stationen (Andocken) gibt es nicht; dafür bräuchte es eine eigene Bewegungsart.
- Ringe der Planeten sind drehsymmetrisch gezeichnet, ihr Umlauf ist nicht zu sehen.
- Vorbeiflüge brauchen bei 0,1 c rund 15 Minuten durchs Bild. Wer es lebhafter will, dreht „Tempo weit draußen“ oder den Zeitraffer hoch.
- Die Absturzbahn ist eine Newton-Hyperbel mit Periheldrehung, keine echte Kerr-Bahn; das Einfrieren am Horizont ist nur als Abdunkeln nachgebildet.

### Ankunft und Transwarp

**Stand 2026-10-14: gebaut.** Branch `events`. Zwei Befunde aus der Durchsicht der Galerie: Die Ankunft bei Warp und Hyperraum sah aus wie rückwärts einparken, und der Transwarp-Wirbel hatte gerade Feldkanten.

Ursachen:

- **Ankunft:** Eine Ankunft spielte den Abflug rückwärts und drehte nur die Verschiebung um. Die Streckung hängt aber am Heck (`shipVert`: `q.x += (q.x + 0.5) * (Streckung - 1)`). Rückwärts gespielt zog sich die Nase zum Heck zurück, das Schiff kam also mit dem Heck voran an. Beim Hyperraum kam dazu das kurze Zurückweichen des Abflugs: umgedreht schob es das Schiff erst nach vorn und dann zurück auf den Platz. Beim Wirbel (Sprungpunkt, Transwarp, Strudelstart) kam das Schiff von hinten, der Wirbel stand aber vor ihm, und rückwärts gespielt beschleunigte es erst und bremste dann.
- **Feldkanten:** Das Licht des Ereignisses liegt auf einem Quadrat mit halber Seite `reach` (Wirbel 2,2 Schiffsradien). Die Gaußglocke des Wirbels war dort noch bei etwa 12 Prozent und wurde an den Seiten des Quadrats abgeschnitten. Der Ring von FTL und Transition lief gegen Ende über das Quadrat hinaus.

Geändert:

- **Eigene Ankunft** (`ShipEventNow.arrivalLook`): Licht, Blenden und Größe laufen weiter rückwärts, die Bewegung nicht. Die Nase steht beim Austritt `d · r³` Schiffslängen hinter ihrem Platz (r von 1 auf 0), das Tempo fällt also nur. Warp 1,6 Längen, Hyperraum 1,2, Wirbel 0,9 mit `r²`, Triebwerksflamme (Epstein, Zündung, Full Burn) wie bisher 4 Längen. Die Streckung hängt bei der Ankunft an der Nase: der Streifen liegt hinter dem Schiff und holt auf. Streifen, Blitz und Wirbel liegen hinter dem Schiff.
- **Wirbel bleibt stehen:** Er öffnet sich 0,9 Schiffslängen vor (Ankunft: hinter) dem Ruheplatz und wandert nicht mehr mit. Beim Abflug fliegt das Schiff jetzt wirklich hinein, vorher lief der Wirbel vor ihm her.
- **Weicher runder Rand** für alles Ereignislicht (`shipEventLight`): Abfall auf null zwischen 62 und 97 Prozent von `reach`, gemessen rund um die Mitte. Dazu größere Quadrate: Wirbel 3,6, Blitz mit Ring 3,4, Lichttunnel 7,5 Schiffsradien.
- **Durchs Wurmloch** (`wormholeSteer`): Vorher lief das Schiff zur Mitte des Wurmlochs hin und von ihr weg, ohne sich zu drehen, also seitwärts oder rückwärts. Jetzt dreht es sich zuerst in einer kurzen flachen Kurve um die eigene Hochachse, in die Kurve geneigt (erste 22 Prozent des Abflugs), bis die Nase auf dem Schirm genau zum Wurmloch zeigt, und fliegt dann immer schneller hinein. Bei der Ankunft kommt es mit der Nase vom Wurmloch weg heraus, bremst bis zu seinem Platz und dreht danach zurück in seine Lage. Reicht die Kurve allein nicht (Dreiviertelansicht fast von der Seite, Ziel oben oder unten), steigt oder sinkt die Nase dazu; ein letzter kleiner Rest wird in der Bildebene ausgeglichen. Galerie: `event-wormhole.jpg` und neu der Clip `event-wormhole.mp4` (12 s, Abflug, Pause, Ankunft).
- Ohne Bewegung und daher unverändert: FTL, Transition, Tarnung, Materialisieren, Auftauchen, Unwahrscheinlichkeit, Sternentor. Kawoosh und Durchflug liegen im Ring des Tors (Linsen-Shader) und hatten keine Kanten.

Belege in `shots/events/`: `warp-ankunft-*` und `hyperspace-ankunft-*` (sechs Phasen der Ankunft, vorher und nachher, dazu als Raster `*-raster.jpg`), `transwarp-galerie-*`, `transwarp-gross-*`, `transwarp-rand-*` und `transwarp-scheibe-*` (Galerie-Ausschnitt, groß, am Bildrand, über der hellen Scheibe). Galerie neu gerendert nach `.tmp/galerie/neu/` mit denselben Befehlen.

Selbsttest (`SelfTestMotion.arrivalChecks`): für jedes Ereignis läuft die Nase bei der Ankunft nur vorwärts, das Tempo fällt monoton, sie endet am Platz. Durchs Wurmloch mit Ziel vorn, hinten, oben, unten und schräg: die Bewegung folgt der Nase auf 2 Grad, in die richtige Richtung, die Drehung springt nicht, die Ankunft bremst monoton. Am Rand für Warp, Hyperraum, Transwarp und Full Burn, oben und unten, nach links und nach rechts: Bewegung der Nase auf dem Schirm längs ihrer Richtung, kein zusätzliches Seitwärts, Tempo fällt monoton.

Kosten (`--bench-ab`, SciFi-Hafen, 3440 x 1440, alt und neu im Wechsel): alt +0,11 und −0,29 ms, neu +0,00 und −0,16 ms, im Rauschen. Mehr Pixel kostet nur ein laufender Wirbel (Quadrat etwa 2,7-mal so groß, für 1,3 bis 2,8 s). Presets ohne Objekte pixelgleich zu `referenz/`.

Nase am Rand (2026-10-22, Version 1.0.1): Drehung und Neigung kippten die Nase auf dem Schirm um etwa 12 Grad, die Kurve setzte aber an der Waagrechten an (nach links sogar mit falschem Vorzeichen); jetzt dreht `shipRotation` von der projizierten Nase auf die Bewegung, um die Blickachse, sodass die Dreiviertelansicht bleibt, belegt durch `SelfTestMotion.bandHeadingChecks` (höchstens 2 Grad, mit Kurven, Ankunft und Abflug) und `shots/nase/`.

### Qualitätsstufen

**Stand 2026-10-13.** Anlass: Der Nutzer fand Teile des Bilds zu grob, vor allem den Jet. Ziel: Jet ohne sichtbare Pixel schon bei der Standardstufe, dazu Stufen wie in Spielen. Branch `qualitaet`.

**Bestandsaufnahme (3440 x 1440, Ausgewogen).**

| Teil | Auflösung | Was man sah |
| --- | --- | --- |
| Strahlenkarte | halb (1720 x 720), 24 Byte pro Texel, 30 MB | weich, aber ohne Treppen |
| Scharfe Zone ums Loch | doppelt, 1,5 Schattenradien | Photonenring sauber. An der inneren Kante des Scheibenbilds bleiben einzelne helle und magentafarbene Pixel: Dort mittelt die Abfrage Scheibenkoordinaten zweier Bilder, kein Auflösungsproblem |
| Jet-Karten | wie die Strahlenkarte, Lage entlang des Jets in 8 Bit | **grob**: senkrechte Spalten, stufige Knoten, Treppen am Fuß. Drei Ursachen: Rauschen beim Einsammeln (höchstens vier Stichproben pro Strahlschritt, ein Schritt ist oft zehn Jetbreiten lang), Lage in 8 Bit, bilineares Hochskalieren |
| Nebel und Galaxien | halb, etwa 20-mal pro Sekunde | Galaxien weich, Arme verwaschen |
| Körper und Schiffe | Kachel so groß wie auf dem Schirm, Atlas 1024 | Ringkante und Rand der Planeten mit Treppen von einem Pixel, Stargate-Ring blockig |
| Mini-Karten der Linsen | 512 x 512 | Rand des Wurmlochs mit leichten Treppen, die kommen aus der Randformel, nicht aus der Karte |
| Partikel | Punkte in voller Auflösung | sauber |
| Lichtpuffer | viertel Auflösung, etwa 20-mal pro Sekunde | weich, unauffällig |

Vergleichsbilder je Stufe in `shots/qualitaet/stufen-*.png`.

**Jet (gilt ab Ausgewogen).**

1. Quer zum Jet wird jeder Strahlabschnitt exakt integriert: eine Gerade durch eine Gauß-Röhre, mit erf. Längs der Achse höchstens acht Stücke, je nachdem, wie stark sich die Höhe ändert. Benachbarte Strahlen stimmen damit überein, das Rauschen ist weg.
2. Lage entlang des Jets in 16 Bit (`rg16Unorm`). Die Jet-Karten brauchen 8 statt 6 Byte pro Texel. Mini-Karte eines zweiten Lochs mit Jet: genau 8 MiB.
3. Außerhalb der scharfen Zone Catmull-Rom statt bilinear (9 Texel in 5 Abfragen), auf die 2 x 2 Nachbarn begrenzt. So entsteht an der Schattenkante, wo die Emission springt, kein Überschwingen.

Eine eigene scharfe Zone für den Jet war danach nicht nötig: Die kubisch hochgerechnete halbe Auflösung sieht aus wie die volle Karte (`shots/qualitaet/jet-vorher-nachher.png`, `jet-m87-vorher-nachher.png`). Der Jetfuß liegt in der scharfen Zone des Lochs.

**Stufen.** Gesamtstufe getrennt für Netzteil und Akku. Standard war zuerst Ausgewogen an beiden (so sparsam wie bisher). Seit 2026-10-13 (Branch `update`) ist der Standard Hoch am Netzteil und Ausgewogen am Akku, siehe „Standard Hoch am Netzteil“ unten. Unter „Erweitert“ hat jeder Bereich eine eigene Stufe, die an Netzteil und Akku gilt. Neue Seite „Qualität“ im Einstellungsfenster (Seite 11), die Auswahl auf „Energie“ und das Detail auf „Objekte“ sind dorthin gewandert. Der Bildschirmschoner nimmt die Stufe am Netzteil (`saver.json` hat dafür `quality`).

| Bereich | Akku sparen | Ausgewogen | Hoch | Ultra |
| --- | --- | --- | --- | --- |
| Loch und Scheibe | Karte 0,4, Zone 1,5 Radien | 0,5, 1,5 | 0,6, 2,0 | 0,75, 2,5 |
| Jet | bilinear | kubisch | kubisch, Karte mindestens 0,6 | kubisch, Karte mindestens 0,75 |
| Nebel und Galaxien | halb, 10-mal pro Sekunde, Galaxie-Kachel 256 | halb, 20-mal, 512 | 0,75, 1024 | voll, 1024 |
| Körper und Schiffe | Kachel 0,6, höchstens 256 | 1, 512, Atlas 1024 | 1,5, 1024, Atlas 2048 | 2, 1024, Atlas 2048 |
| Linsen | Mini-Karte 384, Fernfeld 2,4 | 512, 3,2 | 640, 3,2 | 768, 3,6 |
| Partikel und Schweife | Lichtpuffer viertel, 10-mal | viertel, 20-mal | halb, 20-mal | halb, jedes Bild |

Die Strahlenkarte wächst höchstens auf 2,8 Millionen Texel (67 MB, mit Jet 90 MB). Auf 3440 x 1440 ist das genau 0,75, auf einem 5K-Schirm bleibt Ultra darunter. Kacheln, die feiner als der Schirm gerechnet sind (Hoch, Ultra), werden mit vier Abfragen im Viertelpixel-Abstand heruntergemittelt; einfach bilinear abgefragt wären ihre Kanten sogar stufiger geworden.

Ein Wechsel wirkt ohne Neustart. Die Strahlenkarte wird nur neu gerechnet, wenn sich ihre Auflösung oder die scharfe Zone ändert. Nebel, Lichtpuffer und Kacheln werden beim nächsten Bild neu gezeichnet. Beim Wechsel zwischen Netzteil und Akku übernimmt die App die Stufe sofort. Alte `settings.json`: `mapScale` 0,5 bleibt bei der Gesamtstufe, kleiner wird „Loch und Scheibe“ auf Akku sparen, bis 0,74 auf Hoch, darüber auf Ultra; `detailBox` aus wird Akku sparen. Das Detail einer Szene (`objects.detail`) bleibt in der Datei, wirkt aber nicht mehr.

**Messtabelle** (MacBook Air M4, Median von 480 abwechselnden Bildern `--bench-q`, Grafikspeicher `--mem` für das ganze Bild).

| Stufe | Sternsystem 3440 x 1440 | Sternsystem 1440 x 2560 | SciFi-Hafen 3440 x 1440 | Dein Strudel 3440 x 1440 | Speicher Sternsystem breit / hoch | Speicher Strudel breit / hoch |
| --- | --- | --- | --- | --- | --- | --- |
| Akku sparen | -0,05 ms | -0,04 ms | -0,07 ms | 0,00 ms | 86 / 74 MB | 60 / 52 MB |
| Ausgewogen | 2,7 ms (`--bench`) | 2,0 ms | Grundlast | Grundlast | 108 / 89 MB | 71 / 62 MB |
| Hoch | +0,05 ms | +0,03 ms | +0,05 bis +0,24 ms | +0,02 ms | 193 / 163 MB | 109 / 92 MB |
| Ultra | +0,25 ms | +0,11 ms | +0,20 ms | +0,04 ms | 258 / 215 MB | 163 / 135 MB |

`--bench` absolut, Sternsystem breit, zwei Runden: 2,35 / 2,43 ms, 2,67 / 2,76 ms, 2,81 / 2,83 ms, 3,08 / 2,96 ms. Der SciFi-Hafen streute bei Hoch zwischen zwei Läufen von +0,04 bis +0,24 ms. Je Bereich gegen Ausgewogen (`--qa`): Loch -0,01 / +0,02 / +0,03 ms und -15 / +34 / +83 MB, Jet -0,04 / 0,00 / +0,01 ms und 0 / +18 / +51 MB, Nebel 0,00 / +0,02 / +0,03 ms und 0 / +13 / +30 MB, Körper -0,01 / 0,00 / +0,01 ms und -1 / +28 / +32 MB, Linsen (zweites Loch) -0,08 / +0,01 / +0,05 ms und -3 / +4 / +8 MB, Partikel -0,02 / +0,03 / +0,12 ms. Diese Werte zeigt die Seite „Qualität“ an.

Fazit aus den Zahlen: Pro Bild kosten die Stufen wenig, denn die teuren Pässe laufen in voller Auflösung schon heute. Hoch und Ultra kosten vor allem Grafikspeicher und Zeit beim Neurechnen der Strahlen. Akku sparen spart pro Bild kaum etwas, nur Speicher.

**Abweichungen bei Ausgewogen.** Die fünf Presets ohne Objekte sind pixelgleich zu `shots/objekte/referenz/` (beide Größen). SciFi-Hafen ist pixelgleich zum alten Stand. Sternsystem weicht in 24 886 Pixeln ab, höchstens 9 von 255: der Jet (gewollt) und 213 Pixel an sehr kleinen Körpern, deren Kachel mindestens 8 Pixel groß ist und die jetzt gemittelt statt einfach abgefragt werden.

**Werkzeuge.** `--quality 0...3`, `--qa jet=3,hole=2`, `--bench-q <Stufe>` (gleiche Szene in zwei Stufen abwechselnd, mit `--bench-qa`). `--map` und `--nobox` gehen weiter und überstimmen die Stufe. Selbsttest prüft Standard, alte Dateien, unbekannte Einträge, Speichern und Laden, Obergrenze der Karte und `saver.json`.

**Standard Hoch am Netzteil (2026-10-13).** `QualitySettings.defaultPower` ist Hoch, `defaultBattery` bleibt Ausgewogen. Wer in `settings.json` noch keinen Eintrag `quality` hat oder darin keine Stufe `power`, bekommt Hoch. Eine gespeicherte Stufe bleibt, wie sie ist. Da Version 1.0.0 `quality` beim ersten Speichern immer mit `power` schreibt, betrifft der neue Standard vor allem neue Installationen. Der Bildschirmschoner nimmt die Stufe am Netzteil, also ebenfalls Hoch; eine `saver.json` ohne `quality` lädt mit Hoch. Kosten laut Messtabelle oben: Sternsystem breit etwa +0,05 ms pro Bild und 193 statt 108 MB.

`--snapshot` und `--bench` rechnen ohne `--quality` weiter mit Ausgewogen, damit die Messwerte oben vergleichbar bleiben. Die Referenzbilder in `shots/objekte/referenz/` sind bei Ausgewogen entstanden. `scripts/check-referenz.sh <Ordner>` rendert die fünf Presets ohne Objekte in beiden Formaten ausdrücklich mit `--quality 1` und vergleicht Pixel für Pixel: am 2026-10-13 alle zehn Bilder 0 abweichende Pixel. Selbsttest: Standard Hoch und Ausgewogen, gespeichertes Ausgewogen bleibt, Eintrag ohne `power` bekommt Hoch, alte Datei mit `mapScale` bekommt am Netzteil Hoch, alte `saver.json` rechnet mit Hoch.

**Offen.**

- Die hellen Pixel an der inneren Kante des Scheibenbilds: bräuchte Schattierung pro Strahl in der scharfen Zone statt gemittelter Koordinaten. Kostet Zeit in jedem Bild.
- Rand des Wurmlochs: Treppen kommen aus der Formel des Randrings, die Stufen ändern daran nichts.
- Ringkante der Planeten wird bei Ultra weicher, aber nicht ganz glatt. Ein Planet verschiebt sich zwischen den Stufen um bis zu zwei Pixel (Rundung der Kachelgröße).
- Live mit `BH_DEBUG=1` nicht gemessen, nur im Benchmark. Look-Freigabe durch den Nutzer.

### Naht bei zwei Löchern

**Stand 2026-10-13: behoben**, Branch `fix-naht`.

**Ursache.** Keine Naht beim Sprung von 360 auf 0 Grad und kein fehlender Pol-Fix: Die kleine Strahlenkarte des zweiten Lochs läuft durch denselben `traceRay` wie die Hauptkarte und hat beide Fixes vom 2026-09-25. Die Streifen kamen aus der Art, wie die kleine Karte gelesen wird. Sie ist stark vergrößert (Masse 0,7: zwei Pixel pro Texel), dadurch wurden Fehler beim Filtern zwischen Texeln sichtbar:

1. **Gestrichelter dunkler Ring knapp außerhalb des Schattens.** Die Karte speicherte die Fluchtrichtung oktaedrisch kodiert. Strahlen, die um etwa eine halbe Drehung abgelenkt werden, laufen rückwärts, genau auf die Faltkante der Kodierung. Filtern zwischen Texeln beiderseits der Kante gab eine falsche Richtung, also einen falschen Ablenkwinkel: Das Ringleuchten fiel dort auf null. Belegt mit einem Debug-Ausgang des Ablenkwinkels: an den dunklen Pixeln ein Einbruch von 210 auf 120 von 255 zwischen zwei glatten Nachbarn. Dazu lief der Winkel nach einer vollen Drehung wieder auf null (zweiter, innerer Ring).
2. **Gestrichelter Ring am Kartenrand** (etwa 300 Pixel um das zweite Loch, sichtbar nur auf hellem Grund, also wenn die Bilder der Löcher überlappen): `holeLayer` setzte außerhalb der Karte die Fangzahl auf -1, innen am Rand liegt sie bei -0,125. In 2 x 2-Quads über dem Rand sprang `fwidth`, der Schatten deckte dort einzelne Pixel bis 36 % ab.
3. **Dunkler Riss in der Scheibe** dort, wo ein Scheibenbild vom zweiten in den ersten Durchgang wechselt (der Rand der nahen Scheibe vor dem fernen Bild): Die beiden Durchgänge wurden getrennt gefiltert, die Deckung des fernen Bildes fiel an der Grenze auf die Hälfte.
4. **Treppen an der Innenkante ab Masse 0,6 und magenta-schwarze Funken:** Nahe am Horizont wird der Rotverschiebungsfaktor der Kreisbahnformel unendlich und kippt ins Negative. Gefiltert schnitt das eine Kante entlang des Texelrasters in das stürzende Gas, negative Werte färbten Pixel magenta oder schwarz. Dazu war die Kante an der ISCO hart und zeigte die Stufen der interpolierten Karte.

**Fix** (`Shaders.swift`, `LensShaders.swift`, `Lenses.swift`):

- Die Karte eines zweiten Lochs (`GeoParams.disk.z = 1`) speichert statt der Fluchtrichtung die Drehung des Strahls: Summe der kleinen Drehungen pro Schritt als Drehvektor, Achse in xy, Winkel in z. Keine Faltkante, und der Winkel läuft über eine volle Drehung hinaus weiter. `holeBend` dreht damit direkt, das Ringleuchten nimmt π plus diesen Winkel. Die Hauptkarte bleibt unverändert.
- Fangzahl außerhalb der Karte -0,125 statt -1.
- `holeDiskFetch`: Texel eines anderen Scheibenbilds werden nicht gemittelt. Wo die vier Texel verschiedene Bilder zeigen oder die Rotverschiebung springt, wird jeder Texel für sich gemischt und die Farben gewichtet. Squeeze in solchen Quads aus Differenzen innerhalb eines Bilds statt aus `fwidth` über die Grenze.
- `diskShade2`: Rotverschiebung auf 0 bis 6 begrenzt, Gas mit negativem oder über 4 bis 6 explodierendem Faktor ausgeblendet; die helle Sichel davor bleibt. Kante an der ISCO ein Pixel weich.
- `dispFrag`: Wo eine Linse vor der Ebene das Bild verschiebt, wird Gas mit negativem Faktor der Hauptscheibe ausgelassen (die magenta Säume am vergrößerten Innenrand). Ohne Linse läuft der Code nicht.
- Im Lichtpass der Linse liest `holeSkyAt` nur noch den Kartenwert statt die ganze Ablenkung zu rechnen.

**Nachweis.** Vorher und nachher als vergrößerte Ausschnitte in `shots/naht/` (Doppelsystem bei 345 s, Schattenrand 8-fach, Kartenrand, Masse 0,7 mit Innenkante, Riss und Funken, hinter der Ebene, mit Jet, ohne Scheibe, Hochkant, Gargantua mit Masse 0,6, Zeitreihe 330 bis 360 s). Eingebaute Presets ohne Objekte pixelgleich zu `shots/objekte/referenz/` (alle fünf, beide Formate), Sternsystem und SciFi-Hafen pixelgleich zum alten Stand, Wurmloch allein 2 Pixel um 1 von 255, Maus-Linse allein pixelgleich: Hauptloch, Wurmloch und Maus-Linse haben den Fehler nicht, sie lesen keine kleine Karte. `--selftest` grün, `--edgecheck` mit zweitem Loch 1 von 255.

**Kosten** (`--bench-ab`, 3440 x 1440, je sechs Läufe im Wechsel mit dem alten Stand, Median): Doppelsystem +0,62 statt +0,67 ms, fest vor der Ebene +0,80 statt +0,82 ms, Masse 0,7 +2,19 statt +2,24 ms. Gleich teuer oder etwas billiger; der Rechner lief dabei unter Last, die Werte liegen höher als in der Sparrunde. Neuberechnen der Strahlen (`--bench-geo`) unverändert.

**Offen:** Ganz nah am Schatten bleibt die Innenkante bei großen Massen leicht wellig (Interpolation zwischen Texeln, kein Streifen mehr). Eine feinere Karte für große Massen würde das glätten, kostet aber Speicher über dem Budget von 8 MB.

### Jet mittig und glatt

**Stand 2026-10-14**, Branch `jet`. Anlass: Im Review wirkte der Jet pixelig und seitlich versetzt zum Loch.

**Messung** (2000 x 1000, `--quality 1` und `2`, mit und ohne `--debug 5`; Schatten aus `--debug 1`, also der Fangbereich, dessen Rand der Photonenring ist; Werkzeug `scripts/jet-achse.py`, Zahlen in `shots/jet/messung-*.txt`). Lage der Jetachse (Mitte der Halbwertsbreite) gegen die Mitte von Schatten und Photonenring:

| Szene | Neigung, Spin | vorher Fuß / Mitte / Fuß Gegenjet | nachher | erwartet aus 2 a sin(i) |
| --- | --- | --- | --- | --- |
| Dein Strudel | 66°, 0,9 | +27 / +31 / +25 px | -4 / +1 / -3 px | +30 px |
| Eisblau | 74°, 0,9 | +29 / +32 / +28 px | -4 / -1 / +2 px | +30 px |
| Gargantua | 84°, 0,6 | +18 / +22 / +16 px | -4 / -1 / +2 px | +19 px |
| M87* | 17°, 0,9 | +16 / +6 / +9 px | +9 / -5 / -6 px | +11 px |
| Draufsicht | 12°, 0,9 | +7 / +1 / +4 px | +5 / -7 / -4 px | +6 px |
| Sternsystem 3440 x 1440 | 66°, 0,9 | +41 / +46 / +41 px | -4 / +1 / 0 px | +43 px |

Der Schatten selbst liegt 0,5 bis 3,5 px neben der Lochposition. Die Zahlen sind bei Ausgewogen und Hoch gleich und hängen nicht von der Lochposition ab (drei Positionen geprüft). Bei M87* und Draufsicht sieht man den Jet fast von vorn, die Achse ist dort ein breiter Fleck, die Messung streut um einige Pixel.

**Ursache: Physik, kein Rasterfehler.** Ein halbes Texel in der halben Karte, im kubischen Hochrechnen oder ein falscher Bezugsrahmen hätte sich mit Stufe oder Position geändert. Tat es nicht. Der Schatten eines drehenden Lochs liegt um etwa 2 a sin(i) neben der projizierten Drehachse. `traceRay` verschiebt das Bild darum so, dass der Schatten auf der Lochposition landet. Der Jet lief aber korrekt auf der Drehachse, also 2 a sin(i) daneben: bei Spin 0,9 und 66° 1,64 M, 30 px auf 2000 x 1000 und 43 px auf 3440 x 1440. Dazu kam das Wackeln der Achse schon am Fuß (bis 0,18 Jetbreiten zur Seite, oben und unten verschieden), das den Fuß schief wirken ließ. Der Fuß sitzt auf der Achse, nicht am Innenrand der Scheibe.

**Fix** (`Shaders.swift`, `ObjectSystem.swift`, `Lenses.swift`, `ObjectShaders.swift`, `LensShaders.swift`):

- `ObjectSystem.shadowCentre` rechnet die waagerechte Mitte der Schattenkontur aus der kritischen Kurve von Kerr (linker und rechter Rand, 2000 Stützstellen, einmal pro Bild auf der CPU). Bei 0,9 und 66° sind das 1,84 M statt der 1,64 M der Kameraverschiebung. Die übrigen 3 px sind der Rest, um den der Schatten neben der Lochposition liegt.
- `jetSegment` verschiebt die Jetröhre um diesen Wert nach links im Bild (`jet3.z`, in +y der Welt), mit der Tiefe skaliert (`jet3.w = cos(i) / r0`). So bleibt die Achse eine senkrechte Linie durch die Mitte von Schatten und Photonenring, auch weit oben. Das zweite Loch bekommt dieselbe Verschiebung (`shots/jet/zweites-loch-vorher-nachher.png`).
- Das Wackeln setzt erst zwischen `base` und dem Sechsfachen davon ein. Jet und Gegenjet verlassen das Loch auf derselben Linie.
- Hinter dem Loch vergrößert die Linse den seitlichen Abstand der Röhre. Mit voller Verschiebung lag der Fuß des Gegenjets 14 px (2000 x 1000) bis 18 px (3440 x 1440) links der Mitte. Der Gegenjet bekommt deshalb am Fuß zwei Drittel der Verschiebung, ab dem Vierfachen von `base` die volle.
- Licht, das erst nach einem engen Umlauf um die Photonenbahnen in die Röhre trifft (der Strahl war schon unter 3,6 bis 5,6 M und läuft wieder nach außen), wird ausgeblendet. Diese Bilder sind Haarlinien, die keine Karte auflöst: Vorher lag am Fuß ein gepunkteter Bogen, beim Gegenjet mit schwarzen und hellen Funken. Mit verschobener Röhre wäre der Bogen nur auf einer Seite des Schattens gelegen. Der breite Linsenschein des Gegenjets um den Schatten (M87*) bleibt.
- Die Lage quer zum Jet für Filamente (`jetSide`) misst ab der neuen Achse statt ab der Lochposition (`jetP.w`).

**Physik-Hinweis.** Der Jet steht damit nicht mehr exakt auf der Drehachse, sondern 0,5 bis 2 M daneben, genau so weit, wie der Kerr-Schatten zur Seite rückt. Physikalisch richtig wäre der Versatz, er liest sich aber als Fehler, weil das Auge den Jet am Schatten misst. Der Gegenjet hinter dem Loch wird gelinst, sein Fuß ist darum mit einem Faktor nachgestellt (siehe oben). Das ist eine Annäherung für Neigungen um 60 bis 85°; bei M87* (17°) liegt der gelinste Gegenjet weiter 6 bis 11 px links. Der sichtbare dunkle Fleck ist bei 66° um etwa 20 px nach rechts verschoben, weil das innere Scheibenbild links in den Schatten ragt. Bezug ist deshalb die Kontur von Schatten und Photonenring, nicht der dunkle Fleck.

**Pixelig: Ursache.** Die Filamente lasen das Rauschen mit `lateral * 14`. Die feinste Oktave des Rauschens war damit 2 bis 3 px breit (S / 504): Knapp an der Nyquistgrenze, das ergab pixelbreite senkrechte Spalten und mit den Scheibenbändern Blöcke, bei jeder Stufe gleich. Karte, Lage in 16 Bit und kubisches Hochrechnen waren nicht schuld; ihr Ergebnis (`--debug 3`) ist glatt. Dazu schnitt `jetFloor` das Jetlicht hart ab: Auf dunklem Himmel stand am Rand des schwachen Scheins eine Kante von etwa 4 von 255.

**Pixelig: Fix.** Filamente mit `lateral * 4`, feinste Oktave etwa S / 144 (10 px bei 1440 px Höhe), die groben Streifen bleiben. Jetlicht steigt per `smoothstep` von der Schwelle bis zum Vierfachen an, statt zu springen. Die Haarlinien am Fuß sind über den Umlauf-Filter oben weg.

**Nachweis** in `shots/jet/`: `*-mitte-vorher-nachher.png` (Gesamtbild und nur Jet, grüne Linie Mitte von Schatten und Photonenring, rote Lochposition), `*-crops-ausgewogen.png` und `*-crops-hoch.png` (Fuß, Mitte, Spitze, Gegenjet als 1:1-Ausschnitte, zweifach ohne Glättung vergrößert) für den Jet der Galerie und das Sternsystem.

**Prüfungen.** Die fünf Presets ohne Objekte sind pixelgleich zu `shots/objekte/referenz/` (alle zehn Bilder 0 Pixel). Keines davon hat einen Jet. `--selftest` grün. Kosten mit `--bench-ab`, 3440 x 1440, vier Runden alt und neu im Wechsel, Aufpreis der Objekte gegen dasselbe Bild ohne Objekte (`shots/jet/kosten-bench-ab.txt`). Sternsystem Ausgewogen alt +0,20 / +0,45 / +0,51 / +0,36 ms, neu -0,01 / +0,47 / +0,50 / +0,43 ms, Median +0,40 gegen +0,45 ms. Hoch alt +0,33 / +0,57 / +0,61 / +0,44 ms, neu +0,40 / +0,50 / +0,56 / +0,47 ms, Median +0,51 gegen +0,48 ms. M87* mit Standard-Jet Ausgewogen Median +0,08 gegen +0,06 ms. Der Unterschied liegt zwischen -0,03 und +0,05 ms und damit in der Streuung zwischen zwei Runden (bis 0,5 ms); pro Pixel kommen nur zwei `smoothstep` dazu. Neuberechnen der Strahlen (`--bench-geo`) +9 bis +13 % mit Objekten, wie vorher (+10 bis +11 %).

**Offen.** Ein kurzer, weicher Rest des Bogens rechts oben am Fuß bleibt bei 66° sichtbar, nur im Bild „nur Jet“. Live und auf dem Notebook-Schirm nicht angesehen, Look-Freigabe durch den Nutzer.

### Planeten nahe am Loch

**Stand 2026-10-13: behoben**, Branch `planet-look`.

**Befund.** Ein Planet auf enger Bahn (etwa 9 bis 12 M) sah aus wie eine Seifenblase: Man sah die Scheibe durch ihn hindurch, dazu ein heller blauer Rand. Liegt die Bahn in der Scheibenebene, schnitt eine gerade waagrechte Kante den Planeten: oben fest, unten durchsichtig. Der Fehler war älter als die Arbeit an der Bewegung. Nachgestellt mit `--add planet:earth:mode=orbit,radius=9,incl=30,size=1.5 --series 0,20,40,60`.

**Ursache.** Drei Dinge zusammen, alle in Weg L und im Licht der Körper. Additives Blending, die Linse und Gezeitennormalen waren es nicht, die Blauverschiebung auch nicht (Faktor 1,1 im Blau).

1. **Eine Tiefe für die ganze Kugel.** `bodyLayers` sortierte jeden Körper mit der Tiefe seines Mittelpunkts gegen die Scheibendurchgänge des Pixels. Schneidet die Scheibenebene den Planeten, kippte die Zuordnung entlang einer Bildschirmzeile. Das war die gerade Kante, auch bei fernen Planeten, die die Ebene kreuzen.
2. **Die Scheibe deckte Körper nur mit ihrem Himmels-Alpha.** Hinter einem Scheibendurchgang lag der Körper unter `e + (1 - a) * Körper`. Das Alpha der Scheibe ist bewusst klein, damit Sterne durch die Gasbahnen schimmern (innen oft 0,1 bis 0,4). Ein beleuchteter Planet ist viel heller als ein Stern und schien deshalb mit 60 bis 90 % durch das hellste Gas: der Glaskörper.
3. **Licht nur aus Richtung Loch.** Die Scheibe wirkte als Lampe im Mittelpunkt. Ein Körper vor dem Loch zeigte uns seine Nachtseite, schwarz, und nur der Rand leuchtete im Gegenlicht. Mit dem fünffachen Licht nahe am Loch (Abstand und Doppler) wurden Atmosphärenrand und Dunst zu einem dicken blauen Ring.

**Fix.**

- `bodyLayers` (`BodyShaders.swift`): Runde Körper (Planeten, Monde, Felsen, nahe Sterne) bekommen ihren Radius in M (`BodyRef.ext.w`). Liegt ein Scheibendurchgang näher als der Radius an ihrer Mitte, zählt pro Pixel die Vorderseite der Kugel, und der Übergang ist über ein Fünftel des Radius weich. Die Ebene schneidet den Planeten jetzt entlang einer gekrümmten, weichen Linie. Sonst und für Schiffe, Kometen und feste Körper unverändert.
- `dispFrag` (`Shaders.swift`): Nach beiden Scheibendurchgängen wird vom Licht der Körper hinter dem Gas der Anteil abgezogen, den dichtes Gas verdeckt (`bodyHidden`): im inneren Teil der Scheibe (bis 0,25 des Außenradius, weich bis 0,4) ab Alpha 0,25 ganz, bei ganz dünnem Gas nichts. Die äußere Scheibe bleibt bei `1 - a`. Die Schritte davor sind unverändert. Ein erster Versuch mit umgebauter Reihenfolge kostete auch ohne Körper etwa 0,1 ms und wich in einem Pixel von den Presets ab.
- `BodyRenderer.swift`: Innerhalb der halben Scheibe (weich ab einem Viertel) kommt ein weiches Fülllicht aus der Scheibe dazu, 10 % des Scheibenlichts, so ist die Seite weg vom Loch nicht schwarz. Atmosphärenrand und Dunst wachsen dort oberhalb des Lichts eines fernen Planeten nur noch mit 15 %. Planeten ohne Atmosphäre (Gestein, Eis) haben keinen Rand, wie vorher. Doppler und Rotverschiebung durch Schwerkraft unverändert.

**Nachweis** in `shots/planet/`, jeweils oben vorher, unten nachher: `nah-zeitreihe.png` (die nachgestellte Szene), `nah-t60-zoom.png` und `nah-t0-zoom.png` (dreifach), `bahn-r12.png` (Bahn in der Ebene), `typ-*.png` (alle zehn Planetentypen nahe am Loch), `mond-*.png` (alle fünf Monde an einem nahen Planeten), `fern.png` und `fern-schnitt.png` (ferne Planeten bei 30, 40 und 66 M), `sternsystem.png`, `katalog-planeten.png`, `katalog-monde.png`.

- Die fünf Presets ohne Objekte sind pixelgleich zu `shots/objekte/referenz/` (beide Formate, `--top 24 --bottom 70 --time 20`).
- Sternsystem (beide Formate) und die Kataloge der Planeten und Monde sind pixelgleich zum alten Stand. SciFi-Hafen weicht in 98 Pixeln um bis zu 16 von 255 ab: ein schwaches Bild hinter dem inneren Gas ist jetzt verdeckt.
- Ferne Planeten ändern sich nur, wo sie die Scheibenebene kreuzen: Dort ist die gerade Kante jetzt gekrümmt und weich (`fern-schnitt.png`).

**Kosten** (`--bench-ab`, 3440 x 1440, im Wechsel mit dem alten Stand, Reihenfolge alt, neu, neu, alt, Median von je sechs Läufen). Sternsystem, zwei Messreihen: alt +0,376 und +0,367 ms, neu +0,378 und +0,385 ms, also 0 bis +0,02 ms; einzelne Läufe streuen um ±0,03 ms. Strudel mit einem Planeten bei 9 M: alt und neu +0,03 ms. Das Bild ohne Objekte lag in einer Reihe um 0,03 ms höher (1,65 statt 1,62 ms, Strudel), in den anderen gleich; das liegt an der Grenze dessen, was der Benchmark trennt. Der Rechner lief nicht ruhig, ein Lauf brach ohne Ausgabe ab und ließ sich nicht wiederholen.

**Sichtbar anders als vorher.** Ein Planet unter der Scheibenebene hinter dem inneren Gas ist jetzt verdeckt statt durchscheinend, er taucht wirklich hinter die Scheibe. Das betrifft auch Einstein-Bögen eines solchen Planeten, wenn das Gas davor dicht ist. Ein Planet auf einer Bahn genau in der Ebene steckt zur Hälfte in der Scheibe.

**Offen.**

- Bei starker Gezeitenstreckung rechnet die Tiefe pro Pixel mit der ungestreckten Kugel. Am gestreckten Ende ist die Schnittlinie deshalb nur ungefähr richtig.
- Das Fülllicht ist ein gleichmäßiges Umgebungslicht, keine Fläche mit Richtung. Look-Freigabe durch den Nutzer.

### Borg-Würfel und Galaxienpaar

**Stand 2026-10-14**, Branch `borg`.

**Befund.** Der Borg-Würfel war ein Quader mit Greeble-Muster im Shader: eine Textur ohne Tiefe, gerade Kanten, keine Lücken. Das Galaxienpaar zeigte immer zwei Spiralen.

**Borg-Würfel** (`BorgCube.swift`, Material `greeble` in `ShipShaders.swift`).

- Ein Kern als Würfel, darüber eine Schale aus Blöcken. Jede der sechs Seiten wird mit Seed binär geteilt, immer quer zur längeren Seite und außermittig. Die ersten beiden Schnitte lassen breite, tiefe Gräben (0,075 der halben Kantenlänge 2), die nächsten Kanäle von 0,04, danach Fugen von 0,022. Ein Blatt endet bei 0,16 bis 0,38 Seitenlänge oder nach acht Schnitten.
- Jedes Blatt bekommt eine eigene Höhe: meist nahe der Außenfläche, 17 % abgesenkt, 10 % erhöht, 7 % fehlen ganz. Durch fehlende Platten sieht man den Kern mit Trägern und Kästen. Auf größeren Blöcken liegen Rohre, kleine Kästen und Vertiefungen, dazu kleine grüne Lichter (Material Glühfarbe, folgt dem Regler).
- Blöcke an den Kanten werden zufällig zurückgeschnitten, an Ecken öfter ausgebrochen. Kanten und Ecken sind dadurch unregelmäßig, die Silhouette bleibt im Ganzen ein Würfel.
- Das grüne Leuchten aus den Kanälen steht im Netz: Der Kern und der Fuß jeder Wand tragen Emission im Vertex, sie fällt mit der Höhe über dem Kern ab. Der Shader nimmt davon die vierte Potenz, so bleibt das Leuchten unten in den Kanälen. Das alte Fugenleuchten aus dem Plattengitter ist weg, die Platten-Töne bleiben als feines Detail.
- 36 318 Dreiecke, gleicher Seed ergibt dasselbe Netz. Das Netz wird wie jedes Schiff einmal gebaut und im Cache von `ShipCatalog` gehalten.

**Galaxienpaar** (`ObjectCatalog.swift`, `ObjectSystem.packGalaxy`, `bakeGalaxy` in `ObjectShaders.swift`).

- Zwei neue Auswahlen „Galaxie A“ und „Galaxie B“ mit Spirale, Balkenspirale, Elliptisch, Linsenförmig (S0), Irregulär und Ringgalaxie. Sie gehen als Untertyp-Codes in `GalBake.d.y` und `d.z`. `galDisk` und `galRender` nehmen den Typ jetzt als Argument, die Mitglieder nutzen dieselben Modelle wie die einzelnen Galaxien. Eine Balkenspirale im Paar hat einen festen Balken von 0,7, eine elliptische eine feste Abplattung.
- Brücke und Schweife bleiben. Scheiben (Spirale, Balken, Ring) ziehen lange dünne Schweife, eine elliptische nur einen breiten, kurzen Strom alter Sterne, dazu schwache Schalen auf wechselnden Seiten. Eine linsenförmige hat einen glatten, rötlichen Schweif, eine irreguläre einen blauen, knotigen.
- Standard bleibt Spirale und Spirale. Fehlen die Schlüssel in einer alten Datei, gilt der Katalog-Standard 0. Das Bild ist dann pixelgleich zum alten Stand, auch der Atlas-Schlüssel ändert sich nicht.

**Nachweis** in `shots/borg/`: `borg-*-vorher.jpg` und `borg-*-nachher.jpg` (Dreiviertel, frontal, von unten, nah, mittel und klein am Rand), `paar-vorher.jpg`, `paar-nachher.jpg` und drei neue Paare. Selbsttests: Borg-Netz deterministisch mit 8000 bis 40 000 Dreiecken, Galaxienpaar aus alter Datei backt wie bisher.

**Kosten** (`--bench-ab`, 3440 x 1440, alter und neuer Stand im Wechsel). SciFi-Hafen ohne Borg: alt +0,520 und +0,624 ms, neu +0,522 und +0,544 ms, also im Rauschen. Strudel mit einem großen Borg-Würfel (fest im Bild, Größe 360), ruhige Reihe: alt +0,090 und +0,126 ms, neu +0,094 und +0,094 ms. Eine zweite Reihe lief auf einem belasteten Rechner (ohne Objekte 4 statt 1,9 ms) und streute zwischen -0,17 und +0,07 ms. Das Galaxienpaar wird einmal in den Atlas gebacken und kostet pro Bild nichts mehr. Der Würfel baut sein Netz einmal und hält es im Cache. Die fünf Presets ohne Objekte sind pixelgleich zu `shots/objekte/referenz/`.

**Offen.**

- Die Auswahl auf der Seite Objekte nutzt den bestehenden Picker der Katalog-Parameter. Im Fenster angesehen ist sie nicht.
- Klein am Rand (rund 60 Pixel) mischt die Kantenglättung die Lichter zu grünen Punkten auf dunklem Grund. Ob das als Borg-Würfel reicht, braucht ein Urteil am echten Bildschirm.

## 10. Offene Fragen an den Nutzer

1. **Schiffe: Rasterung oder SDF?**
   1. Dreiecksnetze aus Bausteinen gerastert, gleicher Weg wie eigene OBJ/USDZ-Modelle, billig und scharf.
   2. Echtes SDF-Raymarching wie vorgeschlagen, weichere Übergänge, etwa zehnmal teurer pro Schiffspixel.
   Empfehlung: 1.
2. **Reihenfolge der Stufen 3 und 4?**
   1. Erst Raumschiffe und Stationen, dann zweites Loch und Wurmloch.
   2. Erst zweites Loch und Wurmloch, dann Schiffe.
   Empfehlung: 1, weil die Schiffe auf dem Atlas aus Stufe 2 aufsetzen und die Linsenliste den Kern von `dispFrag` umbaut, das geht besser zuletzt.
3. **Objekte über Monitorgrenzen?**
   1. Jeder Monitor hat seine eigene Szene im Preset, nichts wandert hinüber.
   2. Zusätzlich eine monitorübergreifende Ebene, auf der Randobjekte von einem Schirm zum nächsten fliegen.
   Empfehlung: 1 jetzt, 2 als spätere Erweiterung, weil sie eine zweite Szenen-Ebene in `AppSettings` braucht.

**Entschieden am 2026-10-11 (Projektleitung):** Frage 1: Rasterung aus Bausteinen (Option 1). Das erfüllt die Wahl des Nutzers „im Code nachgeformt plus Import“. Frage 2: erst Schiffe, dann zweites Loch und Wurmloch (Option 1). Frage 3: jede Szene bleibt auf ihrem Monitor (Option 1). Das Fliegen über Monitorgrenzen wird dem Nutzer später als Erweiterung angeboten.

## 11. Rechtlicher Hinweis (getrennt, ohne Einfluss auf den Plan)

Namen und Formen der Schiffe und Stationen aus Star Trek, Star Wars, Battlestar Galactica, Raumpatrouille Orion und den anderen Universen sind Marken oder Designs der Rechteinhaber. Für die private Nutzung auf dem eigenen Mac spielt das keine Rolle, bei einer Weitergabe der App könnte es eine Rolle spielen.

## 12. Schritt 1 vor 1.0

Vier kleine Funktionen, alle ohne Eingriff in den Renderer außer dem Zähler und der Qualitätsstufe.

**Pause bei Sperre und Schlaf.** `SystemWatch` (`RunPolicy.swift`) sammelt Gründe: `screenIsLocked`, Bildschirmschoner (`screensaver.didstart`), `screensDidSleep`, `willSleep` und `sessionDidResignActive`. Ein Grund genügt zum Anhalten, zum Starten müssen alle weg sein. Das Aufwachen wartet 0,35 s, damit ein Aufwachen mit sofortigem Sperrbildschirm kein Bild dazwischen zeichnet. Angehalten wird in `Wallpaper.setSuspended`: alle Ansichten pausieren, am Bild und am Renderer ändert sich nichts. Die Strahlenkarten bleiben, das erste Bild danach ist ein gewöhnliches, die Uhr springt nicht (`resumeClock`). Änderungen während der Pause (Look, Layout) zeichnen erst beim Aufwachen. Außerdem baut die App die Fenster bei einer Bildschirm-Mitteilung nur noch neu, wenn sich Rahmen oder Skalierung eines Schirms geändert haben.

**Hitze.** `RunPolicy.plan` ist eine reine Funktion aus Einstellungen, Energiemodus, Hitze, Bewegung reduzieren und Pausengründen. `serious`: halbe Bildrate (mindestens 5) und `RenderQuality.lowered(by: 1)`, nie unter Akku sparen. `critical`: Standbild. Die Qualitätsstufe bleibt ab `serious` gesenkt, auch bei `critical` und in der Pause, damit steigende oder fallende Hitze nur einmal neu rechnet. Schalter: Energie > Bei Hitze drosseln, Standard an.

**Bewegung reduzieren.** Ist `accessibilityDisplayShouldReduceMotion` an und der Schalter Allgemein > Bewegung reduzieren beachten (Standard an) gesetzt, ist die wirksame Animationsstufe Aus. Die gewählte Stufe bleibt gespeichert. Ein Hinweis unter der Stufe erscheint, solange das System sie erzwingt. `accessibilityDisplayOptionsDidChangeNotification` wirkt sofort.

**Willkommensfenster.** `Store.freshInstall` ist wahr, wenn beim Start keine settings.json existierte. Nur dann, und nur einmal (`welcomeShown`), öffnet sich das Fenster. Eine alte Datei ohne den Schlüssel zählt nie als frisch. Die Vorschaubilder rendert derselbe Renderer in Stufe Akku sparen, 240 x 150 Pixel, nacheinander im Hauptthread. Das Anmeldeobjekt wird beim Schließen angemeldet, wenn der Haken noch gesetzt ist, nicht bei einem Lauf mit `BH_SETTINGS`. `BH_FORCE_WELCOME=1` erzwingt das Fenster.

**Messung** (MacBook Air M4, eingebauter Schirm 1920 x 1242, 30 Bilder pro Sekunde, Sternsystem aus einer Kopie der Einstellungen, `BH_DEBUG=1`, Zustand per Test-Mitteilung gewechselt):

| Zustand | Bilder in 5 s | GPU pro Bild |
|---|---|---|
| läuft | 150 | 2,7 bis 3,2 ms |
| gesperrt | 0, 0, 0 | keine Bilder, 0 ms |
| danach entsperrt | 150 | 3,1 ms, 0 Strahlen-Durchläufe |
| Hitze `serious` | 75 | 3,8 bis 4,0 ms, Karte 960 x 621 statt 1152 x 745, ein Durchlauf beim Wechsel |
| Hitze `critical` | 0, 0 | keine Bilder |
| Hitze vorbei | 150 | 2,7 bis 2,9 ms, ein Durchlauf beim Zurückstellen |
| Bewegung reduzieren an | 0 | keine Bilder |

Der ganze Lauf von rund 110 s brauchte 2,95 s CPU-Zeit. Beim Wechsel zurück zum Laufen blieb die Strahlenkarte stehen (0 Durchläufe), das erste Bild kostete 3,1 ms.

**Offen.** Echter Bildschirmschlaf und echte Sperre ließen sich nicht auslösen, ohne die Sitzung des Nutzers zu sperren. Die Mitteilungen `screenIsLocked` und die NSWorkspace-Namen sind nach Apples Dokumentation verdrahtet, aber nur über die Test-Mitteilung im Lauf geprüft. Das Standbild als echtes Hintergrundbild (`Stills`) wird weiter nach Zeitplan erneuert, auch während der Pause.

