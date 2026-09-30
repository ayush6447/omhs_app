import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Shown once, before the dashboard: who is being measured. Age decides
/// which cholesterol ranges apply, so it's worth asking up front.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});

  /// Called after Continue or Skip.
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController();
  DateTime? _birthDate;
  Sex? _sex;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _finish({required bool save}) async {
    if (save) {
      await context.read<ProfileStore>().update((p) => p.copyWith(
            name: _name.text.trim(),
            birthDate: () => _birthDate,
            sex: () => _sex,
          ));
    }
    if (!mounted) return;
    await context.read<AppSettings>().markSetupDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final canContinue = _name.text.trim().isNotEmpty;
    final age = _birthDate == null
        ? null
        : UserProfile(id: '', birthDate: _birthDate).age;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text("Who's being\nmeasured?",
                style: mono(30, color: c.text, height: 1.2)),
            const SizedBox(height: 12),
            Text(
              'Age sets which cholesterol ranges apply. You can change this '
              'or add more people later in Settings.',
              style: TextStyle(fontSize: 13, color: c.muted, height: 1.45),
            ),
            const SizedBox(height: 28),
            AppTextField(
              controller: _name,
              label: 'Full name',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            AppTapField(
              label: 'Date of birth',
              value: _birthDate == null
                  ? null
                  : '${formatDate(_birthDate!)}  ·  $age yrs',
              icon: Icons.cake_outlined,
              onTap: _pickBirthDate,
            ),
            const SizedBox(height: 14),
            SegmentedPill<Sex?>(
              values: Sex.values,
              labels: Sex.values.map(sexLabel).toList(),
              selected: _sex,
              onChanged: (s) => setState(() => _sex = s),
            ),
            const SizedBox(height: 32),
            PillButton(
              label: 'Continue',
              variant: PillVariant.primary,
              expand: true,
              onPressed: canContinue ? () => _finish(save: true) : null,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _finish(save: false),
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
