import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../models/furniture_model.dart';
import '../services/asset_server.dart';

class Realistic3DScreen extends StatefulWidget {
  final List<FurnitureModel> furniture;
  final double roomWidth;
  final double roomDepth;

  const Realistic3DScreen({
    super.key,
    required this.furniture,
    required this.roomWidth,
    required this.roomDepth,
  });

  @override
  State<Realistic3DScreen> createState() => _Realistic3DScreenState();
}

class _Realistic3DScreenState extends State<Realistic3DScreen> {
  final WebviewController _controller = WebviewController();

  String _statusText = 'Starting local server…';
  bool _showOverlay = true;
  bool _hasError = false;
  bool _dataSent = false; // guard so we only send once

  StreamSubscription? _msgSub;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _fallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      setState(() => _statusText = 'Copying 3D assets…');
      final baseUrl = await AssetServer.start();

      setState(() => _statusText = 'Initialising WebView…');
      await _controller.initialize();

      // Listen for 'ready' from window.chrome.webview.postMessage in the HTML
      _msgSub = _controller.webMessage.listen((msg) {
        final text = msg.toString();
        if (text.contains('ready') && !_dataSent) {
          _sendFurnitureData();
        }
      });

      setState(() => _statusText = 'Loading 3D viewer…');
      await _controller.loadUrl('$baseUrl/room_viewer.html');

      setState(() => _showOverlay = false);

      // Fallback: if the 'ready' message is missed for any reason,
      // send furniture data after 4 seconds anyway.
      _fallbackTimer = Timer(const Duration(seconds: 4), () {
        if (!_dataSent) {
          debugPrint('3D viewer: fallback timer fired, sending data');
          _sendFurnitureData();
        }
      });
    } catch (e) {
      setState(() {
        _statusText = 'Error: $e';
        _hasError = true;
      });
    }
  }

  void _sendFurnitureData() {
    if (_dataSent) return;
    _dataSent = true;

    final items = widget.furniture.map((item) {
      final hex = item.color.value
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2);
      return {
        'type': item.type.name,
        'x': item.position.dx,
        'y': item.position.dy,
        'width': item.size.width,
        'height': item.size.height,
        'rotation': item.rotation,
        'color': '#$hex',
      };
    }).toList();

    final payload = jsonEncode({
      'items': items,
      'roomWidth': widget.roomWidth,
      'roomDepth': widget.roomDepth,
    });

    // Double-encode so the string arrives safely inside the JS function call
    final jsCall = 'window.loadFurniture(${jsonEncode(payload)})';
    _controller.executeScript(jsCall);
    debugPrint('3D viewer: sent ${items.length} furniture items');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _AppBar(itemCount: widget.furniture.length),
      ),
      body: Stack(
        children: [
          // WebView is always in the tree so it keeps rendering
          Webview(_controller),

          // Overlay hides the WebView until it is ready
          if (_showOverlay)
            _LoadingOverlay(message: _statusText, hasError: _hasError),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final int itemCount;
  const _AppBar({required this.itemCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F2A),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
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
              tooltip: 'Back to editor',
            ),
            const SizedBox(width: 2),
            const Text(
              'Realistic 3D View',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            _Badge(
              icon: Icons.chair_outlined,
              label: '$itemCount item${itemCount == 1 ? '' : 's'}',
              color: Colors.indigo,
            ),
            const SizedBox(width: 10),
            _Badge(
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

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45)),
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

class _LoadingOverlay extends StatelessWidget {
  final String message;
  final bool hasError;
  const _LoadingOverlay({required this.message, required this.hasError});

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
                size: 44,
              ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasError
                    ? Colors.redAccent.withOpacity(0.85)
                    : Colors.white.withOpacity(0.65),
                fontSize: 14,
              ),
            ),
            if (!hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Loading Three.js + GLB models…',
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
