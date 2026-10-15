#!/usr/bin/env python3
"""Schreibt index.html (Englisch) und de/index.html (Deutsch) aus einer Vorlage.

Quelle der Texte ist texte.md; hier stehen sie so, wie sie auf der Seite erscheinen.
Aufruf aus dem Repo:  python3 website/werkzeuge/build.py
Kein Server, keine Abhängigkeiten. Die erzeugten Dateien werden eingecheckt.
"""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = "https://digitaliq.github.io/blackhole-wallpaper/"
RELEASES = "https://github.com/DigitalIQ/blackhole-wallpaper/releases/latest"
REPO = "https://github.com/DigitalIQ/blackhole-wallpaper"
# Homebrew 7 loads casks from other taps only after brew trust.
BREW_LINES = ["brew tap digitaliq/tap", "brew trust --tap digitaliq/tap", "brew install --cask blackhole-wallpaper"]
BREW = " && ".join(BREW_LINES)

PRESETS = ["swirl", "gargantua", "m87", "topview", "iceblue", "starsystem", "scifi"]

T = {
  "en": {
    "lang": "en", "path": "", "other_path": "de/", "other_label": "Deutsch", "other_lang": "de",
    "title": "Black Hole Wallpaper: a live black hole for your Mac",
    "desc": "Free, open source animated wallpaper for macOS. A spinning black hole with real light bending, computed in Metal. Download it or install with Homebrew.",
    "og_alt": "Black Hole Wallpaper. Real light bending, live on your Mac desktop.",
    "skip": "Skip to content",
    "name": "Black Hole Wallpaper",
    "doc": "macOS 15+ / MIT / Metal",
    "nav": [("physics", "Physics"), ("presets", "Presets"), ("objects", "Objects"), ("film", "Film"), ("install", "Install")],
    "nav_label": "Sections",
    "h1": "Your desktop, bent by a black hole.",
    "lede": "Black Hole Wallpaper is a live wallpaper for macOS. Every pixel follows a ray of light around a spinning black hole, computed in Metal on your Mac.",
    "download": "Download for macOS",
    "copy": "Copy", "copied": "Copied",
    "fine": "Free and open source, MIT license. macOS 15 or later.",
    "still_alt": "Still from the app, preset Gargantua: a black hole with a thin glowing disk, the far side of the disk bent up over the shadow.",
    "live_label": "A black hole rendered live in your browser: a thin glowing disk, the far side of the disk bent up over the shadow.",
    "fig1": "Live in your browser: a lighter version of the app's ray tracer, preset Gargantua. Without WebGL or with reduced motion you see a still from the app.",
    "hint": "Move your pointer", "hint_touch": "Drag to tilt",
    "anno": ["Photon ring", "Far side of the disk, bent up", "Shadow", "Brighter side, moving toward you"],
    "spec": [("Light", "Ray traced, Kerr metric"), ("GPU, all moving *", "1.7 to 2.6 ms per frame"), ("GPU, edges only *", "0.12 to 0.14 ms per frame"), ("Presets", "7, plus your own")],
    "spec_note": "* Measured on a MacBook Air M4 at 3440 x 1440.",
    "phys_h": "Real light bending, not a video loop",
    "phys_p": [
      "Most black hole wallpapers are videos. This one is computed. The app traces a ray of light for every pixel through the spacetime of a spinning (Kerr) black hole, step by step. That ray tracing produces the shadow, the thin photon ring, the far side of the disk bent up over the top, and stars smeared into arcs near the Einstein ring.",
      "The disk starts at the innermost stable orbit and turns at Kepler speed. The side moving toward you is brighter and bluer, from Doppler beaming and gravitational redshift.",
    ],
    "truth": [("Computed", "Light paths, shadow, photon ring, the bent far side of the disk, Doppler brightening, lensed stars and objects."), ("Artistic", "The colors. A real disk would glow white to orange. The palettes are a choice, and you can change them.")],
    "figs": [("2", "fig-close", "Close to the shadow: the photon ring and the disk bent around it.", "Close-up from the app: the black shadow, a thin bright ring at its edge, the glowing disk wrapped around it in orange and magenta."),
             ("3", "fig-ring", "A galaxy right behind the hole becomes a closed Einstein ring.", "A thin white ring around the black hole and its magenta disk: the image of a galaxy behind it."),
             ("4", "fig-planet", "A ringed planet behind the hole, bent into a ring with a counter image.", "A ringed planet stretched into arcs around the black hole, preset Gargantua.")],
    "pre_h": "Seven presets, then make your own",
    "pre_p": "Pick one per display or one for all. Duplicate any preset and change the hole, disk, colors, nebula, stars and edges.",
    "presets": {
      "swirl": ("Swirl", "Magenta and orange disk in a violet nebula. The default."),
      "gargantua": ("Gargantua", "Warm, thin disk seen from the side, like the film."),
      "m87": ("M87* as photographed", "Seen from almost straight on, like the first photo of a black hole."),
      "topview": ("Top View", "The disk from above."),
      "iceblue": ("Ice Blue", "Cold blue and violet."),
      "starsystem": ("Star System", "Galaxies, a pulsar, an asteroid belt, a ringed planet with a moon and a comet around the hole."),
      "scifi": ("Sci-Fi Harbor", "A wormhole next to the hole, a space station, a stargate and ships from four universes."),
    },
    "preset_alt": "Still from the app, preset {name}.",
    "obj_h": "Add things. The hole bends them.",
    "obj_p": "Put a galaxy right behind the hole and it becomes a closed Einstein ring. Slightly off, it splits into two arcs. A planet on an orbit dips behind the disk and comes back bent. Comet tails point away from the hole.",
    "kinds": ["Galaxies, from spirals to quasars", "Distant and nearby stars, pulsars and magnetars", "A relativistic jet along the spin axis", "Planets with rings, clouds and storms, and their moons", "Asteroids, belts, comets and meteors", "Ships and stations from many science fiction worlds, plus real spacecraft like Hubble and James Webb", "A second black hole and a wormhole"],
    "obj_main": ("6", "Sci-Fi Harbor on an ultrawide display: ships and a station on their orbits around the hole.", "Still from the app: the black hole with its magenta disk, a star destroyer, a starship and a space station around it."),
    "obj_small": [("Wormhole: another sky seen through it", "A sphere showing a different, cooler sky next to the black hole.", "obj-wormhole"),
                  ("A second black hole with its own disk and jet", "A smaller black hole with a disk and a jet next to the main one.", "obj-second"),
                  ("An Earth-like planet lit by the disk", "An Earth-like planet with clouds next to the black hole.", "obj-planet")],
    "motion_h": "Motion follows physics", "motion": ['Bodies run on Kepler orbits. Fast visitors swing by or plunge in.', 'Tides stretch them near the hole. Their light shifts red or blue.', 'Moons stay locked to their planet. Asteroids tumble. Meteors slow down.', 'Ships accelerate and bank. A second hole has real mass.', 'A Time-lapse slider speeds it all up.'],
    "obj_models": "Bring your own 3D model as OBJ, USDZ, USD, PLY, STL, glTF or GLB.",
    "obj_note": "Ships are simple shapes built in the app as a fan tribute. Not affiliated with any studio or franchise.",
    "mac_h": "Made to sit behind your work",
    "mac_facts": ["Glowing bands run along the menu bar and the Dock.", "Three animation levels: everything moves, only the edges move, or a still image.", "It pauses in Low Power Mode and when windows cover the desktop.", "Pick a preset per display. A screen saver and a still for the lock screen come with it.", "Four quality levels: Battery Saver, Balanced, High and Ultra. One level for the power adapter, one for battery, and six areas can be set separately. The jet is smooth already at Balanced.", "The app is in English and German. It follows the system language, or you choose on the General page."],
    "chart_cap": "GPU time per frame, MacBook Air M4 at 3440 x 1440. The app runs at 30 frames per second by default.",
    "chart_all": "Everything moves", "chart_edges": "Only the edges",
    "chart_all_v": "1.7 to 2.6 ms", "chart_edges_v": "0.12 to 0.14 ms",
    "film_h": "26 seconds in motion",
    "film_p": "Rendered from the app, no sound.",
    "film_play": "Play film",
    "film_fallback": "Your browser cannot play this video.",
    "film_dl": "Download the MP4",
    "film_cap": "Every shot is rendered by the app itself.",
    "inst_h": "Install",
    "inst_p": "Two ways. Both get you the same app.",
    "dl_h": "Download",
    "dl_steps": ["Download the latest release from GitHub.", "Move the app to Applications."],
    "dl_btn": "Download latest release",
    "brew_h": "Homebrew",
    "brew_step": "Run this in Terminal:",
    "first": "The app is not notarized by Apple, so macOS blocks the first start. Open it once, then click Open Anyway in System Settings > Privacy & Security. Or run xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app in Terminal.",
    "after": "It lives in the menu bar. Open Settings from there, or launch the app again from Spotlight.",
    "faq_h": "Questions",
    "faq": [("Is it free?", "Yes. Free and open source under the MIT license."),
            ("Will it drain my battery?", "It pauses in Low Power Mode and when windows cover the desktop. With only the edges moving it needs less than a tenth of the GPU time. On battery you can pick a lighter quality level. Numbers are in the README."),
            ("Which Macs does it run on?", "macOS 15 or later."),
            ("Why does macOS warn me on first launch?", "The app is not notarized by Apple. Since macOS 15, right-click and Open no longer helps. Click Open Anyway in System Settings > Privacy & Security once, or remove the quarantine flag with xattr. Homebrew quarantines its download too."),
            ("Is the physics real?", "The light bending is: the app integrates light rays through Kerr spacetime. The colors are artistic. The README lists exactly what is real and what is approximated."),
            ("Can I use my own 3D models?", "Yes: OBJ, USDZ, USD, PLY, STL, glTF and GLB."),
            ('Which languages does the app speak?', 'English and German. It follows the system language, or you pick one on the General page.'),
            ("Does the app go online?", "Only for updates. It asks api.github.com at most once a day and loads updates from GitHub's download servers. You can switch the check off on the General page. No analytics."),
            ("Does this website track me?", "No. No cookies, no analytics, no requests to other servers.")],
    "foot_made": "Made by DigitalIQ", "foot_lic": "MIT license", "foot_src": "Source on GitHub",
  },
  "de": {
    "lang": "de", "path": "de/", "other_path": "../", "other_label": "English", "other_lang": "en",
    "title": "Schwarzes Loch: animierter Hintergrund für deinen Mac",
    "desc": "Freier, quelloffener Live-Hintergrund für macOS: ein drehendes Schwarzes Loch mit echter Lichtbiegung, gerechnet in Metal. Laden oder per Homebrew.",
    "og_alt": "Schwarzes Loch. Echte Lichtbiegung, live auf deinem Mac.",
    "skip": "Zum Inhalt springen",
    "name": "Schwarzes Loch",
    "doc": "ab macOS 15 / MIT / Metal",
    "nav": [("physics", "Physik"), ("presets", "Voreinstellungen"), ("objects", "Objekte"), ("film", "Film"), ("install", "Installieren")],
    "nav_label": "Abschnitte",
    "h1": "Dein Schreibtisch, gebogen von einem Schwarzen Loch.",
    "lede": "Schwarzes Loch ist ein animierter Hintergrund für macOS. Jeder Pixel folgt einem Lichtstrahl um ein drehendes Schwarzes Loch, gerechnet in Metal auf deinem Mac.",
    "download": "Für macOS laden",
    "copy": "Kopieren", "copied": "Kopiert",
    "fine": "Frei und quelloffen, MIT-Lizenz. Ab macOS 15.",
    "still_alt": "Standbild aus der App, Voreinstellung Gargantua: ein Schwarzes Loch mit dünner leuchtender Scheibe, deren Rückseite sich über den Schatten biegt.",
    "live_label": "Ein Schwarzes Loch, live im Browser gerechnet: dünne leuchtende Scheibe, die Rückseite über den Schatten gebogen.",
    "fig1": "Live in deinem Browser: eine leichtere Fassung des Lochs aus der App, Voreinstellung Gargantua. Ohne WebGL oder bei reduzierter Bewegung siehst du ein Standbild aus der App.",
    "hint": "Beweg die Maus", "hint_touch": "Ziehen zum Kippen",
    "anno": ["Photonenring", "Rückseite der Scheibe, nach oben gebogen", "Schatten", "Hellere Seite, kommt auf dich zu"],
    "spec": [("Licht", "Strahlen verfolgt, Kerr-Metrik"), ("GPU, alles bewegt *", "1,7 bis 2,6 ms pro Bild"), ("GPU, nur Ränder *", "0,12 bis 0,14 ms pro Bild"), ("Voreinstellungen", "7, dazu deine eigenen")],
    "spec_note": "* Gemessen auf einem MacBook Air M4 bei 3440 x 1440.",
    "phys_h": "Echte Lichtbiegung statt Videoschleife",
    "phys_p": [
      "Die meisten Schwarzes-Loch-Hintergründe sind Videos. Dieser wird gerechnet. Die App verfolgt für jeden Pixel einen Lichtstrahl durch die Raumzeit eines drehenden Schwarzen Lochs (Kerr), Schritt für Schritt. Daraus entstehen der Schatten, der dünne Photonenring, die Rückseite der Scheibe, die sich über den Schatten biegt, und Sterne, die sich nahe dem Einstein-Ring zu Bögen ziehen.",
      "Die Scheibe beginnt an der innersten stabilen Bahn und dreht sich nach Kepler. Die Seite, die auf dich zukommt, ist heller und blauer, durch Doppler-Effekt und Gravitations-Rotverschiebung.",
    ],
    "truth": [("Gerechnet", "Lichtwege, Schatten, Photonenring, die gebogene Rückseite der Scheibe, Doppler-Aufhellung, gebogene Sterne und Objekte."), ("Künstlerisch", "Die Farben. Eine echte Scheibe leuchtet weiß bis orange. Die Paletten sind eine Entscheidung, und du kannst sie ändern.")],
    "figs": [("2", "fig-close", "Nah am Schatten: der Photonenring und die Scheibe, die sich um ihn biegt.", "Nahaufnahme aus der App: der schwarze Schatten, an seinem Rand ein dünner heller Ring, darum die leuchtende Scheibe in Orange und Magenta."),
             ("3", "fig-ring", "Eine Galaxie genau hinter dem Loch wird zum geschlossenen Einstein-Ring.", "Ein dünner weißer Ring um das Schwarze Loch und seine magentafarbene Scheibe: das Bild einer Galaxie dahinter."),
             ("4", "fig-planet", "Ein Ringplanet hinter dem Loch, zum Ring gebogen, mit Gegenbild.", "Ein Ringplanet, zu Bögen um das Schwarze Loch gezogen, Voreinstellung Gargantua.")],
    "pre_h": "Sieben Voreinstellungen, dann deine eigene",
    "pre_p": "Wähl eine pro Bildschirm oder eine für alle. Dupliziere eine Voreinstellung und ändere Loch, Scheibe, Farben, Nebel, Sterne und Ränder.",
    "presets": {
      "swirl": ("Strudel", "Scheibe in Magenta und Orange in einem violetten Nebel. Der Standard."),
      "gargantua": ("Gargantua", "Warme, dünne Scheibe von der Seite, wie im Film."),
      "m87": ("M87* wie auf dem Foto", "Fast von vorn, wie das erste Foto eines Schwarzen Lochs."),
      "topview": ("Draufsicht", "Die Scheibe von oben."),
      "iceblue": ("Eisblau", "Kaltes Blau und Violett."),
      "starsystem": ("Sternsystem", "Galaxien, ein Pulsar, ein Asteroidengürtel, ein Ringplanet mit Mond und ein Komet ums Loch."),
      "scifi": ("SciFi-Hafen", "Ein Wurmloch neben dem Loch, eine Raumstation, ein Sternentor und Schiffe aus vier Universen."),
    },
    "preset_alt": "Standbild aus der App, Voreinstellung {name}.",
    "obj_h": "Stell etwas dazu. Das Loch biegt es.",
    "obj_p": "Steht eine Galaxie genau hinter dem Loch, wird sie zum geschlossenen Einstein-Ring. Knapp daneben teilt sie sich in zwei Bögen. Ein Planet auf seiner Bahn taucht hinter der Scheibe ab und kommt gebogen wieder hervor. Kometenschweife zeigen vom Loch weg.",
    "kinds": ["Galaxien, von der Spirale bis zum Quasar", "Ferne und nahe Sterne, Pulsare und Magnetare", "Ein Jet entlang der Drehachse", "Planeten mit Ringen, Wolken und Stürmen, dazu ihre Monde", "Asteroiden, Gürtel, Kometen und Meteore", "Schiffe und Stationen aus vielen Science-Fiction-Welten, dazu echte Raumfahrt wie Hubble und James Webb", "Ein zweites Schwarzes Loch und ein Wurmloch"],
    "obj_main": ("6", "SciFi-Hafen auf einem Ultrawide-Schirm: Schiffe und eine Station auf ihren Bahnen ums Loch.", "Standbild aus der App: das Schwarze Loch mit magentafarbener Scheibe, darum ein Sternzerstörer, ein Raumschiff und eine Raumstation."),
    "obj_small": [("Wurmloch: ein anderer Himmel darin", "Eine Kugel neben dem Schwarzen Loch, in der ein anderer, kühlerer Himmel zu sehen ist.", "obj-wormhole"),
                  ("Ein zweites Schwarzes Loch mit Scheibe und Jet", "Ein kleineres Schwarzes Loch mit Scheibe und Jet neben dem Hauptloch.", "obj-second"),
                  ("Ein erdähnlicher Planet im Licht der Scheibe", "Ein erdähnlicher Planet mit Wolken neben dem Schwarzen Loch.", "obj-planet")],
    "motion_h": "Die Bewegung folgt der Physik", "motion": ['Körper laufen auf Kepler-Bahnen. Schnelle Besucher schwingen vorbei oder stürzen hinein.', 'Gezeiten ziehen sie nahe am Loch in die Länge. Ihr Licht wird röter oder blauer.', 'Monde bleiben an ihren Planeten gebunden. Asteroiden taumeln. Meteore werden langsamer.', 'Schiffe beschleunigen und gehen in die Kurve. Ein zweites Loch hat echte Masse.', 'Ein Zeitraffer-Regler beschleunigt alles.'],
    "obj_models": "Bring dein eigenes 3D-Modell mit, als OBJ, USDZ, USD, PLY, STL, glTF oder GLB.",
    "obj_note": "Die Schiffe sind einfache Formen, in der App gebaut, als Hommage von Fans. Keine Verbindung zu einem Studio oder einer Marke.",
    "mac_h": "Gemacht, um hinter deiner Arbeit zu bleiben",
    "mac_facts": ["Leuchtende Bänder laufen an Menüleiste und Dock entlang.", "Drei Stufen: alles bewegt sich, nur die Ränder, oder ein Standbild.", "Im Energiesparmodus und bei verdecktem Schreibtisch hält es an.", "Wähl eine Voreinstellung pro Bildschirm. Ein Bildschirmschoner und ein Standbild für den Sperrbildschirm sind dabei.", "Vier Qualitätsstufen: Akku sparen, Ausgewogen, Hoch und Ultra. Eine Stufe fürs Netzteil, eine für den Akku, sechs Bereiche lassen sich einzeln einstellen. Der Jet ist schon bei Ausgewogen glatt.", "Die App gibt es auf Deutsch und Englisch. Sie folgt der Systemsprache, oder du wählst auf der Seite „Allgemein“."],
    "chart_cap": "GPU-Zeit pro Bild, MacBook Air M4 bei 3440 x 1440. Standard sind 30 Bilder pro Sekunde.",
    "chart_all": "Alles bewegt sich", "chart_edges": "Nur die Ränder",
    "chart_all_v": "1,7 bis 2,6 ms", "chart_edges_v": "0,12 bis 0,14 ms",
    "film_h": "26 Sekunden in Bewegung",
    "film_p": "Aus der App gerendert, ohne Ton.",
    "film_play": "Film abspielen",
    "film_fallback": "Dein Browser kann das Video nicht abspielen.",
    "film_dl": "MP4 herunterladen",
    "film_cap": "Jede Einstellung hat die App selbst gerendert.",
    "inst_h": "Installieren",
    "inst_p": "Zwei Wege, dieselbe App.",
    "dl_h": "Download",
    "dl_steps": ["Lade die neueste Version von GitHub.", "Leg die App in den Ordner Programme."],
    "dl_btn": "Neueste Version laden",
    "brew_h": "Homebrew",
    "brew_step": "Im Terminal ausführen:",
    "first": "Die App ist nicht von Apple notarisiert, deshalb blockiert macOS den ersten Start. Öffne sie einmal und klicke in Systemeinstellungen > Datenschutz & Sicherheit auf „Trotzdem öffnen“. Oder im Terminal: xattr -dr com.apple.quarantine /Applications/BlackHoleWallpaper.app",
    "after": "Sie sitzt in der Menüleiste. Dort öffnest du die Einstellungen, oder du startest die App noch einmal über Spotlight.",
    "faq_h": "Fragen",
    "faq": [("Kostet es etwas?", "Nein. Frei und quelloffen unter der MIT-Lizenz."),
            ("Zieht es meinen Akku leer?", "Im Energiesparmodus und bei verdecktem Schreibtisch hält es an. Wenn sich nur die Ränder bewegen, braucht es weniger als ein Zehntel der GPU-Zeit. Am Akku wählst du eine leichtere Qualitätsstufe. Die Messwerte stehen in der README."),
            ("Auf welchen Macs läuft es?", "Ab macOS 15."),
            ("Warum warnt macOS beim ersten Start?", "Die App ist nicht von Apple notarisiert. Seit macOS 15 hilft Rechtsklick und Öffnen nicht mehr. Klicke einmal in Systemeinstellungen > Datenschutz & Sicherheit auf „Trotzdem öffnen“ oder entferne die Quarantäne-Markierung mit xattr. Auch Homebrew stellt den Download unter Quarantäne."),
            ("Ist die Physik echt?", "Die Lichtbiegung ja: Die App rechnet Lichtstrahlen durch die Kerr-Raumzeit. Die Farben sind künstlerisch. Die README sagt genau, was echt ist und was genähert."),
            ("Kann ich eigene 3D-Modelle nutzen?", "Ja, als OBJ, USDZ, USD, PLY, STL, glTF und GLB."),
            ('Welche Sprachen kann die App?', 'Deutsch und Englisch. Sie folgt der Systemsprache, oder du wählst auf der Seite „Allgemein“.'),
            ("Geht die App ins Internet?", "Nur für Updates. Sie fragt höchstens einmal am Tag bei api.github.com nach und lädt Updates von den Download-Servern von GitHub. Die Prüfung schaltest du auf der Seite „Allgemein“ ab. Keine Statistik."),
            ("Trackt mich diese Seite?", "Nein. Keine Cookies, keine Statistik, keine Anfragen an andere Server.")],
    "foot_made": "Made by DigitalIQ", "foot_lic": "MIT-Lizenz", "foot_src": "Quellcode auf GitHub",
  },
}

