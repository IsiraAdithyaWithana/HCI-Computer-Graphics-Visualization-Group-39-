import 'package:flutter/material.dart';

class FurnitureModel {
  String id;
  String name;
  Offset position;
  Size size;
  Color color;

  FurnitureModel({
    required this.id,
    required this.name,
    required this.position,
    required this.size,
    required this.color    
  });
}