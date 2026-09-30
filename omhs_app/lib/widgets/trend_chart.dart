import 'dart:math';

import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/reading.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

enum TrendSpan { days30, days90, all }

/// Cholesterol over time, drawn over the desirable / borderline / high bands.
/// Tap or drag to inspect a reading.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.readings,
    required this.unit,
    required this.ranges,
    required this.span,
    this.height = 180,
  });

  /// Any order; the chart sorts by time.
  final List<Reading> readings;
  final CholUnit unit;
  final CholRanges ranges;
  final TrendSpan span;
  final double height;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;

  List<Reading> get _points {
    final cutoff = switch (widget.span) {
      TrendSpan.days30 => DateTime.now().subtract(const Duration(days: 30)),
      TrendSpan.days90 => DateTime.now().subtract(const Duration(days: 90)),
      TrendSpan.all => null,
    };
    final list = widget.readings
        .where((r) => cutoff == null || r.time.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  @override
  void didUpdateWidget(TrendChart old) {
    super.didUpdateWidget(old);
    if (old.span != widget.span || old.readings != widget.readings) {
      _selected = null;
    }
  }

  void _select(Offset pos, double width, int count) {
    if (count == 0) return;
    final plot = width - _TrendPainter.rightGutter;
    final i = count == 1
        ? 0
        : (pos.dx / plot * (count - 1)).round().clamp(0, count - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final points = _points;
    if (points.length < 2) {
      return SizedBox(
        height: widget.height * 0.6,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'No readings in this period'
                : 'Take one more reading to see a trend',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      );
    }
    final sel = _selected != null && _selected! < points.length
        ? points[_selected!]
        : null;
    final first = points.first, last = points.last;
    final change = last.totalChol - first.totalChol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: sel == null
              ? Text(
                  '${points.length} readings · '
                  '${change >= 0 ? '+' : '−'}${formatChol(change.abs(), widget.unit)} '
                  '${unitLabel(widget.unit)} since ${formatShortDate(first.time)}',
                  style: TextStyle(fontSize: 12, color: c.muted),
                )
              : Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${formatChol(sel.totalChol, widget.unit)} ',
                    style: mono(13, color: c.text),
                  ),
                  TextSpan(
                    text: '${unitLabel(widget.unit)} · ${formatWhen(sel.time)}',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ])),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) => Semantics(
            label: 'Cholesterol trend, ${points.length} readings, from '
                '${formatChol(first.totalChol, widget.unit)} to '
                '${formatChol(last.totalChol, widget.unit)} '
                '${unitLabel(widget.unit)}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _select(d.localPosition, box.maxWidth, points.length),
              onHorizontalDragUpdate: (d) =>
                  _select(d.localPosition, box.maxWidth, points.length),
              child: CustomPaint(
                size: Size(box.maxWidth, widget.height),
                painter: _TrendPainter(
                  points: points,
                  ranges: widget.ranges,
                  unit: widget.unit,
                  selected: _selected,
                  colors: c,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: _TrendPainter.rightGutter),
          child: Row(
            children: [
              Text(formatShortDate(first.time),
                  style: TextStyle(fontSize: 11, color: c.muted)),
              const Spacer(),
              Text(formatShortDate(last.time),
                  style: TextStyle(fontSize: 11, color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.ranges,
    required this.unit,
    required this.selected,
    required this.colors,
  });

  /// Room on the right for the threshold labels.
  static const rightGutter = 40.0;

  final List<Reading> points;
  final CholRanges ranges;
  final CholUnit unit;
  final int? selected;
  final OmhsColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final plotW = size.width - rightGutter;
    final values = points.map((r) => r.totalChol);
    // Keep both thresholds in view so the bands always make sense.
    final lo = min(values.reduce(min), ranges.borderlineFrom - 40) - 10;
    final hi = max(values.reduce(max), ranges.highFrom + 20) + 10;
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));
    double x(int i) => plotW * i / (points.length - 1);

    final plot = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, plotW, size.height), const Radius.circular(12));
    canvas.save();
    canvas.clipRRect(plot);
    final yB = y(ranges.borderlineFrom), yH = y(ranges.highFrom);
    canvas.drawRect(Rect.fromLTRB(0, yB, plotW, size.height),
        Paint()..color = c.primary.withValues(alpha: 0.07));
    canvas.drawRect(Rect.fromLTRB(0, yH, plotW, yB),
        Paint()..color = c.pink.withValues(alpha: 0.45));
    canvas.drawRect(Rect.fromLTRB(0, 0, plotW, yH),
        Paint()..color = c.danger.withValues(alpha: 0.12));
    canvas.restore();

    for (final (v, yy) in [(ranges.borderlineFrom, yB), (ranges.highFrom, yH)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: formatChol(v, unit),
          style: TextStyle(fontFamily: kMonoFont, fontSize: 10, color: c.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotW + 6, yy - tp.height / 2));
    }

    final line = Path()..moveTo(x(0), y(points[0].totalChol));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(x(i), y(points[i].totalChol));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = c.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (selected != null && selected! < points.length) {
      final sx = x(selected!);
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height),
          Paint()..color = c.muted.withValues(alpha: 0.5)..strokeWidth = 1);
    }

    // Dots only when they won't crowd the line.
    final showDots = points.length <= 40;
    for (var i = 0; i < points.length; i++) {
      final isSel = i == selected;
      final isLast = i == points.length - 1;
      if (!showDots && !isSel && !isLast) continue;
      final o = Offset(x(i), y(points[i].totalChol));
      final r = isSel || isLast ? 5.0 : 3.0;
      canvas.drawCircle(o, r + 2, Paint()..color = c.surfaceAlt);
      canvas.drawCircle(o, r, Paint()..color = c.primary);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.unit != unit ||
      old.ranges != ranges ||
      old.colors != colors;
}
