import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A crackling current along the edge of [child], for a card that needs
/// attention. A light version of React Bits' ElectricBorder: no shader and no
/// package, just a few jagged strands over a soft glow, drawn by one
/// [CustomPainter] that repaints on its own layer (the list around it does not).
///
/// With "remove animations" on (or [animate] false) the strands are drawn once,
/// still. The ticker also stops by itself while the tab is not shown.
class ElectricBorder extends StatefulWidget {
  const ElectricBorder({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = 16,
    this.thickness = 1.5,
    this.strands = 2,
    this.animate = true,
  });

  final Widget child;
  final Color color;
  final double borderRadius;
  final double thickness;

  /// How many jagged lines run along the edge.
  final int strands;
  final bool animate;

  @override
  State<ElectricBorder> createState() => _ElectricBorderState();
}

class _ElectricBorderState extends State<ElectricBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // Long enough that the phase never visibly jumps when it wraps.
    duration: const Duration(seconds: 60),
  );

  bool _moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final moving =
        widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (moving == _moving) return;
    _moving = moving;
    moving ? _clock.repeat() : _clock.stop();
  }

  @override
  void didUpdateWidget(ElectricBorder old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) didChangeDependencies();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        // In front of the card: the current is brighter than its own border.
        foregroundPainter: _CurrentPainter(
          clock: _clock,
          color: widget.color,
          radius: widget.borderRadius,
          thickness: widget.thickness,
          strands: widget.strands.clamp(1, 4),
        ),
        child: widget.child,
      ),
    );
  }
}

class _CurrentPainter extends CustomPainter {
  _CurrentPainter({
    required this.clock,
    required this.color,
    required this.radius,
    required this.thickness,
    required this.strands,
  }) : super(repaint: clock);

  final AnimationController clock;
  final Color color;
  final double radius;
  final double thickness;
  final int strands;

  /// Distance between two samples of the edge, in px.
  static const _step = 5.0;

  /// How far a strand strays from the edge, in px.
  static const _amplitude = 2.6;

  // The edge sampled once per size: points and outward normals.
  Size? _sampledFor;
  List<Offset> _points = const [];
  List<Offset> _normals = const [];
  List<double> _arc = const [];

  void _sample(Size size) {
    if (_sampledFor == size) return;
    _sampledFor = size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final metric = path.computeMetrics().first;
    final count = math.max(8, (metric.length / _step).round());
    _points = [];
    _normals = [];
    _arc = [];
    for (var i = 0; i < count; i++) {
      final at = metric.getTangentForOffset(metric.length * i / count)!;
      _points.add(at.position);
      // The path runs clockwise: the outward normal is the tangent turned left.
      _normals.add(Offset(at.vector.dy, -at.vector.dx));
      _arc.add(metric.length * i / count);
    }
  }

  /// Cheap stand-in for noise: three sines that drift at different speeds.
  double _wander(double s, double t, int strand) {
    final k = strand * 2.3;
    return math.sin(s * 0.11 + t * 5.1 + k) * 0.6 +
        math.sin(s * 0.31 - t * 8.7 + k * 1.7) * 0.3 +
        math.sin(s * 0.83 + t * 13.0 + k * 0.6) * 0.15;
  }

  Path _strand(double t, int strand, double spread) {
    final path = Path();
    final n = _points.length;
    for (var i = 0; i <= n; i++) {
      final j = i % n;
      final offset = _wander(_arc[j], t, strand) * _amplitude * spread;
      final p = _points[j] + _normals[j] * offset;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _sample(size);
    final t = clock.isAnimating ? clock.value * 60 : 0.0;
    // A slight flicker of the whole current.
    final flicker = 0.85 + 0.15 * math.sin(t * 17.0);

    // The strand that runs on the edge and the ones that stray from it.
    final paths = [
      for (var s = 0; s < strands; s++) _strand(t, s, s == 0 ? 0.55 : 1.0),
    ];

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // Soft glow: wide, faint strokes instead of a blur (much cheaper).
    for (final path in paths) {
      line
        ..strokeWidth = thickness * 5
        ..color = color.withValues(alpha: 0.10 * flicker);
      canvas.drawPath(path, line);
      line
        ..strokeWidth = thickness * 2.6
        ..color = color.withValues(alpha: 0.22 * flicker);
      canvas.drawPath(path, line);
    }
    // The current itself.
    for (final path in paths) {
      line
        ..strokeWidth = thickness
        ..color = color.withValues(alpha: 0.95 * flicker);
      canvas.drawPath(path, line);
    }
    // A whiter core on the strand closest to the edge.
    line
      ..strokeWidth = thickness * 0.5
      ..color = Color.lerp(color, Colors.white, 0.7)!.withValues(
        alpha: flicker,
      );
    canvas.drawPath(paths.first, line);
  }

  @override
  bool shouldRepaint(_CurrentPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.thickness != thickness ||
      old.strands != strands;
}