e = html.escape
DL_ICON = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 3v11M5 9.5l5 5 5-5M3 17.5h14" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="square"/></svg>'
FACT_ICONS = [
  '<path d="M2 5h18M2 17h18" stroke="currentColor" stroke-width="2"/>',
  '<path d="M3 11h4l2-5 4 10 2-5h4" stroke="currentColor" stroke-width="2" fill="none"/>',
  '<path d="M7 4v14M15 4v14" stroke="currentColor" stroke-width="3"/>',
  '<rect x="2" y="4" width="18" height="11" stroke="currentColor" stroke-width="2" fill="none"/><path d="M8 19h6" stroke="currentColor" stroke-width="2"/>',
  '<path d="M4 18v-4M9 18v-8M14 18v-12M19 18V4" stroke="currentColor" stroke-width="3"/>',
  '<path d="M3 5h16M3 11h16M3 17h16" stroke="currentColor" stroke-width="2"/><path d="M8 3v4M14 9v4M7 15v4" stroke="currentColor" stroke-width="2"/>',
]


def picture(p, name, alt, w, h, lazy=True, prefix=""):
    lz = ' loading="lazy" decoding="async"' if lazy else ""
    return (f'<picture><source type="image/webp" srcset="{prefix}assets/img/{name}.webp">'
            f'<img src="{prefix}assets/img/{name}.jpg" alt="{e(alt)}" width="{w}" height="{h}"{lz}></picture>')


