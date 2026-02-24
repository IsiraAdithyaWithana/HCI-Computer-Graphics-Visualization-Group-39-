import 'package:flutter/material.dart';
import 'package:furniture_visualizer/widgets/mouse_tool_sidebar.dart';
import '../widgets/room_canvas.dart';
import '../models/furniture_model.dart';

class Editor2DScreen extends StatefulWidget {
  const Editor2DScreen({super.key});

  @override
  State<Editor2DScreen> createState() => _Editor2DScreenState();
}

class _Editor2DScreenState extends State<Editor2DScreen> {
  MouseMode _currentMode = MouseMode.select;
  FurnitureType selectedType = FurnitureType.chair;

  // ✅ THIS FIXES THE RED ERROR
  final GlobalKey<RoomCanvasState> canvasKey = GlobalKey<RoomCanvasState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("2D Room Editor"),
        actions: [
          IconButton(
            icon: Icon(
              canvasKey.currentState?.isSnapResizeEnabled ?? true
                  ? Icons.grid_on
                  : Icons.crop_free,
            ),
            tooltip: "Toggle Resize Mode",
            onPressed: () {
              canvasKey.currentState?.toggleResizeMode();
              setState(() {}); // refresh icon
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              final json = canvasKey.currentState?.exportToJson();
              debugPrint(json);
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              // Example load (you can replace with file picker later)
              const sampleJson = '''
              [
                {
                  "id": "1",
                  "type": "chair",
                  "x": 100,
                  "y": 100,
                  "width": 60,
                  "height": 60,
                  "color": 4280391411,
                  "rotation": 0
                }
              ]
              ''';

              canvasKey.currentState?.loadFromJson(sampleJson);
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // 🖱 TOOL SIDEBAR
          MouseToolSidebar(
            currentMode: _currentMode,
            onModeChanged: (mode) {
              setState(() {
                _currentMode = mode;
              });
            },
          ),

          // 🪑 FURNITURE SIDEBAR
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

          // 🎨 CANVAS
          Expanded(
            child: RoomCanvas(
              key: canvasKey,
              selectedType: selectedType,
              currentMode: _currentMode,
            ),
          ),
        ],
      ),
    );
  }
}
