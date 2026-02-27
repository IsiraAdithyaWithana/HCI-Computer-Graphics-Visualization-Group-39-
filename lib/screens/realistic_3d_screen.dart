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

  bool _sceneReady = false;
  bool _hasError = false;
  String _statusText = 'Starting…';

  @override
  void initState() {
    super.initState();
    // Must run after first frame so Webview() widget is in the render tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      setState(() => _statusText = 'Initialising WebView…');
      await _controller.initialize();

      setState(() => _statusText = 'Copying 3D assets…');
      final baseUrl = await AssetServer.start();
      debugPrint('[3D] Server: $baseUrl');

      final url = _buildUrl(baseUrl);
      setState(() => _statusText = 'Loading 3D scene…');
      await _controller.loadUrl(url);

      // Hide Flutter overlay — Three.js loading spinner inside WebView takes over
      setState(() => _sceneReady = true);
    } catch (e, st) {
      debugPrint('[3D] Error: $e\n$st');
      setState(() {
        _hasError = true;
        _statusText = 'Error: $e';
      });
    }
  }

  String _buildUrl(String baseUrl) {
    final items = widget.furniture
        .map(
          (f) => {
            'type': f.type.name,
            'x': f.position.dx,
            'y': f.position.dy,
            'width': f.size.width,
            'height': f.size.height,
            'rotation': f.rotation,
          },
        )
        .toList();

    final payload = jsonEncode({
      'items': items,
      'roomWidth': widget.roomWidth,
      'roomDepth': widget.roomDepth,
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
        child: _AppBar(itemCount: widget.furniture.length),
      ),
      body: Stack(
        children: [
          // ── THE FIX ────────────────────────────────────────────────────────
          // Webview inside a Stack gets *loose* constraints and defaults to
          // zero size → black screen.  Positioned.fill gives it *tight*
          // constraints that match the full Stack area, so it actually renders.
          Positioned.fill(child: Webview(_controller)),

          // Flutter overlay while booting
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
  const _AppBar({required this.itemCount});

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
