import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomShape — every supported canvas shape
// Each shape is expressed as a Path normalised to a width × height bounding box.
// 100 px = 1 metre.  _insideShape(path, point) replaces the old rect check.
// ─────────────────────────────────────────────────────────────────────────────

enum RoomShape {
  rectangle,
  circle,
  oval,
  triangle,
  pentagon,
  hexagon,
  heptagon,
  octagon,
  nonagon,
  decagon,
  hendecagon,
  trapezoid,
  diamond,
  rhombus,
  parallelogram,
  star,
  semiCircle,
  heart,
  ring,
  trefoil,
  asteroid,
  pie,
  cross,
  crescent,
  custom,
}

extension RoomShapeExt on RoomShape {
  String get label {
    switch (this) {
      case RoomShape.rectangle:
        return 'Rectangle';
      case RoomShape.circle:
        return 'Circle';
      case RoomShape.oval:
        return 'Oval';
      case RoomShape.triangle:
        return 'Triangle';
      case RoomShape.pentagon:
        return 'Pentagon';
      case RoomShape.hexagon:
        return 'Hexagon';
      case RoomShape.heptagon:
        return 'Heptagon';
      case RoomShape.octagon:
        return 'Octagon';
      case RoomShape.nonagon:
        return 'Nonagon';
      case RoomShape.decagon:
        return 'Decagon';
      case RoomShape.hendecagon:
        return 'Hendecagon';
      case RoomShape.trapezoid:
        return 'Trapezoid';
      case RoomShape.diamond:
        return 'Diamond';
      case RoomShape.rhombus:
        return 'Rhombus';
      case RoomShape.parallelogram:
        return 'Parallelogram';
      case RoomShape.star:
        return 'Star';
      case RoomShape.semiCircle:
        return 'Semi-circle';
      case RoomShape.heart:
        return 'Heart';
      case RoomShape.ring:
        return 'Ring';
      case RoomShape.trefoil:
        return 'Trefoil';
      case RoomShape.asteroid:
        return 'Asteroid';
      case RoomShape.pie:
        return 'Pie';
      case RoomShape.cross:
        return 'Cross';
      case RoomShape.crescent:
        return 'Crescent';
      case RoomShape.custom:
        return 'Custom';
    }
  }

  IconData get icon {
    switch (this) {
      case RoomShape.rectangle:
        return Icons.crop_square;
      case RoomShape.circle:
        return Icons.circle_outlined;
      case RoomShape.oval:
        return Icons.egg_outlined;
      case RoomShape.triangle:
        return Icons.change_history;
      case RoomShape.pentagon:
        return Icons.pentagon_outlined;
      case RoomShape.hexagon:
        return Icons.hexagon_outlined;
      case RoomShape.heptagon:
        return Icons.hive_outlined;
      case RoomShape.octagon:
        return Icons.stop_circle_outlined;
      case RoomShape.nonagon:
        return Icons.blur_circular;
      case RoomShape.decagon:
        return Icons.brightness_1_outlined;
      case RoomShape.hendecagon:
        return Icons.adjust;
      case RoomShape.trapezoid:
        return Icons.filter_tilt_shift;
      case RoomShape.diamond:
        return Icons.diamond_outlined;
      case RoomShape.rhombus:
        return Icons.rotate_90_degrees_cw;
      case RoomShape.parallelogram:
        return Icons.space_bar;
      case RoomShape.star:
        return Icons.star_outline;
      case RoomShape.semiCircle:
        return Icons.brightness_3;
      case RoomShape.heart:
        return Icons.favorite_outline;
      case RoomShape.ring:
        return Icons.radio_button_unchecked;
      case RoomShape.trefoil:
        return Icons.bubble_chart_outlined;
      case RoomShape.asteroid:
        return Icons.flare;
      case RoomShape.pie:
        return Icons.pie_chart_outline;
      case RoomShape.cross:
        return Icons.add;
      case RoomShape.crescent:
        return Icons.bedtime_outlined;
      case RoomShape.custom:
        return Icons.edit_outlined;
    }
  }

  /// True for shapes that cannot be meaningfully described only by width/height
  bool get isCustom => this == RoomShape.custom;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shape path builder
// All paths fit within Rect.fromLTWH(0, 0, w, h).
// Custom shape uses the provided list of relative points (0..1 each axis).
// ─────────────────────────────────────────────────────────────────────────────

Path buildRoomPath(
  RoomShape shape,
  double w,
  double h, {
  List<Offset>? customPoints, // relative 0..1 coords for RoomShape.custom
}) {
  switch (shape) {
    case RoomShape.rectangle:
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));

