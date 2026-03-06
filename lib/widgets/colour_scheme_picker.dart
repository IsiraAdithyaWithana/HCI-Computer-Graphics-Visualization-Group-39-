import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomColourScheme — data model
// ─────────────────────────────────────────────────────────────────────────────

class RoomColourScheme {
  final String id;
  final String name;
  final String description;
  final String mood;
  final Color wall;
  final Color floor;
  final Color ceiling;
  final Color accent;
  final Color trim;

  const RoomColourScheme({
    required this.id,
    required this.name,
    required this.description,
    required this.mood,
    required this.wall,
    required this.floor,
    required this.ceiling,
    required this.accent,
    required this.trim,
  });

  RoomColourScheme copyWith({
    Color? wall,
    Color? floor,
    Color? ceiling,
    Color? accent,
    Color? trim,
  }) {
    return RoomColourScheme(
      id: id,
      name: name,
      description: description,
      mood: mood,
      wall: wall ?? this.wall,
      floor: floor ?? this.floor,
      ceiling: ceiling ?? this.ceiling,
      accent: accent ?? this.accent,
      trim: trim ?? this.trim,
    );
  }

  List<Color> get paletteSwatches => [wall, floor, ceiling, accent, trim];
}

// ── Curated presets ───────────────────────────────────────────────────────────

