import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/log_report.dart';
import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import '../../l10n/app_localizations.dart';
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
  String _selectedVoice = SettingsRepository.defaultVoice;
  String _selectedTtsEngine = 'soniox';
  double _outputGain = SettingsRepository.defaultOutputGain;
  bool _enableSourceTranscription = false;
  String _voiceProcessingMode = 'auto';
  bool _micRecording = false;
  bool _debugMode = false;
  final _glossaryController = TextEditingController();
  bool _useGlossaryPreset = true;
  bool _isLoading = true;
  bool _isSaving = false;
  final _regionDetector = SonioxRegionDetector();
  SonioxRegion? _region;
  String _savedApiKey = '';

  /// Soniox voices: (id, female).
  static const _voices = [
    ('Daniel', false),
    ('Adrian', false),
    ('Bohdan', false),
    ('Yana', true),
    ('Arabella', true),
    ('Grace', true),
  ];

  String _voiceLabel(AppLocalizations l, String id, bool female) {
    if (female) return l.voiceFemale(id);
    return id == SettingsRepository.defaultVoice ? l.voiceMaleDefault(id) : l.voiceMale(id);
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final apiKey = await widget.settingsRepository.getApiKey();
    final voice = await widget.settingsRepository.getVoice();
    final debugMode = await widget.settingsRepository.getDebugMode();
    // Debug options: show the stored values even while debug mode is off.
    final ttsEngine = await widget.settingsRepository.getTtsEngine(raw: true);
    final gain = await widget.settingsRepository.getOutputGain();
    final enableSourceTranscription =
        await widget.settingsRepository.getEnableSourceTranscription(raw: true);
    final voiceProcessingMode = await widget.settingsRepository.getVoiceProcessingMode(raw: true);
    final micRecording = await widget.settingsRepository.getMicRecording(raw: true);
    final glossary = await widget.settingsRepository.getGlossary();
    final useGlossaryPreset = await widget.settingsRepository.getUseGlossaryPreset();
    final region = SonioxRegion.fromCode(await widget.settingsRepository.getSonioxRegion());

    setState(() {
      if (apiKey != null) {
        _apiKeyController.text = apiKey;
        _savedApiKey = apiKey.trim();
      }
      _region = region;
      _debugMode = debugMode;
      _selectedVoice = voice;
      _selectedTtsEngine = ttsEngine;
      _outputGain = gain;
      _enableSourceTranscription = enableSourceTranscription;
      _voiceProcessingMode = voiceProcessingMode;
      _micRecording = micRecording;
      _glossaryController.text = glossary;
      _useGlossaryPreset = useGlossaryPreset;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final apiKey = _apiKeyController.text.trim();
    await widget.settingsRepository.setApiKey(apiKey);
    await widget.settingsRepository.setDebugMode(_debugMode);
    await widget.settingsRepository.setVoice(_selectedVoice);
    await widget.settingsRepository.setTtsEngine(_selectedTtsEngine);
    await widget.settingsRepository.setOutputGain(_outputGain);
    await widget.settingsRepository.setVoiceProcessingMode(_voiceProcessingMode);
    await widget.settingsRepository.setMicRecording(_micRecording);
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
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (check) {
      case SonioxKeyCheck.invalid:
        messenger.showSnackBar(SnackBar(content: Text(l.settingsSavedKeyRejected)));
        return; // stay: the key needs fixing
      case SonioxKeyCheck.us:
        messenger.showSnackBar(SnackBar(content: Text(l.settingsSavedUs)));
        return; // stay: show the region hint below the key
      case SonioxKeyCheck.unknown:
        messenger.showSnackBar(SnackBar(content: Text(l.settingsSavedUnchecked)));
      case SonioxKeyCheck.eu:
      case null:
        messenger.showSnackBar(SnackBar(content: Text(l.settingsSaved)));
    }
    Navigator.of(context).pop();
  }

  Future<void> _reportBug() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await LogReport.share(
        subject: l.bugReportSubject,
        text: l.bugReportText(LogReport.supportEmail),
      );
      if (shared == null) {
        messenger.showSnackBar(SnackBar(content: Text(l.settingsNoLogEntries)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.settingsBugReportFailed(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const sectionStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
    return Scaffold(
      appBar: AppBar(
        // Back (top left) discards changes; save sits top right.
        title: Text(l.settings),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _isSaving || _isLoading ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(l.save),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.settingsSonioxAccess, style: sectionStyle),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: l.apiKeyLabel,
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
                    SonioxRegionInfo(region: _region!),
                  ],
                  const SizedBox(height: 24),
                  Text(l.settingsSpeechOutput, style: sectionStyle),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedVoice,
                    decoration: InputDecoration(
                      labelText: l.settingsVoice,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final (id, female) in _voices)
                        DropdownMenuItem(value: id, child: Text(_voiceLabel(l, id, female))),
                    ],
                    onChanged: _selectedTtsEngine == 'soniox' || !_debugMode
                        ? (val) {
                            if (val != null) {
                              setState(() {
                                _selectedVoice = val;
                              });
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 24),
                  Text(l.settingsGlossary, style: sectionStyle),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l.settingsGlossaryPreset),
                    subtitle: Text(l.settingsGlossaryPresetHint),
                    value: _useGlossaryPreset,
                    onChanged: (val) => setState(() => _useGlossaryPreset = val ?? false),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _glossaryController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l.settingsOwnGlossary,
                      alignLabelWithHint: true,
                      hintText: l.settingsOwnGlossaryHint,
                      helperText: l.settingsOwnGlossaryHelper,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(l.settingsVolume, style: sectionStyle),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.settingsGain, style: const TextStyle(fontSize: 15)),
                      Text(
                        '${(_outputGain * 100).round()}%',
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
                    l.settingsGainHint,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  Text(l.settingsHelp, style: sectionStyle),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(l.settingsReportBug),
                    subtitle: Text(l.settingsReportBugHint(LogReport.supportEmail)),
                    onTap: _reportBug,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.settingsDebugMode),
                    subtitle: Text(l.settingsDebugModeHint),
                    value: _debugMode,
                    onChanged: (val) => setState(() => _debugMode = val),
                  ),
                  if (_debugMode) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedTtsEngine,
                      decoration: InputDecoration(
                        labelText: l.settingsTtsEngine,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(value: 'soniox', child: Text(l.ttsEngineSoniox)),
                        DropdownMenuItem(value: 'onboard', child: Text(l.ttsEngineOnboard)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTtsEngine = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _voiceProcessingMode,
                      decoration: InputDecoration(
                        labelText: l.settingsVoiceProcessing,
                        helperText: l.settingsVoiceProcessingHint,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(value: 'auto', child: Text(l.voiceProcessingAuto)),
                        DropdownMenuItem(value: 'on', child: Text(l.voiceProcessingOn)),
                        DropdownMenuItem(value: 'off', child: Text(l.voiceProcessingOff)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _voiceProcessingMode = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: Text(l.settingsSourceTranscription),
                      subtitle: Text(l.settingsSourceTranscriptionHint),
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
                        title: Text(l.settingsMicRecording),
                        subtitle: Text(l.settingsMicRecordingHint),
                        value: _micRecording,
                        onChanged: (val) => setState(() => _micRecording = val),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ValueListenableBuilder<int>(
                      valueListenable: AppLogger.logCountNotifier,
                      builder: (context, logCount, _) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.article_outlined),
                          title: Text(l.settingsAppLogs(logCount)),
                          subtitle: Text(l.settingsAppLogsHint),
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
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
