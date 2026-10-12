# Umstellung der Live-Übersetzung auf Soniox Speech-to-Speech (STS)

Dieses Dokument beschreibt die Architektur und die geplanten Änderungen zur Umstellung des Live-Übersetzungs-Services von der OpenAI Realtime API (`gpt-realtime-translate`) auf die **Soniox Real-time Speech-to-Speech (STS) Translation API** (`stt-rt.soniox.com` & `tts-rt.soniox.com`).

---

## User Review Required

> [!IMPORTANT]
> **Neuer API-Key erforderlich:** Da Soniox als Anbieter verwendet wird, benötigt die Anwendung nun einen **Soniox API Key** anstelle eines OpenAI Keys.
>
> **Zwei parallele WebSocket-Verbindungen:** Die Soniox STS Pipeline nutzt zwei gekoppelte WebSockets (einen für Real-time Speech-to-Text + Translation und einen für Real-time Text-to-Speech). Das Routing der übersetzten Text-Token an den TTS-Service erfolgt in Echtzeit auf Client-Seite (`SonioxRealtimeTranslationService`).

---

## Open Questions

- Gibt es eine bevorzugte Standard-Stimme (Soniox Voice) für die synthetisierte Sprachausgabe (z.B. "Daniel")? *(Standardmäßig wird "Daniel" als vorausgewählte Stimme hinterlegt, konfigurierbar in den Einstellungen)*.

---

## Proposed Changes

### Core Network Layer

#### [NEW] [soniox_realtime_translation_service.dart](file:///Users/pete414980/github-projects/live-translator/lib/core/network/soniox_realtime_translation_service.dart)
- Erstellt `SonioxRealtimeTranslationService`, der zwei WebSocket-Verbindungen verwaltet:
  1. **STT + Translation WebSocket (`wss://stt-rt.soniox.com/transcribe-websocket`)**:
     - sendet Header `Authorization: Bearer <API_KEY>`
     - sendet initiale JSON-Konfiguration:
       ```json
       {
         "model": "stt-rt-v5",
         "audio_format": "pcm_s16le",
         "sample_rate": 24000,
         "num_channels": 1,
         "enable_endpoint_detection": true,
         "translation": {
           "type": "one_way",
           "target_language": "ru"
         }
       }
       ```
     - überträgt Audio-Chunks (PCM16, 24kHz) als binäre WebSocket-Frames.
     - verarbeitet eingehende `tokens`:
       - `translation_status == "original"` -> gibt Quelltranskription auf `onSourceTranscriptDelta` aus.
       - `translation_status == "translation"` -> gibt Zieltranskription auf `onTranscriptDelta` aus und leitet den Text direkt an den TTS-WebSocket weiter.
  2. **TTS WebSocket (`wss://tts-rt.soniox.com/tts-websocket`)**:
     - sendet Header `Authorization: Bearer <API_KEY>`
     - sendet initiale JSON-Konfiguration:
       ```json
       {
         "stream_id": "stream-1",
         "model": "tts-rt-v2",
         "voice": "Daniel",
         "audio_format": "pcm_s16le",
         "sample_rate": 24000
       }
       ```
     - empfängt übersetzte Textstücke und sendet diese als `{ "text": tokenText, "text_end": false }`.
     - empfängt generierte Base64 PCM-Audiochunks `{ "audio": "<base64_data>", "audio_end": false }`, dekodiert diese und leitet sie als `AudioDelta` an die App-Audiowiedergabe weiter.

#### [DELETE] [openai_realtime_translation_service.dart](file:///Users/pete414980/github-projects/live-translator/lib/core/network/openai_realtime_translation_service.dart)
- Entfernung des alten OpenAI-Services, da die Funktionalität vollständig durch `SonioxRealtimeTranslationService` ersetzt wird.

---

### Storage Layer

#### [MODIFY] [settings_repository.dart](file:///Users/pete414980/github-projects/live-translator/lib/core/storage/settings_repository.dart)
- Aktualisierung der Storage-Keys (`soniox_api_key`, `soniox_voice`).
- Hinzufügen von Hilfsmethoden für `getVoice()` / `setVoice()` mit Standardwert `"Daniel"`.

---

### Translation & State Management Layer

#### [MODIFY] [translation_provider.dart](file:///Users/pete414980/github-projects/live-translator/lib/features/translation/translation_provider.dart)
- Austausch der `OpenAiRealtimeTranslationService`-Abhängigkeit gegen `SonioxRealtimeTranslationService`.
- Aktualisierung von Statusmeldungen ("Verbinde mit Soniox...").
- Übergabe von API Key, Target Language und Voice beim Verbindungsaufbau.

---

### UI Layer & Entrypoint

#### [MODIFY] [settings_screen.dart](file:///Users/pete414980/github-projects/live-translator/lib/features/settings/settings_screen.dart)
- Anpassung der Überschriften und Textfelder auf **Soniox API Konfiguration** & **Soniox API Key**.
- Hinzufügen eines Dropdowns zur Auswahl der Soniox Stimme (z.B. "Daniel", "Adrian").

#### [MODIFY] [main.dart](file:///Users/pete414980/github-projects/live-translator/lib/main.dart)
- Instanziierung von `SonioxRealtimeTranslationService` statt `OpenAiRealtimeTranslationService`.

---

### Tests

#### [NEW] [soniox_realtime_translation_service_test.dart](file:///Users/pete414980/github-projects/live-translator/test/soniox_realtime_translation_service_test.dart)
- Unit-Tests mit Fake WebSocket Channels zur Prüfung des dualen Verbindungsaufbaus, des Token-Routings, der Audiodaten-Verarbeitung und des Verbindungsabbaus.

#### [DELETE] [openai_realtime_translation_service_test.dart](file:///Users/pete414980/github-projects/live-translator/test/openai_realtime_translation_service_test.dart)
- Entfernung der veralteten OpenAI-Tests.

---

## Verification Plan

### Automated Tests
- Ausführen der Flutter Unit Tests:
  ```bash
  flutter test test/soniox_realtime_translation_service_test.dart
  flutter test test/audio_service_test.dart
  flutter test test/settings_repository_test.dart
  ```

### Manual Verification
- Überprüfung der Einstellungen im Emulator/Gerät (Soniox API Key Eingabe, Voice Auswahl, Zielsprachenauswahl).
- Testen des Start/Stopp-Prozesses der Live-Übersetzung.
