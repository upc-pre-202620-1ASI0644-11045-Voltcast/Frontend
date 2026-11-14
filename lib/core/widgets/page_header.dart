import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Light top of the screens opened over the tabs: round back button, the
/// "Voltcast" mark, a small eyebrow and a big title, with an optional [trailing]
/// widget under them (a count and an action).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: 'Volver',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.field,
                    foregroundColor: AppColors.ink,
                    fixedSize: const Size.square(40),
                  ),
                ),
              const Spacer(),
              const Icon(Icons.bolt_outlined, size: 18, color: AppColors.blue),
              const SizedBox(width: 2),
              const Text(
                'Voltcast',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            eyebrow,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          if (trailing != null) ...[const SizedBox(height: 14), trailing!],
        ],
      ),
    );
  }
}

/// The spreadsheet mark of the file cards: a gridded sheet with a folded
/// corner and a green "X" badge over its lower left.
class ExcelIcon extends StatelessWidget {
  const ExcelIcon({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ExcelPainter()),
    );
  }
}

class _ExcelPainter extends CustomPainter {
  static const _green = Color(0xFF16A34A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Soft shadow under the sheet.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * .55, s * .95),
        width: s * .62,
        height: s * .07,
      ),
      Paint()..color = const Color(0x14000000),
    );
    // Sheet with the top-right corner folded.
    final l = s * .3,
        t = s * .03,
        r = s * .88,
        b = s * .9,
        f = s * .17,
        rad = s * .06;
    final sheet = Path()
      ..moveTo(l + rad, t)
      ..lineTo(r - f, t)
      ..lineTo(r, t + f)
      ..lineTo(r, b - rad)
      ..quadraticBezierTo(r, b, r - rad, b)
      ..lineTo(l + rad, b)
      ..quadraticBezierTo(l, b, l, b - rad)
      ..lineTo(l, t + rad)
      ..quadraticBezierTo(l, t, l + rad, t)
      ..close();
    canvas.drawPath(sheet, Paint()..color = Colors.white);
    canvas.drawPath(
      sheet,
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .035
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - f, t)
        ..lineTo(r - f, t + f)
        ..lineTo(r, t + f)
        ..close(),
      Paint()..color = const Color(0xFFBBF7D0),
    );
    // Grid: 3 columns × 4 rows.
    final grid = Paint()
      ..color = const Color(0xFF86EFAC)
      ..strokeWidth = s * .025;
    final gl = s * .44, gr = s * .78, gt = s * .34, gb = s * .76;
    for (var i = 0; i <= 3; i++) {
      final x = gl + (gr - gl) * i / 3;
      canvas.drawLine(Offset(x, gt), Offset(x, gb), grid);
    }
    for (var i = 0; i <= 4; i++) {
      final y = gt + (gb - gt) * i / 4;
      canvas.drawLine(Offset(gl, y), Offset(gr, y), grid);
    }
    // Badge with the "X".
    final badge = Rect.fromLTWH(s * .1, s * .42, s * .42, s * .42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(s * .08)),
      Paint()..color = _green,
    );
    final x = TextPainter(
      text: TextSpan(
        text: 'X',
        style: TextStyle(
          fontSize: s * .28,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    x.paint(canvas, badge.center - Offset(x.width / 2, x.height / 2));
  }

  @override
  bool shouldRepaint(_ExcelPainter oldDelegate) => false;
}
