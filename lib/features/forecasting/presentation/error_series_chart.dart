import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../data/evaluation_series.dart';

/// Mean error (%) of each validation day as a line. The [selected] day is
/// marked; touching or dragging picks the nearest day with [onSelect].
class ErrorSeriesChart extends StatelessWidget {
  const ErrorSeriesChart({
    super.key,
    required this.points,
    required this.selected,
    required this.onSelect,
    this.isSelectable,
  });

  final List<SeriesPoint> points;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Days that cannot be picked (offline: only the ones saved) are ignored.
  final bool Function(DateTime day)? isSelectable;

  void _pick(double dx, double width) {
    if (points.isEmpty) return;
    final step = points.length < 2
        ? 1.0
        : (width - _padX * 2) / (points.length - 1);
    final i = ((dx - _padX) / step).round().clamp(0, points.length - 1);
    final day = points[i].date;
    if (day != selected && (isSelectable?.call(day) ?? true)) onSelect(day);
  }

  @override
  Widget build(BuildContext context) {
    final at = selected == null
        ? null
        : points.where((p) => p.date == selected).firstOrNull;
    return Semantics(
      label:
          'Gráfica del error medio por día, del ${formatShortDate(points.first.date)} '
          'al ${formatShortDate(points.last.date)}'
          '${at == null ? '' : '. Día elegido ${formatShortDate(at.date)}: ${decimal(at.meanErrorPct, 2)} por ciento'}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _pick(d.localPosition.dx, box.maxWidth),
            child: CustomPaint(
              size: Size(box.maxWidth, 190),
              painter: _SeriesPainter(points, selected),
            ),
          ),
        ),
      ),
    );
  }
}

const _padX = 14.0;

class _SeriesPainter extends CustomPainter {
  _SeriesPainter(this.points, this.selected);

  final List<SeriesPoint> points;
  final DateTime? selected;

  static const _top = 26.0, _bottom = 24.0;

  TextPainter _text(
    String s,
    Color color, {
    bool bold = false,
    double size = 11,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = points.map((p) => p.meanErrorPct);
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.2) {
      // A flat line still needs a scale.
      hi += 0.1;
      lo -= 0.1;
    }
    final pad = (hi - lo) * 0.12;
    lo = (lo - pad).clamp(0, double.infinity);
    hi += pad;

    final plotH = size.height - _top - _bottom;
    final step = points.length < 2
        ? 0.0
        : (size.width - _padX * 2) / (points.length - 1);
    Offset at(int i) => Offset(
      _padX + step * i,
      _top + plotH * (1 - (points[i].meanErrorPct - lo) / (hi - lo)),
    );

    // Three guide lines with their value.
    final grid = Paint()
      ..color = const Color(0xFFE3E7EE)
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = _top + plotH * (1 - f);
      canvas.drawLine(Offset(_padX, y), Offset(size.width - _padX, y), grid);
      final label = _text(
        decimal(lo + (hi - lo) * f, 1),
        AppColors.muted,
        size: 10,
      );
      label.paint(canvas, Offset(_padX, y - label.height - 1));
    }

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (points.length <= 31) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(at(i), 2.2, Paint()..color = AppColors.blue);
      }
    }

    // First and last day.
    final first = _text(formatShortDate(points.first.date), AppColors.muted);
    first.paint(canvas, Offset(_padX, size.height - first.height));
    if (points.length > 1) {
      final last = _text(formatShortDate(points.last.date), AppColors.muted);
      last.paint(
        canvas,
        Offset(size.width - _padX - last.width, size.height - last.height),
      );
    }

    // The chosen day: guide, big dot and its value.
    final i = points.indexWhere((p) => p.date == selected);
    if (i < 0) return;
    final p = at(i);
    canvas.drawLine(
      Offset(p.dx, _top - 4),
      Offset(p.dx, _top + plotH),
      Paint()
        ..color = AppColors.blue.withValues(alpha: 0.35)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(p, 6, Paint()..color = Colors.white);
    canvas.drawCircle(p, 4.5, Paint()..color = AppColors.blue);

    final bubble = _text(
      '${decimal(points[i].meanErrorPct, 2)} %',
      Colors.white,
      bold: true,
    );
    final w = bubble.width + 14, h = bubble.height + 6;
    final left = (p.dx - w / 2).clamp(0.0, size.width - w);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 0, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.ink);
    bubble.paint(canvas, Offset(left + 7, 3));
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.points != points || old.selected != selected;
}
