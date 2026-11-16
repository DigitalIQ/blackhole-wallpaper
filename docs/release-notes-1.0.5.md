# Black Hole Wallpaper 1.0.5

Die App gibt nach 60 Sekunden Pause die Grafik-Caches des pausierten Schirms frei. Das angezeigte Bild bleibt erhalten. Beim Fortsetzen werden die benötigten Ressourcen neu aufgebaut. Bei Speicherdruck werden zusätzlich gemeinsame Grafik-Caches freigegeben.

Im lokalen Test mit drei Schirmen sank der Speicherverbrauch von 421 MiB während der Animation auf 106 MiB nach längerer Pause. Nach dem Fortsetzen lag er wieder bei 419 MiB. Eine dauerhafte Einsparung während der Animation ist damit nicht belegt.

Alle sieben Werksvoreinstellungen liefern nach Freigabe und Wiederaufbau pixelgleiche Bilder. Der neue Selbsttest `--selftest-memory` prüft Darstellung und GPU-Speicherfreigabe.
