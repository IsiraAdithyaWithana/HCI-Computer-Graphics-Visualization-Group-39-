import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/colour_scheme_picker.dart';

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
  static String _schemeKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:colourScheme';
  static String _canvasBgKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:canvasBg';
  static String _shapeKey(String userId, String projectId) =>
      'user:$userId:project:$projectId:roomShape';

  /// Stores the last-used {width, height, scaleFactor} per furniture type name.
  /// Global key — shared across ALL users and ALL projects so that a resize
  /// done in one project is automatically applied when the same furniture type
  /// is placed in any other project.
  static const String _typeSizeKey = 'global:typeSizes';

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
    await prefs.remove(_schemeKey(userId, projectId));
    await prefs.remove(_canvasBgKey(userId, projectId));
    // NOTE: _typeSizeKey is intentionally NOT removed — it is global across
    // ALL users and ALL projects. Deleting a project must never wipe saved
    // furniture sizes for everyone.
    await prefs.remove(_shapeKey(userId, projectId));
    // Remove from every user's shared list by scanning all keys
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (!key.endsWith(':sharedProjects')) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final hadEntry = entries.any(
          (e) => e['projectId'] == projectId && e['ownerUserId'] == userId,
        );
        if (hadEntry) {
          entries.removeWhere(
            (e) => e['projectId'] == projectId && e['ownerUserId'] == userId,
          );
          await prefs.setString(key, jsonEncode(entries));
        }
      } catch (_) {}
    }
  }

  // ── Layout (furniture + room dims) ────────────────────────────────────────

  Future<void> save({
    required String userId,
    required String projectId,
    required String furnitureJson,
    required double roomWidthM,
    required double roomDepthM,
    RoomColourScheme? colourScheme,
    Color? canvasBgColour,
    String? roomShape,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_furnitureKey(userId, projectId), furnitureJson);
    await prefs.setDouble(_widthKey(userId, projectId), roomWidthM);
    await prefs.setDouble(_depthKey(userId, projectId), roomDepthM);
    if (colourScheme != null) {
      await prefs.setString(
        _schemeKey(userId, projectId),
        jsonEncode(colourScheme.toJson()),
      );
    }
    if (canvasBgColour != null) {
      await prefs.setInt(_canvasBgKey(userId, projectId), canvasBgColour.value);
    }
    if (roomShape != null) {
      await prefs.setString(_shapeKey(userId, projectId), roomShape);
    }
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
    RoomColourScheme? scheme;
    final schemeRaw = prefs.getString(_schemeKey(userId, projectId));
    if (schemeRaw != null) {
      try {
        scheme = RoomColourScheme.fromJson(
          jsonDecode(schemeRaw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    Color? canvasBg;
    final bgVal = prefs.getInt(_canvasBgKey(userId, projectId));
    if (bgVal != null) canvasBg = Color(bgVal);
    final roomShape = prefs.getString(_shapeKey(userId, projectId));
    return LayoutSnapshot(
      furnitureJson: json,
      roomWidthM: w ?? 6.0,
      roomDepthM: d ?? 5.0,
      colourScheme: scheme,
      canvasBgColour: canvasBg,
      roomShape: roomShape,
    );
  }

  // ── Type size preferences ────────────────────────────────────────────────

  /// Saves the last-used size + scaleFactor per furniture type.
  /// [prefs] maps type name → {'w': double, 'h': double, 'sf': double}
  /// Stored under a single global key so all projects and users share it.
  Future<void> saveTypeSizes(Map<String, Map<String, double>> prefs) async {
    final sharedPrefs = await SharedPreferences.getInstance();
    await sharedPrefs.setString(_typeSizeKey, jsonEncode(prefs));
  }

  /// Loads the type size prefs. Returns an empty map if nothing saved yet.
  /// Global — not scoped to any project or user.
  Future<Map<String, Map<String, double>>> loadTypeSizes() async {
    final sharedPrefs = await SharedPreferences.getInstance();
    final raw = sharedPrefs.getString(_typeSizeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(k, {
          'w': (m['w'] as num).toDouble(),
          'h': (m['h'] as num).toDouble(),
          'sf': (m['sf'] as num).toDouble(),
        });
      });
    } catch (_) {
      return {};
    }
  }

  // ── Shared projects ───────────────────────────────────────────────────────

  static String _sharedProjectsKey(String userId) =>
      'user:$userId:sharedProjects';

  Future<List<Map<String, dynamic>>> loadSharedProjects(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sharedProjectsKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSharedProjects(
    String userId,
    List<Map<String, dynamic>> list,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sharedProjectsKey(userId), jsonEncode(list));
  }

  Future<void> shareProject({
    required String ownerUserId,
    required String projectId,
    required String targetUserId,
    required String projectName,
    required String roomType,
    required double widthM,
    required double depthM,
    required int previewColorValue,
  }) async {
    final list = await loadSharedProjects(targetUserId);
    final exists = list.any(
      (e) => e['projectId'] == projectId && e['ownerUserId'] == ownerUserId,
    );
    if (!exists) {
      list.add({
        'projectId': projectId,
        'ownerUserId': ownerUserId,
        'name': projectName,
        'roomType': roomType,
        'widthM': widthM,
        'depthM': depthM,
        'previewColorValue': previewColorValue,
      });
      await _saveSharedProjects(targetUserId, list);
    }
  }

  Future<void> unshareProject({
    required String ownerUserId,
    required String projectId,
    required String targetUserId,
  }) async {
    final list = await loadSharedProjects(targetUserId);
    list.removeWhere(
      (e) => e['projectId'] == projectId && e['ownerUserId'] == ownerUserId,
    );
    await _saveSharedProjects(targetUserId, list);
  }

  // ── Known regular users — dynamic registry ────────────────────────────────

  static const String _knownUsersKey = 'global:knownUserIds';

  static Future<void> registerUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownUsersKey);
    final list = <String>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        list.addAll((jsonDecode(raw) as List).cast<String>());
      } catch (_) {}
    }
    if (!list.contains(userId)) {
      list.add(userId);
      await prefs.setString(_knownUsersKey, jsonEncode(list));
    }
  }

  static Future<List<String>> getKnownUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownUsersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  // ── User credentials (email + password) ──────────────────────────────────
  // Stored as: global:credentials → { email: password, ... }
  // Admin credentials are hardcoded and cannot be changed via this method.

  static const String _credentialsKey = 'global:credentials';

  static Future<Map<String, String>> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_credentialsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCredentials(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_credentialsKey, jsonEncode(map));
  }

  /// Register a new user with email + password.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> createAccount(String email, String password) async {
    final e = email.trim().toLowerCase();
    // Block the hardcoded admin slot
    if (e == 'admin@gmail.com') return 'That email is reserved.';
    final creds = await _loadCredentials();
    if (creds.containsKey(e))
      return 'An account with that email already exists.';
    creds[e] = password;
    await _saveCredentials(creds);
    await registerUser(e);
    return null; // success
  }

  /// Validate credentials. Returns true if correct.
  /// Admin is checked separately via hardcoded values.
  static Future<bool> verifyPassword(String email, String password) async {
    final e = email.trim().toLowerCase();
    // Admin hardcoded
    if (e == 'admin@gmail.com') return password == 'admin123';
    final creds = await _loadCredentials();
    return creds[e] == password;
  }

  /// Check whether a user account exists.
  static Future<bool> accountExists(String email) async {
    final e = email.trim().toLowerCase();
    if (e == 'admin@gmail.com') return true;
    final creds = await _loadCredentials();
    return creds.containsKey(e);
  }

  /// Reset (change) password for an existing account.
  /// Returns null on success, error string on failure.
  static Future<String?> resetPassword(String email, String newPassword) async {
    final e = email.trim().toLowerCase();
    if (e == 'admin@gmail.com') return 'Admin password cannot be changed here.';
    final creds = await _loadCredentials();
    if (!creds.containsKey(e)) return 'No account found with that email.';
    creds[e] = newPassword;
    await _saveCredentials(creds);
    return null; // success
  }

  // ── Design Requests ───────────────────────────────────────────────────────

  static const String _requestsKey = 'global:designRequests';

  Future<List<Map<String, dynamic>>> loadRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_requestsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveRequests(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_requestsKey, jsonEncode(list));
  }

  Future<void> submitRequest({
    required String requestId,
    required String userId,
    required String userName,
    required String roomName,
    required String roomType,
    required String notes,
  }) async {
    final list = await loadRequests();
    list.add({
      'id': requestId,
      'userId': userId,
      'userName': userName,
      'roomName': roomName,
      'roomType': roomType,
      'notes': notes,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'projectId': null,
      'ownerUserId': null,
    });
    await _saveRequests(list);
  }

  Future<void> fulfillRequest({
    required String requestId,
    required String projectId,
    required String ownerUserId,
  }) async {
    final list = await loadRequests();
    final idx = list.indexWhere((r) => r['id'] == requestId);
    if (idx != -1) {
      list[idx] = {
        ...list[idx],
        'status': 'ready',
        'projectId': projectId,
        'ownerUserId': ownerUserId,
      };
      await _saveRequests(list);
    }
  }

  Future<void> deleteRequest(String requestId) async {
    final list = await loadRequests();
    list.removeWhere((r) => r['id'] == requestId);
    await _saveRequests(list);
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
  final RoomColourScheme? colourScheme;
  final Color? canvasBgColour;
  final String? roomShape;
  const LayoutSnapshot({
    required this.furnitureJson,
    required this.roomWidthM,
    required this.roomDepthM,
    this.colourScheme,
    this.canvasBgColour,
    this.roomShape,
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
