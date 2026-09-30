import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/format.dart';
import '../data/readings_store.dart';
import '../data/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Lists every profile; tap one to make it active, or add a new one.
Future<void> showProfileSwitcher(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProfileSwitcher(),
    );

/// View and edit one profile. Every change is saved as it is made.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profileId});

  final String profileId;

  static Route<void> route(String profileId) => MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(profileId: profileId));

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  /// Centimetres, or feet in imperial.
  final _height = TextEditingController();

  /// Inches part of the height (imperial only).
  final _heightIn = TextEditingController();

  /// Kilograms or pounds.
  final _weight = TextEditingController();

  /// Units the body fields currently show; null until first filled.
  BodyUnits? _units;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _doctorName;
  late final TextEditingController _doctorPhone;

  String get _id => widget.profileId;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileStore>().byId(_id) ?? UserProfile(id: _id);
    _name = TextEditingController(text: p.name);
    _emergencyName = TextEditingController(text: p.emergencyName);
    _emergencyPhone = TextEditingController(text: p.emergencyPhone);
    _doctorName = TextEditingController(text: p.doctorName);
    _doctorPhone = TextEditingController(text: p.doctorPhone);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _height,
      _heightIn,
      _weight,
      _emergencyName,
      _emergencyPhone,
      _doctorName,
      _doctorPhone,
    ]) {
      c.dispose();
    }
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final units = Provider.of<AppSettings>(context).bodyUnits;
    if (units == _units) return;
    _units = units;
    final p = context.read<ProfileStore>().byId(_id);
    final h = p?.heightCm, w = p?.weightKg;
    if (units == BodyUnits.metric) {
      _height.text = _num(h);
      _heightIn.text = '';
      _weight.text = _num(w);
    } else {
      final inches = h == null ? null : (h / kCmPerInch).round();
      _height.text = inches == null ? '' : '${inches ~/ 12}';
      _heightIn.text = inches == null ? '' : '${inches % 12}';
      _weight.text = w == null ? '' : '${(w / kKgPerLb).round()}';
    }
  }

  bool get _imperial => _units == BodyUnits.imperial;

  /// Height typed into the fields, in cm; null when empty or implausible.
  double? get _typedHeightCm {
    if (!_imperial) return _parse(_height.text, 50, 250);
    final ft = _parse(_height.text, 1, 8);
    final inch =
        _heightIn.text.trim().isEmpty ? 0.0 : _parse(_heightIn.text, 0, 11.99);
    if (ft == null || inch == null) return null;
    final cm = (ft * 12 + inch) * kCmPerInch;
    return cm >= 50 && cm <= 250 ? cm : null;
  }

  bool get _heightInvalid =>
      (_height.text.trim().isNotEmpty || _heightIn.text.trim().isNotEmpty) &&
      _typedHeightCm == null;

  /// Weight typed into the field, in kg; null when empty or implausible.
  double? get _typedWeightKg {
    if (!_imperial) return _parse(_weight.text, 2, 400);
    final lb = _parse(_weight.text, 5, 880);
    return lb == null ? null : lb * kKgPerLb;
  }

  void _saveHeight() =>
      _edit((p) => p.copyWith(heightCm: () => _typedHeightCm));

  void _saveWeight() =>
      _edit((p) => p.copyWith(weightKg: () => _typedWeightKg));

  Future<void> _edit(UserProfile Function(UserProfile) change) =>
      context.read<ProfileStore>().update(change, id: _id);

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickBirthDate(UserProfile p) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: p.birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Date of birth',
    );
    if (picked != null) await _edit((p) => p.copyWith(birthDate: () => picked));
  }

  Future<void> _changePhoto(UserProfile p) async {
    final store = context.read<ProfileStore>();
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
              if (p.photoPath != null)
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
      await store.removePhoto(id: _id);
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
      if (file != null) await store.setPhoto(File(file.path), id: _id);
    } on PlatformException catch (e) {
      if (!mounted) return;
      _snack(e.code.contains('denied')
          ? 'Permission denied. Allow access in system settings.'
          : 'Could not load photo.');
    }
  }

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) _snack('Could not start a call on this device.');
  }

  Future<void> _delete(UserProfile p) async {
    final name = p.name.trim().isEmpty ? 'this profile' : p.name.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
            'Their details and readings will be removed from this device.'),
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
    if (confirmed != true || !mounted) return;
    final readings = context.read<ReadingsStore>();
    final store = context.read<ProfileStore>();
    Navigator.of(context).pop();
    await store.remove(_id);
    readings.removeForProfile(_id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ProfileStore>();
    final p = store.byId(_id);
    // Deleted while this screen was closing.
    if (p == null) return const Scaffold();

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
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 14),
                  Text('Profile', style: mono(26, color: c.text)),
                  const Spacer(),
                  if (store.activeId != _id)
                    TextButton(
                      onPressed: () => store.switchTo(_id),
                      child: const Text('Make active'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(
                      profile: p, size: 112, onTap: () => _changePhoto(p)),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: c.pink,
                      shape:
                          CircleBorder(side: BorderSide(color: c.bg, width: 3)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _changePhoto(p),
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
                style:
                    mono(20, color: p.name.trim().isEmpty ? c.muted : c.text),
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
                  AppTextField(
                    controller: _name,
                    label: 'Full name',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => _edit((p) => p.copyWith(name: v)),
                  ),
                  const SizedBox(height: 12),
                  AppTapField(
                    label: 'Date of birth',
                    value: p.birthDate == null
                        ? null
                        : '${formatDate(p.birthDate!)}  ·  ${p.age} yrs',
                    icon: Icons.cake_outlined,
                    onTap: () => _pickBirthDate(p),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedPill<Sex?>(
              values: Sex.values,
              labels: Sex.values.map(sexLabel).toList(),
              selected: p.sex,
              onChanged: (s) => _edit((p) => p.copyWith(sex: () => s)),
            ),
            const SizedBox(height: 10),
            Text(
              '${rangesFor(p.age).label} are used for this profile\'s readings.',
              style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Body'),
            SoftCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _height,
                          label: 'Height',
                          suffix: _imperial ? 'ft' : 'cm',
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true),
                          allow: RegExp(r'[0-9.,]'),
                          invalid: _heightInvalid,
                          onChanged: (_) => _saveHeight(),
                        ),
                      ),
                      if (_imperial) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppTextField(
                            controller: _heightIn,
                            label: '',
                            suffix: 'in',
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true),
                            allow: RegExp(r'[0-9.,]'),
                            invalid: _heightInvalid,
                            onChanged: (_) => _saveHeight(),
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: _weight,
                          label: 'Weight',
                          suffix: _imperial ? 'lb' : 'kg',
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true),
                          allow: RegExp(r'[0-9.,]'),
                          invalid: _weight.text.trim().isNotEmpty &&
                              _typedWeightKg == null,
                          onChanged: (_) => _saveWeight(),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 28, color: c.divider),
                  KeyValueRow(
                    'BMI',
                    PillBadge(
                      p.bmi == null
                          ? '—'
                          : '${p.bmi!.toStringAsFixed(1)} · ${_bmiLabel(p.bmi!)}',
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
                      (v) => _edit((p) => p.copyWith(smoker: v))),
                  _Toggle('Diabetes', p.diabetes,
                      (v) => _edit((p) => p.copyWith(diabetes: v))),
                  _Toggle('High blood pressure', p.hypertension,
                      (v) => _edit((p) => p.copyWith(hypertension: v))),
                  _Toggle('Taking cholesterol medication', p.onCholMeds,
                      (v) => _edit((p) => p.copyWith(onCholMeds: v)),
                      subtitle: 'e.g. statins'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Contacts'),
            _ContactCard(
              title: 'Emergency contact',
              icon: Icons.emergency_outlined,
              name: _emergencyName,
              phone: _emergencyPhone,
              onName: (v) => _edit((p) => p.copyWith(emergencyName: v)),
              onPhone: (v) => _edit((p) => p.copyWith(emergencyPhone: v)),
              onCall: p.emergencyPhone.trim().isEmpty
                  ? null
                  : () => _call(p.emergencyPhone),
            ),
            const SizedBox(height: 14),
            _ContactCard(
              title: 'Doctor',
              icon: Icons.medical_services_outlined,
              name: _doctorName,
              phone: _doctorPhone,
              onName: (v) => _edit((p) => p.copyWith(doctorName: v)),
              onPhone: (v) => _edit((p) => p.copyWith(doctorPhone: v)),
              onCall: p.doctorPhone.trim().isEmpty
                  ? null
                  : () => _call(p.doctorPhone),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Stored only on this device. Used to put readings '
                    'in context.',
                    style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
                  ),
                ),
              ],
            ),
            if (store.profiles.length > 1) ...[
              const SizedBox(height: 26),
              PillButton(
                label: 'Delete profile',
                icon: Icons.delete_outline_rounded,
                variant: PillVariant.outline,
                outlineColor: c.danger,
                expand: true,
                onPressed: () => _delete(p),
              ),
            ],
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

