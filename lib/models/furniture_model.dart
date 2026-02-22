import 'package:flutter/material.dart';

enum FurnitureType { chair, table, sofa }

class FurnitureModel {
  String id;
  FurnitureType type;
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

  factory FurnitureModel.fromJson(Map<String, dynamic> json) {
    return FurnitureModel(
      id: json['id'],
      type: FurnitureType.values.firstWhere((e) => e.name == json['type']),
      position: Offset(json['x'], json['y']),
      size: Size(json['width'], json['height']),
      color: Color(json['color']),
      rotation: json['rotation'],
    );
  }
}
