import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/soniox_region.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/ui/app_theme.dart';
import '../settings/settings_screen.dart';
import 'api_key_setup.dart';
import 'languages.dart';
import 'translation_provider.dart';
import '../../l10n/app_localizations.dart';

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
  String _sourceLanguage = '';
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
      _sourceLanguage = sourceLanguageCodes.contains(source) ? source : '';
      _targetLanguage = targetLanguageCodes.contains(target) ? target : 'ru';
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
            tooltip: AppLocalizations.of(context).settings,
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
        final l = AppLocalizations.of(context);
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
                    l.homeTranscriptTitle(languageName(l, _targetLanguage)),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (provider.targetTranscript.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_all, size: 20),
                    tooltip: l.homeClearText,
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
    final l = AppLocalizations.of(context);
    DropdownButtonFormField<String> dropdown({
      required String label,
      required String value,
      required List<String> options,
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
        items: [for (final code in options) DropdownMenuItem(value: code, child: Text(languageName(l, code)))],
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
            label: l.homeSourceLanguage,
            value: _sourceLanguage,
            options: sourceLanguageCodes,
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
            label: l.homeTargetLanguage,
            value: _targetLanguage,
            options: targetLanguageCodes,
            onChanged: (code) {
              setState(() => _targetLanguage = code);
              settingsRepository.setTargetLanguage(code);
            },
          ),
        ),
      ],
    );
  }

  String _statusText(AppLocalizations l, TranslationProvider provider) => switch (provider.status) {
        TranslationStatus.idle => l.statusIdle,
        TranslationStatus.connecting => l.statusConnecting,
        TranslationStatus.active => l.statusActive,
        TranslationStatus.finishing => l.statusFinishing,
        TranslationStatus.connectionError => l.statusConnectionError,
        TranslationStatus.reconnecting =>
          l.statusReconnecting(provider.reconnectAttempt, TranslationProvider.maxReconnectAttempts),
        TranslationStatus.disconnected => l.statusDisconnected,
        TranslationStatus.checkingKey => l.statusCheckingKey,
        TranslationStatus.keyRejected => l.statusKeyRejected,
        TranslationStatus.noApiKey => l.statusNoApiKey,
        TranslationStatus.initializing => l.statusInitializing,
        TranslationStatus.startFailed => l.statusStartFailed(provider.statusError ?? ''),
        TranslationStatus.stopping => l.statusStopping,
      };

  Widget _statusCard(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isTranslating = provider.isTranslating;
    return Card(
      color: isTranslating ? scheme.primaryContainer : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isTranslating ? Icons.sensors : Icons.sensors_off,
              color: isTranslating ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.homeStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: isTranslating ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _statusText(l, provider),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isTranslating ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _startButton(provider),
          ],
        ),
      ),
    );
  }

  /// Round start/stop button: brand gradient (icon colors) to start, error color to stop.
  Widget _startButton(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isTranslating = provider.isTranslating;
    final glow = isTranslating ? scheme.error : AppTheme.violet;
    return Tooltip(
      message: isTranslating ? l.homeTapToStop : l.homeTapToStart,
      child: Semantics(
        button: true,
        label: isTranslating ? l.homeTapToStop : l.homeTapToStart,
        child: GestureDetector(
          onTap: () {
            if (isTranslating) {
              provider.stopTranslation();
            } else {
              provider.startTranslation();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTranslating ? scheme.error : null,
              gradient: isTranslating ? null : AppTheme.brandGradient,
              boxShadow: [
                BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 2),
              ],
            ),
            child: Icon(
              isTranslating ? Icons.stop_rounded : Icons.mic_rounded,
              color: isTranslating ? scheme.onError : Colors.white,
              size: 38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _levelBar(TranslationProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final level = provider.audioLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context).homeMicLevel,
              style: labelStyle.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('${(level * 100).toInt()}%', style: labelStyle),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: level,
            minHeight: 10,
            backgroundColor: scheme.surfaceContainerHighest,
            // clipping (very loud) in the error color, otherwise the brand accent
            valueColor: AlwaysStoppedAnimation<Color>(level > 0.8 ? scheme.error : scheme.primary),
          ),
        ),
      ],
    );
  }

  /// Debug mode: adaptive TTS buffer, playback speed and latencies.
  Widget _bufferCard(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final buffer = provider.phoneBufferSeconds.toStringAsFixed(1);
    final target = provider.targetDelaySeconds.toStringAsFixed(1);
    final late = provider.lastLateFragmentDelaySeconds;
    final speedUp = provider.currentPlaybackSpeed > 1.01;
    final onCard = scheme.onSecondaryContainer;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.graphic_eq, size: 20, color: onCard),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l.homeBufferTitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onCard),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: speedUp ? scheme.tertiaryContainer : scheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l.homeBufferTempo(provider.currentPlaybackSpeed.toStringAsFixed(2)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: speedUp ? scheme.onTertiaryContainer : onCard,
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
                    provider.isPreRolling ? l.homeBufferPrerolling(buffer, target) : l.homeBufferStatus(buffer, target),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: onCard),
                  ),
                ),
                if (provider.hasRecentOutOfOrderEvent)
                  Tooltip(
                    message: l.homeBufferReorder(provider.ttsOutOfOrderEvents),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.alt_route, size: 16, color: scheme.tertiary),
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
                backgroundColor: scheme.surface.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation<Color>(provider.isPreRolling ? scheme.tertiary : scheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.homeLatency(
                    provider.translationLatencySeconds.toStringAsFixed(2),
                    provider.ttsLatencySeconds.toStringAsFixed(2),
                  ) +
                  (late > 0 ? ' (${late.toStringAsFixed(2)}s)' : ''),
              style: TextStyle(fontSize: 11, color: onCard, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcriptBox(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final empty = provider.targetTranscript.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SingleChildScrollView(
        reverse: true, // Auto-scroll to bottom on new text
        child: Text(
          empty ? l.homeTranscriptPlaceholder : provider.targetTranscript,
          style: TextStyle(
            fontSize: 18,
            height: 1.45,
            color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _sourceTranscriptTile(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final empty = provider.sourceTranscript.isEmpty;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        l.homeSourceTranscriptTitle,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      ),
      children: [
        Container(
          width: double.infinity,
          height: 100,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              empty ? l.homeSourceTranscriptPlaceholder : provider.sourceTranscript,
              style: TextStyle(fontSize: 14, color: empty ? scheme.onSurfaceVariant : scheme.onSurface),
            ),
          ),
        ),
      ],
    );
  }
}
