# Auditorium

Android-App (Flutter), die Vorträge, Predigten und Seminare live übersetzt und die Übersetzung
per Sprachausgabe direkt in die Kopfhörer spricht – auch bei ausgeschaltetem Bildschirm.

- Spracherkennung, Übersetzung und Sprachausgabe: [Soniox](https://soniox.com) (Realtime STT + TTS; EU- oder US-Endpunkte je nach Region des Soniox-Projekts, automatisch erkannt)
- Gesprochene Sprache: Deutsch, Englisch oder automatisch
- Zielsprachen: Russisch, Ukrainisch, Englisch, Deutsch, Spanisch, Französisch, Arabisch
- Eigenes Glossar für Namen und Fachbegriffe; Glossar für Predigten ist enthalten

Für die Nutzung ist ein eigener Soniox-API-Schlüssel nötig, der in den Einstellungen eingetragen
und verschlüsselt auf dem Gerät gespeichert wird.

## Entwicklung

```sh
flutter pub get
flutter test
flutter run
```

Architektur, Soniox-Protokoll und Audio-Details: siehe [AGENTS.md](AGENTS.md).

## Release (Google Play)

```sh
flutter build appbundle --release
```

- Vor jedem Upload die Build-Nummer in `pubspec.yaml` erhöhen (`version: x.y.z+<build>`).
- Store-Texte: `fastlane/metadata/android/de-DE/`.
- Debug-Funktionen (Mikrofon-Mitschnitt) sind in Release-Builds deaktiviert.
