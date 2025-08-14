import 'package:flutter/material.dart';

class CropRegion {
  final int id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final Color color;

  CropRegion({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.color,
  });

  CropRegion copyWith({
    int? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    Color? color,
  }) {
    return CropRegion(
      id: id ?? this.id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      color: color ?? this.color,
    );
  }

  @override
  String toString() {
    return 'CropRegion(id: $id, name: $name, x: $x, y: $y, width: $width, height: $height, color: $color)';
  }
}
