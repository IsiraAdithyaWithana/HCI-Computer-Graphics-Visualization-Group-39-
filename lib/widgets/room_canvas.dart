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
  

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (event) {
        if (event.isKeyPressed(LogicalKeyboardKey.delete)) {
          if (selectedItem != null) {
            setState(() {
              furnitureItems.remove(selectedItem);
              selectedItem = null;
            });
          }
        }
      },
      child: GestureDetector(

        onPanStart: (details) {
          for (var item in furnitureItems) {
            if (_isInside(item, details.localPosition)) {
              setState(() {
                selectedItem = item;
              });
              break;
            }
          }
        },

        onSecondaryTapDown: (details) {
  if (selectedItem != null) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        0,
        0,
      ),
      items: [
        const PopupMenuItem(
          value: "delete",
          child: Text("Delete"),
        ),
      ],
    ).then((value) {
      if (value == "delete") {
        setState(() {
          furnitureItems.remove(selectedItem);
          selectedItem = null;
        });
      }
    });
  }
},

        onPanUpdate: (details) {
  if (selectedItem != null) {
    final newPosition = selectedItem!.position + details.delta;

    setState(() {
      selectedItem!.position = Offset(
        (newPosition.dx / 20).round() * 20,
        (newPosition.dy / 20).round() * 20,
      );
    });
  }
},


        onTapDown: (details) {
  bool tappedOnItem = false;

  for (var item in furnitureItems) {
    if (_isInside(item, details.localPosition)) {
      setState(() {
        selectedItem = item;
      });
      tappedOnItem = true;
      break;
    }
  }

  if (!tappedOnItem) {
    setState(() {
      selectedItem = null; // deselect previous
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

      paint.color = item.color;

      canvas.drawRect(
        Rect.fromLTWH(
          item.position.dx,
          item.position.dy,
          item.size.width,
          item.size.height,
        ),
        paint,
      );

      // Draw selection border
      if (item == selectedItem) {
        final borderPaint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

        canvas.drawRect(
          Rect.fromLTWH(
            item.position.dx,
            item.position.dy,
            item.size.width,
            item.size.height,
          ),
          borderPaint,
        );
      }
      if (item == selectedItem) {
  final handlePaint = Paint()
    ..color = Colors.red;

  canvas.drawCircle(
    Offset(
      item.position.dx + item.size.width,
      item.position.dy + item.size.height,
    ),
    8,
    handlePaint,
  );
}
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
