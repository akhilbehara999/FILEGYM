import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';

import 'image_utils.dart';
import 'converters/pdf_converter.dart';
import 'converters/image_converter.dart';
import 'converters/office_converter.dart';
import 'converters/text_converter.dart';
import 'converters/zip_converter.dart';
import 'builders/docx_archive_builder.dart';
import 'builders/pptx_archive_builder.dart';

/// Thin facade that preserves the original `FileConverter` public API.
/// All heavy lifting is delegated to specialised converter classes.
class FileConverter {
  static Future<Directory> getSafeDownloadDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download');
    }
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    } catch (_) {}
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) {
        final dir = Directory('$home\\Downloads');
        if (await dir.exists()) return dir;
      }
    }
    return Directory.systemTemp;
  }

  /// Lightweight image dimension reader — delegates to ImageUtils.
  static List<int>? readImageDimensions(Uint8List bytes) =>
      ImageUtils.readImageDimensions(bytes);

  /// Stitch multiple images into a single PDF — delegates to PdfConverter.
  static Future<String> stitchImagesToPdf({
    required List<String> imagePaths,
    required String pageSize,
    required String orientation,
    required String margin,
  }) =>
      PdfConverter.stitchImagesToPdf(
        imagePaths: imagePaths,
        pageSize: pageSize,
        orientation: orientation,
        margin: margin,
      );

  /// Resize an image — delegates to ImageUtils.
  static Future<String> resizeImage({
    required String sourcePath,
    required int width,
    required int height,
    required String targetFormat,
    double quality = 80.0,
  }) =>
      ImageUtils.resizeImage(
        sourcePath: sourcePath,
        width: width,
        height: height,
        targetFormat: targetFormat,
        quality: quality,
      );

  /// Creates a DOCX archive with images (one per page) — delegates to DocxArchiveBuilder.
  static void createDocxArchiveWithImages(Archive archive, List<Uint8List> images) =>
      DocxArchiveBuilder.createDocxArchiveWithImages(archive, images);

  /// Creates a PPTX archive with images (one per slide, full-bleed) — delegates to PptxArchiveBuilder.
  static void createPptxArchiveWithImages(Archive archive, List<Uint8List> images) =>
      PptxArchiveBuilder.createPptxArchiveWithImages(archive, images);

  /// Main conversion entry point — routes to the correct converter by target format.
  static Future<String> convert({
    required String sourcePath,
    required String targetFormat,
    double quality = 80.0,
    double scale = 1.0,
  }) async {
    // ── Batch image-to-PDF ──
    final isBatchImages = sourcePath.contains(';');
    if (isBatchImages) {
      if (targetFormat.toLowerCase() == 'pdf') {
        return _batchImagesToPdf(sourcePath);
      } else {
        throw Exception('Only PDF format is supported for batch image stitching');
      }
    }

    // ── Single-file validation ──
    final file = File(sourcePath);
    if (!await file.exists()) throw Exception('Source file does not exist');

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('File is empty — nothing to convert');
    if (bytes.length <= 1 && !sourcePath.toLowerCase().endsWith('.txt')) {
      throw Exception('File has no meaningful content');
    }

    final ext = targetFormat.toLowerCase();
    final tempDir = Directory.systemTemp;
    final baseName = p.basenameWithoutExtension(sourcePath);
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_converted.$ext';

    // Legacy format guard
    final sourceLower = sourcePath.toLowerCase();
    if (sourceLower.endsWith('.xls') || sourceLower.endsWith('.doc') || sourceLower.endsWith('.ppt')) {
      final legacyExt = sourceLower.split('.').last;
      throw Exception('Legacy Microsoft Office formats (.$legacyExt) are not supported. Please convert them to modern formats (.xlsx, .docx, .pptx) first.');
    }

    final isZip = bytes.length >= 4 &&
        bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;

    // ── Route to converter ──
    if (ext == 'pdf') {
      return PdfConverter.convert(sourcePath: sourcePath, bytes: bytes, baseName: baseName, outputPath: outputPath, isZip: isZip);
    } else if (ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp' || ext == 'ico' || ext == 'svg') {
      return ImageConverter.convert(sourcePath: sourcePath, targetFormat: ext, bytes: bytes, outputPath: outputPath, quality: quality, scale: scale);
    } else if (ext == 'docx' || ext == 'xlsx' || ext == 'pptx') {
      return OfficeConverter.convert(sourcePath: sourcePath, targetFormat: ext, bytes: bytes, baseName: baseName, outputPath: outputPath, isZip: isZip);
    } else if (ext == 'txt' || ext == 'csv' || ext == 'json') {
      return TextConverter.convert(sourcePath: sourcePath, targetFormat: ext, bytes: bytes, baseName: baseName, outputPath: outputPath, isZip: isZip);
    } else if (ext == 'zip') {
      return ZipConverter.convert(sourcePath: sourcePath, bytes: bytes, baseName: baseName, outputPath: outputPath, tempDir: tempDir);
    } else {
      // Unknown format — passthrough copy
      await File(outputPath).writeAsBytes(bytes);
      return outputPath;
    }
  }

  /// Internal: handles batch image → PDF stitching via the semicolon-separated path list.
  static Future<String> _batchImagesToPdf(String sourcePath) async {
    final paths = sourcePath.split(';');
    final pdf = pw.Document();
    final tempDir = Directory.systemTemp;

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;

      Uint8List imageBytes;
      final bName = p.basenameWithoutExtension(path);
      if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
        final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${bName}_temp.png';
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          await channel.invokeMethod('convertHeic', {'heicPath': path, 'outputPath': tempImgPath});
        } else {
          final imgObj = img.Image(width: 10, height: 10);
          await File(tempImgPath).writeAsBytes(img.encodePng(imgObj));
        }
        imageBytes = await File(tempImgPath).readAsBytes();
        await File(tempImgPath).delete();
      } else {
        imageBytes = bytes;
      }

      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) continue;
      final pngBytes = img.encodePng(decodedImage);
      pdf.addPage(pw.Page(
        build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(pngBytes))),
      ));
    }

    final bName = p.basenameWithoutExtension(paths.first);
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${bName}_batch_converted.pdf';
    await File(outputPath).writeAsBytes(await pdf.save());
    return outputPath;
  }
}
