import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../data/component.dart';

/// The component as a solid bar that turns under the finger around its
/// vertical axis only (horizontal swipes); a flick keeps it spinning.
class RotatableBar extends StatefulWidget {
  const RotatableBar({super.key, required this.type, required this.serial});

  final ComponentType type;
  final String serial;

  @override
  State<RotatableBar> createState() => RotatableBarState();
}

class RotatableBarState extends State<RotatableBar> with SingleTickerProviderStateMixin {
  static const _radiansPerPixel = 0.012;

  // Starts turned and tilted like the sketch, so it reads as a solid at once.
  // The tilt stays fixed: the bar only turns one way, around its long side.
  double _yaw = 0.6;
  static const _pitch = -0.3;
  late final AnimationController _spin = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() => _yaw = _spin.value));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.type.label} ${widget.serial}. Desliza para girarlo.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragDown: (_) => _spin.stop(),
        onHorizontalDragUpdate: (d) => setState(() => _yaw += d.delta.dx * _radiansPerPixel),
        onHorizontalDragEnd: (d) =>
            _spin.animateWith(FrictionSimulation(0.15, _yaw, d.velocity.pixelsPerSecond.dx * _radiansPerPixel)),
        child: CustomPaint(
          size: Size.infinite,
          painter: PrismPainter(type: widget.type, serial: widget.serial, yaw: _yaw, pitch: _pitch),
        ),
      ),
    );
  }
}

/// A rectangular metal bar drawn in perspective: each face is shaded by how
/// much it faces the light, the serial is engraved along the broad faces, and
/// a soft shadow lies on the floor under it.
class PrismPainter extends CustomPainter {
  PrismPainter({required this.type, required this.serial, required this.yaw, required this.pitch});

  final ComponentType type;
  final String serial;
  final double yaw;
  final double pitch;

  /// Bar proportions (width, height, depth), in units of its height.
  static const _w = 0.26, _h = 1.0, _d = 0.12;

  /// Fixed lean, as in the sketch.
  static const _roll = -0.35;
  static const _camera = 3.2;
  static const _light = (x: -0.45, y: 0.55, z: 0.70);

  /// Corner i has x = bit 0, y = bit 1, z = bit 2 (0 = negative side).
  static const _faces = [
    (corners: [4, 5, 7, 6], normal: (x: 0.0, y: 0.0, z: 1.0)),
    (corners: [1, 0, 2, 3], normal: (x: 0.0, y: 0.0, z: -1.0)),
    (corners: [5, 1, 3, 7], normal: (x: 1.0, y: 0.0, z: 0.0)),
    (corners: [0, 4, 6, 2], normal: (x: -1.0, y: 0.0, z: 0.0)),
    (corners: [6, 7, 3, 2], normal: (x: 0.0, y: 1.0, z: 0.0)),
    (corners: [0, 1, 5, 4], normal: (x: 0.0, y: -1.0, z: 0.0)),
  ];

  ({double x, double y, double z}) _rotate(({double x, double y, double z}) v) {
    // Roll (lean), then pitch (tilt towards the viewer), then yaw (spin).
    var x = v.x * cos(_roll) - v.y * sin(_roll);
    var y = v.x * sin(_roll) + v.y * cos(_roll);
    var z = v.z;
    final y2 = y * cos(pitch) - z * sin(pitch);
    z = y * sin(pitch) + z * cos(pitch);
    y = y2;
    final x2 = x * cos(yaw) + z * sin(yaw);
    z = -x * sin(yaw) + z * cos(yaw);
    x = x2;
    return (x: x, y: y, z: z);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.height * 0.74, size.width * 1.6);
    final centre = Offset(size.width / 2, size.height * 0.46);
    Offset project(({double x, double y, double z}) v) {
      final k = _camera / (_camera - v.z);
      return centre + Offset(v.x * k * scale, -v.y * k * scale);
    }

    final model = [
      for (var i = 0; i < 8; i++)
        (x: (i & 1 == 0 ? -_w : _w) / 2, y: (i & 2 == 0 ? -_h : _h) / 2, z: (i & 4 == 0 ? -_d : _d) / 2),
    ];
    final points = [for (final v in model) project(_rotate(v))];

    // Floor shadow, as wide as the bar looks from here.
    final xs = points.map((p) => p.dx);
    final spread = xs.reduce(max) - xs.reduce(min);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(centre.dx, size.height * 0.93), width: spread * 1.2 + 20, height: 22),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final base = type == ComponentType.anode ? const Color(0xFFB08D4A) : const Color(0xFF6E7A86);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.25);

    for (final face in _faces) {
      final n = _rotate(face.normal);
      if (n.z <= 0) continue; // facing away (the bar is convex: no sorting needed)
      final lit = max(0.0, n.x * _light.x + n.y * _light.y + n.z * _light.z);
      final colour = Color.lerp(Colors.black, base, 0.45 + 0.55 * lit)!;
      final c = [for (final i in face.corners) points[i]];
      final path = Path()
        ..moveTo(c[0].dx, c[0].dy)
        ..lineTo(c[1].dx, c[1].dy)
        ..lineTo(c[2].dx, c[2].dy)
        ..lineTo(c[3].dx, c[3].dy)
        ..close();
      // Brushed sheen across the face.
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            c[0],
            c[1],
            [Color.lerp(colour, Colors.black, 0.12)!, Color.lerp(colour, Colors.white, 0.28)!, colour],
            [0, 0.45, 1],
          ),
      );
      canvas.drawPath(path, edge);
      if (face.normal.z != 0) _engrave(canvas, face.normal.z > 0, project);
    }
  }

  /// Writes the serial along the bar on the front (+z) or back (-z) face.
  void _engrave(Canvas canvas, bool front, Offset Function(({double x, double y, double z})) project) {
    final text = TextPainter(
      text: TextSpan(
        text: serial,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: type == ComponentType.anode
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Fit the text along 70% of the height without exceeding 70% of the width.
    var length = _h * 0.7;
    var thickness = length * text.height / text.width;
    if (thickness > _w * 0.7) {
      thickness = _w * 0.7;
      length = thickness * text.width / text.height;
    }
    final z = front ? _d / 2 : -_d / 2;
    // Reads bottom to top; on the back face the line is mirrored so it reads
    // the right way round when seen from behind.
    final side = front ? -thickness / 2 : thickness / 2;
    final origin = project(_rotate((x: side, y: -length / 2, z: z)));
    final along = project(_rotate((x: side, y: length / 2, z: z)));
    final down = project(_rotate((x: -side, y: -length / 2, z: z)));

    final a = (along - origin) / text.width;
    final b = (down - origin) / text.height;
    canvas.save();
    canvas.transform(
      Float64List.fromList([a.dx, a.dy, 0, 0, b.dx, b.dy, 0, 0, 0, 0, 1, 0, origin.dx, origin.dy, 0, 1]),
    );
    text.paint(canvas, Offset.zero);
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(PrismPainter old) =>
      old.yaw != yaw || old.pitch != pitch || old.type != type || old.serial != serial;
}
