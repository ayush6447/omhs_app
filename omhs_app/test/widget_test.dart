import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/data/format.dart';
import 'package:omhs_app/device/protocol.dart';

void main() {
  group('protocol', () {
    test('parses state lines', () {
      final e = parseLine('STATE,MEASURE');
      expect(e, isA<PhaseEvent>());
      expect((e as PhaseEvent).phase, MeasurePhase.measuring);
    });

    test('parses currents and results', () {
      final i = parseLine('I,50.2,49.8\r\n') as CurrentEvent;
      expect(i.ch1, 50.2);
      expect(i.ch2, 49.8);
      final r = parseLine('RESULT,182.4,0.91') as ResultEvent;
      expect(r.mgdl, 182.4);
      expect(r.quality, 0.91);
    });

    test('ignores unknown or malformed lines', () {
      expect(parseLine('HELLO,3'), isNull);
      expect(parseLine('BTN,START'), isNull);
      expect(parseLine('P,abc'), isNull);
      expect(parseLine(''), isNull);
    });
  });

  group('format', () {
    test('categories', () {
      expect(categorize(199), CholCategory.desirable);
      expect(categorize(200), CholCategory.borderline);
      expect(categorize(240), CholCategory.high);
    });

    test('units', () {
      expect(formatChol(193.35, CholUnit.mgdl), '193');
      expect(formatChol(193.35, CholUnit.mmoll), '5.00');
    });
  });
}