const List<RoomColourScheme> kColourPresets = [
  RoomColourScheme(
    id: 'nordic_dust',
    name: 'Nordic Dust',
    description: 'Hushed greys and bone white',
    mood: 'Calm',
    wall: Color(0xFFE8E4DF),
    floor: Color(0xFFC9B89A),
    ceiling: Color(0xFFF5F3F0),
    accent: Color(0xFF7A8E8F),
    trim: Color(0xFFD6D0C8),
  ),
  RoomColourScheme(
    id: 'warm_terracotta',
    name: 'Warm Terracotta',
    description: 'Sun-baked earth and olive',
    mood: 'Energetic',
    wall: Color(0xFFD4856A),
    floor: Color(0xFF8B6B4A),
    ceiling: Color(0xFFF2E8DF),
    accent: Color(0xFF6B7C4A),
    trim: Color(0xFFE8C9A8),
  ),
  RoomColourScheme(
    id: 'coastal_linen',
    name: 'Coastal Linen',
    description: 'Sea glass and bleached sand',
    mood: 'Serene',
    wall: Color(0xFFB8CDD6),
    floor: Color(0xFFD4C4A0),
    ceiling: Color(0xFFF0EFEB),
    accent: Color(0xFF4A7A8A),
    trim: Color(0xFFE0D8CC),
  ),
  RoomColourScheme(
    id: 'midnight_velvet',
    name: 'Midnight Velvet',
    description: 'Deep navy and burnished brass',
    mood: 'Dramatic',
    wall: Color(0xFF1E2A3A),
    floor: Color(0xFF3A2E22),
    ceiling: Color(0xFF152030),
    accent: Color(0xFFC9A96E),
    trim: Color(0xFF2A3848),
  ),
  RoomColourScheme(
    id: 'forest_retreat',
    name: 'Forest Retreat',
    description: 'Sage green and warm walnut',
    mood: 'Grounded',
    wall: Color(0xFF8A9E8A),
    floor: Color(0xFF7A5E40),
    ceiling: Color(0xFFEEEAE4),
    accent: Color(0xFF4A6048),
    trim: Color(0xFFBEC9BE),
  ),
  RoomColourScheme(
    id: 'blush_studio',
    name: 'Blush Studio',
    description: 'Dusty rose and pale gold',
    mood: 'Romantic',
    wall: Color(0xFFE8C4BC),
    floor: Color(0xFFC8A882),
    ceiling: Color(0xFFF8F0EC),
    accent: Color(0xFFB8906A),
    trim: Color(0xFFF0DDD8),
  ),
  RoomColourScheme(
    id: 'slate_modernist',
    name: 'Slate Modernist',
    description: 'Concrete grey and graphite',
    mood: 'Bold',
    wall: Color(0xFF8A9098),
    floor: Color(0xFF4A5058),
    ceiling: Color(0xFFE8EAEC),
    accent: Color(0xFFD4A84A),
    trim: Color(0xFFB0B8C0),
  ),
  RoomColourScheme(
    id: 'cream_luxe',
    name: 'Cream Luxe',
    description: 'Ivory white and champagne',
    mood: 'Elegant',
    wall: Color(0xFFF0EAE0),
    floor: Color(0xFFD8C8A8),
    ceiling: Color(0xFFFAF8F4),
    accent: Color(0xFFC9A96E),
    trim: Color(0xFFE8E0D0),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// ColourSchemePicker  — full-screen panel
// ─────────────────────────────────────────────────────────────────────────────

class ColourSchemePicker extends StatefulWidget {
  final RoomColourScheme? initialScheme;
  final void Function(RoomColourScheme scheme)? onApply;

  const ColourSchemePicker({super.key, this.initialScheme, this.onApply});

  /// Convenience: push as a full route
  static Future<RoomColourScheme?> show(
    BuildContext context, {
    RoomColourScheme? initial,
  }) {
    return Navigator.of(context).push<RoomColourScheme>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => ColourSchemePicker(
          initialScheme: initial,
          onApply: (s) => Navigator.of(context).pop(s),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.0, 0.04), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<ColourSchemePicker> createState() => _ColourSchemePickerState();
}

class _ColourSchemePickerState extends State<ColourSchemePicker>
    with SingleTickerProviderStateMixin {
  late RoomColourScheme _active;
  String? _selectedPresetId;
  _EditTarget _editTarget = _EditTarget.none;

  late final AnimationController _previewAnim;
  late Animation<double> _previewScale;

  @override
  void initState() {
    super.initState();
    _active = widget.initialScheme ?? kColourPresets.first;
    _selectedPresetId = _findMatchingPreset(_active);

    _previewAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _previewScale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _previewAnim, curve: Curves.easeOutBack));
    _previewAnim.forward();
  }

  @override
  void dispose() {
    _previewAnim.dispose();
    super.dispose();
  }

  String? _findMatchingPreset(RoomColourScheme scheme) {
    for (final p in kColourPresets) {
      if (p.wall == scheme.wall &&
          p.floor == scheme.floor &&
          p.ceiling == scheme.ceiling &&
          p.accent == scheme.accent &&
          p.trim == scheme.trim) {
        return p.id;
      }
    }
    return null;
  }

  void _selectPreset(RoomColourScheme preset) {
    setState(() {
      _active = preset;
      _selectedPresetId = preset.id;
      _editTarget = _EditTarget.none;
    });
    _previewAnim
      ..reset()
      ..forward();
    HapticFeedback.lightImpact();
  }

  void _updateSurface(Color c) {
    setState(() {
      _selectedPresetId = null;
      switch (_editTarget) {
        case _EditTarget.wall:
          _active = _active.copyWith(wall: c);
          break;
        case _EditTarget.floor:
          _active = _active.copyWith(floor: c);
          break;
        case _EditTarget.ceiling:
          _active = _active.copyWith(ceiling: c);
          break;
        case _EditTarget.accent:
          _active = _active.copyWith(accent: c);
          break;
        case _EditTarget.trim:
          _active = _active.copyWith(trim: c);
          break;
        case _EditTarget.none:
          break;
      }
    });
  }

  void _apply() {
    widget.onApply?.call(_active);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D11),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left — preset gallery
                  _buildPresetGallery(),
                  // Centre — live preview
                  Expanded(child: _buildPreviewColumn()),
                  // Right — surface editors
                  _buildSurfacePanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: Color(0xFF17171F),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C3E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: Color(0xFF8E8A9A),
            ),
            tooltip: 'Back',
            splashRadius: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'COLOUR SCHEME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC9A96E),
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 16, color: const Color(0xFF2C2C3E)),
          const SizedBox(width: 12),
          Text(
            _active.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFFF0EDE8),
            ),
          ),
          const Spacer(),
          // Palette preview strip
          Row(
            children: _active.paletteSwatches
                .map(
                  (c) => Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(width: 20),
          _GoldButton(
            label: 'Apply Scheme',
            icon: Icons.check_rounded,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }

  // ── Preset gallery ─────────────────────────────────────────────────────────

  Widget _buildPresetGallery() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF17171F),
        border: Border(right: BorderSide(color: Color(0xFF2C2C3E))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'PRESETS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF56535F),
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: kColourPresets.length,
              itemBuilder: (_, i) => _PresetTile(
                preset: kColourPresets[i],
                selected: _selectedPresetId == kColourPresets[i].id,
                onTap: () => _selectPreset(kColourPresets[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Centre preview ─────────────────────────────────────────────────────────

  Widget _buildPreviewColumn() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scheme info
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _active.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF0EDE8),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _active.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8A9A),
                      ),
                    ),
                  ],
                ),
              ),
              _MoodTag(mood: _active.mood),
            ],
          ),
          const SizedBox(height: 20),
          // Room preview
          Expanded(
            child: ScaleTransition(
              scale: _previewScale,
              child: _RoomPreview(scheme: _active),
            ),
          ),
          const SizedBox(height: 16),
          // Harmony bar
          _HarmonyBar(scheme: _active),
        ],
      ),
    );
  }

  // ── Surface panel ──────────────────────────────────────────────────────────

  Widget _buildSurfacePanel() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF17171F),
        border: Border(left: BorderSide(color: Color(0xFF2C2C3E))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'SURFACES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF56535F),
                letterSpacing: 1.4,
              ),
            ),
          ),
          // Scrollable middle section — surface rows + swatch picker
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SurfaceRow(
                    label: 'WALLS',
                    icon: Icons.format_paint_outlined,
                    color: _active.wall,
                    selected: _editTarget == _EditTarget.wall,
                    onTap: () => setState(
                      () => _editTarget = _editTarget == _EditTarget.wall
                          ? _EditTarget.none
                          : _EditTarget.wall,
                    ),
                  ),
                  _SurfaceRow(
                    label: 'FLOOR',
                    icon: Icons.layers_outlined,
                    color: _active.floor,
                    selected: _editTarget == _EditTarget.floor,
                    onTap: () => setState(
                      () => _editTarget = _editTarget == _EditTarget.floor
                          ? _EditTarget.none
                          : _EditTarget.floor,
                    ),
                  ),
                  _SurfaceRow(
                    label: 'CEILING',
                    icon: Icons.space_bar_rounded,
                    color: _active.ceiling,
                    selected: _editTarget == _EditTarget.ceiling,
                    onTap: () => setState(
                      () => _editTarget = _editTarget == _EditTarget.ceiling
                          ? _EditTarget.none
                          : _EditTarget.ceiling,
                    ),
                  ),
                  _SurfaceRow(
                    label: 'ACCENT',
                    icon: Icons.star_border_rounded,
                    color: _active.accent,
                    selected: _editTarget == _EditTarget.accent,
                    onTap: () => setState(
                      () => _editTarget = _editTarget == _EditTarget.accent
                          ? _EditTarget.none
                          : _EditTarget.accent,
                    ),
                  ),
                  _SurfaceRow(
                    label: 'TRIM & SKIRTING',
                    icon: Icons.border_style_rounded,
                    color: _active.trim,
                    selected: _editTarget == _EditTarget.trim,
                    onTap: () => setState(
                      () => _editTarget = _editTarget == _EditTarget.trim
                          ? _EditTarget.none
                          : _EditTarget.trim,
                    ),
                  ),
                  // Inline colour swatch picker
                  if (_editTarget != _EditTarget.none) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(
                        'PICK COLOUR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF56535F),
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    _SwatchPicker(
                      currentColour: _currentEditColour,
                      onColourSelected: _updateSurface,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          // Hex display strip — pinned to bottom
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Divider(color: Color(0xFF2C2C3E), height: 1),
                const SizedBox(height: 14),
                _HexRow(label: 'Walls', color: _active.wall),
                _HexRow(label: 'Floor', color: _active.floor),
                _HexRow(label: 'Ceiling', color: _active.ceiling),
                _HexRow(label: 'Accent', color: _active.accent),
                _HexRow(label: 'Trim', color: _active.trim),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _currentEditColour {
    switch (_editTarget) {
      case _EditTarget.wall:
        return _active.wall;
      case _EditTarget.floor:
        return _active.floor;
      case _EditTarget.ceiling:
        return _active.ceiling;
      case _EditTarget.accent:
        return _active.accent;
      case _EditTarget.trim:
        return _active.trim;
      case _EditTarget.none:
        return Colors.transparent;
    }
  }
}

enum _EditTarget { none, wall, floor, ceiling, accent, trim }

// ─────────────────────────────────────────────────────────────────────────────
// _RoomPreview — isometric-style 3-wall room cross section
// ─────────────────────────────────────────────────────────────────────────────

class _RoomPreview extends StatelessWidget {
  final RoomColourScheme scheme;
  const _RoomPreview({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        return Container(
          width: c.maxWidth,
          height: c.maxHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D11),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2C2C3E)),
          ),
          clipBehavior: Clip.hardEdge,
          child: CustomPaint(
            painter: _RoomPainter(scheme: scheme),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'LIVE PREVIEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: scheme.ceiling.computeLuminance() > 0.5
                        ? const Color(0x445555AA)
                        : Colors.white.withOpacity(0.15),
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomPainter extends CustomPainter {
  final RoomColourScheme scheme;
  const _RoomPainter({required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Padding / margins
    final pad = w * 0.06;
    final left = pad;
    final right = w - pad;
    final top = h * 0.08;
    final bottom = h - pad * 0.8;

    // Perspective vanishing-point style corners
    final vanishX = w * 0.5;
    final vanishY = h * 0.35;

    // Room depth split
    final floorY = h * 0.62;
    final ceilY = h * 0.14;

    // ── Background ceiling ─────────────────────────────────────────────────
    final ceilPath = Path()
      ..moveTo(left, ceilY)
      ..lineTo(right, ceilY)
      ..lineTo(right, floorY * 0.08 + ceilY * 0.92)
      ..lineTo(left, floorY * 0.08 + ceilY * 0.92)
      ..close();

    // ── Back wall ──────────────────────────────────────────────────────────
    final backWallPath = Path()
      ..moveTo(left, ceilY)
      ..lineTo(right, ceilY)
      ..lineTo(right, floorY)
      ..lineTo(left, floorY)
      ..close();
    canvas.drawPath(backWallPath, Paint()..color = scheme.wall);

    // Subtle lighting gradient overlay on back wall
    final wallGradPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withOpacity(0.06),
          Colors.transparent,
          Colors.black.withOpacity(0.10),
        ],
      ).createShader(Rect.fromLTWH(left, ceilY, right - left, floorY - ceilY));
    canvas.drawPath(backWallPath, wallGradPaint);

    // ── Floor ──────────────────────────────────────────────────────────────
    final floorPath = Path()
      ..moveTo(left, floorY)
      ..lineTo(right, floorY)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(floorPath, Paint()..color = scheme.floor);

    // Floor grain gradient
    final floorGradPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.18), Colors.transparent],
          ).createShader(
            Rect.fromLTWH(left, floorY, right - left, bottom - floorY),
          );
    canvas.drawPath(floorPath, floorGradPaint);

    // Floor planks (subtle lines)
    final plankPaint = Paint()
      ..color = scheme.floor.computeLuminance() > 0.5
          ? Colors.black.withOpacity(0.06)
          : Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.8;
    final plankCount = 6;
    for (var i = 1; i < plankCount; i++) {
      final y = floorY + (bottom - floorY) * (i / plankCount);
      canvas.drawLine(Offset(left, y), Offset(right, y), plankPaint);
    }

    // ── Ceiling ────────────────────────────────────────────────────────────
    final ceilingPath = Path()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..lineTo(right, ceilY)
      ..lineTo(left, ceilY)
      ..close();
    canvas.drawPath(ceilingPath, Paint()..color = scheme.ceiling);

    // ── Trim / skirting board ──────────────────────────────────────────────
    final skirtH = (bottom - floorY) * 0.18;
    final skirtPath = Path()
      ..moveTo(left, floorY)
      ..lineTo(right, floorY)
      ..lineTo(right, floorY + skirtH)
      ..lineTo(left, floorY + skirtH)
      ..close();
    canvas.drawPath(skirtPath, Paint()..color = scheme.trim);

    // Trim cornice (top)
    final corniceH = (floorY - ceilY) * 0.06;
    final cornicePath = Path()
      ..moveTo(left, ceilY)
      ..lineTo(right, ceilY)
      ..lineTo(right, ceilY + corniceH)
      ..lineTo(left, ceilY + corniceH)
      ..close();
    canvas.drawPath(cornicePath, Paint()..color = scheme.trim);

    // ── Wall dividing line ─────────────────────────────────────────────────
    final divPaint = Paint()
      ..color = scheme.accent.withOpacity(0.3)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(left, floorY), Offset(right, floorY), divPaint);

    // ── Accent: decorative wall panel ─────────────────────────────────────
    final panelW = (right - left) * 0.42;
    final panelH = (floorY - ceilY) * 0.52;
    final panelLeft = left + (right - left) * 0.29;
    final panelTop = ceilY + (floorY - ceilY) * 0.24;
    final panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelLeft, panelTop, panelW, panelH),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      panelRect,
      Paint()
        ..color = scheme.accent.withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      panelRect,
      Paint()
        ..color = scheme.accent.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Window light ──────────────────────────────────────────────────────
    final winLeft = left + (right - left) * 0.07;
    final winTop = ceilY + (floorY - ceilY) * 0.18;
    final winW = (right - left) * 0.18;
    final winH = (floorY - ceilY) * 0.45;
    final winRect = Rect.fromLTWH(winLeft, winTop, winW, winH);
    canvas.drawRect(
      winRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFEDC8), Color(0xFFFFF3D0)],
        ).createShader(winRect),
    );
    // Window cross frame
    final framePaint = Paint()
      ..color = scheme.trim.withOpacity(0.9)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(winLeft + winW / 2, winTop),
      Offset(winLeft + winW / 2, winTop + winH),
      framePaint,
    );
    canvas.drawLine(
      Offset(winLeft, winTop + winH * 0.48),
      Offset(winLeft + winW, winTop + winH * 0.48),
      framePaint,
    );
    // Window border
    canvas.drawRect(
      winRect,
      Paint()
        ..color = scheme.trim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Window light spill on floor
    final spillPath = Path()
      ..moveTo(winLeft, floorY)
      ..lineTo(winLeft + winW, floorY)
      ..lineTo(winLeft + winW * 1.4, bottom)
      ..lineTo(winLeft - winW * 0.3, bottom)
      ..close();
    canvas.drawPath(
      spillPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFFEDC8).withOpacity(0.22),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromLTWH(
                winLeft - winW,
                floorY,
                winW * 2.5,
                bottom - floorY,
              ),
            ),
    );

    // ── Stylised sofa (furniture hint) ────────────────────────────────────
    _drawSofa(canvas, scheme, left, right, floorY, bottom);
  }

  void _drawSofa(
    Canvas canvas,
    RoomColourScheme scheme,
    double left,
    double right,
    double floorY,
    double bottom,
  ) {
    final sofaColour = _blendWithAccent(scheme.accent, scheme.floor, 0.35);
    final sofaW = (right - left) * 0.38;
    final sofaH = (bottom - floorY) * 0.55;
    final sofaLeft = left + (right - left) * 0.52;
    final sofaTop = floorY + (bottom - floorY) * 0.08;

    final sofaBody = RRect.fromRectAndRadius(
      Rect.fromLTWH(sofaLeft, sofaTop, sofaW, sofaH * 0.65),
      const Radius.circular(5),
    );
    canvas.drawRRect(sofaBody, Paint()..color = sofaColour);

    // Back cushion
    final backCushion = RRect.fromRectAndRadius(
      Rect.fromLTWH(sofaLeft, sofaTop, sofaW, sofaH * 0.30),
      const Radius.circular(4),
    );
    canvas.drawRRect(backCushion, Paint()..color = _darken(sofaColour, 0.10));

    // Legs
    final legPaint = Paint()..color = _darken(scheme.floor, 0.20);
    final legW = sofaW * 0.07;
    final legH = sofaH * 0.20;
    canvas.drawRect(
      Rect.fromLTWH(sofaLeft + sofaW * 0.06, sofaTop + sofaH * 0.6, legW, legH),
      legPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(sofaLeft + sofaW * 0.87, sofaTop + sofaH * 0.6, legW, legH),
      legPaint,
    );

    // Accent cushion
    final cushionSize = sofaW * 0.18;
    final cushionLeft = sofaLeft + sofaW * 0.36;
    final cushionTop = sofaTop + sofaH * 0.05;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cushionLeft, cushionTop, cushionSize, cushionSize),
        const Radius.circular(3),
      ),
      Paint()..color = scheme.accent.withOpacity(0.85),
    );
  }

  Color _blendWithAccent(Color a, Color b, double t) => Color.lerp(b, a, t)!;

  Color _darken(Color c, double amount) => HSLColor.fromColor(c)
      .withLightness((HSLColor.fromColor(c).lightness - amount).clamp(0.0, 1.0))
      .toColor();

  @override
  bool shouldRepaint(_RoomPainter old) => old.scheme != scheme;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PresetTile extends StatelessWidget {
  final RoomColourScheme preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF252534) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9A96E).withOpacity(0.6)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Mini swatch grid
            SizedBox(
              width: 32,
              height: 32,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _MiniPalette(scheme: preset),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? const Color(0xFFF0EDE8)
                          : const Color(0xFFB0ACC0),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    preset.mood,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF56535F),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: Color(0xFFC9A96E),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniPalette extends StatelessWidget {
  final RoomColourScheme scheme;
  const _MiniPalette({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final colours = [scheme.ceiling, scheme.wall, scheme.accent, scheme.floor];
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      children: colours.map((c) => Container(color: c)).toList(),
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SurfaceRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF252534) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9A96E).withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF8E8A9A)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFF0EDE8)
                    : const Color(0xFF8E8A9A),
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            // Colour swatch
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.edit_outlined,
                size: 12,
                color: Color(0xFFC9A96E),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Inline swatch palette
