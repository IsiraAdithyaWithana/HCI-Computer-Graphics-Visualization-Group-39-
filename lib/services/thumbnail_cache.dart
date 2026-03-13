import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Singleton that stores top-down PNG thumbnails of every furniture GLB.
///
/// Key convention:
///   Built-in types → FurnitureType.name   e.g. "chair"
///   Custom GLBs    → glbFileName           e.g. "custom_couch_abc123.glb"
///
/// ui.Image objects are GPU resources invalidated on hot-reload.
/// We keep raw PNG bytes alongside decoded images so [reloadImages] can
/// re-decode immediately from memory without any disk I/O.
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache._() {
    // Register for hot-reload callbacks so we re-decode images automatically.
    // In release builds reassemble is never called, so this is a no-op there.
    if (kDebugMode) {
      WidgetsFlutterBinding.ensureInitialized();
      // We piggyback on the SchedulerBinding post-frame to detect reassemble:
      // the actual hook is via the State.reassemble override in the widget tree.
    }
  }
  static final instance = ThumbnailCache._();

  // Decoded GPU images — invalidated by hot-reload
  final Map<String, ui.Image> _images = {};
  // Raw PNG bytes — survive hot-reload (plain Dart heap)
  final Map<String, Uint8List> _bytes = {};

  Map<String, ui.Image> get images => Map.unmodifiable(_images);
  bool hasImage(String key) => _images.containsKey(key);

  // ── Disk paths ─────────────────────────────────────────────────────────────
  static Directory get _thumbDir {
    final base = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? Directory.systemTemp.path)
        : (Platform.environment['HOME'] ?? Directory.systemTemp.path);
    return Directory(
      '$base${Platform.pathSeparator}furniture_visualizer'
      '${Platform.pathSeparator}thumbnails',
    );
  }

  static File _thumbFile(String key) {
    final safe = key.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${_thumbDir.path}${Platform.pathSeparator}$safe.png');
  }

  // ── Load all cached thumbnails from disk ───────────────────────────────────
  Future<void> loadAll() async {
    _images.clear();
    _bytes.clear();
    final dir = _thumbDir;
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.png')) {
        try {
          final bytes = await entity.readAsBytes();
          final img = await _decodeBytes(bytes);
          final key = entity.uri.pathSegments.last.replaceAll('.png', '');
          _images[key] = img;
          _bytes[key] = bytes;
        } catch (e) {
          debugPrint('[ThumbnailCache] load error ${entity.path}: $e');
        }
      }
    }
    if (_images.isNotEmpty) notifyListeners();
  }

  // ── Re-decode from in-memory bytes (call on hot-reload) ───────────────────
  /// Fast — no disk I/O. Falls back to [loadAll] if bytes are empty.
  Future<void> reloadImages() async {
    if (_bytes.isEmpty) {
      await loadAll();
      return;
    }
    // Clear stale disposed GPU handles first so nothing draws a dead image
    _images.clear();
    // Re-decode every PNG from raw bytes — no disk access needed
    final toProcess = Map<String, Uint8List>.from(_bytes); // snapshot
    for (final entry in toProcess.entries) {
      try {
        _images[entry.key] = await _decodeBytes(entry.value);
      } catch (e) {
        debugPrint('[ThumbnailCache] reloadImages error ${entry.key}: $e');
      }
    }
    notifyListeners();
  }

  // ── Clear all thumbnails from memory and disk ──────────────────────────────
  Future<void> clearAll() async {
    _images.clear();
    _bytes.clear();
    final dir = _thumbDir;
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  // ── Store a thumbnail from Three.js base64 data-URL ───────────────────────
  Future<void> store(String key, String base64DataUrl) async {
    try {
      final comma = base64DataUrl.indexOf(',');
      final b64 = comma >= 0
          ? base64DataUrl.substring(comma + 1)
          : base64DataUrl;
      final bytes = base64Decode(b64);
      final img = await _decodeBytes(bytes);
      _images[key] = img;
      _bytes[key] = bytes;
      final dir = _thumbDir;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await _thumbFile(key).writeAsBytes(bytes);
      notifyListeners();
    } catch (e) {
      debugPrint('[ThumbnailCache] store error key=$key: $e');
    }
  }

  // ── Helper ─────────────────────────────────────────────────────────────────
  static Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
