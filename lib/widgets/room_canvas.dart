import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
import 'dart:math' as Math;

enum MouseMode { select, hand, draw }

class RoomCanvas extends StatefulWidget {
  final FurnitureType selectedType;
  final MouseMode currentMode;

  const RoomCanvas({
    super.key,
    required this.selectedType,
    required this.currentMode,
  });

  @override
  State<RoomCanvas> createState() => RoomCanvasState();
}

class RoomCanvasState extends State<RoomCanvas> {
  List<FurnitureModel> furnitureItems = [];
  List<FurnitureModel> selectedItems = [];
  FurnitureModel? selectedItem;

  Offset? _dragStart;
  bool _isRotating = false;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _isPanningCanvas = false;

  bool _isSelectingBox = false;
  Offset? _selectionStart;
  Offset? _selectionCurrent;

  Offset? _hoverScreenPosition;
  Offset? _hoverScenePosition;
  bool _showRotateCursor = false;
  bool _showResizeCursor = false;
  bool _showMoveCursor = false;

  final double gridSize = 20;
  bool enableSnap = true;
  bool snapResizeEnabled = true;

  static const double _cursorSize = 32;

  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isSnapResizeEnabled => snapResizeEnabled;
  void toggleResizeSnap() =>
      setState(() => snapResizeEnabled = !snapResizeEnabled);

  double get currentZoom => _transformationController.value.getMaxScaleOnAxis();

  void setZoom(double zoom) {
    final current = _transformationController.value;
    final oldScale = current.getMaxScaleOnAxis();
    final ratio = zoom / oldScale;
    final box = context.findRenderObject() as RenderBox?;
    final centre = box != null
        ? Offset(box.size.width / 2, box.size.height / 2)
        : Offset.zero;

    final updated = current.clone()
      ..translate(centre.dx, centre.dy)
      ..scale(ratio)
      ..translate(-centre.dx, -centre.dy);

    _transformationController.value = updated;
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

  // ── Coordinate helpers ─────────────────────────────────────────────────────

  Offset _toScene(Offset screenPos) => MatrixUtils.transformPoint(
    Matrix4.inverted(_transformationController.value),
    screenPos,
  );

  Offset _globalToScene(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox;
    return _toScene(box.globalToLocal(globalPos));
  }

  Offset _globalToLocal(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox;
    return box.globalToLocal(globalPos);
  }

  // ── Snap helpers ───────────────────────────────────────────────────────────

  double _snap(double value) =>
      enableSnap ? (value / gridSize).round() * gridSize : value;

  Offset _snapOffset(Offset o) => Offset(_snap(o.dx), _snap(o.dy));

  // ── Geometry helpers ───────────────────────────────────────────────────────

  Offset _toLocalRotatedSpace(FurnitureModel item, Offset scenePoint) {
    final center = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );
    final dx = scenePoint.dx - center.dx;
    final dy = scenePoint.dy - center.dy;
    final cosR = Math.cos(-item.rotation);
    final sinR = Math.sin(-item.rotation);
    return Offset(
      dx * cosR - dy * sinR + item.size.width / 2,
      dx * sinR + dy * cosR + item.size.height / 2,
    );
  }

  bool _isInsideRotated(FurnitureModel item, Offset scenePoint) {
    final local = _toLocalRotatedSpace(item, scenePoint);
    return local.dx >= 0 &&
        local.dx <= item.size.width &&
        local.dy >= 0 &&
        local.dy <= item.size.height;
  }

  bool _isOnResizeHandle(FurnitureModel item, Offset scenePoint) {
    final local = _toLocalRotatedSpace(item, scenePoint);
    return (local - Offset(item.size.width, item.size.height)).distance <= 18;
  }

