import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileDetectionServiceProvider = Provider((ref) => FileDetectionService());

class DetectedFile {
  final String path;
  final String name;
  final String extension;
  final String detectedType;
  final int sizeBytes;
  final double confidence;

  DetectedFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.detectedType,
    required this.sizeBytes,
    required this.confidence,
  });
}

class FileDetectionService {
  // Magic bytes mapping
  static final Map<String, List<List<int>>> _magicBytes = {
    'pdf': [[0x25, 0x50, 0x44, 0x46]],
    'jpeg': [[0xFF, 0xD8, 0xFF]],
    'png': [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]],
    'gif': [[0x47, 0x49, 0x46, 0x38]],
    'bmp': [[0x42, 0x4D]],
    'zip': [[0x50, 0x4B, 0x03, 0x04]], // Note: DOCX, XLSX are also ZIPs
  };

  Future<DetectedFile> analyzeFile(String filePath) async {
    final file = File(filePath);
    final name = filePath.split(Platform.pathSeparator).last;
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final size = await file.length();
    
    // Read first few bytes
    String detectedType = 'unknown';
    double confidence = 0.0;
    
    try {
      final stream = file.openRead(0, 16);
      final bytes = await stream.first;
      
      for (var entry in _magicBytes.entries) {
        for (var signature in entry.value) {
          if (bytes.length >= signature.length) {
            bool matches = true;
            for (int i = 0; i < signature.length; i++) {
              if (bytes[i] != signature[i]) {
                matches = false;
                break;
              }
            }
            if (matches) {
              detectedType = entry.key;
              confidence = 0.99; // Magic bytes match gives high confidence
              break;
            }
          }
        }
        if (detectedType != 'unknown') break;
      }
    } catch (e) {
      // Fallback to extension
    }

    // Refine detection for ZIP based formats (docx, xlsx)
    if (detectedType == 'zip') {
      if (extension == 'docx') {
        detectedType = 'docx';
        confidence = 0.90;
      } else if (extension == 'xlsx') {
        detectedType = 'xlsx';
        confidence = 0.90;
      }
    }

    // If magic bytes failed, fallback to extension
    if (detectedType == 'unknown' && extension.isNotEmpty) {
      detectedType = extension;
      confidence = 0.60;
    }

    // Map types to human readable formats
    final readableType = _getReadableType(detectedType);

    return DetectedFile(
      path: filePath,
      name: name,
      extension: extension,
      detectedType: readableType,
      sizeBytes: size,
      confidence: confidence,
    );
  }

  String _getReadableType(String type) {
    switch (type) {
      case 'pdf': return 'PDF Document';
      case 'jpeg':
      case 'jpg': return 'JPEG Image';
      case 'png': return 'PNG Image';
      case 'docx': return 'Word Document';
      case 'xlsx': return 'Excel Spreadsheet';
      case 'csv': return 'CSV Data';
      case 'json': return 'JSON Data File';
      case 'zip': return 'ZIP Archive';
      default: return '${type.toUpperCase()} File';
    }
  }
}
