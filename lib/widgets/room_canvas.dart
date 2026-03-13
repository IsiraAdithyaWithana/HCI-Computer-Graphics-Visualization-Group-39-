import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
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
    // custom fields — null for all built-in types
    this.customGlbOverride,
    this.customLabelOverride,
    this.customColor,
    this.customDefaultSize,
    this.onChanged,
    this.onUndoStateChanged,
    this.thumbnails = const {},
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
      furnitureItems = decoded.map((e) => FurnitureModel.fromJson(e)).toList();
      selectedItems.clear();
      selectedItem = null;
    });
  }

  void _save() => widget.onChanged?.call();

  // ── Coordinate helpers ────────────────────────────────────────────────────
  Offset _toScene(Offset screenPos) => MatrixUtils.transformPoint(
    Matrix4.inverted(_transformationController.value),
    screenPos,
  );

  Offset _globalToScene(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox;
    return _toScene(box.globalToLocal(globalPos));
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

  // Returns true if scene point [p] lies within the room rectangle
  bool _insideRoom(Offset p) {
    return p.dx >= 0 &&
        p.dx <= widget.roomWidthPx &&
        p.dy >= 0 &&
        p.dy <= widget.roomDepthPx;
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
        return const Size(140, 50);
      case FurnitureType.stool:
        return const Size(45, 45);
      case FurnitureType.table:
        return const Size(120, 80);
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
    if (size != null) {
      // Explicit size supplied (e.g. from draw-drag) — use it directly.
      itemSize = size;
    } else if (widget.selectedType == FurnitureType.custom &&
        widget.customGlbOverride != null) {
      // Custom GLB: inherit NATURAL size from an already-placed sibling
      // (same GLB file). Back-calculate naturalSize = size / sf, then use at sf=1.
      final existing = furnitureItems
          .where((f) => f.glbOverride == widget.customGlbOverride)
          .firstOrNull;
      if (existing != null) {
        final sf = existing.scaleFactor > 0 ? existing.scaleFactor : 1.0;
        itemSize = Size(existing.size.width / sf, existing.size.height / sf);
      } else {
        itemSize = widget.customDefaultSize ?? const Size(80, 80);
      }
    } else {
      // Built-in type: if a sibling has been resized, inherit its natural size
      // so new placements match the user's saved size preference.
      final sibling = furnitureItems
          .where((f) => f.type == widget.selectedType)
          .firstOrNull;
      if (sibling != null) {
        final sf = sibling.scaleFactor > 0 ? sibling.scaleFactor : 1.0;
        // Natural size = size at scaleFactor=1; new items always start at sf=1
        itemSize = Size(sibling.size.width / sf, sibling.size.height / sf);
      } else {
        itemSize = _defaultSize(widget.selectedType);
      }
    }

    final freePos = _findFreePosition(_snapOffset(position), itemSize);
    return FurnitureModel(
      id: DateTime.now().toString(),
      type: widget.selectedType,
      position: freePos,
      size: itemSize,
      color: _defaultColor(widget.selectedType),
      glbOverride: widget.selectedType == FurnitureType.custom
          ? widget.customGlbOverride
          : null,
      labelOverride: widget.selectedType == FurnitureType.custom
          ? widget.customLabelOverride
          : null,
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
      child: MouseRegion(
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
                            // Only allow placement inside the room
                            if (_insideRoom(s)) _drawTapPos = s;
                            return;
                          }
                          if (widget.currentMode != MouseMode.select) return;
                          if (_onAnyHandle(s)) return;
                          for (final item in furnitureItems.reversed) {
                            if (_inside(item, s)) {
                              setState(() {
                                if (HardwareKeyboard
                                    .instance
                                    .isControlPressed) {
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
                              _showContextMenu(d.globalPosition);
                              return;
                            }
                          }
                        },
                        onPanStart: (d) {
                          if (_isTrackpadActive) return;
                          _drawTapPos = null;
                          if (widget.currentMode == MouseMode.hand) {
                            setState(() => _isPanningCanvas = true);
                            _cursorAsset.value =
                                'assets/cursors/grab_cursor.png';
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
                                  if (!HardwareKeyboard
                                      .instance
                                      .isControlPressed)
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
                              for (final item in selectedItems)
                                item.position += delta;
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
                                item.position = _snapOffset(item.position);
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
                                  final r = Rect.fromLTWH(
                                    item.position.dx,
                                    item.position.dy,
                                    item.size.width,
                                    item.size.height,
                                  );
                                  for (final other in furnitureItems) {
                                    if (draggedIds.contains(other.id)) continue;
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
                            _cursorAsset.value =
                                'assets/cursors/add_cursor.png';
                          } else {
                            _cursorAsset.value =
                                'assets/cursors/main_cursor.png';
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
                                    furnitureItems: furnitureItems,
                                    selectedItems: selectedItems,
                                    roomWidth: widget.roomWidthPx,
                                    roomDepth: widget.roomDepthPx,
                                    canvasW: _canvasW,
                                    canvasH: _canvasH,
                                    canvasBgColour: widget.canvasBgColour,
                                    roomFloorColour: widget.roomFloorColour,
                                    roomWallColour: widget.roomWallColour,
                                    thumbnails: widget.thumbnails,
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
                        left: pos.dx - _cursorSize / 2,
                        top: pos.dy - _cursorSize / 2,
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background (area outside the room) — uses the configurable canvas bg colour
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = canvasBgColour,
    );
    final rr = Rect.fromLTWH(0, 0, roomWidth, roomDepth);
    // Room floor — use the scheme colour
    canvas.drawRect(rr, Paint()..color = roomFloorColour);

    // Grid — adapts to floor colour
    canvas.save();
    canvas.clipRect(rr);
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

    // Shadow + walls
    canvas.drawRect(
      rr.inflate(2),
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRect(
      rr,
      Paint()
        ..color = roomWallColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    final cp = Paint()..color = roomWallColour;
    for (final c in [
      Offset(0, 0),
      Offset(roomWidth, 0),
      Offset(0, roomDepth),
      Offset(roomWidth, roomDepth),
    ])
      canvas.drawCircle(c, 5, cp);

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
      if (thumb != null) {
        _drawThumbnailTile(canvas, item, thumb);
      } else {
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
  void _drawThumbnailTile(Canvas canvas, FurnitureModel item, ui.Image img) {
    final w = item.size.width;
    final h = item.size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // Drop shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 3), const Radius.circular(4)),
      Paint()..color = Colors.black.withOpacity(0.25),
    );

    // Clip to rounded rect
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));

    // Draw the thumbnail image stretched to fill the tile
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.restore();

    // Thin border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
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
      // ── Custom furniture: styled labelled tile ─────────────────────────
      case FurnitureType.custom:
        _custom(canvas, item);
        break;
    }
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