class _ProfileSwitcher extends StatelessWidget {
  const _ProfileSwitcher();

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ProfileStore>();
    final nav = Navigator.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('Profiles', style: mono(20, color: c.text)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in store.profiles)
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        selected: p.id == store.activeId,
                        selectedTileColor: c.surfaceAlt,
                        leading: ProfileAvatar(profile: p),
                        title: Text(
                          p.name.trim().isEmpty ? 'Unnamed' : p.name.trim(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.text, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          [
                            if (p.age != null) '${p.age} yrs',
                            if (p.sex != null) sexLabel(p.sex!),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit',
                          icon: Icon(Icons.edit_outlined,
                              size: 20, color: c.muted),
                          onPressed: () {
                            nav.pop();
                            nav.push(ProfileScreen.route(p.id));
                          },
                        ),
                        onTap: () {
                          store.switchTo(p.id);
                          nav.pop();
                        },
                      ),
                  ],
                ),
              ),
              Divider(height: 16, color: c.divider),
              _SheetTile(Icons.person_add_alt_rounded, 'Add profile',
                  () async {
                nav.pop();
                final id = await store.add();
                nav.push(ProfileScreen.route(id));
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return ListTile(
      leading: Icon(icon, color: danger ? c.danger : c.primary),
      title: Text(label,
          style: TextStyle(
              color: danger ? c.danger : c.text, fontWeight: FontWeight.w500)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.title,
    required this.icon,
    required this.name,
    required this.phone,
    required this.onName,
    required this.onPhone,
    required this.onCall,
  });

  final String title;
  final IconData icon;
  final TextEditingController name;
  final TextEditingController phone;
  final ValueChanged<String> onName;
  final ValueChanged<String> onPhone;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              if (onCall != null)
                RoundIconButton(
                  icon: Icons.call_rounded,
                  tooltip: 'Call',
                  onTap: onCall!,
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: name,
            label: 'Name',
            textCapitalization: TextCapitalization.words,
            onChanged: onName,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: phone,
            label: 'Phone',
            keyboard: TextInputType.phone,
            allow: RegExp(r'[0-9+()\- ]'),
            onChanged: onPhone,
          ),
        ],
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
