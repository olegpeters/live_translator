import 'dart:math';
import 'dart:typed_data';

/// Converts raw 16-bit PCM mono bytes into a valid WAV format with a 44-byte RIFF header.
Uint8List pcmToWav(
  Uint8List pcmBytes, {
  int sampleRate = 24000,
  int numChannels = 1,
  int bitsPerSample = 16,
}) {
  final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final int blockAlign = numChannels * (bitsPerSample ~/ 8);
  final int dataSize = pcmBytes.length;
  final int chunkSize = 36 + dataSize;

  final ByteData header = ByteData(44);
  // "RIFF"
  header.setUint8(0, 0x52); // 'R'
  header.setUint8(1, 0x49); // 'I'
  header.setUint8(2, 0x46); // 'F'
  header.setUint8(3, 0x46); // 'F'
  // ChunkSize (little-endian)
  header.setUint32(4, chunkSize, Endian.little);
  // "WAVE"
  header.setUint8(8, 0x57); // 'W'
  header.setUint8(9, 0x41); // 'A'
  header.setUint8(10, 0x56); // 'V'
  header.setUint8(11, 0x45); // 'E'
  // "fmt "
  header.setUint8(12, 0x66); // 'f'
  header.setUint8(13, 0x6D); // 'm'
  header.setUint8(14, 0x74); // 't'
  header.setUint8(15, 0x20); // ' '
  // Subchunk1Size (16 for PCM)
  header.setUint32(16, 16, Endian.little);
  // AudioFormat (1 = PCM)
  header.setUint16(20, 1, Endian.little);
  // NumChannels
  header.setUint16(22, numChannels, Endian.little);
  // SampleRate
  header.setUint32(24, sampleRate, Endian.little);
  // ByteRate
  header.setUint32(28, byteRate, Endian.little);
  // BlockAlign
  header.setUint16(32, blockAlign, Endian.little);
  // BitsPerSample
  header.setUint16(34, bitsPerSample, Endian.little);
  // "data"
  header.setUint8(36, 0x64); // 'd'
  header.setUint8(37, 0x61); // 'a'
  header.setUint8(38, 0x74); // 't'
  header.setUint8(39, 0x61); // 'a'
  // Subchunk2Size
  header.setUint32(40, dataSize, Endian.little);

  final Uint8List wavBytes = Uint8List(44 + dataSize);
  wavBytes.setRange(0, 44, header.buffer.asUint8List());
  wavBytes.setRange(44, 44 + dataSize, pcmBytes);
  return wavBytes;
}

/// Amplifies 16-bit PCM mono bytes by a factor of [gain].
/// Values are clamped between -32768 and 32767 to prevent digital clipping overflow.
Uint8List amplifyPcm16(Uint8List pcmBytes, double gain) {
  if (gain == 1.0 || pcmBytes.isEmpty) return pcmBytes;

  final ByteData byteData = ByteData.sublistView(pcmBytes);
  final Uint8List amplifiedBytes = Uint8List(pcmBytes.length);
  final ByteData outData = ByteData.sublistView(amplifiedBytes);

  final int sampleCount = pcmBytes.length ~/ 2;
  for (int i = 0; i < sampleCount; i++) {
    final int sample = byteData.getInt16(i * 2, Endian.little);
    final int amplified = (sample * gain).round().clamp(-32768, 32767);
    outData.setInt16(i * 2, amplified, Endian.little);
  }

  return amplifiedBytes;
}

/// Applies a smooth linear fade-in and/or fade-out to 16-bit PCM mono bytes.
/// Micro fade-in/out (default 32 samples = ~1.3ms at 24kHz) is applied only at the
/// start/end of a stream to prevent DC-offset step pops, while keeping inner
/// batch boundaries bit-exact continuous to prevent stuttering/volume dips.
Uint8List applyPcm16EdgeSmoothing(
  Uint8List pcmBytes, {
  bool fadeIn = false,
  bool fadeOut = false,
  int fadeSamples = 32,
}) {
  if ((!fadeIn && !fadeOut) || pcmBytes.length < 4) return pcmBytes;

  final int totalSamples = pcmBytes.length ~/ 2;
  final int actualFadeSamples = min(fadeSamples, totalSamples ~/ 2);
  if (actualFadeSamples <= 0) return pcmBytes;

  final Uint8List smoothedBytes = Uint8List.fromList(pcmBytes);
  final ByteData byteData = ByteData.sublistView(smoothedBytes);

  if (fadeIn) {
    for (int i = 0; i < actualFadeSamples; i++) {
      final double factor = i / actualFadeSamples;
      final int sample = byteData.getInt16(i * 2, Endian.little);
      final int smoothed = (sample * factor).round().clamp(-32768, 32767);
      byteData.setInt16(i * 2, smoothed, Endian.little);
    }
  }

  if (fadeOut) {
    for (int i = 0; i < actualFadeSamples; i++) {
      final int sampleIndex = totalSamples - actualFadeSamples + i;
      final double factor = (actualFadeSamples - 1 - i) / actualFadeSamples;
      final int sample = byteData.getInt16(sampleIndex * 2, Endian.little);
      final int smoothed = (sample * factor).round().clamp(-32768, 32767);
      byteData.setInt16(sampleIndex * 2, smoothed, Endian.little);
    }
  }

  return smoothedBytes;
}
