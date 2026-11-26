/// Text to read aloud when reading aloud is switched on during a talk: the last complete
/// sentence of [finalText] plus the sentence in progress after it, so speech continues
/// seamlessly with the next translated words.
///
/// Sentence ends: . ! ? … and Arabic ؟ ۔ (optionally followed by closing quotes/brackets),
/// followed by whitespace or the end of the text. Long texts without punctuation are cut to
/// the last [maxChars] characters at a word boundary.
String speechResumeText(String finalText, {int maxChars = 400}) {
  final text = finalText.trimRight();
  if (text.trim().isEmpty) return '';

  final ends = <int>[
    for (final m in _sentenceEnd.allMatches(text)) m.end,
  ];
  // End of the last complete sentence (the text itself may end with a complete sentence).
  final lastComplete = ends.isEmpty ? null : ends.last;
  var start = 0;
  if (lastComplete != null) {
    final before = ends.where((e) => e < lastComplete);
    start = before.isEmpty ? 0 : before.last;
  }
  var result = text.substring(start).trim();
  if (result.length > maxChars) {
    final cut = result.length - maxChars;
    final space = result.indexOf(RegExp(r'\s'), cut);
    result = (space == -1 ? result.substring(cut) : result.substring(space)).trim();
  }
  return result;
}

final RegExp _sentenceEnd = RegExp(r'[.!?…؟۔]+[»"”’)\]]*(?=\s|$)');
