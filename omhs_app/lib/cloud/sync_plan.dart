import 'dart:convert';

import '../data/checksum.dart';

/// Same text for the same data, whatever order Firestore returns fields in
/// and whether a whole number comes back as 182 or 182.0.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? v) => switch (v) {
      Map() => {
          for (final k in v.keys.map((k) => '$k').toList()..sort())
            k: _canonical(v[k]),
        },
      List() => [for (final e in v) _canonical(e)],
      num() => v.toDouble(),
      _ => v,
    };

/// Short fingerprint of one document, stored after each sync.
String docHash(Map<String, dynamic> doc) =>
    crc32(utf8.encode(canonicalJson(doc))).toRadixString(16);

/// What to do with one collection to bring this phone and the cloud level.
class SyncPlan {
  const SyncPlan({
    this.download = const [],
    this.upload = const [],
    this.deleteLocal = const [],
    this.deleteRemote = const [],
    this.synced = const {},
  });

  /// Copy the cloud version here.
  final List<String> download;

  /// Write this phone's version to the cloud.
  final List<String> upload;
  final List<String> deleteLocal;
  final List<String> deleteRemote;

  /// Each document's hash once the plan is carried out; the next sync's
  /// [last].
  final Map<String, String> synced;

  bool get changesLocal => download.isNotEmpty || deleteLocal.isNotEmpty;
  bool get changesRemote => upload.isNotEmpty || deleteRemote.isNotEmpty;
}

/// Three-way merge of one collection, by document id. [last] holds each
/// document's hash at the previous sync; it tells "deleted here" from
/// "added on another phone", and "changed here" from "changed there". When
/// both sides changed the same document, this phone wins.
SyncPlan planSync({
  required Map<String, String> local,
  required Map<String, String> remote,
  required Map<String, String> last,
}) {
  final download = <String>[];
  final upload = <String>[];
  final deleteLocal = <String>[];
  final deleteRemote = <String>[];
  final synced = <String, String>{};

  for (final id in {...local.keys, ...remote.keys}) {
    final l = local[id], r = remote[id], base = last[id];
    if (l != null && r != null) {
      if (l == r) {
        synced[id] = l;
      } else if (l == base) {
        download.add(id); // only the cloud changed
        synced[id] = r;
      } else {
        upload.add(id);
        synced[id] = l;
      }
    } else if (l != null) {
      if (base == null || l != base) {
        upload.add(id); // new here, or edited here after a delete there
        synced[id] = l;
      } else {
        deleteLocal.add(id); // deleted on another phone
      }
    } else if (r != null) {
      if (base == null || r != base) {
        download.add(id); // new there, or edited there after a delete here
        synced[id] = r;
      } else {
        deleteRemote.add(id); // deleted here
      }
    }
  }
  return SyncPlan(
    download: download,
    upload: upload,
    deleteLocal: deleteLocal,
    deleteRemote: deleteRemote,
    synced: synced,
  );
}

/// Push only, without reading the cloud: upload what changed here since
/// [last] and delete what was removed here.
SyncPlan planPush({
  required Map<String, String> local,
  required Map<String, String> last,
}) =>
    SyncPlan(
      upload: [
        for (final e in local.entries)
          if (last[e.key] != e.value) e.key,
      ],
      deleteRemote: [
        for (final id in last.keys)
          if (!local.containsKey(id)) id,
      ],
      synced: Map.of(local),
    );
