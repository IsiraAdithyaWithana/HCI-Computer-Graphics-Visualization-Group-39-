import 'package:flutter/material.dart';
import '../models/furniture_model.dart';
import 'dart:math' as Math;

class Preview3DScreen extends StatefulWidget {
  final List<FurnitureModel> furniture;
  final double roomWidth;
  final double roomDepth;

  const Preview3DScreen({
    super.key,
    required this.furniture,
    required this.roomWidth,
    required this.roomDepth,
  });

  @override
  State<Preview3DScreen> createState() => _Preview3DScreenState();
}

class _Preview3DScreenState extends State<Preview3DScreen> {
  // Camera orbit angles — fully unlimited, no clamp.
  double _yaw = 0.5;
  double _pitch = 0.55;
  double _zoom = 1.0; // 0.5 = zoomed out, 2.0 = zoomed in

  Offset? _dragStart;
  double _dragStartYaw = 0;
  double _dragStartPitch = 0;

  // Zoom constraints
  static const double _minZoom = 0.4;
  static const double _maxZoom = 2.5;

  String get _zoomLabel => '${(_zoom * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12122A),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Back button — clearly visible on dark background
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back to Editor',
                ),
                const SizedBox(width: 4),
                const Text(
                  '3D Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),

                // Item count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.indigo.withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${widget.furniture.length} item${widget.furniture.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),

                // Drag hint
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.threesixty,
                        color: Colors.white.withOpacity(0.4),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Drag to orbit',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Main 3D canvas — full drag to orbit with no rotation limit
          GestureDetector(
            onPanStart: (details) {
              _dragStart = details.localPosition;
              _dragStartYaw = _yaw;
              _dragStartPitch = _pitch;
            },
            onPanUpdate: (details) {
              setState(() {
                // Horizontal drag = yaw (spin left/right) — no limit
                _yaw =
                    _dragStartYaw +
                    (details.localPosition.dx - _dragStart!.dx) * 0.007;

                // Vertical drag = pitch (tilt up/down) — full 360, no clamp
                _pitch =
                    _dragStartPitch -
                    (details.localPosition.dy - _dragStart!.dy) * 0.007;
              });
            },
            child: CustomPaint(
              painter: Room3DPainter(
                furniture: widget.furniture,
                roomWidth: widget.roomWidth,
                roomDepth: widget.roomDepth,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
              ),
              child: const SizedBox.expand(),
            ),
          ),

          // ── Zoom slider — bottom right, styled like MS Word ──────────────
          Positioned(
            right: 16,
            bottom: 24,
            child: _ZoomControl(
              zoom: _zoom,
              min: _minZoom,
              max: _maxZoom,
              label: _zoomLabel,
              onChanged: (v) => setState(() => _zoom = v),
              onReset: () => setState(() => _zoom = 1.0),
            ),
          ),

          // ── Camera reset button — bottom left ────────────────────────────
          Positioned(
            left: 16,
            bottom: 24,
            child: Tooltip(
              message: 'Reset camera',
              child: GestureDetector(
                onTap: () => setState(() {
                  _yaw = 0.5;
                  _pitch = 0.55;
                  _zoom = 1.0;
                }),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.home_outlined,
                        color: Colors.white.withOpacity(0.7),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Reset',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom control widget — horizontal slider with +/- buttons and a label.
// Styled similar to the zoom bar in MS Word / Google Docs.
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomControl extends StatelessWidget {
  final double zoom;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const _ZoomControl({
    required this.zoom,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C30).withOpacity(0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus button
          _IconBtn(
            icon: Icons.remove,
            onTap: () => onChanged((zoom - 0.1).clamp(min, max)),
          ),
          const SizedBox(width: 4),

          // Slider
          SizedBox(
            width: 140,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.indigo[300],
                inactiveTrackColor: Colors.white.withOpacity(0.15),
                thumbColor: Colors.white,
                overlayColor: Colors.indigo.withOpacity(0.2),
              ),
              child: Slider(
                value: zoom.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Plus button
          _IconBtn(
            icon: Icons.add,
            onTap: () => onChanged((zoom + 0.1).clamp(min, max)),
          ),
          const SizedBox(width: 8),

          // Percentage label — tap to reset to 100%
          GestureDetector(
            onTap: onReset,
            child: Container(
              width: 46,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, color: Colors.white70, size: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — all 3D math lives here.
// ─────────────────────────────────────────────────────────────────────────────

class Room3DPainter extends CustomPainter {
  final List<FurnitureModel> furniture;
  final double roomWidth;
  final double roomDepth;
  final double yaw;
  final double pitch;
  final double zoom;

  Room3DPainter({
    required this.furniture,
    required this.roomWidth,
    required this.roomDepth,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  // Scale converts 2D canvas pixels to 3D world units.
  static const double _baseScale = 0.35;
  // Base field-of-view distance for perspective division.
  static const double _fov = 850.0;
  // Room wall height in canvas pixels before scaling.
  static const double _wallHeightPx = 220.0;

  double get _scale => _baseScale * zoom;

  // Projects a 3D world point to a 2D screen offset.
  // The room is centred on the origin before applying camera rotations.
  Offset _project(double wx, double wy, double wz, Size screen) {
    final cx = wx - (roomWidth * _scale) / 2;
    final cz = wz - (roomDepth * _scale) / 2;

    // Yaw — rotate around the vertical Y axis.
    final rx = cx * Math.cos(yaw) + cz * Math.sin(yaw);
    final rz = -cx * Math.sin(yaw) + cz * Math.cos(yaw);

    // Pitch — tilt the camera by rotating around the X axis.
    final ry = wy * Math.cos(pitch) - rz * Math.sin(pitch);
    final rz2 = wy * Math.sin(pitch) + rz * Math.cos(pitch);

    // Perspective division.
    final camZ = rz2 + _fov;
    if (camZ <= 0.1) return Offset(screen.width / 2, screen.height / 2);

    final sx = (rx / camZ) * _fov + screen.width / 2;
    final sy = (-ry / camZ) * _fov + screen.height * 0.46;

    return Offset(sx, sy);
  }

  void _fillFace(
    Canvas canvas,
    List<Offset> pts,
    Color color, {
    double strokeOpacity = 0.18,
  }) {
    if (pts.length < 3) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) path.lineTo(p.dx, p.dy);
    path.close();

    canvas.drawPath(path, Paint()..color = color);

    if (strokeOpacity > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withOpacity(strokeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  // Returns a darkened copy of colour for Lambert shading.
  Color _shade(Color color, double amount) {
    return Color.fromARGB(
      color.alpha,
      (color.red * (1 - amount)).round().clamp(0, 255),
      (color.green * (1 - amount)).round().clamp(0, 255),
      (color.blue * (1 - amount)).round().clamp(0, 255),
    );
  }

  double _furnitureHeightPx(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return 80;
      case FurnitureType.table:
        return 75;
      case FurnitureType.sofa:
        return 90;
    }
  }

  void _drawFurnitureBox(Canvas canvas, Size screen, FurnitureModel item) {
    final sceneH = _furnitureHeightPx(item.type) * _scale;
    final hw = (item.size.width * _scale) / 2;
    final hd = (item.size.height * _scale) / 2;
    final cx = (item.position.dx + item.size.width / 2) * _scale;
    final cz = (item.position.dy + item.size.height / 2) * _scale;

    final r = item.rotation;
    final corners =
        [
          [-hw, -hd],
          [hw, -hd],
          [hw, hd],
          [-hw, hd],
        ].map((c) {
          final lx = c[0], lz = c[1];
          return [
            cx + lx * Math.cos(r) - lz * Math.sin(r),
            cz + lx * Math.sin(r) + lz * Math.cos(r),
          ];
        }).toList();

    final bot = corners.map((c) => _project(c[0], 0, c[1], screen)).toList();
    final top = corners
        .map((c) => _project(c[0], sceneH, c[1], screen))
        .toList();

    final base = item.color;

    // Five faces with simple directional shading.
    _fillFace(canvas, [top[0], top[1], top[2], top[3]], base); // top
    _fillFace(canvas, [
      bot[0],
      bot[1],
      top[1],
      top[0],
    ], _shade(base, 0.28)); // front
    _fillFace(canvas, [
      bot[1],
      bot[2],
      top[2],
      top[1],
    ], _shade(base, 0.48)); // right
    _fillFace(
      canvas,
      [bot[2], bot[3], top[3], top[2]],
      _shade(base, 0.38),
      strokeOpacity: 0.08,
    ); // back
    _fillFace(
      canvas,
      [bot[3], bot[0], top[0], top[3]],
      _shade(base, 0.33),
      strokeOpacity: 0.08,
    ); // left

    // Label on top face so you can tell items apart.
    final label = item.type.name[0].toUpperCase();
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final topCentre = Offset(
      (top[0].dx + top[1].dx + top[2].dx + top[3].dx) / 4 - tp.width / 2,
      (top[0].dy + top[1].dy + top[2].dy + top[3].dy) / 4 - tp.height / 2,
    );
    tp.paint(canvas, topCentre);
  }

  double _cameraDistance(FurnitureModel item) {
    final cx =
        (item.position.dx + item.size.width / 2) * _scale -
        (roomWidth * _scale) / 2;
    final cz =
        (item.position.dy + item.size.height / 2) * _scale -
        (roomDepth * _scale) / 2;
    final rx = cx * Math.cos(yaw) + cz * Math.sin(yaw);
    final rz = -cx * Math.sin(yaw) + cz * Math.cos(yaw);
    return rz * Math.cos(pitch);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0D1A), Color(0xFF181830)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final rw = roomWidth * _scale;
    final rd = roomDepth * _scale;
    final wh = _wallHeightPx * _scale;

    final f0 = _project(0, 0, 0, size);
    final f1 = _project(rw, 0, 0, size);
    final f2 = _project(rw, 0, rd, size);
    final f3 = _project(0, 0, rd, size);

    // Floor
    _fillFace(
      canvas,
      [f0, f1, f2, f3],
      const Color(0xFF20203A),
      strokeOpacity: 0,
    );

    // Floor grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.055)
      ..strokeWidth = 0.6;
    const step = 60.0;
    for (double gx = 0; gx <= roomWidth; gx += step) {
      canvas.drawLine(
        _project(gx * _scale, 0, 0, size),
        _project(gx * _scale, 0, rd, size),
        gridPaint,
      );
    }
    for (double gz = 0; gz <= roomDepth; gz += step) {
      canvas.drawLine(
        _project(0, 0, gz * _scale, size),
        _project(rw, 0, gz * _scale, size),
        gridPaint,
      );
    }

    // Back wall
    _fillFace(
      canvas,
      [f0, f1, _project(rw, wh, 0, size), _project(0, wh, 0, size)],
      const Color(0xFF2A2A44),
      strokeOpacity: 0.1,
    );

    // Left wall
    _fillFace(
      canvas,
      [f0, _project(0, wh, 0, size), _project(0, wh, rd, size), f3],
      const Color(0xFF252540),
      strokeOpacity: 0.1,
    );

    // Baseboard accent lines
    final baseboard = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 1.2;
    canvas.drawLine(f0, f1, baseboard);
    canvas.drawLine(f0, f3, baseboard);

    // Furniture — sorted back-to-front
    final sorted = List<FurnitureModel>.from(furniture)
      ..sort((a, b) => _cameraDistance(b).compareTo(_cameraDistance(a)));
    for (final item in sorted) {
      _drawFurnitureBox(canvas, size, item);
    }
  }

  @override
  bool shouldRepaint(covariant Room3DPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.furniture.length != furniture.length;
}