  bool _isOnRotateHandle(FurnitureModel item, Offset scenePoint) {
    final center = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );
    final dist = item.size.height / 2 + 25;
    final handle = Offset(
      center.dx + dist * Math.cos(item.rotation - 1.5708),
      center.dy + dist * Math.sin(item.rotation - 1.5708),
    );
    return (scenePoint - handle).distance <= 35;
  }

  bool _isOnAnyHandle(Offset scenePos) {
    if (selectedItem == null) return false;
    return _isOnRotateHandle(selectedItem!, scenePos) ||
        _isOnResizeHandle(selectedItem!, scenePos);
  }

  // ── Cursor helpers ─────────────────────────────────────────────────────────

  String? get _activeCursorAsset {
    if (_showRotateCursor || _isRotating)
      return 'assets/cursors/rotate_cursor.png';
    if (_showResizeCursor || _isResizing)
      return 'assets/cursors/expand_cursor.png';
    if (_showMoveCursor || _isDragging) return 'assets/cursors/move_cursor.png';
    if (_hoverScreenPosition != null) return 'assets/cursors/canvas_cursor.png';
    return null;
  }

  void _updateCursorFlags(Offset scenePos) {
    _showRotateCursor = false;
    _showResizeCursor = false;
    _showMoveCursor = false;

    if (selectedItem != null) {
      if (_isOnRotateHandle(selectedItem!, scenePos)) {
        _showRotateCursor = true;
        return;
      }
      if (_isOnResizeHandle(selectedItem!, scenePos)) {
        _showResizeCursor = true;
        return;
      }
    }
    for (final item in furnitureItems.reversed) {
      if (_isInsideRotated(item, scenePos)) {
        _showMoveCursor = true;
        return;
      }
    }
  }

  // ── Context menu ───────────────────────────────────────────────────────────

  void _showContextMenu(Offset globalPosition) async {
    if (selectedItem == null) return;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'rotate', child: Text('Rotate 90°')),
      ],
    );

    if (result == 'delete') {
      setState(() {
        furnitureItems.removeWhere((i) => selectedItems.contains(i));
        selectedItems.clear();
        selectedItem = null;
      });
    } else if (result == 'duplicate') {
      setState(() {
        furnitureItems.add(
          FurnitureModel(
            id: DateTime.now().toString(),
            type: selectedItem!.type,
            position: selectedItem!.position + const Offset(20, 20),
            size: selectedItem!.size,
            color: selectedItem!.color,
            rotation: selectedItem!.rotation,
          ),
        );
      });
    } else if (result == 'rotate') {
      setState(() => selectedItem!.rotation += 1.5708);
    }
  }

  // ── Furniture defaults ─────────────────────────────────────────────────────

  Size _defaultSize(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return const Size(60, 60);
      case FurnitureType.table:
        return const Size(120, 80);
      case FurnitureType.sofa:
        return const Size(160, 75);
    }
  }

  Color _defaultColor(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return const Color(0xFF8B6F47);
      case FurnitureType.table:
        return const Color(0xFF6B4423);
      case FurnitureType.sofa:
        return const Color(0xFF4A6FA5);
    }
  }

  FurnitureModel _newItem({required Offset position, Size? size}) =>
      FurnitureModel(
        id: DateTime.now().toString(),
        type: widget.selectedType,
        position: _snapOffset(position),
        size: size ?? _defaultSize(widget.selectedType),
        color: _defaultColor(widget.selectedType),
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cursorAsset = _activeCursorAsset;
    final showCursorOverlay =
        cursorAsset != null && _hoverScreenPosition != null;

    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.delete &&
            selectedItems.isNotEmpty) {
          setState(() {
            furnitureItems.removeWhere((i) => selectedItems.contains(i));
            selectedItems.clear();
            selectedItem = null;
          });
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.none,
        onHover: (event) {
          final scene = _toScene(event.localPosition);
          setState(() {
            _hoverScenePosition = scene;
            _hoverScreenPosition = event.localPosition;
            _updateCursorFlags(scene);
          });
        },
        onExit: (_) {
          setState(() {
            _hoverScenePosition = null;
            _hoverScreenPosition = null;
            _showRotateCursor = false;
            _showResizeCursor = false;
            _showMoveCursor = false;
          });
        },
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(1000),
              minScale: 0.3,
              maxScale: 3.0,
              panEnabled: widget.currentMode == MouseMode.hand,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,

                onTapDown: (details) {
                  if (widget.currentMode != MouseMode.select) return;
                  final scenePos = _globalToScene(details.globalPosition);
                  if (_isOnAnyHandle(scenePos)) return;

                  for (final item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
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

                onTapUp: (details) {
                  if (widget.currentMode != MouseMode.draw) return;
                  final scenePos = _globalToScene(details.globalPosition);
                  setState(
                    () => furnitureItems.add(_newItem(position: scenePos)),
                  );
                },

                onSecondaryTapDown: (details) {
                  final scenePos = _globalToScene(details.globalPosition);
                  for (final item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
                      setState(() {
                        selectedItem = item;
                        if (!selectedItems.contains(item)) {
                          selectedItems
                            ..clear()
                            ..add(item);
                        }
                      });
                      _showContextMenu(details.globalPosition);
                      return;
                    }
                  }
                },

                onPanStart: (details) {
                  if (widget.currentMode == MouseMode.hand) {
                    setState(() {
                      _isPanningCanvas = true;
                      _dragStart = details.globalPosition;
                    });
                    return;
                  }
                  final scenePos = _globalToScene(details.globalPosition);

                  if (selectedItem != null &&
                      _isOnRotateHandle(selectedItem!, scenePos)) {
                    setState(() {
                      _isRotating = true;
                      _showRotateCursor = true;
                      _showResizeCursor = false;
                      _showMoveCursor = false;
                    });
                    return;
                  }
                  if (selectedItem != null &&
                      _isOnResizeHandle(selectedItem!, scenePos)) {
                    setState(() {
                      _isResizing = true;
                      _showResizeCursor = true;
                      _showRotateCursor = false;
                      _showMoveCursor = false;
                    });
                    return;
                  }

                  for (final item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
                      setState(() {
                        if (!selectedItems.contains(item)) {
                          if (!HardwareKeyboard.instance.isControlPressed)
                            selectedItems.clear();
                          selectedItems.add(item);
                        }
                        selectedItem = item;
                        _isDragging = true;
                        _showMoveCursor = true;
                        _showRotateCursor = false;
                        _showResizeCursor = false;
                      });
                      _dragStart = scenePos;
                      return;
                    }
                  }

                  setState(() {
                    _isSelectingBox = true;
                    _selectionStart = scenePos;
                    _selectionCurrent = scenePos;
                    if (widget.currentMode == MouseMode.select) {
                      selectedItems.clear();
                      selectedItem = null;
                    }
                  });
                },

                onPanUpdate: (details) {
                  final scenePos = _globalToScene(details.globalPosition);
                  final localPos = _globalToLocal(details.globalPosition);

                  if (_isSelectingBox && _selectionStart != null) {
                    setState(() {
                      _selectionCurrent = scenePos;
                      _hoverScreenPosition = localPos;
                    });
                    return;
                  }
                  if (_isRotating && selectedItem != null) {
                    final center = Offset(
                      selectedItem!.position.dx + selectedItem!.size.width / 2,
                      selectedItem!.position.dy + selectedItem!.size.height / 2,
                    );
                    setState(() {
                      selectedItem!.rotation =
                          Math.atan2(
                            scenePos.dy - center.dy,
                            scenePos.dx - center.dx,
                          ) +
                          1.5708;
                      _hoverScreenPosition = localPos;
                    });
                    return;
                  }
                  if (_isResizing && selectedItem != null) {
                    final local = _toLocalRotatedSpace(selectedItem!, scenePos);
                    double w = local.dx.clamp(40.0, 800.0);
                    double h = local.dy.clamp(40.0, 800.0);
                    if (snapResizeEnabled) {
                      w = _snap(w);
                      h = _snap(h);
                    }
                    setState(() {
                      selectedItem!.size = Size(w, h);
                      _hoverScreenPosition = localPos;
                    });
                    return;
                  }
                  if (_isDragging &&
                      selectedItems.isNotEmpty &&
                      _dragStart != null) {
                    final delta = scenePos - _dragStart!;
                    setState(() {
                      for (final item in selectedItems) item.position += delta;
                      _hoverScreenPosition = localPos;
                    });
                    _dragStart = scenePos;
                    return;
                  }
                  if (_isPanningCanvas && _dragStart != null) {
                    final scale = _transformationController.value
                        .getMaxScaleOnAxis();
                    _transformationController.value =
                        _transformationController.value.clone()..translate(
                          details.delta.dx / scale,
                          details.delta.dy / scale,
                        );
                    _dragStart = details.globalPosition;
                    setState(() => _hoverScreenPosition = localPos);
                  }
                },

                onPanEnd: (_) {
                  if (widget.currentMode == MouseMode.draw &&
                      _selectionStart != null &&
                      _selectionCurrent != null) {
                    final rect = Rect.fromPoints(
                      _selectionStart!,
                      _selectionCurrent!,
                    );
                    if (rect.width.abs() > 10 && rect.height.abs() > 10) {
                      setState(() {
                        furnitureItems.add(
                          _newItem(
                            position: rect.topLeft,
                            size: Size(
                              _snap(rect.width.abs()),
                              _snap(rect.height.abs()),
                            ),
                          ),
                        );
                      });
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
                        item.size = Size(
                          _snap(item.size.width).clamp(40.0, 800.0),
                          _snap(item.size.height).clamp(40.0, 800.0),
                        );
                      }
                    });
                  }
                  setState(() {
                    _isRotating = false;
                    _isDragging = false;
                    _isResizing = false;
                    _isPanningCanvas = false;
                    _isSelectingBox = false;
                    _selectionStart = null;
                    _selectionCurrent = null;
                    _showRotateCursor = false;
                    _showResizeCursor = false;
                    _showMoveCursor = false;
                  });
                  _dragStart = null;
                },

                child: Stack(
                  children: [
                    CustomPaint(
                      painter: RoomPainter(furnitureItems, selectedItems),
                      size: Size.infinite,
                    ),
                    if (_isSelectingBox &&
                        _selectionStart != null &&
                        _selectionCurrent != null)
                      CustomPaint(
                        painter: MarqueePainter(
                          _selectionStart!,
                          _selectionCurrent!,
                        ),
                        size: Size.infinite,
                      ),
                  ],
                ),
              ),
            ),

            Positioned.fill(
              child: IgnorePointer(
                child: MouseRegion(cursor: SystemMouseCursors.none),
              ),
            ),

            if (showCursorOverlay)
              Positioned(
                left: _hoverScreenPosition!.dx - _cursorSize / 2,
                top: _hoverScreenPosition!.dy - _cursorSize / 2,
                width: _cursorSize,
                height: _cursorSize,
                child: IgnorePointer(
                  child: Image.asset(
                    cursorAsset!,
                    width: _cursorSize,
                    height: _cursorSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomPainter — draws furniture as recognisable 2D shapes, not plain boxes.
// ─────────────────────────────────────────────────────────────────────────────

class RoomPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;

  RoomPainter(this.furnitureItems, this.selectedItems);

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid ────────────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.13)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 20)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    for (double y = 0; y < size.height; y += 20)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

    // ── Furniture ────────────────────────────────────────────────────────────
    for (final item in furnitureItems) {
      canvas.save();
      canvas.translate(
        item.position.dx + item.size.width / 2,
        item.position.dy + item.size.height / 2,
      );
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      switch (item.type) {
        case FurnitureType.chair:
          _drawChair(canvas, item);
          break;
        case FurnitureType.table:
          _drawTable(canvas, item);
          break;
        case FurnitureType.sofa:
          _drawSofa(canvas, item);
          break;
      }

      // ── Selection handles ─────────────────────────────────────────────────
      if (selectedItems.contains(item)) {
        // Selection border
        canvas.drawRect(
          Rect.fromLTWH(-2, -2, item.size.width + 4, item.size.height + 4),
          Paint()
            ..color = Colors.blue.withOpacity(0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        // Rotate handle stem
        canvas.drawLine(
          Offset(item.size.width / 2, 0),
          Offset(item.size.width / 2, -25),
          Paint()
            ..color = Colors.blue.withOpacity(0.5)
            ..strokeWidth = 1.5,
        );
        // Rotate handle circle
        canvas.drawCircle(
          Offset(item.size.width / 2, -25),
          10,
          Paint()..color = Colors.blue,
        );
        canvas.drawCircle(
          Offset(item.size.width / 2, -25),
          10,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        // Resize handle
        canvas.drawCircle(
          Offset(item.size.width, item.size.height),
          10,
          Paint()..color = Colors.red,
        );
        canvas.drawCircle(
          Offset(item.size.width, item.size.height),
          10,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      canvas.restore();
    }
  }

  // ── Chair: seat rectangle + back bar + 4 leg dots ─────────────────────────
  void _drawChair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;

    final seatPaint = Paint()..color = c;
    final darkPaint = Paint()..color = _darken(c, 0.3);
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.15);
    final outlinePaint = Paint()
      ..color = _darken(c, 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Drop shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, w, h),
        const Radius.circular(4),
      ),
      shadowPaint,
    );

    // Back rest (top 22% of height)
    final backH = h * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, backH),
        const Radius.circular(3),
      ),
      darkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, backH),
        const Radius.circular(3),
      ),
      outlinePaint,
    );

    // Seat (remaining 78%)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, backH, w, h - backH),
        const Radius.circular(3),
      ),
      seatPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, backH, w, h - backH),
        const Radius.circular(3),
      ),
      outlinePaint,
    );

    // Seat cushion line
    canvas.drawLine(
      Offset(w * 0.1, backH + (h - backH) * 0.5),
      Offset(w * 0.9, backH + (h - backH) * 0.5),
      Paint()
        ..color = _darken(c, 0.15)
        ..strokeWidth = 1.0,
    );

    // Four legs (small filled circles at corners)
    final legR = w * 0.07;
    final legPaint = Paint()..color = _darken(c, 0.5);
    for (final pos in [
      Offset(w * 0.12, h * 0.85),
      Offset(w * 0.88, h * 0.85),
      Offset(w * 0.12, h * 0.97),
      Offset(w * 0.88, h * 0.97),
    ]) {
      canvas.drawCircle(pos, legR, legPaint);
    }

    // Label
    _drawLabel(canvas, 'CHAIR', w, h, c);
  }

  // ── Table: surface + 4 corner legs + grain lines ─────────────────────────
  void _drawTable(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;

    final topPaint = Paint()..color = c;
    final legPaint = Paint()..color = _darken(c, 0.35);
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.15);
    final outlinePaint = Paint()
      ..color = _darken(c, 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Drop shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w, h),
        const Radius.circular(3),
      ),
      shadowPaint,
    );

    // Leg insets (small rectangles at each corner)
    final legW = w * 0.10;
    final legH = h * 0.14;
    for (final pos in [
      Offset(0, 0),
      Offset(w - legW, 0),
      Offset(0, h - legH),
      Offset(w - legW, h - legH),
    ]) {
      canvas.drawRect(Rect.fromLTWH(pos.dx, pos.dy, legW, legH), legPaint);
    }

    // Table surface
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(legW * 0.3, legH * 0.3, w - legW * 0.6, h - legH * 0.6),
        const Radius.circular(3),
      ),
      topPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(legW * 0.3, legH * 0.3, w - legW * 0.6, h - legH * 0.6),
        const Radius.circular(3),
      ),
      outlinePaint,
    );

    // Wood grain lines
    final grainPaint = Paint()
      ..color = _darken(c, 0.1)
      ..strokeWidth = 0.8;
    for (int i = 1; i < 4; i++) {
      final y = h * 0.2 + (h * 0.6 / 4) * i;
      canvas.drawLine(
        Offset(legW * 0.5, y),
        Offset(w - legW * 0.5, y),
        grainPaint,
      );
    }

    _drawLabel(canvas, 'TABLE', w, h, c);
  }

  // ── Sofa: base + 2 armrests + back rest + 3 cushions ─────────────────────
  void _drawSofa(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;

    final basePaint = Paint()..color = _darken(c, 0.2);
    final seatPaint = Paint()..color = c;
    final armPaint = Paint()..color = _darken(c, 0.3);
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.15);
    final outlinePaint = Paint()
      ..color = _darken(c, 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Drop shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w, h),
        const Radius.circular(5),
      ),
      shadowPaint,
    );

    // Base rectangle (full size)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(5),
      ),
      basePaint,
    );

    // Back rest (top 28%)
    final backH = h * 0.28;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, backH),
        const Radius.circular(5),
      ),
      armPaint,
    );

    // Left armrest
    final armW = w * 0.10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, backH, armW, h - backH),
        const Radius.circular(3),
      ),
      armPaint,
    );

    // Right armrest
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - armW, backH, armW, h - backH),
        const Radius.circular(3),
      ),
      armPaint,
    );

    // Seat area
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(armW, backH, w - armW * 2, h - backH),
        const Radius.circular(3),
      ),
      seatPaint,
    );

    // Three cushion dividers
    final seatW = w - armW * 2;
    final divPaint = Paint()
      ..color = _darken(c, 0.2)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(armW + seatW / 3, backH + 4),
      Offset(armW + seatW / 3, h - 4),
      divPaint,
    );
    canvas.drawLine(
      Offset(armW + seatW * 2 / 3, backH + 4),
      Offset(armW + seatW * 2 / 3, h - 4),
      divPaint,
    );

    // Outer outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(5),
      ),
      outlinePaint,
    );

    _drawLabel(canvas, 'SOFA', w, h, c);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _darken(Color color, double amount) {
    return Color.fromARGB(
      color.alpha,
      (color.red * (1 - amount)).round().clamp(0, 255),
      (color.green * (1 - amount)).round().clamp(0, 255),
      (color.blue * (1 - amount)).round().clamp(0, 255),
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    double w,
    double h,
    Color baseColor,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.75),
          fontSize: (w * 0.13).clamp(8.0, 13.0),
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          shadows: [Shadow(color: Colors.black38, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);

    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// MarqueePainter
// ─────────────────────────────────────────────────────────────────────────────

class MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  MarqueePainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()..color = Colors.blue.withOpacity(0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
