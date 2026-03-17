import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import '../models/furniture_model.dart';
import '../services/asset_server.dart';
import 'bill_preview_screen.dart';
import '../services/thumbnail_cache.dart';

class Realistic3DScreen extends StatefulWidget {
  final List<FurnitureModel> furniture;
  final double roomWidth;
  final double roomDepth;
  final double wallHeightM;

  /// Room colour scheme — passed through to the Three.js viewer.
  final Color wallColour;
  final Color floorColour;
  final Color ceilingColour;
  final Color trimColour;

  /// Called when the user saves a resized furniture item in the 3D view.
  /// [id] is the FurnitureModel.id, [scaleFactor] is the multiplier applied.
  final void Function(String id, double scaleFactor)? onSizeUpdated;

  /// Called once per custom GLB when the scene first loads.
  /// [id] is the FurnitureModel.id; [widthPx] and [depthPx] are the natural
  /// canvas-pixel footprint dimensions derived from the GLB's bounding box.
  /// Use these to update the 2D tile so it matches the real model shape.
  final void Function(String id, double widthPx, double depthPx)?
  onNaturalSizeDetected;

  /// Called when the user saves a tint on a selected furniture item.
  /// [tintHex] is null when tint is cleared.
  /// FIX: added {double strength} so the saved percentage is forwarded to Flutter.
  final void Function(String id, String? tintHex, {double strength})?
  onTintUpdated;

  /// Undo / Redo — ValueNotifier so the appbar reacts live to canvas history changes.
  final ValueNotifier<bool>? canUndoNotifier;
  final ValueNotifier<bool>? canRedoNotifier;

  /// Callback to open the bill preview from 3D view.
  final List<FurnitureModel>? allFurniture;

  /// Returns JSON of updated furniture items so the 3D scene can live-update.
  final String? Function()? onUndo;
  final String? Function()? onRedo;

  /// Room shape name (matches RoomShape.name e.g. 'circle', 'hexagon').
  final String roomShape;

  /// Custom polygon points as relative 0..1 coords — only when roomShape == 'custom'.
  final List<Map<String, double>>? customShapePoints;

  /// Whether this user has admin (designer) privileges.
  final bool isAdmin;

  const Realistic3DScreen({
    super.key,
    required this.furniture,
    required this.roomWidth,
    required this.roomDepth,
    this.wallHeightM = 3.2,
    this.wallColour = const Color(0xFFF0EBE2),
    this.floorColour = const Color(0xFFD4C4A8),
    this.ceilingColour = const Color(0xFFFAF8F4),
    this.trimColour = const Color(0xFFE8E0D4),
    this.roomShape = 'rectangle',
    this.customShapePoints,
    this.isAdmin = true,
    this.onSizeUpdated,
    this.onNaturalSizeDetected,
    this.onTintUpdated,
    this.allFurniture,
    this.onUndo,
    this.onRedo,
    this.canUndoNotifier,
    this.canRedoNotifier,
  });

  @override
  State<Realistic3DScreen> createState() => _Realistic3DScreenState();
}

class _Realistic3DScreenState extends State<Realistic3DScreen> {
  final WebviewController _controller = WebviewController();

  bool _sceneReady = false;
  bool _hasError = false;
  String _statusText = 'Starting…';

  @override
  void initState() {
    super.initState();
    // Global keyboard handler — fires even when the WebView owns focus.
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _controller.dispose();
    super.dispose();
  }

