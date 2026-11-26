import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
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
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppLocalizations.of(context).settings,
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        // Android 15+ draws edge to edge: keep content clear of the navigation bar.
        top: false,
        child: !_loaded
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
            : LayoutBuilder(
                // Low screens (small phones, landscape): the stage leaves too little room for the
                // transcript, so scroll with a fixed transcript height instead of overflowing.
                builder: (context, constraints) => constraints.maxHeight < _minExpandedHeight
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: _buildTranslator(expandTranscript: false),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: _buildTranslator(expandTranscript: true),
                      ),
              ),
      ),
    );
  }

  /// Below this body height the translator scrolls instead of stretching the transcript.
  static const double _minExpandedHeight = 600;

  Widget _buildTranslator({required bool expandTranscript}) {
    return Consumer<TranslationProvider>(
      builder: (context, provider, child) {
        final isTranslating = provider.isTranslating;
        final transcript = _transcriptCard(provider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expandTranscript ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Center(child: _languagePill(enabled: !isTranslating)),
            const SizedBox(height: 20),
            Center(child: _stage(provider)),
            const SizedBox(height: 14),
            Center(child: _statusPill(provider)),
            // Android asks only twice; after that the mic can only be allowed in the app settings.
            if (provider.status == TranslationStatus.micPermissionDenied) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(AppLocalizations.of(context).homeOpenAppSettings),
                ),
              ),
            ],
            if (_debugMode && isTranslating) ...[const SizedBox(height: 12), _bufferCard(provider)],
            const SizedBox(height: 20),
            if (expandTranscript) Expanded(child: transcript) else SizedBox(height: 200, child: transcript),
            // Debug: source text as recognized by the model
            if (_debugMode && provider.enableSourceTranscription) _sourceTranscriptTile(provider),
          ],
        );
      },
    );
  }

  /// "Automatisch → Russisch" as one pill; each half opens its language menu.
  /// Locked while translating (applies at the next start).
  Widget _languagePill({required bool enabled}) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget half({
      required String tooltip,
      required String value,
      required List<String> options,
      required String other,
      required ValueChanged<String> onSelected,
    }) {
      return PopupMenuButton<String>(
        tooltip: tooltip,
        enabled: enabled,
        initialValue: value,
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          // Translating into the spoken language makes no sense (Soniox passes it through untranslated).
          for (final code in options)
            PopupMenuItem(value: code, enabled: code != other, child: Text(languageName(l, code))),
        ],
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: scheme.shadow.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            languageName(l, value),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: scheme.onSurface),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: half(
              tooltip: l.homeSourceLanguage,
              value: _sourceLanguage,
              options: sourceLanguageCodes,
              other: _targetLanguage,
              onSelected: (code) {
                setState(() => _sourceLanguage = code);
                settingsRepository.setSourceLanguage(code);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded, size: 20, color: scheme.onSurfaceVariant),
          ),
          Flexible(
            child: half(
              tooltip: l.homeTargetLanguage,
              value: _targetLanguage,
              options: targetLanguageCodes,
              other: _sourceLanguage,
              onSelected: (code) {
                setState(() => _targetLanguage = code);
                settingsRepository.setTargetLanguage(code);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Big start/stop button with the microphone level as a ring around it. The ring sits
  /// outside the button, so the level stays visible while the button shows "stop".
  Widget _stage(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isTranslating = provider.isTranslating;
    const ringSize = 208.0;
    const buttonSize = 156.0;
    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Semantics(
            label: l.homeMicLevel,
            value: '${(provider.audioLevel * 100).round()} %',
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: provider.audioLevel.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 120),
              builder: (context, level, _) => CustomPaint(
                size: const Size.square(ringSize),
                painter: _LevelRingPainter(level: level, track: scheme.surfaceContainerHighest, clipping: scheme.error),
              ),
            ),
          ),
          Tooltip(
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
                child: Container(
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.brandGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.violet.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isTranslating ? Icons.stop_rounded : Icons.mic_rounded,
                      key: ValueKey(isTranslating),
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(AppLocalizations l, TranslationProvider provider) => switch (provider.status) {
    TranslationStatus.idle => l.statusIdle,
    TranslationStatus.connecting => l.statusConnecting,
    TranslationStatus.active => l.statusActive,
    TranslationStatus.finishing => l.statusFinishing,
    TranslationStatus.connectionError => l.statusConnectionError,
    TranslationStatus.reconnecting => l.statusReconnecting(
      provider.reconnectAttempt,
      TranslationProvider.maxReconnectAttempts,
    ),
    TranslationStatus.disconnected => l.statusDisconnected,
    TranslationStatus.checkingKey => l.statusCheckingKey,
    TranslationStatus.keyRejected => l.statusKeyRejected,
    TranslationStatus.noApiKey => l.statusNoApiKey,
    TranslationStatus.initializing => l.statusInitializing,
    TranslationStatus.startFailed => l.statusStartFailed(provider.statusError ?? ''),
    TranslationStatus.micPermissionDenied => l.statusMicPermissionDenied,
    TranslationStatus.stopping => l.statusStopping,
  };

  /// Status as a pill: live (with running time), error, or neutral.
  Widget _statusPill(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = provider.status;
    final live = provider.isTranslating && status == TranslationStatus.active;
    final error = const {
      TranslationStatus.connectionError,
      TranslationStatus.keyRejected,
      TranslationStatus.noApiKey,
      TranslationStatus.startFailed,
      TranslationStatus.micPermissionDenied,
    }.contains(status);
    final (background, foreground, dot) = live
        ? (scheme.primaryContainer, scheme.onPrimaryContainer, const Color(0xFFE5484D))
        : error
        ? (scheme.errorContainer, scheme.onErrorContainer, scheme.error)
        : (scheme.surfaceContainerHigh, scheme.onSurfaceVariant, scheme.outline);
    final since = provider.liveSince;
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: live && since != null
                ? _LiveTimer(
                    since: since,
                    builder: (elapsed) => Text(
                      '${_statusText(l, provider)} · $elapsed',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: foreground),
                    ),
                  )
                : Text(
                    _statusText(l, provider),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: foreground),
                  ),
          ),
        ],
      ),
    );
  }

  /// Reading aloud on/off, right at the text it reads (off by default; switchable while live).
  Widget _speechToggle(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final on = provider.speechEnabled;
    return Tooltip(
      message: on ? l.homeSpeechOnTooltip : l.homeSpeechOffTooltip,
      child: FilterChip(
        key: const ValueKey('speechToggle'),
        selected: on,
        showCheckmark: false,
        avatar: Icon(
          on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 18,
          color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
        label: Text(l.homeSpeechToggle, overflow: TextOverflow.ellipsis, maxLines: 1),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: on ? scheme.onPrimary : scheme.onSurface,
        ),
        selectedColor: scheme.primary,
        side: BorderSide(color: on ? scheme.primary : scheme.outline),
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        onSelected: provider.setSpeechEnabled,
      ),
    );
  }

  /// Translation in one uniform, readable style (no fading of older sentences).
  Widget _transcriptCard(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final empty = provider.targetTranscript.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.homeTranscriptTitle(languageName(l, _targetLanguage)),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _speechToggle(provider)),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: scheme.onSurfaceVariant,
                tooltip: l.homeClearText,
                onPressed: empty ? null : provider.clearTranscript,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              reverse: true, // Auto-scroll to the newest text
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                empty ? l.homeTranscriptPlaceholder : provider.targetTranscript,
                textDirection: !empty && rtlLanguageCodes.contains(_targetLanguage) ? TextDirection.rtl : null,
                style: TextStyle(fontSize: 19, height: 1.45, color: empty ? scheme.onSurfaceVariant : scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
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

  Widget _sourceTranscriptTile(TranslationProvider provider) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final empty = provider.sourceTranscript.isEmpty;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(l.homeSourceTranscriptTitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
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

/// Microphone level as a ring: track plus a brand-gradient arc from the top, clockwise;
/// the arc turns to [clipping] when the input is close to overdrive.
class _LevelRingPainter extends CustomPainter {
  _LevelRingPainter({required this.level, required this.track, required this.clipping});

  final double level;
  final Color track;
  final Color clipping;

  static const stroke = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (level <= 0.005) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (level > 0.8) {
      paint.color = clipping;
    } else {
      paint.shader = const SweepGradient(
        // ends on cyan again, so the round cap at the arc start does not pick up magenta
        colors: [AppTheme.cyan, AppTheme.electricBlue, AppTheme.violet, AppTheme.magenta, AppTheme.cyan],
        stops: [0.0, 0.35, 0.65, 0.92, 1.0],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    }
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * level, false, paint);
  }

  @override
  bool shouldRepaint(_LevelRingPainter old) => old.level != level || old.track != track || old.clipping != clipping;
}

/// Running time since [since], refreshed every second.
class _LiveTimer extends StatefulWidget {
  const _LiveTimer({required this.since, required this.builder});

  final DateTime since;
  final Widget Function(String elapsed) builder;

  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    String two(int v) => v.toString().padLeft(2, '0');
    return widget.builder('${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}');
  }
}
