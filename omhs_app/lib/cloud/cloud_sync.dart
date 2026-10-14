import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reading.dart';
import '../data/readings_store.dart';
import '../data/user_profile.dart';
import 'account.dart';
import 'sync_plan.dart';

enum SyncStatus {
  /// Not signed in.
  off,
  syncing,
  synced,

  /// Changes are saved on the phone and go up when it's back online.
  waiting,
  error,
}

/// Keeps profiles and readings in the signed-in user's Firestore space:
///   users/{uid}/profiles/{profileId}   UserProfile JSON (+ photo, base64)
///   users/{uid}/readings/{readingId}   Reading JSON
///
/// A full sync (sign-in, app resume, "Sync now") reads both collections and
/// merges them three ways with what was last synced (see planSync), so
/// additions, edits and deletions on either phone come through. Local
/// changes are pushed a few seconds after they happen.
class CloudSync extends ChangeNotifier with WidgetsBindingObserver {
  CloudSync(this._account, this._profiles, this._readings, this._prefs) {
    _account.addListener(_onAccount);
    _profiles.addListener(_onLocalChange);
    _readings.addListener(_onLocalChange);
    WidgetsBinding.instance.addObserver(this);
    _onAccount();
  }

  final AccountService _account;
  final ProfileStore _profiles;
  final ReadingsStore _readings;
  final SharedPreferences _prefs;

  /// Firestore documents are capped at 1 MiB; bigger photos stay local.
  static const _maxPhotoBytes = 700 * 1024;
  static const _writeTimeout = Duration(seconds: 15);
  static const _pushDelay = Duration(seconds: 3);

  SyncStatus _status = SyncStatus.off;
  DateTime? _lastSynced;
  String? _error;
  String? _uid;
  bool _running = false;
  bool? _queued; // null: nothing queued; true: full sync; false: push
  bool _applying = false;
  Timer? _pushTimer;

  SyncStatus get status => _status;
  DateTime? get lastSynced => _lastSynced;
  String? get error => _error;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  void _onAccount() {
    final uid = _account.user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _pushTimer?.cancel();
    if (uid == null) {
      _status = SyncStatus.off;
      _error = null;
      notifyListeners();
      return;
    }
    final t = _prefs.getString(_key(uid, 'time'));
    _lastSynced = t == null ? null : DateTime.tryParse(t);
    syncNow();
  }

  void _onLocalChange() {
    if (_uid == null || _applying) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () => _run(full: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _uid != null) _run(full: true);
  }

  /// Full two-way sync.
  Future<void> syncNow() => _run(full: true);

