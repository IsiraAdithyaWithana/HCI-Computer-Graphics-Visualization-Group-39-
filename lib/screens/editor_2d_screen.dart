import 'package:flutter/material.dart';
import 'package:furniture_visualizer/widgets/mouse_tool_sidebar.dart';
import '../widgets/room_canvas.dart';
import '../models/furniture_model.dart';
import '3d_preview_screen.dart';

class Editor2DScreen extends StatefulWidget {
  const Editor2DScreen({super.key});

  @override
  State<Editor2DScreen> createState() => _Editor2DScreenState();
}

class _Editor2DScreenState extends State<Editor2DScreen> {
  MouseMode _currentMode = MouseMode.select;
  FurnitureType _selectedType = FurnitureType.chair;

  final GlobalKey<RoomCanvasState> _canvasKey = GlobalKey<RoomCanvasState>();

  void _toggleResizeSnap() {
    _canvasKey.currentState?.toggleResizeSnap();
    setState(() {});
  }

  void _openPreview3D() {
    final items = _canvasKey.currentState?.furnitureItems ?? [];

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some furniture first.')),
      );
      return;
    }

    double maxX = 0, maxY = 0;
    for (final item in items) {
      final right = item.position.dx + item.size.width;
      final bottom = item.position.dy + item.size.height;
      if (right > maxX) maxX = right;
      if (bottom > maxY) maxY = bottom;
    }

    const padding = 80.0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Preview3DScreen(
          furniture: List.from(items),
          roomWidth: maxX + padding,
          roomDepth: maxY + padding,
        ),
      ),
    );
  }

  // Reads the current zoom level from the canvas via the GlobalKey.
  double get _canvasZoom => _canvasKey.currentState?.currentZoom ?? 1.0;

  String get _zoomLabel => '${(_canvasZoom * 100).round()}%';

  void _setZoom(double value) {
    _canvasKey.currentState?.setZoom(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapEnabled = _canvasKey.currentState?.isSnapResizeEnabled ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('2D Room Editor'),
        actions: [
          IconButton(
            icon: Icon(snapEnabled ? Icons.grid_on : Icons.crop_free),
            tooltip: 'Toggle resize snap',
            onPressed: _toggleResizeSnap,
          ),
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'Preview in 3D',
            onPressed: _openPreview3D,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Export to JSON',
            onPressed: () {
              final json = _canvasKey.currentState?.exportToJson();
              debugPrint(json);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Layout exported to console.')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Load from JSON',
            onPressed: () {
              const sampleJson = '''
              [
                {
                  "id": "1", "type": "chair",
                  "x": 100, "y": 100, "width": 60, "height": 60,
                  "color": 4280391411, "rotation": 0
                },
                {
                  "id": "2", "type": "table",
                  "x": 220, "y": 100, "width": 120, "height": 80,
                  "color": 4285290483, "rotation": 0
                },
                {
                  "id": "3", "type": "sofa",
                  "x": 100, "y": 240, "width": 150, "height": 70,
                  "color": 4278222848, "rotation": 0
                }
              ]
              ''';
              _canvasKey.currentState?.loadFromJson(sampleJson);
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Tool mode sidebar
          MouseToolSidebar(
            currentMode: _currentMode,
            onModeChanged: (mode) => setState(() => _currentMode = mode),
          ),

          // Furniture picker
          Container(
            width: 200,
            color: Colors.grey[200],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Furniture',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.chair),
                  title: const Text('Chair'),
                  selected: _selectedType == FurnitureType.chair,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.chair),
                ),
                ListTile(
                  leading: const Icon(Icons.table_restaurant),
                  title: const Text('Table'),
                  selected: _selectedType == FurnitureType.table,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.table),
                ),
                ListTile(
                  leading: const Icon(Icons.weekend),
                  title: const Text('Sofa'),
                  selected: _selectedType == FurnitureType.sofa,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.sofa),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.view_in_ar, size: 18),
                      label: const Text('View 3D'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openPreview3D,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Canvas area — Stack so we can overlay the zoom control
          Expanded(
            child: Stack(
              children: [
                RoomCanvas(
                  key: _canvasKey,
                  selectedType: _selectedType,
                  currentMode: _currentMode,
                ),

                // Zoom control — bottom right of canvas area
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _ZoomControl(
                    zoom: _canvasZoom,
                    min: 0.3,
                    max: 3.0,
                    label: _zoomLabel,
                    onChanged: _setZoom,
                    onReset: () => _setZoom(1.0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared zoom control widget — same used in 3D screen.
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomControl extends StatelessWidget {
  final double zoom;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const _ZoomControl({
    required this.zoom,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconBtn(
            icon: Icons.remove,
            onTap: () => onChanged((zoom - 0.1).clamp(min, max)),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 130,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.indigo,
                inactiveTrackColor: Colors.grey.shade300,
                thumbColor: Colors.indigo,
                overlayColor: Colors.indigo.withOpacity(0.15),
              ),
              child: Slider(
                value: zoom.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _IconBtn(
            icon: Icons.add,
            onTap: () => onChanged((zoom + 0.1).clamp(min, max)),
          ),
          const SizedBox(width: 8),
          // Label — tap to reset to 100%
          GestureDetector(
            onTap: onReset,
            child: Container(
              width: 46,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, color: Colors.grey.shade700, size: 16),
      ),
    );
  }
}
