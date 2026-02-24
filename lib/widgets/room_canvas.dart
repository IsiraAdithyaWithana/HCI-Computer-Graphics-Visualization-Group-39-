import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
import 'dart:math' as Math;

class RoomCanvas extends StatefulWidget {
  final FurnitureType selectedType;

  const RoomCanvas({super.key, required this.selectedType});

  @override
  State<RoomCanvas> createState() => RoomCanvasState();
}

class RoomCanvasState extends State<RoomCanvas> {
  List<FurnitureModel> furnitureItems = [];
  FurnitureModel? selectedItem;
  final FocusNode _focusNode = FocusNode();
  Offset? _dragStart;
  bool _isResizing = false;
  bool _isDragging = false;
  bool _isRotating = false;
  Offset? _hoverPosition; // scene space — for hit testing
  Offset?
  _hoverScreenPosition; // widget-local screen space — for cursor overlay

  // Which custom cursor to show (only one can be true at a time)
  bool _showRotateCursor = false;
  bool _showResizeCursor = false;
  bool _showMoveCursor = false;

  final double gridSize = 20;
  bool enableSnap = true;
  List<FurnitureModel> selectedItems = [];
  bool _isPanningCanvas = false;
  bool snapResizeEnabled = true;

  static const double _cursorSize = 32;

  final TransformationController _transformationController =
      TransformationController();

  void toggleResizeMode() {
    setState(() {
      snapResizeEnabled = !snapResizeEnabled;
    });
  }

  bool get isSnapResizeEnabled => snapResizeEnabled;

  Offset _toScene(Offset screenPosition) {
    final inverseMatrix = Matrix4.inverted(_transformationController.value);
    return MatrixUtils.transformPoint(inverseMatrix, screenPosition);
  }

  Offset _globalToWidgetLocal(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox;
    return renderBox.globalToLocal(globalPosition);
  }

