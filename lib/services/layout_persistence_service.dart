import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists layouts and project metadata to disk.
/// All data is namespaced by [userId] so multiple users can coexist.
///
/// Key schema:
///   user:{userId}:projects                      → JSON array of PersistedProject
///   user:{userId}:project:{id}:furniture        → furniture JSON string
///   user:{userId}:project:{id}:roomWidth        → double
///   user:{userId}:project:{id}:roomDepth        → double
class LayoutPersistenceService {
  LayoutPersistenceService._();
  static final instance = LayoutPersistenceService._();

  static String _projectsKey(String userId) => 'user:$userId:projects';
  static String _furnitureKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:furniture';
  static String _widthKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:roomWidth';
  static String _depthKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:roomDepth';

  // ── Project list ──────────────────────────────────────────────────────────

  Future<List<PersistedProject>> loadProjects(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectsKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PersistedProject.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProjects(
    String userId,
    List<PersistedProject> projects,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _projectsKey(userId),
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> upsertProject(String userId, PersistedProject project) async {
    final list = await loadProjects(userId);
    final idx = list.indexWhere((p) => p.id == project.id);
    if (idx == -1) {
      list.add(project);
    } else {
      list[idx] = project;
    }
    await saveProjects(userId, list);
  }

  Future<void> deleteProject(String userId, String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadProjects(userId);
    list.removeWhere((p) => p.id == projectId);
    await saveProjects(userId, list);
    await prefs.remove(_furnitureKey(userId, projectId));
    await prefs.remove(_widthKey(userId, projectId));
    await prefs.remove(_depthKey(userId, projectId));
  }

  // ── Layout (furniture + room dims) ────────────────────────────────────────

  Future<void> save({
    required String userId,
    required String projectId,
    required String furnitureJson,
    required double roomWidthM,
    required double roomDepthM,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_furnitureKey(userId, projectId), furnitureJson);
    await prefs.setDouble(_widthKey(userId, projectId), roomWidthM);
    await prefs.setDouble(_depthKey(userId, projectId), roomDepthM);
  }

  Future<LayoutSnapshot?> load({
    required String userId,
    required String projectId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_furnitureKey(userId, projectId));
    final w = prefs.getDouble(_widthKey(userId, projectId));
    final d = prefs.getDouble(_depthKey(userId, projectId));
    if (json == null || json.isEmpty) return null;
    try {
      jsonDecode(json);
    } catch (_) {
      return null;
    }
    return LayoutSnapshot(
      furnitureJson: json,
      roomWidthM: w ?? 6.0,
      roomDepthM: d ?? 5.0,
    );
  }

  /// Legacy single-slot load — for migrating old saves.
  Future<LayoutSnapshot?> loadLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('canvas_furniture_json');
    final w = prefs.getDouble('canvas_room_width');
    final d = prefs.getDouble('canvas_room_depth');
    if (json == null || json.isEmpty) return null;
    try {
      jsonDecode(json);
    } catch (_) {
      return null;
    }
    return LayoutSnapshot(
      furnitureJson: json,
      roomWidthM: w ?? 6.0,
      roomDepthM: d ?? 5.0,
    );
  }
}

// ── Data classes ─────────────────────────────────────────────────────────────

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

class PersistedProject {
  final String id;
  final String name;
  final String roomType; // RoomType.name string
  final double widthM;
  final double depthM;
  final int furnitureCount;
  final DateTime lastModified;
  final DateTime createdAt;
  final bool isFavorite;
  final int previewColorValue;

  const PersistedProject({
    required this.id,
    required this.name,
    required this.roomType,
    required this.widthM,
    required this.depthM,
    required this.furnitureCount,
    required this.lastModified,
    required this.createdAt,
    this.isFavorite = false,
    required this.previewColorValue,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'roomType': roomType,
    'widthM': widthM,
    'depthM': depthM,
    'furnitureCount': furnitureCount,
    'lastModified': lastModified.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'isFavorite': isFavorite,
    'previewColorValue': previewColorValue,
  };

  factory PersistedProject.fromJson(Map<String, dynamic> j) => PersistedProject(
    id: j['id'] as String,
    name: j['name'] as String,
    roomType: j['roomType'] as String? ?? 'other',
    widthM: (j['widthM'] as num).toDouble(),
    depthM: (j['depthM'] as num).toDouble(),
    furnitureCount: (j['furnitureCount'] as num?)?.toInt() ?? 0,
    lastModified: DateTime.parse(j['lastModified'] as String),
    createdAt: DateTime.parse(j['createdAt'] as String),
    isFavorite: j['isFavorite'] as bool? ?? false,
    previewColorValue: (j['previewColorValue'] as num?)?.toInt() ?? 0xFF7C9A92,
  );

  PersistedProject copyWith({
    String? name,
    double? widthM,
    double? depthM,
    int? furnitureCount,
    DateTime? lastModified,
    bool? isFavorite,
  }) => PersistedProject(
    id: id,
    name: name ?? this.name,
    roomType: roomType,
    widthM: widthM ?? this.widthM,
    depthM: depthM ?? this.depthM,
    furnitureCount: furnitureCount ?? this.furnitureCount,
    lastModified: lastModified ?? this.lastModified,
    createdAt: createdAt,
    isFavorite: isFavorite ?? this.isFavorite,
    previewColorValue: previewColorValue,
  );
}
