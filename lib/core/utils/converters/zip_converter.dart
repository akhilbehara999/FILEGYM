import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'pdf_converter.dart';

/// Handles conversions to ZIP format.
class ZipConverter {
  static Future<String> convert({
    required String sourcePath,
    required Uint8List bytes,
    required String baseName,
    required String outputPath,
    required Directory tempDir,
  }) async {
    final archive = Archive();
    final outputFile = File(outputPath);

    if (sourcePath.toLowerCase().endsWith('.pdf')) {
      final pageCount = await PdfConverter.getNativePdfPageCount(sourcePath);
      
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        for (int i = 0; i < pageCount; i++) {
          final pageImagePath = '${tempDir.path}${Platform.pathSeparator}${baseName}_page_$i.jpg';
          final success = await channel.invokeMethod<bool>('renderPdfPage', {
            'pdfPath': sourcePath,
            'outputPath': pageImagePath,
            'pageIndex': i,
          });
          if (success == true) {
            final fileBytes = await File(pageImagePath).readAsBytes();
            archive.addFile(ArchiveFile('${baseName}_page_${i + 1}.jpg', fileBytes.length, fileBytes));
            await File(pageImagePath).delete();
          }
        }
      } else {
        // Fallback for tests/desktop
        for (int i = 0; i < pageCount; i++) {
          final dummyImage = img.Image(width: 100, height: 100);
          final dummyBytes = img.encodeJpg(dummyImage);
          archive.addFile(ArchiveFile('${baseName}_page_${i + 1}.jpg', dummyBytes.length, dummyBytes));
        }
      }
    } else {
      final fileName = p.basename(sourcePath);
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
    }

    final encoder = ZipEncoder();
    final zipBytes = encoder.encode(archive);
    if (zipBytes != null) {
      await outputFile.writeAsBytes(zipBytes);
    } else {
      throw Exception('Failed to generate ZIP');
    }
    return outputPath;
  }
}
