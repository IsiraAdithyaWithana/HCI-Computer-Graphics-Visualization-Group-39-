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

  /// Called whenever the zoom level changes (mouse wheel, pinch, setZoom).
  final void Function(double zoom)? onZoomChanged;

  const RoomCanvas({
    super.key,
    required this.selectedType,
    required this.currentMode,
    this.roomWidthPx = 600,
    this.roomDepthPx = 500,
    this.onZoomChanged,
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

  // Cursor state via ValueNotifier — updating these never repaints furniture.
  final _cursorPos = ValueNotifier<Offset?>(null);
  final _cursorAsset = ValueNotifier<String?>(
    'assets/cursors/canvas_cursor.png',
  );
  bool _isRotatingLive = false;
  bool _isResizingLive = false;
  bool _isDraggingLive = false;

  // Draw-mode: saved on onTapDown, cleared by onPanStart so drag never also creates a point-item
  Offset? _drawTapPos;

  // Trackpad state
  double _trackpadLastScale = 1.0;
  bool _isTrackpadActive = false;
  Offset _trackpadFocal = Offset.zero;

  final double gridSize = 20;
  bool enableSnap = true;
  bool snapResizeEnabled = true;
  static const double _cursorSize = 32;

  // Large virtual canvas
  static const double _canvasW = 5000;
  static const double _canvasH = 4000;

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

  // ── Coordinate helpers ─────────────────────────────────────────────────────
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
      if (_onResize(selectedItem!, scenePos)) {
        _cursorAsset.value = 'assets/cursors/expand_cursor.png';
        return;
      }
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

  // ── Defaults ──────────────────────────────────────────────────────────────
  Size _defaultSize(FurnitureType t) {
    switch (t) {
      case FurnitureType.chair:
        return const Size(60, 60);
      case FurnitureType.table:
        return const Size(120, 80);
      case FurnitureType.sofa:
        return const Size(160, 75);
    }
  }

  Color _defaultColor(FurnitureType t) {
    switch (t) {
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
          _updateCursor(_toScene(event.localPosition), event.localPosition);
        },
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
              // ── Canvas layer (no InteractiveViewer → no boundary clamping) ──
              ColoredBox(
                color: const Color(0xFFBABCC4),
                child: ClipRect(
                  // AnimatedBuilder rebuilds Transform on controller change;
                  // we pass null child so setState also refreshes marquee/items.
                  child: AnimatedBuilder(
                    animation: _transformationController,
                    builder: (context, _) => Transform(
                      transform: _transformationController.value,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final scenePos = _globalToScene(
                            details.globalPosition,
                          );
                          if (widget.currentMode == MouseMode.draw) {
                            _drawTapPos = scenePos;
                            return;
                          }
                          if (widget.currentMode != MouseMode.select) return;
                          if (_onAnyHandle(scenePos)) return;
                          for (final item in furnitureItems.reversed) {
                            if (_inside(item, scenePos)) {
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
                        onTapUp: (details) {
                          if (widget.currentMode == MouseMode.draw &&
                              _drawTapPos != null) {
                            setState(
                              () => furnitureItems.add(
                                _newItem(position: _drawTapPos!),
                              ),
                            );
                            _drawTapPos = null;
                          }
                        },
                        onSecondaryTapDown: (details) {
                          final scenePos = _globalToScene(
                            details.globalPosition,
                          );
                          for (final item in furnitureItems.reversed) {
                            if (_inside(item, scenePos)) {
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
                          if (_isTrackpadActive) return;
                          _drawTapPos = null;
                          if (widget.currentMode == MouseMode.hand) {
                            setState(() => _isPanningCanvas = true);
                            _dragStart = details.globalPosition;
                            return;
                          }
                          final s = _globalToScene(details.globalPosition);
                          if (selectedItem != null &&
                              _onRotate(selectedItem!, s)) {
                            setState(() => _isRotating = true);
                            _isRotatingLive = true;
                            _cursorAsset.value =
                                'assets/cursors/rotate_cursor.png';
                            return;
                          }
                          if (selectedItem != null &&
                              _onResize(selectedItem!, s)) {
                            setState(() => _isResizing = true);
                            _isResizingLive = true;
                            _cursorAsset.value =
                                'assets/cursors/expand_cursor.png';
                            return;
                          }
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
                        onPanUpdate: (details) {
                          if (_isTrackpadActive) return;
                          final s = _globalToScene(details.globalPosition);
                          _cursorPos.value =
                              (context.findRenderObject() as RenderBox?)
                                  ?.globalToLocal(details.globalPosition);
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
                            final l = _localRotated(selectedItem!, s);
                            double w = l.dx.clamp(40.0, 800.0);
                            double h = l.dy.clamp(40.0, 800.0);
                            if (snapResizeEnabled) {
                              w = _snap(w);
                              h = _snap(h);
                            }
                            setState(() => selectedItem!.size = Size(w, h));
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
                            // GestureDetector is inside Transform so delta is
                            // already in scene-space. M.translate(scene_delta)
                            // shifts the canvas by scale*scene_delta screen pixels.
                            _transformationController.value =
                                _transformationController.value.clone()
                                  ..translate(
                                    details.delta.dx,
                                    details.delta.dy,
                                  );
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

              // ── Cursor overlay — only this rebuilds on hover ─────────────
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

  // ── Mouse wheel zoom ───────────────────────────────────────────────────────
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final factor = event.scrollDelta.dy < 0 ? 1.10 : 0.90;
      _zoomAround(factor, event.localPosition);
    }
  }

  // ── Touchpad: two-finger pan + pinch zoom ──────────────────────────────────
  void _onTrackpadStart(PointerPanZoomStartEvent event) {
    _trackpadLastScale = 1.0;
    _isTrackpadActive = true;
    _trackpadFocal = _cursorPos.value ?? event.localPosition;
    _cursorPos.value = null;
    _cursorAsset.value = null;
  }

  void _onTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    // Detect pinch by comparing scale change from last frame
    final bool isZooming = (event.scale - _trackpadLastScale).abs() > 0.001;

    if (isZooming) {
      final delta = event.scale / _trackpadLastScale;
      _trackpadLastScale = event.scale;

      _zoomAroundNoCursor(delta, event.localPosition);
    } else {
      // Only pan if NOT zooming
      if (event.panDelta != Offset.zero) {
        _transformationController.value =
            _transformationController.value.clone()..translate(
              event.panDelta.dx / currentScale,
              event.panDelta.dy / currentScale,
            );
      }
    }

    setState(() {});
  }

  void _onTrackpadEnd(PointerPanZoomEndEvent event) {
    _isTrackpadActive = false;
    _trackpadLastScale = 1.0;
    _trackpadFocal = Offset.zero;
    _cursorAsset.value = 'assets/cursors/canvas_cursor.png';
  }

  void _zoomAround(double factor, Offset screenFocal) {
    _zoomAroundNoCursor(factor, screenFocal);
  }

  /// Zoom keeping [screenFocal] fixed on screen.
  ///
  /// Uses a clean analytic formula — no InteractiveViewer boundary clamping:
  ///   new_translate = (1 - f) * focal + f * old_translate
  /// where f = new_scale / old_scale (after clamping to [0.3, 3.0]).
  void _zoomAroundNoCursor(double factor, Offset screenFocal) {
    final matrix = _transformationController.value;

    final currentScale = matrix.getMaxScaleOnAxis();
    final newScale = (currentScale * factor).clamp(0.05, 5.0);

    if ((newScale - currentScale).abs() < 0.0001) return;

    final scaleFactor = newScale / currentScale;

    final sceneFocal = MatrixUtils.transformPoint(
      Matrix4.inverted(matrix),
      screenFocal,
    );

    final newMatrix = matrix.clone()
      ..translate(sceneFocal.dx, sceneFocal.dy)
      ..scale(scaleFactor)
      ..translate(-sceneFocal.dx, -sceneFocal.dy);

    _transformationController.value = newMatrix;

    widget.onZoomChanged?.call(newScale);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class RoomPainter extends CustomPainter {
  final List<FurnitureModel> furnitureItems;
  final List<FurnitureModel> selectedItems;
  final double roomWidth, roomDepth, canvasW, canvasH;

  const RoomPainter({
    required this.furnitureItems,
    required this.selectedItems,
    required this.roomWidth,
    required this.roomDepth,
    required this.canvasW,
    required this.canvasH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = const Color(0xFFBABCC4),
    );

    final rr = Rect.fromLTWH(0, 0, roomWidth, roomDepth);

    canvas.drawRect(rr, Paint()..color = const Color(0xFFFAF8F5));

    canvas.save();
    canvas.clipRect(rr);
    final gp = Paint()
      ..color = Colors.grey.withOpacity(0.22)
      ..strokeWidth = 1;
    for (double x = 0; x <= roomWidth; x += 20)
      canvas.drawLine(Offset(x, 0), Offset(x, roomDepth), gp);
    for (double y = 0; y <= roomDepth; y += 20)
      canvas.drawLine(Offset(0, y), Offset(roomWidth, y), gp);
    canvas.restore();

    canvas.drawRect(
      rr.inflate(2),
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawRect(
      rr,
      Paint()
        ..color = const Color(0xFF4A4A5A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    final cp = Paint()..color = const Color(0xFF4A4A5A);
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
          _chair(canvas, item);
          break;
        case FurnitureType.table:
          _table(canvas, item);
          break;
        case FurnitureType.sofa:
          _sofa(canvas, item);
          break;
      }
      if (selectedItems.contains(item)) {
        canvas.drawRect(
          Rect.fromLTWH(-2, -2, item.size.width + 4, item.size.height + 4),
          Paint()
            ..color = Colors.blue.withOpacity(.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(item.size.width / 2, 0),
          Offset(item.size.width / 2, -25),
          Paint()
            ..color = Colors.blue.withOpacity(.5)
            ..strokeWidth = 1.5,
        );
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

  void _dimLabel(Canvas canvas, String t, Offset pos, bool rot) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: const TextStyle(
          color: Color(0xFF44445A),
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

  void _chair(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withOpacity(.15),
    );
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
    for (final r in [
      Rect.fromLTWH(0, 0, w, bH),
      Rect.fromLTWH(0, bH, w, h - bH),
    ])
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        Paint()
          ..color = _dk(c, .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(sr, const Radius.circular(3)),
      Paint()
        ..color = _dk(c, .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final gp = Paint()
      ..color = _dk(c, .1)
      ..strokeWidth = .8;
    for (int i = 1; i < 4; i++) {
      final y = h * .2 + (h * .6 / 4) * i;
      canvas.drawLine(Offset(lW * .5, y), Offset(w - lW * .5, y), gp);
    }
    _lbl(canvas, 'TABLE', w, h);
  }

  void _sofa(Canvas canvas, FurnitureModel item) {
    final w = item.size.width;
    final h = item.size.height;
    final c = item.color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w, h),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.black.withOpacity(.15),
    );
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(5),
      ),
      Paint()
        ..color = _dk(c, .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _lbl(canvas, 'SOFA', w, h);
  }

  Color _dk(Color c, double a) => Color.fromARGB(
    c.alpha,
    (c.red * (1 - a)).round().clamp(0, 255),
    (c.green * (1 - a)).round().clamp(0, 255),
    (c.blue * (1 - a)).round().clamp(0, 255),
  );

  void _lbl(Canvas canvas, String text, double w, double h) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withOpacity(.75),
          fontSize: (w * .13).clamp(8.0, 13.0),
          fontWeight: FontWeight.bold,
          letterSpacing: .5,
          shadows: const [Shadow(color: Colors.black38, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));
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
