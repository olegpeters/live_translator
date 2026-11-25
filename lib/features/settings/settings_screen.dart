import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/log_report.dart';
import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import 'log_viewer_screen.dart';
import 'soniox_region_info.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsRepository settingsRepository;

  const SettingsScreen({super.key, required this.settingsRepository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  String _selectedLanguage = 'ru';
  String _selectedVoice = SettingsRepository.defaultVoice;
  String _selectedTtsEngine = 'soniox';
  double _outputGain = SettingsRepository.defaultOutputGain;
  bool _enableSourceTranscription = false;
  String _voiceProcessingMode = 'auto';
  bool _micRecording = false;
  String _sourceLanguage = 'de';
  final _glossaryController = TextEditingController();
  bool _useGlossaryPreset = true;
  bool _isLoading = true;
  bool _isSaving = false;
  final _regionDetector = SonioxRegionDetector();
  SonioxRegion? _region;
  String _savedApiKey = '';

  final List<Map<String, String>> _languages = const [
    {'code': 'ru', 'name': 'Russisch (ru)'},
    {'code': 'en', 'name': 'Englisch (en)'},
    {'code': 'es', 'name': 'Spanisch (es)'},
    {'code': 'fr', 'name': 'Französisch (fr)'},
    {'code': 'uk', 'name': 'Ukrainisch (uk)'},
  ];

  final List<Map<String, String>> _voices = const [
    {'id': 'Daniel', 'name': 'Daniel (Männlich, Standard)'},
    {'id': 'Adrian', 'name': 'Adrian (Männlich)'},
    {'id': 'Bohdan', 'name': 'Bohdan (Männlich)'},
    {'id': 'Yana', 'name': 'Yana (Weiblich)'},
    {'id': 'Arabella', 'name': 'Arabella (Weiblich)'},
    {'id': 'Grace', 'name': 'Grace (Weiblich)'},
  ];

  final List<Map<String, String>> _ttsEngines = const [
    {'id': 'soniox', 'name': 'Soniox API (Cloud-Streaming)'},
    {'id': 'onboard', 'name': 'Onboard Android TTS (Lokal)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final apiKey = await widget.settingsRepository.getApiKey();
    final language = await widget.settingsRepository.getTargetLanguage();
    final voice = await widget.settingsRepository.getVoice();
    final ttsEngine = await widget.settingsRepository.getTtsEngine();
    final gain = await widget.settingsRepository.getOutputGain();
    final enableSourceTranscription =
        await widget.settingsRepository.getEnableSourceTranscription();
    final voiceProcessingMode = await widget.settingsRepository.getVoiceProcessingMode();
    final micRecording = await widget.settingsRepository.getMicRecording();
    final sourceLanguage = await widget.settingsRepository.getSourceLanguage();
    final glossary = await widget.settingsRepository.getGlossary();
    final useGlossaryPreset = await widget.settingsRepository.getUseGlossaryPreset();
    final region = SonioxRegion.fromCode(await widget.settingsRepository.getSonioxRegion());

    setState(() {
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
        _savedApiKey = apiKey.trim();
      }
      _region = region;
      _selectedLanguage = language;
      _selectedVoice = voice;
      _selectedTtsEngine = ttsEngine;
      _outputGain = gain;
      _enableSourceTranscription = enableSourceTranscription;
      _voiceProcessingMode = voiceProcessingMode;
      _micRecording = micRecording;
      _sourceLanguage = sourceLanguage;
      _glossaryController.text = glossary;
      _useGlossaryPreset = useGlossaryPreset;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final apiKey = _apiKeyController.text.trim();
    await widget.settingsRepository.setApiKey(apiKey);
    await widget.settingsRepository.setTargetLanguage(_selectedLanguage);
    await widget.settingsRepository.setVoice(_selectedVoice);
    await widget.settingsRepository.setTtsEngine(_selectedTtsEngine);
    await widget.settingsRepository.setOutputGain(_outputGain);
    await widget.settingsRepository.setVoiceProcessingMode(_voiceProcessingMode);
    await widget.settingsRepository.setMicRecording(_micRecording);
    await widget.settingsRepository.setSourceLanguage(_sourceLanguage);
    await widget.settingsRepository.setGlossary(_glossaryController.text);
    await widget.settingsRepository.setUseGlossaryPreset(_useGlossaryPreset);
    await widget.settingsRepository
        .setEnableSourceTranscription(_enableSourceTranscription);

    // Soniox keys only work in their project's region (default US, EU on request):
    // check a new key now instead of failing at the start of a talk.
    SonioxKeyCheck? check;
    if (apiKey.isEmpty) {
      await widget.settingsRepository.setSonioxRegion(null);
      _region = null;
    } else if (apiKey != _savedApiKey || _region == null) {
      check = await _regionDetector.detect(apiKey);
      // invalid / unknown: stored as "not detected", checked again at start
      await widget.settingsRepository.setSonioxRegion(check.region?.code);
      _region = check.region;
    }
    _savedApiKey = apiKey;

    if (!mounted) return;
    setState(() => _isSaving = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (check) {
      case SonioxKeyCheck.invalid:
        messenger.showSnackBar(const SnackBar(
          content: Text('Gespeichert, aber der API-Key wird von Soniox nicht akzeptiert. Bitte prüfen.'),
        ));
        return; // stay: the key needs fixing
      case SonioxKeyCheck.us:
        messenger.showSnackBar(const SnackBar(
          content: Text('Gespeichert. Der API-Key gehört zu einem Soniox-Projekt in den USA.'),
        ));
        return; // stay: show the region hint below the key
      case SonioxKeyCheck.unknown:
        messenger.showSnackBar(const SnackBar(
          content: Text('Gespeichert. Der API-Key konnte nicht geprüft werden (offline?); Prüfung beim Start.'),
        ));
      case SonioxKeyCheck.eu:
      case null:
        messenger.showSnackBar(
          const SnackBar(content: Text('Einstellungen erfolgreich gespeichert')),
        );
    }
    Navigator.of(context).pop();
  }

  Future<void> _reportBug() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await LogReport.share(bugReport: true);
      if (shared == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Noch keine Protokolleinträge vorhanden.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlerbericht konnte nicht erstellt werden: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Soniox API Konfiguration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'Soniox API Key',
                      hintText: 'Key...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureApiKey = !_obscureApiKey;
                          });
                        },
                      ),
                    ),
                  ),
                  if (_region != null) ...[
                    const SizedBox(height: 8),
                    SonioxRegionInfo(region: _region),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Übersetzungs-Einstellungen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _sourceLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Gesprochene Sprache (Quelle)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'de', child: Text('Deutsch (de)')),
                      DropdownMenuItem(value: 'en', child: Text('Englisch (en)')),
                      DropdownMenuItem(value: '', child: Text('Automatisch erkennen')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _sourceLanguage = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Zielsprache',
                      border: OutlineInputBorder(),
                    ),
                    items: _languages.map((lang) {
                      return DropdownMenuItem<String>(
                        value: lang['code'],
                        child: Text(lang['name']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedLanguage = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVoice,
                    decoration: const InputDecoration(
                      labelText: 'Soniox Stimme (TTS Voice)',
                      border: OutlineInputBorder(),
                    ),
                    items: _voices.map((voice) {
                      return DropdownMenuItem<String>(
                        value: voice['id'],
                        child: Text(voice['name']!),
                      );
                    }).toList(),
                    onChanged: _selectedTtsEngine == 'soniox'
                        ? (val) {
                            if (val != null) {
                              setState(() {
                                _selectedVoice = val;
                              });
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTtsEngine,
                    decoration: const InputDecoration(
                      labelText: 'TTS Engine (Sprachausgabe)',
                      border: OutlineInputBorder(),
                    ),
                    items: _ttsEngines.map((engine) {
                      return DropdownMenuItem<String>(
                        value: engine['id'],
                        child: Text(engine['name']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedTtsEngine = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Glossar-Preset „Predigt (Adventisten)“ verwenden'),
                    subtitle: const Text(
                      'Bibelbücher, Namen, adventistische Begriffe und Ellen-White-Buchtitel. '
                      'Wird mit dem Freitext-Glossar kombiniert; eigene Einträge haben Vorrang.',
                    ),
                    value: _useGlossaryPreset,
                    onChanged: (val) => setState(() => _useGlossaryPreset = val ?? false),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _glossaryController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Eigenes Glossar (Namen, Fachbegriffe)',
                      alignLabelWithHint: true,
                      hintText: 'Ein Eintrag pro Zeile, z. B.\nAaron\nAnbetung = поклонение',
                      helperText: 'Begriff = Erkennungshilfe; "Quelle = Ziel" legt die Übersetzung fest.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ausgabelautstärke / Audio-Verstärkung',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Verstärkungsfaktor:',
                        style: TextStyle(fontSize: 15),
                      ),
                      Text(
                        '${(_outputGain * 100).round()}% (${_outputGain == 1.0 ? 'Standard' : (_outputGain == 2.0 ? '2x Boost' : '${_outputGain.toStringAsFixed(1)}x')})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Slider(
                    value: _outputGain,
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    label: '${(_outputGain * 100).round()}%',
                    onChanged: (val) {
                      setState(() {
                        _outputGain = val;
                      });
                    },
                  ),
                  Text(
                    'Erhöht die digitale Lautstärke der gesprochenen Übersetzung (100% - 300%). Standard ist 200%.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _voiceProcessingMode,
                    decoration: const InputDecoration(
                      labelText: 'Sprachverarbeitung Mikrofon',
                      helperText: 'Echo-/Rauschunterdrückung. Mit Kopfhörern aus (sonst wird Sprache '
                          'während der Wiedergabe unterdrückt), mit Lautsprecher an.',
                      helperMaxLines: 3,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Automatisch (nach Kopfhörer)')),
                      DropdownMenuItem(value: 'on', child: Text('Immer an')),
                      DropdownMenuItem(value: 'off', child: Text('Immer aus')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _voiceProcessingMode = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Diagnose & Debugging',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Quelltext-Transkription (Deutsch)'),
                    subtitle: const Text(
                      'Erkennt und zeigt den deutschen Originaltext an. Nur für Debugging/Diagnose relevant. Standard: Deaktiviert.',
                    ),
                    value: _enableSourceTranscription,
                    onChanged: (val) {
                      setState(() {
                        _enableSourceTranscription = val;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  // Debug builds only: store builds never record microphone audio.
                  if (!kReleaseMode)
                    SwitchListTile(
                      title: const Text('Mikrofon-Mitschnitt'),
                      subtitle: const Text(
                        'Speichert das an Soniox gesendete Mikrofon-Audio der letzten Sitzung als WAV. '
                        'Wird beim Log-Export mitgeteilt. Nur zur Diagnose.',
                      ),
                      value: _micRecording,
                      onChanged: (val) => setState(() => _micRecording = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: AppLogger.logCountNotifier,
                    builder: (context, logCount, _) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.article_outlined),
                        title: Text('App-Logs / Protokoll ($logCount Einträge)'),
                        subtitle: const Text(
                          'Sitzungsprotokoll seit App-Start anzeigen, kopieren oder als .txt Datei auf dem Handy speichern.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LogViewerScreen(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Fehler melden'),
                    subtitle: Text(
                      'Schickt das technische Protokoll (ohne Audio und Vortragstext) per Mail an '
                      '${LogReport.supportEmail}. Du entscheidest im Teilen-Menü, ob und wie es gesendet wird.',
                    ),
                    onTap: _reportBug,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text(
                              'Speichern',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
