import 'dart:convert';
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
  final _cursorAsset = ValueNotifier<String?>(
    'assets/cursors/canvas_cursor.png',
  );
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
    _cursorAsset.value = 'assets/cursors/canvas_cursor.png';
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
                            _drawTapPos = s;
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
                          setState(() {
                            _isSelectingBox = true;
                            _selectionStart = s;
                            _selectionCurrent = s;
                            if (widget.currentMode == MouseMode.select) {
                              selectedItems.clear();
                              selectedItem = null;
                            }
                          });
                          _cursorAsset.value =
                              'assets/cursors/canvas_cursor.png';
                        },
                        onPanUpdate: (d) {
                          if (_isTrackpadActive) return;
                          final s = _globalToScene(d.globalPosition);
                          _cursorPos.value =
                              (context.findRenderObject() as RenderBox?)
                                  ?.globalToLocal(d.globalPosition);
                          if (_isSelectingBox && _selectionStart != null) {
                            setState(() => _selectionCurrent = s);
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
                          if (widget.currentMode == MouseMode.draw &&
                              _isSelectingBox &&
                              _selectionStart != null &&
                              _selectionCurrent != null) {
                            final rect = Rect.fromPoints(
                              _selectionStart!,
                              _selectionCurrent!,
                            );
                            if (rect.width.abs() > 10 &&
                                rect.height.abs() > 10) {
                              _pushUndo();
                              setState(
                                () => furnitureItems.add(
                                  _newItem(
                                    position: rect.topLeft,
                                    size: Size(
                                      _snap(rect.width.abs()),
                                      _snap(rect.height.abs()),
                                    ),
                                  ),
                                ),
                              );
                              _save();
                            }
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
                          _cursorAsset.value =
                              'assets/cursors/canvas_cursor.png';
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
    _cursorAsset.value = 'assets/cursors/canvas_cursor.png';
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
      ..scale(clamped, clamped, 1.0)
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
      _drawFurniture(canvas, item);
      // Tint overlay: a semi-transparent rectangle in the chosen colour.
      // Blended at 45% opacity so original art shows through.
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

  // ── Custom furniture tile ─────────────────────────────────────────────────
  void _custom(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 6);
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = c,
    );
    // Top accent stripe
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * .20),
        const Radius.circular(6),
      ),
      Paint()..color = _dk(c, .28),
    );
    // Subtle inner highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .08, h * .28, w * .84, h * .55),
        const Radius.circular(4),
      ),
      Paint()..color = _lt(c, .12),
    );
    // Star / custom badge icon drawn as simple lines
    final bp = Paint()
      ..color = Colors.white.withOpacity(.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final bx = w * .85, by = h * .13, br = Math.min(w, h) * .07;
    canvas.drawCircle(Offset(bx, by), br, bp);
    canvas.drawLine(Offset(bx - br * .6, by), Offset(bx + br * .6, by), bp);
    canvas.drawLine(Offset(bx, by - br * .6), Offset(bx, by + br * .6), bp);
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .40), radius: 6);
    // Label — use the user-supplied name, truncated to fit
    final label = (item.labelOverride ?? 'CUSTOM').toUpperCase();
    _lbl(canvas, label, w, h);
  }

  // ── Seating ───────────────────────────────────────────────────────────────
  void _chair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    final bH = h * .22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, bH),
        const Radius.circular(3),
      ),
      Paint()..color = _dk(c, .3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, bH, w, h - bH),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, bH), _dk(c, .45));
    _outline(canvas, Rect.fromLTWH(0, bH, w, h - bH), _dk(c, .45));
    canvas.drawLine(
      Offset(w * .1, bH + (h - bH) * .5),
      Offset(w * .9, bH + (h - bH) * .5),
      Paint()
        ..color = _dk(c, .15)
        ..strokeWidth = 1,
    );
    final lp = Paint()..color = _dk(c, .5);
    for (final p in [
      Offset(w * .12, h * .85),
      Offset(w * .88, h * .85),
      Offset(w * .12, h * .97),
      Offset(w * .88, h * .97),
    ])
      canvas.drawCircle(p, w * .07, lp);
    _lbl(canvas, 'CHAIR', w, h);
  }

  void _sofa(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .2),
    );
    final bH = h * .28;
    final aW = w * .10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, bH),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, bH, aW, h - bH),
        const Radius.circular(3),
      ),
      Paint()..color = _dk(c, .3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - aW, bH, aW, h - bH),
        const Radius.circular(3),
      ),
      Paint()..color = _dk(c, .3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(aW, bH, w - aW * 2, h - bH),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    final sW = w - aW * 2;
    final dp = Paint()
      ..color = _dk(c, .2)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(aW + sW / 3, bH + 4),
      Offset(aW + sW / 3, h - 4),
      dp,
    );
    canvas.drawLine(
      Offset(aW + sW * 2 / 3, bH + 4),
      Offset(aW + sW * 2 / 3, h - 4),
      dp,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 5);
    _lbl(canvas, 'SOFA', w, h);
  }

  void _armchair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 6);
    final aW = w * .12;
    final bH = h * .30;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, bH),
        const Radius.circular(6),
      ),
      Paint()..color = _dk(c, .3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, bH, aW, h - bH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(c, .25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - aW, bH, aW, h - bH),
        const Radius.circular(4),
      ),
      Paint()..color = _dk(c, .25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(aW, bH, w - aW * 2, h - bH),
        const Radius.circular(4),
      ),
      Paint()..color = c,
    );
    canvas.drawCircle(
      Offset(w / 2, bH + (h - bH) * .45),
      5,
      Paint()..color = _dk(c, .2),
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 6);
    _lbl(canvas, 'ARM', w, h);
  }

  void _bench(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * .6),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    canvas.drawLine(
      Offset(w * .05, h * .55),
      Offset(w * .95, h * .55),
      Paint()
        ..color = _dk(c, .2)
        ..strokeWidth = 1.5,
    );
    final legW = w * .08;
    final legH = h * .4;
    final lp = Paint()..color = _dk(c, .35);
    canvas.drawRect(Rect.fromLTWH(w * .05, h * .6, legW, legH), lp);
    canvas.drawRect(Rect.fromLTWH(w * .45, h * .6, legW, legH), lp);
    canvas.drawRect(Rect.fromLTWH(w - w * .05 - legW, h * .6, legW, legH), lp);
    _outline(canvas, Rect.fromLTWH(0, 0, w, h * .6), _dk(c, .4), radius: 3);
    _lbl(canvas, 'BENCH', w, h * .6);
  }

  void _stool(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawOval(Rect.fromLTWH(0, 0, w, h * .55), Paint()..color = c);
    canvas.drawOval(
      Rect.fromLTWH(0, 0, w, h * .55),
      Paint()
        ..color = _dk(c, .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawOval(
      Rect.fromLTWH(w * .35, h * .15, w * .3, h * .25),
      Paint()..color = _dk(c, .25),
    );
    canvas.drawLine(
      Offset(w * .5, h * .55),
      Offset(w * .5, h * .85),
      Paint()
        ..color = _dk(c, .4)
        ..strokeWidth = w * .15,
    );
    canvas.drawOval(
      Rect.fromLTWH(w * .15, h * .8, w * .7, h * .2),
      Paint()..color = _dk(c, .3),
    );
    _lbl(canvas, 'STOOL', w, h * .55);
  }

  // ── Tables ────────────────────────────────────────────────────────────────
  void _table(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.black.withOpacity(.15),
    );
    final lW = w * .10;
    final lH = h * .14;
    final lp = Paint()..color = _dk(c, .35);
    for (final p in [
      Offset(0, 0),
      Offset(w - lW, 0),
      Offset(0, h - lH),
      Offset(w - lW, h - lH),
    ])
      canvas.drawRect(Rect.fromLTWH(p.dx, p.dy, lW, lH), lp);
    final sr = Rect.fromLTWH(lW * .3, lH * .3, w - lW * .6, h - lH * .6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sr, const Radius.circular(3)),
      Paint()..color = c,
    );
    _outline(canvas, sr, _dk(c, .4));
    final gp = Paint()
      ..color = _dk(c, .1)
      ..strokeWidth = .8;
    for (int i = 1; i < 4; i++)
      canvas.drawLine(
        Offset(lW * .5, h * .2 + (h * .6 / 4) * i),
        Offset(w - lW * .5, h * .2 + (h * .6 / 4) * i),
        gp,
      );
    _lbl(canvas, 'TABLE', w, h);
  }

  void _coffeeTable(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(8),
      ),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 6, w - 12, h - 12),
        const Radius.circular(5),
      ),
      Paint()..color = _lt(c, .25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, w * .4, h * .25),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withOpacity(.15),
    );
    final lp = Paint()..color = _dk(c, .5);
    for (final p in [
      Offset(0, 0),
      Offset(w - 8, 0),
      Offset(0, h - 8),
      Offset(w - 8, h - 8),
    ])
      canvas.drawRect(Rect.fromLTWH(p.dx, p.dy, 8, 8), lp);
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 8);
    _lbl(canvas, 'COFFEE', w, h);
  }

  void _desk(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = c,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * .65, 0, w * .35, h),
      Paint()..color = _dk(c, .12),
    );
    final dp = Paint()
      ..color = _dk(c, .35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(w * .65, h * .33), Offset(w, h * .33), dp);
    canvas.drawLine(Offset(w * .65, h * .66), Offset(w, h * .66), dp);
    for (final y in [h * .16, h * .5, h * .83])
      canvas.drawCircle(Offset(w * .83, y), 3, Paint()..color = _lt(c, .4));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * .06, h),
      Paint()..color = _dk(c, .3),
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 4);
    _lbl(canvas, 'DESK', w * .6, h);
  }

  void _sideTable(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .1, h * .2, w * .8, h * .5),
        const Radius.circular(3),
      ),
      Paint()..color = _lt(c, .15),
    );
    _outline(
      canvas,
      Rect.fromLTWH(w * .1, h * .2, w * .8, h * .5),
      _dk(c, .3),
      radius: 3,
    );
    canvas.drawCircle(Offset(w * .5, h * .45), 4, Paint()..color = _lt(c, .5));
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 6);
    _lbl(canvas, 'SIDE', w, h * .2);
  }

  // ── Storage ───────────────────────────────────────────────────────────────
  void _wardrobe(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    canvas.drawLine(
      Offset(w * .5, 0),
      Offset(w * .5, h),
      Paint()
        ..color = _dk(c, .4)
        ..strokeWidth = 2,
    );
    for (final x in [w * .05, w * .55]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h * .08, w * .44, h * .8),
          const Radius.circular(2),
        ),
        Paint()..color = _lt(c, .08),
      );
      _outline(
        canvas,
        Rect.fromLTWH(x, h * .08, w * .44, h * .8),
        _dk(c, .25),
        radius: 2,
      );
    }
    for (final x in [w * .5 - w * .07, w * .5 + w * .04])
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h * .42, w * .03, h * .16),
          const Radius.circular(2),
        ),
        Paint()..color = _lt(c, .5),
      );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 3);
    _lbl(canvas, 'WARDROBE', w, h * .08);
  }

  void _bookshelf(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = _dk(c, .1),
    );
    final shelves = 3;
    final shelfH = h / shelves;
    for (int i = 0; i <= shelves; i++)
      canvas.drawRect(
        Rect.fromLTWH(0, shelfH * i - 2, w, 4),
        Paint()..color = _dk(c, .3),
      );
    final bkColors = [
      Colors.red.shade300,
      Colors.blue.shade300,
      Colors.green.shade300,
      Colors.orange.shade300,
      Colors.purple.shade300,
      Colors.teal.shade300,
      Colors.pink.shade200,
    ];
    for (int shelf = 0; shelf < shelves; shelf++) {
      double bx = w * .03;
      int bi = (shelf * 3) % bkColors.length;
      while (bx < w * .92) {
        final bw = (w * .04 + w * .04 * ((bx * 7) % 1)).clamp(w * .03, w * .1);
        if (bx + bw > w * .92) break;
        canvas.drawRect(
          Rect.fromLTWH(bx, shelfH * shelf + 4, bw, shelfH - 8),
          Paint()..color = bkColors[bi % bkColors.length],
        );
        bx += bw + w * .012;
        bi++;
      }
    }
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .5), radius: 3);
    _lbl(canvas, 'BOOKS', w, h - 12);
  }

  void _cabinet(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    final dw = w * .44;
    final dh = h * .75;
    final dy = h * .12;
    for (final dx in [w * .04, w * .52]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, dy, dw, dh),
          const Radius.circular(2),
        ),
        Paint()..color = _lt(c, .12),
      );
      _outline(canvas, Rect.fromLTWH(dx, dy, dw, dh), _dk(c, .3), radius: 2);
      canvas.drawCircle(
        Offset(dx + dw * .78, dy + dh * .5),
        4,
        Paint()..color = _lt(c, .55),
      );
    }
    canvas.drawLine(
      Offset(0, h * .12),
      Offset(w, h * .12),
      Paint()
        ..color = _dk(c, .3)
        ..strokeWidth = 1.5,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 3);
    _lbl(canvas, 'CABINET', w, h * .12);
  }

  void _dresser(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    final rows = 3;
    final dh = (h - (rows + 1) * 4.0) / rows;
    for (int i = 0; i < rows; i++) {
      final dy = 4.0 + i * (dh + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * .04, dy, w * .92, dh),
          const Radius.circular(2),
        ),
        Paint()..color = _lt(c, .1),
      );
      _outline(
        canvas,
        Rect.fromLTWH(w * .04, dy, w * .92, dh),
        _dk(c, .3),
        radius: 2,
      );
      for (final kx in [w * .35, w * .65])
        canvas.drawCircle(
          Offset(kx, dy + dh * .5),
          3.5,
          Paint()..color = _lt(c, .55),
        );
    }
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 3);
    _lbl(canvas, 'DRESSER', w, 4);
  }

  // ── Bedroom ───────────────────────────────────────────────────────────────
  void _bed(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = _dk(c, .35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * .18),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .45),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, h * .16, w * .92, h * .8),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFF5F0E8),
    );
    final pw = w * .4;
    final pOff = w * .06;
    for (final px in [pOff, w - pOff - pw]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(px, h * .2, pw, h * .18),
          const Radius.circular(5),
        ),
        Paint()..color = Colors.white,
      );
      _outline(
        canvas,
        Rect.fromLTWH(px, h * .2, pw, h * .18),
        Colors.grey.shade300,
        radius: 5,
        sw: 1,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, h * .42, w * .92, h * .52),
        const Radius.circular(4),
      ),
      Paint()..color = _lt(c, .3),
    );
    canvas.drawLine(
      Offset(w * .04, h * .44),
      Offset(w * .96, h * .44),
      Paint()
        ..color = _dk(c, .15)
        ..strokeWidth = 1.5,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 6);
    _lbl(canvas, 'BED', w, h * .42);
  }

  void _singleBed(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h, r: 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = _dk(c, .35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * .18),
        const Radius.circular(5),
      ),
      Paint()..color = _dk(c, .45),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, h * .16, w * .92, h * .8),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFF5F0E8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .1, h * .2, w * .8, h * .18),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.white,
    );
    _outline(
      canvas,
      Rect.fromLTWH(w * .1, h * .2, w * .8, h * .18),
      Colors.grey.shade300,
      radius: 5,
      sw: 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, h * .42, w * .92, h * .52),
        const Radius.circular(4),
      ),
      Paint()..color = _lt(c, .3),
    );
    canvas.drawLine(
      Offset(w * .04, h * .44),
      Offset(w * .96, h * .44),
      Paint()
        ..color = _dk(c, .15)
        ..strokeWidth = 1.5,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 6);
    _lbl(canvas, 'SINGLE', w, h * .42);
  }

  void _nightstand(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .08, h * .12, w * .84, h * .55),
        const Radius.circular(2),
      ),
      Paint()..color = _lt(c, .15),
    );
    _outline(
      canvas,
      Rect.fromLTWH(w * .08, h * .12, w * .84, h * .55),
      _dk(c, .3),
      radius: 2,
    );
    canvas.drawCircle(Offset(w * .5, h * .4), 4, Paint()..color = _lt(c, .6));
    canvas.drawLine(
      Offset(w * .08, h * .75),
      Offset(w * .92, h * .75),
      Paint()
        ..color = _dk(c, .25)
        ..strokeWidth = 1.2,
    );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .4), radius: 4);
    _lbl(canvas, 'NSTAND', w, h * .12);
  }

  // ── Decor ─────────────────────────────────────────────────────────────────
  void _plant(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    final potH = h * .38;
    final potPath = Path()
      ..moveTo(w * .25, h - potH)
      ..lineTo(w * .15, h)
      ..lineTo(w * .85, h)
      ..lineTo(w * .75, h - potH)
      ..close();
    canvas.drawPath(potPath, Paint()..color = const Color(0xFFB07040));
    canvas.drawRect(
      Rect.fromLTWH(w * .2, h - potH, w * .6, h * .04),
      Paint()..color = const Color(0xFF8B5A2B),
    );
    for (final angle in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8]) {
      final cx = w * .5 + Math.cos(angle) * w * .18;
      final cy = h * .35 + Math.sin(angle) * h * .15;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w * .45,
          height: h * .28,
        ),
        Paint()..color = angle.abs() < .1 ? c : _dk(c, .2),
      );
    }
    canvas.drawLine(
      Offset(w * .5, h - potH),
      Offset(w * .5, h * .5),
      Paint()
        ..color = _dk(c, .35)
        ..strokeWidth = 2,
    );
    _lbl(canvas, 'PLANT', w, h * .62, color: Colors.white);
  }

  void _lamp(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    canvas.drawCircle(
      Offset(w * .5, h * .3),
      w * .42,
      Paint()..color = c.withOpacity(.18),
    );
    final shadePath = Path()
      ..moveTo(w * .15, h * .38)
      ..lineTo(w * .3, h * .08)
      ..lineTo(w * .7, h * .08)
      ..lineTo(w * .85, h * .38)
      ..close();
    canvas.drawPath(shadePath, Paint()..color = c);
    canvas.drawPath(
      shadePath,
      Paint()
        ..color = _dk(c, .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(w * .5, h * .38),
      w * .08,
      Paint()..color = Colors.white.withOpacity(.9),
    );
    canvas.drawLine(
      Offset(w * .5, h * .4),
      Offset(w * .5, h * .82),
      Paint()
        ..color = _dk(c, .5)
        ..strokeWidth = w * .06,
    );
    final basePath = Path()
      ..moveTo(w * .25, h * .82)
      ..lineTo(w * .2, h)
      ..lineTo(w * .8, h)
      ..lineTo(w * .75, h * .82)
      ..close();
    canvas.drawPath(basePath, Paint()..color = _dk(c, .4));
    _lbl(canvas, 'LAMP', w, h * .6, color: Colors.white70);
  }

  void _tvStand(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    _shadow(canvas, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(3),
      ),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * .25),
        const Radius.circular(3),
      ),
      Paint()..color = _lt(c, .08),
    );
    final compW = (w - 8) / 3;
    for (int i = 0; i < 3; i++) {
      final dx = 4.0 + i * (compW + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, h * .3, compW, h * .62),
          const Radius.circular(2),
        ),
        Paint()..color = _lt(c, .06),
      );
      _outline(
        canvas,
        Rect.fromLTWH(dx, h * .3, compW, h * .62),
        _dk(c, .3),
        radius: 2,
      );
    }
    for (final fx in [w * .05, w * .5 - 6.0, w * .95 - 12.0])
      canvas.drawRect(
        Rect.fromLTWH(fx, h * .95, 12, h * .05),
        Paint()..color = _dk(c, .5),
      );
    _outline(canvas, Rect.fromLTWH(0, 0, w, h), _dk(c, .45), radius: 3);
    _lbl(canvas, 'TV STAND', w, h * .3);
  }

  void _rug(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w, h),
        const Radius.circular(12),
      ),
      Paint()..color = Colors.black.withOpacity(.10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(10),
      ),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .06, h * .08, w * .88, h * .84),
        const Radius.circular(6),
      ),
      Paint()..color = _lt(c, .18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .1, h * .12, w * .8, h * .76),
        const Radius.circular(4),
      ),
      Paint()
        ..color = _lt(c, .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final cx = w * .5;
    final cy = h * .5;
    final dw = w * .2;
    final dh = h * .25;
    final diamond = Path()
      ..moveTo(cx, cy - dh)
      ..lineTo(cx + dw, cy)
      ..lineTo(cx, cy + dh)
      ..lineTo(cx - dw, cy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = _lt(c, .25));
    canvas.drawPath(
      diamond,
      Paint()
        ..color = _dk(c, .1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _outline(
      canvas,
      Rect.fromLTWH(0, 0, w, h),
      _dk(c, .35),
      radius: 10,
      sw: 1.5,
    );
    _lbl(canvas, 'RUG', w, h);
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
