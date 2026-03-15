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

// ── Room templates ──────────────────────────────────────────────────────────
// furnitureJson: pre-placed furniture for this template.
// Coordinates are in canvas pixels where 100px = 1 metre.
// null = empty room (user starts from scratch).

class RoomTemplate {
  final String name;
  final RoomType type;
  final double widthM;
  final double depthM;
  final String description;

  /// Pre-placed furniture JSON. If non-null this is written to the project's
  /// layout storage immediately after creation, so the room opens with
  /// furniture already arranged.
  final String? furnitureJson;

  const RoomTemplate({
    required this.name,
    required this.type,
    required this.widthM,
    required this.depthM,
    required this.description,
    this.furnitureJson,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Pre-built template furniture layouts
// 100 px = 1 metre.  id format: "type_x_y" (unique per template)
// Colors use Flutter Color.value integers (ARGB hex).
// ─────────────────────────────────────────────────────────────────────────────

// ignore: constant_identifier_names
const String _kCompactLiving = '''
[
  {"id":"sofa_160_20","type":"sofa","x":160,"y":20,"width":200,"height":80,"color":4283740581,"rotation":0,"scaleFactor":1.0},
  {"id":"armchair_30_140","type":"armchair","x":30,"y":140,"width":80,"height":80,"color":4285431354,"rotation":0,"scaleFactor":1.0},
  {"id":"armchair_390_140","type":"armchair","x":390,"y":140,"width":80,"height":80,"color":4285431354,"rotation":0,"scaleFactor":1.0},
  {"id":"coffeeTable_175_150","type":"coffeeTable","x":175,"y":150,"width":110,"height":70,"color":4283585591,"rotation":0,"scaleFactor":1.0},
  {"id":"tvStand_170_320","type":"tvStand","x":170,"y":320,"width":160,"height":50,"color":4281938255,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_10_10","type":"plant","x":10,"y":10,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"rug_130_120","type":"rug","x":130,"y":120,"width":180,"height":160,"color":4289396228,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_440_20","type":"lamp","x":440,"y":20,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kSpaciousBedroom = '''
[
  {"id":"bed_210_160","type":"bed","x":210,"y":160,"width":170,"height":220,"color":4285437131,"rotation":0,"scaleFactor":1.0},
  {"id":"nightstand_155_180","type":"nightstand","x":155,"y":180,"width":50,"height":50,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"nightstand_385_180","type":"nightstand","x":385,"y":180,"width":50,"height":50,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"wardrobe_20_20","type":"wardrobe","x":20,"y":20,"width":160,"height":55,"color":4283188782,"rotation":0,"scaleFactor":1.0},
  {"id":"desk_420_20","type":"desk","x":420,"y":20,"width":140,"height":65,"color":4283716218,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_450_90","type":"chair","x":450,"y":90,"width":60,"height":60,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_555_20","type":"plant","x":555,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_10_160","type":"lamp","x":10,"y":160,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0},
  {"id":"rug_190_230","type":"rug","x":190,"y":230,"width":200,"height":120,"color":4289396228,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kStudioOffice = '''
[
  {"id":"desk_20_20","type":"desk","x":20,"y":20,"width":180,"height":70,"color":4283716218,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_80_95","type":"chair","x":80,"y":95,"width":60,"height":60,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_20_180","type":"bookshelf","x":20,"y":180,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_20_225","type":"bookshelf","x":20,"y":225,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_290_20","type":"cabinet","x":290,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_390_20","type":"plant","x":390,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"sofa_220_220","type":"sofa","x":220,"y":220,"width":170,"height":75,"color":4283740581,"rotation":0,"scaleFactor":1.0},
  {"id":"coffeeTable_235_300","type":"coffeeTable","x":235,"y":300,"width":90,"height":50,"color":4283585591,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_10_290","type":"lamp","x":10,"y":290,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kLShapeKitchen = '''
[
  {"id":"cabinet_20_20","type":"cabinet","x":20,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_110_20","type":"cabinet","x":110,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_200_20","type":"cabinet","x":200,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_20_80","type":"cabinet","x":20,"y":80,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_110_80","type":"cabinet","x":110,"y":80,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_200_80","type":"cabinet","x":200,"y":80,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_300_20","type":"cabinet","x":300,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"sideTable_340_150","type":"sideTable","x":340,"y":150,"width":80,"height":80,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"table_450_220","type":"table","x":450,"y":220,"width":140,"height":90,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_430_170","type":"chair","x":430,"y":170,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_515_170","type":"chair","x":515,"y":170,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_430_315","type":"chair","x":430,"y":315,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_515_315","type":"chair","x":515,"y":315,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_640_20","type":"plant","x":640,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kCosyDining = '''
[
  {"id":"table_175_150","type":"table","x":175,"y":150,"width":150,"height":100,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_155_105","type":"chair","x":155,"y":105,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_245_105","type":"chair","x":245,"y":105,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_155_255","type":"chair","x":155,"y":255,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"chair_245_255","type":"chair","x":245,"y":255,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"chair_90_165","type":"chair","x":90,"y":165,"width":55,"height":55,"color":4284770119,"rotation":1.5708,"scaleFactor":1.0},
  {"id":"chair_355_165","type":"chair","x":355,"y":165,"width":55,"height":55,"color":4284770119,"rotation":-1.5708,"scaleFactor":1.0},
  {"id":"cabinet_20_20","type":"cabinet","x":20,"y":20,"width":100,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_130_20","type":"cabinet","x":130,"y":20,"width":100,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_440_20","type":"plant","x":440,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_10_330","type":"lamp","x":10,"y":330,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kGrandLivingRoom = '''
[
  {"id":"sofa_250_30","type":"sofa","x":250,"y":30,"width":260,"height":90,"color":4283740581,"rotation":0,"scaleFactor":1.0},
  {"id":"sofa_30_80","type":"sofa","x":30,"y":80,"width":90,"height":200,"color":4283740581,"rotation":1.5708,"scaleFactor":1.0},
  {"id":"armchair_740_100","type":"armchair","x":740,"y":100,"width":90,"height":90,"color":4285431354,"rotation":0,"scaleFactor":1.0},
  {"id":"armchair_740_200","type":"armchair","x":740,"y":200,"width":90,"height":90,"color":4285431354,"rotation":0,"scaleFactor":1.0},
  {"id":"coffeeTable_310_170","type":"coffeeTable","x":310,"y":170,"width":140,"height":90,"color":4283585591,"rotation":0,"scaleFactor":1.0},
  {"id":"tvStand_300_450","type":"tvStand","x":300,"y":450,"width":220,"height":55,"color":4281938255,"rotation":0,"scaleFactor":1.0},
  {"id":"table_570_480","type":"table","x":570,"y":480,"width":180,"height":110,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_555_440","type":"chair","x":555,"y":440,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_640_440","type":"chair","x":640,"y":440,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_555_600","type":"chair","x":555,"y":600,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"chair_640_600","type":"chair","x":640,"y":600,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"bookshelf_20_20","type":"bookshelf","x":20,"y":20,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_20_70","type":"bookshelf","x":20,"y":70,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_830_20","type":"plant","x":830,"y":20,"width":50,"height":50,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_830_630","type":"plant","x":830,"y":630,"width":50,"height":50,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"rug_230_120","type":"rug","x":230,"y":120,"width":300,"height":200,"color":4289396228,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_10_530","type":"lamp","x":10,"y":530,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kKidsBedroom = '''
[
  {"id":"singleBed_20_20","type":"singleBed","x":20,"y":20,"width":100,"height":200,"color":4285437131,"rotation":0,"scaleFactor":1.0},
  {"id":"nightstand_130_20","type":"nightstand","x":130,"y":20,"width":45,"height":45,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"desk_200_20","type":"desk","x":200,"y":20,"width":140,"height":65,"color":4283716218,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_230_90","type":"chair","x":230,"y":90,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_20_240","type":"bookshelf","x":20,"y":240,"width":100,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"wardrobe_270_240","type":"wardrobe","x":270,"y":240,"width":110,"height":50,"color":4283188782,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_350_20","type":"plant","x":350,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"rug_130_160","type":"rug","x":130,"y":160,"width":120,"height":100,"color":4289396228,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kHomeStudio = '''
[
  {"id":"desk_20_20","type":"desk","x":20,"y":20,"width":200,"height":75,"color":4283716218,"rotation":0,"scaleFactor":1.0},
  {"id":"desk_20_100","type":"desk","x":20,"y":100,"width":75,"height":150,"color":4283716218,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_100_90","type":"chair","x":100,"y":90,"width":65,"height":65,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_300_20","type":"bookshelf","x":300,"y":20,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"bookshelf_300_70","type":"bookshelf","x":300,"y":70,"width":120,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"sofa_270_310","type":"sofa","x":270,"y":310,"width":180,"height":75,"color":4283740581,"rotation":0,"scaleFactor":1.0},
  {"id":"coffeeTable_290_240","type":"coffeeTable","x":290,"y":240,"width":110,"height":60,"color":4283585591,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_20_300","type":"cabinet","x":20,"y":300,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_490_20","type":"plant","x":490,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_490_390","type":"plant","x":490,"y":390,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"lamp_490_290","type":"lamp","x":490,"y":290,"width":40,"height":60,"color":4294945829,"rotation":0,"scaleFactor":1.0}
]''';

// ignore: constant_identifier_names
const String _kOpenKitchen = '''
[
  {"id":"cabinet_20_20","type":"cabinet","x":20,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_110_20","type":"cabinet","x":110,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_200_20","type":"cabinet","x":200,"y":20,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_20_80","type":"cabinet","x":20,"y":80,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"cabinet_110_80","type":"cabinet","x":110,"y":80,"width":80,"height":55,"color":4283650148,"rotation":0,"scaleFactor":1.0},
  {"id":"sideTable_220_170","type":"sideTable","x":220,"y":170,"width":120,"height":100,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"stool_240_130","type":"stool","x":240,"y":130,"width":50,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"stool_300_130","type":"stool","x":300,"y":130,"width":50,"height":40,"color":4284503617,"rotation":0,"scaleFactor":1.0},
  {"id":"table_380_300","type":"table","x":380,"y":300,"width":150,"height":100,"color":4285164579,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_360_255","type":"chair","x":360,"y":255,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_440_255","type":"chair","x":440,"y":255,"width":55,"height":55,"color":4284770119,"rotation":0,"scaleFactor":1.0},
  {"id":"chair_360_405","type":"chair","x":360,"y":405,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"chair_440_405","type":"chair","x":440,"y":405,"width":55,"height":55,"color":4284770119,"rotation":3.14159,"scaleFactor":1.0},
  {"id":"plant_540_20","type":"plant","x":540,"y":20,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0},
  {"id":"plant_540_440","type":"plant","x":540,"y":440,"width":40,"height":40,"color":4280433724,"rotation":0,"scaleFactor":1.0}
]''';

// ─────────────────────────────────────────────────────────────────────────────
// Template catalogue — shown on Dashboard Templates page and Home page
// ─────────────────────────────────────────────────────────────────────────────

const List<RoomTemplate> kRoomTemplates = [
  RoomTemplate(
    name: 'Compact Living',
    type: RoomType.livingRoom,
    widthM: 5.0,
    depthM: 4.0,
    description: 'Perfect for apartments',
    furnitureJson: _kCompactLiving,
  ),
  RoomTemplate(
    name: 'Spacious Bedroom',
    type: RoomType.bedroom,
    widthM: 6.0,
    depthM: 5.0,
    description: 'Master suite layout',
    furnitureJson: _kSpaciousBedroom,
  ),
  RoomTemplate(
    name: 'Studio Office',
    type: RoomType.office,
    widthM: 4.5,
    depthM: 3.5,
    description: 'Productive workspace',
    furnitureJson: _kStudioOffice,
  ),
  RoomTemplate(
    name: 'L-Shape Kitchen',
    type: RoomType.kitchen,
    widthM: 7.0,
    depthM: 5.5,
    description: 'Open-plan friendly',
    furnitureJson: _kLShapeKitchen,
  ),
  RoomTemplate(
    name: 'Cosy Dining',
    type: RoomType.diningRoom,
    widthM: 5.0,
    depthM: 4.0,
    description: 'Intimate dining space',
    furnitureJson: _kCosyDining,
  ),
  RoomTemplate(
    name: 'Grand Living Room',
    type: RoomType.livingRoom,
    widthM: 9.0,
    depthM: 7.0,
    description: 'Open-plan living',
    furnitureJson: _kGrandLivingRoom,
  ),
  RoomTemplate(
    name: 'Kids Bedroom',
    type: RoomType.bedroom,
    widthM: 4.0,
    depthM: 3.5,
    description: 'Fun and functional',
    furnitureJson: _kKidsBedroom,
  ),
  RoomTemplate(
    name: 'Home Studio',
    type: RoomType.office,
    widthM: 5.5,
    depthM: 4.5,
    description: 'Creative workspace',
    furnitureJson: _kHomeStudio,
  ),
  RoomTemplate(
    name: 'Open Kitchen',
    type: RoomType.kitchen,
    widthM: 6.0,
    depthM: 5.0,
    description: 'Island kitchen layout',
    furnitureJson: _kOpenKitchen,
  ),
  RoomTemplate(
    name: 'Master Bathroom',
    type: RoomType.bathroom,
    widthM: 4.0,
    depthM: 3.5,
    description: 'Luxury en-suite',
    furnitureJson: null, // intentionally empty — bathrooms have custom fixtures
  ),
];
