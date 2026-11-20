import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forecast.dart';
import 'forecast_widgets.dart';

/// Voltage of one cell over the forecast horizon, with the allowed limit as a
/// dashed line. Opens on the highest day; touch or drag to read another.
class ForecastChart extends StatefulWidget {
  const ForecastChart({super.key, required this.items});

  /// One cell, oldest day first.
  final List<ForecastItem> items;

  @override
  State<ForecastChart> createState() => _ForecastChartState();
}

class _ForecastChartState extends State<ForecastChart> {
  int? _selected;

  double? get _limit =>
      widget.items.map((i) => i.maxVoltage).whereType<double>().lastOrNull;

  /// The day the user touched, or else the highest one (the first, on a tie):
  /// whether a cell goes over the limit is what this screen is read for.
  int get _shown {
    final items = widget.items;
    final touched = _selected;
    if (touched != null && touched < items.length) return touched;
    var peak = 0;
    for (var i = 1; i < items.length; i++) {
      if (items[i].voltage > items[peak].voltage) peak = i;
    }
    return peak;
  }

  void _select(double dx, double width) {
    final n = widget.items.length;
    if (n < 2) return;
    final plot = width - ForecastChartPainter.left - ForecastChartPainter.right;
    final t = ((dx - ForecastChartPainter.left) / plot).clamp(0.0, 1.0);
    setState(() => _selected = (t * (n - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final shown = _shown;
    final selected = items[shown];
    final values = items.map((i) => i.voltage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '${formatShortDate(selected.date)} · ${volts(selected.voltage)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (selected.exceeds)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Supera el límite',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Semantics(
          label:
              'Gráfico de ${items.length} días, de ${volts(values.reduce(math.min))} '
              'a ${volts(values.reduce(math.max))}${_limit == null ? '' : ', límite ${volts(_limit!, 2)}'}',
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _select(d.localPosition.dx, box.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _select(d.localPosition.dx, box.maxWidth),
              child: CustomPaint(
                size: Size(box.maxWidth, 220),
                painter: ForecastChartPainter(
                  items: items,
                  limit: _limit,
                  selected: shown,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Also used to draw the PNG that can be downloaded.
class ForecastChartPainter extends CustomPainter {
  ForecastChartPainter({
    required this.items,
    required this.limit,
    this.selected,
  });

  final List<ForecastItem> items;
  final double? limit;
  final int? selected;

  static const left = 46.0, right = 8.0, top = 8.0, bottom = 24.0;

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    Color color = AppColors.muted,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10.5, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;
    final values = items.map((i) => i.voltage).toList();
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (limit != null) {
      lo = math.min(lo, limit!);
      hi = math.max(hi, limit!);
    }
    final pad = (hi - lo) * 0.08 == 0 ? 0.05 : (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;

    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    double x(int i) => items.length < 2
        ? plot.center.dx
        : plot.left + plot.width * i / (items.length - 1);
    double y(double v) => plot.bottom - plot.height * (v - lo) / (hi - lo);

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var k = 0; k < 4; k++) {
      final v = lo + (hi - lo) * k / 3;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(
        canvas,
        v.toStringAsFixed(2),
        Offset(plot.left - 6, y(v)),
        align: TextAlign.right,
      );
    }
    for (final i in {0, (items.length - 1) ~/ 2, items.length - 1}) {
      _text(
        canvas,
        formatShortDate(items[i].date),
        Offset(x(i), size.height - 8),
        align: TextAlign.center,
      );
    }

    final line = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // The days over the limit stand out in red on top of the blue line.
    final over = Path();
    final dots = <Offset>[];
    var open = false;
    for (var i = 0; i < items.length; i++) {
      if (!items[i].exceeds) {
        open = false;
        continue;
      }
      final at = Offset(x(i), y(values[i]));
      if (open) {
        over.lineTo(at.dx, at.dy);
      } else {
        over.moveTo(at.dx, at.dy);
        // A lone day has no segment: it is drawn as a dot.
        if ((i == 0 || !items[i - 1].exceeds) &&
            (i == items.length - 1 || !items[i + 1].exceeds)) {
          dots.add(at);
        }
      }
      open = true;
    }
    canvas.drawPath(
      over,
      Paint()
        ..color = AppColors.error
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    for (final dot in dots) {
      canvas.drawCircle(dot, 2.4, Paint()..color = AppColors.error);
    }

    if (limit != null) {
      final dashed = Paint()
        ..color = AppColors.error
        ..strokeWidth = 1.6;
      for (var dx = plot.left; dx < plot.right; dx += 10) {
        canvas.drawLine(
          Offset(dx, y(limit!)),
          Offset(math.min(dx + 5, plot.right), y(limit!)),
          dashed,
        );
      }
      _text(
        canvas,
        'Límite ${limit!.toStringAsFixed(2)} V',
        Offset(plot.right, y(limit!) - 9),
        color: AppColors.error,
        align: TextAlign.right,
      );
    }

    if (selected != null && selected! < items.length) {
      final at = Offset(x(selected!), y(values[selected!]));
      canvas.drawLine(
        Offset(at.dx, plot.top),
        Offset(at.dx, plot.bottom),
        Paint()..color = AppColors.muted,
      );
      canvas.drawCircle(
        at,
        5,
        Paint()
          ..color = items[selected!].exceeds ? AppColors.error : AppColors.blue,
      );
      canvas.drawCircle(at, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(ForecastChartPainter old) =>
      old.items != items || old.limit != limit || old.selected != selected;
}
