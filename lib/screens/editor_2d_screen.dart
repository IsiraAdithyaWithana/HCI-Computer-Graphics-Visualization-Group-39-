import 'package:flutter/material.dart';
import '../widgets/room_canvas.dart';
import '../models/furniture_model.dart';

class Editor2DScreen extends StatefulWidget {
  const Editor2DScreen({super.key});

  @override
  State<Editor2DScreen> createState() => _Editor2DScreenState();
}

class _Editor2DScreenState extends State<Editor2DScreen> {

  FurnitureType selectedType = FurnitureType.chair;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("2D Room Editor")),
      body: Row(
        children: [

          // LEFT PANEL
          Container(
            width: 200,
            color: Colors.grey[200],
            child: Column(
              children: [
                ListTile(
                  title: const Text("Chair"),
                  onTap: () {
                    setState(() {
                      selectedType = FurnitureType.chair;
                    });
                  },
                ),
                ListTile(
                  title: const Text("Table"),
                  onTap: () {
                    setState(() {
                      selectedType = FurnitureType.table;
                    });
                  },
                ),
                ListTile(
                  title: const Text("Sofa"),
                  onTap: () {
                    setState(() {
                      selectedType = FurnitureType.sofa;
                    });
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: RoomCanvas(selectedType: selectedType),
          ),
        ],
      ),
    );
  }
}
