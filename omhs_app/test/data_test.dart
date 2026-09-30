import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/data/backup.dart';
import 'package:omhs_app/data/export.dart';
import 'package:omhs_app/data/format.dart';
import 'package:omhs_app/data/reading.dart';
import 'package:omhs_app/data/readings_store.dart';
import 'package:omhs_app/data/user_profile.dart';
import 'package:omhs_app/device/mock_device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reading _reading(String id, double mgdl, {DateTime? time}) => Reading(
      id: id,
      time: time ?? DateTime(2026, 9, 1, 9),
      totalChol: mgdl,
      quality: 0.9,
      ch1mA: 50,
      ch2mA: 49.5,
      peakPressure: 180,
      note: 'fasting, "quoted"',
    );

void main() {
  late Directory tmp;
  late ProfileStore profiles;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    profiles = await ProfileStore.load();
    tmp = await Directory.systemTemp.createTemp('omhs_test');
  });

  tearDown(() => tmp.delete(recursive: true));

  test('readings survive a restart', () async {
    final file = File('${tmp.path}/readings.json');
    final store = ReadingsStore(MockDeviceService(), profiles, file);
    store.add(_reading('a', 190));
    store.add(_reading('b', 210, time: DateTime(2026, 9, 2)));
    store.toggleFlag('a');
    await store.flush();

    final again = ReadingsStore(
        MockDeviceService(), profiles, file, await ReadingsStore.readFile(file));
    expect(again.items.map((r) => r.id), ['b', 'a']);
    expect(again.byId('a')!.flagged, isTrue);
    expect(again.byId('a')!.note, 'fasting, "quoted"');
    expect(again.byId('a')!.profileId, profiles.activeId);
  });

  test('a damaged history file is moved aside, not overwritten', () async {
    final file = File('${tmp.path}/readings.json')..writeAsStringSync('{oops');
    expect(await ReadingsStore.readFile(file), isEmpty);
    expect(file.existsSync(), isFalse);
    expect(tmp.listSync().single.path, contains('.corrupt-'));
  });

  test('each profile sees only its own readings', () async {
    final store = ReadingsStore(
        MockDeviceService(), profiles, File('${tmp.path}/r.json'));
    final first = profiles.activeId;
    store.add(_reading('a', 190));
    final second = await profiles.add();
    expect(store.items, isEmpty);
    store.add(_reading('b', 200));
    expect(store.items.single.profileId, second);
    await profiles.switchTo(first);
    expect(store.items.single.id, 'a');
    await store.flush();
  });

  test('backup round trip keeps profiles, photos and readings', () {
    final backup = Backup(
      createdAt: DateTime(2026, 9, 30, 10),
      activeId: 'p2',
      profiles: const [
        UserProfile(id: 'p1', name: 'A', photoPath: '/old/phone/a.jpg'),
        UserProfile(id: 'p2', name: 'B', doctorPhone: '123'),
      ],
      photos: {'p1': Uint8List.fromList([1, 2, 3])},
      readings: [_reading('a', 190).copyWith(profileId: 'p1')],
    );
    final back = Backup.decode(backup.encode());
    expect(back.activeId, 'p2');
    expect(back.profiles.map((p) => p.name), ['A', 'B']);
    expect(back.profiles.first.photoPath, isNull);
    expect(back.photos['p1'], [1, 2, 3]);
    expect(back.profiles[1].doctorPhone, '123');
    expect(back.readings.single.profileId, 'p1');
  });

  test('backup rejects other files', () {
    expect(() => Backup.decode('not json'), throwsFormatException);
    expect(() => Backup.decode('{"format":"other"}'), throwsFormatException);
    expect(
        () => Backup.decode(
            '{"format":"omhs-backup","version":1,"profiles":"x","readings":[]}'),
        throwsFormatException);
  });

  group('export', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final profile = UserProfile(
      id: 'p1',
      name: 'Asha Rao',
      birthDate: DateTime(2010, 1, 1),
      smoker: true,
    );
    final readings = [
      _reading('a', 165, time: DateTime(2026, 8, 1)),
      _reading('b', 185, time: DateTime(2026, 9, 1)),
    ];

    test('csv escapes notes and uses age-based categories', () {
      final csv = ReportExporter(profile, readings, CholUnit.mgdl).csvText();
      final lines = csv.split('\r\n');
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('2026-09-01'));
      // 185 mg/dL is borderline at 16 (desirable for an adult).
      expect(lines[1], contains(',Borderline,'));
      expect(lines[1], endsWith('"fasting, ""quoted"""'));
    });

    test('pdf builds', () async {
      final bytes =
          await ReportExporter(profile, readings, CholUnit.mmoll).pdfBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
