# Soniox Realtime STT + TTS & Flutter Audio Insights

Pipeline: Mic (`AudioService`, record) → Soniox STT + translation (`SonioxRealtimeTranslationService`)
→ `TranslationSegmenter` → `TtsStreamManager` → Soniox TTS → `PlayoutScheduler` → `PcmOutput`
(Android: `PcmStreamPlayer.kt`, AudioTrack streaming; elsewhere: `AudioPlayersPcmOutput`).

## 1. Soniox WebSocket Authentication
- **Web (Chrome):** Browser WebSockets do not support `Authorization: Bearer` HTTP headers. Authenticate via subprotocols list: `protocols: ['soniox-api-key', apiKey]`.
- **Native (Android/iOS):** Authenticate via `Authorization: Bearer <API_KEY>` HTTP header.
- **Regions (`SonioxRegion`):** a project's region is fixed at creation (default US, EU on request); its keys
  only authenticate at that region's endpoints (US key at `*.eu.soniox.com` → `401 unauthenticated`, "Incorrect
  API key"). `SonioxRegionDetector` probes EU first, then US, when a key is saved (or at start if unknown) and
  stores the region; the settings show it with a hint how to get EU processing.
- **Never send `api_key` in config payloads** (deprecated; "don't send it both ways"; refused from 15 Jan 2027).

## 2. Soniox STT (`stt-rt-v5`)
- Config supports `language_hints`, `context` (`terms`, `translation_terms: [{source, target}]`, `general`, `text`), `enable_endpoint_detection`, `max_endpoint_delay_ms` (500–3000).
- Non-final tokens are re-sent with every response and replace the previous provisional text; final tokens arrive once. Use `TranscriptModel` (final + provisional), never append non-final tokens.
- `translation_status`: `original` (source), `translation`, `none` (not translated, e.g. already target language / playback echo).
- Original-language text is not logged (user preference); only token timing (`start_ms`/`end_ms`) for gap diagnostics. Translated text is logged only in debug builds (release: length only), as the privacy policy promises the log holds no transcripts or translations.
- STT and TTS connections close after ~40 s without client messages; TTS keepalive is `{"keep_alive": true}` (sent every 20 s).

## 3. Soniox Realtime TTS Protocol (`wss://tts-rt[.eu].soniox.com/tts-websocket`)
- **Stream config:** one JSON per stream: `{"stream_id", "model": "tts-rt-v2", "language", "voice", "audio_format": "pcm_s16le", "sample_rate": 24000}`. `language` is mandatory; no `type` fields.
- **Text:** `{"stream_id", "text", "text_end"}`; **cancel:** `{"stream_id", "cancel": true}`.
- **Responses:** `audio` (base64) + `audio_end`, then `{"terminated": true}`. A stream is complete only after `terminated`. After a stream error the server also sends `terminated`.
- **Limits:** 5 concurrent streams per connection (`TtsStreamManager` uses max 4, queues the rest). A stream without text for "a few seconds" (no `text_end`) fails with `request_timeout` (408); keepalives don't extend it.
- **Segmenting (`TranslationSegmenter`):** one TTS stream per sentence. Forward complete words only; end streams at confirmed sentence punctuation (followed by whitespace), STT `<end>`, or idle (`defaultIdleClose` 1.8 s, must stay above typical translation burst gaps ~1.6 s and below the 408 timeout). Never end streams at commas (prosody breaks, more streams → 429).
- **Errors:** retry 408/429/5xx only if the stream produced no audio yet, with the *same* `stream_id` after `terminated` (keeps playout order). Otherwise emit an end marker.
- **Sequence numbers** (`streamIndex * 1000000 + chunkIndex`) are assigned on receipt and stay monotonic for the whole session, including reconnects (`connect(newSession: false)`).

## 4. Playout (`PlayoutScheduler`)
- Segments (TTS streams) play strictly in stream-index order; a missing earlier segment is waited for up to `maxStreamTransitionWaitMs`. Chunks for already finished segments are dropped.
- **Start delay per segment** (talkspurt-style): a segment starts when complete or when its first chunk waited `targetDelaySeconds`. The target is learned from arrival curves: `need = max(arrival_i − first − audioBefore_i)`, target = p90(last 10) + 0.3 s, raised immediately, lowered max 15 % per segment. Starvation is only acceptable *between* segments.
- **Pause shaping:** leading/trailing TTS silence is trimmed (−45 dBFS); pause after a segment = 350 ms (sentence) / 150 ms (clause) / 80 ms (soft), scaled down when behind.
- **Catch-up:** backlog above target → shorten pauses first, then speed up to 1.25x (ramp 0.05 per segment, pitch-preserving via AudioTrack `PlaybackParams`); emergency (≥12 s) 1.3x without pauses.
- Feeds the output with only ~0.4 s lookahead so ordering/timing decisions stay in Dart. Uses `package:clock` → testable with `fake_async`.

## 5. Audio Output
- **Android:** `PcmStreamPlayer.kt` writes PCM continuously into one AudioTrack (MODE_STREAM) — no gaps between chunks. Reports played/queued frames every 50 ms.
- **Fallback (`AudioPlayersPcmOutput`, e.g. Web):** WAV batches of 1–2 s via `audioplayers`; every `play()` leaves a small gap. Web autoplay: unlock with `AudioPlayer.resume()` on a user gesture. `onPlayerComplete` fires early on Web — use the computed PCM duration.

## 6. Android
- `TranslationForegroundService` (type microphone) keeps the mic alive in background / screen off.
- **Bluetooth:** recording uses `AndroidRecordConfig(manageBluetooth: false)` and `audioRouteChange: follow`. The `record` plugin otherwise switches a BT headset into its call profile (SCO/HFP, `setCommunicationDevice`), which conflicts with A2DP media playback: the headset mic goes silent or capture pauses whenever TTS plays. Input comes from the phone mic, output stays A2DP.
- Don't apply the `audioplayers` global `AudioContext` on Android (it sets speakerphone / audio mode system-wide); TTS plays via the native AudioTrack there.
- Mic voice processing (AEC/NS/AGC) mode `auto`: off with headphones (it suppresses speech during playback even without echo), on with loudspeaker (prevents our own TTS echo from being transcribed).

## 7. UI
- **Home:** language selection (spoken → target, locked while translating), start/stop, mic level, translated text.
  Without an API key the `ApiKeySetup` card sits on top and the translator below is greyed out and read-only;
  the key is checked (region) on OK, saved if accepted, and the region hint stays until "Verstanden".
- **Debug mode** (settings switch, off by default): shows the TTS buffer/latency card and the technical options
  (TTS engine, mic voice processing, source transcription, mic recording, log viewer). Those options only take
  effect while debug mode is on: `SettingsRepository` getters return defaults otherwise (`raw: true` reads the
  stored value for the settings screen).
