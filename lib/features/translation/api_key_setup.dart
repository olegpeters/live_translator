import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import '../settings/soniox_region_info.dart';

/// First-run card on the home screen: asks for the Soniox API key, checks it
/// (region detection) on OK and only then saves it. The result (region hint) stays
/// visible until the user confirms with "Verstanden", which calls [onDone].
class ApiKeySetup extends StatefulWidget {
  const ApiKeySetup({
    super.key,
    required this.settingsRepository,
    required this.regionDetector,
    required this.onDone,
  });

  final SettingsRepository settingsRepository;
  final SonioxRegionDetector regionDetector;
  final VoidCallback onDone;

  static final signupUrl = Uri.parse('https://console.soniox.com/signup/');

  @override
  State<ApiKeySetup> createState() => _ApiKeySetupState();
}

class _ApiKeySetupState extends State<ApiKeySetup> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  /// Set once the key is accepted (eu / us) or saved unchecked (unknown).
  SonioxKeyCheck? _result;

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
    setState(() {
      _checking = false;
      _result = check;
    });
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
    final result = _result;
    final done = result != null;
    final region = result?.region;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
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
                enabled: !_checking && !done,
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
                onPressed: _checking || done || _controller.text.trim().isEmpty ? null : _submit,
                child: _checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : done
                        ? const Icon(Icons.check)
                        : const Text('OK'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (done) ...[
          if (region != null)
            SonioxRegionInfo(region: region)
          else
            const Text(
              'API-Key gespeichert. Er konnte gerade nicht geprüft werden (offline?); '
              'die Prüfung erfolgt beim Start der Übersetzung.',
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: widget.onDone, child: const Text('Verstanden')),
        ] else
          OutlinedButton.icon(
            onPressed: _openSignup,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Soniox-Konto erstellen'),
          ),
      ],
    );
  }
}