  /// Intercepts Ctrl+Z / Ctrl+Shift+Z at the OS level regardless of focus.
  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!widget.isAdmin) return false; // non-admins cannot undo/redo
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _handleUndo();
      return true;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _handleRedo();
      return true;
    }
    return false;
  }

  /// Call undo on the 2D canvas and immediately push updated items to the 3D scene.
  void _handleUndo() {
    final json = widget.onUndo?.call();
    if (json != null && _sceneReady) {
      _pushItemsToScene(json);
    }
  }

  /// Call redo on the 2D canvas and immediately push updated items to the 3D scene.
  void _handleRedo() {
    final json = widget.onRedo?.call();
    if (json != null && _sceneReady) {
      _pushItemsToScene(json);
    }
  }

  /// Call `window.flutterUpdateItems` in the webview with the current item states.
  void _pushItemsToScene(String itemsJson) {
    final escaped = itemsJson
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    _controller.executeScript("window.flutterUpdateItems('$escaped');");
  }

  Future<void> _boot() async {
    try {
      setState(() => _statusText = 'Initialising WebView…');
      await _controller.initialize();

      // ── Listen for messages from the 3D viewer ──────────────────────────
      _controller.webMessage.listen((msg) {
        try {
          final data = jsonDecode(msg) as Map<String, dynamic>;
          if (data['type'] == 'undo') {
            _handleUndo();
          } else if (data['type'] == 'redo') {
            _handleRedo();
          } else if (data['type'] == 'sizeUpdate') {
            final id = data['id'] as String?;
            final scaleFactor = (data['scaleFactor'] as num?)?.toDouble();
            if (id != null && scaleFactor != null) {
              widget.onSizeUpdated?.call(id, scaleFactor);
              debugPrint('[3D→Flutter] sizeUpdate id=$id scale=$scaleFactor');
            }
          } else if (data['type'] == 'naturalSize') {
            final id = data['id'] as String?;
            final widthPx = (data['widthPx'] as num?)?.toDouble();
            final depthPx = (data['depthPx'] as num?)?.toDouble();
            if (id != null && widthPx != null && depthPx != null) {
              widget.onNaturalSizeDetected?.call(id, widthPx, depthPx);
              debugPrint(
                '[3D→Flutter] naturalSize id=$id w=${widthPx.toStringAsFixed(1)} d=${depthPx.toStringAsFixed(1)}',
              );
            }
          } else if (data['type'] == 'tintUpdate') {
            // FIX: read tintStrength from the JS message and forward it.
            // Previously this was dropped, so Flutter always stored 0.4 default.
            final id = data['id'] as String?;
            final tintHex = data['tintHex'] as String?;
            final tintStrength =
                (data['tintStrength'] as num?)?.toDouble() ?? 0.4;
            if (id != null) {
              widget.onTintUpdated?.call(id, tintHex, strength: tintStrength);
              debugPrint(
                '[3D→Flutter] tintUpdate id=$id tint=$tintHex strength=$tintStrength',
              );
            }
          } else if (data['type'] == 'thumbnail') {
            final key = data['key'] as String?;
            final base64 = data['base64'] as String?;
            if (key != null && base64 != null && base64.length > 100) {
              ThumbnailCache.instance.store(key, base64);
              debugPrint('[3D→Flutter] thumbnail key=$key');
            }
          }
        } catch (e) {
          debugPrint('[3D] webMessage parse error: $e');
        }
      });

      setState(() => _statusText = 'Copying 3D assets…');
      final baseUrl = await AssetServer.start();
      debugPrint('[3D] Server: $baseUrl');

      final url = _buildUrl(baseUrl);
      setState(() => _statusText = 'Loading 3D scene…');
      await _controller.loadUrl(url);

      setState(() => _sceneReady = true);

      // Apply role-based UI restrictions in the WebView
      await Future.delayed(const Duration(milliseconds: 600));
      _applyRoleRestrictions();
    } catch (e, st) {
      debugPrint('[3D] Error: $e\n$st');
      setState(() {
        _hasError = true;
        _statusText = 'Error: $e';
      });
    }
  }

  String _colourHex(Color c) =>
      c.value.toRadixString(16).substring(2).toUpperCase();

  void _applyRoleRestrictions() {
    if (widget.isAdmin) return; // admins see everything
    // Hide: Select toggle, Scale panel save button, per-item shading sliders
    _controller.executeScript('''
      (function() {
        var selBtn = document.getElementById('select-toggle');
        if (selBtn) selBtn.style.display = 'none';
        var saveBtn = document.getElementById('btn-save');
        if (saveBtn) saveBtn.style.display = 'none';
        var itemBright = document.getElementById('lp-item-bright');
        var itemDark   = document.getElementById('lp-item-dark');
        var lpReset    = document.getElementById('lp-reset');
        var lbv = document.getElementById('lp-item-bright-val');
        var ldv = document.getElementById('lp-item-dark-val');
        [itemBright, itemDark, lpReset, lbv, ldv].forEach(function(el) {
          if (el) el.closest('.lp-row, button') && (el.closest('.lp-row') || el).style
            ? (el.closest('.lp-row') || el).style.display = 'none'
            : (el ? el.style.display = 'none' : null);
        });
        // Simplest approach: hide whole selected furniture shading section
        var shadingLabel = Array.from(document.querySelectorAll('.lp-section-label'))
          .find(function(el) { return el.textContent.includes('Selected furniture'); });
        if (shadingLabel) {
          shadingLabel.style.display = 'none';
          var next = shadingLabel.nextElementSibling;
          while (next && !next.classList.contains('lp-divider') && !next.classList.contains('lp-section-label')) {
            next.style.display = 'none';
            next = next.nextElementSibling;
          }
        }
      })();
    ''');
  }

  String _buildUrl(String baseUrl) {
    final items = widget.furniture
        .map(
          (f) => {
            'id': f.id,
            'type': f.type.name,
            'x': f.position.dx,
            'y': f.position.dy,
            'width': f.size.width,
            'height': f.size.height,
            'rotation': f.rotation,
            'scaleFactor': f.scaleFactor,
            if (f.glbOverride != null) 'glbFile': f.glbOverride,
            if (f.labelOverride != null) 'label': f.labelOverride,
            // FIX: send both tint colour AND tintStrength so JS restores the
            // exact saved percentage when the 3D view is reopened.
            // Previously only 'tint' was sent — JS fell back to 0.5 default.
            if (f.tintHex != null) 'tint': f.tintHex,
            if (f.tintHex != null) 'tintStrength': f.tintStrength,
          },
        )
        .toList();

    final payload = jsonEncode({
      'items': items,
      'roomWidth': widget.roomWidth,
      'roomDepth': widget.roomDepth,
      'wallHeight': widget.wallHeightM,
      'wallColor': _colourHex(widget.wallColour),
      'floorColor': _colourHex(widget.floorColour),
      'ceilingColor': _colourHex(widget.ceilingColour),
      'trimColor': _colourHex(widget.trimColour),
      'roomShape': widget.roomShape,
      if (widget.customShapePoints != null)
        'customShapePoints': widget.customShapePoints,
    });

    final encoded = base64Url.encode(utf8.encode(payload));
    return '$baseUrl/room_viewer.html?d=$encoded';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _AppBar(
          itemCount: widget.furniture.length,
          canUndoNotifier: widget.canUndoNotifier,
          canRedoNotifier: widget.canRedoNotifier,
          onUndo: _handleUndo,
          onRedo: _handleRedo,
          isAdmin: widget.isAdmin,
          onViewBill: widget.allFurniture != null
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillPreviewScreen(
                        projectName: 'My Design',
                        furniture: widget.allFurniture!,
                      ),
                    ),
                  );
                }
              : null,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerPanZoomStart: (e) {
                if (!_sceneReady) return;
                _controller.executeScript(
                  'window._flutterTouchpad&&window._flutterTouchpad("start",'
                  '${e.localPosition.dx},${e.localPosition.dy},1.0,0.0,0.0);',
                );
              },
              onPointerPanZoomUpdate: (e) {
                if (!_sceneReady) return;
                _controller.executeScript(
                  'window._flutterTouchpad&&window._flutterTouchpad("update",'
                  '${e.localPosition.dx},${e.localPosition.dy},'
                  '${e.scale},${e.panDelta.dx},${e.panDelta.dy});',
                );
              },
              onPointerPanZoomEnd: (e) {
                if (!_sceneReady) return;
                _controller.executeScript(
                  'window._flutterTouchpad&&window._flutterTouchpad("end",'
                  '0,0,1.0,0.0,0.0);',
                );
              },
              child: Webview(_controller),
            ),
          ),
          if (!_sceneReady)
            Positioned.fill(
              child: _Overlay(message: _statusText, hasError: _hasError),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final int itemCount;
  final ValueNotifier<bool>? canUndoNotifier;
  final ValueNotifier<bool>? canRedoNotifier;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool isAdmin;
  final VoidCallback? onViewBill;

  const _AppBar({
    required this.itemCount,
    this.canUndoNotifier,
    this.canRedoNotifier,
    this.onUndo,
    this.onRedo,
    this.isAdmin = true,
    this.onViewBill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F2A),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
            const Text(
              'Realistic 3D View',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // ── Undo / Redo buttons (admin only) ──────────────────────
            if (isAdmin) ...[
              ValueListenableBuilder<bool>(
                valueListenable: canUndoNotifier ?? ValueNotifier(false),
                builder: (_, canUndo, __) => Tooltip(
                  message: 'Undo (Ctrl+Z)',
                  child: _AppBarIconBtn(
                    icon: Icons.undo_rounded,
                    enabled: canUndo,
                    onTap: canUndo ? onUndo : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ValueListenableBuilder<bool>(
                valueListenable: canRedoNotifier ?? ValueNotifier(false),
                builder: (_, canRedo, __) => Tooltip(
                  message: 'Redo (Ctrl+Shift+Z)',
                  child: _AppBarIconBtn(
                    icon: Icons.redo_rounded,
                    enabled: canRedo,
                    onTap: canRedo ? onRedo : null,
                  ),
                ),
              ),
            ],
            // ── View Bill button ──────────────────────────────────
            if (onViewBill != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onViewBill,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x33C9A96E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFC9A96E).withOpacity(0.5),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFFC9A96E),
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'View Bill',
                        style: TextStyle(
                          color: Color(0xFFC9A96E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            _Chip(
              icon: Icons.chair_outlined,
              label: '$itemCount item${itemCount == 1 ? '' : 's'}',
              color: Colors.indigo,
            ),
            const SizedBox(width: 8),
            _Chip(
              icon: Icons.threesixty,
              label: 'Drag to orbit',
              color: Colors.teal,
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _AppBarIconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _AppBarIconBtn({required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? Colors.white.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.white : Colors.white.withOpacity(0.25),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color.withOpacity(0.9), size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final String message;
  final bool hasError;
  const _Overlay({required this.message, required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D1A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasError)
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: Color(0xFF6366F1),
                  strokeWidth: 3,
                ),
              )
            else
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasError
                    ? Colors.redAccent
                    : Colors.white.withOpacity(0.65),
                fontSize: 14,
              ),
            ),
            if (!hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Three.js + GLB models loading…',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
