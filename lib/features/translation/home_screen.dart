import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_repository.dart';
import '../settings/settings_screen.dart';
import 'translation_provider.dart';

class HomeScreen extends StatelessWidget {
  final SettingsRepository settingsRepository;

  const HomeScreen({super.key, required this.settingsRepository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live-Übersetzung Gottesdienst'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    settingsRepository: settingsRepository,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<TranslationProvider>(
        builder: (context, provider, child) {
          final isTranslating = provider.isTranslating;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Status Card
                Card(
                  elevation: 2,
                  color: isTranslating
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          isTranslating
                              ? Icons.sensors
                              : Icons.sensors_off,
                          color: isTranslating ? Colors.green : Colors.grey,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                provider.statusMessage,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isTranslating
                                      ? Colors.green.shade900
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Audio Level Indicator (Input Volume Bar)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Eingangssignal (Mischpult / USB):',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '${(provider.audioLevel * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
                              : (provider.audioLevel > 0.4
                                  ? Colors.orange
                                  : Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Main Start / Stop Button
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (isTranslating) {
                        provider.stopTranslation();
                      } else {
                        provider.startTranslation();
                      }
                    },
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isTranslating ? Colors.red : Colors.deepPurple,
                        boxShadow: [
                          BoxShadow(
                            color: (isTranslating ? Colors.red : Colors.deepPurple)
                                .withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        isTranslating ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  isTranslating ? 'Tippen zum Stoppen' : 'Tippen zum Starten',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),

                const SizedBox(height: 24),

                // Live Transcript (Russian Subtitles)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live-Untertitel (Russisch):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (provider.targetTranscript.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 20),
                        tooltip: 'Untertitel leeren',
                        onPressed: provider.clearTranscript,
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: Container(
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
                            ? 'Die übersetzten Sätze erscheinen hier live während des Gottesdienstes...'
                            : provider.targetTranscript,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.4,
                          color: provider.targetTranscript.isEmpty
                              ? Colors.grey
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),

                // Debug: source text as recognized by the model
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Erkannter Quelltext (Deutsch) – Diagnose',
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
                              ? 'Hier erscheint der vom Modell erkannte deutsche Text...'
                              : provider.sourceTranscript,
                          style: TextStyle(
                            fontSize: 14,
                            color: provider.sourceTranscript.isEmpty
                                ? Colors.grey
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
