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

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'durationMs': durationMs,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Segment.fromJson(Map<String, dynamic> json) => Segment(
        id: json['id'] as int,
        filePath: json['filePath'] as String,
        durationMs: json['durationMs'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
