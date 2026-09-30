import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// View and edit the user's profile. Every change is saved as it is made.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ProfileScreen());

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _height;
  late final TextEditingController _weight;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileStore>().profile;
    _name = TextEditingController(text: p.name);
    _height = TextEditingController(text: _num(p.heightCm));
    _weight = TextEditingController(text: _num(p.weightKg));
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  /// Parses a measurement, returning null when empty or outside [min]..[max].
  static double? _parse(String s, double min, double max) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    if (v == null || v < min || v > max) return null;
    return v;
  }

  Future<void> _pickBirthDate() async {
    final store = context.read<ProfileStore>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: store.profile.birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Date of birth',
    );
    if (picked != null) await store.update((p) => p.copyWith(birthDate: () => picked));
  }

  Future<void> _changePhoto() async {
    final store = context.read<ProfileStore>();
    final hasPhoto = store.profile.photoPath != null;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTile(Icons.photo_camera_outlined, 'Take photo',
                  () => Navigator.pop(context, _PhotoAction.camera)),
              _SheetTile(Icons.photo_library_outlined, 'Choose from gallery',
                  () => Navigator.pop(context, _PhotoAction.gallery)),
              if (hasPhoto)
                _SheetTile(Icons.delete_outline_rounded, 'Remove photo',
                    () => Navigator.pop(context, _PhotoAction.remove),
                    danger: true),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    if (action == _PhotoAction.remove) {
      await store.removePhoto();
      return;
    }
    try {
      final file = await ImagePicker().pickImage(
        source: action == _PhotoAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file != null) await store.setPhoto(File(file.path));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.code.contains('denied')
            ? 'Permission denied. Allow access in system settings.'
            : 'Could not load photo.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ProfileStore>();
    final p = store.profile;

    final summary = [
      if (p.age != null) '${p.age} yrs',
      if (p.sex != null) sexLabel(p.sex!),
    ].join(' · ');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 14),
                  Text('Profile', style: mono(26, color: c.text)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(size: 112, onTap: _changePhoto),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: c.pink,
                      shape: CircleBorder(side: BorderSide(color: c.bg, width: 3)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _changePhoto,
                        child: Tooltip(
                          message: 'Change photo',
                          child: SizedBox.square(
                            dimension: 38,
                            child: Icon(Icons.photo_camera_rounded,
                                size: 18, color: c.onPink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                p.name.trim().isEmpty ? 'Your name' : p.name.trim(),
                style: mono(20, color: p.name.trim().isEmpty ? c.muted : c.text),
                textAlign: TextAlign.center,
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(summary,
                    style: TextStyle(fontSize: 13, color: c.muted)),
              ),
            ],
            const SizedBox(height: 28),
            const SectionLabel('Personal'),
            SoftCard(
              child: Column(
                children: [
                  _Field(
                    controller: _name,
                    label: 'Full name',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => store.update((p) => p.copyWith(name: v)),
                  ),
                  const SizedBox(height: 12),
                  _TapField(
                    label: 'Date of birth',
                    value: p.birthDate == null
                        ? null
                        : '${formatDate(p.birthDate!)}  ·  ${p.age} yrs',
                    icon: Icons.cake_outlined,
                    onTap: _pickBirthDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedPill<Sex?>(
              values: Sex.values,
              labels: Sex.values.map(sexLabel).toList(),
              selected: p.sex,
              onChanged: (s) => store.update((p) => p.copyWith(sex: () => s)),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Body'),
            SoftCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          controller: _height,
                          label: 'Height',
                          suffix: 'cm',
                          number: true,
                          invalid: _height.text.trim().isNotEmpty &&
                              _parse(_height.text, 50, 250) == null,
                          onChanged: (v) => store.update((p) => p.copyWith(
                              heightCm: () => _parse(v, 50, 250))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          controller: _weight,
                          label: 'Weight',
                          suffix: 'kg',
                          number: true,
                          invalid: _weight.text.trim().isNotEmpty &&
                              _parse(_weight.text, 2, 400) == null,
                          onChanged: (v) => store.update((p) => p.copyWith(
                              weightKg: () => _parse(v, 2, 400))),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 28, color: c.divider),
                  KeyValueRow(
                    'BMI',
                    p.bmi == null
                        ? PillBadge('—', bg: c.badge, fg: c.onBadge)
                        : PillBadge(
                            '${p.bmi!.toStringAsFixed(1)} · ${_bmiLabel(p.bmi!)}',
                            bg: c.badge,
                            fg: c.onBadge,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Health context'),
            SoftCard(
              padding: 8,
              child: Column(
                children: [
                  _Toggle('Smoker', p.smoker,
                      (v) => store.update((p) => p.copyWith(smoker: v))),
                  _Toggle('Diabetes', p.diabetes,
                      (v) => store.update((p) => p.copyWith(diabetes: v))),
                  _Toggle('High blood pressure', p.hypertension,
                      (v) => store.update((p) => p.copyWith(hypertension: v))),
                  _Toggle('Taking cholesterol medication', p.onCholMeds,
                      (v) => store.update((p) => p.copyWith(onCholMeds: v)),
                      subtitle: 'e.g. statins'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Stored only on this device. Used to put your readings '
                    'in context.',
                    style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _bmiLabel(double bmi) {
    if (bmi < 18.5) return 'Under';
    if (bmi < 25) return 'Healthy';
    if (bmi < 30) return 'Over';
    return 'Obese';
  }
}

enum _PhotoAction { camera, gallery, remove }

class _SheetTile extends StatelessWidget {
  const _SheetTile(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final fg = danger ? c.danger : c.text;
    return ListTile(
      leading: Icon(icon, color: danger ? c.danger : c.primary),
      title: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surfaceAlt,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 20, color: c.primary),
          ),
        ),
      ),
    );
  }
}

InputDecoration _decoration(BuildContext context, String label,
    {String? suffix, bool invalid = false}) {
  final c = context.omhs;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: 1.4),
      );
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    filled: true,
    fillColor: c.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: TextStyle(color: c.muted, fontSize: 13),
    floatingLabelStyle: TextStyle(color: invalid ? c.danger : c.primary),
    suffixStyle: mono(12, weight: FontWeight.w400, color: c.muted),
    enabledBorder: border(invalid ? c.danger : Colors.transparent),
    focusedBorder: border(invalid ? c.danger : c.primary),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.suffix,
    this.number = false,
    this.invalid = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? suffix;
  final bool number;
  final bool invalid;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        textInputAction: TextInputAction.done,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.name,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        style: TextStyle(
          fontSize: 15,
          color: context.omhs.text,
          fontFamily: number ? kMonoFont : null,
        ),
        decoration:
            _decoration(context, label, suffix: suffix, invalid: invalid),
      );
}

/// Looks like a field, opens a picker when tapped.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: _decoration(context, label).copyWith(
          suffixIcon: Icon(icon, size: 20, color: c.muted),
        ),
        child: value == null
            ? null
            : Text(value!, style: TextStyle(fontSize: 15, color: c.text)),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged, {this.subtitle});

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      activeTrackColor: c.primary,
      title: Text(label, style: TextStyle(fontSize: 14, color: c.text)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(fontSize: 12, color: c.muted)),
    );
  }
}
