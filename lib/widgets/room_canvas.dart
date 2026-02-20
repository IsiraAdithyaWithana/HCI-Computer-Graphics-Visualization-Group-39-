import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';

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
        selectedItem!.rotation += 1.5708; // 90° in radians
      });
    }
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
      child: GestureDetector(
        onTapDown: (details) {
          for (var item in furnitureItems.reversed) {
            if (_isInside(item, details.localPosition)) {
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
            if (_isInside(item, details.localPosition)) {
              setState(() {
                selectedItem = item;
              });

              _showContextMenu(details.globalPosition);
              return;
            }
          }
        },

        onPanStart: (details) {
          if (selectedItem != null &&
              _isOnResizeHandle(selectedItem!, details.localPosition)) {
            _isResizing = true;
            return;
          }

          for (var item in furnitureItems.reversed) {
            if (_isInside(item, details.localPosition)) {
              setState(() {
                selectedItem = item;
              });

              _isDragging = true;
              _dragStart = details.localPosition;
              _itemStartPosition = item.position;
              return;
            }
          }

          _isDragging = false;
          _isResizing = false;
        },

        onPanUpdate: (details) {
          if (selectedItem == null) return;

          if (_isDragging && _dragStart != null && _itemStartPosition != null) {
            final delta = details.localPosition - _dragStart!;

            setState(() {
              selectedItem!.position = _itemStartPosition! + delta;
            });
          }

          if (_isResizing) {
            setState(() {
              selectedItem!.size = Size(
                (details.localPosition.dx - selectedItem!.position.dx).clamp(
                  40,
                  500,
                ),
                (details.localPosition.dy - selectedItem!.position.dy).clamp(
                  40,
                  500,
                ),
              );
            });
          }
        },

        onPanEnd: (_) {
          if (selectedItem != null) {
            setState(() {
              selectedItem!.position = Offset(
                (selectedItem!.position.dx / 20).round() * 20,
                (selectedItem!.position.dy / 20).round() * 20,
              );

              selectedItem!.size = Size(
                (selectedItem!.size.width / 20).round() * 20,
                (selectedItem!.size.height / 20).round() * 20,
              );
            });
          }

          _isDragging = false;
          _isResizing = false;
          _dragStart = null;
          _itemStartPosition = null;
        },

        onTapUp: (details) {
          bool tappedOnItem = false;

          for (var item in furnitureItems) {
            if (_isInside(item, details.localPosition)) {
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
    );
  }

  bool _isInside(FurnitureModel item, Offset point) {
    return point.dx >= item.position.dx &&
        point.dx <= item.position.dx + item.size.width &&
        point.dy >= item.position.dy &&
        point.dy <= item.position.dy + item.size.height;
  }

  bool _isOnResizeHandle(FurnitureModel item, Offset point) {
    final handleCenter = Offset(
      item.position.dx + item.size.width,
      item.position.dy + item.size.height,
    );

    return (point - handleCenter).distance <= 12;
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

      // Move to center of item
      canvas.translate(
        item.position.dx + item.size.width / 2,
        item.position.dy + item.size.height / 2,
      );

      // Rotate
      canvas.rotate(item.rotation);

      // Move origin back to top-left of rectangle
      canvas.translate(-item.size.width / 2, -item.size.height / 2);

      paint.color = item.color;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, item.size.width, item.size.height),
        paint,
      );

      if (selectedItem != null && item.id == selectedItem!.id) {
        final borderPaint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

        canvas.drawRect(
          Rect.fromLTWH(0, 0, item.size.width, item.size.height),
          borderPaint,
        );

        final handlePaint = Paint()..color = Colors.red;

        canvas.drawCircle(
          Offset(item.size.width, item.size.height),
          8,
          handlePaint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
