import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'custom_furniture_registry.dart';

/// Copies all viewer assets (HTML + JS libraries + GLB models) from Flutter's
/// asset bundle — plus any user-added custom GLB files — to a temp directory,
/// then starts a local HTTP server.
///
/// Custom models are re-synced on every call to [start] so newly added
/// furniture appears without restarting the server.
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

  // ── Start (or return cached URL) ─────────────────────────────────────────

  static Future<String> start() async {
    final serveDir = Directory('${Directory.systemTemp.path}/furniture_viewer');
    await serveDir.create(recursive: true);

    if (_server == null) {
      // First launch: copy all Flutter-bundled assets
      for (final assetPath in _assets) {
        final bytes = await rootBundle.load(assetPath);
        final fileName = assetPath.split('/').last;
        final outFile = File('${serveDir.path}/$fileName');
        await outFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }

      // Start the static file server (port 0 → OS picks a free port)
      final handler = createStaticHandler(
        serveDir.path,
        defaultDocument: 'room_viewer.html',
      );
      _server = await shelf_io.serve(handler, 'localhost', 0);
      _baseUrl = 'http://localhost:${_server!.port}';
      debugPrint('[AssetServer] started at $_baseUrl');
    }

    // Always re-sync custom models so newly added GLBs are immediately
    // available without restarting the server.
    await _syncCustomModels(serveDir);

    return _baseUrl!;
  }

  // ── Sync custom GLB files into the serve directory ───────────────────────

  static Future<void> _syncCustomModels(Directory serveDir) async {
    try {
      final modelsDir = CustomFurnitureRegistry.modelsDir;
      if (!await modelsDir.exists()) return;

      await for (final entity in modelsDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.glb')) {
          final filename = entity.path.split(Platform.pathSeparator).last;
          final dest = File('${serveDir.path}/$filename');
          // Only copy if the file is missing or has been updated
          if (!await dest.exists() ||
              (await entity.lastModified()).isAfter(
                await dest.lastModified(),
              )) {
            await entity.copy(dest.path);
            debugPrint('[AssetServer] synced custom model: $filename');
          }
        }
      }
    } catch (e) {
      debugPrint('[AssetServer] custom model sync error: $e');
    }
  }

  // ── Stop the server ──────────────────────────────────────────────────────

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _baseUrl = null;
    debugPrint('[AssetServer] stopped');
  }
}
