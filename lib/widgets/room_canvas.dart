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
  // Canvas content
  List<FurnitureModel> furnitureItems = [];
  List<FurnitureModel> selectedItems = [];
  FurnitureModel? selectedItem;

  // Drag / gesture state
  Offset? _dragStart;
  bool _isRotating = false;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _isPanningCanvas = false;

  // Marquee selection / draw-by-drag state
  bool _isSelectingBox = false;
  Offset? _selectionStart;
  Offset? _selectionCurrent;

  // Screen-space position of the pointer, used to position the PNG overlay.
  Offset? _hoverScreenPosition;
  // Scene-space position of the pointer, used for hit testing.
  Offset? _hoverScenePosition;
  bool _showRotateCursor = false;
  bool _showResizeCursor = false;
  bool _showMoveCursor = false;

  // Settings
  final double gridSize = 20;
  bool enableSnap = true;
  bool snapResizeEnabled = true;

  static const double _cursorSize = 32;

  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();

  // Public API used by parent widgets

  bool get isSnapResizeEnabled => snapResizeEnabled;
  void toggleResizeSnap() =>
      setState(() => snapResizeEnabled = !snapResizeEnabled);

  // Returns the current zoom level (1.0 = 100%).
  double get currentZoom => _transformationController.value.getMaxScaleOnAxis();

  // Sets the zoom level while keeping the canvas centred on the current view.
  void setZoom(double zoom) {
    final current = _transformationController.value;
    final oldScale = current.getMaxScaleOnAxis();
    final ratio = zoom / oldScale;

    // Scale around the centre of the widget.
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

  // Coordinate helpers

  // Converts a widget-local screen position to scene (canvas) space.
  Offset _toScene(Offset screenPos) => MatrixUtils.transformPoint(
    Matrix4.inverted(_transformationController.value),
    screenPos,
  );

  // Converts a global position to widget-local space, then to scene space.
  // Used for all gesture events since globalPosition is always consistent.
  Offset _globalToScene(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox;
    return _toScene(box.globalToLocal(globalPos));
  }

  // Converts a global position to widget-local space for the cursor overlay.
  Offset _globalToLocal(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox;
    return box.globalToLocal(globalPos);
  }

  // Snap helpers

  double _snap(double value) =>
      enableSnap ? (value / gridSize).round() * gridSize : value;

  Offset _snapOffset(Offset o) => Offset(_snap(o.dx), _snap(o.dy));

  // Geometry helpers

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

  // Cursor helpers

  // Decides which PNG to show as the cursor overlay.
  // Returns null when no custom cursor is needed.
  String? get _activeCursorAsset {
    if (_showRotateCursor || _isRotating)
      return 'assets/cursors/rotate_cursor.png';
    if (_showResizeCursor || _isResizing)
      return 'assets/cursors/expand_cursor.png';
    if (_showMoveCursor || _isDragging) return 'assets/cursors/move_cursor.png';
    if (_hoverScreenPosition != null) return 'assets/cursors/canvas_cursor.png';
    return null;
  }

  // Updates which custom cursor flag should be active based on where the pointer is.
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

  // Context menu

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
        PopupMenuItem(value: 'rotate', child: Text('Rotate 90')),
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

  // Furniture defaults

  Size _defaultSize(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return const Size(60, 60);
      case FurnitureType.table:
        return const Size(120, 80);
      case FurnitureType.sofa:
        return const Size(150, 70);
    }
  }

  Color _defaultColor(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return Colors.blueGrey;
      case FurnitureType.table:
        return Colors.brown;
      case FurnitureType.sofa:
        return Colors.green;
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

  // Build

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
                          // Ctrl held: toggle this item in or out of the selection.
                          selectedItems.contains(item)
                              ? selectedItems.remove(item)
                              : selectedItems.add(item);
                          selectedItem = item;
                        } else if (selectedItems.contains(item)) {
                          // Tapping an already-selected item with no Ctrl.
                          // Keep the whole group so dragging moves all of them.
                          selectedItem = item;
                        } else {
                          // Tapping a different unselected item — replace selection.
                          selectedItems
                            ..clear()
                            ..add(item);
                          selectedItem = item;
                        }
                      });
                      return;
                    }
                  }

                  // Tapped empty space — clear everything.
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
                  // Hand mode: InteractiveViewer handles the actual panning.
                  // We just track state so the canvas cursor stays active.
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
                        // If the item is already selected, keep the group.
                        // If it is new, replace the selection.
                        if (!selectedItems.contains(item)) {
                          if (!HardwareKeyboard.instance.isControlPressed) {
                            selectedItems.clear();
                          }
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

                  // Nothing was hit — start a marquee or draw-drag.
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
                  // localPos is computed once and used inside every setState call
                  // so the cursor overlay image follows the pointer every frame.
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
                      for (final item in selectedItems) {
                        item.position += delta;
                      }
                      _hoverScreenPosition = localPos;
                    });
                    _dragStart = scenePos;
                    return;
                  }

                  // Canvas pan: setState is required so the cursor overlay
                  // rebuilds and the PNG image follows the pointer.
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
                  // Draw mode: finalise the dragged rectangle as a new item.
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

                  // Select mode: finalise the marquee and select overlapping items.
                  if (widget.currentMode == MouseMode.select &&
                      _isSelectingBox &&
                      _selectionStart != null &&
                      _selectionCurrent != null) {
                    final rect = Rect.fromPoints(
                      _selectionStart!,
                      _selectionCurrent!,
                    );
                    setState(() {
                      selectedItems = furnitureItems.where((item) {
                        return rect.overlaps(
                          Rect.fromLTWH(
                            item.position.dx,
                            item.position.dy,
                            item.size.width,
                            item.size.height,
                          ),
                        );
                      }).toList();
                      selectedItem = selectedItems.isNotEmpty
                          ? selectedItems.last
                          : null;
                    });
                  }

                  // Snap every selected item to the grid at the end of a drag.
                  // All items must be snapped — not just selectedItem — so that
                  // no single item ends up offset from the others after the drop.
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

            // Full-coverage invisible MouseRegion that keeps the OS cursor hidden
            // even when the pointer is over InteractiveViewer's own internal
            // MouseRegion, which would otherwise override our none setting.
            Positioned.fill(
              child: IgnorePointer(
                child: MouseRegion(cursor: SystemMouseCursors.none),
              ),
            ),

            // The PNG cursor image, centred on the current pointer position.
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

class RoomPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;

  RoomPainter(this.furnitureItems, this.selectedItems);

  @override
  void paint(Canvas canvas, Size size) {
    final itemPaint = Paint();

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final item in furnitureItems) {
      canvas.save();
      canvas.translate(
        item.position.dx + item.size.width / 2,
        item.position.dy + item.size.height / 2,
      );
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      itemPaint.color = item.color;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, item.size.width, item.size.height),
        itemPaint,
      );

      if (selectedItems.contains(item)) {
        // Line connecting the item to the rotate handle
        canvas.drawLine(
          Offset(item.size.width / 2, 0),
          Offset(item.size.width / 2, -25),
          Paint()
            ..color = Colors.blue.withOpacity(0.4)
            ..strokeWidth = 2,
        );
        // Rotate handle
        canvas.drawCircle(
          Offset(item.size.width / 2, -25),
          12,
          Paint()..color = Colors.blue,
        );
        // Resize handle
        canvas.drawCircle(
          Offset(item.size.width, item.size.height),
          12,
          Paint()..color = Colors.red,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  MarqueePainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()..color = Colors.blue.withOpacity(0.15));
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
