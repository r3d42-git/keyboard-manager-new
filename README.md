# Keyboard Manager

Keyboard Manager verwaltet mechanische Tastaturen und ihre Komponenten lokal auf dem Mac. Zu jedem Board siehst du, welche Keycap-Sets montiert sind und wie viele Switches aus welchem Set verbaut sind. Fotos, Notizen und technische Daten gehören direkt zum Eintrag. Die App läuft ab macOS 14 und ist auf Deutsch und Englisch verfügbar.

Das universelle DMG unterstützt Macs mit Apple-Chip und Intel-Prozessor. [Aktuelles stabiles Release](https://github.com/r3d42-git/keyboard-manager-new/releases/latest) · [Alle Releases](https://github.com/r3d42-git/keyboard-manager-new/releases)

## Die Sammlung bedienen

- **Übersicht** (⌘1) zeigt Keyboards, Keycap-Sets, Artisans und Switch-Sets als Tabelle. Wähle oben die Bestandsart und klicke auf einen Spaltenkopf, um zu sortieren. Bei Switch-Sets zeigen **Gesamt**, **Verbaut** und **Verfügbar**, wie viele Switches du hast, wie viele verteilt sind und wie viele noch frei sind.
- **Galerie** (⌘2) öffnet sich beim Start mit deinen Keyboards. Hier kannst du auch Keycap-Sets und Artisans ansehen und unten rechts die Größe der Fotokarten einstellen. Suche, Filter und Sortierung gelten je Bestandsart in beiden Ansichten. Die App merkt sich Spalte und Richtung auch nach einem Neustart. Mit **Ohne Foto** und bei Keycap-Sets und Artisans zusätzlich **Nicht montiert** findest du passende Einträge direkt.
- Ein Klick auf eine Karte oder ein Doppelklick auf eine Tabellenzeile öffnet die Details. Von einem Keyboard kannst du zu den verknüpften Keycap-Sets, Artisans und Switch-Sets wechseln und mit **Zurück zum Keyboard** wieder dasselbe Board und Foto ansehen.
- **Erfassen** (⌘3) oder **⌘N** öffnet einen Entwurf mit den Reitern **Daten**, **Verknüpfungen**, **Fotos** und **Notizen**. Unter **Verknüpfungen** kannst du einem Keyboard mehrere Keycap-Sets zuordnen und verbaute Switch-Stückzahlen direkt eingeben.

Die Anleitung beschreibt die Bedienung, Komponentenbeziehungen und den Export von PDF- und XLSX-Berichten. [Fachliche Beschreibung](documentation/Keyboard_Manager_V2_Fachliche_Beschreibung.md) · [Datenschutz](PRIVACY.md)

## Backup und Datenübernahme

Unter **Daten** in der Seitenleiste erstellst du ein ZIP-Backup mit allen vier Bestandsarten und den lokal verwalteten Fotos. Über **Backup einspielen …** kannst du auch ZIP-Sicherungen früherer Versionen der nativen Mac-App öffnen. Die App prüft die Sicherung und zeigt die enthaltenen Einträge und Fotos an. Erst nach deiner Bestätigung ersetzt sie die aktuelle Sammlung. Einen vorhandenen Bestand bewahrt sie separat auf und zeigt ihn auf Wunsch im Finder. [Backup und Wiederherstellung](documentation/Keyboard_Manager_V2_Fachliche_Beschreibung.md#berichte-und-backups-speichern)

Wenn du die native Mac-App bereits verwendest, öffnet Version 1.2.0 deinen lokalen Bestand einschließlich bereits importierter V1-Daten direkt. Hast du deine Sammlung noch in der früheren Electron-App oder nur als V1-Sicherung, verwende zuerst **V1-Migration** in der nativen Version **1.1.2**. Dort kannst du einen V1-Datenordner, ein V1-ZIP-Backup oder eine ältere V1-JSON-Sicherung übernehmen. Prüfe den übernommenen Bestand in 1.1.2 und aktualisiere anschließend auf 1.2.0. [Version 1.1.2](https://github.com/r3d42-git/keyboard-manager-new/releases/tag/v1.1.2)

## Lokal bauen

Führe mit installiertem Xcode im Projektordner diesen Befehl aus.

```bash
./script/build_and_run.sh --build
```

Der Debug-Build liegt unter `dist/Keyboard Manager.app`. Ein Aufruf von `./script/build_and_run.sh` baut und startet die App. Die Tests laufen mit folgendem Befehl.

```bash
xcodebuild -project KeyboardManager.xcodeproj -scheme KeyboardManager -configuration Debug test
```

Für die Verteilung entsteht ein universelles, Developer-ID-signiertes und von Apple notarisiertes DMG. [Release-Anleitung](RELEASE.md)

## Projekthistorie

Die folgenden Dokumente beschreiben den früheren Entwicklungsstand einschließlich der damaligen V1-Datenübernahme. Der aktuelle Produktumfang ist in der fachlichen Beschreibung oben dokumentiert.

- [Projektübersicht und Architektur](PROJECT_SUMMARY.md)
- [Historischer Funktionsvergleich](FEATURE_PARITY.md)
- [Frühere Migrationsstrategie](MIGRATION.md)

## Lizenz

Ab Version 1.1.1 steht das Projekt unter GNU GPL Version 3 oder später (`GPL-3.0-or-later`). Frühere Releases behalten ihre MIT-Lizenz. Der vollständige Quellcode jedes Releases ist über das gleichnamige Git-Tag verfügbar. [Lizenz](LICENSE) · [Lizenzhinweise](LICENSING.md) · [Hinweise zu ZIPFoundation](THIRD_PARTY_NOTICES.md)
