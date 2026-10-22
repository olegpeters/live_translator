import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  LogLevel? _selectedLevelFilter;
  String _searchQuery = '';
  bool _autoScrollToBottom = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    // Auto scroll to bottom after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _autoScrollToBottom) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  List<LogEntry> get _filteredLogs {
    return AppLogger.logs.where((entry) {
      if (_selectedLevelFilter != null && entry.level != _selectedLevelFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final msg = entry.message.toLowerCase();
        final tag = entry.tag.toLowerCase();
        final err = entry.error?.toString().toLowerCase() ?? '';
        return msg.contains(_searchQuery) ||
            tag.contains(_searchQuery) ||
            err.contains(_searchQuery);
      }
      return true;
    }).toList();
  }

  Future<void> _saveOrShareLogFile() async {
    final formattedText = AppLogger.exportFormattedLog();
    if (formattedText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Log-Einträge zum Speichern vorhanden.')),
        );
      }
      return;
    }

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'live_translator_log_$dateStr.txt';

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(formattedText);

      final xFile = XFile(file.path, mimeType: 'text/plain', name: fileName);
      final result = await Share.shareXFiles(
        [xFile],
        subject: 'Live Translator App Log ($fileName)',
        text: 'Live Translator Debugging-Protokoll',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.status == ShareResultStatus.success
                  ? 'Log-Datei erfolgreich exportiert ($fileName)'
                  : 'Log-Datei unter $filePath bereitgestellt',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern der Log-Datei: $e')),
        );
      }
    }
  }

  Future<void> _copyToClipboard() async {
    final text = AppLogger.exportFormattedLog();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gesamtes Log in die Zwischenablage kopiert.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log löschen?'),
        content: const Text(
          'Möchten Sie das aktuelle temporäre Sitzungsprotokoll wirklich löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              AppLogger.clear();
              Navigator.of(ctx).pop();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log-Einträge gelöscht.')),
              );
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey.shade700;
      case LogLevel.info:
        return Colors.blue.shade700;
      case LogLevel.warning:
        return Colors.orange.shade800;
      case LogLevel.error:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppLogger.logCountNotifier,
      builder: (context, count, _) {
        final logs = _filteredLogs;
        final totalCount = AppLogger.logs.length;

        return Scaffold(
          appBar: AppBar(
            title: Text('App-Logs ($totalCount)'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'In Zwischenablage kopieren',
                onPressed: logs.isEmpty ? null : _copyToClipboard,
              ),
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: 'Als Textdatei speichern / teilen',
                onPressed: logs.isEmpty ? null : _saveOrShareLogFile,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Log löschen',
                onPressed: totalCount == 0 ? null : _clearLogs,
              ),
            ],
          ),
          body: Column(
            children: [
              // Header Session Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Start: ${_formatTime(AppLogger.sessionStart)} • Total: $totalCount Einträge',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _autoScrollToBottom = !_autoScrollToBottom;
                        });
                        if (_autoScrollToBottom) _scrollToBottom();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Row(
                          children: [
                            Icon(
                              _autoScrollToBottom
                                  ? Icons.vertical_align_bottom
                                  : Icons.vertical_align_center,
                              size: 16,
                              color: _autoScrollToBottom ? Colors.green.shade700 : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-Scroll',
                              style: TextStyle(
                                fontSize: 11,
                                color: _autoScrollToBottom ? Colors.green.shade700 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),

              // Filter Controls
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Suchen (Text/Tag)...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<LogLevel?>(
                      value: _selectedLevelFilter,
                      hint: const Text('Level'),
                      isDense: true,
                      items: [
                        const DropdownMenuItem<LogLevel?>(
                          value: null,
                          child: Text('Alle Levels'),
                        ),
                        ...LogLevel.values.map((lvl) {
                          return DropdownMenuItem<LogLevel?>(
                            value: lvl,
                            child: Text(lvl.name.toUpperCase()),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedLevelFilter = val;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Logs List
              Expanded(
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          totalCount == 0
                              ? 'Keine Log-Einträge seit dem App-Start vorhanden.'
                              : 'Keine passenden Log-Einträge für Filter gefunden.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: logs.length,
                          separatorBuilder: (ctx, i) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = logs[index];
                            final color = _getLevelColor(entry.level);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: color, width: 0.8),
                                        ),
                                        child: Text(
                                          entry.levelString,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '[${entry.tag}]',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatTime(entry.timestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.message,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (entry.error != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Error: ${entry.error}',
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                  if (entry.stackTrace != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${entry.stackTrace}',
                                      style: TextStyle(
                                        color: Colors.red.shade900,
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                      ),
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),

              // Bottom Bar Action Buttons
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: totalCount == 0 ? null : _copyToClipboard,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Kopieren'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: totalCount == 0 ? null : _saveOrShareLogFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('Log als .txt speichern'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }
}
