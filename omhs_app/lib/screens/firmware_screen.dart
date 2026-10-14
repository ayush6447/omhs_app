import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device/device_service.dart';
import '../device/firmware_update.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Pick a firmware file and send it to Board 1 or Board 5 over BLE.
class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const FirmwareScreen());

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  late final FirmwareUpdater _updater;
  FirmwareTarget _target = FirmwareTarget.board5;
  String? _fileName;
  Uint8List? _image;
  String? _crc;

  @override
  void initState() {
    super.initState();
    _updater = FirmwareUpdater(context.read<DeviceService>());
  }

  @override
  void dispose() {
    _updater.dispose(); // cancels a running update
    super.dispose();
  }

  String? get _fileProblem =>
      _image == null ? null : FirmwareUpdater.check(_target, _image!);

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked =
          await FilePicker.pickFile(dialogTitle: 'Choose a firmware file');
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _fileName = picked.name;
        _image = bytes;
        _crc = crc32(bytes).toRadixString(16).padLeft(8, '0');
      });
    } catch (e) {
      debugPrint('Picking firmware failed: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open that file.')));
    }
  }

  Future<void> _start() async {
    final image = _image;
    if (image == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update ${_target.label}?'),
        content: Text(
          '$_fileName (${_size(image.length)}) will be sent to the device. '
          'Keep the phone close and this screen open until it finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (ok == true) await _updater.run(_target, image);
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop the update?'),
        content: const Text('The device keeps its current firmware.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.omhs.danger),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final d = context.watch<DeviceService>();
    return ListenableBuilder(
      listenable: _updater,
      builder: (context, _) {
        final u = _updater;
        final running = u.isRunning;
        final problem = _fileProblem;
        final canStart = !running &&
            _image != null &&
            problem == null &&
            d.isConnected &&
            !d.isBusy;
        return PopScope(
          canPop: !running,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = Navigator.of(context);
            if (await _confirmLeave()) {
              u.cancel();
              nav.pop();
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
                children: [
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        RoundIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 14),
                        Text('Firmware', style: mono(26, color: c.text)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SoftCard(
                    child: Column(
                      children: [
                        KeyValueRow(
                            'Device',
                            PillBadge(d.isConnected ? 'Connected' : d.status.title,
                                bg: c.badge, fg: c.onBadge)),
                        Divider(height: 20, color: c.divider),
                        KeyValueRow(
                            'Installed',
                            PillBadge(d.firmware ?? '—',
                                bg: c.badge, fg: c.onBadge)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const SectionLabel('Board'),
                  IgnorePointer(
                    ignoring: running,
                    child: SegmentedPill<FirmwareTarget>(
                      values: const [FirmwareTarget.board5, FirmwareTarget.board1],
                      labels: const ['Board 5 · BLE', 'Board 1 · Teensy'],
                      selected: _target,
                      onChanged: (t) => setState(() => _target = t),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _target == FirmwareTarget.board5
                        ? 'The Bluetooth board restarts after the update; the '
                            'app reconnects on its own.'
                        : 'Board 5 passes the image on to the Teensy, which '
                            'restarts with it.',
                    style: TextStyle(fontSize: 12, color: c.muted, height: 1.4),
                  ),
                  const SizedBox(height: 26),
                  const SectionLabel('File'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_image == null)
                          Text('No file chosen.',
                              style: TextStyle(fontSize: 13, color: c.muted))
                        else ...[
                          Text(
                            _fileName ?? 'firmware',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.text),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_size(_image!.length)} · CRC $_crc',
                            style: mono(12,
                                weight: FontWeight.w400, color: c.muted),
                          ),
                        ],
                        if (problem != null) ...[
                          const SizedBox(height: 10),
                          Text(problem,
                              style: TextStyle(
                                  fontSize: 12, color: c.danger, height: 1.4)),
                        ],
                        const SizedBox(height: 14),
                        PillButton(
                          label: _image == null ? 'Choose file' : 'Choose another',
                          icon: Icons.folder_open_rounded,
                          variant: PillVariant.outline,
                          expand: true,
                          onPressed: running ? null : _pick,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (u.stage != UpdateStage.idle) ...[
                    _ProgressCard(updater: u),
                    const SizedBox(height: 20),
                  ],
                  if (running)
                    PillButton(
                      label: 'Cancel update',
                      icon: Icons.close_rounded,
                      expand: true,
                      onPressed: u.cancel,
                    )
                  else
                    PillButton(
                      label: u.stage == UpdateStage.failed
                          ? 'Try again'
                          : 'Update firmware',
                      icon: Icons.system_update_alt_rounded,
                      variant: PillVariant.primary,
                      expand: true,
                      onPressed: canStart ? _start : null,
                    ),
                  if (!running && !d.isConnected) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Connect the device to update it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ] else if (!running && d.isBusy) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Wait for the measurement to finish.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Only use files from the OMHS team. The device checks the '
                    'file before switching to it, so an interrupted update '
                    'leaves the current firmware in place.',
                    style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.updater});

  final FirmwareUpdater updater;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final u = updater;
    final (String title, Color color) = switch (u.stage) {
      UpdateStage.starting => ('Preparing the device…', c.primary),
      UpdateStage.sending => ('Sending…', c.primary),
      UpdateStage.verifying => ('Device is checking the file…', c.primary),
      UpdateStage.done => ('Update installed', c.ok),
      UpdateStage.failed => ('Update failed', c.danger),
      UpdateStage.idle => ('', c.primary),
    };
    final detail = switch (u.stage) {
      UpdateStage.done => u.target == FirmwareTarget.board5
          ? 'Board 5 is restarting. The app reconnects on its own and shows '
              'the new version.'
          : 'Board 1 is restarting with the new firmware.',
      UpdateStage.failed => u.error,
      _ => '${_size(u.sent)} of ${_size(u.total)}',
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              if (u.isRunning)
                Text('${(u.progress * 100).floor()}%',
                    style: mono(14, color: c.text)),
            ],
          ),
          if (u.isRunning) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: u.stage == UpdateStage.starting ? null : u.progress,
                minHeight: 8,
                color: c.primary,
                backgroundColor: c.ringTrack,
              ),
            ),
          ],
          if (detail != null) ...[
            const SizedBox(height: 10),
            Text(detail,
                style: TextStyle(fontSize: 12, color: c.muted, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// e.g. "812 KB" or "1.4 MB"
String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
