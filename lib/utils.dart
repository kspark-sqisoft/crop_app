import 'dart:math';

import 'package:flutter/material.dart';

class Utils {
  /// 랜덤 색상 생성 (알파값 20% 포함)
  static Color generateRandomColor() {
    final random = Random();
    return Color.fromARGB(
      255,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
  }
}
