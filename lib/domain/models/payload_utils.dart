import 'package:flutter/material.dart';

class NodePayloadConverter {
  static FontWeight parseFontWeight(dynamic val) {
    if (val == null) return FontWeight.normal;
    return FontWeight.values.firstWhere(
      (e) =>
          e.value.toString() == val.toString() ||
          e.toString() == val.toString(),
      orElse: () => FontWeight.normal,
    );
  }
}
