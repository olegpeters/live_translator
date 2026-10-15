# Soniox Realtime STT + TTS & Flutter Audio Insights

## 1. Soniox WebSocket Authentication
- **Web (Chrome):** Browser WebSockets do not support `Authorization: Bearer` HTTP headers. Authenticate via subprotocols list: `protocols: ['soniox-api-key', apiKey]`.
- **Native (Android/iOS):** Authenticate via `Authorization: Bearer <API_KEY>` HTTP header.
- **Deprecated:** Do not send `api_key` inside initial JSON config payloads.

## 2. Soniox Realtime TTS Protocol (`wss://tts-rt.soniox.com/tts-websocket`)
- **Initial Stream Config:** Send one JSON config frame per stream:
  `{"stream_id": "stream-1", "model": "tts-rt-v2", "language": "ru", "voice": "Daniel", "audio_format": "pcm_s16le", "sample_rate": 24000}`
  - `language` is mandatory.
  - Do NOT include `type` fields (`"type": "start"` or `"type": "text"` are invalid schema).
- **Text Streaming:**
  `{"stream_id": "stream-1", "text": "...", "text_end": false}`
- **Stream Lifecycle & Limits:**
  - Max **5 concurrent active streams** per organization (exceeding triggers HTTP 429).
  - Idle streams receiving no text for >2–3 seconds without `text_end: true` are terminated by Soniox with `408 - Stream killed: output audio rate below minimum`.
  - Closing streams at every comma creates too many rapid streams and causes 429 concurrency errors and overlapping audio tracks.

## 3. Flutter Web & Audio Playback (`audioplayers`)
- **Autoplay Policy:** Web Audio Context must be unlocked via user gesture (`AudioPlayer.resume()`) upon starting translation.
- **Premature Cutoff Prevention:** On Web, `onPlayerComplete` events can fire earlier than the physical PCM duration. Always calculate sample duration (`durationMs = pcmBytes.length * 1000 / (sampleRate * 2)`) and delay before triggering playback for the next chunk to avoid cutting off playing audio.
