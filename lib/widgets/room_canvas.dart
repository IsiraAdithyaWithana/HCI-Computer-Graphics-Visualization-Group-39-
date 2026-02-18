import 'package:flutter/material.dart';
import 'package:furniture_visualizer/models/furniture_model.dart';

class RoomCanvas extends StatefulWidget {
  const RoomCanvas({super.key});

  @override
  State<RoomCanvas> createState() => _RoomCanvasState();
}

class _RoomCanvasState extends State<RoomCanvas> {

  List<FurnitureModel> furnitureItems = [];
  FurnitureModel? selectedItem;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(

      onPanStart: (details) {
        for (var item in furnitureItems) {
          if (_isInside(item, details.localPosition)) {
            selectedItem = item;
            break;
          }
        }
      },

      onPanUpdate: (details) {
        if (selectedItem != null) {
          setState(() {
            selectedItem!.position += details.delta;
          });
        }
      },

      onPanEnd: (_) {
        selectedItem = null;
      },

      onTapDown: (details) {
        bool tappedOnItem = false;

        for (var item in furnitureItems) {
          if (_isInside(item, details.localPosition)) {
            tappedOnItem = true;
            selectedItem = item;
            break;
          }
        }

        if (!tappedOnItem) {
          setState(() {
            furnitureItems.add(
              FurnitureModel(
                id: DateTime.now().toString(),
                name: "Chair",
                position: details.localPosition,
                size: const Size(80, 80),
                color: Colors.blueGrey,
              ),
            );
          });
        }
      },

      child: CustomPaint(
        painter: RoomPainter(furnitureItems, selectedItem),
        size: Size.infinite,
      ),
    );
  }

  bool _isInside(FurnitureModel item, Offset point) {
    return point.dx >= item.position.dx &&
        point.dx <= item.position.dx + item.size.width &&
        point.dy >= item.position.dy &&
        point.dy <= item.position.dy + item.size.height;
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
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