class _SwatchPicker extends StatelessWidget {
  final Color currentColour;
  final void Function(Color) onColourSelected;

  const _SwatchPicker({
    required this.currentColour,
    required this.onColourSelected,
  });

  static const List<Color> _swatches = [
    // Whites & creams
    Color(0xFFFAF8F4), Color(0xFFF5F2ED), Color(0xFFEDE9E0), Color(0xFFE0D9D0),
    // Greys
    Color(0xFFCCCAC5), Color(0xFFB0ACA5), Color(0xFF8A8880), Color(0xFF5A5855),
    // Charcoals & darks
    Color(0xFF3A3835), Color(0xFF252320), Color(0xFF17171F), Color(0xFF0D0D11),
    // Warm neutrals
    Color(0xFFD4C4A0), Color(0xFFC9B89A), Color(0xFFB8A882), Color(0xFF9E8A68),
    // Terracottas
    Color(0xFFE8C0A8), Color(0xFFD4856A), Color(0xFFB86050), Color(0xFF8A4030),
    // Greens
    Color(0xFFBEC9BE), Color(0xFF8A9E8A), Color(0xFF5A7A5A), Color(0xFF344A34),
    // Blues
    Color(0xFFB8CDD6), Color(0xFF6A9AB0), Color(0xFF3A6A82), Color(0xFF1E3A52),
    // Navies
    Color(0xFF2A3848), Color(0xFF1E2A3A), Color(0xFF152030), Color(0xFF0A1220),
    // Golds & accents
    Color(0xFFE8D5B0), Color(0xFFC9A96E), Color(0xFF9E7A44), Color(0xFF6A4E20),
    // Pinks / roses
    Color(0xFFF0DDD8), Color(0xFFE8C4BC), Color(0xFFD0907A), Color(0xFFB06060),
    // Sages
    Color(0xFFD0DACC), Color(0xFF9AB0A0), Color(0xFF6A8878), Color(0xFF3A5848),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _swatches.map((c) {
          final isSelected = c == currentColour;
          return GestureDetector(
            onTap: () => onColourSelected(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFC9A96E)
                      : Colors.white.withOpacity(0.08),
                  width: isSelected ? 2.0 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFC9A96E).withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HarmonyBar extends StatelessWidget {
  final RoomColourScheme scheme;
  const _HarmonyBar({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final colours = scheme.paletteSwatches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PALETTE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF56535F),
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(colours.length * 2 - 1, (i) {
            if (i.isOdd) {
              return const SizedBox(width: 3);
            }
            final colour = colours[i ~/ 2];
            final labels = ['Walls', 'Floor', 'Ceiling', 'Accent', 'Trim'];
            final label = labels[i ~/ 2];
            return Expanded(
              child: Tooltip(
                message:
                    '$label — #${colour.value.toRadixString(16).substring(2).toUpperCase()}',
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _HexRow extends StatelessWidget {
  final String label;
  final Color color;
  const _HexRow({required this.label, required this.color});

  String get _hex =>
      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF56535F)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _hex));
            },
            child: Text(
              _hex,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8A9A),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodTag extends StatelessWidget {
  final String mood;
  const _MoodTag({required this.mood});

  static const Map<String, Color> _moodColors = {
    'Calm': Color(0xFF4A9EE8),
    'Energetic': Color(0xFFE8A838),
    'Serene': Color(0xFF4CAF7D),
    'Dramatic': Color(0xFF9A4AE8),
    'Grounded': Color(0xFF7A8E6A),
    'Romantic': Color(0xFFE84A8A),
    'Bold': Color(0xFFE84A4A),
    'Elegant': Color(0xFFC9A96E),
  };

  @override
  Widget build(BuildContext context) {
    final c = _moodColors[mood] ?? const Color(0xFF8E8A9A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(
        mood.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: c,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _GoldButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFC9A96E),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC9A96E).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF0D0D11)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D0D11),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ColourSchemeButton — drop-in toolbar widget for Editor2DScreen
// ─────────────────────────────────────────────────────────────────────────────

/// A compact toolbar button that opens the ColourSchemePicker and calls back
/// with the chosen [RoomColourScheme].
///
/// Usage in editor_2d_screen.dart:
///
///   ColourSchemeButton(
///     current: _currentScheme,
///     onSchemeChanged: (s) => setState(() => _currentScheme = s),
///   )
class ColourSchemeButton extends StatelessWidget {
  final RoomColourScheme? current;
  final void Function(RoomColourScheme)? onSchemeChanged;

  const ColourSchemeButton({super.key, this.current, this.onSchemeChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = current ?? kColourPresets.first;
    return Tooltip(
      message: 'Colour Scheme',
      child: GestureDetector(
        onTap: () async {
          final result = await ColourSchemePicker.show(
            context,
            initial: scheme,
          );
          if (result != null) onSchemeChanged?.call(result);
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F2B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2C2C3E)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini swatch row
              ...scheme.paletteSwatches
                  .take(4)
                  .map(
                    (c) => Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(width: 6),
              const Text(
                'Colours',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E8A9A),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: Color(0xFF56535F),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
