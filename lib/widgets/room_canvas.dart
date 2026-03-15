import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
import '../models/room_shape.dart';
import 'dart:math' as Math;

enum MouseMode { select, hand, draw }

class RoomCanvas extends StatefulWidget {
  final FurnitureType selectedType;
  final MouseMode currentMode;
  final double roomWidthPx;
  final double roomDepthPx;
  final void Function(double zoom)? onZoomChanged;
  final VoidCallback? onChanged;

  /// Fired whenever canUndo or canRedo changes so the parent can rebuild its
  /// undo/redo buttons with the correct enabled state.
  final VoidCallback? onUndoStateChanged;

  // ── Colour scheme ──────────────────────────────────────────────────────
  /// Background colour for the entire canvas viewport (area outside the room).
  final Color canvasBgColour;

  /// Room floor colour shown in the 2D top-down canvas.
  final Color roomFloorColour;

  /// Wall/border colour for the room outline.
  final Color roomWallColour;

  // ── Custom furniture overrides ─────────────────────────────────────────
  // Set these when selectedType == FurnitureType.custom so the canvas knows
  // which GLB file and label to attach to newly placed custom items.
  final String? customGlbOverride;
  final String? customLabelOverride;
  final Color? customColor;

  /// The 2D footprint size stored in the registry entry for this custom type.
  /// When set, overrides the generic 80×80 custom default.
  final Size? customDefaultSize;

  /// Top-down PNG thumbnails from the 3D viewer.
  /// Key: FurnitureType.name for built-ins, glbFileName for custom GLBs.
  final Map<String, ui.Image> thumbnails;

  /// When true the ceiling layer is visible — shows the split ceiling canvas.
  final bool showCeilingLayer;

  /// Ceiling surface colour used as the ceiling canvas background tint.
  final Color ceilingColour;

  /// Shape of the room canvas.
  final RoomShape roomShape;

  /// Custom shape points (relative 0..1 coords) — only used when roomShape == custom.
  final List<Offset>? customShapePoints;

  /// Persistent size preferences per furniture type.
  /// Key: FurnitureType.name for built-ins, glbFileName for custom GLBs.
  /// Value: {'w': width, 'h': height, 'sf': scaleFactor}
  /// Supplied by the editor so new items always match the last user-chosen size,
  /// even when ALL items of that type have been deleted.
  final Map<String, Map<String, double>> typeSizePrefs;

  const RoomCanvas({
    super.key,
    required this.selectedType,
    required this.currentMode,
    this.roomWidthPx = 600,
    this.roomDepthPx = 500,
    this.onZoomChanged,
    this.canvasBgColour = const Color(0xFF0D0D11),
    this.roomFloorColour = const Color(0xFFFAF8F5),
    this.roomWallColour = const Color(0xFF4A4A5A),
    this.customGlbOverride,
    this.customLabelOverride,
    this.customColor,
    this.customDefaultSize,
    this.onChanged,
    this.onUndoStateChanged,
    this.thumbnails = const {},
    this.showCeilingLayer = false,
    this.ceilingColour = const Color(0xFFF0EDE8),
    this.typeSizePrefs = const {},
    this.roomShape = RoomShape.rectangle,
    this.customShapePoints,
  });

  @override
  State<RoomCanvas> createState() => RoomCanvasState();
}

class RoomCanvasState extends State<RoomCanvas> {
  List<FurnitureModel> furnitureItems = [];
  List<FurnitureModel> selectedItems = [];
  FurnitureModel? selectedItem;

  // ── Undo / Redo ────────────────────────────────────────────────────────────
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxHistory = 50;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Snapshot the current state before a mutation so it can be undone.
  void _pushUndo() {
    _undoStack.add(_exportSnapshot());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
    widget.onUndoStateChanged?.call();
  }

  String _exportSnapshot() {
    return jsonEncode(furnitureItems.map((f) => f.toJson()).toList());
  }

