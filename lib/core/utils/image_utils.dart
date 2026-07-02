import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Pure image utilities — dimension reading, SVG rasterize/encode, ICO encode,
/// and resize helpers. No conversion logic lives here.
class ImageUtils {
  /// Lightweight image dimension reader — reads JPEG/PNG headers without
  /// decoding the full pixel buffer, preventing OOM on large camera photos.
  static List<int>? readImageDimensions(Uint8List bytes) {
    try {
      // PNG: bytes 16-23 contain width (4 bytes) and height (4 bytes) in IHDR
      if (bytes.length > 24 &&
          bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (w > 0 && h > 0) return [w, h];
      }
      // JPEG: scan for SOF0/SOF2 marker (0xFF 0xC0 or 0xFF 0xC2)
      if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        while (offset < bytes.length - 9) {
          if (bytes[offset] != 0xFF) { offset++; continue; }
          final marker = bytes[offset + 1];
          if (marker == 0xC0 || marker == 0xC2) {
            final h = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final w = (bytes[offset + 7] << 8) | bytes[offset + 8];
            if (w > 0 && h > 0) return [w, h];
          }
          final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          offset += 2 + segLen;
        }
      }
      // WebP: RIFF header
      if (bytes.length > 30 &&
          bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        // VP8 lossy
        if (bytes[15] == 0x56 && bytes[16] == 0x50 && bytes[17] == 0x38 && bytes[18] == 0x20) {
          if (bytes.length > 29) {
            final w = ((bytes[26] | (bytes[27] << 8)) & 0x3FFF);
            final h = ((bytes[28] | (bytes[29] << 8)) & 0x3FFF);
            if (w > 0 && h > 0) return [w, h];
          }
        }
      }
    } catch (_) {}
    // Fallback: full decode (only for unusual formats)
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return [decoded.width, decoded.height];
    } catch (_) {}
    return null;
  }

  /// Returns true if the file extension is a known raster/vector image type.
  static bool isImageExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp' || ext == '.gif' || ext == '.bmp' || ext == '.ico' || ext == '.svg';
  }

  /// Converts a decoded [img.Image] to an SVG with an embedded base64 PNG.
  static String convertImageToSvg(img.Image image) {
    final pngBytes = img.encodePng(image);
    final base64Png = base64Encode(pngBytes);
    return '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${image.width}" height="${image.height}">
  <image width="${image.width}" height="${image.height}" xlink:href="data:image/png;base64,$base64Png" href="data:image/png;base64,$base64Png"/>
</svg>''';
  }

  /// Rasterizes an SVG string into an [img.Image].
  static img.Image rasterizeSvg(String svgContent) {
    int width = 800;
    int height = 800;
    
    final svgTagRegex = RegExp(r'<svg[^>]*>');
    final svgTagMatch = svgTagRegex.firstMatch(svgContent);
    if (svgTagMatch != null) {
      final svgTag = svgTagMatch.group(0)!;
      final wMatch = RegExp(r'width="(\d+)"').firstMatch(svgTag);
      final hMatch = RegExp(r'height="(\d+)"').firstMatch(svgTag);
      if (wMatch != null) width = int.tryParse(wMatch.group(1)!) ?? width;
      if (hMatch != null) height = int.tryParse(hMatch.group(1)!) ?? height;
    }
    
    final canvas = img.Image(width: width, height: height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    
    // Check for base64 embedded image (matches both href and xlink:href)
    final base64Regex = RegExp(r'(?:xlink:)?href="data:image/[^;]+;base64,([^"]+)"');
    final base64Match = base64Regex.firstMatch(svgContent);
    if (base64Match != null) {
      try {
        final decodedBytes = base64Decode(base64Match.group(1)!.trim());
        final decoded = img.decodeImage(decodedBytes);
        if (decoded != null) {
          img.compositeImage(canvas, decoded, dstW: width, dstH: height);
          return canvas;
        }
      } catch (_) {}
    }
    
    // Basic vector shapes parsing
    final rectRegex = RegExp(r'<rect([^>]*)/>');
    for (final m in rectRegex.allMatches(svgContent)) {
      final attrs = m.group(1)!;
      final x = _getAttrInt(attrs, 'x', 0);
      final y = _getAttrInt(attrs, 'y', 0);
      final w = _getAttrInt(attrs, 'width', 0);
      final h = _getAttrInt(attrs, 'height', 0);
      final fill = _getAttrColor(attrs, 'fill', img.ColorRgb8(0, 0, 0));
      if (w > 0 && h > 0) {
        img.fillRect(canvas, x1: x, y1: y, x2: x + w, y2: y + h, color: fill);
      }
    }
    
    final circleRegex = RegExp(r'<circle([^>]*)/>');
    for (final m in circleRegex.allMatches(svgContent)) {
      final attrs = m.group(1)!;
      final cx = _getAttrInt(attrs, 'cx', 0);
      final cy = _getAttrInt(attrs, 'cy', 0);
      final r = _getAttrInt(attrs, 'r', 0);
      final fill = _getAttrColor(attrs, 'fill', img.ColorRgb8(0, 0, 0));
      if (r > 0) {
        img.fillCircle(canvas, x: cx, y: cy, radius: r, color: fill);
      }
    }
    
    final lineRegex = RegExp(r'<line([^>]*)/>');
    for (final m in lineRegex.allMatches(svgContent)) {
      final attrs = m.group(1)!;
      final x1 = _getAttrInt(attrs, 'x1', 0);
      final y1 = _getAttrInt(attrs, 'y1', 0);
      final x2 = _getAttrInt(attrs, 'x2', 0);
      final y2 = _getAttrInt(attrs, 'y2', 0);
      final stroke = _getAttrColor(attrs, 'stroke', img.ColorRgb8(0, 0, 0));
      img.drawLine(canvas, x1: x1, y1: y1, x2: x2, y2: y2, color: stroke);
    }
    
    return canvas;
  }

  static int _getAttrInt(String attrs, String name, int def) {
    final match = RegExp(name + r'="(\d+)"').firstMatch(attrs);
    if (match != null) return int.tryParse(match.group(1)!) ?? def;
    return def;
  }

  static img.Color _getAttrColor(String attrs, String name, img.Color def) {
    final match = RegExp(name + r'="([^"]+)"').firstMatch(attrs);
    if (match != null) {
      final val = match.group(1)!.trim();
      if (val.startsWith('#')) {
        final hex = val.substring(1);
        if (hex.length == 6) {
          final r = int.parse(hex.substring(0, 2), radix: 16);
          final g = int.parse(hex.substring(2, 4), radix: 16);
          final b = int.parse(hex.substring(4, 6), radix: 16);
          return img.ColorRgb8(r, g, b);
        }
      }
    }
    return def;
  }

  /// Encodes an [image] as a proper ICO file by embedding PNG data.
  /// ICO format: header + directory entry + PNG image data.
  static Uint8List encodeIco(img.Image image) {
    // Encode the image as PNG (the standard for modern ICO files)
    final pngBytes = img.encodePng(image);

    // ICO header: 6 bytes
    final header = ByteData(6);
    header.setUint16(0, 0, Endian.little);     // Reserved
    header.setUint16(2, 1, Endian.little);     // Type: 1 = ICO
    header.setUint16(4, 1, Endian.little);     // Image count: 1

    // ICO directory entry: 16 bytes
    final directory = ByteData(16);
    final w = image.width >= 256 ? 0 : image.width;  // 0 means 256
    final h = image.height >= 256 ? 0 : image.height;
    directory.setUint8(0, w);                        // Width
    directory.setUint8(1, h);                        // Height
    directory.setUint8(2, 0);                        // Color count (0 for 32-bit)
    directory.setUint8(3, 0);                        // Reserved
    directory.setUint16(4, 1, Endian.little);        // Color planes
    directory.setUint16(6, 32, Endian.little);       // Bits per pixel
    directory.setUint32(8, pngBytes.length, Endian.little);  // Image data size
    directory.setUint32(12, 22, Endian.little);     // Offset (6 header + 16 directory = 22)

    // Combine: header + directory + PNG data
    final ico = Uint8List(6 + 16 + pngBytes.length);
    ico.setAll(0, header.buffer.asUint8List());
    ico.setAll(6, directory.buffer.asUint8List());
    ico.setAll(22, pngBytes);
    return ico;
  }

  /// Resizes an image, trying native Android first, then falling back to isolate.
  static Future<String> resizeImage({
    required String sourcePath,
    required int width,
    required int height,
    required String targetFormat,
    double quality = 80.0,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('Source file does not exist');
    }

    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        final ext = targetFormat.toLowerCase();
        final tempDir = Directory.systemTemp;
        final baseName = p.basenameWithoutExtension(sourcePath);
        final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_resized.$ext';
        
        final bool? success = await channel.invokeMethod<bool>('resizeImage', {
          'sourcePath': sourcePath,
          'outputPath': outputPath,
          'width': width,
          'height': height,
          'quality': quality.toInt(),
        });
        if (success == true) {
          return outputPath;
        } else {
          throw Exception('Native resize returned false/null');
        }
      } catch (_) {}
    }

    final params = ResizeParams(
      sourcePath: sourcePath,
      width: width,
      height: height,
      targetFormat: targetFormat,
      quality: quality,
    );

    return await compute(resizeImageIsolate, params);
  }

  /// Isolate entry-point for resizing — must be a top-level or static function.
  static String resizeImageIsolate(ResizeParams params) {
    final file = File(params.sourcePath);
    final bytes = file.readAsBytesSync();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw Exception('Failed to decode source image');
    }

    final resizedImage = img.copyResize(
      decodedImage,
      width: params.width,
      height: params.height,
      interpolation: img.Interpolation.linear,
    );

    final ext = params.targetFormat.toLowerCase();
    final tempDir = Directory.systemTemp;
    final baseName = p.basenameWithoutExtension(params.sourcePath);
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_resized.$ext';
    final outputFile = File(outputPath);

    Uint8List outBytes;
    if (ext == 'png') {
      outBytes = Uint8List.fromList(img.encodePng(resizedImage, level: 9));
    } else {
      // The Dart 'image' package lacks a WebP encoder; fall back to JPEG
      outBytes = Uint8List.fromList(img.encodeJpg(resizedImage, quality: params.quality.toInt()));
    }
    outputFile.writeAsBytesSync(outBytes);

    return outputPath;
  }
}

class ResizeParams {
  final String sourcePath;
  final int width;
  final int height;
  final String targetFormat;
  final double quality;

  ResizeParams({
    required this.sourcePath,
    required this.width,
    required this.height,
    required this.targetFormat,
    required this.quality,
  });
}
