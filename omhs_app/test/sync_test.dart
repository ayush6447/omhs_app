import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/cloud/sync_plan.dart';
import 'package:omhs_app/data/reading.dart';

void main() {
  group('canonical json', () {
    test('field order and 182 vs 182.0 do not matter', () {
      expect(docHash({'a': 1, 'b': 'x', 'c': null}),
          docHash({'c': null, 'b': 'x', 'a': 1.0}));
      expect(docHash({'a': 1}), isNot(docHash({'a': 2})));
      expect(docHash({
        'm': {'y': 1, 'x': 2}
      }), docHash({
        'm': {'x': 2.0, 'y': 1}
      }));
    });

    test('a reading hashes the same after a cloud round trip', () {
      final r = Reading(
        id: '1',
        time: DateTime(2026, 10, 14, 9),
        totalChol: 182,
        quality: 0.9,
        ch1mA: 50,
        ch2mA: 49.5,
        peakPressure: 180,
      );
      // Firestore hands whole doubles back as they were, but keys in any
      // order; simulate that.
      final back = Map<String, dynamic>.fromEntries(
          r.toJson().entries.toList().reversed);
      expect(docHash(Reading.fromJson(back).toJson()), docHash(r.toJson()));
    });
  });

  group('planSync', () {
    SyncPlan plan(Map<String, String> l, Map<String, String> r,
            [Map<String, String> last = const {}]) =>
        planSync(local: l, remote: r, last: last);

    test('first sync merges both sides', () {
      final p = plan({'a': '1', 'b': '2'}, {'b': '2', 'c': '3'});
      expect(p.upload, ['a']);
      expect(p.download, ['c']);
      expect(p.deleteLocal, isEmpty);
      expect(p.deleteRemote, isEmpty);
      expect(p.synced, {'a': '1', 'b': '2', 'c': '3'});
    });

    test('edits flow the right way; this phone wins a conflict', () {
      const last = {'a': '1', 'b': '1', 'c': '1'};
      final p = plan({'a': '2', 'b': '1', 'c': '5'},
          {'a': '1', 'b': '3', 'c': '6'}, last);
      expect(p.upload, unorderedEquals(['a', 'c']));
      expect(p.download, ['b']);
      expect(p.synced, {'a': '2', 'b': '3', 'c': '5'});
    });

    test('deletions on either side are carried over', () {
      const last = {'a': '1', 'b': '1'};
      final p = plan({'b': '1'}, {'a': '1'}, last);
      expect(p.deleteRemote, ['a']); // deleted here
      expect(p.deleteLocal, ['b']); // deleted on the other phone
      expect(p.synced, isEmpty);
    });

    test('an edit beats a delete on the other side', () {
      const last = {'a': '1', 'b': '1'};
      final p = plan({'a': '2'}, {'b': '2'}, last);
      expect(p.upload, ['a']);
      expect(p.download, ['b']);
    });

    test('in sync: nothing to do', () {
      final p = plan({'a': '1'}, {'a': '1'}, {'a': '1'});
      expect(p.changesLocal || p.changesRemote, isFalse);
    });
  });

  test('planPush uploads changes and deletes removals', () {
    final p = planPush(
        local: {'a': '1', 'b': '2', 'c': '3'}, last: {'a': '1', 'b': '1', 'd': '1'});
    expect(p.upload, unorderedEquals(['b', 'c']));
    expect(p.deleteRemote, ['d']);
    expect(p.synced, {'a': '1', 'b': '2', 'c': '3'});
  });
}
