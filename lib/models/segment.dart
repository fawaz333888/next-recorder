import 'package:flutter/foundation.dart';

@immutable
class Segment {
  const Segment({
    required this.id,
    required this.filePath,
    required this.durationMs,
    required this.createdAt,
  });

  final int id;
  final String filePath;
  final int durationMs;
  final DateTime createdAt;

  String get label => 'Segmen $id';
}