  Future<void> _run({required bool full}) async {
    final uid = _uid;
    if (uid == null) return;
    if (_running) {
      _queued = (_queued ?? false) || full;
      return;
    }
    _running = true;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      final complete = full ? await _fullSync(uid) : await _push(uid);
      if (uid != _uid) return; // signed out meanwhile
      _error = null;
      _status = complete ? SyncStatus.synced : SyncStatus.waiting;
      if (complete) {
        _lastSynced = DateTime.now();
        await _prefs.setString(
            _key(uid, 'time'), _lastSynced!.toIso8601String());
      }
    } on FirebaseException catch (e) {
      debugPrint('Sync failed: ${e.code} ${e.message}');
      _status = e.code == 'unavailable' ? SyncStatus.waiting : SyncStatus.error;
      _error = switch (e.code) {
        'unavailable' => null,
        'permission-denied' => 'The cloud refused access. Sign out and in '
            'again; if it persists, check the Firestore rules.',
        _ => 'Sync failed (${e.code}). Try again later.',
      };
    } catch (e) {
      debugPrint('Sync failed: $e');
      _status = SyncStatus.error;
      _error = 'Sync failed. Try again later.';
    } finally {
      _running = false;
      notifyListeners();
      final next = _queued;
      _queued = null;
      if (next != null) unawaited(_run(full: next));
    }
  }

  // ---------------------------------------------------------------------
  // Full sync

  /// Returns false when the writes are queued offline.
  Future<bool> _fullSync(String uid) async {
    final user = _userDoc(uid);
    final remoteP = await _fetch(user.collection('profiles'));
    final remoteR = await _fetch(user.collection('readings'));
    final localP = await _localProfiles();
    final localR = _localReadings();
    final lastP = _loadHashes(uid, 'profiles');
    final lastR = _loadHashes(uid, 'readings');

    // First sync on a phone that only has the empty starter profile: take
    // the account's profiles instead of adding a blank one next to them.
    final dropLocal = <String>{};
    if (lastP.isEmpty && remoteP.isNotEmpty) {
      for (final p in _profiles.profiles) {
        if (p.isEmpty && _readings.forProfile(p.id).isEmpty) {
          dropLocal.add(p.id);
          localP.remove(p.id);
        }
      }
    }

    final planP = planSync(
        local: _hashes(localP), remote: _hashes(remoteP), last: lastP);
    final planR = planSync(
        local: _hashes(localR), remote: _hashes(remoteR), last: lastR);

    await _applyProfiles(planP, remoteP, dropLocal);
    _applyReadings(planR, remoteR);
    final complete = await _write(user, [
      (user.collection('profiles'), planP, localP),
      (user.collection('readings'), planR, localR),
    ]);
    await _saveHashes(uid, 'profiles', planP.synced);
    await _saveHashes(uid, 'readings', planR.synced);
    return complete;
  }

  Future<Map<String, Map<String, dynamic>>> _fetch(
      CollectionReference<Map<String, dynamic>> c) async {
    final snap = await c.get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  Future<void> _applyProfiles(SyncPlan plan,
      Map<String, Map<String, dynamic>> remote, Set<String> drop) async {
    if (!plan.changesLocal && drop.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    Future<UserProfile> fromCloud(String id) async {
      final json = Map<String, dynamic>.from(remote[id]!);
      final photo = json.remove('photo');
      final p = UserProfile.fromJson(json);
      if (photo is! String) return p.copyWith(photoPath: () => null);
      final path = '${dir.path}/profile_${stamp}_$id.jpg';
      await File(path).writeAsBytes(base64Decode(photo), flush: true);
      return p.copyWith(photoPath: () => path);
    }

    final next = <UserProfile>[];
    for (final p in _profiles.profiles) {
      if (drop.contains(p.id) || plan.deleteLocal.contains(p.id)) continue;
      next.add(plan.download.contains(p.id) ? await fromCloud(p.id) : p);
    }
    for (final id in plan.download) {
      if (_profiles.byId(id) == null) next.add(await fromCloud(id));
    }
    // Every reading belongs to a profile; never end up with none.
    if (next.isEmpty) return;
    _applying = true;
    try {
      await _profiles.replaceAll(next, _profiles.activeId);
    } finally {
      _applying = false;
    }
  }

  void _applyReadings(SyncPlan plan, Map<String, Map<String, dynamic>> remote) {
    if (!plan.changesLocal) return;
    final deleted = plan.deleteLocal.toSet();
    final downloaded = {
      for (final id in plan.download) id: Reading.fromJson(remote[id]!),
    };
    final next = [
      for (final r in _readings.all)
        if (!deleted.contains(r.id)) downloaded.remove(r.id) ?? r,
      ...downloaded.values,
    ];
    _applying = true;
    try {
      _readings.replaceAll(next);
    } finally {
      _applying = false;
    }
  }

  // ---------------------------------------------------------------------
  // Push

  Future<bool> _push(String uid) async {
    final user = _userDoc(uid);
    final localP = await _localProfiles();
    final localR = _localReadings();
    final planP =
        planPush(local: _hashes(localP), last: _loadHashes(uid, 'profiles'));
    final planR =
        planPush(local: _hashes(localR), last: _loadHashes(uid, 'readings'));
    final complete = await _write(user, [
      (user.collection('profiles'), planP, localP),
      (user.collection('readings'), planR, localR),
    ]);
    await _saveHashes(uid, 'profiles', planP.synced);
    await _saveHashes(uid, 'readings', planR.synced);
    return complete;
  }

  /// Uploads and deletes in batches. Firestore keeps the writes on the phone
  /// when offline and sends them later; that returns false after a timeout
  /// instead of waiting.
  Future<bool> _write(
      DocumentReference<Map<String, dynamic>> user,
      List<
              (
                CollectionReference<Map<String, dynamic>>,
                SyncPlan,
                Map<String, Map<String, dynamic>>
              )>
          work) async {
    final ops = <void Function(WriteBatch)>[];
    for (final (collection, plan, local) in work) {
      for (final id in plan.upload) {
        ops.add((b) => b.set(collection.doc(id), local[id]!));
      }
      for (final id in plan.deleteRemote) {
        ops.add((b) => b.delete(collection.doc(id)));
      }
    }
    if (ops.isEmpty) return true;
    final commits = <Future<void>>[];
    for (var i = 0; i < ops.length; i += 400) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(400)) {
        op(batch);
      }
      commits.add(batch.commit());
    }
    var complete = true;
    await Future.wait(commits).timeout(_writeTimeout, onTimeout: () {
      complete = false;
      return const [];
    });
    return complete;
  }

  // ---------------------------------------------------------------------
  // Local documents and hashes

  /// Photo inlined; the path is only meaningful on this phone.
  Future<Map<String, Map<String, dynamic>>> _localProfiles() async {
    final out = <String, Map<String, dynamic>>{};
    for (final p in _profiles.profiles) {
      final json = p.toJson()..remove('photoPath');
      final path = p.photoPath;
      if (path != null) {
        final f = File(path);
        if (await f.exists() && await f.length() <= _maxPhotoBytes) {
          json['photo'] = base64Encode(await f.readAsBytes());
        }
      }
      out[p.id] = json;
    }
    return out;
  }

  /// Sample readings from the simulated device never go to the cloud.
  Map<String, Map<String, dynamic>> _localReadings() => {
        for (final r in _readings.all)
          if (!r.id.startsWith('demo-')) r.id: r.toJson(),
      };

  static Map<String, String> _hashes(Map<String, Map<String, dynamic>> docs) =>
      {for (final e in docs.entries) e.key: docHash(e.value)};

  static String _key(String uid, String what) => 'sync.$uid.$what';

  Map<String, String> _loadHashes(String uid, String what) {
    final raw = _prefs.getString(_key(uid, what));
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveHashes(
          String uid, String what, Map<String, String> hashes) =>
      _prefs.setString(_key(uid, what), jsonEncode(hashes));

  // ---------------------------------------------------------------------

  /// Deletes everything this account stored in the cloud, then signs out.
  /// Data on this phone stays.
  Future<void> deleteCloudData() async {
    final uid = _uid;
    if (uid == null) return;
    final user = _userDoc(uid);
    for (final name in ['profiles', 'readings']) {
      final snap = await user.collection(name).get();
      for (var i = 0; i < snap.docs.length; i += 400) {
        final batch = _db.batch();
        for (final d in snap.docs.skip(i).take(400)) {
          batch.delete(d.reference);
        }
        await batch.commit().timeout(_writeTimeout);
      }
    }
    await user.delete().timeout(_writeTimeout);
    for (final what in ['profiles', 'readings', 'time']) {
      await _prefs.remove(_key(uid, what));
    }
    await _account.signOut();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    _account.removeListener(_onAccount);
    _profiles.removeListener(_onLocalChange);
    _readings.removeListener(_onLocalChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