  void _restoreSnapshot(String snapshot) {
    try {
      final list = jsonDecode(snapshot) as List;
      setState(() {
        furnitureItems = list
            .map((e) => FurnitureModel.fromJson(e as Map<String, dynamic>))
            .toList();
        selectedItems.clear();
        selectedItem = null;
      });
    } catch (_) {}
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_exportSnapshot());
    _restoreSnapshot(_undoStack.removeLast());
    widget.onUndoStateChanged?.call();
    widget.onChanged?.call();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_exportSnapshot());
    _restoreSnapshot(_redoStack.removeLast());
    widget.onUndoStateChanged?.call();
    widget.onChanged?.call();
  }

  /// Called externally (e.g. from the 3D size-save callback) to snapshot the
  /// current state so the mutation that follows can be undone from the 2D canvas.
  void pushUndoExternal() => _pushUndo();

  Offset? _dragStart;
  bool _isRotating = false;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _isPanningCanvas = false;
  bool _isSelectingBox = false;
  Offset? _selectionStart;
  Offset? _selectionCurrent;

  /// Stores each dragged item's position at the moment dragging started.
  /// Used to snap back to the original position if the drop would cause overlap.
  Map<String, Offset> _preDragPositions = {};

  final _cursorPos = ValueNotifier<Offset?>(null);
  final _cursorAsset = ValueNotifier<String?>('assets/cursors/main_cursor.png');
  // ── Ceiling canvas cursor (separate so the two panels never interfere) ──
  final _cursorPosC = ValueNotifier<Offset?>(null);
  final _cursorAssetC = ValueNotifier<String?>(
    'assets/cursors/main_cursor.png',
  );
  // Separate dragging-live flag for ceiling so it doesn't pollute furniture cursor
  bool _isCeilingDragging = false;
  bool _isRotatingLive = false;
  bool _isResizingLive = false;
  bool _isDraggingLive = false;
  Offset? _drawTapPos;

  double _trackpadLastScale = 1.0;
  bool _isTrackpadActive = false;
  Offset _trackpadFocal = Offset.zero;

  final double gridSize = 20;
  bool enableSnap = true;
  bool snapResizeEnabled = true;
  static const double _cursorSize = 32;

  /// Returns the (dx, dy) offset to subtract from the pointer position when
  /// placing the cursor PNG overlay so the visual hotspot matches the actual
  /// interaction point.
  ///
  /// Arrow cursors have their hotspot at the tip (top-left → offset 0,0).
  /// Crosshair/move/rotate cursors have it at the centre → offset size/2, size/2.
  static Offset _cursorHotspot(String? asset) {
    if (asset == null) return Offset.zero;
    // Arrow pointers: hotspot is the tip at top-left of the image
    if (asset.contains('main_cursor') || asset.contains('add_cursor')) {
      return Offset.zero;
    }
    // All other cursors (move, rotate, expand, canvas/grab): hotspot is centre
    return const Offset(_cursorSize / 2, _cursorSize / 2);
  }

  static const double _canvasW = 5000;
  static const double _canvasH = 4000;

  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();

  // ── Public API ────────────────────────────────────────────────────────────
  bool get isSnapResizeEnabled => snapResizeEnabled;
  void toggleResizeSnap() =>
      setState(() => snapResizeEnabled = !snapResizeEnabled);
  double get currentZoom => _transformationController.value.getMaxScaleOnAxis();

  /// Called by the 3D screen when a custom GLB's real footprint is measured.
  /// [widthPx]/[depthPx] are always the TRUE natural size (scaleFactor=1.0).
  /// The displayed tile is set to naturalSize × scaleFactor so it matches the 3D model.
  void updateItemNaturalSize(String id, double widthPx, double depthPx) {
    final idx = furnitureItems.indexWhere((f) => f.id == id);
    if (idx == -1) return;
    final item = furnitureItems[idx];
    final sf = item.scaleFactor > 0 ? item.scaleFactor : 1.0;
    setState(() {
      item.size = Size(
        (widthPx * sf).clamp(20.0, 1200.0),
        (depthPx * sf).clamp(20.0, 1200.0),
      );
    });
    _save();
  }

  void setZoom(double zoom) {
    final current = _transformationController.value;
    final oldScale = current.getMaxScaleOnAxis();
    final ratio = zoom / oldScale;
    final box = context.findRenderObject() as RenderBox?;
    final centre = box != null
        ? Offset(box.size.width / 2, box.size.height / 2)
        : Offset.zero;
    _transformationController.value = current.clone()
      ..translate(centre.dx, centre.dy)
      ..scale(ratio)
      ..translate(-centre.dx, -centre.dy);
    widget.onZoomChanged?.call(zoom);
    setState(() {});
  }

  String exportToJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert(furnitureItems.map((e) => e.toJson()).toList());

  void loadFromJson(String jsonString) {
    final List decoded = jsonDecode(jsonString);
    setState(() {
      furnitureItems = decoded
          .map((e) => FurnitureModel.fromJson(e as Map<String, dynamic>))
          .map(_migrateFurnitureSize)
          .toList();
      selectedItems.clear();
      selectedItem = null;
    });
  }

  /// Corrects furniture sizes that were saved with wrong default dimensions.
  /// Called once on load so stale saved layouts are automatically fixed.
  FurnitureModel _migrateFurnitureSize(FurnitureModel item) {
    switch (item.type) {
      case FurnitureType.bench:
        // Old default was Size(140,50) — landscape and too wide.
        // Correct default is Size(30,100) — portrait, matches the 3D GLB.
        // Only migrate if the item still has the old wrong proportions
        // (width > height), so user-resized benches are left alone.
        if (item.size.width > item.size.height) {
          return FurnitureModel(
            id: item.id,
            type: item.type,
            position: item.position,
            size: const Size(30, 100),
            color: item.color,
            rotation: item.rotation,
            scaleFactor: item.scaleFactor,
            glbOverride: item.glbOverride,
            labelOverride: item.labelOverride,
            tintHex: item.tintHex,
          );
        }
        return item;
      case FurnitureType.table:
        // table.glb is portrait (narrow X, long Z) — same as bench.
        // Old saves may have the wrong landscape size (width > height).
        // Migrate to portrait so the 2D tile matches the 3D GLB.
        if (item.size.width > item.size.height) {
          return FurnitureModel(
            id: item.id,
            type: item.type,
            position: item.position,
            size: const Size(80, 120),
            color: item.color,
            rotation: item.rotation,
            scaleFactor: item.scaleFactor,
            glbOverride: item.glbOverride,
            labelOverride: item.labelOverride,
            tintHex: item.tintHex,
          );
        }
        return item;
      default:
        return item;
    }
  }

  void _save() => widget.onChanged?.call();

  // ── Coordinate helpers ────────────────────────────────────────────────────
  Offset _toScene(Offset screenPos) => MatrixUtils.transformPoint(
    Matrix4.inverted(_transformationController.value),
    screenPos,
  );

  Offset _globalToScene(Offset globalPos, {double xOffset = 0}) {
    final box = context.findRenderObject() as RenderBox;
    // xOffset adjusts for the ceiling panel being in the right half of a split Row
    final local = box.globalToLocal(globalPos) - Offset(xOffset, 0);
    return _toScene(local);
  }

  // ── Snap ──────────────────────────────────────────────────────────────────
  double _snap(double v) => enableSnap ? (v / gridSize).round() * gridSize : v;
  Offset _snapOffset(Offset o) => Offset(_snap(o.dx), _snap(o.dy));

  // ── Geometry ──────────────────────────────────────────────────────────────
  Offset _localRotated(FurnitureModel item, Offset p) {
    final c = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    final cos = Math.cos(-item.rotation);
    final sin = Math.sin(-item.rotation);
    return Offset(
      dx * cos - dy * sin + item.size.width / 2,
      dx * sin + dy * cos + item.size.height / 2,
    );
  }

  bool _inside(FurnitureModel item, Offset p) {
    final l = _localRotated(item, p);
    return l.dx >= 0 &&
        l.dx <= item.size.width &&
        l.dy >= 0 &&
        l.dy <= item.size.height;
  }

  // Returns the room shape path (cached for this frame via getter)
  Path get _roomShapePath => buildRoomPath(
    widget.roomShape,
    widget.roomWidthPx,
    widget.roomDepthPx,
    customPoints: widget.customShapePoints,
  );

  // Returns true if scene point [p] lies within the room shape
  bool _insideRoom(Offset p) {
    if (widget.roomShape == RoomShape.rectangle) {
      // Fast path for rectangle (most common case)
      return p.dx >= 0 &&
          p.dx <= widget.roomWidthPx &&
          p.dy >= 0 &&
          p.dy <= widget.roomDepthPx;
    }
    return insideShape(_roomShapePath, p);
  }

  bool _onResize(FurnitureModel item, Offset p) {
    final l = _localRotated(item, p);
    return (l - Offset(item.size.width, item.size.height)).distance <= 18;
  }

  bool _onRotate(FurnitureModel item, Offset p) {
    final c = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );
    final dist = item.size.height / 2 + 25;
    final h = Offset(
      c.dx + dist * Math.cos(item.rotation - 1.5708),
      c.dy + dist * Math.sin(item.rotation - 1.5708),
    );
    return (p - h).distance <= 35;
  }

  bool _onAnyHandle(Offset p) =>
      selectedItem != null &&
      (_onRotate(selectedItem!, p) || _onResize(selectedItem!, p));

  // ── Cursor ────────────────────────────────────────────────────────────────
  void _updateCursor(Offset scenePos, Offset localPos) {
    _cursorPos.value = localPos;

    // Always show default cursor when hovering outside the room floor
    if (!_insideRoom(scenePos)) {
      _cursorAsset.value = 'assets/cursors/main_cursor.png';
      return;
    }

    // Hand mode — canvas pan cursor (grab state is set in pan handlers)
    if (widget.currentMode == MouseMode.hand) {
      if (!_isPanningCanvas) {
        _cursorAsset.value = 'assets/cursors/canvas_cursor.png';
      }
      return;
    }

    // Draw / add mode
    if (widget.currentMode == MouseMode.draw) {
      _cursorAsset.value = 'assets/cursors/add_cursor.png';
      return;
    }

    // Select mode
    if (_isRotatingLive) {
      _cursorAsset.value = 'assets/cursors/rotate_cursor.png';
      return;
    }
    if (_isResizingLive) {
      _cursorAsset.value = 'assets/cursors/expand_cursor.png';
      return;
    }
    if (_isDraggingLive) {
      _cursorAsset.value = 'assets/cursors/move_cursor.png';
      return;
    }
    if (selectedItem != null) {
      if (_onRotate(selectedItem!, scenePos)) {
        _cursorAsset.value = 'assets/cursors/rotate_cursor.png';
        return;
      }
      // Resize cursor disabled — resize is done via the 3D scale panel
    }
    for (final item in furnitureItems.reversed) {
      if (_inside(item, scenePos)) {
        _cursorAsset.value = 'assets/cursors/move_cursor.png';
        return;
      }
    }
    _cursorAsset.value = 'assets/cursors/main_cursor.png';
  }

  // ── Ceiling canvas cursor ─────────────────────────────────────────────────
  // scenePos is d.localPosition (already scene coords inside Transform).
  // localPos is the raw local position used to place the PNG overlay.
  void _updateCeilingCursor(Offset scenePos, Offset localPos) {
    _cursorPosC.value = localPos;

    // Outside room floor → default arrow
    if (!_insideRoom(scenePos)) {
      _cursorAssetC.value = 'assets/cursors/main_cursor.png';
      return;
    }

    // Hand mode → canvas pan cursor
    if (widget.currentMode == MouseMode.hand) {
      _cursorAssetC.value = 'assets/cursors/canvas_cursor.png';
      return;
    }

    // Draw mode with ceiling spot selected → add cursor
    if (widget.currentMode == MouseMode.draw &&
        widget.selectedType == FurnitureType.ceilingSpot) {
      _cursorAssetC.value = 'assets/cursors/add_cursor.png';
      return;
    }

    // Draw mode but non-ceiling type selected → blocked, show default
    if (widget.currentMode == MouseMode.draw) {
      _cursorAssetC.value = 'assets/cursors/main_cursor.png';
      return;
    }

    // Active ceiling drag → keep move cursor
    if (_isCeilingDragging) {
      _cursorAssetC.value = 'assets/cursors/move_cursor.png';
      return;
    }

    // Hovering over a ceiling spot → move cursor
    for (final item in furnitureItems.reversed) {
      if (item.type != FurnitureType.ceilingSpot) continue;
      if (_inside(item, scenePos)) {
        _cursorAssetC.value = 'assets/cursors/move_cursor.png';
        return;
      }
    }

    _cursorAssetC.value = 'assets/cursors/main_cursor.png';
  }

  // ── Ceiling drag end / cancel helper ─────────────────────────────────────
  void _endCeilingDrag() {
    if (_isCeilingDragging && selectedItems.isNotEmpty) {
      setState(() {
        for (final item in selectedItems) {
          if (item.type == FurnitureType.ceilingSpot) {
            item.position = _clampToRoom(_snapOffset(item.position), item.size);
          }
        }
      });
      _save();
    }
    setState(() {
      _isCeilingDragging = false;
      _isPanningCanvas = false;
      _dragStart = null;
    });
    // Restore correct idle cursor based on active mode
    if (widget.currentMode == MouseMode.hand) {
      _cursorAssetC.value = 'assets/cursors/canvas_cursor.png';
    } else if (widget.currentMode == MouseMode.draw &&
        widget.selectedType == FurnitureType.ceilingSpot) {
      _cursorAssetC.value = 'assets/cursors/add_cursor.png';
    } else {
      _cursorAssetC.value = 'assets/cursors/main_cursor.png';
    }
  }

  // ── Context menu ──────────────────────────────────────────────────────────
  void _showContextMenu(Offset globalPos) async {
    if (selectedItem == null) return;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'rotate', child: Text('Rotate 90°')),
      ],
    );
    if (result == 'delete') {
      _pushUndo();
      setState(() {
        furnitureItems.removeWhere((i) => selectedItems.contains(i));
        selectedItems.clear();
        selectedItem = null;
      });
      _save();
    } else if (result == 'duplicate') {
      _pushUndo();
      final dupSize = selectedItem!.size;
      final freePos = _findFreePosition(
        selectedItem!.position + const Offset(20, 20),
        dupSize,
      );
      setState(() {
        furnitureItems.add(
          FurnitureModel(
            id: DateTime.now().toString(),
            type: selectedItem!.type,
            position: freePos,
            size: dupSize,
            color: selectedItem!.color,
            rotation: selectedItem!.rotation,
            glbOverride: selectedItem!.glbOverride,
            labelOverride: selectedItem!.labelOverride,
          ),
        );
      });
      _save();
    } else if (result == 'rotate') {
      _pushUndo();
      setState(() => selectedItem!.rotation += 1.5708);
      _save();
    }
  }

  // ── Defaults ──────────────────────────────────────────────────────────────
  Size _defaultSize(FurnitureType t) {
    switch (t) {
      case FurnitureType.chair:
        return const Size(60, 60);
      case FurnitureType.sofa:
        return const Size(160, 75);
      case FurnitureType.armchair:
        return const Size(80, 80);
      case FurnitureType.bench:
        return const Size(30, 100);
      case FurnitureType.stool:
        return const Size(45, 45);
      case FurnitureType.table:
        return const Size(80, 120); // table.glb is portrait (narrow X, long Z)
      case FurnitureType.coffeeTable:
        return const Size(100, 60);
      case FurnitureType.desk:
        return const Size(130, 70);
      case FurnitureType.sideTable:
        return const Size(50, 50);
      case FurnitureType.wardrobe:
        return const Size(120, 60);
      case FurnitureType.bookshelf:
        return const Size(100, 40);
      case FurnitureType.cabinet:
        return const Size(80, 50);
      case FurnitureType.dresser:
        return const Size(100, 50);
      case FurnitureType.bed:
        return const Size(140, 180);
      case FurnitureType.singleBed:
        return const Size(100, 180);
      case FurnitureType.nightstand:
        return const Size(50, 50);
      case FurnitureType.plant:
        return const Size(50, 50);
      case FurnitureType.lamp:
        return const Size(40, 60);
      case FurnitureType.tvStand:
        return const Size(160, 50);
      case FurnitureType.rug:
        return const Size(160, 120);
      // ── Lights ────────────────────────────────────────────────────────
      case FurnitureType.floorLampLight:
        return const Size(30, 30);
      case FurnitureType.tableLampLight:
        return const Size(20, 20);
      case FurnitureType.wallLight:
        return const Size(40, 12); // wide, shallow — hugs wall
      case FurnitureType.ceilingSpot:
        return const Size(25, 25);
      case FurnitureType.windowLight:
        return const Size(80, 12); // wide window on wall
      // ── Custom furniture default footprint ────────────────────────────
      case FurnitureType.custom:
        // Use the size stored in the registry entry (set at import time)
        return widget.customDefaultSize ?? const Size(80, 80);
    }
  }

  Color _defaultColor(FurnitureType t) {
    switch (t) {
      case FurnitureType.chair:
        return const Color(0xFF8B6F47);
      case FurnitureType.sofa:
        return const Color(0xFF4A6FA5);
      case FurnitureType.armchair:
        return const Color(0xFF7B5E3A);
      case FurnitureType.bench:
        return const Color(0xFF6D4C41);
      case FurnitureType.stool:
        return const Color(0xFF9E7B50);
      case FurnitureType.table:
        return const Color(0xFF6B4423);
      case FurnitureType.coffeeTable:
        return const Color(0xFF5D4037);
      case FurnitureType.desk:
        return const Color(0xFF546E7A);
      case FurnitureType.sideTable:
        return const Color(0xFF795548);
      case FurnitureType.wardrobe:
        return const Color(0xFF4E342E);
      case FurnitureType.bookshelf:
        return const Color(0xFF6D4C41);
      case FurnitureType.cabinet:
        return const Color(0xFF455A64);
      case FurnitureType.dresser:
        return const Color(0xFF5D4037);
      case FurnitureType.bed:
        return const Color(0xFF7986CB);
      case FurnitureType.singleBed:
        return const Color(0xFF9575CD);
      case FurnitureType.nightstand:
        return const Color(0xFF6D4C41);
      case FurnitureType.plant:
        return const Color(0xFF388E3C);
      case FurnitureType.lamp:
        return const Color(0xFFF9A825);
      case FurnitureType.tvStand:
        return const Color(0xFF37474F);
      case FurnitureType.rug:
        return const Color(0xFFB71C1C);
      // ── Lights ────────────────────────────────────────────────────────
      case FurnitureType.floorLampLight:
        return const Color(0xFFFFD54F);
      case FurnitureType.tableLampLight:
        return const Color(0xFFFFCC02);
      case FurnitureType.wallLight:
        return const Color(0xFFFFB300);
      case FurnitureType.ceilingSpot:
        return const Color(0xFFFFFFFF);
      case FurnitureType.windowLight:
        return const Color(0xFFB3E5FC);
      // ── Custom furniture uses the colour stored in the registry entry ──
      case FurnitureType.custom:
        return widget.customColor ?? const Color(0xFF607D8B);
    }
  }

  /// Checks if [rect] overlaps any existing furniture item.
  bool _overlapsAny(Rect rect) {
    return furnitureItems.any((item) {
      final ir = Rect.fromLTWH(
        item.position.dx,
        item.position.dy,
        item.size.width,
        item.size.height,
      );
      return rect.overlaps(ir);
    });
  }

  /// Returns a position near [preferred] that doesn't overlap existing items.
  /// Tries a spiral of offsets; falls back to preferred if none found.
  Offset _findFreePosition(Offset preferred, Size size) {
    // First try the exact position — if it's free, use it
    final prefRect = Rect.fromLTWH(
      preferred.dx,
      preferred.dy,
      size.width,
      size.height,
    );
    if (!_overlapsAny(prefRect)) return preferred;

    // Spiral outwards in grid steps until a free slot is found
    const step = 20.0;
    final maxTries = 80;
    for (var i = 1; i <= maxTries; i++) {
      final offsets = [
        Offset(step * i, 0),
        Offset(-step * i, 0),
        Offset(0, step * i),
        Offset(0, -step * i),
        Offset(step * i, step * i),
        Offset(-step * i, step * i),
        Offset(step * i, -step * i),
        Offset(-step * i, -step * i),
      ];
      for (final off in offsets) {
        final candidate = _snapOffset(preferred + off);
        final r = Rect.fromLTWH(
          candidate.dx,
          candidate.dy,
          size.width,
          size.height,
        );
        if (!_overlapsAny(r)) return candidate;
      }
    }
    return preferred; // give up — let it overlap
  }

  FurnitureModel _newItem({required Offset position, Size? size}) {
    Size itemSize;
    // Track the scaleFactor to inherit from an existing sibling.
    // New items must inherit the sibling's ACTUAL size AND scaleFactor so they
    // appear identical to existing items of the same type — not at natural/default size.
    double inheritedScaleFactor = 1.0;

    if (size != null) {
      // Explicit size supplied (e.g. from draw-drag) — use it directly.
      itemSize = size;
    } else if (widget.selectedType == FurnitureType.custom &&
        widget.customGlbOverride != null) {
      // Custom GLB: find an existing sibling and inherit its exact size + scale.
      final existing = furnitureItems
          .where((f) => f.glbOverride == widget.customGlbOverride)
          .firstOrNull;
      if (existing != null) {
        itemSize = existing.size;
        inheritedScaleFactor = existing.scaleFactor > 0
            ? existing.scaleFactor
            : 1.0;
      } else {
        // No sibling on canvas — check persisted prefs keyed by glb filename
        final glbFile = widget.customGlbOverride!.split('/').last;
        final pref = widget.typeSizePrefs[glbFile];
        if (pref != null) {
          itemSize = Size(pref['w']!, pref['h']!);
          inheritedScaleFactor = pref['sf'] ?? 1.0;
        } else {
          itemSize = widget.customDefaultSize ?? const Size(80, 80);
        }
      }
    } else {
      // Priority order for size:
      //   1. Existing sibling on canvas (has the live size)
      //   2. typeSizePrefs — persisted from last session, survives item deletion
      //   3. _defaultSize fallback
      final sibling = furnitureItems
          .where((f) => f.type == widget.selectedType && !f.type.isLight)
          .firstOrNull;
      if (sibling != null) {
        // Inherit exact size + scaleFactor from existing sibling
        itemSize = sibling.size;
        inheritedScaleFactor = sibling.scaleFactor > 0
            ? sibling.scaleFactor
            : 1.0;
      } else {
        // No sibling on canvas — check persisted prefs
        final prefKey = widget.selectedType.name;
        final pref = widget.typeSizePrefs[prefKey];
        if (pref != null) {
          itemSize = Size(pref['w']!, pref['h']!);
          inheritedScaleFactor = pref['sf'] ?? 1.0;
        } else {
          itemSize = _defaultSize(widget.selectedType);
        }
      }
    }

    // ── Zone constraints ──────────────────────────────────────────────────
    Offset placedPos;
    final zone = widget.selectedType.isLight
        ? widget.selectedType.lightZone
        : LightZone.floor;

    if (zone == LightZone.wall) {
      placedPos = _snapToWall(position, itemSize);
    } else if (zone == LightZone.ceiling) {
      placedPos = _clampToRoom(position, itemSize);
    } else if (zone == LightZone.onFurniture) {
      placedPos = _snapToFurniture(position, itemSize);
    } else {
      placedPos = _findFreePosition(_snapOffset(position), itemSize);
    }

    return FurnitureModel(
      id: DateTime.now().toString(),
      type: widget.selectedType,
      position: placedPos,
      size: itemSize,
      color: _defaultColor(widget.selectedType),
      scaleFactor: inheritedScaleFactor,
      glbOverride: widget.selectedType == FurnitureType.custom
          ? widget.customGlbOverride
          : null,
      labelOverride: widget.selectedType == FurnitureType.custom
          ? widget.customLabelOverride
          : null,
    );
  }

  // ── Constrain drag position by light zone ───────────────────────────────
  Offset _constrainForZone(FurnitureModel item, Offset pos) {
    if (!item.type.isLight) return pos;
    final zone = item.type.lightZone;
    if (zone == LightZone.wall) {
      return _snapToWall(pos, item.size);
    } else if (zone == LightZone.ceiling) {
      return _clampToRoom(pos, item.size);
    } else if (zone == LightZone.onFurniture) {
      return _snapToFurniture(pos, item.size);
    }
    return pos;
  }

  // ── Snap to nearest wall ─────────────────────────────────────────────────
  Offset _snapToWall(Offset pos, Size size) {
    final roomW = widget.roomWidthPx;
    final roomH = widget.roomDepthPx;
    // Distances from pos.dx/dy to each wall edge
    final dLeft = pos.dx;
    final dRight = roomW - pos.dx;
    final dTop = pos.dy;
    final dBottom = roomH - pos.dy;
    final minD = Math.min(Math.min(dLeft, dRight), Math.min(dTop, dBottom));

    if (minD == dLeft) {
      // Left wall — item hugs left edge
      return Offset(0, pos.dy.clamp(0, roomH - size.height));
    } else if (minD == dRight) {
      // Right wall
      return Offset(roomW - size.width, pos.dy.clamp(0, roomH - size.height));
    } else if (minD == dTop) {
      // Top wall
      return Offset(pos.dx.clamp(0, roomW - size.width), 0);
    } else {
      // Bottom wall
      return Offset(pos.dx.clamp(0, roomW - size.width), roomH - size.height);
    }
  }

  // ── Clamp to room interior ───────────────────────────────────────────────
  Offset _clampToRoom(Offset pos, Size size) {
    final roomW = widget.roomWidthPx;
    final roomH = widget.roomDepthPx;
    return Offset(
      pos.dx.clamp(0, roomW - size.width),
      pos.dy.clamp(0, roomH - size.height),
    );
  }

  // ── Snap table lamp to nearest ANY furniture surface ────────────────────
  Offset _snapToFurniture(Offset pos, Size size) {
    final candidates = furnitureItems.where((f) => !f.type.isLight).toList();
    if (candidates.isEmpty) return _findFreePosition(_snapOffset(pos), size);

    // The lamp's centre position
    final lampCx = pos.dx + size.width / 2;
    final lampCy = pos.dy + size.height / 2;

    // 1. Check if lamp centre is already inside any furniture footprint
    for (final f in candidates) {
      final fRect = Rect.fromLTWH(
        f.position.dx,
        f.position.dy,
        f.size.width,
        f.size.height,
      );
      if (fRect.contains(Offset(lampCx, lampCy))) {
        // Allow free placement — just clamp so lamp stays fully inside furniture
        return Offset(
          pos.dx.clamp(
            f.position.dx,
            f.position.dx + f.size.width - size.width,
          ),
          pos.dy.clamp(
            f.position.dy,
            f.position.dy + f.size.height - size.height,
          ),
        );
      }
    }

    // 2. Not inside any furniture → snap to nearest furniture and clamp within it
    FurnitureModel? nearest;
    double bestDist = double.infinity;
    for (final f in candidates) {
      final fc = f.position + Offset(f.size.width / 2, f.size.height / 2);
      final d = (fc - Offset(lampCx, lampCy)).distance;
      if (d < bestDist) {
        bestDist = d;
        nearest = f;
      }
    }
    // Clamp within nearest furniture bounds
    return Offset(
      pos.dx.clamp(
        nearest!.position.dx,
        nearest.position.dx + nearest.size.width - size.width,
      ),
      pos.dy.clamp(
        nearest.position.dy,
        nearest.position.dy + nearest.size.height - size.height,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (event) {
        if (event is! RawKeyDownEvent) return;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        // Ctrl+Z → undo
        if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
          undo();
          return;
        }
        // Ctrl+Shift+Z → redo
        if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
          redo();
          return;
        }
        // Delete → remove selected
        if (event.logicalKey == LogicalKeyboardKey.delete &&
            selectedItems.isNotEmpty) {
          _pushUndo();
          setState(() {
            furnitureItems.removeWhere((i) => selectedItems.contains(i));
            selectedItems.clear();
            selectedItem = null;
          });
          _save();
        }
      },
      child: widget.showCeilingLayer
          ? _buildSplitView(context)
          : _buildFurnitureCanvas(context),
    );
  }

  // ── Furniture-only canvas (normal mode) ──────────────────────────────────
  Widget _buildFurnitureCanvas(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.none,
      onHover: (event) =>
          _updateCursor(_toScene(event.localPosition), event.localPosition),
      onExit: (_) {
        _cursorPos.value = null;
        _cursorAsset.value = null;
      },
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onTrackpadStart,
        onPointerPanZoomUpdate: _onTrackpadUpdate,
        onPointerPanZoomEnd: _onTrackpadEnd,
        child: Stack(
          children: [
            ColoredBox(
              color: widget.canvasBgColour,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _transformationController,
                  builder: (context, _) => Transform(
                    transform: _transformationController.value,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        final s = _globalToScene(d.globalPosition);
                        if (widget.currentMode == MouseMode.draw) {
                          // Ceiling spots can only be placed on the ceiling canvas (right panel)
                          if (widget.selectedType == FurnitureType.ceilingSpot)
                            return;
                          // Only allow placement inside the room
                          if (_insideRoom(s)) _drawTapPos = s;
                          return;
                        }
                        if (widget.currentMode != MouseMode.select) return;
                        if (_onAnyHandle(s)) return;
                        for (final item in furnitureItems.reversed) {
                          // Ceiling spots are locked in the furniture canvas
                          if (item.type == FurnitureType.ceilingSpot) continue;
                          if (_inside(item, s)) {
                            setState(() {
                              if (HardwareKeyboard.instance.isControlPressed) {
                                selectedItems.contains(item)
                                    ? selectedItems.remove(item)
                                    : selectedItems.add(item);
                                selectedItem = item;
                              } else if (selectedItems.contains(item)) {
                                selectedItem = item;
                              } else {
                                selectedItems
                                  ..clear()
                                  ..add(item);
                                selectedItem = item;
                              }
                            });
                            return;
                          }
                        }
                        setState(() {
                          selectedItems.clear();
                          selectedItem = null;
                        });
                      },
                      onTapUp: (d) {
                        if (widget.currentMode == MouseMode.draw &&
                            _drawTapPos != null) {
                          _pushUndo();
                          setState(
                            () => furnitureItems.add(
                              _newItem(position: _drawTapPos!),
                            ),
                          );
                          _drawTapPos = null;
                        }
                      },
                      onSecondaryTap: () {
                        // Quick right-click on furniture = context menu.
                        // The tool wheel (hold + drag) is handled by
                        // _ToolWheelScope above this widget.
                        if (selectedItem != null) {
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final pos = box.localToGlobal(
                            Offset(
                              selectedItem!.position.dx +
                                  selectedItem!.size.width / 2,
                              selectedItem!.position.dy +
                                  selectedItem!.size.height / 2,
                            ),
                          );
                          _showContextMenu(pos);
                        }
                      },
                      onSecondaryTapDown: (d) {
                        final s = _globalToScene(d.globalPosition);
                        for (final item in furnitureItems.reversed) {
                          if (_inside(item, s)) {
                            setState(() {
                              selectedItem = item;
                              if (!selectedItems.contains(item))
                                selectedItems
                                  ..clear()
                                  ..add(item);
                            });
                            return;
                          }
                        }
                      },
                      onPanStart: (d) {
                        if (_isTrackpadActive) return;
                        _drawTapPos = null;
                        if (widget.currentMode == MouseMode.hand) {
                          setState(() => _isPanningCanvas = true);
                          _cursorAsset.value = 'assets/cursors/grab_cursor.png';
                          _dragStart = d.globalPosition;
                          return;
                        }
                        final s = _globalToScene(d.globalPosition);
                        if (selectedItem != null &&
                            _onRotate(selectedItem!, s)) {
                          _pushUndo();
                          setState(() => _isRotating = true);
                          _isRotatingLive = true;
                          _cursorAsset.value =
                              'assets/cursors/rotate_cursor.png';
                          return;
                        }
                        // Draw mode — no marquee, no drag on empty canvas
                        if (widget.currentMode == MouseMode.draw) return;
                        // Resize gesture disabled — use 3D view scale panel instead
                        for (final item in furnitureItems.reversed) {
                          if (_inside(item, s)) {
                            setState(() {
                              if (!selectedItems.contains(item)) {
                                if (!HardwareKeyboard.instance.isControlPressed)
                                  selectedItems.clear();
                                selectedItems.add(item);
                              }
                              selectedItem = item;
                              _isDragging = true;
                            });
                            _isDraggingLive = true;
                            _cursorAsset.value =
                                'assets/cursors/move_cursor.png';
                            _dragStart = s;
                            _pushUndo();
                            // Snapshot positions so we can revert if drop overlaps
                            _preDragPositions = {
                              for (final it in selectedItems)
                                it.id: it.position,
                            };
                            return;
                          }
                        }
                        // Select mode only — start marquee box
                        if (widget.currentMode != MouseMode.select) return;
                        setState(() {
                          _isSelectingBox = true;
                          _selectionStart = s;
                          _selectionCurrent = s;
                          selectedItems.clear();
                          selectedItem = null;
                        });
                        _cursorAsset.value = 'assets/cursors/main_cursor.png';
                      },
                      onPanUpdate: (d) {
                        if (_isTrackpadActive) return;
                        final s = _globalToScene(d.globalPosition);
                        _cursorPos.value =
                            (context.findRenderObject() as RenderBox?)
                                ?.globalToLocal(d.globalPosition);
                        if (_isSelectingBox && _selectionStart != null) {
                          setState(() => _selectionCurrent = s);
                          final localPos =
                              (context.findRenderObject() as RenderBox?)
                                  ?.globalToLocal(d.globalPosition);
                          if (localPos != null) _updateCursor(s, localPos);
                          return;
                        }
                        if (_isRotating && selectedItem != null) {
                          final c = Offset(
                            selectedItem!.position.dx +
                                selectedItem!.size.width / 2,
                            selectedItem!.position.dy +
                                selectedItem!.size.height / 2,
                          );
                          setState(
                            () => selectedItem!.rotation =
                                Math.atan2(s.dy - c.dy, s.dx - c.dx) + 1.5708,
                          );
                          return;
                        }
                        if (_isResizing && selectedItem != null) {
                          // Resize disabled — no-op
                          return;
                        }
                        if (_isDragging &&
                            selectedItems.isNotEmpty &&
                            _dragStart != null) {
                          final delta = s - _dragStart!;
                          setState(() {
                            for (final item in selectedItems) {
                              final raw = item.position + delta;
                              item.position = _constrainForZone(item, raw);
                            }
                          });
                          _dragStart = s;
                          return;
                        }
                        if (_isPanningCanvas) {
                          _transformationController.value =
                              _transformationController.value.clone()
                                ..translate(d.delta.dx, d.delta.dy);
                        }
                      },
                      onPanEnd: (_) {
                        if (_isTrackpadActive) return;
                        // Restore hand-mode cursor after releasing grab
                        if (_isPanningCanvas) {
                          _cursorAsset.value =
                              'assets/cursors/canvas_cursor.png';
                        }
                        if (widget.currentMode == MouseMode.select &&
                            _isSelectingBox &&
                            _selectionStart != null &&
                            _selectionCurrent != null) {
                          final rect = Rect.fromPoints(
                            _selectionStart!,
                            _selectionCurrent!,
                          );
                          setState(() {
                            selectedItems = furnitureItems
                                .where(
                                  (item) => rect.overlaps(
                                    Rect.fromLTWH(
                                      item.position.dx,
                                      item.position.dy,
                                      item.size.width,
                                      item.size.height,
                                    ),
                                  ),
                                )
                                .toList();
                            selectedItem = selectedItems.isNotEmpty
                                ? selectedItems.last
                                : null;
                          });
                        }
                        if (selectedItems.isNotEmpty) {
                          setState(() {
                            for (final item in selectedItems) {
                              item.position = _constrainForZone(
                                item,
                                _snapOffset(item.position),
                              );
                              // Only snap the size when the user was actively
                              // resizing — dragging must NEVER alter the size.
                              if (_isResizing) {
                                item.size = Size(
                                  _snap(item.size.width).clamp(40.0, 800.0),
                                  _snap(item.size.height).clamp(40.0, 800.0),
                                );
                              }
                            }
                            // Overlap check: if any dragged item overlaps a
                            // non-dragged item, revert ALL dragged items to
                            // their pre-drag positions.
                            if (_isDragging && _preDragPositions.isNotEmpty) {
                              final draggedIds = selectedItems
                                  .map((i) => i.id)
                                  .toSet();
                              bool hasOverlap = false;
                              for (final item in selectedItems) {
                                // onFurniture lights (table lamps) intentionally
                                // sit ON furniture — always overlap their host.
                                // Exclude them from the overlap revert check.
                                if (item.type.isLight &&
                                    item.type.lightZone ==
                                        LightZone.onFurniture) {
                                  continue;
                                }
                                final r = Rect.fromLTWH(
                                  item.position.dx,
                                  item.position.dy,
                                  item.size.width,
                                  item.size.height,
                                );
                                for (final other in furnitureItems) {
                                  if (draggedIds.contains(other.id)) continue;
                                  // Also skip furniture that this light sits on
                                  if (other.type.isLight) continue;
                                  final or2 = Rect.fromLTWH(
                                    other.position.dx,
                                    other.position.dy,
                                    other.size.width,
                                    other.size.height,
                                  );
                                  if (r.overlaps(or2)) {
                                    hasOverlap = true;
                                    break;
                                  }
                                }
                                if (hasOverlap) break;
                              }
                              if (hasOverlap) {
                                for (final item in selectedItems) {
                                  final orig = _preDragPositions[item.id];
                                  if (orig != null) item.position = orig;
                                }
                                // Drag was cancelled — discard the undo snapshot
                                if (_undoStack.isNotEmpty) {
                                  _undoStack.removeLast();
                                  widget.onUndoStateChanged?.call();
                                }
                              }
                            }
                            _preDragPositions = {};
                          });
                          _save();
                        }

                        setState(() {
                          _isRotating = _isDragging = _isResizing =
                              _isPanningCanvas = _isSelectingBox = false;
                          _selectionStart = _selectionCurrent = null;
                        });
                        _isRotatingLive = _isResizingLive = _isDraggingLive =
                            false;
                        _dragStart = null;
                        // Restore the correct idle cursor for the active mode
                        if (widget.currentMode == MouseMode.hand) {
                          _cursorAsset.value =
                              'assets/cursors/canvas_cursor.png';
                        } else if (widget.currentMode == MouseMode.draw) {
                          _cursorAsset.value = 'assets/cursors/add_cursor.png';
                        } else {
                          _cursorAsset.value = 'assets/cursors/main_cursor.png';
                        }
                      },
                      child: SizedBox(
                        width: _canvasW,
                        height: _canvasH,
                        child: RepaintBoundary(
                          child: Stack(
                            children: [
                              CustomPaint(
                                painter: RoomPainter(
                                  // Ceiling spots are NEVER shown on the
                                  // furniture canvas — only in CeilingPainter.
                                  furnitureItems: furnitureItems
                                      .where(
                                        (i) =>
                                            i.type != FurnitureType.ceilingSpot,
                                      )
                                      .toList(),
                                  selectedItems: selectedItems,
                                  roomWidth: widget.roomWidthPx,
                                  roomDepth: widget.roomDepthPx,
                                  canvasW: _canvasW,
                                  canvasH: _canvasH,
                                  canvasBgColour: widget.canvasBgColour,
                                  roomFloorColour: widget.roomFloorColour,
                                  roomWallColour: widget.roomWallColour,
                                  thumbnails: widget.thumbnails,
                                  showCeilingLayer: widget.showCeilingLayer,
                                  roomShape: widget.roomShape,
                                  customShapePoints: widget.customShapePoints,
                                ),
                                size: const Size(_canvasW, _canvasH),
                              ),
                              if (_isSelectingBox &&
                                  _selectionStart != null &&
                                  _selectionCurrent != null)
                                CustomPaint(
                                  painter: MarqueePainter(
                                    _selectionStart!,
                                    _selectionCurrent!,
                                  ),
                                  size: const Size(_canvasW, _canvasH),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Cursor overlay
            ValueListenableBuilder<Offset?>(
              valueListenable: _cursorPos,
              builder: (_, pos, __) {
                if (pos == null) return const SizedBox.shrink();
                return ValueListenableBuilder<String?>(
                  valueListenable: _cursorAsset,
                  builder: (_, asset, __) {
                    if (asset == null) return const SizedBox.shrink();
                    return Positioned(
                      left: pos.dx - _cursorHotspot(asset).dx,
                      top: pos.dy - _cursorHotspot(asset).dy,
                      width: _cursorSize,
                      height: _cursorSize,
                      child: IgnorePointer(
                        child: Image.asset(
                          asset,
                          width: _cursorSize,
                          height: _cursorSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Split view: furniture canvas + ceiling canvas side-by-side ─────────
  Widget _buildSplitView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfW = constraints.maxWidth / 2;
        final fullH = constraints.maxHeight;
        return Row(
          children: [
            // ── Left: furniture canvas (no ceiling spots) ──────────────────
            SizedBox(
              width: halfW,
              height: fullH,
              child: Stack(
                children: [
                  _buildFurnitureCanvas(context),
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '🪑 Furniture Canvas',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFBBB8C8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Vertical divider ────────────────────────────────────────────
            Container(width: 2, color: const Color(0xFF3A3A5A)),
            // ── Right: ceiling canvas (cursor overlay is inside it) ─────────
            SizedBox(
              width: halfW - 2,
              height: fullH,
              child: _buildCeilingCanvas(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCeilingCanvas(BuildContext context) {
    // Structure mirrors _buildFurnitureCanvas exactly:
    //   MouseRegion  ← outermost so onHover always fires for normal movement
    //     Listener   ← onPointerMove still fires during captured drag gestures
    //       Stack [ canvas, label, cursor(last=on top) ]
    return MouseRegion(
      cursor: SystemMouseCursors.none,
      onHover: (event) {
        _cursorPosC.value = event.localPosition;
        _updateCeilingCursor(
          _toScene(event.localPosition),
          event.localPosition,
        );
      },
      onExit: (_) {
        _cursorPosC.value = null;
        _cursorAssetC.value = null;
      },
      child: Listener(
        // onPointerMove fires even during GestureDetector-captured pans
        // (raw pointer routing bypasses the gesture arena)
        onPointerMove: (event) {
          _cursorPosC.value = event.localPosition;
          _updateCeilingCursor(
            _toScene(event.localPosition),
            event.localPosition,
          );
        },
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _zoomAround(
              event.scrollDelta.dy < 0 ? 1.10 : 0.90,
              event.localPosition,
            );
          }
        },
        child: Stack(
          children: [
            // ── Canvas ─────────────────────────────────────────────────
            ColoredBox(
              color: widget.canvasBgColour,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _transformationController,
                  builder: (context, _) => Transform(
                    transform: _transformationController.value,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        final s =
                            d.localPosition; // scene coords inside Transform
                        if (widget.currentMode == MouseMode.draw &&
                            widget.selectedType == FurnitureType.ceilingSpot &&
                            _insideRoom(s)) {
                          _drawTapPos = s;
                        } else if (widget.currentMode == MouseMode.select) {
                          for (final item in furnitureItems.reversed) {
                            if (item.type != FurnitureType.ceilingSpot)
                              continue;
                            if (_inside(item, s)) {
                              setState(() {
                                selectedItems = [item];
                                selectedItem = item;
                              });
                              return;
                            }
                          }
                          setState(() {
                            selectedItems.clear();
                            selectedItem = null;
                          });
                        }
                      },
                      onTapUp: (d) {
                        if (_drawTapPos != null) {
                          _pushUndo();
                          setState(() {
                            furnitureItems.add(
                              _newItem(position: _drawTapPos!),
                            );
                            _drawTapPos = null;
                          });
                          _save();
                        }
                      },
                      onPanStart: (d) {
                        final s = d.localPosition;
                        for (final item in furnitureItems.reversed) {
                          if (item.type != FurnitureType.ceilingSpot) continue;
                          if (_inside(item, s)) {
                            _pushUndo();
                            setState(() {
                              selectedItems = [item];
                              selectedItem = item;
                              _isCeilingDragging = true;
                              _dragStart = s;
                            });
                            _cursorAssetC.value =
                                'assets/cursors/move_cursor.png';
                            return;
                          }
                        }
                        if (widget.currentMode == MouseMode.hand) {
                          setState(() => _isPanningCanvas = true);
                          _cursorAssetC.value =
                              'assets/cursors/canvas_cursor.png';
                          _dragStart = d.localPosition;
                        }
                      },
                      onPanUpdate: (d) {
                        if (_isCeilingDragging &&
                            selectedItems.isNotEmpty &&
                            _dragStart != null) {
                          final s = d.localPosition;
                          final delta = s - _dragStart!;
                          setState(() {
                            for (final item in selectedItems) {
                              if (item.type != FurnitureType.ceilingSpot)
                                continue;
                              item.position = _clampToRoom(
                                item.position + delta,
                                item.size,
                              );
                            }
                          });
                          _dragStart = s;
                        } else if (_isPanningCanvas &&
                            widget.currentMode == MouseMode.hand) {
                          _transformationController.value =
                              _transformationController.value.clone()
                                ..translate(d.delta.dx, d.delta.dy);
                        }
                      },
                      onPanEnd: (_) => _endCeilingDrag(),
                      onPanCancel: () => _endCeilingDrag(),
                      child: SizedBox(
                        width: _canvasW,
                        height: _canvasH,
                        child: CustomPaint(
                          painter: CeilingPainter(
                            furnitureItems: furnitureItems,
                            selectedItems: selectedItems,
                            roomWidth: widget.roomWidthPx,
                            roomDepth: widget.roomDepthPx,
                            canvasW: _canvasW,
                            canvasH: _canvasH,
                            ceilingColour: widget.ceilingColour,
                            wallColour: widget.roomWallColour,
                            thumbnails: widget.thumbnails,
                          ),
                          size: const Size(_canvasW, _canvasH),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Label ──────────────────────────────────────────────────
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '⬆ Ceiling Canvas',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            // ── Cursor PNG — last child = always rendered on top ───────
            ValueListenableBuilder<Offset?>(
              valueListenable: _cursorPosC,
              builder: (_, pos, __) {
                if (pos == null) return const SizedBox.shrink();
                return ValueListenableBuilder<String?>(
                  valueListenable: _cursorAssetC,
                  builder: (_, asset, __) {
                    if (asset == null) return const SizedBox.shrink();
                    return Positioned(
                      left: pos.dx - _cursorHotspot(asset).dx,
                      top: pos.dy - _cursorHotspot(asset).dy,
                      width: _cursorSize,
                      height: _cursorSize,
                      child: IgnorePointer(
                        child: Image.asset(
                          asset,
                          width: _cursorSize,
                          height: _cursorSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Input handlers ────────────────────────────────────────────────────────
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _zoomAround(event.scrollDelta.dy < 0 ? 1.10 : 0.90, event.localPosition);
    }
  }

  void _onTrackpadStart(PointerPanZoomStartEvent event) {
    _trackpadLastScale = 1.0;
    _isTrackpadActive = true;
    _trackpadFocal = _cursorPos.value ?? event.localPosition;
    _cursorPos.value = null;
    _cursorAsset.value = null;
  }

  void _onTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    final isPinch = (event.scale - 1.0).abs() > 0.03;
    if (!isPinch && event.panDelta != Offset.zero) {
      final scale = _transformationController.value.getMaxScaleOnAxis();
      _transformationController.value = _transformationController.value.clone()
        ..translate(event.panDelta.dx / scale, event.panDelta.dy / scale);
    }
    if (isPinch && event.scale > 0 && event.scale != _trackpadLastScale) {
      _zoomAroundNoCursor(event.scale / _trackpadLastScale, _trackpadFocal);
      _trackpadLastScale = event.scale;
    }
    setState(() {});
  }

  void _onTrackpadEnd(PointerPanZoomEndEvent event) {
    _isTrackpadActive = false;
    _trackpadLastScale = 1.0;
    _trackpadFocal = Offset.zero;
    if (widget.currentMode == MouseMode.hand) {
      _cursorAsset.value = 'assets/cursors/canvas_cursor.png';
    } else if (widget.currentMode == MouseMode.draw) {
      _cursorAsset.value = 'assets/cursors/add_cursor.png';
    } else {
      _cursorAsset.value = 'assets/cursors/main_cursor.png';
    }
  }

  void _zoomAround(double factor, Offset screenFocal) =>
      _zoomAroundNoCursor(factor, screenFocal);

  void _zoomAroundNoCursor(double factor, Offset screenFocal) {
    final current = _transformationController.value;
    final scale = current.getMaxScaleOnAxis();
    final clamped = (scale * factor).clamp(0.05, 5.0);
    if ((clamped - scale).abs() < 0.0001) return;
    final f = clamped / scale;
    final tx = current.storage[12];
    final ty = current.storage[13];
    _transformationController.value = Matrix4.identity()
      ..scale(clamped, clamped, clamped)
      ..setTranslationRaw(
        (1.0 - f) * screenFocal.dx + f * tx,
        (1.0 - f) * screenFocal.dy + f * ty,
        0.0,
      );
    widget.onZoomChanged?.call(clamped);
    setState(() {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomPainter
// ─────────────────────────────────────────────────────────────────────────────
class RoomPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;
  final double roomWidth, roomDepth, canvasW, canvasH;
  final Color canvasBgColour;
  final Color roomFloorColour;
  final Color roomWallColour;
  final Map<String, ui.Image> thumbnails;
  final bool showCeilingLayer;
  final RoomShape roomShape;
  final List<Offset>? customShapePoints;

  const RoomPainter({
    required this.furnitureItems,
    required this.selectedItems,
    required this.roomWidth,
    required this.roomDepth,
    required this.canvasW,
    required this.canvasH,
    this.canvasBgColour = const Color(0xFF0D0D11),
    this.roomFloorColour = const Color(0xFFFAF8F5),
    this.roomWallColour = const Color(0xFF4A4A5A),
    this.thumbnails = const {},
    this.showCeilingLayer = false,
    this.roomShape = RoomShape.rectangle,
    this.customShapePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background (area outside the room) — uses the configurable canvas bg colour
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = canvasBgColour,
    );

    // Build the room shape path
    final roomPath = buildRoomPath(
      roomShape,
      roomWidth,
      roomDepth,
      customPoints: customShapePoints,
    );
    final rr = Rect.fromLTWH(0, 0, roomWidth, roomDepth);

    // Room floor — use the scheme colour, clipped to shape
    canvas.save();
    canvas.clipPath(roomPath);
    canvas.drawPath(roomPath, Paint()..color = roomFloorColour);

    // Ring inner hole — draw background colour inside to fake a hole
    if (roomShape == RoomShape.ring) {
      canvas.drawPath(
        buildRingHolePath(roomWidth, roomDepth),
        Paint()..color = canvasBgColour,
      );
    }

    // Ceiling layer overlay — subtle blue tint
    if (showCeilingLayer) {
      canvas.drawPath(
        roomPath,
        Paint()..color = const Color(0xFF1565C0).withOpacity(0.09),
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: '⬆ CEILING LAYER',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF42A5F5),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, const Offset(8, 6));
    }

    // Grid — clipped to room shape
    final gp = Paint()
      ..color = roomFloorColour.computeLuminance() > 0.5
          ? Colors.black.withOpacity(0.10)
          : Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    for (double x = 0; x <= roomWidth; x += 20)
      canvas.drawLine(Offset(x, 0), Offset(x, roomDepth), gp);
    for (double y = 0; y <= roomDepth; y += 20)
      canvas.drawLine(Offset(0, y), Offset(roomWidth, y), gp);
    canvas.restore();

    // Shadow under shape
    canvas.drawPath(
      roomPath.shift(const Offset(2, 2)),
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Wall stroke — draw the shape outline
    canvas.drawPath(
      roomPath,
      Paint()
        ..color = roomWallColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round,
    );

    // Dimension labels — always based on bounding box
    _dimLabel(
      canvas,
      '${(roomWidth / 100).toStringAsFixed(1)} m',
      Offset(roomWidth / 2, roomDepth + 20),
      false,
    );
    _dimLabel(
      canvas,
      '${(roomDepth / 100).toStringAsFixed(1)} m',
      Offset(roomWidth + 20, roomDepth / 2),
      true,
    );

    // Furniture
    for (final item in furnitureItems) {
      canvas.save();
      canvas.translate(
        item.position.dx + item.size.width / 2,
        item.position.dy + item.size.height / 2,
      );
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      // Use top-down 3D thumbnail when available, else vector fallback
      final thumbKey = item.type == FurnitureType.custom
          ? (item.glbOverride ?? '')
          : item.type.name;
      final thumb = thumbnails[thumbKey];
      // Draw thumbnail; if it fails (disposed after hot-reload) fall back to vector
      if (thumb == null || !_drawThumbnailTile(canvas, item, thumb)) {
        _drawFurniture(canvas, item);
      }

      // Tint overlay
      if (item.tintHex != null && item.tintHex!.isNotEmpty) {
        final tint = _hexToColor(item.tintHex!);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, item.size.width, item.size.height),
            const Radius.circular(4),
          ),
          Paint()
            ..color = tint.withOpacity(0.45)
            ..blendMode = BlendMode.multiply,
        );
      }
      if (selectedItems.contains(item)) _drawHandles(canvas, item);
      canvas.restore();
    }
  }

  /// Draws a real top-down 3D thumbnail image fitted inside the item tile.
  /// Draws a top-down 3D thumbnail image into the furniture tile.
  ///
  /// Handles two tricky cases:
  ///   1. Orientation mismatch — if the image is portrait but the tile is
  ///      landscape (or vice versa), rotate the image 90° so the long axis
  ///      always aligns.  This fixes e.g. bench.glb which renders tall but
  ///      the tile expects a wide footprint.
  ///   2. Disposed GPU texture after hot-reload — catches the error and falls
  ///      back to the vector art so the canvas never goes blank.
  ///
  /// Returns true if drawn, false if the image was disposed (caller should
  /// fall back to _drawFurniture).
  bool _drawThumbnailTile(Canvas canvas, FurnitureModel item, ui.Image img) {
    try {
      final w = item.size.width;
      final h = item.size.height;
      final rect = Rect.fromLTWH(0, 0, w, h);

      // Drop shadow
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.translate(0, 3), const Radius.circular(4)),
        Paint()..color = Colors.black.withOpacity(0.25),
      );

      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));

      // Stretch image to fill the entire tile — no grey bars, no cropping.
      // The thumbnail is a top-down render so slight stretch is imperceptible.
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );

      canvas.restore();

      // Thin grey border
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFF6B7C88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return true;
    } catch (_) {
      // ui.Image was disposed (hot-reload) — caller falls back to vector art
      return false;
    }
  }

  void _drawFurniture(Canvas canvas, FurnitureModel item) {
    switch (item.type) {
      case FurnitureType.chair:
        _chair(canvas, item);
        break;
      case FurnitureType.sofa:
        _sofa(canvas, item);
        break;
      case FurnitureType.armchair:
        _armchair(canvas, item);
        break;
      case FurnitureType.bench:
        _bench(canvas, item);
        break;
      case FurnitureType.stool:
        _stool(canvas, item);
        break;
      case FurnitureType.table:
        _table(canvas, item);
        break;
      case FurnitureType.coffeeTable:
        _coffeeTable(canvas, item);
        break;
      case FurnitureType.desk:
        _desk(canvas, item);
        break;
      case FurnitureType.sideTable:
        _sideTable(canvas, item);
        break;
      case FurnitureType.wardrobe:
        _wardrobe(canvas, item);
        break;
      case FurnitureType.bookshelf:
        _bookshelf(canvas, item);
        break;
      case FurnitureType.cabinet:
        _cabinet(canvas, item);
        break;
      case FurnitureType.dresser:
        _dresser(canvas, item);
        break;
      case FurnitureType.bed:
        _bed(canvas, item);
        break;
      case FurnitureType.singleBed:
        _singleBed(canvas, item);
        break;
      case FurnitureType.nightstand:
        _nightstand(canvas, item);
        break;
      case FurnitureType.plant:
        _plant(canvas, item);
        break;
      case FurnitureType.lamp:
        _lamp(canvas, item);
        break;
      case FurnitureType.tvStand:
        _tvStand(canvas, item);
        break;
      case FurnitureType.rug:
        _rug(canvas, item);
        break;
      // ── Lights ────────────────────────────────────────────────────────
      case FurnitureType.floorLampLight:
        _drawFloorLamp2D(canvas, item);
        break;
      case FurnitureType.tableLampLight:
        _drawTableLamp2D(canvas, item);
        break;
      case FurnitureType.wallLight:
        _drawWallLight2D(canvas, item);
        break;
      case FurnitureType.ceilingSpot:
        _drawCeilingSpot2D(canvas, item);
        break;
      case FurnitureType.windowLight:
        _drawWindow2D(canvas, item);
        break;
      // ── Custom furniture: styled labelled tile ─────────────────────────
      case FurnitureType.custom:
        _custom(canvas, item);
        break;
    }
  }

  // ── 2D light drawing methods ─────────────────────────────────────────────

  void _drawFloorLamp2D(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = Math.min(w, h) * 0.45;
    // Outer glow ring
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.4,
      Paint()
        ..color = const Color(0xFFFFD54F).withOpacity(0.25)
        ..style = PaintingStyle.fill,
    );
    // Base circle
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFFFD54F),
    );
    // Warm dot centre
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.45,
      Paint()..color = const Color(0xFFFFF9C4),
    );
    // Label
    _drawLightLabel(canvas, item, '💡');
  }

  void _drawTableLamp2D(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = Math.min(w, h) * 0.45;
    // Glow
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.3,
      Paint()
        ..color = const Color(0xFFFFCC02).withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFFFCC02),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.4,
      Paint()..color = const Color(0xFFFFF8E1),
    );
    _drawLightLabel(canvas, item, '🔆');
  }

  void _drawWallLight2D(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(3),
    );
    // Wall light body — warm amber bar
    canvas.drawRRect(rect, Paint()..color = const Color(0xFFFFB300));
    // Glow emitting downward/inward
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.1, 0, w * 0.8, h * 0.6),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFFF3E0).withOpacity(0.7),
    );
    // Border
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFFE65100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    // Small label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'WALL',
        style: TextStyle(
          fontSize: 6,
          color: Color(0xFF3E2723),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  }

  void _drawCeilingSpot2D(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = Math.min(w, h) * 0.45;
    // Wide diffuse glow
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.6,
      Paint()
        ..color = const Color(0xFFFFFFFF).withOpacity(0.15)
        ..style = PaintingStyle.fill,
    );
    // Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFFBDBDBD)
        ..style = PaintingStyle.fill,
    );
    // Inner bright spot
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.5,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    // Ring border
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF757575)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _drawLightLabel(canvas, item, '◎');
  }

  void _drawWindow2D(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    // Glass fill — light blue
    canvas.drawRect(rect, Paint()..color = const Color(0xFFB3E5FC));
    // Window pane divider
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = const Color(0xFF0288D1)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(0, h / 2),
      Offset(w, h / 2),
      Paint()
        ..color = const Color(0xFF0288D1)
        ..strokeWidth = 1.0,
    );
    // Frame border
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF0277BD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawLightLabel(Canvas canvas, FurnitureModel item, String emoji) {
    // Nothing needed — the emoji circles speak for themselves at small size
  }

  void _drawHandles(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    // Selection rectangle
    canvas.drawRect(
      Rect.fromLTWH(-2, -2, w + 4, h + 4),
      Paint()
        ..color = Colors.blue.withOpacity(.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Rotation handle (blue dot above centre) — kept
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, -25),
      Paint()
        ..color = Colors.blue.withOpacity(.5)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(w / 2, -25), 10, Paint()..color = Colors.blue);
    canvas.drawCircle(
      Offset(w / 2, -25),
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Resize handle (red dot at bottom-right) REMOVED
    // Use the 3D view scale panel to resize furniture
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _shadow(Canvas canvas, double w, double h, {double r = 4}) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, w, h), Radius.circular(r)),
        Paint()..color = Colors.black.withOpacity(.15),
      );

  /// Parses a '#RRGGBB' hex string into a [Color].
  Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return Colors.transparent;
    return Color(int.parse('FF$h', radix: 16));
  }

  Color _dk(Color c, double a) => Color.fromARGB(
    c.alpha,
    (c.red * (1 - a)).round().clamp(0, 255),
    (c.green * (1 - a)).round().clamp(0, 255),
    (c.blue * (1 - a)).round().clamp(0, 255),
  );

  Color _lt(Color c, double a) => Color.fromARGB(
    c.alpha,
    (c.red + (255 - c.red) * a).round().clamp(0, 255),
    (c.green + (255 - c.green) * a).round().clamp(0, 255),
    (c.blue + (255 - c.blue) * a).round().clamp(0, 255),
  );

  void _outline(
    Canvas canvas,
    Rect r,
    Color c, {
    double radius = 3,
    double sw = 1.2,
  }) => canvas.drawRRect(
    RRect.fromRectAndRadius(r, Radius.circular(radius)),
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw,
  );

  void _lbl(Canvas canvas, String text, double w, double h, {Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: (color ?? Colors.white).withOpacity(.82),
          fontSize: (w * .11).clamp(7.0, 12.0),
          fontWeight: FontWeight.bold,
          letterSpacing: .4,
          shadows: const [Shadow(color: Colors.black38, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));
  }

  void _dimLabel(Canvas canvas, String t, Offset pos, bool rot) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: const TextStyle(
          color: Color(0xFF8E8A9A),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (rot) canvas.rotate(-Math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  // Wood-grain fill: base colour + thin horizontal lines
  void _woodGrain(Canvas canvas, double w, double h, Color base) {
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = base);
    final p = Paint()
      ..color = _dk(base, .08)
      ..strokeWidth = 0.8;
    final spacing = (h / 6).clamp(4.0, 12.0);
    for (double y = spacing; y < h; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(w, y), p);
    }
  }

  // Soft drop shadow
  void _dropShadow(Canvas canvas, double w, double h, {double r = 5}) {
    final sp = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..color = Colors.black.withOpacity(0.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(3, 4, w, h), Radius.circular(r)),
      sp,
    );
  }

  // Thin outline
  void _ol(Canvas canvas, Rect r, Color c, {double rad = 3, double sw = 1.0}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(rad)),
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
  }

  // ── Custom furniture tile ─────────────────────────────────────────────────
  void _custom(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _dropShadow(canvas, w, h, r: 6);
    // Body with wood-like texture
    _woodGrain(canvas, w, h, c);
    // Border frame
    canvas.drawRect(
      Rect.fromLTWH(w * .06, h * .06, w * .88, h * .88),
      Paint()
        ..color = _lt(c, .22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .40), rad: 4);
    final label = (item.labelOverride ?? 'CUSTOM').toUpperCase();
    _lbl(canvas, label, w, h);
  }

  // ── Seating ───────────────────────────────────────────────────────────────
  void _chair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    final wood = const Color(0xFFB8895A);
    _dropShadow(canvas, w, h, r: 4);
    // Seat cushion (bottom 75%)
    final seatTop = h * .22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, seatTop, w * .92, h - seatTop - h * .02),
        const Radius.circular(4),
      ),
      Paint()..color = c,
    );
    // Seat cushion highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .1, seatTop + h * .06, w * .8, h * .22),
        const Radius.circular(3),
      ),
      Paint()..color = _lt(c, .18),
    );
    // Backrest (top 22%) — darker wood
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, seatTop),
        const Radius.circular(4),
      ),
      Paint()..color = wood,
    );
    // Backrest slats
    final slatP = Paint()
      ..color = _dk(wood, .2)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = w * i / 4;
      canvas.drawLine(Offset(x, 2), Offset(x, seatTop - 2), slatP);
    }
    // 4 legs (small circles at corners)
    final legP = Paint()..color = wood;
    final lr = (w * .065).clamp(3.0, 6.0);
    for (final p in [
      Offset(w * .13, h * .88),
      Offset(w * .87, h * .88),
      Offset(w * .13, h * .97),
      Offset(w * .87, h * .97),
    ])
      canvas.drawCircle(p, lr, legP);
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), rad: 4);
  }

  void _sofa(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    final dark = _dk(c, .3);
    _dropShadow(canvas, w, h, r: 6);
    // Overall body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = dark,
    );
    final bH = h * .26; // backrest height
    final aW = w * .09; // armrest width
    // Backrest
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, bH),
        const Radius.circular(6),
      ),
      Paint()..color = _dk(c, .38),
    );
    // Left armrest
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, bH, aW, h - bH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(c, .25),
    );
    // Right armrest
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - aW, bH, aW, h - bH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(c, .25),
    );
    // Seat area
    final seatRect = Rect.fromLTWH(aW, bH, w - aW * 2, h - bH);
    canvas.drawRect(seatRect, Paint()..color = c);
    // Cushion dividers
    final nCushions = w > 200 ? 3 : 2;
    final cW = seatRect.width / nCushions;
    final divP = Paint()
      ..color = _dk(c, .22)
      ..strokeWidth = 1.5;
    for (int i = 1; i < nCushions; i++) {
      final x = aW + cW * i;
      canvas.drawLine(Offset(x, bH + 4), Offset(x, h - 4), divP);
    }
    // Cushion highlight on each section
    for (int i = 0; i < nCushions; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(aW + cW * i + 4, bH + 4, cW - 8, (h - bH) * .35),
          const Radius.circular(3),
        ),
        Paint()..color = _lt(c, .15),
      );
    }
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .5), rad: 6, sw: 1.2);
  }

  void _armchair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _dropShadow(canvas, w, h, r: 5);
    final bH = h * .28;
    final aW = w * .12;
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .28),
    );
    // Backrest
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, bH),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .38),
    );
    // Armrests
    for (final x in [0.0, w - aW]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bH, aW, h - bH),
          const Radius.circular(3),
        ),
        Paint()..color = _dk(c, .25),
      );
    }
    // Seat
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(aW, bH, w - aW * 2, h - bH),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    // Single cushion highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(aW + 4, bH + 4, w - aW * 2 - 8, (h - bH) * .38),
        const Radius.circular(3),
      ),
      Paint()..color = _lt(c, .18),
    );
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), rad: 5);
  }

  void _bench(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFFA0784A);
    _dropShadow(canvas, w, h, r: 3);
    // Top planks
    _woodGrain(canvas, w, h, wood);
    // Plank lines
    final nPlanks = (w / 40).round().clamp(2, 8);
    final pw = w / nPlanks;
    final lp = Paint()
      ..color = _dk(wood, .25)
      ..strokeWidth = 1.2;
    for (int i = 1; i < nPlanks; i++) {
      canvas.drawLine(Offset(pw * i, 0), Offset(pw * i, h), lp);
    }
    // Legs
    final legW = (w * .08).clamp(5.0, 12.0);
    final legH = h * .2;
    final legP = Paint()..color = _dk(wood, .35);
    for (final x in [w * .08, w - w * .08 - legW]) {
      canvas.drawRect(Rect.fromLTWH(x, h - legH, legW, legH), legP);
    }
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(wood, .4), rad: 2);
  }

  void _stool(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    final r = Math.min(w, h) / 2;
    _dropShadow(canvas, w, h, r: r);
    // Round seat
    canvas.drawCircle(Offset(w / 2, h / 2), r - 2, Paint()..color = c);
    // Highlight
    canvas.drawCircle(
      Offset(w / 2 - r * .2, h / 2 - r * .2),
      r * .35,
      Paint()..color = _lt(c, .22),
    );
    // Seat edge
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      r - 2,
      Paint()
        ..color = _dk(c, .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Cross brace at centre
    final bp = Paint()
      ..color = _dk(c, .3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(w / 2, h / 2 - r * .4),
      Offset(w / 2, h / 2 + r * .4),
      bp,
    );
    canvas.drawLine(
      Offset(w / 2 - r * .4, h / 2),
      Offset(w / 2 + r * .4, h / 2),
      bp,
    );
  }

  // ── Tables ────────────────────────────────────────────────────────────────
  void _table(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFFD4A96A);
    _dropShadow(canvas, w, h, r: 4);
    _woodGrain(canvas, w, h, wood);
    // Outer border frame
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Inner line (table edge)
    canvas.drawRect(
      Rect.fromLTWH(5, 5, w - 10, h - 10),
      Paint()
        ..color = _dk(wood, .15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Legs — filled rectangles at corners
    final lS = (Math.min(w, h) * .08).clamp(5.0, 12.0);
    final legP = Paint()..color = _dk(wood, .45);
    for (final o in [
      Offset(0, 0),
      Offset(w - lS, 0),
      Offset(0, h - lS),
      Offset(w - lS, h - lS),
    ])
      canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, lS, lS), legP);
  }

  void _coffeeTable(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFFB8895A);
    _dropShadow(canvas, w, h, r: 4);
    _woodGrain(canvas, w, h, wood);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Inset surface line
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 6, w - 12, h - 12),
        const Radius.circular(2),
      ),
      Paint()
        ..color = _dk(wood, .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Small legs at corners
    final lS = (Math.min(w, h) * .09).clamp(4.0, 10.0);
    final legP = Paint()..color = _dk(wood, .5);
    for (final o in [
      Offset(2, 2),
      Offset(w - lS - 2, 2),
      Offset(2, h - lS - 2),
      Offset(w - lS - 2, h - lS - 2),
    ])
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx, o.dy, lS, lS),
          const Radius.circular(1),
        ),
        legP,
      );
  }

  void _desk(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFFC8A878);
    _dropShadow(canvas, w, h, r: 3);
    _woodGrain(canvas, w, h, wood);
    // L-shape or straight — draw surface edge
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Monitor depression at top-centre
    final mW = w * .28, mH = h * .32;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - mW / 2, h * .06, mW, mH),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF2A2A3A),
    );
    // Monitor screen
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - mW / 2 + 2, h * .06 + 2, mW - 4, mH - 4),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF3A6080).withOpacity(.7),
    );
    // Drawer handle line
    final dY = h * .72;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .05, dY, w * .9, h * .2),
        const Radius.circular(2),
      ),
      Paint()
        ..color = _dk(wood, .18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Drawer pull
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .44, dY + h * .07, w * .12, h * .06),
        const Radius.circular(2),
      ),
      Paint()..color = _dk(wood, .4),
    );
  }

  void _sideTable(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFFB8895A);
    _dropShadow(canvas, w, h, r: 4);
    // Round or square depending on aspect
    final isRound = (w - h).abs() < h * .25;
    if (isRound) {
      final r = Math.min(w, h) / 2 - 2;
      canvas.drawCircle(Offset(w / 2, h / 2), r, Paint()..color = wood);
      canvas.drawCircle(
        Offset(w / 2, h / 2),
        r * .75,
        Paint()
          ..color = _lt(wood, .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(w / 2, h / 2),
        r,
        Paint()
          ..color = _dk(wood, .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else {
      _woodGrain(canvas, w, h, wood);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..color = _dk(wood, .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  // ── Storage ───────────────────────────────────────────────────────────────
  void _wardrobe(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF8D6E63);
    _dropShadow(canvas, w, h, r: 4);
    _woodGrain(canvas, w, h, wood);
    // Outer case
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Two door panels
    final mid = w / 2;
    canvas.drawLine(
      Offset(mid, 3),
      Offset(mid, h - 3),
      Paint()
        ..color = _dk(wood, .3)
        ..strokeWidth = 2,
    );
    // Door handles
    final hY = h / 2;
    final hLen = h * .08;
    for (final x in [mid - w * .04, mid + w * .04]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, hY - hLen / 2, 4, hLen),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFD4AF70),
      );
    }
    // Hinge lines
    final hP = Paint()
      ..color = _dk(wood, .4)
      ..strokeWidth = 1;
    for (final yy in [h * .15, h * .85]) {
      canvas.drawCircle(
        Offset(mid - 4, yy),
        2,
        Paint()..color = const Color(0xFFD4AF70),
      );
      canvas.drawCircle(
        Offset(mid + 4, yy),
        2,
        Paint()..color = const Color(0xFFD4AF70),
      );
    }
  }

  void _bookshelf(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF8D7B6A);
    _dropShadow(canvas, w, h, r: 3);
    // Back panel
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _dk(wood, .2));
    // Shelves
    final nShelves = (h / 22).round().clamp(2, 6);
    final shH = h / nShelves;
    final bookColors = [
      const Color(0xFF5B8CBA),
      const Color(0xFFBA5B5B),
      const Color(0xFF5BBA7A),
      const Color(0xFFBAA35B),
      const Color(0xFF8B5BBA),
      const Color(0xFFBA7A5B),
    ];
    for (int s = 0; s < nShelves; s++) {
      final sy = s * shH;
      // Shelf board
      canvas.drawRect(
        Rect.fromLTWH(0, sy + shH - 3, w, 3),
        Paint()..color = _dk(wood, .35),
      );
      // Books on this shelf
      double bx = 3;
      int bIdx = s;
      while (bx < w - 4) {
        final bW = (8.0 + (bIdx * 3 % 8)).clamp(7.0, 16.0);
        if (bx + bW > w - 3) break;
        canvas.drawRect(
          Rect.fromLTWH(bx, sy + 2, bW, shH - 5),
          Paint()..color = bookColors[bIdx % bookColors.length],
        );
        canvas.drawLine(
          Offset(bx, sy + 2),
          Offset(bx, sy + shH - 3),
          Paint()
            ..color = _dk(bookColors[bIdx % bookColors.length], .3)
            ..strokeWidth = 0.5,
        );
        bx += bW + 1;
        bIdx++;
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _cabinet(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF9E8070);
    _dropShadow(canvas, w, h, r: 3);
    _woodGrain(canvas, w, h, wood);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Door divisions
    final nDoors = (w / 60).round().clamp(1, 4);
    final dW = w / nDoors;
    for (int i = 0; i < nDoors; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dW * i + 3, 3, dW - 6, h - 6),
          const Radius.circular(2),
        ),
        Paint()
          ..color = _lt(wood, .08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      // Handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dW * i + dW / 2 - 4, h / 2 - 6, 8, 12),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFD4AF70),
      );
    }
  }

  void _dresser(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF9E8070);
    _dropShadow(canvas, w, h, r: 3);
    _woodGrain(canvas, w, h, wood);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Drawer rows
    final nDrawers = (h / 18).round().clamp(2, 5);
    final dH = h / nDrawers;
    for (int i = 0; i < nDrawers; i++) {
      final dy = dH * i;
      canvas.drawLine(
        Offset(3, dy),
        Offset(w - 3, dy),
        Paint()
          ..color = _dk(wood, .28)
          ..strokeWidth = 1.2,
      );
      // Handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w / 2 - 10, dy + dH / 2 - 3, 20, 6),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFFD4AF70),
      );
    }
  }

  // ── Bedroom ───────────────────────────────────────────────────────────────
  void _bed(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    const headboard = Color(0xFF8D6E63);
    const sheet = Color(0xFFF0EBE2);
    const pillow = Color(0xFFFAF8F5);
    _dropShadow(canvas, w, h, r: 6);
    // Bed frame
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = headboard,
    );
    // Headboard (top section)
    final hbH = h * .15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, hbH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(headboard, .2),
    );
    // Headboard panel detail
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .08, hbH * .15, w * .84, hbH * .7),
        const Radius.circular(3),
      ),
      Paint()
        ..color = _lt(headboard, .1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Mattress / sheet area
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .06, hbH + h * .02, w * .88, h - hbH - h * .08),
        const Radius.circular(3),
      ),
      Paint()..color = sheet,
    );
    // Duvet fold line
    canvas.drawLine(
      Offset(w * .06, hbH + h * .38),
      Offset(w * .94, hbH + h * .38),
      Paint()
        ..color = _dk(sheet, .12)
        ..strokeWidth = 1.5,
    );
    // Two pillows side by side
    final pW = w * .34, pH = hbH + h * .13, pTop = hbH + h * .03;
    for (final px in [w * .08, w - w * .08 - pW]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(px, pTop, pW, pH - pTop),
          const Radius.circular(4),
        ),
        Paint()..color = pillow,
      );
      // Pillow crease
      canvas.drawLine(
        Offset(px + pW * .2, pTop + 4),
        Offset(px + pW * .8, pTop + 4),
        Paint()
          ..color = _dk(pillow, .12)
          ..strokeWidth = 1,
      );
      _ol(
        canvas,
        Rect.fromLTWH(px, pTop, pW, pH - pTop),
        _dk(pillow, .25),
        rad: 4,
        sw: 0.8,
      );
    }
    // Footboard
    canvas.drawRect(
      Rect.fromLTWH(0, h - h * .05, w, h * .05),
      Paint()..color = _dk(headboard, .15),
    );
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(headboard, .4), rad: 4, sw: 1.5);
  }

  void _singleBed(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    const headboard = Color(0xFF8D6E63);
    const sheet = Color(0xFFF0EBE2);
    const pillow = Color(0xFFFAF8F5);
    _dropShadow(canvas, w, h, r: 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = headboard,
    );
    final hbH = h * .15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, hbH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(headboard, .2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .06, hbH + h * .02, w * .88, h - hbH - h * .08),
        const Radius.circular(3),
      ),
      Paint()..color = sheet,
    );
    canvas.drawLine(
      Offset(w * .06, hbH + h * .38),
      Offset(w * .94, hbH + h * .38),
      Paint()
        ..color = _dk(sheet, .12)
        ..strokeWidth = 1.5,
    );
    // Single centre pillow
    final pW = w * .72;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - pW / 2, hbH + h * .03, pW, h * .12),
        const Radius.circular(3),
      ),
      Paint()..color = pillow,
    );
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(headboard, .4), rad: 4, sw: 1.5);
  }

  void _nightstand(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF9E8070);
    _dropShadow(canvas, w, h, r: 3);
    _woodGrain(canvas, w, h, wood);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = _dk(wood, .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Drawer line
    canvas.drawLine(
      Offset(3, h / 2),
      Offset(w - 3, h / 2),
      Paint()
        ..color = _dk(wood, .3)
        ..strokeWidth = 1.2,
    );
    // Handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - 8, h * .65, 16, 5),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFD4AF70),
    );
    // Lamp circle (small)
    canvas.drawCircle(
      Offset(w / 2, h * .28),
      Math.min(w, h) * .18,
      Paint()..color = const Color(0xFFFFE8A0).withOpacity(.6),
    );
    canvas.drawCircle(
      Offset(w / 2, h * .28),
      Math.min(w, h) * .18,
      Paint()
        ..color = const Color(0xFFD4A040)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Decor ─────────────────────────────────────────────────────────────────
  void _plant(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final r = Math.min(w, h) / 2;
    _dropShadow(canvas, w, h, r: r);
    // Pot base
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      r - 2,
      Paint()..color = const Color(0xFF8B6914),
    );
    // Leaves — overlapping ovals
    final leafP = Paint()..color = const Color(0xFF4A8A3A);
    final leafDkP = Paint()..color = const Color(0xFF2E5E24);
    final angles = [0.0, 1.05, 2.1, 3.14, 4.19, 5.24];
    for (final a in angles) {
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.rotate(a);
      canvas.drawOval(
        Rect.fromLTWH(-r * .25, -r * .82, r * .5, r * .65),
        leafP,
      );
      canvas.restore();
    }
    // Centre stem
    canvas.drawCircle(Offset(w / 2, h / 2), r * .22, leafDkP);
    // Pot rim
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      r - 2,
      Paint()
        ..color = const Color(0xFF6B4F10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _lamp(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    _dropShadow(canvas, w, h, r: Math.min(w, h) / 2);
    // Glow circle
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      Math.min(w, h) / 2 - 2,
      Paint()..color = const Color(0xFFFFE8A0).withOpacity(.55),
    );
    // Shade outline
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      Math.min(w, h) / 2 - 2,
      Paint()
        ..color = const Color(0xFFD4A040)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Inner bright spot
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      Math.min(w, h) * .18,
      Paint()..color = const Color(0xFFFFFFCC).withOpacity(.8),
    );
  }

  void _tvStand(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final wood = const Color(0xFF5A5A6A);
    _dropShadow(canvas, w, h, r: 3);
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = wood,
    );
    // TV screen area (dark, glossy)
    final tvW = w * .82, tvH = h * .62;
    final tvR = Rect.fromLTWH(w / 2 - tvW / 2, h * .08, tvW, tvH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tvR, const Radius.circular(3)),
      Paint()..color = const Color(0xFF1A1A2A),
    );
    // Screen reflection
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - tvW / 2 + 4, h * .10, tvW * .3, tvH * .3),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withOpacity(.08),
    );
    // Compartments below
    final cY = h * .76;
    canvas.drawLine(
      Offset(3, cY),
      Offset(w - 3, cY),
      Paint()
        ..color = _dk(wood, .3)
        ..strokeWidth = 1.2,
    );
    final nComps = (w / 55).round().clamp(2, 5);
    final cW = w / nComps;
    for (int i = 1; i < nComps; i++) {
      canvas.drawLine(
        Offset(cW * i, cY),
        Offset(cW * i, h - 3),
        Paint()
          ..color = _dk(wood, .25)
          ..strokeWidth = 1,
      );
    }
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(wood, .5), rad: 4, sw: 1.5);
  }

  void _rug(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 5, w, h),
        const Radius.circular(12),
      ),
      Paint()..color = Colors.black.withOpacity(.12),
    );
    // Main surface
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(10),
      ),
      Paint()..color = c,
    );
    // Fringe lines (short edges)
    final fp = Paint()
      ..color = _dk(c, .25)
      ..strokeWidth = 1.5;
    final nFringe = (w / 8).round();
    for (int i = 0; i < nFringe; i++) {
      final x = w * i / nFringe + 4;
      canvas.drawLine(Offset(x, 0), Offset(x, 5), fp);
      canvas.drawLine(Offset(x, h - 5), Offset(x, h), fp);
    }
    // Border stripe
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .05, h * .07, w * .9, h * .86),
        const Radius.circular(6),
      ),
      Paint()
        ..color = _dk(c, .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Inner border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .1, h * .13, w * .8, h * .74),
        const Radius.circular(4),
      ),
      Paint()
        ..color = _lt(c, .15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Centre medallion
    final cx = w / 2, cy = h / 2;
    canvas.drawOval(
      Rect.fromLTWH(cx - w * .18, cy - h * .22, w * .36, h * .44),
      Paint()..color = _lt(c, .18),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - w * .18, cy - h * .22, w * .36, h * .44),
      Paint()
        ..color = _dk(c, .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _ol(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .35), rad: 10, sw: 1.5);
  }

  @override
  bool shouldRepaint(covariant RoomPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
class MarqueePainter extends CustomPainter {
  final Offset start, end;
  const MarqueePainter(this.start, this.end);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()..color = Colors.blue.withOpacity(.10));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant MarqueePainter old) =>
      old.start != start || old.end != end;
}

