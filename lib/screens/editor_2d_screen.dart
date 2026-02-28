import 'package:flutter/material.dart';
import 'package:furniture_visualizer/widgets/mouse_tool_sidebar.dart';
import '../widgets/room_canvas.dart';
import '../models/furniture_model.dart';
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

  double _roomWidthM = 6.0;
  double _roomDepthM = 5.0;
  static const double _minRoomM = 3.0;
  static const double _maxRoomM = 15.0;
  static const double _mPerPx = 100.0;

  double get _roomWidthPx => _roomWidthM * _mPerPx;
  double get _roomDepthPx => _roomDepthM * _mPerPx;

  double _canvasZoom = 1.0;
  String get _zoomLabel => '${(_canvasZoom * 100).round()}%';

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

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _toggleResizeSnap() {
    _canvasKey.currentState?.toggleResizeSnap();
    setState(() {});
  }

  void _onZoomChanged(double zoom) => setState(() => _canvasZoom = zoom);

  void _setZoom(double value) {
    _canvasKey.currentState?.setZoom(value);
    setState(() => _canvasZoom = value);
  }

  @override
  Widget build(BuildContext context) {
    final snapEnabled = _canvasKey.currentState?.isSnapResizeEnabled ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('2D Room Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Realistic 3D View',
            onPressed: _openRealistic3D,
          ),
          IconButton(
            icon: Icon(snapEnabled ? Icons.grid_on : Icons.crop_free),
            tooltip: 'Toggle resize snap',
            onPressed: _toggleResizeSnap,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Export to JSON',
            onPressed: () {
              debugPrint(_canvasKey.currentState?.exportToJson());
              _snack('Layout exported to console.');
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Load from JSON',
            onPressed: () {
              const sampleJson =
                  '[{"id":"1","type":"chair","x":100,"y":100,"width":60,"height":60,"color":4280391411,"rotation":0},'
                  '{"id":"2","type":"table","x":220,"y":100,"width":120,"height":80,"color":4285290483,"rotation":0},'
                  '{"id":"3","type":"sofa","x":100,"y":240,"width":150,"height":70,"color":4278222848,"rotation":0}]';
              _canvasKey.currentState?.loadFromJson(sampleJson);
            },
          ),
        ],
      ),
      body: Row(
        children: [
          MouseToolSidebar(
            currentMode: _currentMode,
            onModeChanged: (mode) => setState(() => _currentMode = mode),
          ),

          // ── Left panel ─────────────────────────────────────────────────────
          SizedBox(
            width: 220,
            child: _LeftPanel(
              selectedType: _selectedType,
              onTypeChanged: (t) => setState(() => _selectedType = t),
              roomWidthM: _roomWidthM,
              roomDepthM: _roomDepthM,
              minRoomM: _minRoomM,
              maxRoomM: _maxRoomM,
              onWidthChanged: (v) => setState(() => _roomWidthM = v),
              onDepthChanged: (v) => setState(() => _roomDepthM = v),
              onRealistic3D: _openRealistic3D,
            ),
          ),

          // ── Canvas ──────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                RoomCanvas(
                  key: _canvasKey,
                  selectedType: _selectedType,
                  currentMode: _currentMode,
                  roomWidthPx: _roomWidthPx,
                  roomDepthPx: _roomDepthPx,
                  onZoomChanged: _onZoomChanged,
                ),
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
// Left panel — scrollable, with categorised furniture + room controls
// ─────────────────────────────────────────────────────────────────────────────

class _LeftPanel extends StatefulWidget {
  final FurnitureType selectedType;
  final ValueChanged<FurnitureType> onTypeChanged;
  final double roomWidthM, roomDepthM, minRoomM, maxRoomM;
  final ValueChanged<double> onWidthChanged, onDepthChanged;
  final VoidCallback onRealistic3D;

  const _LeftPanel({
    required this.selectedType,
    required this.onTypeChanged,
    required this.roomWidthM,
    required this.roomDepthM,
    required this.minRoomM,
    required this.maxRoomM,
    required this.onWidthChanged,
    required this.onDepthChanged,
    required this.onRealistic3D,
  });

  @override
  State<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<_LeftPanel> {
  // Track which category indices are expanded
  final Set<int> _expanded = {0}; // Seating open by default

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.grey[200],
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.chair_alt, size: 15, color: Colors.black54),
                const SizedBox(width: 6),
                const Text(
                  'Furniture',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),

          // ── Category list (scrollable) ──────────────────────────────────────
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Categories
                ...List.generate(kFurnitureCategories.length, (ci) {
                  final cat = kFurnitureCategories[ci];
                  final isOpen = _expanded.contains(ci);
                  // Check if any item in this cat is selected
                  final hasSelected = cat.items.any(
                    (i) => i.type == widget.selectedType,
                  );
                  return _CategorySection(
                    category: cat,
                    isExpanded: isOpen,
                    hasSelectedItem: hasSelected,
                    selectedType: widget.selectedType,
                    onToggle: () => setState(() {
                      isOpen ? _expanded.remove(ci) : _expanded.add(ci);
                    }),
                    onItemTap: widget.onTypeChanged,
                  );
                }),

                const Divider(height: 1, thickness: 1),

                // ── Room Size ──────────────────────────────────────────────────
                Container(
                  color: Colors.grey[200],
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.square_foot,
                        size: 15,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      const Text(
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
                  value: widget.roomWidthM,
                  min: widget.minRoomM,
                  max: widget.maxRoomM,
                  onChanged: widget.onWidthChanged,
                ),
                _RoomSlider(
                  label: 'Depth',
                  value: widget.roomDepthM,
                  min: widget.minRoomM,
                  max: widget.maxRoomM,
                  onChanged: widget.onDepthChanged,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
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
                          '${widget.roomWidthM.toStringAsFixed(1)} m  ×  ${widget.roomDepthM.toStringAsFixed(1)} m',
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

                const Divider(height: 1, thickness: 1),

                // ── Realistic 3D button ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: const Text('Realistic 3D View'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: widget.onRealistic3D,
                    ),
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
// Animated category section with 2-column item grid
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final FurnitureCategory category;
  final bool isExpanded;
  final bool hasSelectedItem;
  final FurnitureType selectedType;
  final VoidCallback onToggle;
  final ValueChanged<FurnitureType> onItemTap;

  const _CategorySection({
    required this.category,
    required this.isExpanded,
    required this.hasSelectedItem,
    required this.selectedType,
    required this.onToggle,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = category.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Category header ──────────────────────────────────────────────────
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isExpanded
                  ? accentColor.withOpacity(0.08)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isExpanded ? accentColor : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                // Category icon with colored background
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(isExpanded ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(category.icon, size: 15, color: accentColor),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    category.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isExpanded
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isExpanded ? accentColor : Colors.black87,
                    ),
                  ),
                ),
                // Item count badge
                if (!isExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: hasSelectedItem
                          ? accentColor.withOpacity(0.15)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${category.items.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: hasSelectedItem ? accentColor : Colors.black54,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Chevron
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: isExpanded ? accentColor : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Animated item grid ───────────────────────────────────────────────
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildGrid(accentColor),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),

        // Thin separator
        const Divider(height: 1, thickness: 1, indent: 0, endIndent: 0),
      ],
    );
  }

  Widget _buildGrid(Color accentColor) {
    return Container(
      color: accentColor.withOpacity(0.04),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 2.2,
        ),
        itemCount: category.items.length,
        itemBuilder: (_, i) {
          final item = category.items[i];
          final isSelected = item.type == selectedType;
          return _FurnitureGridItem(
            item: item,
            isSelected: isSelected,
            accentColor: accentColor,
            onTap: () => onItemTap(item.type),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual grid item tile
// ─────────────────────────────────────────────────────────────────────────────

class _FurnitureGridItem extends StatelessWidget {
  final FurnitureCategoryItem item;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _FurnitureGridItem({
    required this.item,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withOpacity(.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(.04),
                    blurRadius: 2,
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 16,
              color: isSelected ? accentColor : Colors.black54,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? accentColor : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Room dimension slider with tap-to-edit value
// ─────────────────────────────────────────────────────────────────────────────

class _RoomSlider extends StatefulWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  const _RoomSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_RoomSlider> createState() => _RoomSliderState();
}

class _RoomSliderState extends State<_RoomSlider> {
  bool _editing = false;
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _focus = FocusNode()
      ..addListener(() {
        if (!_focus.hasFocus && _editing) _commit();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _ctrl.text = widget.value.toStringAsFixed(1);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    });
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (v != null) widget.onChanged(v.clamp(widget.min, widget.max));
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              _editing
                  ? SizedBox(
                      width: 68,
                      height: 26,
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: Colors.indigo),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(
                              color: Colors.indigo,
                              width: 1.5,
                            ),
                          ),
                          suffix: const Text(
                            ' m',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onSubmitted: (_) => _commit(),
                      ),
                    )
                  : GestureDetector(
                      onTap: _startEditing,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.text,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.indigo.withOpacity(0.35),
                            ),
                            color: Colors.indigo.withOpacity(0.05),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.value.toStringAsFixed(1)} m',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.edit,
                                size: 10,
                                color: Colors.indigo,
                              ),
                            ],
                          ),
                        ),
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
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: ((widget.max - widget.min) * 2).round(),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom control
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomControl extends StatelessWidget {
  final double zoom, min, max;
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
  Widget build(BuildContext context) => GestureDetector(
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
