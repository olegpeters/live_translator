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
  double _outputGain = SettingsRepository.defaultOutputGain;
  bool _isLoading = true;

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
    final gain = await widget.settingsRepository.getOutputGain();

    setState(() {
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
      }
      _selectedLanguage = language;
      _outputGain = gain;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await widget.settingsRepository.setApiKey(_apiKeyController.text.trim());
    await widget.settingsRepository.setTargetLanguage(_selectedLanguage);
    await widget.settingsRepository.setOutputGain(_outputGain);

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