def copy_btn(t):
    return (f'<button class="copy-cmd" type="button" data-copy="{html.escape(BREW)}" data-label="{t["copy"]}" data-done="{t["copied"]}">'
            f'<code>{"<br>".join(html.escape(l) for l in BREW_LINES)}</code><span class="k" aria-live="polite">{t["copy"]}</span></button>')


def page(key):
    t = T[key]
    pre = "" if key == "en" else "../"
    url = BASE + t["path"]
    other_url = BASE + ("de/" if key == "en" else "")
    ld = [{
        "@context": "https://schema.org", "@type": "SoftwareApplication",
        "name": "Black Hole Wallpaper", "alternateName": "Schwarzes Loch",
        "description": t["desc"], "url": url, "inLanguage": t["lang"],
        "applicationCategory": "DesktopEnhancementApplication", "operatingSystem": "macOS 15 or later",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "license": "https://opensource.org/licenses/MIT",
        "downloadUrl": RELEASES, "installUrl": RELEASES, "codeRepository": REPO,
        "image": BASE + "assets/img/og.jpg", "screenshot": BASE + "assets/img/preset-swirl.jpg",
        "author": {"@type": "Person", "name": "DigitalIQ", "url": "https://github.com/DigitalIQ"},
    }, {
        "@context": "https://schema.org", "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in t["faq"]],
    }]
    nav = "".join(f'<a href="#{i}">{e(l)}</a>' for i, l in t["nav"])
    a = t["anno"]
    spec = "".join(f'<div><dt class="label">{e(k)}</dt><dd class="num">{e(v)}</dd></div>' for k, v in t["spec"])
    phys_p = "".join(f"<p>{e(x)}</p>" for x in t["phys_p"])
    truth = "".join(f'<div><dt class="label{" art" if i else ""}">{e(k)}</dt><dd>{e(v)}</dd></div>' for i, (k, v) in enumerate(t["truth"]))
    dims = {"fig-close": (1000, 700), "fig-ring": (1000, 769), "fig-planet": (1000, 769)}
    figs = "".join(f'<figure class="fig">{picture(None, n, alt, *dims[n], prefix=pre)}<figcaption class="cap"><b>Fig. {num}</b><span>{e(c)}</span></figcaption></figure>'
                   for num, n, c, alt in t["figs"])
    letters = "abcdefg"
    presets = "".join(
        f'<li><figure class="fig">{picture(None, "preset-" + p, t["preset_alt"].format(name=t["presets"][p][0]), 1400, 586, prefix=pre)}'
        f'<figcaption class="cap"><b>5{letters[i]}</b><span><strong>{e(t["presets"][p][0])}.</strong> {e(t["presets"][p][1])}</span></figcaption></figure></li>'
        for i, p in enumerate(PRESETS))
    motion = "".join(f"<li><span>&rarr;</span>{e(k)}</li>" for k in t["motion"])
    kinds = "".join(f"<li><span>{i+1:02d}</span>{e(k)}</li>" for i, k in enumerate(t["kinds"]))
    num, cap, alt = t["obj_main"]
    small = "".join(f'<figure class="fig">{picture(None, n, alt2, 1000, 419, prefix=pre)}<figcaption class="cap"><b>6{letters[i+1]}</b><span>{e(c)}</span></figcaption></figure>'
                    for i, (c, alt2, n) in enumerate(t["obj_small"]))
    facts = "".join(f'<li><svg viewBox="0 0 22 22" aria-hidden="true">{FACT_ICONS[i]}</svg><span>{e(f)}</span></li>' for i, f in enumerate(t["mac_facts"]))
    faq = "".join(f"<details><summary>{e(q)}</summary><p>{e(ans)}</p></details>" for q, ans in t["faq"])
    dl_steps = "".join(f"<li>{e(s)}</li>" for s in t["dl_steps"])

    return f"""<!doctype html>
<html lang="{t['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(t['title'])}</title>
<meta name="description" content="{e(t['desc'])}">
<link rel="canonical" href="{url}">
<link rel="alternate" hreflang="en" href="{BASE}">
<link rel="alternate" hreflang="de" href="{BASE}de/">
<link rel="alternate" hreflang="x-default" href="{BASE}">
<meta name="theme-color" content="#E4E6EA">
<meta name="color-scheme" content="light">
<meta property="og:type" content="website">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{e(t['title'])}">
<meta property="og:description" content="{e(t['desc'])}">
<meta property="og:image" content="{BASE}assets/img/og.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{e(t['og_alt'])}">
<meta property="og:locale" content="{'en_US' if key == 'en' else 'de_DE'}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="{pre}favicon.ico" sizes="32x32">
<link rel="icon" href="{pre}assets/img/favicon-512.png" type="image/png" sizes="512x512">
<link rel="apple-touch-icon" href="{pre}assets/img/apple-touch-icon.png">
<link rel="preload" href="{pre}assets/fonts/archivo-latin-wdth-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{pre}assets/css/site.css">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
</head>
<body>
<!--
THESIS: The page is the app's technical dossier. It proves a computed black hole the way a space-agency document proves a craft: figure plates with leader lines and a spec table of measured numbers. Refuses the category default of a dark glowing hero.
OWN-WORLD: cool datasheet grey, black 2px rules, Strudel orange as field and rule, the app's flowing bands as the sheet's lines, Archivo across its width axis, the black hole only inside black figure plates with white annotation.
STORY: see the hole bending light, learn that it is computed, check the numbers, download.
FIRST VIEWPORT: masthead with a flowing band, H1 in expanded caps with lede, orange download field and brew command on the left; a 7/12 figure plate with the live shader and four leader lines on the right; spec table below.
FORM: candidate 5 of 7 (mission documentation), seed f7a0f39c, with bands borrowed from the desktop direction.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
-->
<a class="skip" href="#main">{e(t['skip'])}</a>
<div class="wrap">
  <header class="head">
    <a class="id" href="./"><img src="{pre}assets/img/icon-64.png" alt="" width="28" height="28"><span>{e(t['name'])}</span></a>
    <span class="doc">{e(t['doc'])}</span>
    <nav aria-label="{e(t['nav_label'])}">{nav}<a class="lang" href="{t['other_path']}" hreflang="{t['other_lang']}" lang="{t['other_lang']}">{e(t['other_label'])}</a></nav>
  </header>
</div>
<div class="band" aria-hidden="true"></div>

<main id="main">
<div class="wrap">
  <div class="hero">
    <div class="copy">
      <div>
        <h1>{e(t['h1'])}</h1>
        <p class="lede">{e(t['lede'])}</p>
      </div>
      <div class="act">
        <a class="btn" href="{RELEASES}">{e(t['download'])}{DL_ICON}</a>
        {copy_btn(t)}
        <p class="fine">{e(t['fine'])}</p>
      </div>
    </div>
    <figure class="fig">
      <div class="plate" id="plate" data-label="{e(t['live_label'])}">
        {picture(None, "hero-still", t['still_alt'], 1400, 1061, lazy=False, prefix=pre)}
        <svg class="anno" viewBox="0 0 1000 1000" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
          <circle cx="500" cy="520" r="172" stroke-dasharray="3 5"/>
          <polyline points="625,400 770,232 980,232"/><text x="776" y="218">{e(a[0])}</text>
          <polyline points="470,350 330,190 20,190"/><text x="20" y="176">{e(a[1])}</text>
          <polyline class="m1" points="500,520 330,770 20,770"/><text class="m1" x="20" y="756">{e(a[2])}</text>
          <polyline points="705,520 770,800 980,800"/><text x="980" y="826" text-anchor="end">{e(a[3])}</text>
        </svg>
      </div>
      <figcaption class="cap"><b>Fig. 1</b><span>{e(t['fig1'])}</span><span class="hint" data-touch="{e(t['hint_touch'])}">{e(t['hint'])}</span></figcaption>
    </figure>
  </div>
</div>
<div class="band" aria-hidden="true"></div>
<div class="wrap">
  <dl class="spec">{spec}</dl>
  <p class="fine spec-note">{e(t['spec_note'])}</p>
</div>

<section class="dark" id="physics" aria-labelledby="physics-h">
  <div class="wrap phys">
    <div class="text">
      <h2 id="physics-h">{e(t['phys_h'])}</h2>
      {phys_p}
      <dl class="truth">{truth}</dl>
    </div>
    <div class="figs">{figs}</div>
  </div>
</section>
<div class="band" aria-hidden="true"></div>

<section id="presets" aria-labelledby="presets-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="presets-h">{e(t['pre_h'])}</h2><p>{e(t['pre_p'])}</p></div>
    <ul class="presets">{presets}</ul>
  </div>
</section>

<section class="spot" id="objects" aria-labelledby="objects-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="objects-h">{e(t['obj_h'])}</h2><p>{e(t['obj_p'])}</p></div>
    <div class="objects">
      <figure class="fig main-fig">{picture(None, "obj-ships", alt, 1600, 768, prefix=pre)}<figcaption class="cap"><b>Fig. {num}</b><span>{e(cap)}</span></figcaption></figure>
      <div>
        <ul class="kinds">{kinds}</ul>
        <div class="notes"><p>{e(t['obj_models'])}</p><p class="fine">{e(t['obj_note'])}</p></div>
      </div>
    </div>
    <div class="motion-row"><h3 class="motion-h">{e(t['motion_h'])}</h3><ul class="motion">{motion}</ul></div>
    <div class="obj-row">{small}</div>
  </div>
</section>

<section class="tint" id="mac" aria-labelledby="mac-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="mac-h">{e(t['mac_h'])}</h2></div>
    <div class="mac">
      <ul class="facts">{facts}</ul>
      <figure class="chart">
        <div class="body">
          <div class="bar"><div class="lbl"><span>{e(t['chart_all'])}</span><span class="num">{e(t['chart_all_v'])}</span></div><div class="track"><span class="range hot" style="left:56.7%;width:30%"></span></div></div>
          <div class="bar"><div class="lbl"><span>{e(t['chart_edges'])}</span><span class="num">{e(t['chart_edges_v'])}</span></div><div class="track"><span class="range" style="left:4%;width:1.2%;min-width:4px"></span></div></div>
          <div class="axis num" aria-hidden="true"><span>0 ms</span><span>1</span><span>2</span><span>3 ms</span></div>
        </div>
        <figcaption class="cap"><b>Fig. 7</b><span>{e(t['chart_cap'])}</span></figcaption>
      </figure>
    </div>
  </div>
</section>

<section class="dark film" id="film" aria-labelledby="film-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="film-h">{e(t['film_h'])}</h2><p>{e(t['film_p'])}</p></div>
    <figure class="fig">
      <div class="player">
        <video id="promo" muted playsinline loop preload="none" poster="{pre}assets/film/poster.jpg" width="1920" height="1080">
          <source src="{pre}assets/film/promo.webm" type="video/webm">
          <source src="{pre}assets/film/promo.mp4" type="video/mp4">
          <p>{e(t['film_fallback'])} <a href="{pre}assets/film/promo.mp4">{e(t['film_dl'])}</a></p>
        </video>
        <button class="play" id="play" type="button"><span><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 1.5v13l11-6.5z" fill="currentColor"/></svg>{e(t['film_play'])}</span></button>
      </div>
      <figcaption class="cap"><b>Fig. 8</b><span>{e(t['film_cap'])} <a href="{pre}assets/film/promo.mp4">{e(t['film_dl'])}</a></span></figcaption>
    </figure>
  </div>
</section>
<div class="band" aria-hidden="true"></div>

<section id="install" aria-labelledby="install-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="install-h">{e(t['inst_h'])}</h2><p>{e(t['inst_p'])}</p></div>
    <div class="install">
      <div class="path">
        <h3>{e(t['dl_h'])}</h3>
        <ol class="steps">
          <li>{e(t['dl_steps'][0])}<a class="btn" href="{RELEASES}">{e(t['dl_btn'])}{DL_ICON}</a></li>
          <li>{e(t['dl_steps'][1])}</li>
          <li class="warn">{e(t['first'])}</li>
          <li>{e(t['after'])}</li>
        </ol>
      </div>
      <div class="path">
        <h3>{e(t['brew_h'])}</h3>
        <ol class="steps">
          <li>{e(t['brew_step'])}{copy_btn(t)}</li>
          <li class="warn">{e(t['first'])}</li>
          <li>{e(t['after'])}</li>
        </ol>
      </div>
    </div>
  </div>
</section>

<section class="tint" id="faq" aria-labelledby="faq-h">
  <div class="wrap">
    <div class="sec-head"><h2 id="faq-h">{e(t['faq_h'])}</h2></div>
    <div class="faq">{faq}</div>
  </div>
</section>
</main>

<div class="band" aria-hidden="true"></div>
<footer class="foot">
  <div class="wrap">
    <span>{e(t['foot_made'])}</span>
    <a href="https://opensource.org/licenses/MIT">{e(t['foot_lic'])}</a>
    <a href="{REPO}">{e(t['foot_src'])}</a>
    <a href="{t['other_path']}" hreflang="{t['other_lang']}" lang="{t['other_lang']}">{e(t['other_label'])}</a>
  </div>
</footer>
<script type="module" src="{pre}assets/js/main.js"></script>
</body>
</html>
"""


for k, out in (("en", ROOT / "index.html"), ("de", ROOT / "de" / "index.html")):
    out.parent.mkdir(exist_ok=True)
    out.write_text(page(k), encoding="utf-8")
    print("geschrieben:", out.relative_to(ROOT))
