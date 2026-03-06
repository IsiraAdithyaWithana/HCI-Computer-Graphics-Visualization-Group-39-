import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the 3D scale factor for each furniture *type* permanently.
///
/// Key strategy
/// ─────────────
/// • Built-in types  → FurnitureType.name  (e.g. "chair", "sofa")
/// • Custom GLB items → glbFileName         (e.g. "barcelona_chair.glb")
///
/// This means:
///   - Every new instance of a type gets the last-saved scale automatically.
///   - Resizing one chair in 3D sets the default for ALL future chairs.
///   - Clearing layout / hot-reload / full restart does NOT lose saved sizes.
class FurnitureScaleService {
  FurnitureScaleService._();
  static final instance = FurnitureScaleService._();

  static const _kPrefsKey = 'furniture_type_scales';

  /// In-memory cache so reads are synchronous after [load()] completes.
  final Map<String, double> _scales = {};

  bool _loaded = false;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Must be awaited once at app start (in main.dart) before the UI runs.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        decoded.forEach((k, v) {
          if (v is num) _scales[k] = v.toDouble();
        });
      } catch (_) {
        // corrupt data – start fresh
      }
    }
    _loaded = true;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the saved scale for [typeKey], or 1.0 if none has been saved yet.
  /// [typeKey] = glbFileName for custom items, FurnitureType.name otherwise.
  double getScale(String typeKey) => _scales[typeKey] ?? 1.0;

  /// Saves [scaleFactor] for [typeKey] and immediately flushes to disk.
  Future<void> saveScale(String typeKey, double scaleFactor) async {
    _scales[typeKey] = scaleFactor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(_scales));
  }
}
