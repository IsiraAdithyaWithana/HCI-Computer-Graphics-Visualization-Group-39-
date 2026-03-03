import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the 2D canvas layout (furniture JSON + room dimensions) to disk.
/// Call [save] any time the layout mutates; call [load] on app start.
class LayoutPersistenceService {
  LayoutPersistenceService._();
  static final instance = LayoutPersistenceService._();

  static const _kFurniture = 'canvas_furniture_json';
  static const _kRoomWidth = 'canvas_room_width';
  static const _kRoomDepth = 'canvas_room_depth';

  Future<void> save({
    required String furnitureJson,
    required double roomWidthM,
    required double roomDepthM,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFurniture, furnitureJson);
    await prefs.setDouble(_kRoomWidth, roomWidthM);
    await prefs.setDouble(_kRoomDepth, roomDepthM);
  }

  Future<LayoutSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kFurniture);
    final w = prefs.getDouble(_kRoomWidth);
    final d = prefs.getDouble(_kRoomDepth);
    if (json == null || json.isEmpty) return null;
    try {
      jsonDecode(json); // validate
    } catch (_) {
      return null;
    }
    return LayoutSnapshot(
      furnitureJson: json,
      roomWidthM: w ?? 6.0,
      roomDepthM: d ?? 5.0,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFurniture);
    await prefs.remove(_kRoomWidth);
    await prefs.remove(_kRoomDepth);
  }
}

class LayoutSnapshot {
  final String furnitureJson;
  final double roomWidthM;
  final double roomDepthM;
  const LayoutSnapshot({
    required this.furnitureJson,
    required this.roomWidthM,
    required this.roomDepthM,
  });
}
