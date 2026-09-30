import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup.dart';
import '../data/export.dart';
import '../data/format.dart';
import '../data/readings_store.dart';
import '../data/user_profile.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

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
          const SectionLabel('Profile'),
          const _ProfileCard(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showProfileSwitcher(context),
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text(context.watch<ProfileStore>().profiles.length > 1
                  ? 'Switch profile'
                  : 'Add another person'),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 10),
          SegmentedPill<BodyUnits>(
            values: BodyUnits.values,
            labels: const ['cm · kg', 'ft · lb'],
            selected: settings.bodyUnits,
            onChanged: settings.setBodyUnits,
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
          const SectionLabel('Backup'),
          const _BackupCard(),
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

/// Avatar, name and age; opens the full profile.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final p = context.watch<ProfileStore>().profile;
    final details = [
      if (p.age != null) '${p.age} yrs',
      if (p.sex != null) sexLabel(p.sex!),
    ].join(' · ');
    return Material(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(ProfileScreen.route(p.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const ProfileAvatar(size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.isEmpty ? 'Set up your profile' : p.name.trim(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.isEmpty
                          ? 'Photo, age and health details'
                          : (details.isEmpty ? 'Edit profile' : details),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Save everything to a file, or replace everything from one.
class _BackupCard extends StatelessWidget {
  const _BackupCard();

  Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final backup = await Backup.fromStores(
          context.read<ProfileStore>(), context.read<ReadingsStore>());
      final file = await backup.writeTemp();
      await shareFile(file, subject: 'OMHS backup');
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not create the backup.')));
      debugPrint('Backup failed: $e');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final profiles = context.read<ProfileStore>();
    final readings = context.read<ReadingsStore>();
    final Backup backup;
    try {
      final picked = await FilePicker.pickFile(dialogTitle: 'Choose a backup');
      if (picked == null) return;
      backup = Backup.decode(utf8.decode(await picked.readAsBytes()));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open that file.')));
      debugPrint('Restore failed: $e');
      return;
    }
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace data on this phone?'),
        content: Text(
          'Backup from ${formatWhen(backup.createdAt)}: '
          '${backup.profiles.length} profile(s), '
          '${backup.readings.length} reading(s).\n\n'
          'This replaces the ${profiles.profiles.length} profile(s) and '
          '${readings.all.length} reading(s) on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.omhs.danger),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await backup.restoreInto(profiles, readings);
      messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Restore failed. Try again or use another backup file.')));
      debugPrint('Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profiles, photos and readings in one file. Keep it in Drive or '
            'email, or use it to move to a new phone.',
            style: TextStyle(fontSize: 12, color: c.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Back up',
                  icon: Icons.cloud_upload_outlined,
                  variant: PillVariant.primary,
                  expand: true,
                  onPressed: () => _backup(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  label: 'Restore',
                  icon: Icons.settings_backup_restore_rounded,
                  variant: PillVariant.outline,
                  expand: true,
                  onPressed: () => _restore(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
