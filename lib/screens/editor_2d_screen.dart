import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:furniture_visualizer/widgets/mouse_tool_sidebar.dart';
import '../widgets/room_canvas.dart';
import '../widgets/colour_scheme_picker.dart';
import '../models/furniture_model.dart';
import '../services/custom_furniture_registry.dart';
import 'realistic_3d_screen.dart';
import '../services/layout_persistence_service.dart';
import '../services/thumbnail_cache.dart';
import '../services/thumbnail_generator_service.dart';
import 'dart:ui' as ui;

// ─────────────────────────────────────────────────────────────────────────────
// Editor2DScreen
// ─────────────────────────────────────────────────────────────────────────────

class Editor2DScreen extends StatefulWidget {
  /// The unique ID of the project being edited. Every save/load uses this key.
  final String projectId;

  /// The ID of the logged-in user. Combined with projectId to namespace storage.
  final String userId;

  /// Optional human-readable project name shown in the app bar.
  final String? projectName;

  const Editor2DScreen({
    super.key,
    required this.projectId,
    required this.userId,
    this.projectName,
  });

  @override
  State<Editor2DScreen> createState() => _Editor2DScreenState();
}

class _Editor2DScreenState extends State<Editor2DScreen> {
  MouseMode _currentMode = MouseMode.select;
  FurnitureType _selectedType = FurnitureType.chair;
  String? _selectedCustomId;

  // ── Colour scheme (room surfaces) ─────────────────────────────────────────
  RoomColourScheme _currentScheme = kColourPresets.first;

  // ── Canvas background colour ──────────────────────────────────────────────
  Color _canvasBgColour = const Color(0xFF0D0D11);

  final GlobalKey<RoomCanvasState> _canvasKey = GlobalKey<RoomCanvasState>();

  // Thumbnails for 2D canvas — updated whenever ThumbnailCache notifies
  Map<String, ui.Image> _thumbnails = {};
  // Ceiling layer toggle — when true, ceiling spots are shown/editable
  bool _showCeilingLayer = false;

  // ── Persistent size preferences per furniture type ─────────────────────
  // Survives item deletion and hot reload.
  // Key: FurnitureType.name (built-ins) or glbFileName (custom)
  // Value: {'w': width, 'h': height, 'sf': scaleFactor}
  Map<String, Map<String, double>> _typeSizePrefs = {};
  void _onThumbsUpdated() {
    if (mounted)
      setState(() => _thumbnails = Map.of(ThumbnailCache.instance.images));
  }

  // Live undo/redo state — ValueNotifier so the 3D screen reacts without being rebuilt.
  final ValueNotifier<bool> _undoNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _redoNotifier = ValueNotifier(false);

  void _onUndoStateChanged() {
    _undoNotifier.value = _canvasKey.currentState?.canUndo ?? false;
    _redoNotifier.value = _canvasKey.currentState?.canRedo ?? false;
  }

  @override
  void dispose() {
    ThumbnailCache.instance.removeListener(_onThumbsUpdated);
    _undoNotifier.dispose();
    _redoNotifier.dispose();
    super.dispose();
  }

  /// Called on every hot-reload. ui.Image GPU objects are invalidated by the
  /// engine restart, so we re-decode from the in-memory raw bytes and then
  /// force a setState so the canvas repaints with the fresh images.
  @override
  void reassemble() {
    super.reassemble();
    // Step 1: immediately drop all ui.Image references so the painter
    // falls back to vector art — avoids trying to draw disposed GPU textures.
    setState(() => _thumbnails = {});
    // Step 2: re-decode raw bytes back into fresh ui.Image objects, then repaint.
    ThumbnailCache.instance.reloadImages().then((_) {
      if (mounted)
        setState(() => _thumbnails = Map.of(ThumbnailCache.instance.images));
    });
  }

  double _roomWidthM = 6.0;
  double _roomDepthM = 5.0;
  static const double _minRoomM = 3.0;
  static const double _maxRoomM = 50.0;
  static const double _mPerPx = 100.0;

  double get _roomWidthPx => _roomWidthM * _mPerPx;
  double get _roomDepthPx => _roomDepthM * _mPerPx;

  double _canvasZoom = 1.0;
  String get _zoomLabel => '${(_canvasZoom * 100).round()}%';

  String? get _customGlbOverride {
    if (_selectedType != FurnitureType.custom || _selectedCustomId == null)
      return null;
    try {
      return CustomFurnitureRegistry.instance.entries
          .firstWhere((e) => e.id == _selectedCustomId)
          .glbFileName;
    } catch (_) {
      return null;
    }
  }

  String? get _customLabelOverride {
    if (_selectedType != FurnitureType.custom || _selectedCustomId == null)
      return null;
    try {
      return CustomFurnitureRegistry.instance.entries
          .firstWhere((e) => e.id == _selectedCustomId)
          .name;
    } catch (_) {
      return null;
    }
  }

