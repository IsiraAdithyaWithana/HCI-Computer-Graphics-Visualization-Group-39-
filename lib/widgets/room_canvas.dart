import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
import 'dart:math' as Math;

class RoomCanvas extends StatefulWidget {
  final FurnitureType selectedType;

  const RoomCanvas({super.key, required this.selectedType});

  @override
  State<RoomCanvas> createState() => _RoomCanvasState();
}

class _RoomCanvasState extends State<RoomCanvas> {
  List<FurnitureModel> furnitureItems = [];
  FurnitureModel? selectedItem;
  final FocusNode _focusNode = FocusNode();
  Offset? _dragStart;
  Offset? _itemStartPosition;
  bool _isResizing = false;
  bool _isDragging = false;
  Offset? _hoverPosition;
  Size? _resizeStartSize;

  MouseCursor _getCursor() {
    if (selectedItem == null || _hoverPosition == null) {
      return SystemMouseCursors.basic;
    }

    if (_isOnRotateHandle(selectedItem!, _hoverPosition!)) {
      return SystemMouseCursors.click;
    }

    if (_isOnResizeHandle(selectedItem!, _hoverPosition!)) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }

    if (_isInsideRotated(selectedItem!, _hoverPosition!)) {
      return SystemMouseCursors.move;
    }