  String exportToJson() {
    final data = furnitureItems.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  void loadFromJson(String jsonString) {
    final List decoded = jsonDecode(jsonString);
    setState(() {
      furnitureItems = decoded.map((e) => FurnitureModel.fromJson(e)).toList();
      selectedItems.clear();
      selectedItem = null;
    });
  }

  double _snap(double value) {
    if (!enableSnap) return value;
    return (value / gridSize).round() * gridSize;
  }

  Offset _snapOffset(Offset offset) =>
      Offset(_snap(offset.dx), _snap(offset.dy));

  /// Always returns [SystemMouseCursors.none] when any custom PNG cursor
  /// should be visible — including during active drags so the OS cursor
  /// never reappears mid-gesture.
  MouseCursor _getCursor() {
    if (_showRotateCursor || _isRotating) return SystemMouseCursors.none;
    if (_showResizeCursor || _isResizing) return SystemMouseCursors.none;
    if (_showMoveCursor || _isDragging) return SystemMouseCursors.none;
    return SystemMouseCursors.none;
  }

  /// Updates all three hover-cursor flags based on where the pointer is.
  void _updateHoverCursorFlags(Offset scenePos) {
    _showRotateCursor = false;
    _showResizeCursor = false;
    _showMoveCursor = false;

    // 1️⃣ Check handles only for selected item
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

    // 2️⃣ Check if hovering ANY furniture item
    for (var item in furnitureItems.reversed) {
      if (_isInsideRotated(item, scenePos)) {
        _showMoveCursor = true;
        return;
      }
    }

    // 3️⃣ Otherwise nothing special (canvas cursor will show)
  }

  /// Which asset path to use for the overlay, if any.
  String? get _activeCursorAsset {
    if (_showRotateCursor || _isRotating)
      return 'assets/cursors/rotate_cursor.png';
    if (_showResizeCursor || _isResizing)
      return 'assets/cursors/expand_cursor.png';
    if (_showMoveCursor || _isDragging) return 'assets/cursors/move_cursor.png';
    if (_hoverScreenPosition != null) {
      return 'assets/cursors/canvas_cursor.png';
    }
    return null;
  }

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

  void _showContextMenu(Offset globalPosition) async {
    if (selectedItem == null) return;
    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'rotate', child: Text('Rotate 90°')),
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

  bool _isTappingHandle(Offset scenePos) {
    if (selectedItem == null) return false;
    return _isOnRotateHandle(selectedItem!, scenePos) ||
        _isOnResizeHandle(selectedItem!, scenePos);
  }

  @override
  Widget build(BuildContext context) {
    final String? cursorAsset = _activeCursorAsset;
    final bool showOverlay =
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
        cursor: _getCursor(),
        onHover: (event) {
          final scene = _toScene(event.localPosition);
          setState(() {
            _hoverPosition = scene;
            _hoverScreenPosition = event.localPosition;
            _updateHoverCursorFlags(scene);
          });
        },
        onExit: (_) {
          setState(() {
            _hoverPosition = null;
            _hoverScreenPosition = null;
            _showRotateCursor = false;
            _showResizeCursor = false;
            _showMoveCursor = false;
          });
        },
        child: Stack(
          children: [
            // ── Main canvas ─────────────────────────────────────────────
            InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(1000),
              minScale: 0.5,
              maxScale: 3,
              panEnabled: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,

                onTapDown: (details) {
                  final scenePos = details.localPosition;
                  if (_isTappingHandle(scenePos)) return;

                  for (var item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
                      setState(() {
                        if (HardwareKeyboard.instance.isControlPressed) {
                          selectedItems.contains(item)
                              ? selectedItems.remove(item)
                              : selectedItems.add(item);
                        } else {
                          selectedItems.clear();
                          selectedItems.add(item);
                        }
                        selectedItem = item;
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
                  final scenePos = details.localPosition;
                  if (_isTappingHandle(scenePos)) return;

                  final tappedItem = furnitureItems.any(
                    (i) => _isInsideRotated(i, scenePos),
                  );
                  if (!tappedItem) {
                    setState(() {
                      furnitureItems.add(
                        FurnitureModel(
                          id: DateTime.now().toString(),
                          type: widget.selectedType,
                          position: _snapOffset(scenePos),
                          size: _getSize(widget.selectedType),
                          color: _getColor(widget.selectedType),
                        ),
                      );
                    });
                  }
                },

                onSecondaryTapDown: (details) {
                  final scenePos = details.localPosition;
                  for (var item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
                      setState(() {
                        selectedItem = item;
                        if (!selectedItems.contains(item)) {
                          selectedItems.clear();
                          selectedItems.add(item);
                        }
                      });
                      _showContextMenu(details.globalPosition);
                      return;
                    }
                  }
                },

                onPanStart: (details) {
                  final scenePos = details.localPosition;

                  if (selectedItem != null &&
                      _isOnRotateHandle(selectedItem!, scenePos)) {
                    setState(() {
                      _isRotating = true;
                      _isResizing = false;
                      _isDragging = false;
                      _isPanningCanvas = false;
                      // Lock the overlay to rotate PNG for the whole gesture
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
                      _isRotating = false;
                      _isDragging = false;
                      _isPanningCanvas = false;
                      _showResizeCursor = true;
                      _showRotateCursor = false;
                      _showMoveCursor = false;
                    });
                    return;
                  }

                  for (var item in furnitureItems.reversed) {
                    if (_isInsideRotated(item, scenePos)) {
                      setState(() {
                        if (!selectedItems.contains(item)) {
                          if (!HardwareKeyboard.instance.isControlPressed) {
                            selectedItems.clear();
                          }
                          selectedItems.add(item);
                        }

                        selectedItem = item;

                        _isDragging = true;
                        _isRotating = false;
                        _isResizing = false;
                        _isPanningCanvas = false;

                        _showMoveCursor = true;
                        _showRotateCursor = false;
                        _showResizeCursor = false;
                      });

                      _dragStart = scenePos;
                      return;
                    }
                  }

                  setState(() {
                    _isPanningCanvas = true;
                    _isDragging = false;
                    _isRotating = false;
                    _isResizing = false;
                    _showRotateCursor = false;
                    _showResizeCursor = false;
                    _showMoveCursor = false;
                  });
                  _dragStart = details.globalPosition;
                },

                onPanUpdate: (details) {
                  final scenePos = details.localPosition;
                  // Keep overlay tracking the pointer during any drag
                  final widgetLocal = _globalToWidgetLocal(
                    details.globalPosition,
                  );

                  // ── ROTATE ─────────────────────────────────────────────
                  if (_isRotating && selectedItem != null) {
                    final center = Offset(
                      selectedItem!.position.dx + selectedItem!.size.width / 2,
                      selectedItem!.position.dy + selectedItem!.size.height / 2,
                    );
                    final angle =
                        Math.atan2(
                          scenePos.dy - center.dy,
                          scenePos.dx - center.dx,
                        ) +
                        1.5708;
                    setState(() {
                      selectedItem!.rotation = angle;
                      _hoverScreenPosition = widgetLocal;
                    });
                    return;
                  }

                  // ── RESIZE ─────────────────────────────────────────────
                  if (_isResizing && selectedItem != null) {
                    final local = _toLocalRotatedSpace(selectedItem!, scenePos);

                    double newWidth = local.dx.clamp(40, 800);
                    double newHeight = local.dy.clamp(40, 800);

                    if (snapResizeEnabled) {
                      newWidth = _snap(newWidth);
                      newHeight = _snap(newHeight);
                    }

                    setState(() {
                      selectedItem!.size = Size(newWidth, newHeight);
                      _hoverScreenPosition = widgetLocal;
                    });

                    return;
                  }

                  // ── DRAG OBJECT(S) ──────────────────────────────────────
                  if (_isDragging &&
                      selectedItems.isNotEmpty &&
                      _dragStart != null) {
                    final delta = scenePos - _dragStart!;

                    setState(() {
                      for (var item in selectedItems) {
                        item.position += delta;
                      }

                      _hoverScreenPosition = widgetLocal;
                    });

                    _dragStart = scenePos;
                    return;
                  }

                  // ── PAN CANVAS ──────────────────────────────────────────
                  if (_isPanningCanvas && _dragStart != null) {
                    final delta = details.globalPosition - _dragStart!;

                    final matrix = _transformationController.value.clone();
                    matrix.translate(delta.dx, delta.dy);
                    _transformationController.value = matrix;

                    _dragStart = details.globalPosition;

                    // 🔥 IMPORTANT: update cursor overlay position
                    setState(() {
                      _hoverScreenPosition = _globalToWidgetLocal(
                        details.globalPosition,
                      );
                    });
                  }
                },

                onPanEnd: (_) {
                  if (selectedItems.isNotEmpty) {
                    setState(() {
                      for (var item in selectedItems) {
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
                    // Clear all custom cursors — onHover will re-evaluate
                    // them on the next mouse move.
                    _showRotateCursor = false;
                    _showResizeCursor = false;
                    _showMoveCursor = false;
                  });

                  _dragStart = null;
                },

                child: CustomPaint(
                  painter: RoomPainter(furnitureItems, selectedItems),
                  size: Size.infinite,
                ),
              ),
            ),

            // ── Custom cursor overlay ────────────────────────────────────
            // One Positioned widget handles all three cursor images.
            // IgnorePointer ensures the image never swallows mouse events.
            if (showOverlay)
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

  bool _isInsideRotated(FurnitureModel item, Offset point) {
    final local = _toLocalRotatedSpace(item, point);
    return local.dx >= 0 &&
        local.dx <= item.size.width &&
        local.dy >= 0 &&
        local.dy <= item.size.height;
  }

  bool _isOnResizeHandle(FurnitureModel item, Offset point) {
    final local = _toLocalRotatedSpace(item, point);
    return (local - Offset(item.size.width, item.size.height)).distance <= 18;
  }

  bool _isOnRotateHandle(FurnitureModel item, Offset point) {
    final center = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );
    final dist = item.size.height / 2 + 25;
    final handle = Offset(
      center.dx + dist * Math.cos(item.rotation - 1.5708),
      center.dy + dist * Math.sin(item.rotation - 1.5708),
    );
    return (point - handle).distance <= 35;
  }

  Size _getSize(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return const Size(60, 60);
      case FurnitureType.table:
        return const Size(120, 80);
      case FurnitureType.sofa:
        return const Size(150, 70);
    }
  }

  Color _getColor(FurnitureType type) {
    switch (type) {
      case FurnitureType.chair:
        return Colors.blueGrey;
      case FurnitureType.table:
        return Colors.brown;
      case FurnitureType.sofa:
        return Colors.green;
    }
  }
}

class RoomPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;

  RoomPainter(this.furnitureItems, this.selectedItems);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var item in furnitureItems) {
      canvas.save();
      canvas.translate(
        item.position.dx + item.size.width / 2,
        item.position.dy + item.size.height / 2,
      );
      canvas.rotate(item.rotation);
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      paint.color = item.color;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, item.size.width, item.size.height),
        paint,
      );

      if (selectedItems.contains(item)) {
        canvas.drawLine(
          Offset(item.size.width / 2, 0),
          Offset(item.size.width / 2, -25),
          Paint()
            ..color = Colors.blue.withOpacity(0.4)
            ..strokeWidth = 2,
        );
        canvas.drawCircle(
          Offset(item.size.width / 2, -25),
          12,
          Paint()..color = Colors.blue,
        );
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