  Color? get _customColor {
    if (_selectedType != FurnitureType.custom || _selectedCustomId == null)
      return null;
    try {
      return Color(
        CustomFurnitureRegistry.instance.entries
            .firstWhere((e) => e.id == _selectedCustomId)
            .colorValue,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the 2D default footprint size stored in the selected registry entry.
  Size? get _customDefaultSize {
    if (_selectedType != FurnitureType.custom || _selectedCustomId == null)
      return null;
    try {
      final entry = CustomFurnitureRegistry.instance.entries.firstWhere(
        (e) => e.id == _selectedCustomId,
      );
      return Size(entry.defaultWidthPx, entry.defaultHeightPx);
    } catch (_) {
      return null;
    }
  }

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
          wallColour: _currentScheme.wall,
          floorColour: _currentScheme.floor,
          ceilingColour: _currentScheme.ceiling,
          trimColour: _currentScheme.trim,
          canUndoNotifier: _undoNotifier,
          canRedoNotifier: _redoNotifier,
          onUndo: () {
            _canvasKey.currentState?.undo();
            return _canvasKey.currentState?.exportToJson();
          },
          onRedo: () {
            _canvasKey.currentState?.redo();
            return _canvasKey.currentState?.exportToJson();
          },
          onSizeUpdated: (String id, double scaleFactor) {
            final canvasItems = _canvasKey.currentState?.furnitureItems ?? [];
            final idx = canvasItems.indexWhere((f) => f.id == id);
            if (idx == -1) return;

            // Push undo BEFORE mutating so size-save can be undone from 2D
            _canvasKey.currentState?.pushUndoExternal();

            final saved = canvasItems[idx];
            final oldFactor = saved.scaleFactor > 0 ? saved.scaleFactor : 1.0;
            final naturalW = saved.size.width / oldFactor;
            final naturalH = saved.size.height / oldFactor;
            final newW = (naturalW * scaleFactor).clamp(20.0, 1200.0);
            final newH = (naturalH * scaleFactor).clamp(20.0, 1200.0);

            setState(() {
              for (final item in canvasItems) {
                final isSibling = saved.glbOverride != null
                    ? item.glbOverride == saved.glbOverride
                    : item.type == saved.type;
                if (!isSibling) continue;
                item.size = Size(newW, newH);
                item.scaleFactor = scaleFactor;
              }

              // Persist size preference for this type — survives item deletion
              final prefKey = saved.glbOverride != null
                  ? (saved.glbOverride!.split('/').last) // glb filename
                  : saved.type.name; // e.g. "sofa"
              _typeSizePrefs[prefKey] = {
                'w': newW,
                'h': newH,
                'sf': scaleFactor,
              };
            });

            // Save both layout AND type size prefs to disk
            _saveLayout();
            LayoutPersistenceService.instance.saveTypeSizes(
              widget.userId,
              widget.projectId,
              _typeSizePrefs,
            );
          },
          onNaturalSizeDetected: (String id, double widthPx, double depthPx) {
            _canvasKey.currentState?.updateItemNaturalSize(
              id,
              widthPx,
              depthPx,
            );
            final items = _canvasKey.currentState?.furnitureItems ?? [];
            final item = items.where((f) => f.id == id).firstOrNull;
            if (item?.glbOverride != null) {
              final entry = CustomFurnitureRegistry.instance.entries
                  .where((e) => item!.glbOverride!.endsWith(e.glbFileName))
                  .firstOrNull;
              if (entry != null) {
                CustomFurnitureRegistry.instance.updateNaturalSize(
                  entry.id,
                  widthPx,
                  depthPx,
                );
              }
            }
            _saveLayout();
          },
          onTintUpdated: (String id, String? tintHex) {
            final canvasItems = _canvasKey.currentState?.furnitureItems ?? [];
            final idx = canvasItems.indexWhere((f) => f.id == id);
            if (idx != -1) {
              setState(() => canvasItems[idx].tintHex = tintHex);
              _saveLayout();
            }
          },
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

  // ── Canvas background colour picker ───────────────────────────────────────
  static const _bgPresets = [
    Color(0xFF0D0D11), // default near-black
    Color(0xFF111318), // charcoal blue
    Color(0xFF1A1A1A), // dark grey
    Color(0xFF1C1510), // dark warm
    Color(0xFF0D1117), // dark slate
    Color(0xFF17171F), // app surface
    Color(0xFF12100E), // almost black warm
    Color(0xFF0A0F0D), // very dark green
    Color(0xFF2A2A3A), // mid charcoal
    Color(0xFF252534), // elevated surface
    Color(0xFF1E1E2E), // deep purple-grey
    Color(0xFF22222A), // neutral dark
  ];

  Future<void> _pickCanvasBgColour(BuildContext ctx) async {
    final picked = await showDialog<Color>(
      context: ctx,
      builder: (_) => _CanvasBgPickerDialog(initial: _canvasBgColour),
    );
    if (picked != null) {
      setState(() => _canvasBgColour = picked);
      _saveLayout();
    }
  }

  @override
  void initState() {
    super.initState();
    ThumbnailCache.instance.addListener(_onThumbsUpdated);

    // Populate immediately from whatever is already in the cache.
    // loadAll() runs in main() before this widget exists, so notifyListeners()
    // fires with no listeners — we must read the current state ourselves here.
    _thumbnails = Map.of(ThumbnailCache.instance.images);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedLayout();
      // Start silent background thumbnail generation for all built-in GLBs.
      // If already cached from a previous session this returns instantly.
      ThumbnailGeneratorService.instance.generateBuiltinsInBackground(context);
    });
  }

  Future<void> _loadSavedLayout() async {
    final snapshot = await LayoutPersistenceService.instance.load(
      userId: widget.userId,
      projectId: widget.projectId,
    );
    // Load type size preferences (persisted separately from furniture items)
    final sizePrefs = await LayoutPersistenceService.instance.loadTypeSizes(
      widget.userId,
      widget.projectId,
    );
    if (sizePrefs.isNotEmpty) {
      setState(() => _typeSizePrefs = sizePrefs);
    }
    if (snapshot == null) return;
    setState(() {
      _roomWidthM = snapshot.roomWidthM;
      _roomDepthM = snapshot.roomDepthM;
      if (snapshot.colourScheme != null) {
        _currentScheme = snapshot.colourScheme!;
      }
      if (snapshot.canvasBgColour != null) {
        _canvasBgColour = snapshot.canvasBgColour!;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canvasKey.currentState?.loadFromJson(snapshot.furnitureJson);
    });
  }

  Future<void> _saveLayout() async {
    final json = _canvasKey.currentState?.exportToJson();
    if (json == null) return;
    await LayoutPersistenceService.instance.save(
      userId: widget.userId,
      projectId: widget.projectId,
      furnitureJson: json,
      roomWidthM: _roomWidthM,
      roomDepthM: _roomDepthM,
      colourScheme: _currentScheme,
      canvasBgColour: _canvasBgColour,
    );
    // Update project metadata (furniture count + lastModified) in the list
    final count = _canvasKey.currentState?.furnitureItems.length ?? 0;
    final existing = (await LayoutPersistenceService.instance.loadProjects(
      widget.userId,
    )).where((p) => p.id == widget.projectId).firstOrNull;
    if (existing != null) {
      await LayoutPersistenceService.instance.upsertProject(
        widget.userId,
        existing.copyWith(
          furnitureCount: count,
          lastModified: DateTime.now(),
          widthM: _roomWidthM,
          depthM: _roomDepthM,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapEnabled = _canvasKey.currentState?.isSnapResizeEnabled ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? '2D Room Editor'),
        actions: [
          // ── Undo ────────────────────────────────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: _undoNotifier,
            builder: (_, canUndo, __) => Tooltip(
              message: 'Undo (Ctrl+Z)',
              child: IconButton(
                icon: Icon(
                  Icons.undo_rounded,
                  color: canUndo
                      ? const Color(0xFFC9A96E)
                      : const Color(0xFF4A4A6A),
                ),
                onPressed: canUndo
                    ? () => _canvasKey.currentState?.undo()
                    : null,
              ),
            ),
          ),
          // ── Redo ────────────────────────────────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: _redoNotifier,
            builder: (_, canRedo, __) => Tooltip(
              message: 'Redo (Ctrl+Shift+Z)',
              child: IconButton(
                icon: Icon(
                  Icons.redo_rounded,
                  color: canRedo
                      ? const Color(0xFFC9A96E)
                      : const Color(0xFF4A4A6A),
                ),
                onPressed: canRedo
                    ? () => _canvasKey.currentState?.redo()
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ── Room colour scheme picker ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: ColourSchemeButton(
              current: _currentScheme,
              onSchemeChanged: (s) {
                setState(() => _currentScheme = s);
                _saveLayout();
              },
            ),
          ),
          // ── Canvas background colour picker ────────────────────────────
          Tooltip(
            message: 'Canvas background colour',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickCanvasBgColour(context),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F2B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C2C3E)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _canvasBgColour,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF8E8A9A),
                          width: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.format_paint_outlined,
                      size: 16,
                      color: Color(0xFF8E8A9A),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        ],
      ),
      body: Row(
        children: [
          MouseToolSidebar(
            currentMode: _currentMode,
            onModeChanged: (mode) => setState(() => _currentMode = mode),
          ),
          SizedBox(
            width: 220,
            child: _LeftPanel(
              selectedType: _selectedType,
              selectedCustomId: _selectedCustomId,
              onTypeChanged: (t) => setState(() {
                _selectedType = t;
                _selectedCustomId = null;
                _currentMode = MouseMode.draw;
              }),
              onCustomItemSelected: (id) => setState(() {
                _selectedType = FurnitureType.custom;
                _selectedCustomId = id;
                _currentMode = MouseMode.draw;
              }),
              roomWidthM: _roomWidthM,
              roomDepthM: _roomDepthM,
              minRoomM: _minRoomM,
              maxRoomM: _maxRoomM,
              onWidthChanged: (v) {
                setState(() => _roomWidthM = v);
                _saveLayout();
              },
              onDepthChanged: (v) {
                setState(() => _roomDepthM = v);
                _saveLayout();
              },
              onRealistic3D: _openRealistic3D,
              showCeilingLayer: _showCeilingLayer,
              onCeilingLayerToggle: () =>
                  setState(() => _showCeilingLayer = !_showCeilingLayer),
            ),
          ),
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
                  customGlbOverride: _customGlbOverride,
                  customLabelOverride: _customLabelOverride,
                  customColor: _customColor,
                  customDefaultSize: _customDefaultSize,
                  onChanged: _saveLayout,
                  onUndoStateChanged: _onUndoStateChanged,
                  canvasBgColour: _canvasBgColour,
                  roomFloorColour: _currentScheme.floor,
                  roomWallColour: _currentScheme.wall,
                  thumbnails: _thumbnails,
                  showCeilingLayer: _showCeilingLayer,
                  ceilingColour: _currentScheme.ceiling,
                  typeSizePrefs: _typeSizePrefs,
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _ZoomControl(
                    zoom: _canvasZoom,
                    min: 0.05,
                    max: 5.0,
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
// _LeftPanel
// ─────────────────────────────────────────────────────────────────────────────

class _LeftPanel extends StatefulWidget {
  final FurnitureType selectedType;
  final String? selectedCustomId;
  final ValueChanged<FurnitureType> onTypeChanged;
  final ValueChanged<String> onCustomItemSelected;
  final double roomWidthM, roomDepthM, minRoomM, maxRoomM;
  final ValueChanged<double> onWidthChanged, onDepthChanged;
  final VoidCallback onRealistic3D;
  final bool showCeilingLayer;
  final VoidCallback onCeilingLayerToggle;

  const _LeftPanel({
    required this.selectedType,
    required this.selectedCustomId,
    required this.onTypeChanged,
    required this.onCustomItemSelected,
    required this.roomWidthM,
    required this.roomDepthM,
    required this.minRoomM,
    required this.maxRoomM,
    required this.onWidthChanged,
    required this.onDepthChanged,
    required this.onRealistic3D,
    required this.showCeilingLayer,
    required this.onCeilingLayerToggle,
  });

  @override
  State<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<_LeftPanel> {
  final Set<int> _expanded = {0};
  final Set<String> _customExpanded = {};

  void _openAddDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddFurnitureDialog(onAdded: () => setState(() {})),
    );
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'Delete furniture?',
            style: TextStyle(fontSize: 15),
          ),
          content: Text(
            'Remove "$name" from the library?\nThis also deletes its .glb file.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    // Built-in category names (lower-cased) for merge comparison
    final builtinNames = kFurnitureCategories
        .map((c) => c.name.toLowerCase())
        .toSet();

    return Container(
      color: const Color(0xFF17171F),
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            color: const Color(0xFF1F1F2B),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.chair_alt,
                  size: 15,
                  color: const Color(0xFF8E8A9A),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Furniture',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Add custom furniture',
                  child: InkWell(
                    onTap: _openAddDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC9A96E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFC9A96E).withOpacity(0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 16,
                        color: const Color(0xFFC9A96E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // Category list
          Expanded(
            child: ListenableBuilder(
              listenable: CustomFurnitureRegistry.instance,
              builder: (context, _) {
                final allCustom = CustomFurnitureRegistry.instance.entries;
                // Custom categories that are NOT built-in names get their own section
                final newCatNames = CustomFurnitureRegistry
                    .instance
                    .allCategoryNames
                    .where((n) => !builtinNames.contains(n.toLowerCase()))
                    .toList();

                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Built-in categories — custom entries with matching name merged in
                    ...List.generate(kFurnitureCategories.length, (ci) {
                      final cat = kFurnitureCategories[ci];
                      final isOpen = _expanded.contains(ci);
                      final extras = allCustom
                          .where(
                            (e) =>
                                e.category.toLowerCase() ==
                                cat.name.toLowerCase(),
                          )
                          .toList();
                      final hasSelected =
                          cat.items.any((i) => i.type == widget.selectedType) ||
                          (widget.selectedType == FurnitureType.custom &&
                              extras.any(
                                (e) => e.id == widget.selectedCustomId,
                              ));
                      return _CategorySection(
                        category: cat,
                        isExpanded: isOpen,
                        hasSelectedItem: hasSelected,
                        selectedType: widget.selectedType,
                        selectedCustomId: widget.selectedCustomId,
                        extraEntries: extras,
                        onToggle: () => setState(
                          () =>
                              isOpen ? _expanded.remove(ci) : _expanded.add(ci),
                        ),
                        onItemTap: widget.onTypeChanged,
                        onCustomItemTap: widget.onCustomItemSelected,
                        onDeleteCustom: (id, name) async {
                          if (await _confirmDelete(name))
                            await CustomFurnitureRegistry.instance.removeEntry(
                              id,
                            );
                        },
                      );
                    }),

                    // Truly new categories
                    ...newCatNames.map((catName) {
                      final entries = CustomFurnitureRegistry.instance
                          .entriesForCategory(catName);
                      final isOpen = _customExpanded.contains(catName);
                      final hasSelected =
                          widget.selectedType == FurnitureType.custom &&
                          entries.any((e) => e.id == widget.selectedCustomId);
                      return _CustomCategorySection(
                        categoryName: catName,
                        entries: entries,
                        isExpanded: isOpen,
                        hasSelectedItem: hasSelected,
                        selectedCustomId: widget.selectedCustomId,
                        onToggle: () => setState(
                          () => isOpen
                              ? _customExpanded.remove(catName)
                              : _customExpanded.add(catName),
                        ),
                        onItemTap: widget.onCustomItemSelected,
                        onDelete: (id, name) async {
                          if (await _confirmDelete(name))
                            await CustomFurnitureRegistry.instance.removeEntry(
                              id,
                            );
                        },
                      );
                    }),

                    const Divider(height: 1, thickness: 1),

                    // Room size section
                    Container(
                      color: const Color(0xFF1F1F2B),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.square_foot,
                            size: 15,
                            color: const Color(0xFF8E8A9A),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Room Size',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFFF0EDE8),
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
                          color: const Color(0xFFC9A96E).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFC9A96E).withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.straighten,
                              size: 13,
                              color: const Color(0xFFC9A96E),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.roomWidthM.toStringAsFixed(1)} m  ×  ${widget.roomDepthM.toStringAsFixed(1)} m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFC9A96E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(height: 1, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(
                            widget.showCeilingLayer
                                ? Icons.layers_clear
                                : Icons.layers,
                            size: 16,
                          ),
                          label: Text(
                            widget.showCeilingLayer
                                ? 'Hide Ceiling Layer'
                                : 'Show Ceiling Layer',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: widget.showCeilingLayer
                                ? const Color(0xFFFFB300)
                                : const Color(0xFF9E9E9E),
                            side: BorderSide(
                              color: widget.showCeilingLayer
                                  ? const Color(0xFFFFB300)
                                  : const Color(0xFF555555),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: widget.onCeilingLayerToggle,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 17),
                          label: const Text('Realistic 3D View'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC9A96E),
                            foregroundColor: const Color(0xFF0D0D11),
                          ),
                          onPressed: widget.onRealistic3D,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategorySection — built-in + merged custom extras
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final FurnitureCategory category;
  final bool isExpanded, hasSelectedItem;
  final FurnitureType selectedType;
  final String? selectedCustomId;
  final List<CustomFurnitureEntry> extraEntries;
  final VoidCallback onToggle;
  final ValueChanged<FurnitureType> onItemTap;
  final ValueChanged<String> onCustomItemTap;

  /// id, name
  final void Function(String id, String name) onDeleteCustom;

  const _CategorySection({
    required this.category,
    required this.isExpanded,
    required this.hasSelectedItem,
    required this.selectedType,
    required this.onToggle,
    required this.onItemTap,
    required this.onCustomItemTap,
    required this.onDeleteCustom,
    this.selectedCustomId,
    this.extraEntries = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = category.color;
    final total = category.items.length + extraEntries.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isExpanded ? accent.withOpacity(0.08) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isExpanded ? accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(isExpanded ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(category.icon, size: 15, color: accent),
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
                      color: isExpanded ? accent : const Color(0xFFF0EDE8),
                    ),
                  ),
                ),
                if (!isExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: hasSelectedItem
                          ? accent.withOpacity(0.15)
                          : const Color(0xFF1F1F2B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: hasSelectedItem
                            ? accent
                            : const Color(0xFF8E8A9A),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: isExpanded ? accent : const Color(0xFF56535F),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildGrid(accent),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }

  // Zone hint for lighting items
  String? _lightZoneHint(FurnitureType t) {
    switch (t) {
      case FurnitureType.floorLampLight:
        return '📍 Floor only';
      case FurnitureType.tableLampLight:
        return '🪑 On furniture';
      case FurnitureType.wallLight:
        return '🧱 Wall only';
      case FurnitureType.ceilingSpot:
        return '⬆ Ceiling layer';
      case FurnitureType.windowLight:
        return '🧱 Wall only';
      default:
        return null;
    }
  }

  Widget _buildGrid(Color accent) {
    final total = category.items.length + extraEntries.length;
    return Container(
      color: accent.withOpacity(0.04),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          // Lighting category items are slightly taller to show zone hint
          childAspectRatio: category.name == 'Lighting' ? 1.7 : 2.2,
        ),
        itemCount: total,
        itemBuilder: (_, i) {
          if (i < category.items.length) {
            final item = category.items[i];
            final isSel = item.type == selectedType;
            final zoneHint = _lightZoneHint(item.type);
            return GestureDetector(
              onTap: () => onItemTap(item.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSel
                      ? accent.withOpacity(0.15)
                      : const Color(0xFF1F1F2B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel ? accent : const Color(0xFF2C2C3E),
                    width: isSel ? 1.5 : 1,
                  ),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(.2),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 14,
                          color: isSel ? accent : const Color(0xFF8E8A9A),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSel ? accent : const Color(0xFFF0EDE8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (zoneHint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        zoneHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          color: isSel
                              ? accent.withOpacity(0.85)
                              : const Color(0xFF6E6A7A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          final entry = extraEntries[i - category.items.length];
          return _CustomItemTile(
            entry: entry,
            isSelected: entry.id == selectedCustomId,
            accentColor: accent,
            onTap: () => onCustomItemTap(entry.id),
            onDelete: () => onDeleteCustom(entry.id, entry.name),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomCategorySection — user-created category names not in built-ins
// ─────────────────────────────────────────────────────────────────────────────

class _CustomCategorySection extends StatelessWidget {
  final String categoryName;
  final List<CustomFurnitureEntry> entries;
  final bool isExpanded, hasSelectedItem;
  final String? selectedCustomId;
  final VoidCallback onToggle;
  final ValueChanged<String> onItemTap;
  final void Function(String id, String name) onDelete;

  static const Color _accent = const Color(0xFFC9A96E);

  const _CustomCategorySection({
    required this.categoryName,
    required this.entries,
    required this.isExpanded,
    required this.hasSelectedItem,
    required this.selectedCustomId,
    required this.onToggle,
    required this.onItemTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isExpanded
                  ? _accent.withOpacity(0.08)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isExpanded ? _accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(isExpanded ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    categoryName,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isExpanded
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isExpanded ? _accent : const Color(0xFFF0EDE8),
                    ),
                  ),
                ),
                if (!isExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: hasSelectedItem
                          ? _accent.withOpacity(0.15)
                          : const Color(0xFF1F1F2B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${entries.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: hasSelectedItem
                            ? _accent
                            : const Color(0xFF8E8A9A),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: isExpanded ? _accent : const Color(0xFF56535F),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildGrid(),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }

  Widget _buildGrid() => Container(
    color: _accent.withOpacity(0.04),
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
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        return _CustomItemTile(
          entry: entry,
          isSelected: entry.id == selectedCustomId,
          accentColor: _accent,
          onTap: () => onItemTap(entry.id),
          onDelete: () => onDelete(entry.id, entry.name),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomItemTile — tile with trash button
// ─────────────────────────────────────────────────────────────────────────────

class _CustomItemTile extends StatelessWidget {
  final CustomFurnitureEntry entry;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CustomItemTile({
    required this.entry,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.15)
              : const Color(0xFF1F1F2B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF2C2C3E),
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
          children: [
            const SizedBox(width: 7),
            Icon(
              Icons.view_in_ar,
              size: 13,
              color: isSelected ? accentColor : const Color(0xFF56535F),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? accentColor : const Color(0xFFF0EDE8),
                ),
              ),
            ),
            // Trash button
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Tooltip(
                message: 'Delete "${entry.name}"',
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    size: 13,
                    color: const Color(0xFFE05252),
                  ),
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
// _AddFurnitureDialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddFurnitureDialog extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddFurnitureDialog({required this.onAdded});
  @override
  State<_AddFurnitureDialog> createState() => _AddFurnitureDialogState();
}

class _AddFurnitureDialogState extends State<_AddFurnitureDialog> {
  String? _pickedFilePath, _pickedFileName;
  final _nameCtrl = TextEditingController();
  final _newCatCtrl = TextEditingController();
  final _widthCtrl = TextEditingController(text: '80');
  final _heightCtrl = TextEditingController(text: '80');
  bool _createNewCategory = false;
  String? _selectedBuiltinCategory;
  bool _isAdding = false;
  bool _generatingThumbnail = false;
  String? _statusMessage;
  String? _errorMsg;

  final List<String> _builtinCategories = kFurnitureCategories
      .map((c) => c.name)
      .where((name) => name != 'Lighting')
      .toList();
  static const _accent = const Color(0xFFC9A96E);
  static const _accentLight = Color(0xFF252534);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newCatCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb'],
      dialogTitle: 'Select a .glb 3D model file',
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFilePath = result.files.single.path;
        _pickedFileName = result.files.single.name;
        _errorMsg = null;
      });
    }
  }

  Future<void> _handleAdd() async {
    setState(() => _errorMsg = null);
    if (_pickedFilePath == null) {
      setState(() => _errorMsg = 'Please choose a .glb file.');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'Please enter a furniture name.');
      return;
    }

    final String category;
    final bool isNewCat;
    if (_createNewCategory) {
      final nc = _newCatCtrl.text.trim();
      if (nc.isEmpty) {
        setState(() => _errorMsg = 'Please enter a category name.');
        return;
      }
      category = nc;
      isNewCat = true;
    } else {
      if (_selectedBuiltinCategory == null) {
        setState(() => _errorMsg = 'Please select a category.');
        return;
      }
      category = _selectedBuiltinCategory!;
      isNewCat = false;
    }

    setState(() {
      _isAdding = true;
      _statusMessage = 'Importing model…';
    });
    try {
      final entry = await CustomFurnitureRegistry.instance.addEntry(
        name: name,
        category: category,
        sourceGlbPath: _pickedFilePath!,
        isCustomCategory: isNewCat,
        defaultWidthPx: double.tryParse(_widthCtrl.text.trim()) ?? 80,
        defaultHeightPx: double.tryParse(_heightCtrl.text.trim()) ?? 80,
      );
      widget.onAdded();

      // ── Generate top-down thumbnail in background ────────────────────────
      // Keep dialog open with a spinner while Three.js renders the top-down view.
      if (mounted) {
        setState(() {
          _generatingThumbnail = true;
          _statusMessage = 'Generating 3D preview…';
        });
        await ThumbnailGeneratorService.instance.generateForGlb(
          context,
          entry.glbFileName,
          entry.glbFileName,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted)
        setState(() {
          _errorMsg = 'Failed to add: $e';
          _isAdding = false;
          _generatingThumbnail = false;
          _statusMessage = null;
        });
    }
  }

  IconData _catIcon(String n) {
    switch (n) {
      case 'Seating':
        return Icons.chair;
      case 'Tables':
        return Icons.table_restaurant;
      case 'Storage':
        return Icons.door_sliding;
      case 'Bedroom':
        return Icons.bed;
      case 'Decor':
        return Icons.local_florist;
      default:
        return Icons.folder;
    }
  }

  Color _catColor(String n) {
    switch (n) {
      case 'Seating':
        return const Color(0xFF7C5CBF);
      case 'Tables':
        return const Color(0xFF1976D2);
      case 'Storage':
        return const Color(0xFF388E3C);
      case 'Bedroom':
        return const Color(0xFFE64A19);
      case 'Decor':
        return const Color(0xFF00796B);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF17171F),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1F1F2B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFF2C2C3E))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_box_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add Custom Furniture',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File picker
                  _SectionLabel(
                    icon: Icons.view_in_ar_outlined,
                    label: '3D Model File',
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _isAdding ? null : _pickFile,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _pickedFileName != null
                            ? const Color(0xFF252534)
                            : const Color(0xFF17171F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _pickedFileName != null
                              ? _accent.withOpacity(0.45)
                              : const Color(0xFF2C2C3E),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            _pickedFileName != null
                                ? Icons.check_circle_outline
                                : Icons.upload_file,
                            size: 20,
                            color: _pickedFileName != null
                                ? _accent
                                : const Color(0xFF8E8A9A),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pickedFileName ?? 'Choose a .glb file…',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: _pickedFileName != null
                                    ? _accent
                                    : const Color(0xFF8E8A9A),
                                fontWeight: _pickedFileName != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              'Browse',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                  _SectionLabel(
                    icon: Icons.drive_file_rename_outline,
                    label: 'Furniture Name',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_isAdding,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Barcelona Chair',
                      hintStyle: TextStyle(
                        color: const Color(0xFF56535F),
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF17171F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: const Color(0xFF2C2C3E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: const Color(0xFF2C2C3E)),
                      ),
                    ),
                  ),

                  // ── 2D footprint size ───────────────────────────────────
                  const SizedBox(height: 18),
                  _SectionLabel(
                    icon: Icons.straighten_outlined,
                    label: '2D Size (px)  —  100 px ≈ 1 metre',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sets how large the tile appears on the 2D canvas. '
                    'You can also rescale later via the 3D view.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF56535F)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SizeField(
                          label: 'Width',
                          controller: _widthCtrl,
                          enabled: !_isAdding,
                          accent: _accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SizeField(
                          label: 'Height / Depth',
                          controller: _heightCtrl,
                          enabled: !_isAdding,
                          accent: _accent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  _SectionLabel(
                    icon: Icons.category_outlined,
                    label: 'Category',
                  ),
                  const SizedBox(height: 10),

                  // New category checkbox
                  GestureDetector(
                    onTap: _isAdding
                        ? null
                        : () => setState(
                            () => _createNewCategory = !_createNewCategory,
                          ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: _createNewCategory
                                ? _accent
                                : const Color(0xFF1F1F2B),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: _createNewCategory
                                  ? _accent
                                  : const Color(0xFF56535F),
                              width: 1.5,
                            ),
                          ),
                          child: _createNewCategory
                              ? const Icon(
                                  Icons.check,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Create new category',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFF0EDE8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _createNewCategory ? 1.0 : 0.38,
                    child: TextField(
                      controller: _newCatCtrl,
                      enabled: _createNewCategory && !_isAdding,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'New category name…',
                        hintStyle: TextStyle(
                          color: const Color(0xFF56535F),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.create_new_folder_outlined,
                          size: 18,
                          color: _createNewCategory
                              ? _accent
                              : const Color(0xFF56535F),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: _createNewCategory
                            ? const Color(0xFF252534)
                            : const Color(0xFF17171F),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: const Color(0xFF2C2C3E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _accent,
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _accent.withOpacity(0.4),
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: const Color(0xFF1F1F2B),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Dropdown
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _createNewCategory ? 0.38 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: IgnorePointer(
                        ignoring: _createNewCategory || _isAdding,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _createNewCategory
                                ? const Color(0xFF17171F)
                                : const Color(0xFF17171F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _createNewCategory
                                  ? const Color(0xFF1F1F2B)
                                  : const Color(0xFF2C2C3E),
                              width: 1.5,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedBuiltinCategory,
                              hint: Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 17,
                                    color: const Color(0xFF8E8A9A),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Select existing category…',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: const Color(0xFF8E8A9A),
                                    ),
                                  ),
                                ],
                              ),
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                color: const Color(0xFF8E8A9A),
                                size: 20,
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: const Color(0xFFF0EDE8),
                              ),
                              onChanged: (val) => setState(
                                () => _selectedBuiltinCategory = val,
                              ),
                              items: _builtinCategories
                                  .map(
                                    (cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Row(
                                        children: [
                                          Icon(
                                            _catIcon(cat),
                                            size: 16,
                                            color: _catColor(cat),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(cat),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (_errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1515),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF5A2020)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 15,
                            color: const Color(0xFFE05252),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMsg!,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFFFF7070),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 24),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  // ── Status message shown during thumbnail generation ──────
                  if (_generatingThumbnail)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFC9A96E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _statusMessage ?? 'Generating 3D preview…',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFC9A96E),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isAdding
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(color: const Color(0xFF2C2C3E)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8E8A9A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isAdding ? null : _handleAdd,
                          icon: _isAdding
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add, size: 17),
                          label: Text(
                            _generatingThumbnail
                                ? 'Generating preview…'
                                : (_isAdding ? 'Importing…' : 'Add Furniture'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionLabel
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: const Color(0xFFC9A96E)),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF0EDE8),
          letterSpacing: 0.3,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoomSlider
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                color: const Color(0xFF8E8A9A),
              ),
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
                        color: const Color(0xFFC9A96E),
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: const Color(0xFFC9A96E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: const Color(0xFFC9A96E),
                            width: 1.5,
                          ),
                        ),
                        suffix: const Text(
                          ' m',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF56535F),
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
                            color: const Color(0xFFC9A96E).withOpacity(0.35),
                          ),
                          color: const Color(0xFFC9A96E).withOpacity(0.05),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.value.toStringAsFixed(1)} m',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFC9A96E),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.edit,
                              size: 10,
                              color: const Color(0xFFC9A96E),
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
            activeTrackColor: const Color(0xFFC9A96E),
            inactiveTrackColor: const Color(0xFF2C2C3E),
            thumbColor: const Color(0xFFC9A96E),
            overlayColor: const Color(0xFFC9A96E).withOpacity(0.12),
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

// ─────────────────────────────────────────────────────────────────────────────
// _ZoomControl
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF17171F),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF2C2C3E)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
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
              activeTrackColor: const Color(0xFFC9A96E),
              inactiveTrackColor: const Color(0xFF2C2C3E),
              thumbColor: const Color(0xFFC9A96E),
              overlayColor: const Color(0xFFC9A96E).withOpacity(0.15),
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
              color: const Color(0xFF17171F),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF2C2C3E)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF0EDE8),
              ),
            ),
          ),
        ),
      ],
    ),
  );
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
        color: const Color(0xFF1F1F2B),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, color: const Color(0xFF8E8A9A), size: 16),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _CanvasBgPickerDialog — swatch grid + hex input for canvas background colour
// ─────────────────────────────────────────────────────────────────────────────
class _CanvasBgPickerDialog extends StatefulWidget {
  final Color initial;
  const _CanvasBgPickerDialog({required this.initial});
  @override
  State<_CanvasBgPickerDialog> createState() => _CanvasBgPickerDialogState();
}

class _CanvasBgPickerDialogState extends State<_CanvasBgPickerDialog> {
  late Color _current;
  late TextEditingController _hexCtrl;
  late FocusNode _hexFocus;
  bool _hexInvalid = false;

  static const _presets = [
    Color(0xFF0D0D11),
    Color(0xFF111318),
    Color(0xFF1A1A1A),
    Color(0xFF1C1510),
    Color(0xFF0D1117),
    Color(0xFF17171F),
    Color(0xFF12100E),
    Color(0xFF0A0F0D),
    Color(0xFF2A2A3A),
    Color(0xFF252534),
    Color(0xFF1E1E2E),
    Color(0xFF22222A),
  ];

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _hexCtrl = TextEditingController(text: _toHex(_current));
    _hexFocus = FocusNode()
      ..addListener(() {
        if (!_hexFocus.hasFocus) _commitHex();
      });
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  String _toHex(Color c) =>
      c.value.toRadixString(16).substring(2).toUpperCase();

  void _selectPreset(Color c) {
    setState(() {
      _current = c;
      _hexCtrl.text = _toHex(c);
      _hexInvalid = false;
    });
  }

  void _commitHex() {
    final raw = _hexCtrl.text.replaceAll('#', '').trim();
    if (raw.length == 6) {
      final parsed = int.tryParse('FF$raw', radix: 16);
      if (parsed != null) {
        setState(() {
          _current = Color(parsed);
          _hexInvalid = false;
        });
        return;
      }
    }
    setState(() => _hexInvalid = true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F1F2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Row(
              children: [
                Icon(
                  Icons.format_paint_outlined,
                  size: 16,
                  color: Color(0xFFC9A96E),
                ),
                SizedBox(width: 8),
                Text(
                  'Canvas Background',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF0EDE8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Colour shown outside the room boundary',
              style: TextStyle(fontSize: 11, color: Color(0xFF8E8A9A)),
            ),
            const SizedBox(height: 16),
            // Preset swatches
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((c) {
                final isCurrent = c.value == _current.value;
                return GestureDetector(
                  onTap: () => _selectPreset(c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFFC9A96E)
                            : const Color(0xFF2C2C3E),
                        width: isCurrent ? 2.5 : 1,
                      ),
                    ),
                    child: isCurrent
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Color(0xFFC9A96E),
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Hex input row
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _current,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2C2C3E)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '#',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF56535F),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    focusNode: _hexFocus,
                    maxLength: 6,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _hexInvalid
                          ? const Color(0xFFE05252)
                          : const Color(0xFFF0EDE8),
                      fontFamily: 'monospace',
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF17171F),
                      hintText: 'RRGGBB',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3A3842),
                        fontFamily: 'monospace',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: _hexInvalid
                              ? const Color(0xFFE05252)
                              : const Color(0xFF2C2C3E),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: _hexInvalid
                              ? const Color(0xFFE05252)
                              : const Color(0xFF2C2C3E),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: _hexInvalid
                              ? const Color(0xFFE05252)
                              : const Color(0xFFC9A96E),
                          width: 1.5,
                        ),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    ],
                    onSubmitted: (_) => _commitHex(),
                    onChanged: (v) {
                      if (v.length == 6) _commitHex();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _commitHex,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9A96E).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFC9A96E).withOpacity(0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Color(0xFFC9A96E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF8E8A9A)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_current),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9A96E),
                    foregroundColor: const Color(0xFF0D0D11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SizeField — compact numeric text field for 2D footprint width/height input
// ─────────────────────────────────────────────────────────────────────────────
class _SizeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final Color accent;
  const _SizeField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8A9A)),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(fontSize: 13, color: Color(0xFFF0EDE8)),
          decoration: InputDecoration(
            suffixText: 'px',
            suffixStyle: const TextStyle(
              fontSize: 12,
              color: Color(0xFF56535F),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: const Color(0xFF17171F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2C2C3E)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2C2C3E)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
