import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import '../settings/soniox_region_info.dart';

/// First-run card on the home screen: asks for the Soniox API key, checks it
/// (region detection) on OK and only then saves it.
class ApiKeySetup extends StatefulWidget {
  const ApiKeySetup({
    super.key,
    required this.settingsRepository,
    required this.regionDetector,
    required this.onSaved,
  });

  final SettingsRepository settingsRepository;
  final SonioxRegionDetector regionDetector;
  final VoidCallback onSaved;

  static final signupUrl = Uri.parse('https://console.soniox.com/signup/');

  @override
  State<ApiKeySetup> createState() => _ApiKeySetupState();
}

class _ApiKeySetupState extends State<ApiKeySetup> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _controller.text.trim();
    if (key.isEmpty || _checking) return;
    FocusScope.of(context).unfocus();
    setState(() => _checking = true);

    final check = await widget.regionDetector.detect(key);
    if (!mounted) return;
    if (check == SonioxKeyCheck.invalid) {
      setState(() {
        _checking = false;
        _error = 'Soniox akzeptiert diesen API-Key nicht. Bitte prüfen.';
      });
      return;
    }

    await widget.settingsRepository.setApiKey(key);
    // unknown (offline): stored as "not detected", checked again at start
    await widget.settingsRepository.setSonioxRegion(check.region?.code);
    if (!mounted) return;
    setState(() => _checking = false);

    final messenger = ScaffoldMessenger.of(context);
    switch (check) {
      case SonioxKeyCheck.us:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('API-Key gespeichert'),
            content: const SonioxRegionInfo(region: SonioxRegion.us),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Verstanden')),
            ],
          ),
        );
      case SonioxKeyCheck.unknown:
        messenger.showSnackBar(const SnackBar(
          content: Text('API-Key gespeichert. Prüfung nicht möglich (offline?) – sie erfolgt beim Start.'),
        ));
      case SonioxKeyCheck.eu:
        messenger.showSnackBar(const SnackBar(content: Text('API-Key gespeichert · Region EU')));
      case SonioxKeyCheck.invalid:
        break; // handled above
    }
    widget.onSaved();
  }

  Future<void> _openSignup() async {
    final opened = await launchUrl(ApiKeySetup.signupUrl, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link konnte nicht geöffnet werden: ${ApiKeySetup.signupUrl}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Soniox-API-Key eintragen', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Auditorium nutzt Soniox für Spracherkennung, Übersetzung und Sprachausgabe. '
            'Trage deinen API-Key ein, um zu starten.',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  obscureText: true,
                  enabled: !_checking,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Soniox API-Key',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _checking || _controller.text.trim().isEmpty ? null : _submit,
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('OK'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openSignup,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Soniox-Konto erstellen'),
          ),
        ],
      ),
    );
  }
}
