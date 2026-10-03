import 'package:flutter/material.dart';
import '../../core/storage/settings_repository.dart';

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
  String _selectedVoice = 'alloy';
  int _selectedSampleRate = 24000;
  bool _isLoading = true;

  final List<Map<String, String>> _voices = const [
    {'id': 'alloy', 'name': 'Alloy'},
    {'id': 'echo', 'name': 'Echo'},
    {'id': 'shimmer', 'name': 'Shimmer'},
    {'id': 'ash', 'name': 'Ash'},
    {'id': 'ballad', 'name': 'Ballad'},
    {'id': 'coral', 'name': 'Coral'},
    {'id': 'sage', 'name': 'Sage'},
    {'id': 'verse', 'name': 'Verse'},
  ];

  final List<Map<String, String>> _languages = const [
    {'code': 'ru', 'name': 'Russisch (ru)'},
    {'code': 'en', 'name': 'Englisch (en)'},
    {'code': 'es', 'name': 'Spanisch (es)'},
    {'code': 'fr', 'name': 'Französisch (fr)'},
    {'code': 'uk', 'name': 'Ukrainisch (uk)'},
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
    final sampleRate = await widget.settingsRepository.getSampleRate();

    setState(() {
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
      }
      _selectedLanguage = language;
      _selectedVoice = voice;
      _selectedSampleRate = sampleRate;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await widget.settingsRepository.setApiKey(_apiKeyController.text.trim());
    await widget.settingsRepository.setTargetLanguage(_selectedLanguage);
    await widget.settingsRepository.setVoice(_selectedVoice);
    await widget.settingsRepository.setSampleRate(_selectedSampleRate);

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
                    'OpenAI API Konfiguration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'OpenAI API Key',
                      hintText: 'sk-...',
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
                      labelText: 'Synthese-Stimme',
                      border: OutlineInputBorder(),
                    ),
                    items: _voices.map((v) {
                      return DropdownMenuItem<String>(
                        value: v['id'],
                        child: Text(v['name']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedVoice = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedSampleRate,
                    decoration: const InputDecoration(
                      labelText: 'Audio Sampling-Rate',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 24000,
                        child: Text('24 kHz (Standard OpenAI)'),
                      ),
                      DropdownMenuItem(
                        value: 16000,
                        child: Text('16 kHz'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSampleRate = val;
                        });
                      }
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
