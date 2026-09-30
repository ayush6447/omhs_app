import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sex { female, male, other }

String sexLabel(Sex s) => switch (s) {
      Sex.female => 'Female',
      Sex.male => 'Male',
      Sex.other => 'Other',
    };

/// Who is being measured. Age, sex and risk factors put a cholesterol
/// reading in context, so they live alongside the basics.
@immutable
class UserProfile {
  const UserProfile({
    this.name = '',
    this.birthDate,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.photoPath,
    this.smoker = false,
    this.diabetes = false,
    this.hypertension = false,
    this.onCholMeds = false,
  });

  final String name;
  final DateTime? birthDate;
  final Sex? sex;
  final double? heightCm;
  final double? weightKg;

  /// Absolute path to a copy of the photo inside the app's documents dir.
  final String? photoPath;

  final bool smoker;
  final bool diabetes;
  final bool hypertension;

  /// Taking a statin or other lipid-lowering medication.
  final bool onCholMeds;

  bool get isEmpty => name.trim().isEmpty && birthDate == null;

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    var years = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      years--;
    }
    return years;
  }

  double? get bmi {
    final h = heightCm, w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  // Nullable fields use a wrapper so copyWith can clear them.
  UserProfile copyWith({
    String? name,
    ValueGetter<DateTime?>? birthDate,
    ValueGetter<Sex?>? sex,
    ValueGetter<double?>? heightCm,
    ValueGetter<double?>? weightKg,
    ValueGetter<String?>? photoPath,
    bool? smoker,
    bool? diabetes,
    bool? hypertension,
    bool? onCholMeds,
  }) =>
      UserProfile(
        name: name ?? this.name,
        birthDate: birthDate != null ? birthDate() : this.birthDate,
        sex: sex != null ? sex() : this.sex,
        heightCm: heightCm != null ? heightCm() : this.heightCm,
        weightKg: weightKg != null ? weightKg() : this.weightKg,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        smoker: smoker ?? this.smoker,
        diabetes: diabetes ?? this.diabetes,
        hypertension: hypertension ?? this.hypertension,
        onCholMeds: onCholMeds ?? this.onCholMeds,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'birthDate': birthDate?.toIso8601String(),
        'sex': sex?.name,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'photoPath': photoPath,
        'smoker': smoker,
        'diabetes': diabetes,
        'hypertension': hypertension,
        'onCholMeds': onCholMeds,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String? ?? '',
        birthDate: DateTime.tryParse(j['birthDate'] as String? ?? ''),
        sex: Sex.values.where((s) => s.name == j['sex']).firstOrNull,
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        photoPath: j['photoPath'] as String?,
        smoker: j['smoker'] as bool? ?? false,
        diabetes: j['diabetes'] as bool? ?? false,
        hypertension: j['hypertension'] as bool? ?? false,
        onCholMeds: j['onCholMeds'] as bool? ?? false,
      );
}

/// The device owner's profile, persisted on the device.
class ProfileStore extends ChangeNotifier {
  ProfileStore._(this._prefs, this._profile);

  static const _kProfile = 'userProfile';

  final SharedPreferences _prefs;
  UserProfile _profile;

  UserProfile get profile => _profile;

  static Future<ProfileStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var profile = const UserProfile();
    final raw = prefs.getString(_kProfile);
    if (raw != null) {
      try {
        profile = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on FormatException {
        // Corrupt entry; start fresh rather than crash on launch.
      }
    }
    // The photo may have been removed (e.g. app data partly cleared).
    final photo = profile.photoPath;
    if (photo != null && !File(photo).existsSync()) {
      profile = profile.copyWith(photoPath: () => null);
    }
    return ProfileStore._(prefs, profile);
  }

  Future<void> update(UserProfile Function(UserProfile) change) async {
    _profile = change(_profile);
    notifyListeners();
    await _prefs.setString(_kProfile, jsonEncode(_profile.toJson()));
  }

  /// Copies [source] into app storage (the picker's file is temporary)
  /// and makes it the profile photo.
  Future<void> setPhoto(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
    // Unique name so Image.file doesn't serve the previous photo from cache.
    final dest = '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await source.copy(dest);
    final old = _profile.photoPath;
    await update((p) => p.copyWith(photoPath: () => dest));
    _deleteQuietly(old);
  }

  Future<void> removePhoto() async {
    final old = _profile.photoPath;
    await update((p) => p.copyWith(photoPath: () => null));
    _deleteQuietly(old);
  }

  static void _deleteQuietly(String? path) {
    if (path == null) return;
    File(path).delete().ignore();
  }
}