// ─────────────────────────────────────────────────────────────────────────────
// CeilingPainter — draws the ceiling view (right panel in split mode)
// ─────────────────────────────────────────────────────────────────────────────
class CeilingPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;
  final double roomWidth, roomDepth, canvasW, canvasH;
  final Color ceilingColour;
  final Color wallColour;
  final Map<String, ui.Image> thumbnails;

  const CeilingPainter({
    required this.furnitureItems,
    required this.selectedItems,
    required this.roomWidth,
    required this.roomDepth,
    required this.canvasW,
    required this.canvasH,
    required this.ceilingColour,
    required this.wallColour,
    this.thumbnails = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Canvas background (outside room) ─────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = const Color(0xFF0D0D11),
    );

    final rr = Rect.fromLTWH(0, 0, roomWidth, roomDepth);

    // ── Ceiling surface — ceiling colour at 22% opacity ───────────────────
    canvas.drawRect(rr, Paint()..color = ceilingColour.withOpacity(0.22));

    // ── Subtle grid ───────────────────────────────────────────────────────
    final gp = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(rr);
    for (double x = 0; x <= roomWidth; x += 20)
      canvas.drawLine(Offset(x, 0), Offset(x, roomDepth), gp);
    for (double y = 0; y <= roomDepth; y += 20)
      canvas.drawLine(Offset(0, y), Offset(roomWidth, y), gp);
    canvas.restore();

    // ── Wall border ───────────────────────────────────────────────────────
    canvas.drawRect(
      rr,
      Paint()
        ..color = wallColour.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // ── Ghost furniture (non-ceiling items at 40% opacity) ────────────────
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = Colors.white.withOpacity(0.40),
    );
    for (final item in furnitureItems) {
      if (item.type == FurnitureType.ceilingSpot) continue;
      canvas.save();
      final cx = item.position.dx + item.size.width / 2;
      final cy = item.position.dy + item.size.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);
      // Draw simple coloured rect as ghost
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, item.size.width, item.size.height),
          const Radius.circular(3),
        ),
        Paint()..color = item.color,
      );
      canvas.restore();
    }
    canvas.restore();

    // ── Ceiling spots — use thumbnail if available ───────────────────────
    for (final item in furnitureItems) {
      if (item.type != FurnitureType.ceilingSpot) continue;
      canvas.save();
      final cx = item.position.dx + item.size.width / 2;
      final cy = item.position.dy + item.size.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      final w = item.size.width;
      final h = item.size.height;
      // Define c and r here so the selection ring always has them in scope
      final r = Math.min(w, h) * 0.45;
      final c = Offset(w / 2, h / 2);

      // Try thumbnail first
      final thumb = thumbnails[item.type.name];
      if (thumb != null) {
        try {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h),
              const Radius.circular(3),
            ),
            Paint()..color = Colors.black.withOpacity(0.2),
          );
          canvas.save();
          canvas.clipRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h),
              const Radius.circular(3),
            ),
          );
          canvas.drawImageRect(
            thumb,
            Rect.fromLTWH(
              0,
              0,
              thumb.width.toDouble(),
              thumb.height.toDouble(),
            ),
            Rect.fromLTWH(0, 0, w, h),
            Paint()..filterQuality = FilterQuality.high,
          );
          canvas.restore();
        } catch (_) {
          _drawCeilingSpotVector(canvas, item);
        }
      } else {
        _drawCeilingSpotVector(canvas, item);
      }

      // Selection ring — uses c and r defined above
      if (selectedItems.contains(item)) {
        canvas.drawCircle(
          c,
          r + 5,
          Paint()
            ..color = const Color(0xFF42A5F5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
      canvas.restore();
    }

    // ── "CEILING LAYER" label ─────────────────────────────────────────────
    final tp = TextPainter(
      text: const TextSpan(
        text: '⬆ CEILING',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFFFFB300),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(8, 6));
  }

  void _drawCeilingSpotVector(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final r = Math.min(w, h) * 0.45;
    final c = Offset(w / 2, h / 2);

    // Large soft glow halo — very visible on dark ceiling background
    canvas.drawCircle(
      c,
      r * 3.2,
      Paint()
        ..color = const Color(0xFFFFEE58).withOpacity(0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      r * 2.0,
      Paint()
        ..color = const Color(0xFFFFEE58).withOpacity(0.38)
        ..style = PaintingStyle.fill,
    );
    // Housing ring (dark grey outer rim)
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF9E9E9E));
    // Bright inner bulb
    canvas.drawCircle(c, r * 0.58, Paint()..color = const Color(0xFFFFF9C4));
    // Emissive centre dot
    canvas.drawCircle(c, r * 0.28, Paint()..color = const Color(0xFFFFFFFF));
    // Outer housing stroke
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF616161)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(CeilingPainter old) => true;
}
