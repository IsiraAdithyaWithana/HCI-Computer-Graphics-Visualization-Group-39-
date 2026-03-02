import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DesignProject — data model for a saved room design
// ─────────────────────────────────────────────────────────────────────────────

enum RoomType {
  livingRoom,
  bedroom,
  kitchen,
  office,
  diningRoom,
  bathroom,
  other,
}

extension RoomTypeExt on RoomType {
  String get label {
    switch (this) {
      case RoomType.livingRoom:
        return 'Living Room';
      case RoomType.bedroom:
        return 'Bedroom';
      case RoomType.kitchen:
        return 'Kitchen';
      case RoomType.office:
        return 'Home Office';
      case RoomType.diningRoom:
        return 'Dining Room';
      case RoomType.bathroom:
        return 'Bathroom';
      case RoomType.other:
        return 'Custom Room';
    }
  }

  IconData get icon {
    switch (this) {
      case RoomType.livingRoom:
        return Icons.weekend_outlined;
      case RoomType.bedroom:
        return Icons.bed_outlined;
      case RoomType.kitchen:
        return Icons.kitchen_outlined;
      case RoomType.office:
        return Icons.computer_outlined;
      case RoomType.diningRoom:
        return Icons.table_restaurant_outlined;
      case RoomType.bathroom:
        return Icons.bathtub_outlined;
      case RoomType.other:
        return Icons.grid_view_outlined;
    }
  }

  Color get color {
    switch (this) {
      case RoomType.livingRoom:
        return const Color(0xFF7C9A92);
      case RoomType.bedroom:
        return const Color(0xFF9A7C8E);
      case RoomType.kitchen:
        return const Color(0xFFB8956A);
      case RoomType.office:
        return const Color(0xFF6A82B8);
      case RoomType.diningRoom:
        return const Color(0xFF8EA87C);
      case RoomType.bathroom:
        return const Color(0xFF6AA8B8);
      case RoomType.other:
        return const Color(0xFFB86A6A);
    }
  }
}

class DesignProject {
  final String id;
  final String name;
  final RoomType roomType;
  final double widthM;
  final double depthM;
  final int furnitureCount;
  final DateTime lastModified;
  final DateTime createdAt;
  final bool isFavorite;
  final Color previewColor;

  const DesignProject({
    required this.id,
    required this.name,
    required this.roomType,
    required this.widthM,
    required this.depthM,
    required this.furnitureCount,
    required this.lastModified,
    required this.createdAt,
    this.isFavorite = false,
    required this.previewColor,
  });

  String get dimensions =>
      '${widthM.toStringAsFixed(1)} × ${depthM.toStringAsFixed(1)} m';

  String get timeAgo {
    final diff = DateTime.now().difference(lastModified);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${lastModified.day}/${lastModified.month}/${lastModified.year}';
  }

  DesignProject copyWith({bool? isFavorite}) => DesignProject(
    id: id,
    name: name,
    roomType: roomType,
    widthM: widthM,
    depthM: depthM,
    furnitureCount: furnitureCount,
    lastModified: lastModified,
    createdAt: createdAt,
    isFavorite: isFavorite ?? this.isFavorite,
    previewColor: previewColor,
  );
}

// ── Sample projects for dashboard demo ────────────────────────────────────────

final List<DesignProject> kSampleProjects = [
  DesignProject(
    id: 'p1',
    name: 'Main Living Area',
    roomType: RoomType.livingRoom,
    widthM: 7.5,
    depthM: 5.0,
    furnitureCount: 12,
    lastModified: DateTime.now().subtract(const Duration(hours: 2)),
    createdAt: DateTime.now().subtract(const Duration(days: 14)),
    isFavorite: true,
    previewColor: const Color(0xFF7C9A92),
  ),
  DesignProject(
    id: 'p2',
    name: 'Master Bedroom',
    roomType: RoomType.bedroom,
    widthM: 5.5,
    depthM: 4.5,
    furnitureCount: 8,
    lastModified: DateTime.now().subtract(const Duration(days: 1)),
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
    isFavorite: false,
    previewColor: const Color(0xFF9A7C8E),
  ),
  DesignProject(
    id: 'p3',
    name: 'Home Office',
    roomType: RoomType.office,
    widthM: 4.0,
    depthM: 3.5,
    furnitureCount: 6,
    lastModified: DateTime.now().subtract(const Duration(days: 3)),
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
    isFavorite: true,
    previewColor: const Color(0xFF6A82B8),
  ),
  DesignProject(
    id: 'p4',
    name: 'Open Kitchen',
    roomType: RoomType.kitchen,
    widthM: 6.0,
    depthM: 4.0,
    furnitureCount: 10,
    lastModified: DateTime.now().subtract(const Duration(days: 5)),
    createdAt: DateTime.now().subtract(const Duration(days: 20)),
    isFavorite: false,
    previewColor: const Color(0xFFB8956A),
  ),
  DesignProject(
    id: 'p5',
    name: 'Dining Room',
    roomType: RoomType.diningRoom,
    widthM: 5.0,
    depthM: 4.0,
    furnitureCount: 7,
    lastModified: DateTime.now().subtract(const Duration(days: 8)),
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
    isFavorite: false,
    previewColor: const Color(0xFF8EA87C),
  ),
];

// ── Room templates ──────────────────────────────────────────────────────────

class RoomTemplate {
  final String name;
  final RoomType type;
  final double widthM;
  final double depthM;
  final String description;

  const RoomTemplate({
    required this.name,
    required this.type,
    required this.widthM,
    required this.depthM,
    required this.description,
  });
}

const List<RoomTemplate> kRoomTemplates = [
  RoomTemplate(
    name: 'Compact Living',
    type: RoomType.livingRoom,
    widthM: 5.0,
    depthM: 4.0,
    description: 'Perfect for apartments',
  ),
  RoomTemplate(
    name: 'Spacious Bedroom',
    type: RoomType.bedroom,
    widthM: 6.0,
    depthM: 5.0,
    description: 'Master suite layout',
  ),
  RoomTemplate(
    name: 'Studio Office',
    type: RoomType.office,
    widthM: 4.5,
    depthM: 3.5,
    description: 'Productive workspace',
  ),
  RoomTemplate(
    name: 'L-Shape Kitchen',
    type: RoomType.kitchen,
    widthM: 7.0,
    depthM: 5.5,
    description: 'Open-plan friendly',
  ),
];
