import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'format.dart';
import 'reading.dart';
import 'user_profile.dart';

/// Shareable reports of one profile's readings.
class ReportExporter {
  ReportExporter(this.profile, List<Reading> readings, this.unit,
      {this.bodyUnits = BodyUnits.metric})
      : readings = [...readings]..sort((a, b) => b.time.compareTo(a.time));

  final UserProfile profile;

  /// Newest first.
  final List<Reading> readings;
  final CholUnit unit;
  final BodyUnits bodyUnits;

  String get _baseName {
    final who = profile.name.trim().isEmpty
        ? 'profile'
        : profile.name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final d = DateTime.now();
    return 'OMHS_${who}_${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  CholCategory _category(Reading r) =>
      categorize(r.totalChol, age: profile.ageAt(r.time));

  Future<File> _write(String ext, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$_baseName.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  // -------------------------------------------------------------------------
  // CSV

  /// One row per reading, both units, for spreadsheets and calibration work.
  Future<File> csv() =>
      // BOM so Excel opens non-English notes correctly.
      _write('csv', [0xEF, 0xBB, 0xBF, ...utf8.encode(csvText())]);

  String csvText() {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return RegExp(r'[",\n\r]').hasMatch(s)
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final rows = <List<Object?>>[
      [
        'time',
        'total_chol_mg_dl',
        'total_chol_mmol_l',
        'category',
        'signal_quality',
        'peak_pressure_mmhg',
        'led1_ma',
        'led2_ma',
        'flagged',
        'note',
      ],
      for (final r in readings)
        [
          r.time.toIso8601String(),
          r.totalChol.toStringAsFixed(1),
          (r.totalChol / kMgdlPerMmoll).toStringAsFixed(2),
          categoryLabel(_category(r)),
          r.quality.toStringAsFixed(2),
          r.peakPressure.toStringAsFixed(0),
          r.ch1mA.toStringAsFixed(1),
          r.ch2mA.toStringAsFixed(1),
          r.flagged ? 'yes' : 'no',
          r.note ?? '',
        ],
    ];
    return rows.map((row) => row.map(cell).join(',')).join('\r\n');
  }

  // -------------------------------------------------------------------------
  // PDF

  static const _blue = PdfColor.fromInt(0xFF1F32C4);
  static const _ink = PdfColor.fromInt(0xFF101A73);
  static const _muted = PdfColor.fromInt(0xFF7A7FA6);
  static const _tint = PdfColor.fromInt(0xFFF1F2FB);
  static const _pink = PdfColor.fromInt(0xFFFFD3E3);
  static const _red = PdfColor.fromInt(0xFFE5484D);
  static const _redTint = PdfColor.fromInt(0xFFFBE3E4);

  Future<File> pdf() async => _write('pdf', await pdfBytes());

  Future<Uint8List> pdfBytes() async {
    Future<pw.Font> font(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    final regular = await font('Poppins-Regular');
    final bold = await font('Poppins-SemiBold');
    final mono = await font('SpaceMono-Bold');
    final logo = pw.MemoryImage((await rootBundle
            .load('assets/branding/omhs_logo_mark_transparent.png'))
        .buffer
        .asUint8List());

    final p = profile;
    final u = unitLabel(unit);
    final values = readings.map((r) => r.totalChol).toList();
    final avg = values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;

    pw.Widget label(String t) => pw.Text(t.toUpperCase(),
        style: const pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 1));

    pw.Widget fact(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 90,
                child: pw.Text(k,
                    style: const pw.TextStyle(fontSize: 9, color: _muted))),
            pw.Expanded(
                child: pw.Text(v,
                    style: const pw.TextStyle(fontSize: 9, color: _ink))),
          ]),
        );

