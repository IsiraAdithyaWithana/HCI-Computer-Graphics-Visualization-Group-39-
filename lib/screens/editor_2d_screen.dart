import 'package:flutter/material.dart';
import '../widgets/room_canvas.dart';

class Editor2DScreen extends StatelessWidget {
  const Editor2DScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("2D Room Editor"),
      ),
      body: Row(
        children: [
          Container(
            width: 250,
            color: Colors.grey[200],
            child: const Center(
              child: Text("Furniture Panel"),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: const RoomCanvas(),
            ),
          ),
        ],
      ),
    );
  }
}
