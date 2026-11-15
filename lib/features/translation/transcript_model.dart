/// Transcript made of finalized text plus a provisional (non-final) tail.
///
/// Soniox delivers final tokens exactly once, while non-final tokens are re-sent with every
/// response and replace the previous provisional tail. Appending non-final tokens would
/// duplicate text.
class TranscriptModel {
  final StringBuffer _final = StringBuffer();
  String _provisional = '';

  String get finalText => _final.toString();
  String get provisionalText => _provisional;
  String get text => '$_final$_provisional';
  bool get isEmpty => _final.isEmpty && _provisional.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Applies one STT response: [finalText] is appended, [provisionalText] replaces the tail.
  void apply({required String finalText, required String provisionalText}) {
    _final.write(finalText);
    _provisional = provisionalText;
  }

  void clear() {
    _final.clear();
    _provisional = '';
  }
}