    return SystemMouseCursors.basic;
  }

  Offset _toLocalRotatedSpace(FurnitureModel item, Offset globalPoint) {
    final center = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );

    final dx = globalPoint.dx - center.dx;
    final dy = globalPoint.dy - center.dy;

    final cosR = Math.cos(-item.rotation);
    final sinR = Math.sin(-item.rotation);

    final localX = dx * cosR - dy * sinR + item.size.width / 2;
    final localY = dx * sinR + dy * cosR + item.size.height / 2;

    return Offset(localX, localY);
  }

  void _showContextMenu(Offset position) async {
    if (selectedItem == null) return;

    final selected = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'rotate', child: Text('Rotate 90°')),
      ],
    );

    if (selected == 'delete') {
      setState(() {
        furnitureItems.removeWhere((item) => item.id == selectedItem!.id);
        selectedItem = null;
      });
    }

    if (selected == 'duplicate') {
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
    }

    if (selected == 'rotate') {
      setState(() {
        selectedItem!.rotation += 1.5708;
      });
    }
  }

  bool _isRotating = false;

  /// Returns true if the tap point is on any interactive handle
  /// (rotate or resize) of the currently selected item.
  bool _isTappingHandle(Offset point) {
    if (selectedItem == null) return false;
    return _isOnRotateHandle(selectedItem!, point) ||
        _isOnResizeHandle(selectedItem!, point);
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.delete) {
          if (selectedItem != null) {
            setState(() {
              furnitureItems.removeWhere((item) => item.id == selectedItem!.id);
              selectedItem = null;
            });
          }
        }
      },
      child: MouseRegion(
        cursor: _getCursor(),
        onHover: (event) {
          setState(() {
            _hoverPosition = event.localPosition;
          });
        },
        child: GestureDetector(
          onTapDown: (details) {
            // ✅ FIX: If the tap is on a handle of the selected item,
            // do NOT deselect — let onPanStart handle the interaction.
            if (_isTappingHandle(details.localPosition)) return;

            for (var item in furnitureItems.reversed) {
              // ✅ FIX: Use rotation-aware hit test instead of _isInside
              if (_isInsideRotated(item, details.localPosition)) {
                setState(() {
                  selectedItem = item;
                });
                return;
              }
            }

            setState(() {
              selectedItem = null;
            });
          },

          onSecondaryTapDown: (details) {
            for (var item in furnitureItems.reversed) {
              if (_isInsideRotated(item, details.localPosition)) {
                setState(() {
                  selectedItem = item;
                });

                _showContextMenu(details.globalPosition);
                return;
              }
            }
          },

          onPanStart: (details) {
            if (selectedItem != null) {
              // ROTATE FIRST
              if (_isOnRotateHandle(selectedItem!, details.localPosition)) {
                _isRotating = true;
                _isResizing = false;
                _isDragging = false;
                return;
              }

              // RESIZE SECOND
              if (_isOnResizeHandle(selectedItem!, details.localPosition)) {
                _isResizing = true;
                _resizeStartSize = selectedItem!.size;
                return;
              }
            }

            // DRAG THIRD
            for (var item in furnitureItems.reversed) {
              if (_isInsideRotated(item, details.localPosition)) {
                setState(() {
                  selectedItem = item;
                });

                _isDragging = true;
                _isResizing = false;
                _isRotating = false;

                _dragStart = details.localPosition;
                _itemStartPosition = item.position;
                return;
              }
            }

            _isDragging = false;
            _isResizing = false;
            _isRotating = false;
          },

          onPanUpdate: (details) {
            if (_isRotating && selectedItem != null) {
              final center = Offset(
                selectedItem!.position.dx + selectedItem!.size.width / 2,
                selectedItem!.position.dy + selectedItem!.size.height / 2,
              );

              final angle =
                  Math.atan2(
                    details.localPosition.dy - center.dy,
                    details.localPosition.dx - center.dx,
                  ) +
                  1.5708;

              setState(() {
                selectedItem!.rotation = angle;
              });
              return;
            }

            if (_isResizing && selectedItem != null) {
              final local = _toLocalRotatedSpace(
                selectedItem!,
                details.localPosition,
              );

              setState(() {
                selectedItem!.size = Size(
                  local.dx.clamp(40, 800),
                  local.dy.clamp(40, 800),
                );
              });

              return;
            }

            if (_isDragging &&
                selectedItem != null &&
                _dragStart != null &&
                _itemStartPosition != null) {
              final delta = details.localPosition - _dragStart!;

              setState(() {
                selectedItem!.position = _itemStartPosition! + delta;
              });
            }
          },

          onPanEnd: (_) {
            _isRotating = false;
            _isDragging = false;
            _isResizing = false;
            _dragStart = null;
            _itemStartPosition = null;
          },

          onTapUp: (details) {
            // ✅ FIX: Don't place new furniture when releasing on a handle
            if (_isTappingHandle(details.localPosition)) return;

            bool tappedOnItem = false;

            for (var item in furnitureItems) {
              // ✅ FIX: Use rotation-aware hit test here too
              if (_isInsideRotated(item, details.localPosition)) {
                tappedOnItem = true;
                break;
              }
            }

            if (!tappedOnItem) {
              setState(() {
                furnitureItems.add(
                  FurnitureModel(
                    id: DateTime.now().toString(),
                    type: widget.selectedType,
                    position: details.localPosition,
                    size: _getSize(widget.selectedType),
                    color: _getColor(widget.selectedType),
                  ),
                );
              });
            }
          },

          child: CustomPaint(
            painter: RoomPainter(furnitureItems, selectedItem),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  bool _isInside(FurnitureModel item, Offset point) {
    return point.dx >= item.position.dx &&
        point.dx <= item.position.dx + item.size.width &&
        point.dy >= item.position.dy &&
        point.dy <= item.position.dy + item.size.height;
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

    final handleCenter = Offset(item.size.width, item.size.height);

    return (local - handleCenter).distance <= 18;
  }

  bool _isOnRotateHandle(FurnitureModel item, Offset point) {
    final center = Offset(
      item.position.dx + item.size.width / 2,
      item.position.dy + item.size.height / 2,
    );

    final double distanceToHandle = (item.size.height / 2) + 25;

    final handleX =
        center.dx + distanceToHandle * Math.cos(item.rotation - 1.5708);
    final handleY =
        center.dy + distanceToHandle * Math.sin(item.rotation - 1.5708);

    final handlePos = Offset(handleX, handleY);

    return (point - handlePos).distance <= 35;
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
  final FurnitureModel? selectedItem;

  RoomPainter(this.furnitureItems, this.selectedItem);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

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

      if (selectedItem != null && item.id == selectedItem!.id) {
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
