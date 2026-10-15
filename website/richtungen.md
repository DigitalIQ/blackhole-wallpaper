# Design-Richtungen (Phase 4)

Stand 2026-10-13. Auftrag: zwei eigene Richtungen als gerenderte Entwürfe der ersten Bildschirmseite, Desktop und Handy. Der Skill verlangt sieben erarbeitete Richtungen und das Los von impeccable. Beides ist gemacht, gebaut sind zwei.

## Grundlage

- Mechanismus in einem Satz: ein Schwarzes Loch, das jeden Pixel deines Schreibtischs echt biegt, live gerechnet.
- Szene: Mac-Nutzer, die einen Link öffnen, oft abends, oft schon mit dunklem Schreibtisch.
- Der Trott dieser Kategorie: dunkle Seite mit Neonglühen und einem schwebenden Produktbild im MacBook-Rahmen. Das Gegenteil wäre eine helle, verspielte App-Seite. Beides steht nicht auf der Liste.

## Sieben Kandidaten, nach Resonanz geordnet

| Nr. | Welt | Warum sie trägt | Materialfamilie |
|---|---|---|---|
| 1 | Der Mac-Schreibtisch selbst: Menüleiste, Dock, Bänder | Das Produkt lebt genau dort, die Bänder sind sein Erkennungszeichen | Bildschirm-Oberfläche |
| 2 | Abbildung aus einem Physik-Aufsatz zum Raytracing | Zeigt, dass gerechnet wird; Bemaßung, Abbildungsnummern | wissenschaftliche Notation |
| 3 | Titelsequenz eines Science-Fiction-Films | Gargantua, Schiffe aus Film und Serie | Kino |
| 4 | Glasplatten-Archiv einer Sternwarte | Himmel als Beleg, Negativ, Beschriftung von Hand | Fotografie, Archiv |
| 5 | Missionsakte einer Raumfahrtbehörde der 70er: Datenblatt, Spezifikation, Abbildung mit Bemaßung | Technischer Beleg in strenger Form, Messwerte haben Gewicht | Druck, Dokumentation |
| 6 | Programmheft eines Planetariums | Abendritual unter der Kuppel | Ort, Ritual |
| 7 | Brückenkonsole eines Raumschiffs | Die Schiffe der App | Bildschirm-Oberfläche (fiktiv) |

## Los

`concept-seed.mjs --scope direction --mode persuade`, Schlüssel `f7a0f39c`: zu bauen ist Kandidat 5, die Missionsakte. Herausforderer aus dem Katalog von impeccable und ihr Urteil:

| Herausforderer | Urteil | Was die Missionsakte davon übernimmt |
|---|---|---|
| Magazin-Programm mit verstecktem Zeichen | abgelehnt | Strenges Zweispalten-Raster, eine Schmuckfarbe pro Ausgabe |
| Holzschnitt in Farbschichten | abgelehnt | nichts |
| Irisierender Wolkenrand | abgelehnt | nichts |
| Akkretionsscheibe an der Schwelle | konkurrenzfähig, aber deckungsgleich mit dem Produkt | Beschriftungen an Leitlinien rund um den Ring |
| Schneidetisch mit Filmstreifen | abgelehnt | Orange als Fläche mit einem Drittel Anteil, nicht als Akzent |

Dazu als zweite Richtung der eigene Favorit, Kandidat 1 (im Skill „Impeccable's Pick“).

## Richtung A: Missionsakte

Entwurf: `entwuerfe/a-missionsakte/index.html`, Bilder `entwuerfe/bilder/a-missionsakte-desktop.jpg` und `entwuerfe/bilder/a-missionsakte-handy.jpg`.

- Welt: das technische Datenblatt der App. Kühles Datenblatt-Grau, schwarze Linien in 2 px, Strudel-Orange nur als Fläche und Linie. Archivo über die Breitenachse: breite Versalien für Titel, normale Breite für Text.
- Erster Bildschirm: links die H1 in breiten Versalien, Unterzeile, oranges Download-Feld, Brew-Befehl zum Kopieren. Rechts „Fig. 1“, eine schwarze Bildplatte mit dem Live-Loch (three.js) und vier Leitlinien: Photonenring, gebogene Rückseite der Scheibe, Schatten, hellere Seite. Unten eine Spezifikationsleiste mit den echten Messwerten aus der README.
- Geschichte beim Scrollen: Abbildungen 2 bis 7 für die Voreinstellungen, eine Tabelle der Objektarten, die Physik als Abschnitt mit Fußnoten zur README.
- Stärke: hebt sich klar von allen Wallpaper-Seiten ab, macht „echt gerechnet“ sichtbar, Messwerte werden zum Beleg.
- Risiko: hell und streng. Wer nur einen schönen Hintergrund sucht, findet die Akte vielleicht zu technisch.

## Richtung B: Schreibtisch

Entwurf: `entwuerfe/b-schreibtisch/index.html`, Bilder `entwuerfe/bilder/b-schreibtisch-desktop.jpg` und `entwuerfe/bilder/b-schreibtisch-handy.jpg`.

- Welt: die Seite ist der Schreibtisch, den die App macht. Oben eine Menüleiste mit dem echten Menüleisten-Symbol, unten ein Dock, beide mit fließenden Bändern wie in der App. Dazwischen das Live-Loch über die ganze Fläche. Palette Strudel in voller Stärke, Download-Knopf im hellen Gold der innersten Scheibe. Bricolage Grotesque schmal für Titel, Hanken Grotesk für Text.
- Erster Bildschirm: Loch rechts, H1 und Unterzeile links unten, das Dock in der Mitte unten trägt App-Symbol, Download und Brew-Befehl. Beim Scrollen fährt die Kamera näher ans Loch.
- Geschichte beim Scrollen: Abschnitte als ruhige Flächen über dem Nebel, die Voreinstellungen wechseln den Himmel der Seite.
- Stärke: zeigt das Produkt sofort an seinem echten Ort, wirkt am stärksten.
- Risiko: dunkel mit Glühen ist der Trott der Kategorie. Menüleiste und Dock dürfen nicht wie eine Kopie von macOS wirken (kein Apple-Logo, keine Fensterknöpfe).

## Gemeinsam für beide

- `entwuerfe/shared/blackhole.js`: Schwarzschild-Lichtbahnen im Fragment-Shader über three.js 0.170 (selbst gehostet), Scheibe ab r = 3, Kepler-Drehung, Doppler-Aufhellung, gebogener Himmel mit Nebel und Sternen. Halbe Pixeldichte, 30 Bilder pro Sekunde, hält an, wenn nicht sichtbar. Bei `prefers-reduced-motion` und ohne WebGL bleibt ein Standbild aus der App stehen.
- Nicht geprüft: Bildrate auf einem echten MacBook Air. Die Screenshots kommen aus Chrome über Playwright auf diesem Mac.
- Die Seite sagt offen, dass das Loch im Browser eine leichtere Fassung ist (Schwarzschild statt Kerr).

## Empfehlung

A, die Missionsakte, mit einer Leihgabe aus B: die fließenden Bänder als Linien des Datenblatts. Begründung: A beweist, was diese App von Video-Wallpapern unterscheidet, und fällt zwischen dunklen Mac-App-Seiten auf. B ist schöner im ersten Moment, sieht aber aus wie viele Seiten dieser Art.

Jev (`typesafe/jev-1.13`, Anfrage mit den Beschreibungen beider Richtungen, 2026-10-13): A mit Wahrscheinlichkeit 0,83, Confidence 0,74. Weil die Confidence unter 0,8 liegt, habe ich selbst geprüft und stimme A zu, aus dem Grund oben.
