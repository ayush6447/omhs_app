import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/user_profile.dart';
import '../device/device_service.dart';
import '../device/protocol.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ring_gauge.dart';

class MeasureScreen extends StatelessWidget {
  const MeasureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final d = context.watch<DeviceService>();
    final unit = context.watch<AppSettings>().unit;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
        children: [
          Row(
            children: [
              Text('Measure', style: mono(26, color: c.text)),
              const Spacer(),
              const ThemeToggleButton(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Place your finger in the probe and keep your hand still.',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 20),
          _LiveCard(d: d),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'LED 1200 nm',
                  value: d.ch1mA.toStringAsFixed(1),
                  suffix: 'mA',
                  fraction: d.ch1mA / 89,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricTile(
                  label: 'LED 1720 nm',
                  value: d.ch2mA.toStringAsFixed(1),
                  suffix: 'mA',
                  fraction: d.ch2mA / 89,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (d.link != LinkStatus.connected)
            PillButton(
              label: d.link == LinkStatus.connecting
                  ? 'Connecting…'
                  : 'Connect device',
              icon: Icons.bluetooth_rounded,
              variant: PillVariant.primary,
              expand: true,
              onPressed: d.link == LinkStatus.connecting ? null : d.connect,
            )
          else
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Start',
                    icon: Icons.play_arrow_rounded,
                    variant: PillVariant.primary,
                    expand: true,
                    onPressed: d.isBusy ? null : d.start,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: 'Stop',
                    icon: Icons.stop_rounded,
                    expand: true,
                    onPressed: d.isBusy ? d.stop : null,
                  ),
                ),
              ],
            ),
          if (d.linkError != null) ...[
            const SizedBox(height: 12),
            Text(
              d.linkError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.danger, height: 1.4),
            ),
          ],
          if (d.phase == MeasurePhase.done && d.lastResult != null) ...[
            const SizedBox(height: 20),
            _ResultCard(
              mgdl: d.lastResult!.totalChol,
              quality: d.lastResult!.quality,
              unit: unit,
            ),
          ],
          if (d.phase == MeasurePhase.error) ...[
            const SizedBox(height: 20),
            SoftCard(
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: c.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.error ?? 'Device error',
                      style: TextStyle(color: c.text, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Stop asks the device to deflate. It is not a safety cutoff: the '
            'device firmware enforces its own pressure and time limits.',
            style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

String _phaseTitle(MeasurePhase p, LinkStatus link) {
  if (link != LinkStatus.connected) return 'Not connected';
  return switch (p) {
    MeasurePhase.idle => 'Ready',
    MeasurePhase.inflating => 'Inflating cuff',
    MeasurePhase.holding => 'Holding',
    MeasurePhase.measuring => 'Measuring',
    MeasurePhase.deflating => 'Deflating',
    MeasurePhase.done => 'Done',
    MeasurePhase.error => 'Stopped',
  };
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.d});

  final DeviceService d;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    const white = Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: c.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _phaseTitle(d.phase, d.link),
                  style: mono(18, color: white),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(d.progress * 100).round()}%',
                  style: mono(12, color: white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          HeroRing(
            progress: d.progress,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.pressure.round().toString(),
                  style: mono(40, color: white),
                ),
                Text(
                  'mmHg',
                  style: mono(12,
                      weight: FontWeight.w400,
                      color: white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _PhaseSteps(phase: d.phase),
        ],
      ),
    );
  }
}

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.phase});

  final MeasurePhase phase;

  static const _steps = [
    (MeasurePhase.inflating, 'Inflate'),
    (MeasurePhase.holding, 'Hold'),
    (MeasurePhase.measuring, 'Measure'),
    (MeasurePhase.deflating, 'Deflate'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    const white = Colors.white;
    final current = _steps.indexWhere((s) => s.$1 == phase);
    final allDone = phase == MeasurePhase.done;
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Builder(builder: (context) {
              final active = i == current;
              final done = allDone || (current >= 0 && i < current);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? c.pink
                      : done
                          ? white.withValues(alpha: 0.22)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? c.pink
                        : white.withValues(alpha: done ? 0 : 0.3),
                  ),
                ),
                child: Text(
                  _steps[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? c.onPink : white,
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.mgdl,
    required this.quality,
    required this.unit,
  });

  final double mgdl;
  final double quality;
  final CholUnit unit;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result', style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatChol(mgdl, unit), style: mono(34, color: c.primary)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  unitLabel(unit),
                  style: mono(13, weight: FontWeight.w400, color: c.primary),
                ),
              ),
              const Spacer(),
              CategoryBadge(categorize(mgdl,
                  age: context.watch<ProfileStore>().profile.age)),
            ],
          ),
          Divider(height: 24, color: c.divider),
          KeyValueRow(
            'Signal quality',
            PillBadge('${(quality * 100).round()} / 100',
                bg: c.badge, fg: c.onBadge),
          ),
          const SizedBox(height: 10),
          Text(
            'Saved to history.',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}
