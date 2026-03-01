import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single custom furniture entry
// ─────────────────────────────────────────────────────────────────────────────

class CustomFurnitureEntry {
  final String id;
  final String name;
  final String category; // built-in or custom category name
  final String glbFileName; // filename only — served by AssetServer
  final bool isCustomCategory; // true if user created a new category
  final int colorValue; // colour used for the 2D canvas tile

  const CustomFurnitureEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.glbFileName,
    this.isCustomCategory = false,
    this.colorValue = 0xFF607D8B,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'glbFileName': glbFileName,
    'isCustomCategory': isCustomCategory,
    'colorValue': colorValue,
  };

  factory CustomFurnitureEntry.fromJson(Map<String, dynamic> j) =>
      CustomFurnitureEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        glbFileName: j['glbFileName'] as String,
        isCustomCategory: j['isCustomCategory'] as bool? ?? false,
        colorValue: j['colorValue'] as int? ?? 0xFF607D8B,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Singleton registry — persists to disk, notifies listeners on change
//
// Storage layout:
//   Windows : %APPDATA%\furniture_visualizer\custom_furniture.json
//             %APPDATA%\furniture_visualizer\custom_models\*.glb
//   macOS/L : ~/.furniture_visualizer/ (same structure)
// ─────────────────────────────────────────────────────────────────────────────

class CustomFurnitureRegistry extends ChangeNotifier {
  CustomFurnitureRegistry._();
  static final instance = CustomFurnitureRegistry._();

  List<CustomFurnitureEntry> _entries = [];

  /// All registered custom furniture entries.
  List<CustomFurnitureEntry> get entries => List.unmodifiable(_entries);

  // ── Directory / file paths ───────────────────────────────────────────────

  static Directory get _appDataDir {
    final String base;
    if (Platform.isWindows) {
      base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    } else {
      base = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    }
    return Directory('$base${Platform.pathSeparator}furniture_visualizer');
  }

  /// Directory where custom GLB files are stored.
  static Directory get modelsDir =>
      Directory('${_appDataDir.path}${Platform.pathSeparator}custom_models');

  static File get _registryFile =>
      File('${_appDataDir.path}${Platform.pathSeparator}custom_furniture.json');

  // ── Load from disk ───────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      await _appDataDir.create(recursive: true);
      await modelsDir.create(recursive: true);
      if (!await _registryFile.exists()) return;

      final raw = await _registryFile.readAsString();
      final List decoded = jsonDecode(raw) as List;
      _entries = decoded
          .map((e) => CustomFurnitureEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      // Remove orphan entries whose GLB file has been deleted externally
      _entries.removeWhere(
        (e) => !File(
          '${modelsDir.path}${Platform.pathSeparator}${e.glbFileName}',
        ).existsSync(),
      );

      notifyListeners();
    } catch (e) {
      debugPrint('[Registry] load error: $e');
    }
  }

  // ── Persist to disk ──────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      await _appDataDir.create(recursive: true);
      await _registryFile.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[Registry] save error: $e');
    }
  }

  // ── Add a new custom furniture entry ────────────────────────────────────

  /// Copies the user-selected GLB file into the app's models directory
  /// and saves the metadata entry to the JSON registry.
  ///
  /// [sourceGlbPath] is the full path of the file the user picked.
  Future<CustomFurnitureEntry> addEntry({
    required String name,
    required String category,
    required String sourceGlbPath,
    bool isCustomCategory = false,
    int colorValue = 0xFF607D8B,
  }) async {
    await modelsDir.create(recursive: true);

    // Build a safe, collision-free filename
    final ext = sourceGlbPath.split('.').last.toLowerCase();
    final safeBase = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final uid = DateTime.now().millisecondsSinceEpoch.toString();
    final glbFileName = 'custom_${safeBase}_$uid.$ext';

    // Copy the GLB into our models directory
    await File(
      sourceGlbPath,
    ).copy('${modelsDir.path}${Platform.pathSeparator}$glbFileName');

    final entry = CustomFurnitureEntry(
      id: uid,
      name: name,
      category: category,
      glbFileName: glbFileName,
      isCustomCategory: isCustomCategory,
      colorValue: colorValue,
    );

    _entries.add(entry);
    await _save();
    notifyListeners();
    return entry;
  }

  // ── Remove an entry ──────────────────────────────────────────────────────

  Future<void> removeEntry(String id) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx == -1) return;

    final entry = _entries[idx];
    final glb = File(
      '${modelsDir.path}${Platform.pathSeparator}${entry.glbFileName}',
    );
    if (await glb.exists()) await glb.delete();

    _entries.removeAt(idx);
    await _save();
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// All unique category names that have at least one entry.
  List<String> get allCategoryNames =>
      _entries.map((e) => e.category).toSet().toList();

  /// All entries belonging to [category].
  List<CustomFurnitureEntry> entriesForCategory(String category) =>
      _entries.where((e) => e.category == category).toList();
}
