import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

/// Copies all viewer assets (HTML + JS libraries + GLB models) from Flutter's
/// asset bundle to a temp directory, then starts a local HTTP server.
/// Uses Dart's built-in Directory.systemTemp — no path_provider plugin needed.
class AssetServer {
  AssetServer._();

  static HttpServer? _server;
  static String? _baseUrl;

  static const List<String> _assets = [
    // ── HTML viewer ────────────────────────────────────────────────────────
    'assets/viewer/room_viewer.html',

    // ── Three.js local copies (no CDN needed — works offline in WebView2) ──
    'assets/viewer/three.min.js',
    'assets/viewer/OrbitControls.js',
    'assets/viewer/GLTFLoader.js',

    // ── 3D models — Seating ────────────────────────────────────────────────
    'assets/models/chair.glb',
    'assets/models/sofa.glb',
    'assets/models/arm_chair.glb',
    'assets/models/bench.glb',
    'assets/models/stool.glb',

    // ── 3D models — Tables ─────────────────────────────────────────────────
    'assets/models/table.glb',
    'assets/models/coffee_table.glb',
    'assets/models/desk.glb',
    'assets/models/side_table.glb',

    // ── 3D models — Storage ────────────────────────────────────────────────
    'assets/models/wardrobe.glb',
    'assets/models/book_shelf.glb',
    'assets/models/cabinet.glb',
    'assets/models/dresser.glb',

    // ── 3D models — Bedroom ────────────────────────────────────────────────
    'assets/models/double_bed.glb',
    'assets/models/single_bed.glb',
    'assets/models/night_stand.glb',

    // ── 3D models — Decor ──────────────────────────────────────────────────
    'assets/models/plant.glb',
    'assets/models/floor_lamp.glb',
    'assets/models/tv_stand.glb',
    'assets/models/rug.glb',
  ];

  static Future<String> start() async {
    if (_server != null && _baseUrl != null) return _baseUrl!;

    final serveDir = Directory('${Directory.systemTemp.path}/furniture_viewer');
    await serveDir.create(recursive: true);

    // Copy every asset to the flat temp directory
    for (final assetPath in _assets) {
      final bytes = await rootBundle.load(assetPath);
      final fileName = assetPath.split('/').last;
      final outFile = File('${serveDir.path}/$fileName');
      await outFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }

    final handler = createStaticHandler(
      serveDir.path,
      defaultDocument: 'room_viewer.html',
    );

    // Port 0 → OS picks a free port — no conflicts
    _server = await shelf_io.serve(handler, 'localhost', 0);
    _baseUrl = 'http://localhost:${_server!.port}';

    return _baseUrl!;
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _baseUrl = null;
  }
}
