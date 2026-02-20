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
}
