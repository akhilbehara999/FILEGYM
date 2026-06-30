import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mime/mime.dart';

import 'analysis_result.dart';

class FileIntelligenceEngine {
  static Future<AnalysisResult> analyze(String filePath) async {
    final isBatchImages = filePath.contains(';');
    if (isBatchImages) {
      final paths = filePath.split(';');
      for (final p in paths) {
        if (!await File(p).exists()) {
          throw Exception('File does not exist: $p');
        }
      }
      int totalBytes = 0;
      for (final p in paths) {
        totalBytes += await File(p).length();
      }
      final sizeString = _formatBytes(totalBytes, 1);
      final count = paths.length;
      return AnalysisResult(
        fileName: '$count Images Batch',
        trueType: 'Batch Images',
        trueMimeType: 'image/jpeg',
        confidenceScore: 0.99,
        fileSize: sizeString,
        isSafe: true,
        availableConversions: [
          AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        ],
        metadata: {
          'Total Images': count.toString(),
          'Format': 'Multi-page PDF',
        },
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final int sizeInBytes = await file.length();
    final String sizeString = _formatBytes(sizeInBytes, 1);
    final String fileName = filePath.split(Platform.pathSeparator).last;
    final String extension = fileName.contains('.') 
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() 
        : '';

    // Read first 200 bytes for magic number & ASCII header analysis
    final magicBytes = await _readMagicBytes(file);

    String trueType = 'Unknown File';
    String trueMimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    double confidence = 0.50;
    bool isSafe = true; // Simple security scan mock
    String? anomalyWarning;

    if (_isPDF(magicBytes)) {
      trueType = 'PDF Document';
      trueMimeType = 'application/pdf';
      confidence = 0.99;
      if (extension != 'pdf') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually a PDF.';
        confidence = 0.85;
      }
    } else if (_isPNG(magicBytes)) {
      trueType = 'PNG Image';
      trueMimeType = 'image/png';
      confidence = 0.99;
      if (extension != 'png') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually a PNG image.';
        confidence = 0.85;
      }
    } else if (_isJPG(magicBytes)) {
      trueType = 'JPG Image';
      trueMimeType = 'image/jpeg';
      confidence = 0.99;
      if (extension != 'jpg' && extension != 'jpeg') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually a JPG image.';
        confidence = 0.85;
      }
    } else if (_isWEBP(magicBytes)) {
      trueType = 'WEBP Image';
      trueMimeType = 'image/webp';
      confidence = 0.99;
      if (extension != 'webp') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually a WEBP image.';
        confidence = 0.85;
      }
    } else if (_isICO(magicBytes)) {
      trueType = 'ICO Image';
      trueMimeType = 'image/x-icon';
      confidence = 0.99;
      if (extension != 'ico') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually a Windows Icon.';
        confidence = 0.85;
      }
    } else if (_isSVG(magicBytes)) {
      trueType = 'SVG Image';
      trueMimeType = 'image/svg+xml';
      confidence = 0.99;
      if (extension != 'svg') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually an SVG Vector.';
        confidence = 0.85;
      }
    } else if (_isHEIC(magicBytes)) {
      trueType = 'HEIC Image';
      trueMimeType = 'image/heic';
      confidence = 0.99;
      if (extension != 'heic' && extension != 'heif') {
        anomalyWarning = 'Extension mismatch. File claims to be .$extension but is actually an HEIC image.';
        confidence = 0.85;
      }
    } else if (_isZIP(magicBytes)) {
      // DOCX, XLSX, PPTX, APK, ZIP all share the ZIP magic byte.
      trueType = 'ZIP Archive';
      trueMimeType = 'application/zip';
      confidence = 0.90;
      
      if (extension == 'docx') {
        trueType = 'Word Document (DOCX)';
        trueMimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        confidence = 0.95;
      } else if (extension == 'xlsx') {
        trueType = 'Excel Spreadsheet (XLSX)';
        trueMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        confidence = 0.95;
      } else if (extension == 'pptx') {
        trueType = 'PowerPoint Presentation (PPTX)';
        trueMimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        confidence = 0.95;
      } else if (extension == 'apk') {
        trueType = 'Android Package (APK)';
        trueMimeType = 'application/vnd.android.package-archive';
        confidence = 0.95;
      }
    } else {
      // Fallback to extension if magic bytes are unknown
      if (extension == 'txt') {
        trueType = 'Text Document';
        trueMimeType = 'text/plain';
        confidence = 0.70;
      } else if (extension == 'csv') {
        trueType = 'CSV Data';
        trueMimeType = 'text/csv';
        confidence = 0.70;
      } else if (extension == 'md' || extension == 'markdown') {
        trueType = 'Markdown Document';
        trueMimeType = 'text/markdown';
        confidence = 0.70;
      } else if (extension == 'json') {
        trueType = 'JSON Data';
        trueMimeType = 'application/json';
        confidence = 0.70;
      } else if (extension == 'webp') {
        trueType = 'WEBP Image';
        trueMimeType = 'image/webp';
        confidence = 0.70;
      } else if (extension == 'ico') {
        trueType = 'ICO Image';
        trueMimeType = 'image/x-icon';
        confidence = 0.70;
      } else if (extension == 'svg') {
        trueType = 'SVG Image';
        trueMimeType = 'image/svg+xml';
        confidence = 0.70;
      } else if (extension == 'pptx') {
        trueType = 'PowerPoint Presentation (PPTX)';
        trueMimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        confidence = 0.70;
      } else if (extension == 'heic' || extension == 'heif') {
        trueType = 'HEIC Image';
        trueMimeType = 'image/heic';
        confidence = 0.70;
      } else if (extension == 'xls') {
        trueType = 'Legacy Excel Spreadsheet (XLS)';
        trueMimeType = 'application/vnd.ms-excel';
        confidence = 0.80;
      } else if (extension == 'doc') {
        trueType = 'Legacy Word Document (DOC)';
        trueMimeType = 'application/msword';
        confidence = 0.80;
      } else if (extension == 'ppt') {
        trueType = 'Legacy PowerPoint Presentation (PPT)';
        trueMimeType = 'application/vnd.ms-powerpoint';
        confidence = 0.80;
      }
    }
 
    // Determine available conversions based on true type
    final availableConversions = _getAvailableConversions(trueType);
    
    // Generate metadata based on type
    final Map<String, String> metadata = _generateMetadata(trueType, sizeString);
 
    // Simulate scan loading time
    await Future.delayed(const Duration(milliseconds: 1000));
 
    return AnalysisResult(
      fileName: fileName,
      trueType: trueType,
      trueMimeType: trueMimeType,
      confidenceScore: confidence,
      fileSize: sizeString,
      isSafe: isSafe,
      anomalyWarning: anomalyWarning,
      availableConversions: availableConversions,
      metadata: metadata,
    );
  }
 
  static Future<List<int>> _readMagicBytes(File file) async {
    try {
      final stream = file.openRead(0, 200);
      final bytes = <int>[];
      await for (var chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length >= 200) break;
      }
      return bytes;
    } catch (e) {
      return [];
    }
  }
 
  static bool _isPDF(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  }
 
  static bool _isPNG(List<int> bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
           bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
  }
 
  static bool _isJPG(List<int> bytes) {
    if (bytes.length < 3) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }
 
  static bool _isWEBP(List<int> bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
  }
 
  static bool _isICO(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01 && bytes[3] == 0x00;
  }
 
  static bool _isSVG(List<int> bytes) {
    if (bytes.length < 5) return false;
    // Reject ZIP magic signature (PK) early to avoid false matching on Office zip documents
    if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      return false;
    }
    final str = String.fromCharCodes(bytes).toLowerCase();
    return str.contains('<svg');
  }

  static bool _isHEIC(List<int> bytes) {
    if (bytes.length < 12) return false;
    // Check if it has "ftyp" signature
    if (bytes[4] != 0x66 || bytes[5] != 0x74 || bytes[6] != 0x79 || bytes[7] != 0x70) return false;
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    return brand.startsWith('heic') || brand.startsWith('heix') || brand.startsWith('hevc') || 
           brand.startsWith('mif1') || brand.startsWith('msf1');
  }
 
  static bool _isZIP(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }
 
  static String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }
 
  static List<AvailableConversion> _getAvailableConversions(String trueType) {
    final t = trueType.toLowerCase();
    if (t.contains('legacy')) {
      return [];
    }
    if (t.contains('pdf')) {
      return [
        AvailableConversion(format: 'DOCX', icon: LucideIcons.fileText, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'XLSX', icon: LucideIcons.table, color: const Color(0xFFFFAB00)),
        AvailableConversion(format: 'PPTX', icon: LucideIcons.presentation, color: const Color(0xFFFF7A00)),
        AvailableConversion(format: 'JPG', icon: LucideIcons.image, color: const Color(0xFFFF9E00)),
        AvailableConversion(format: 'PNG', icon: LucideIcons.image, color: const Color(0xFFFFC400)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('heic')) {
      return [
        AvailableConversion(format: 'PNG', icon: LucideIcons.image, color: const Color(0xFFFF9E00)),
        AvailableConversion(format: 'JPG', icon: LucideIcons.image, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'WEBP', icon: LucideIcons.image, color: const Color(0xFFFFC400)),
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('image')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'PNG', icon: LucideIcons.image, color: const Color(0xFFFF9E00)),
        AvailableConversion(format: 'JPG', icon: LucideIcons.image, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'WEBP', icon: LucideIcons.image, color: const Color(0xFFFFC400)),
        AvailableConversion(format: 'SVG', icon: LucideIcons.fileCode, color: const Color(0xFFFF7A00)),
        AvailableConversion(format: 'ICO', icon: LucideIcons.box, color: const Color(0xFFE05300)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('word')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('excel')) {
      return [
        AvailableConversion(format: 'CSV', icon: LucideIcons.table, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'JSON', icon: LucideIcons.braces, color: const Color(0xFFFF8A00)),
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('powerpoint') || t.contains('presentation')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('csv')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'XLSX', icon: LucideIcons.table, color: const Color(0xFFFFAB00)),
        AvailableConversion(format: 'JSON', icon: LucideIcons.braces, color: const Color(0xFFFF8A00)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('markdown')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'DOCX', icon: LucideIcons.fileText, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('json')) {
      return [
        AvailableConversion(format: 'CSV', icon: LucideIcons.table, color: const Color(0xFFFFB300)),
        AvailableConversion(format: 'XLSX', icon: LucideIcons.table, color: const Color(0xFFFFAB00)),
        AvailableConversion(format: 'TXT', icon: LucideIcons.fileType2, color: const Color(0xFFFFC400)),
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else if (t.contains('text') || t.contains('txt')) {
      return [
        AvailableConversion(format: 'PDF', icon: LucideIcons.file, color: const Color(0xFFFF5C00)),
        AvailableConversion(format: 'JSON', icon: LucideIcons.braces, color: const Color(0xFFFF8A00)),
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9000)),
      ];
    } else {
      return [
        AvailableConversion(format: 'ZIP', icon: LucideIcons.archive, color: const Color(0xFFFF9E00)),
      ];
    }
  }
 
  static Map<String, String> _generateMetadata(String trueType, String sizeString) {
    final t = trueType.toLowerCase();
    if (t.contains('pdf')) {
      return {'Pages': '1', 'Security': 'None', 'Format': 'PDF-1.7'};
    } else if (t.contains('image')) {
      return {'Dimensions': '1080x1080', 'Color Model': 'RGB', 'Depth': '8-bit'};
    } else if (t.contains('word')) {
      return {'Creator': 'Microsoft Word', 'Content': 'Rich Text'};
    } else if (t.contains('excel')) {
      return {'Sheets': '1', 'Format': 'OpenXML'};
    } else if (t.contains('powerpoint') || t.contains('presentation')) {
      return {'Slides': '4', 'Format': 'PPTX-OpenXML'};
    } else if (t.contains('markdown')) {
      return {'Format': 'CommonMark', 'Encoding': 'UTF-8'};
    } else if (t.contains('json')) {
      return {'Encoding': 'UTF-8', 'Format': 'JSON'};
    }
    return {'Scanned': 'OK'};
  }
}
