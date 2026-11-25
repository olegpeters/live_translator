import 'package:flutter/material.dart';

import '../../core/network/soniox_region.dart';

/// Where Soniox processes audio and text for the given region, with the steps
/// to get EU processing for US projects. [region] null = general hint before a key is checked.
class SonioxRegionInfo extends StatelessWidget {
  const SonioxRegionInfo({super.key, required this.region});

  final SonioxRegion? region;

  static const _euHowTo = 'Für Verarbeitung in der EU: in der Soniox-Konsole unter „Security & compliance“ '
      'die EU-Region beantragen, ein Projekt in der EU-Region anlegen und dessen API-Key verwenden.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (region) {
      SonioxRegion.eu => (
          Icons.verified_user_outlined,
          scheme.secondaryContainer,
          'Region: EU – Audio und Texte werden in der EU verarbeitet.',
        ),
      SonioxRegion.us => (
          Icons.public,
          scheme.tertiaryContainer,
          'Region: USA – Audio und Texte werden in den USA verarbeitet. $_euHowTo',
        ),
      null => (
          Icons.info_outline,
          scheme.surfaceContainerHighest,
          'Soniox-Projekte liegen standardmäßig in der US-Region; Audio und Texte werden dann in den USA '
              'verarbeitet. $_euHowTo',
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
