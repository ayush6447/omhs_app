import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'reading.dart';
import 'readings_store.dart';
import 'user_profile.dart';

/// Everything needed to move to a new phone: profiles (with photos) and
/// every reading, in one JSON file.
class Backup {
  const Backup({
    required this.createdAt,
    required this.activeId,
    required this.profiles,
    required this.photos,
    required this.readings,
  });

  static const _format = 'omhs-backup';
  static const _version = 1;

  final DateTime createdAt;
  final String activeId;

  /// Photo paths are meaningless on another device; see [photos].
  final List<UserProfile> profiles;

  /// Profile id -> photo bytes.
  final Map<String, Uint8List> photos;
  final List<Reading> readings;

  static Future<Backup> fromStores(
      ProfileStore profiles, ReadingsStore readings) async {
    final photos = <String, Uint8List>{};
    for (final p in profiles.profiles) {
      final path = p.photoPath;
      if (path != null && await File(path).exists()) {
        photos[p.id] = await File(path).readAsBytes();
      }
    }
    return Backup(
      createdAt: DateTime.now(),
      activeId: profiles.activeId,
      profiles: profiles.profiles,
      photos: photos,
      readings: readings.all,
    );
  }

  String encode() => jsonEncode({
        'format': _format,
        'version': _version,
        'createdAt': createdAt.toIso8601String(),
        'activeProfileId': activeId,
        'profiles': [
          for (final p in profiles)
            {
              ...p.toJson()..remove('photoPath'),
              if (photos[p.id] != null) 'photo': base64Encode(photos[p.id]!),
            },
        ],
        'readings': [for (final r in readings) r.toJson()],
      });

  /// Throws [FormatException] when [text] isn't an OMHS backup.
  static Backup decode(String text) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Not a backup file');
    }
    if (root is! Map<String, dynamic> || root['format'] != _format) {
      throw const FormatException('Not a backup file');
    }
    if ((root['version'] as int? ?? 0) > _version) {
      throw const FormatException('Made by a newer version of the app');
    }
    try {
      final profiles = <UserProfile>[];
      final photos = <String, Uint8List>{};
      for (final j in root['profiles'] as List<dynamic>) {
        final m = Map<String, dynamic>.from(j as Map)..remove('photoPath');
        final p = UserProfile.fromJson(m);
        profiles.add(p);
        if (m['photo'] is String) photos[p.id] = base64Decode(m['photo']);
      }
      if (profiles.isEmpty) throw const FormatException('No profiles');
      return Backup(
        createdAt: DateTime.parse(root['createdAt'] as String),
        activeId: root['activeProfileId'] as String? ?? profiles.first.id,
        profiles: profiles,
        photos: photos,
        readings: [
          for (final j in root['readings'] as List<dynamic>)
            Reading.fromJson(j as Map<String, dynamic>),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      // Wrong types inside an otherwise valid file.
      throw FormatException('Backup file is damaged ($e)');
    }
  }

  /// Writes the backup to a temporary file for sharing.
  Future<File> writeTemp() async {
    final dir = await getTemporaryDirectory();
    final d = createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final f = File('${dir.path}/OMHS_backup_${d.year}-${two(d.month)}-${two(d.day)}.json');
    await f.writeAsString(encode(), flush: true);
    return f;
  }

  /// Replaces everything on this device with the backup's contents.
  Future<void> restoreInto(ProfileStore profiles, ReadingsStore readings) async {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final restored = <UserProfile>[];
    for (final p in this.profiles) {
      final bytes = photos[p.id];
      if (bytes == null) {
        restored.add(p.copyWith(photoPath: () => null));
        continue;
      }
      final path = '${dir.path}/profile_${stamp}_${p.id}.jpg';
      await File(path).writeAsBytes(bytes, flush: true);
      restored.add(p.copyWith(photoPath: () => path));
    }
    await profiles.replaceAll(restored, activeId);
    readings.replaceAll(this.readings);
  }
}
