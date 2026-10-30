import 'package:flutter/material.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/settings_repository.dart';
import 'log_viewer_screen.dart';

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
  bool _isLoading = true;

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

    setState(() {
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
      }
      _selectedLanguage = language;
      _selectedVoice = voice;
      _selectedTtsEngine = ttsEngine;
      _outputGain = gain;
      _enableSourceTranscription = enableSourceTranscription;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await widget.settingsRepository.setApiKey(_apiKeyController.text.trim());
    await widget.settingsRepository.setTargetLanguage(_selectedLanguage);
    await widget.settingsRepository.setVoice(_selectedVoice);
    await widget.settingsRepository.setTtsEngine(_selectedTtsEngine);
    await widget.settingsRepository.setOutputGain(_outputGain);
    await widget.settingsRepository
        .setEnableSourceTranscription(_enableSourceTranscription);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen erfolgreich gespeichert')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
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
                  const SizedBox(height: 24),
                  const Text(
                    'Übersetzungs-Einstellungen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text(
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
