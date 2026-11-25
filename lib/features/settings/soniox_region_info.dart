import 'package:flutter/material.dart';

import '../../core/network/soniox_region.dart';
import '../../l10n/app_localizations.dart';

/// Where Soniox processes audio and text for a checked API key's region, with the steps
/// to get EU processing for US projects. Shown only once a key is known to be valid.
class SonioxRegionInfo extends StatelessWidget {
  const SonioxRegionInfo({super.key, required this.region});

  final SonioxRegion region;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final (icon, color, text) = switch (region) {
      SonioxRegion.eu => (
          Icons.verified_user_outlined,
          scheme.secondaryContainer,
          l.regionEu,
        ),
      SonioxRegion.us => (
          Icons.public,
          scheme.tertiaryContainer,
          '${l.regionUs} ${l.regionEuHowTo}',
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
