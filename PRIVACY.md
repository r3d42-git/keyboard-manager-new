# Datenschutz

Die Sammlung liegt im Benutzerordner des Mac unter `~/Library/Application Support/de.r3d42.KeyboardManagerV2/Current/`. Dort speichert Keyboard Manager die Datenbank, die verwalteten Fotos und ihre Vorschaubilder. Für ZIP-Backups und PDF-/XLSX-Berichte wählst du den Zielort im macOS-Sichern-Dialog. Die App benötigt kein Nutzerkonto und verwendet keine Telemetrie. Zur Wiederherstellung prüft die App die gewählte Sicherung lokal. Beim Ersetzen der Sammlung legt sie den bisherigen Bestand in ihrem Application-Support-Ordner ab.

## Fotos und Links

Das Öffnen der Sammlung, der Galerie und der Fotoansicht verwendet die lokalen Bilder. Enthält ein Eintrag externe Bildadressen, zeigt der Editor die beteiligten Hosts vor dem Download an. Erst nach deiner Bestätigung ruft er die Bilder über HTTPS ab. Der Bildabruf verwendet weder Cookies noch einen persistenten Netzwerkcache. Wenn du einen Quellenlink öffnest, übergibt die App dessen HTTPS-Adresse an deinen Standardbrowser.

## Updates

Beim Start und bei der manuellen Prüfung in den Einstellungen fragt die App das neueste stabile Release über die öffentliche GitHub-API ab. Der Versionsvergleich erfolgt auf deinem Mac. Die Anfrage enthält keine Sammlungsdaten. GitHub erhält dabei wie bei anderen Webanfragen die IP-Adresse und die üblichen HTTP-Anfrageinformationen.

Wenn du den Download bestätigst, lädt die App das DMG und die zugehörige SHA-256-Datei. Bei übereinstimmender Prüfsumme legt sie den Installer unter `~/Downloads/Keyboard Manager Updates/` ab und öffnet ihn.
