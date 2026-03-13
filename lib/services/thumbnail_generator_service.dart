import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'asset_server.dart';
import 'thumbnail_cache.dart';

/// Singleton service that generates real top-down 3D thumbnails for every GLB.
///
/// Boots a hidden [WebviewController], loads room_viewer.html?thumbonly=1,
/// which renders each GLB top-down in Three.js and sends base64 PNGs back
/// via postMessage.  Results are stored in [ThumbnailCache] (disk-persisted)
/// and the 2D canvas repaints automatically.
///
/// Two modes:
///   1. generateBuiltinsInBackground — thumbnails all 20 built-in GLBs silently
///   2. generateForGlb               — thumbnails one custom imported GLB, awaitable
class ThumbnailGeneratorService {
  ThumbnailGeneratorService._();
  static final instance = ThumbnailGeneratorService._();

  // Keys currently being generated (used for spinners / duplicate prevention)
  final Set<String> _inProgress = {};

  static const _builtinJobKey = '__builtins__';

  static const List<String> builtinKeys = [
    'chair',
    'sofa',
    'armchair',
    'bench',
    'stool',
    'table',
    'coffeeTable',
    'desk',
    'sideTable',
    'wardrobe',
    'bookshelf',
    'cabinet',
    'dresser',
    'bed',
    'singleBed',
    'nightstand',
    'plant',
    'lamp',
    'tvStand',
    'rug',
  ];

  bool get isGeneratingBuiltins => _inProgress.contains(_builtinJobKey);
  bool isGenerating(String key) => _inProgress.contains(key);

  // ── Thumbnail all 20 built-in GLBs silently in the background ─────────────
  void generateBuiltinsInBackground(BuildContext context) {
    final missing = builtinKeys
        .where((k) => !ThumbnailCache.instance.hasImage(k))
        .toList();
    if (missing.isEmpty || _inProgress.contains(_builtinJobKey)) return;
    // Fire and forget — caller is never blocked
    _doBuiltins(context);
  }

  Future<void> _doBuiltins(BuildContext context) async {
    _inProgress.add(_builtinJobKey);
    try {
      await _runSession(context: context);
    } finally {
      _inProgress.remove(_builtinJobKey);
    }
  }

  // ── Thumbnail a single imported GLB — caller awaits this ──────────────────
  /// [glbFileName] — filename inside the custom_models directory
  ///                 e.g. "custom_sofa_1234567890.glb"
  /// [thumbKey]    — key under which the thumbnail is stored in ThumbnailCache
  ///                 (pass glbFileName so room_canvas looks it up by glbOverride)
  Future<void> generateForGlb(
    BuildContext context,
    String glbFileName,
    String thumbKey,
  ) async {
    if (_inProgress.contains(thumbKey)) return;
    _inProgress.add(thumbKey);
    try {
      await _runSession(
        context: context,
        customGlb: glbFileName,
        customKey: thumbKey,
      );
    } finally {
      _inProgress.remove(thumbKey);
    }
  }

  // ── Internal: one WebView session ─────────────────────────────────────────
  Future<void> _runSession({
    required BuildContext context,
    String? customGlb,
    String? customKey,
  }) async {
    final controller = WebviewController();
    final done = Completer<void>();

    try {
      await controller.initialize();

      controller.webMessage.listen((raw) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final type = data['type'] as String?;
          if (type == 'thumbnail') {
            final key = data['key'] as String?;
            final b64 = data['base64'] as String?;
            if (key != null && b64 != null && b64.length > 200) {
              ThumbnailCache.instance.store(key, b64);
              debugPrint('[ThumbGen] ✓ $key');
            }
          } else if (type == 'thumbDone') {
            if (!done.isCompleted) done.complete();
          }
        } catch (_) {}
      });

      // Ensure custom GLBs are copied to the serve dir before loading the page
      await AssetServer.syncCustomModels();
      final baseUrl = await AssetServer.start();

      final String url;
      if (customGlb != null && customKey != null) {
        url =
            '$baseUrl/room_viewer.html'
            '?thumbonly=1'
            '&glb=${Uri.encodeComponent(customGlb)}'
            '&key=${Uri.encodeComponent(customKey)}';
      } else {
        url = '$baseUrl/room_viewer.html?thumbonly=1';
      }

      debugPrint('[ThumbGen] loading $url');
      await controller.loadUrl(url);

      // Max wait: 90 s (20 models × ~4 s each worst case)
      await done.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => debugPrint('[ThumbGen] timeout — partial results OK'),
      );
    } catch (e) {
      debugPrint('[ThumbGen] session error: $e');
    } finally {
      try {
        controller.dispose();
      } catch (_) {}
    }
  }
}
