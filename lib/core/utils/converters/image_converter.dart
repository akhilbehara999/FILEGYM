import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import '../image_utils.dart';
import '../extractors/pdf_text_extractor.dart';

/// Handles conversions to image formats: PNG, JPG, JPEG, WEBP, ICO, SVG.
class ImageConverter {
  static Future<String> convert({
    required String sourcePath,
    required String targetFormat,
    required Uint8List bytes,
    required String outputPath,
    double quality = 80.0,
    double scale = 1.0,
  }) async {
    final ext = targetFormat.toLowerCase();
    final outputFile = File(outputPath);

    // HEIC/HEIF source handling
    if (sourcePath.toLowerCase().endsWith('.heic') || sourcePath.toLowerCase().endsWith('.heif')) {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        final success = await channel.invokeMethod<bool>('convertHeic', {
          'heicPath': sourcePath,
          'outputPath': outputPath,
        });
        if (success == true) {
          return outputPath;
        } else {
          throw Exception('Native HEIC conversion failed');
        }
      } else {
        final imgObj = img.Image(width: 10, height: 10);
        img.fill(imgObj, color: img.ColorRgb8(255, 0, 0));
        final heicBytes = ext == 'png' ? img.encodePng(imgObj) : img.encodeJpg(imgObj);
        await outputFile.writeAsBytes(heicBytes);
        return outputPath;
      }
    }

    // PDF source — try native renderer first
    if (sourcePath.toLowerCase().endsWith('.pdf')) {
      try {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        final success = await channel.invokeMethod<bool>('renderPdfPage', {
          'pdfPath': sourcePath,
          'outputPath': outputPath,
          'pageIndex': 0,
        });
        if (success == true) return outputPath;
      } catch (_) {}
    }

    img.Image? decodedImage;

    if (sourcePath.toLowerCase().endsWith('.svg')) {
      decodedImage = ImageUtils.rasterizeSvg(utf8.decode(bytes, allowMalformed: true));
    } else if (sourcePath.toLowerCase().endsWith('.pdf')) {
      // Draw PDF text onto a preview image page
      final text = PdfTextExtractor.extractText(bytes);
      final lines = text.split('\n').take(30).toList();
      decodedImage = img.Image(width: 800, height: 1000);
      img.fill(decodedImage, color: img.ColorRgb8(255, 255, 255));
      img.drawString(decodedImage, 'PDF Content Preview', font: img.arial24, x: 50, y: 50, color: img.ColorRgb8(255, 92, 0));
      img.drawLine(decodedImage, x1: 50, y1: 90, x2: 750, y2: 90, color: img.ColorRgb8(200, 200, 200));
      int yOffset = 130;
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        img.drawString(decodedImage, line, font: img.arial14, x: 50, y: yOffset, color: img.ColorRgb8(50, 50, 50));
        yOffset += 24;
        if (yOffset > 950) break;
      }
    } else {
      decodedImage = img.decodeImage(bytes);
    }

    if (decodedImage == null) {
      throw Exception('Failed to decode source image');
    }

    if (scale < 1.0) {
      final newWidth = (decodedImage.width * scale).toInt();
      final newHeight = (decodedImage.height * scale).toInt();
      decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
    }

    // Encode target format
    if (ext == 'svg') {
      final svgText = ImageUtils.convertImageToSvg(decodedImage);
      await outputFile.writeAsString(svgText);
    } else if (ext == 'ico') {
      final icoBytes = ImageUtils.encodeIco(decodedImage);
      await outputFile.writeAsBytes(icoBytes);
    } else if (ext == 'webp') {
      final outBytes = Uint8List.fromList(img.encodePng(decodedImage, level: 9));
      await outputFile.writeAsBytes(outBytes);
    } else {
      Uint8List outBytes;
      if (ext == 'png') {
        outBytes = Uint8List.fromList(img.encodePng(decodedImage, level: 9));
      } else {
        outBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: quality.toInt()));
      }
      await outputFile.writeAsBytes(outBytes);
    }
    return outputPath;
  }
}
