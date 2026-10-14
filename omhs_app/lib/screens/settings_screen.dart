import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cloud/account.dart';
import '../cloud/cloud_sync.dart';
import '../data/backup.dart';
import '../data/export.dart';
import '../data/format.dart';
import '../data/notifications.dart';
import '../data/readings_store.dart';
import '../data/reminders.dart';
import '../data/user_profile.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'firmware_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final settings = context.watch<AppSettings>();
    final d = context.watch<DeviceService>();

    Widget value(String v) => PillBadge(v, bg: c.badge, fg: c.onBadge);

    final status = d.status;

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
          if (context.watch<AccountService>().available) ...[
            const SizedBox(height: 16),
            const SectionLabel('Account'),
            const _AccountCard(),
            const SizedBox(height: 10),
          ],
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
                KeyValueRow('Status',
                    value(d.isConnected ? 'Connected' : status.title)),
                Divider(height: 20, color: c.divider),
                KeyValueRow('Name', value(d.deviceName ?? '—')),
                Divider(height: 20, color: c.divider),
                KeyValueRow('Firmware', value(d.firmware ?? '—')),
                Divider(height: 20, color: c.divider),
                KeyValueRow('Link', value('BLE · Board 5')),
                if (status.detail != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    status.detail!,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: status.tone == StatusTone.problem
                            ? c.danger
                            : c.muted),
                  ),
                ],
                const SizedBox(height: 16),
                if (d.isConnected || d.isLinking)
                  PillButton(
                    label: d.isConnected ? 'Disconnect' : 'Cancel',
                    variant: PillVariant.outline,
                    expand: true,
                    onPressed: d.disconnect,
                  )
                else
                  PillButton(
                    label: status.actionLabel ?? 'Connect',
                    variant: PillVariant.primary,
                    expand: true,
                    onPressed: d.runStatusAction,
                  ),
                if (d.isConnected) ...[
                  const SizedBox(height: 10),
                  PillButton(
                    label: 'Update firmware',
                    icon: Icons.system_update_alt_rounded,
                    variant: PillVariant.outline,
                    expand: true,
                    onPressed: () =>
                        Navigator.of(context).push(FirmwareScreen.route()),
                  ),
                ],
                if (d.hasRememberedDevice) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: d.forgetDevice,
                      child: const Text('Forget this device'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('Reminders'),
          const _ReminderCard(),
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
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Restore failed. Try again or use another backup file.')));
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

/// Measurement reminder: on/off, daily or weekly, and the time.
class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  Future<void> _save(BuildContext context, ReminderSchedule next) async {
    final settings = context.read<AppSettings>();
    final notifications = context.read<NotificationService>();
    final messenger = ScaffoldMessenger.of(context);
    if (next.enabled && !settings.reminder.enabled) {
      if (!await notifications.requestPermission()) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Allow notifications for OMHS in system settings to get '
                'reminders.')));
        return;
      }
    }
    await settings.setReminder(next);
    await notifications.applyReminder(next);
  }

  Future<void> _pickTime(BuildContext context, ReminderSchedule r) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.hour, minute: r.minute),
    );
    if (t != null && context.mounted) {
      await _save(context, r.copyWith(hour: t.hour, minute: t.minute));
    }
  }

  Future<void> _pickDay(BuildContext context, ReminderSchedule r) async {
    final day = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Remind me on'),
        children: [
          for (var d = DateTime.monday; d <= DateTime.sunday; d++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Text(weekdayName(d),
                  style: TextStyle(
                      fontWeight: d == r.weekday ? FontWeight.w700 : null)),
            ),
        ],
      ),
    );
    if (day != null && context.mounted) {
      await _save(context, r.copyWith(weekday: day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final r = context.watch<AppSettings>().reminder;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Measurement reminder',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(r.enabled ? r.describe() : 'Off',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: r.enabled,
                onChanged: (on) => _save(context, r.copyWith(enabled: on)),
              ),
            ],
          ),
          if (r.enabled) ...[
            const SizedBox(height: 14),
            SegmentedPill<ReminderRepeat>(
              values: ReminderRepeat.values,
              labels: const ['Daily', 'Weekly'],
              selected: r.repeat,
              onChanged: (v) => _save(context, r.copyWith(repeat: v)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (r.repeat == ReminderRepeat.weekly) ...[
                  Expanded(
                    child: AppTapField(
                      label: 'Day',
                      value: weekdayName(r.weekday),
                      icon: Icons.event_rounded,
                      onTap: () => _pickDay(context, r),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: AppTapField(
                    label: 'Time',
                    value: TimeOfDay(hour: r.hour, minute: r.minute)
                        .format(context),
                    icon: Icons.schedule_rounded,
                    onTap: () => _pickTime(context, r),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'High, rising or weak-signal readings are pointed out on the '
            'Dashboard, and with a notification if the app is in the '
            'background.',
            style: TextStyle(fontSize: 12, color: c.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Google sign-in and cloud sync status.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  Future<void> _deleteCloud(BuildContext context) async {
    final sync = context.read<CloudSync>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your cloud copy?'),
        content: const Text(
            'Profiles and readings stored in your account are deleted and '
            'you are signed out. Everything on this phone stays.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.omhs.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sync.deleteCloudData();
      messenger.showSnackBar(
          const SnackBar(content: Text('Cloud copy deleted.')));
    } catch (e) {
      debugPrint('Deleting cloud data failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not delete. Check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final account = context.watch<AccountService>();
    final sync = context.watch<CloudSync>();
    final user = account.user;

    if (user == null) {
      return SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in to keep profiles and readings in your Google account '
              'and use them on another phone. Optional: the app works fully '
              'without it.',
              style: TextStyle(fontSize: 12, color: c.muted, height: 1.45),
            ),
            const SizedBox(height: 14),
            PillButton(
              label: account.busy ? 'Signing in…' : 'Sign in with Google',
              icon: Icons.account_circle_outlined,
              variant: PillVariant.primary,
              expand: true,
              onPressed: account.busy ? null : account.signInWithGoogle,
            ),
            if (account.error != null) ...[
              const SizedBox(height: 10),
              Text(account.error!,
                  style: TextStyle(fontSize: 12, color: c.danger)),
            ],
          ],
        ),
      );
    }

    final (String status, Color color) = switch (sync.status) {
      SyncStatus.syncing => ('Syncing…', c.muted),
      SyncStatus.synced => (
          sync.lastSynced == null
              ? 'Synced'
              : 'Synced ${_ago(sync.lastSynced!)}',
          c.ok
        ),
      SyncStatus.waiting => ('Saved on this phone; syncs when online', c.muted),
      SyncStatus.error => (sync.error ?? 'Sync failed', c.danger),
      SyncStatus.off => ('Not syncing', c.muted),
    };
    final photo = user.photoURL;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.primary,
                foregroundImage: photo == null ? null : NetworkImage(photo),
                child: Icon(Icons.person_rounded, color: c.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? user.email ?? 'Signed in',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                    if (user.email != null && user.displayName != null)
                      Text(user.email!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(status, style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Sync now',
                  icon: Icons.sync_rounded,
                  variant: PillVariant.outline,
                  expand: true,
                  onPressed: sync.status == SyncStatus.syncing
                      ? null
                      : sync.syncNow,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  variant: PillVariant.outline,
                  expand: true,
                  onPressed: account.signOut,
                ),
              ),
            ],
          ),
          Center(
            child: TextButton(
              onPressed: () => _deleteCloud(context),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: const Text('Delete cloud copy'),
            ),
          ),
        ],
      ),
    );
  }
}

/// e.g. "just now", "5 min ago", "3 h ago", "on 29 Sep"
String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return 'on ${formatShortDate(t)}';
}
