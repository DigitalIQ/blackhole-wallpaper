# Übersetzen

Die App spricht Deutsch und Englisch. Ohne Xcode gibt es keinen String-Catalog-Compiler, deshalb liegen die Übersetzungen in einer Swift-Tabelle. Das läuft gleich in der App, im Bildschirmschoner und in den Werkzeugen wie `--settings-shot`.

## So funktioniert es

- Im Code steht der deutsche Text, eingepackt in `L("…")`. Der deutsche Text ist zugleich der Schlüssel.
- `Sources/BlackHoleWallpaper/Strings.swift` hält die Tabelle `Loc.en`: deutscher Schlüssel, englischer Text.
- Platzhalter wie bei `String(format:)`: `L("%d Minuten", n)`, `L("„%@“ verschwindet …", name)`. Beide Sprachen brauchen dieselben Platzhalter in derselben Reihenfolge.
- Kataloge (Objektarten, Regler, Gruppen, Ereignisse, Paletten, Seitennamen) speichern den deutschen Text. Übersetzt wird erst beim Anzeigen, damit ein Sprachwechsel sofort wirkt. Deshalb nie `L()` in einem `static let`.
- Die Sprache steht in `settings.json` unter `settings.language`: `system`, `en` oder `de`. `system` nimmt Deutsch, wenn Deutsch in den bevorzugten Sprachen von macOS vor Englisch steht, sonst Englisch.
- Namen eingebauter Voreinstellungen werden über ihre ID übersetzt angezeigt, gespeichert bleibt der deutsche Name. Eigene oder umbenannte Voreinstellungen werden nie übersetzt.
- Den App-Namen für Finder und Spotlight legen `scripts/build-app.sh` und `scripts/build-saver.sh` als `InfoPlist.strings` in `en.lproj` und `de.lproj` ab.

## Einen Text ändern oder ergänzen

1. Im Code den deutschen Text in `L("…")` schreiben.
2. Denselben Text als Schlüssel in `Strings.swift` eintragen, mit englischem Wert. Eigennamen bekommen einen Eintrag mit gleichem Wert.
3. Ändert sich der deutsche Text, ändert sich der Schlüssel. Den alten Eintrag ersetzen.
4. `.build/release/BlackHoleWallpaper --selftest` aus dem Projektordner starten. Er prüft: jeder Schlüssel hat beide Sprachen, nichts ist leer, keine Gedankenstriche oder Emojis, gleiche Platzhalter, keine Umlaute im Englischen, jeder Katalogtext und jedes `L("…")` im Code steht in der Tabelle, kein Eintrag ist verwaist.
5. `BH_MISSING_TEXTS=fehlt.json .build/release/BlackHoleWallpaper --selftest` schreibt alle Schlüssel ohne Übersetzung in eine Datei.
6. Prüfbilder: `.build/release/BlackHoleWallpaper --settings-shot x.png --tab 0 --lang en`.

## Eine weitere Sprache

Eine zweite Tabelle neben `Loc.en` anlegen (etwa `Loc.fr`), `Lang` um den Fall erweitern, `Loc.text` und die Auswahl auf der Seite Allgemein ergänzen und die Prüfungen in `SelfTestTexts.swift` auf die neue Tabelle ausdehnen.