    case RoomShape.circle:
      return Path()..addOval(Rect.fromLTWH(0, 0, w, h));

    case RoomShape.oval:
      return Path()..addOval(Rect.fromLTWH(0, 0, w, h));

    case RoomShape.triangle:
      return _polygon(w, h, 3, -math.pi / 2);

    case RoomShape.pentagon:
      return _polygon(w, h, 5, -math.pi / 2);

    case RoomShape.hexagon:
      return _polygon(w, h, 6, 0);

    case RoomShape.heptagon:
      return _polygon(w, h, 7, -math.pi / 2);

    case RoomShape.octagon:
      return _polygon(w, h, 8, math.pi / 8);

    case RoomShape.nonagon:
      return _polygon(w, h, 9, -math.pi / 2);

    case RoomShape.decagon:
      return _polygon(w, h, 10, 0);

    case RoomShape.hendecagon:
      return _polygon(w, h, 11, -math.pi / 2);

    case RoomShape.trapezoid:
      return _trapezoid(w, h);

    case RoomShape.diamond:
      return _diamond(w, h);

    case RoomShape.rhombus:
      return _rhombus(w, h);

    case RoomShape.parallelogram:
      return _parallelogram(w, h);

    case RoomShape.star:
      return _star(w, h, 5);

    case RoomShape.semiCircle:
      return _semiCircle(w, h);

    case RoomShape.heart:
      return _heart(w, h);

    case RoomShape.ring:
      // Ring = circle with inner hole. For hit-testing we use the outer circle.
      // The hole is only visual (drawn separately).
      return Path()..addOval(Rect.fromLTWH(0, 0, w, h));

    case RoomShape.trefoil:
      return _trefoil(w, h);

    case RoomShape.asteroid:
      return _asteroid(w, h);

    case RoomShape.pie:
      return _pie(w, h);

    case RoomShape.cross:
      return _cross(w, h);

    case RoomShape.crescent:
      return _crescent(w, h);

    case RoomShape.custom:
      if (customPoints != null && customPoints.length >= 3) {
        final path = Path();
        path.moveTo(customPoints.first.dx * w, customPoints.first.dy * h);
        for (final pt in customPoints.skip(1)) {
          path.lineTo(pt.dx * w, pt.dy * h);
        }
        path.close();
        return path;
      }
      return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
  }
}

/// Returns true if [point] lies inside [path].
bool insideShape(Path path, Offset point) => path.contains(point);

// ─────────────────────────────────────────────────────────────────────────────
// Private shape builders
// ─────────────────────────────────────────────────────────────────────────────

