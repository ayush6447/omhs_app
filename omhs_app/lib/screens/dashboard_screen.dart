import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/readings_store.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ring_gauge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenHistory,
    required this.onMeasure,
  });

  final VoidCallback onOpenHistory;
  final VoidCallback onMeasure;

  /// Ring shows where the reading sits on a 0-300 mg/dL scale.
  static const _ringMax = 300.0;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ReadingsStore>();
    final unit = context.watch<AppSettings>().unit;
    final latest = store.latest;
    final week =
        store.countSince(DateTime.now().subtract(const Duration(days: 7)));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
        children: [
          Row(
            children: [
              _TabLabel('Dashboard', selected: true, onTap: () {}),
              const SizedBox(width: 18),
              _TabLabel('History', selected: false, onTap: onOpenHistory),
              const Spacer(),
              const ThemeToggleButton(),
              const SizedBox(width: 10),
              const InitialsAvatar('AK'),
            ],
          ),
          const SizedBox(height: 16),
          const DeviceStatusChip(),
          const SizedBox(height: 22),
          Center(
            child: RingGauge(
              progress: latest == null ? 0 : latest.totalChol / _ringMax,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    latest == null ? '—' : formatChol(latest.totalChol, unit),
                    style: mono(36, color: c.text),
                  ),
                  Text(
                    unitLabel(unit),
                    style: mono(12, weight: FontWeight.w400, color: c.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total cholesterol',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  if (latest != null) ...[
                    const SizedBox(height: 8),
                    CategoryBadge(categorize(latest.totalChol)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              latest == null
                  ? 'No readings yet'
                  : 'Last reading · ${formatWhen(latest.time)}',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          const SizedBox(height: 24),
          MetricTile(
            label: 'Signal quality',
            value: latest == null ? '—' : '${(latest.quality * 100).round()}',
            suffix: '/ 100',
            fraction: latest?.quality ?? 0,
          ),
          const SizedBox(height: 16),
          MetricTile(
            label: 'Peak cuff pressure',
            value: latest == null ? '—' : latest.peakPressure.round().toString(),
            suffix: '/ 200 mmHg',
            fraction: (latest?.peakPressure ?? 0) / 200,
          ),
          const SizedBox(height: 16),
          MetricTile(
            label: 'Readings this week',
            value: '$week',
            suffix: '/ 7',
            fraction: week / 7,
          ),
          const SizedBox(height: 26),
          PillButton(
            label: 'New measurement',
            icon: Icons.play_arrow_rounded,
            variant: PillVariant.primary,
            expand: true,
            onPressed: onMeasure,
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Estimates from a research prototype, not a diagnosis.',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, {required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? c.primary : c.muted,
        ),
      ),
    );
  }
}

/// "● OMHS-v2 · Connected" with a Connect action when offline.
class DeviceStatusChip extends StatelessWidget {
  const DeviceStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final d = context.watch<DeviceService>();
    final (Color dot, String text) = switch (d.link) {
      LinkStatus.connected => (c.ok, '${d.deviceName ?? 'OMHS'} · Connected'),
      LinkStatus.connecting => (c.pink, 'Connecting…'),
      LinkStatus.disconnected => (c.muted, 'Device not connected'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: c.text),
            ),
          ),
          if (d.link == LinkStatus.disconnected)
            TextButton(onPressed: d.connect, child: const Text('Connect'))
          else
            const SizedBox(height: 40),
        ],
      ),
    );
  }
}
