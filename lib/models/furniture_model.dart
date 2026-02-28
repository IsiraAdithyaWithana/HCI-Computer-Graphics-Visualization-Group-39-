import 'package:flutter/material.dart';

// ── All furniture types ────────────────────────────────────────────────────
enum FurnitureType {
  // Seating
  chair,
  sofa,
  armchair,
  bench,
  stool,
  // Tables
  table,
  coffeeTable,
  desk,
  sideTable,
  // Storage
  wardrobe,
  bookshelf,
  cabinet,
  dresser,
  // Bedroom
  bed,
  singleBed,
  nightstand,
  // Decor
  plant,
  lamp,
  tvStand,
  rug,
}

// ── Category + item descriptors ────────────────────────────────────────────
class FurnitureCategory {
  final String name;
  final IconData icon;
  final Color color;
  final List<FurnitureCategoryItem> items;
  const FurnitureCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class FurnitureCategoryItem {
  final FurnitureType type;
  final String label;
  final IconData icon;
  const FurnitureCategoryItem({
    required this.type,
    required this.label,
    required this.icon,
  });
}

// ── Master category list ───────────────────────────────────────────────────
const List<FurnitureCategory> kFurnitureCategories = [
  FurnitureCategory(
    name: 'Seating',
    icon: Icons.chair,
    color: Color(0xFF7C5CBF),
    items: [
      FurnitureCategoryItem(
        type: FurnitureType.chair,
        label: 'Chair',
        icon: Icons.chair,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.sofa,
        label: 'Sofa',
        icon: Icons.weekend,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.armchair,
        label: 'Armchair',
        icon: Icons.chair_alt,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.bench,
        label: 'Bench',
        icon: Icons.deck,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.stool,
        label: 'Stool',
        icon: Icons.airline_seat_recline_normal,
      ),
    ],
  ),
  FurnitureCategory(
    name: 'Tables',
    icon: Icons.table_restaurant,
    color: Color(0xFF1976D2),
    items: [
      FurnitureCategoryItem(
        type: FurnitureType.table,
        label: 'Dining Table',
        icon: Icons.table_restaurant,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.coffeeTable,
        label: 'Coffee Table',
        icon: Icons.coffee,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.desk,
        label: 'Desk',
        icon: Icons.desktop_windows,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.sideTable,
        label: 'Side Table',
        icon: Icons.crop_square,
      ),
    ],
  ),
  FurnitureCategory(
    name: 'Storage',
    icon: Icons.door_sliding,
    color: Color(0xFF388E3C),
    items: [
      FurnitureCategoryItem(
        type: FurnitureType.wardrobe,
        label: 'Wardrobe',
        icon: Icons.door_sliding,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.bookshelf,
        label: 'Bookshelf',
        icon: Icons.menu_book,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.cabinet,
        label: 'Cabinet',
        icon: Icons.kitchen,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.dresser,
        label: 'Dresser',
        icon: Icons.space_dashboard,
      ),
    ],
  ),
  FurnitureCategory(
    name: 'Bedroom',
    icon: Icons.bed,
    color: Color(0xFFE64A19),
    items: [
      FurnitureCategoryItem(
        type: FurnitureType.bed,
        label: 'Double Bed',
        icon: Icons.bed,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.singleBed,
        label: 'Single Bed',
        icon: Icons.single_bed,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.nightstand,
        label: 'Nightstand',
        icon: Icons.bedtime,
      ),
    ],
  ),
  FurnitureCategory(
    name: 'Decor',
    icon: Icons.local_florist,
    color: Color(0xFF00796B),
    items: [
      FurnitureCategoryItem(
        type: FurnitureType.plant,
        label: 'Plant',
        icon: Icons.local_florist,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.lamp,
        label: 'Floor Lamp',
        icon: Icons.light,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.tvStand,
        label: 'TV Stand',
        icon: Icons.tv,
      ),
      FurnitureCategoryItem(
        type: FurnitureType.rug,
        label: 'Rug',
        icon: Icons.texture,
      ),
    ],
  ),
];

// ── Data model ─────────────────────────────────────────────────────────────
class FurnitureModel {
  final String id;
  final FurnitureType type;
  Offset position;
  Size size;
  Color color;
  double rotation;

  FurnitureModel({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    required this.color,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'x': position.dx,
    'y': position.dy,
    'width': size.width,
    'height': size.height,
    'color': color.value,
    'rotation': rotation,
  };

  factory FurnitureModel.fromJson(Map<String, dynamic> json) => FurnitureModel(
    id: json['id'] as String,
    type: FurnitureType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => FurnitureType.chair,
    ),
    position: Offset(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    ),
    size: Size(
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    ),
    color: Color(json['color'] as int),
    rotation: (json['rotation'] as num).toDouble(),
  );
}