    pw.Widget stat(String k, String v) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(right: 8),
            decoration: const pw.BoxDecoration(
              color: _tint,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(k,
                    style: const pw.TextStyle(fontSize: 8, color: _muted)),
                pw.SizedBox(height: 3),
                pw.Text(v,
                    style: pw.TextStyle(font: mono, fontSize: 13, color: _ink)),
              ],
            ),
          ),
        );

    final risks = [
      if (p.smoker) 'Smoker',
      if (p.diabetes) 'Diabetes',
      if (p.hypertension) 'High blood pressure',
      if (p.onCholMeds) 'Taking cholesterol medication',
    ];

    final doc = pw.Document(
      title: 'OMHS cholesterol report',
      author: 'OMHS',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      maxPages: 200,
      footer: (ctx) => pw.Row(children: [
        pw.Expanded(
          child: pw.Text(
            'Research prototype. Readings are estimates, not a medical diagnosis.',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: _muted)),
      ]),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Image(logo, width: 34, height: 34),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Text('Cholesterol report',
                  style: pw.TextStyle(font: mono, fontSize: 22, color: _blue)),
            ),
            pw.Text('Generated ${formatWhen(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  label('Patient'),
                  pw.SizedBox(height: 6),
                  fact('Name', p.name.trim().isEmpty ? '—' : p.name.trim()),
                  fact(
                      'Date of birth',
                      p.birthDate == null
                          ? '—'
                          : '${formatDate(p.birthDate!)} (${p.age} yrs)'),
                  fact('Sex', p.sex == null ? '—' : sexLabel(p.sex!)),
                  fact('Height / weight', [
                    p.heightCm == null
                        ? '—'
                        : formatHeight(p.heightCm!, bodyUnits),
                    p.weightKg == null
                        ? '—'
                        : formatWeight(p.weightKg!, bodyUnits),
                  ].join(' / ')),
                  fact('BMI',
                      p.bmi == null ? '—' : p.bmi!.toStringAsFixed(1)),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  label('Health context'),
                  pw.SizedBox(height: 6),
                  fact('Risk factors',
                      risks.isEmpty ? 'None reported' : risks.join(', ')),
                  if (p.doctorName.trim().isNotEmpty ||
                      p.doctorPhone.trim().isNotEmpty)
                    fact(
                        'Doctor',
                        [p.doctorName.trim(), p.doctorPhone.trim()]
                            .where((s) => s.isNotEmpty)
                            .join(', ')),
                  fact('Ranges used', _rangesText(p)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Row(children: [
          stat('Readings', '${readings.length}'),
          stat('Latest',
              values.isEmpty ? '—' : '${formatChol(values.first, unit)} $u'),
          stat('Average', avg == null ? '—' : '${formatChol(avg, unit)} $u'),
          stat(
              'Range',
              values.isEmpty
                  ? '—'
                  : '${formatChol(values.reduce(min), unit)}–'
                      '${formatChol(values.reduce(max), unit)}'),
        ]),
        if (readings.length >= 2) ...[
          pw.SizedBox(height: 18),
          label('Trend'),
          pw.SizedBox(height: 6),
          pw.SizedBox(height: 150, child: _chart(mono)),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            pw.Text(formatDate(readings.last.time),
                style: const pw.TextStyle(fontSize: 7, color: _muted)),
            pw.Spacer(),
            pw.Text(formatDate(readings.first.time),
                style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ]),
        ],
        pw.SizedBox(height: 18),
        label('Readings'),
        pw.SizedBox(height: 6),
        if (readings.isEmpty)
          pw.Text('No readings yet.',
              style: const pw.TextStyle(fontSize: 9, color: _muted))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', u, 'Category', 'Quality', 'Note'],
            data: [
              for (final r in readings)
                [
                  formatWhen(r.time),
                  formatChol(r.totalChol, unit),
                  categoryLabel(_category(r)),
                  '${(r.quality * 100).round()}',
                  [if (r.flagged) 'Flagged', r.note ?? '']
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                ],
            ],
            border: null,
            headerStyle: pw.TextStyle(fontSize: 8, color: _muted, font: bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
            headerDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _muted, width: 0.5)),
            ),
            oddRowDecoration: const pw.BoxDecoration(color: _tint),
            cellAlignments: {1: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
            columnWidths: {
              0: const pw.FixedColumnWidth(110),
              1: const pw.FixedColumnWidth(50),
              2: const pw.FixedColumnWidth(65),
              3: const pw.FixedColumnWidth(45),
              4: const pw.FlexColumnWidth(),
            },
          ),
      ],
    ));
    return doc.save();
  }

  String _rangesText(UserProfile p) {
    final r = rangesFor(p.age);
    return '${r.label}: borderline from ${formatChol(r.borderlineFrom, unit)}, '
        'high from ${formatChol(r.highFrom, unit)} ${unitLabel(unit)}';
  }

  /// Line over the category bands. PDF y runs bottom to top.
  pw.Widget _chart(pw.Font mono) {
    final pts = readings.reversed.toList();
    final ranges = rangesFor(profile.age);
    final values = pts.map((r) => r.totalChol);
    final lo = min(values.reduce(min), ranges.borderlineFrom - 40) - 10;
    final hi = max(values.reduce(max), ranges.highFrom + 20) + 10;
    const gutter = 30.0;

    return pw.Stack(children: [
      pw.CustomPaint(
        size: const PdfPoint(double.infinity, 150),
        painter: (canvas, size) {
          final w = size.x - gutter;
          double y(double v) => size.y * (v - lo) / (hi - lo);
          double x(int i) => w * i / (pts.length - 1);
          final yB = y(ranges.borderlineFrom), yH = y(ranges.highFrom);

          canvas
            ..setFillColor(_tint)
            ..drawRect(0, 0, w, yB)
            ..fillPath()
            ..setFillColor(_pink)
            ..drawRect(0, yB, w, yH - yB)
            ..fillPath()
            ..setFillColor(_redTint)
            ..drawRect(0, yH, w, size.y - yH)
            ..fillPath();

          canvas
            ..setStrokeColor(_blue)
            ..setLineWidth(1.5)
            ..setLineJoin(PdfLineJoin.round)
            ..moveTo(x(0), y(pts[0].totalChol));
          for (var i = 1; i < pts.length; i++) {
            canvas.lineTo(x(i), y(pts[i].totalChol));
          }
          canvas.strokePath();

          if (pts.length <= 60) {
            canvas.setFillColor(_blue);
            for (var i = 0; i < pts.length; i++) {
              canvas
                ..drawEllipse(x(i), y(pts[i].totalChol), 2, 2)
                ..fillPath();
            }
          }
        },
      ),
      // Threshold labels in the right gutter.
      for (final v in [ranges.borderlineFrom, ranges.highFrom])
        pw.Positioned(
          right: 0,
          top: 150 * (1 - (v - lo) / (hi - lo)) - 5,
          child: pw.Text(formatChol(v, unit),
              style: pw.TextStyle(font: mono, fontSize: 7, color: _red)),
        ),
    ]);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Opens the system share sheet (WhatsApp, email, Drive, …) for [file].
Future<void> shareFile(File file, {String? subject}) =>
    SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: subject,
    ));
