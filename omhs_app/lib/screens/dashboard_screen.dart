import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/reading.dart';
import '../data/readings_store.dart';
import '../data/user_profile.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ring_gauge.dart';
import '../widgets/trend_chart.dart';
import 'profile_screen.dart';

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
    final profile = context.watch<ProfileStore>().profile;
    final ranges = rangesFor(profile.age);
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
              ProfileAvatar(onTap: () => showProfileSwitcher(context)),
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
                    CategoryBadge(categorize(latest.totalChol,
                        age: profile.ageAt(latest.time))),
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
          const SizedBox(height: 2),
          Center(
            child: Text(
              '${ranges.label} · desirable under '
              '${formatChol(ranges.borderlineFrom, unit)} ${unitLabel(unit)}',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ),
          const SizedBox(height: 24),
          _TrendCard(readings: store.items, unit: unit, ranges: ranges),
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

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.readings,
    required this.unit,
    required this.ranges,
  });

  final List<Reading> readings;
  final CholUnit unit;
  final CholRanges ranges;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  TrendSpan _span = TrendSpan.days90;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    const labels = {
      TrendSpan.days30: '30d',
      TrendSpan.days90: '90d',
      TrendSpan.all: 'All',
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Trend',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              for (final s in TrendSpan.values)
                Semantics(
                  button: true,
                  selected: s == _span,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _span = s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(
                        labels[s]!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              s == _span ? FontWeight.w700 : FontWeight.w500,
                          color: s == _span ? c.primary : c.muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TrendChart(
            readings: widget.readings,
            unit: widget.unit,
            ranges: widget.ranges,
            span: _span,
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
