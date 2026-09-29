import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final settings = context.watch<AppSettings>();
    final d = context.watch<DeviceService>();

    Widget value(String v) => PillBadge(v, bg: c.badge, fg: c.onBadge);

    final status = switch (d.link) {
      LinkStatus.connected => 'Connected',
      LinkStatus.connecting => 'Connecting…',
      LinkStatus.disconnected => 'Not connected',
    };

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
        children: [
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Settings', style: mono(26, color: c.text)),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Appearance'),
          SegmentedPill<ThemeMode>(
            values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
            labels: const ['System', 'Light', 'Dark'],
            icons: const [
              Icons.brightness_auto_rounded,
              Icons.light_mode_rounded,
              Icons.dark_mode_rounded,
            ],
            selected: settings.themeMode,
            onChanged: settings.setThemeMode,
          ),
          const SizedBox(height: 26),
          const SectionLabel('Units'),
          SegmentedPill<CholUnit>(
            values: CholUnit.values,
            labels: const ['mg/dL', 'mmol/L'],
            selected: settings.unit,
            onChanged: settings.setUnit,
          ),
          const SizedBox(height: 26),
          const SectionLabel('Device'),
          SoftCard(
            child: Column(
              children: [
                KeyValueRow('Status', value(status)),
                Divider(height: 20, color: c.divider),
                KeyValueRow('Name', value(d.deviceName ?? '—')),
                Divider(height: 20, color: c.divider),
                KeyValueRow('Link', value('BLE · Board 5')),
                if (d.linkError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    d.linkError!,
                    style: TextStyle(fontSize: 12, color: c.danger, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                if (d.link == LinkStatus.connected)
                  PillButton(
                    label: 'Disconnect',
                    variant: PillVariant.outline,
                    expand: true,
                    onPressed: d.disconnect,
                  )
                else
                  PillButton(
                    label: 'Connect',
                    variant: PillVariant.primary,
                    expand: true,
                    onPressed:
                        d.link == LinkStatus.connecting ? null : d.connect,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('About'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyValueRow('App', value('OMHS v0.1.0')),
                const SizedBox(height: 12),
                Text(
                  'Research prototype. Readings are estimates collected for '
                  'calibration and are not a medical diagnosis.',
                  style: TextStyle(fontSize: 12, color: c.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
