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

## 4. Adaptive TTS Jitter Buffer (`AdaptiveTtsBuffer`)
- **Sequence numbers are assigned on receipt** (`streamIdx * 1000000 + chunkIdx` in `_emitAudioDelta`), so chunks within one stream are always in order. Chunks of consecutive streams (`stream-N` tail, `stream-N+1` head) legitimately interleave — this is NOT an out-of-order event.
- **Sequence-Based Reordering:** Incoming deltas are inserted in sorted order by `sequenceNumber`, which serializes interleaved streams.
- **Out-of-order / gap detection is per stream** (`_lastReceivedSeq[streamId]`). Never compare against chunks of other streams (inflates target delay, resets speed).
- **Pre-roll (target delay):** Ends only when buffered >= `_targetDelaySeconds`, on `flushPreRoll()`, when all queued streams have ended AND the oldest queued chunk waited the target delay, or after `maxTargetDelay` as safety net. An end marker of an unrelated stream must not release pre-roll. A wake timer re-evaluates time-based conditions.
- **Pre-roll re-arm only on real underrun:** `rearmPreRoll()` is called by `AudioService` when the player is idle AND the buffer queue is empty. Never re-arm in `addChunk` (buffer being empty during playback is normal — `AudioService` drains it into its own queue) or on stream-id changes.
- **Sequence Gap Holding (`maxGapWaitMs = 150`):** If the queue head has a gap within the last played stream, hold popping up to 150ms.
- **Stream Transition Hold (`maxStreamTransitionWaitMs = 1000`):** Don't start `stream-N+1` until `stream-N` ended (`isLastInStream`) or received no audio for 1000ms. Measure from the last chunk *received* for `stream-N`, not from the last pop (pops happen ahead of real playback).
- **Holds must wake the pump:** when `hasAudioToPlay` is false due to a time-based hold, the buffer schedules a status event at hold expiry (provider pumps on status events).
- **Stale Chunk Dropping:** Late chunks with `sequenceNumber <= _lastPlayedSequenceNumber` are dropped to prevent time-warp glitches.
- **Jitter Adaptation:** Out-of-order events immediately reset playback speed to 1.0x and adapt `_targetDelaySeconds` pessimistically up to `maxTargetDelay` (10s).

## 5. Audio Service & Playback Batching (`AudioService`)
- **Batch Size:** Each `play()` call reloads the source and causes an audible gap, so keep batches around 2s (`maxBatchBytes = 96000`). Do not shrink to sub-second batches. Large batches don't harm ordering (see section 4).
- **Strict Stream Isolation:** Batching in `_runPlaybackLoop` MUST strictly verify `_queue.first.streamId == currentStreamId`. Never combine audio deltas from different TTS stream IDs into the same WAV playback batch.
