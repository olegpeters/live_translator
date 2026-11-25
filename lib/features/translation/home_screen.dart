import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import '../settings/settings_screen.dart';
import 'api_key_setup.dart';
import 'languages.dart';
import 'translation_provider.dart';

class HomeScreen extends StatefulWidget {
  final SettingsRepository settingsRepository;
  final SonioxRegionDetector? regionDetector;

  const HomeScreen({super.key, required this.settingsRepository, this.regionDetector});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SonioxRegionDetector _regionDetector = widget.regionDetector ?? SonioxRegionDetector();

  bool _loaded = false;

  /// API key setup card on top; the translator below stays read-only and greyed out
  /// until the key is checked and the user confirmed the result ("Verstanden").
  bool _showSetup = false;
  bool _debugMode = false;
  String _sourceLanguage = 'de';
  String _targetLanguage = 'ru';

  SettingsRepository get settingsRepository => widget.settingsRepository;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final key = await settingsRepository.getApiKey();
    final debugMode = await settingsRepository.getDebugMode();
    final source = await settingsRepository.getSourceLanguage();
    final target = await settingsRepository.getTargetLanguage();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _showSetup = key == null || key.trim().isEmpty;
      _debugMode = debugMode;
      _sourceLanguage = sourceLanguages.any((l) => l.code == source) ? source : 'de';
      _targetLanguage = targetLanguages.any((l) => l.code == target) ? target : 'ru';
    });
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => SettingsScreen(settingsRepository: settingsRepository)))
        .then((_) => _loadState()); // key removed or debug mode toggled
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditorium'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _showSetup
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ApiKeySetup(
                            settingsRepository: settingsRepository,
                            regionDetector: _regionDetector,
                            onDone: () => setState(() => _showSetup = false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Preview of the translator: visible but read-only until a key is set up.
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: Opacity(opacity: 0.45, child: _buildTranslator(expandTranscript: false)),
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildTranslator(expandTranscript: true),
                ),
    );
  }

  Widget _buildTranslator({required bool expandTranscript}) {
    return Consumer<TranslationProvider>(
      builder: (context, provider, child) {
        final isTranslating = provider.isTranslating;
        final transcriptBox = _transcriptBox(provider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expandTranscript ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _languageRow(enabled: !isTranslating),
            const SizedBox(height: 12),
            _statusCard(provider),
            const SizedBox(height: 12),
            _levelBar(provider),
            if (_debugMode && isTranslating) ...[
              const SizedBox(height: 12),
              _bufferCard(provider),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Übersetzung (${languageName(targetLanguages, _targetLanguage)})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (provider.targetTranscript.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_all, size: 20),
                    tooltip: 'Text leeren',
                    onPressed: provider.clearTranscript,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (expandTranscript) Expanded(child: transcriptBox) else SizedBox(height: 160, child: transcriptBox),
            // Debug: source text as recognized by the model
            if (_debugMode && provider.enableSourceTranscription) _sourceTranscriptTile(provider),
          ],
        );
      },
    );
  }

  /// Spoken language → translation language. Locked while translating (applies at start).
  Widget _languageRow({required bool enabled}) {
    DropdownButtonFormField<String> dropdown({
      required String label,
      required String value,
      required List<LanguageOption> options,
      required ValueChanged<String> onChanged,
    }) {
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [for (final o in options) DropdownMenuItem(value: o.code, child: Text(o.name))],
        onChanged: enabled
            ? (v) {
                if (v != null) onChanged(v);
              }
            : null,
      );
    }

    return Row(
      children: [
        Expanded(
          child: dropdown(
            label: 'Vortrag',
            value: _sourceLanguage,
            options: sourceLanguages,
            onChanged: (code) {
              setState(() => _sourceLanguage = code);
              settingsRepository.setSourceLanguage(code);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward),
        ),
        Expanded(
          child: dropdown(
            label: 'Übersetzung',
            value: _targetLanguage,
            options: targetLanguages,
            onChanged: (code) {
              setState(() => _targetLanguage = code);
              settingsRepository.setTargetLanguage(code);
            },
          ),
        ),
      ],
    );
  }

  Widget _statusCard(TranslationProvider provider) {
    final isTranslating = provider.isTranslating;
    return Card(
      elevation: 2,
      color: isTranslating ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isTranslating ? Icons.sensors : Icons.sensors_off,
              color: isTranslating ? Colors.green : Colors.grey,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    provider.statusMessage,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isTranslating ? Colors.green.shade900 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: isTranslating ? 'Tippen zum Stoppen' : 'Tippen zum Starten',
              child: GestureDetector(
                onTap: () {
                  if (isTranslating) {
                    provider.stopTranslation();
                  } else {
                    provider.startTranslation();
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isTranslating ? Colors.red : Colors.deepPurple,
                    boxShadow: [
                      BoxShadow(
                        color: (isTranslating ? Colors.red : Colors.deepPurple).withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    isTranslating ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _levelBar(TranslationProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mikrofon-Pegel',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            Text(
              '${(provider.audioLevel * 100).toInt()}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: provider.audioLevel,
            minHeight: 10,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(
              provider.audioLevel > 0.8
                  ? Colors.red
                  : (provider.audioLevel > 0.4 ? Colors.orange : Colors.blue),
            ),
          ),
        ),
      ],
    );
  }

  /// Debug mode: adaptive TTS buffer, playback speed and latencies.
  Widget _bufferCard(TranslationProvider provider) {
    return Card(
      elevation: 1,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq, size: 20, color: Colors.blue.shade800),
                    const SizedBox(width: 8),
                    Text(
                      'TTS Audio-Puffer & Sync',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: provider.currentPlaybackSpeed > 1.01 ? Colors.orange.shade100 : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Tempo: ${provider.currentPlaybackSpeed.toStringAsFixed(2)}x',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: provider.currentPlaybackSpeed > 1.01 ? Colors.orange.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    provider.isPreRolling
                        ? 'Puffern: ${provider.phoneBufferSeconds.toStringAsFixed(1)}s / Ziel: ${provider.targetDelaySeconds.toStringAsFixed(1)}s)...'
                        : 'Puffer: ${provider.phoneBufferSeconds.toStringAsFixed(1)}s (Ziel: ${provider.targetDelaySeconds.toStringAsFixed(1)}s)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                if (provider.hasRecentOutOfOrderEvent)
                  Tooltip(
                    message: 'Reihenfolge-Anpassung erfolgte (${provider.ttsOutOfOrderEvents})',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.alt_route, size: 16, color: Colors.orange.shade800),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (provider.phoneBufferSeconds / provider.targetDelaySeconds).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.blue.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  provider.isPreRolling
                      ? Colors.orange
                      : (provider.phoneBufferSeconds >= provider.targetDelaySeconds
                          ? Colors.blue.shade700
                          : Colors.lightBlue),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Latenz: Übersetzung ${provider.translationLatencySeconds.toStringAsFixed(2)}s  •  TTS ${provider.ttsLatencySeconds.toStringAsFixed(2)}s${provider.lastLateFragmentDelaySeconds > 0 ? ' (${provider.lastLateFragmentDelaySeconds.toStringAsFixed(2)}s)' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcriptBox(TranslationProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        reverse: true, // Auto-scroll to bottom on new text
        child: Text(
          provider.targetTranscript.isEmpty
              ? 'Die übersetzten Sätze erscheinen hier live während des Vortrags...'
              : provider.targetTranscript,
          style: TextStyle(
            fontSize: 18,
            height: 1.4,
            color: provider.targetTranscript.isEmpty ? Colors.grey : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _sourceTranscriptTile(TranslationProvider provider) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'Erkannter Quelltext – Diagnose',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
      children: [
        Container(
          width: double.infinity,
          height: 100,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              provider.sourceTranscript.isEmpty
                  ? 'Hier erscheint der vom Modell erkannte Originaltext...'
                  : provider.sourceTranscript,
              style: TextStyle(
                fontSize: 14,
                color: provider.sourceTranscript.isEmpty ? Colors.grey : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
