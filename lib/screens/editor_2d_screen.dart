import 'package:flutter/material.dart';
import 'package:furniture_visualizer/widgets/mouse_tool_sidebar.dart';
import '../widgets/room_canvas.dart';
import '../models/furniture_model.dart';
import '3d_preview_screen.dart';
import 'realistic_3d_screen.dart';

class Editor2DScreen extends StatefulWidget {
  const Editor2DScreen({super.key});

  @override
  State<Editor2DScreen> createState() => _Editor2DScreenState();
}

class _Editor2DScreenState extends State<Editor2DScreen> {
  MouseMode _currentMode = MouseMode.select;
  FurnitureType _selectedType = FurnitureType.chair;

  final GlobalKey<RoomCanvasState> _canvasKey = GlobalKey<RoomCanvasState>();

  // ── Room dimensions in metres (1 m = 100 canvas pixels) ────────────────
  double _roomWidthM = 6.0; // 6 m default
  double _roomDepthM = 5.0; // 5 m default

  static const double _minRoomM = 3.0;
  static const double _maxRoomM = 15.0;
  // 1 metre == this many canvas pixels
  static const double _mPerPx = 100.0;

  double get _roomWidthPx => _roomWidthM * _mPerPx;
  double get _roomDepthPx => _roomDepthM * _mPerPx;

  // ── 3D launchers ────────────────────────────────────────────────────────

  void _openRealistic3D() {
    final items = _canvasKey.currentState?.furnitureItems ?? [];
    if (items.isEmpty) {
      _snack('Add some furniture first.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Realistic3DScreen(
          furniture: List.from(items),
          roomWidth: _roomWidthPx,
          roomDepth: _roomDepthPx,
        ),
      ),
    );
  }

  void _openPreview3D() {
    final items = _canvasKey.currentState?.furnitureItems ?? [];
    if (items.isEmpty) {
      _snack('Add some furniture first.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Preview3DScreen(
          furniture: List.from(items),
          roomWidth: _roomWidthPx,
          roomDepth: _roomDepthPx,
        ),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Canvas helpers ───────────────────────────────────────────────────────

  void _toggleResizeSnap() {
    _canvasKey.currentState?.toggleResizeSnap();
    setState(() {});
  }

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
              _snack('Layout exported to console.');
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Load from JSON',
            onPressed: () {
              const sampleJson = '''
              [
                {"id":"1","type":"chair","x":100,"y":100,"width":60,"height":60,"color":4280391411,"rotation":0},
                {"id":"2","type":"table","x":220,"y":100,"width":120,"height":80,"color":4285290483,"rotation":0},
                {"id":"3","type":"sofa","x":100,"y":240,"width":150,"height":70,"color":4278222848,"rotation":0}
              ]
              ''';
              _canvasKey.currentState?.loadFromJson(sampleJson);
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // ── Tool mode sidebar ──────────────────────────────────────────────
          MouseToolSidebar(
            currentMode: _currentMode,
            onModeChanged: (mode) => setState(() => _currentMode = mode),
          ),

          // ── Left panel: furniture picker + room size controls ─────────────
          Container(
            width: 210,
            color: Colors.grey[200],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Furniture section ──────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    'Furniture',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                _FurnitureTile(
                  icon: Icons.chair,
                  label: 'Chair',
                  selected: _selectedType == FurnitureType.chair,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.chair),
                ),
                _FurnitureTile(
                  icon: Icons.table_restaurant,
                  label: 'Table',
                  selected: _selectedType == FurnitureType.table,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.table),
                ),
                _FurnitureTile(
                  icon: Icons.weekend,
                  label: 'Sofa',
                  selected: _selectedType == FurnitureType.sofa,
                  onTap: () =>
                      setState(() => _selectedType = FurnitureType.sofa),
                ),

                const Divider(height: 1),

                // ── Room Size section ──────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.square_foot, size: 15, color: Colors.black54),
                      SizedBox(width: 6),
                      Text(
                        'Room Size',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                _RoomSlider(
                  label: 'Width',
                  value: _roomWidthM,
                  min: _minRoomM,
                  max: _maxRoomM,
                  onChanged: (v) => setState(() => _roomWidthM = v),
                ),
                _RoomSlider(
                  label: 'Depth',
                  value: _roomDepthM,
                  min: _minRoomM,
                  max: _maxRoomM,
                  onChanged: (v) => setState(() => _roomDepthM = v),
                ),

                // Dimension display chip
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.indigo.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.straighten,
                          size: 13,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_roomWidthM.toStringAsFixed(1)} m  ×  ${_roomDepthM.toStringAsFixed(1)} m',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1),

                // ── View 3D buttons ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.view_in_ar, size: 17),
                      label: const Text('View 3D'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openPreview3D,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: const Text('Realistic 3D'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openRealistic3D,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Canvas area ────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                RoomCanvas(
                  key: _canvasKey,
                  selectedType: _selectedType,
                  currentMode: _currentMode,
                  roomWidthPx: _roomWidthPx,
                  roomDepthPx: _roomDepthPx,
                ),

                // Zoom control — bottom right
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
// Furniture list tile
// ─────────────────────────────────────────────────────────────────────────────

class _FurnitureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FurnitureTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      selectedTileColor: Colors.indigo.withOpacity(0.1),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Room dimension slider row
// ─────────────────────────────────────────────────────────────────────────────

class _RoomSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _RoomSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                '${value.toStringAsFixed(1)} m',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.indigo,
              inactiveTrackColor: Colors.grey.shade300,
              thumbColor: Colors.indigo,
              overlayColor: Colors.indigo.withOpacity(0.12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 2).round(), // 0.5 m steps
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom control widget
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
        border: Border.all(color: Colors.grey.shade300),
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
