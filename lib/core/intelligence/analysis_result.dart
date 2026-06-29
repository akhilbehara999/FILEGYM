import 'package:flutter/material.dart';

class AvailableConversion {
  final String format;
  final IconData icon;
  final Color color;

  AvailableConversion({
    required this.format,
    required this.icon,
    required this.color,
  });
}

class AnalysisResult {
  final String fileName;
  final String trueType;
  final String trueMimeType;
  final double confidenceScore;
  final String fileSize;
  final bool isSafe;
  final String? anomalyWarning;
  final List<AvailableConversion> availableConversions;
  final Map<String, String> metadata;

  AnalysisResult({
    required this.fileName,
    required this.trueType,
    required this.trueMimeType,
    required this.confidenceScore,
    required this.fileSize,
    required this.isSafe,
    this.anomalyWarning,
    required this.availableConversions,
    required this.metadata,
  });
}
