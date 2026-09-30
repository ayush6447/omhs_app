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

String newProfileId() => 'p${DateTime.now().microsecondsSinceEpoch}';

/// Who is being measured. Age, sex and risk factors put a cholesterol
/// reading in context, so they live alongside the basics.
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
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
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.doctorName = '',
    this.doctorPhone = '',
  });

  final String id;
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

  final String emergencyName;
  final String emergencyPhone;
  final String doctorName;
  final String doctorPhone;

  bool get isEmpty => name.trim().isEmpty && birthDate == null;

  int? get age => ageAt(DateTime.now());

  /// Age in completed years on [date], e.g. when a reading was taken.
  int? ageAt(DateTime date) {
    final b = birthDate;
    if (b == null) return null;
    var years = date.year - b.year;
    if (date.month < b.month || (date.month == b.month && date.day < b.day)) {
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
    String? emergencyName,
    String? emergencyPhone,
    String? doctorName,
    String? doctorPhone,
  }) =>
      UserProfile(
        id: id,
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
        emergencyName: emergencyName ?? this.emergencyName,
        emergencyPhone: emergencyPhone ?? this.emergencyPhone,
        doctorName: doctorName ?? this.doctorName,
        doctorPhone: doctorPhone ?? this.doctorPhone,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
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
        'emergencyName': emergencyName,
        'emergencyPhone': emergencyPhone,
        'doctorName': doctorName,
        'doctorPhone': doctorPhone,
      };

  /// Entries saved before profiles had ids get a fresh one.
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String? ?? newProfileId(),
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
        emergencyName: j['emergencyName'] as String? ?? '',
        emergencyPhone: j['emergencyPhone'] as String? ?? '',
        doctorName: j['doctorName'] as String? ?? '',
        doctorPhone: j['doctorPhone'] as String? ?? '',
      );
}

/// Everyone measured on this device (e.g. patients in a clinic), plus which
/// one is active. Persisted on the device.
class ProfileStore extends ChangeNotifier {
  ProfileStore._(this._prefs, this._profiles, this._activeId);

  static const _kProfiles = 'userProfiles';
  static const _kActive = 'activeProfileId';

  /// Single profile saved by earlier versions; migrated on load.
  static const _kLegacy = 'userProfile';

  final SharedPreferences _prefs;
  final List<UserProfile> _profiles;
  String _activeId;

  List<UserProfile> get profiles => List.unmodifiable(_profiles);

  String get activeId => _activeId;

  UserProfile get profile => byId(_activeId)!;

  UserProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  static Future<ProfileStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = <UserProfile>[];
    try {
      final raw = prefs.getString(_kProfiles);
      final legacy = prefs.getString(_kLegacy);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List<dynamic>) {
          profiles.add(UserProfile.fromJson(j as Map<String, dynamic>));
        }
      } else if (legacy != null) {
        profiles.add(
            UserProfile.fromJson(jsonDecode(legacy) as Map<String, dynamic>));
      }
    } on FormatException {
      // Corrupt entry; start fresh rather than crash on launch.
    }
    // A photo may have been removed (e.g. app data partly cleared).
    for (var i = 0; i < profiles.length; i++) {
      final photo = profiles[i].photoPath;
      if (photo != null && !File(photo).existsSync()) {
        profiles[i] = profiles[i].copyWith(photoPath: () => null);
      }
    }
    if (profiles.isEmpty) profiles.add(UserProfile(id: newProfileId()));
    var active = prefs.getString(_kActive);
    if (!profiles.any((p) => p.id == active)) active = profiles.first.id;

    final store = ProfileStore._(prefs, profiles, active!);
    await store._save();
    await prefs.remove(_kLegacy);
    return store;
  }

  Future<void> _save() async {
    await _prefs.setString(
        _kProfiles, jsonEncode([for (final p in _profiles) p.toJson()]));
    await _prefs.setString(_kActive, _activeId);
  }

  /// Changes profile [id], or the active one when omitted.
  Future<void> update(UserProfile Function(UserProfile) change,
      {String? id}) async {
    final i = _profiles.indexWhere((p) => p.id == (id ?? _activeId));
    if (i < 0) return;
    _profiles[i] = change(_profiles[i]);
    notifyListeners();
    await _save();
  }

  /// Adds a blank profile, makes it active and returns its id.
  Future<String> add() async {
    final p = UserProfile(id: newProfileId());
    _profiles.add(p);
    _activeId = p.id;
    notifyListeners();
    await _save();
    return p.id;
  }

  Future<void> switchTo(String id) async {
    if (id == _activeId || byId(id) == null) return;
    _activeId = id;
    notifyListeners();
    await _save();
  }

  /// Deletes a profile. The last one can't be removed.
  Future<void> remove(String id) async {
    if (_profiles.length < 2) return;
    final p = byId(id);
    if (p == null) return;
    _profiles.remove(p);
    if (_activeId == id) _activeId = _profiles.first.id;
    notifyListeners();
    await _save();
    _deleteQuietly(p.photoPath);
  }

  /// Copies [source] into app storage (the picker's file is temporary)
  /// and makes it the photo of profile [id], or the active one.
  Future<void> setPhoto(File source, {String? id}) async {
    final target = byId(id ?? _activeId);
    if (target == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
    // Unique name so Image.file doesn't serve the previous photo from cache.
    final dest =
        '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await source.copy(dest);
    await update((p) => p.copyWith(photoPath: () => dest), id: target.id);
    _deleteQuietly(target.photoPath);
  }

  Future<void> removePhoto({String? id}) async {
    final target = byId(id ?? _activeId);
    if (target == null) return;
    await update((p) => p.copyWith(photoPath: () => null), id: target.id);
    _deleteQuietly(target.photoPath);
  }

  static void _deleteQuietly(String? path) {
    if (path == null) return;
    File(path).delete().ignore();
  }
}
