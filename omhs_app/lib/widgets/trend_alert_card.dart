import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/trend_alerts.dart';
import '../theme/app_colors.dart';

/// What stands out about the latest reading: high, rising, a worse band, or
/// a signal too weak to trust. Shows nothing when there's nothing to say.
class TrendAlertCard extends StatelessWidget {
  const TrendAlertCard({super.key, required this.alerts, required this.unit});

  final List<TrendAlert> alerts;
  final CholUnit unit;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final c = context.omhs;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (alerts.first.serious ? c.danger : c.pink)
              .withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) Divider(height: 20, color: c.divider),
            _AlertRow(alerts[i], unit),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow(this.alert, this.unit);

  final TrendAlert alert;
  final CholUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final icon = switch (alert.kind) {
      AlertKind.lowQuality => Icons.signal_cellular_connected_no_internet_0_bar,
      AlertKind.high => Icons.warning_amber_rounded,
      AlertKind.worseCategory => Icons.arrow_upward_rounded,
      AlertKind.rising => Icons.trending_up_rounded,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: alert.serious ? c.danger : c.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.title(unit),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
              ),
              const SizedBox(height: 2),
              Text(
                alert.message(unit),
                style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