/// Regular n-gon, rotated by [startAngle].
Path _polygon(double w, double h, int n, double startAngle) {
  final cx = w / 2, cy = h / 2;
  final rx = w / 2, ry = h / 2;
  final path = Path();
  for (int i = 0; i < n; i++) {
    final angle = startAngle + (2 * math.pi * i / n);
    final x = cx + rx * math.cos(angle);
    final y = cy + ry * math.sin(angle);
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  return path;
}

Path _trapezoid(double w, double h) {
  // Top edge = 60% width centred, bottom = full width
  final indent = w * 0.20;
  return Path()
    ..moveTo(indent, 0)
    ..lineTo(w - indent, 0)
    ..lineTo(w, h)
    ..lineTo(0, h)
    ..close();
}

Path _diamond(double w, double h) {
  return Path()
    ..moveTo(w / 2, 0)
    ..lineTo(w, h / 2)
    ..lineTo(w / 2, h)
    ..lineTo(0, h / 2)
    ..close();
}

Path _rhombus(double w, double h) {
  // Wider than diamond — aspect ratio preserved
  return Path()
    ..moveTo(w * 0.30, 0)
    ..lineTo(w, h * 0.40)
    ..lineTo(w * 0.70, h)
    ..lineTo(0, h * 0.60)
    ..close();
}

Path _parallelogram(double w, double h) {
  final offset = w * 0.25;
  return Path()
    ..moveTo(offset, 0)
    ..lineTo(w, 0)
    ..lineTo(w - offset, h)
    ..lineTo(0, h)
    ..close();
}

Path _star(double w, double h, int points) {
  final cx = w / 2, cy = h / 2;
  final outerX = w / 2, outerY = h / 2;
  final innerX = w * 0.22, innerY = h * 0.22;
  final path = Path();
  for (int i = 0; i < points * 2; i++) {
    final angle = (math.pi / points) * i - math.pi / 2;
    final isOuter = i.isEven;
    final rx = isOuter ? outerX : innerX;
    final ry = isOuter ? outerY : innerY;
    final x = cx + rx * math.cos(angle);
    final y = cy + ry * math.sin(angle);
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  return path;
}

Path _semiCircle(double w, double h) {
  final path = Path();
  path.moveTo(0, h);
  path.arcTo(Rect.fromLTWH(0, 0, w, h * 2), math.pi, math.pi, false);
  path.lineTo(w, h);
  path.close();
  return path;
}

Path _heart(double w, double h) {
  final path = Path();
  final cx = w / 2;
  // Two bezier arcs for the two lobes, then a V at the bottom
  path.moveTo(cx, h * 0.28);
  // Left lobe
  path.cubicTo(
    cx - w * 0.02,
    h * 0.02,
    cx - w * 0.55,
    h * 0.02,
    cx - w * 0.50,
    h * 0.35,
  );
  path.cubicTo(cx - w * 0.45, h * 0.60, cx - w * 0.10, h * 0.72, cx, h * 0.88);
  // Right lobe (mirror)
  path.cubicTo(
    cx + w * 0.10,
    h * 0.72,
    cx + w * 0.45,
    h * 0.60,
    cx + w * 0.50,
    h * 0.35,
  );
  path.cubicTo(cx + w * 0.55, h * 0.02, cx + w * 0.02, h * 0.02, cx, h * 0.28);
  path.close();
  return path;
}

Path _trefoil(double w, double h) {
  final cx = w / 2, cy = h / 2;
  final r = math.min(w, h) * 0.28;
  final path = Path();
  for (int i = 0; i < 3; i++) {
    final angle = (2 * math.pi * i / 3) - math.pi / 2;
    final lx = cx + r * math.cos(angle);
    final ly = cy + r * math.sin(angle);
    path.addOval(Rect.fromCircle(center: Offset(lx, ly), radius: r));
  }
  return path;
}

Path _asteroid(double w, double h) {
  // 4-pointed astroid: x = a*cos³t, y = b*sin³t
  final cx = w / 2, cy = h / 2;
  final a = w / 2, b = h / 2;
  final path = Path();
  const steps = 120;
  for (int i = 0; i <= steps; i++) {
    final t = 2 * math.pi * i / steps;
    final ct = math.cos(t);
    final st = math.sin(t);
    final x = cx + a * ct * ct * ct;
    final y = cy + b * st * st * st;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  path.close();
  return path;
}

Path _pie(double w, double h) {
  final cx = w / 2, cy = h / 2;
  final path = Path();
  path.moveTo(cx, cy);
  path.arcTo(Rect.fromLTWH(0, 0, w, h), -math.pi * 0.75, math.pi * 1.5, false);
  path.close();
  return path;
}

Path _cross(double w, double h) {
  final t = w * 0.30; // arm thickness
  final l = h * 0.30;
  return Path()
    ..moveTo((w - t) / 2, 0)
    ..lineTo((w + t) / 2, 0)
    ..lineTo((w + t) / 2, l)
    ..lineTo(w, l)
    ..lineTo(w, l + t)
    ..lineTo((w + t) / 2, l + t)
    ..lineTo((w + t) / 2, h)
    ..lineTo((w - t) / 2, h)
    ..lineTo((w - t) / 2, l + t)
    ..lineTo(0, l + t)
    ..lineTo(0, l)
    ..lineTo((w - t) / 2, l)
    ..close();
}

Path _crescent(double w, double h) {
  final path = Path();
  // Outer arc (full ellipse)
  path.addOval(Rect.fromLTWH(0, 0, w, h));
  // Subtract inner shifted ellipse via even-odd rule
  final offsetX = w * 0.28;
  path.addOval(Rect.fromLTWH(offsetX, h * 0.05, w * 0.85, h * 0.90));
  path.fillType = PathFillType.evenOdd;
  return path;
}

/// For the ring shape — returns the inner hole path (used for visual only)
Path buildRingHolePath(double w, double h) {
  final inset = math.min(w, h) * 0.28;
  return Path()..addOval(
    Rect.fromLTWH(
      inset,
      inset * (h / w),
      w - inset * 2,
      h - inset * (h / w) * 2,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Clamp a point to stay inside the shape bounding box (used for furniture drag)
// Returns the closest point inside [bounds] — shapes use bounding-box clamping
// as an approximation (exact per-shape clamping would be too expensive).
// ─────────────────────────────────────────────────────────────────────────────
Offset clampToShapeBounds(
  Offset pos,
  Size itemSize,
  double roomW,
  double roomH,
) {
  return Offset(
    pos.dx.clamp(0, roomW - itemSize.width),
    pos.dy.clamp(0, roomH - itemSize.height),
  );
}
