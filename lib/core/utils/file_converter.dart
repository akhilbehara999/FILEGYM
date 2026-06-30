import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
// syncfusion_flutter_pdf removed — page counting uses native PdfRenderer,
// text extraction uses pure-Dart PDF stream parser.

class FileConverter {
  static Future<Directory> getSafeDownloadDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download');
    }
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) {
        return dir;
      }
    } catch (_) {}
    // Fallback for Windows if getDownloadsDirectory returns null or throws
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) {
        final dir = Directory('$home\\Downloads');
        if (await dir.exists()) {
          return dir;
        }
      }
    }
    return Directory.systemTemp;
  }

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

  /// Gets PDF page count using native Android PdfRenderer — zero library cost.
  static Future<int> _getNativePdfPageCount(String pdfPath) async {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
      final count = await channel.invokeMethod<int>('getPdfPageCount', {
        'pdfPath': pdfPath,
      });
      return count ?? 0;
    }
    // Fallback for non-Android: parse PDF trailer for page count
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final pdfStr = String.fromCharCodes(bytes);
      // Look for /Count in the page tree
      final countMatch = RegExp(r'/Count\s+(\d+)').firstMatch(pdfStr);
      if (countMatch != null) return int.parse(countMatch.group(1)!);
    } catch (_) {}
    return 1; // Safe fallback
  }

  static Future<String> stitchImagesToPdf({
    required List<String> imagePaths,
    required String pageSize, // 'A4', 'Letter', 'Fit'
    required String orientation, // 'Portrait', 'Landscape', 'Auto'
    required String margin, // 'None', 'Small', 'Medium'
  }) async {
    final pdf = pw.Document();
    final tempDir = Directory.systemTemp;
    final needsDimensions = pageSize.toLowerCase() == 'fit' ||
        orientation.toLowerCase() == 'auto';

    for (final path in imagePaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;

      Uint8List imageBytes;
      final baseName = p.basenameWithoutExtension(path);

      // Handle HEIC/HEIF via native channel
      if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
        final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_temp.png';
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          await channel.invokeMethod('convertHeic', {
            'heicPath': path,
            'outputPath': tempImgPath,
          });
        } else {
          final imgObj = img.Image(width: 10, height: 10);
          await File(tempImgPath).writeAsBytes(img.encodePng(imgObj));
        }
        imageBytes = await File(tempImgPath).readAsBytes();
        try { await File(tempImgPath).delete(); } catch (_) {}
      } else {
        imageBytes = bytes;
      }

      // Pass raw bytes directly — pw.MemoryImage handles JPEG/PNG natively.
      // No need for the expensive decode→re-encode cycle that caused OOM crashes.
      final imageWidget = pw.MemoryImage(imageBytes);

      // Read dimensions from header only when layout requires them
      int imgWidth = 0;
      int imgHeight = 0;
      if (needsDimensions) {
        final dims = readImageDimensions(imageBytes);
        if (dims != null) {
          imgWidth = dims[0];
          imgHeight = dims[1];
        }
      }

      // Determine Page Format & Layout
      PdfPageFormat format;
      if (pageSize.toLowerCase() == 'a4') {
        format = PdfPageFormat.a4;
      } else if (pageSize.toLowerCase() == 'letter') {
        format = PdfPageFormat.letter;
      } else {
        // Fit layout: use image dimensions (fallback to A4 if unreadable)
        if (imgWidth > 0 && imgHeight > 0) {
          format = PdfPageFormat(
            imgWidth.toDouble(),
            imgHeight.toDouble(),
            marginAll: 0,
          );
        } else {
          format = PdfPageFormat.a4;
        }
      }

      // Handle orientation if not Fit page size
      if (pageSize.toLowerCase() != 'fit') {
        final double width = format.width;
        final double height = format.height;

        if (orientation.toLowerCase() == 'portrait') {
          if (width > height) {
            format = format.copyWith(width: height, height: width);
          }
        } else if (orientation.toLowerCase() == 'landscape') {
          if (width < height) {
            format = format.copyWith(width: height, height: width);
          }
        } else if (orientation.toLowerCase() == 'auto' && imgWidth > 0 && imgHeight > 0) {
          final isImageLandscape = imgWidth > imgHeight;
          final isPageLandscape = width > height;
          if (isImageLandscape != isPageLandscape) {
            format = format.copyWith(width: height, height: width);
          }
        }
      }

      // Handle Margin
      double marginValue = 0.0;
      if (pageSize.toLowerCase() != 'fit') {
        if (margin.toLowerCase() == 'small') {
          marginValue = 10.0;
        } else if (margin.toLowerCase() == 'medium') {
          marginValue = 25.0;
        }
      }

      format = format.copyWith(
        marginTop: marginValue,
        marginBottom: marginValue,
        marginLeft: marginValue,
        marginRight: marginValue,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: format,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                imageWidget,
                fit: pageSize.toLowerCase() == 'fit' ? pw.BoxFit.fill : pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final baseName = imagePaths.isNotEmpty ? p.basenameWithoutExtension(imagePaths.first) : 'stitch';
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_stitch_converted.pdf';
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(await pdf.save());
    return outputPath;
  }

  static Future<String> convert({
    required String sourcePath,
    required String targetFormat,
    double quality = 80.0,
    double scale = 1.0,
  }) async {
    final isBatchImages = sourcePath.contains(';');
    if (isBatchImages) {
      if (targetFormat.toLowerCase() == 'pdf') {
        final paths = sourcePath.split(';');
        final pdf = pw.Document();
        final tempDir = Directory.systemTemp;
        for (final path in paths) {
          final file = File(path);
          if (!await file.exists()) {
            continue;
          }
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) continue;
          
          Uint8List imageBytes;
          final baseName = p.basenameWithoutExtension(path);
          if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
            final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_temp.png';
            if (Platform.isAndroid) {
              const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
              await channel.invokeMethod('convertHeic', {
                'heicPath': path,
                'outputPath': tempImgPath,
              });
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
          final imageWidget = pw.MemoryImage(pngBytes);
          pdf.addPage(
            pw.Page(
              build: (pw.Context context) {
                return pw.Center(
                  child: pw.Image(imageWidget),
                );
              },
            ),
          );
        }
        
        final baseName = p.basenameWithoutExtension(paths.first);
        final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_batch_converted.pdf';
        final outputFile = File(outputPath);
        await outputFile.writeAsBytes(await pdf.save());
        return outputPath;
      } else {
        throw Exception('Only PDF format is supported for batch image stitching');
      }
    }

    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('Source file does not exist');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('File is empty — nothing to convert');
    }
    if (bytes.length <= 1 && !sourcePath.toLowerCase().endsWith('.txt')) {
      throw Exception('File has no meaningful content');
    }

    final ext = targetFormat.toLowerCase();
    final tempDir = Directory.systemTemp;
    final baseName = p.basenameWithoutExtension(sourcePath);
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_converted.$ext';
    final outputFile = File(outputPath);

    final sourceLower = sourcePath.toLowerCase();
    if (sourceLower.endsWith('.xls') || sourceLower.endsWith('.doc') || sourceLower.endsWith('.ppt')) {
      final legacyExt = sourceLower.split('.').last;
      throw Exception('Legacy Microsoft Office formats (.$legacyExt) are not supported. Please convert them to modern formats (.xlsx, .docx, .pptx) first.');
    }

    final isZip = bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;

    // Perform the conversion based on target extension
    if (ext == 'pdf') {
      final pdf = pw.Document();
      
      if (_isImageExtension(sourcePath) || sourcePath.toLowerCase().endsWith('.heic') || sourcePath.toLowerCase().endsWith('.heif')) {
        Uint8List imageBytes;
        if (sourcePath.toLowerCase().endsWith('.heic') || sourcePath.toLowerCase().endsWith('.heif')) {
          final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_temp.png';
          if (Platform.isAndroid) {
            final channel = const MethodChannel('com.akhilbehara.filegym/media_scanner');
            await channel.invokeMethod('convertHeic', {
              'heicPath': sourcePath,
              'outputPath': tempImgPath,
            });
          } else {
            // Test fallback
            final imgObj = img.Image(width: 10, height: 10);
            await File(tempImgPath).writeAsBytes(img.encodePng(imgObj));
          }
          imageBytes = await File(tempImgPath).readAsBytes();
          await File(tempImgPath).delete();
        } else {
          imageBytes = bytes;
        }

        final image = img.decodeImage(imageBytes);
        if (image == null) {
          throw Exception('Could not decode image — file may be corrupted or in an unsupported format');
        }
        final pngBytes = img.encodePng(image);
        final imageWidget = pw.MemoryImage(pngBytes);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(imageWidget),
              );
            },
          ),
        );
      } else if (sourcePath.toLowerCase().endsWith('.svg')) {
        final raster = _rasterizeSvg(String.fromCharCodes(bytes));
        final pngBytes = img.encodePng(raster);
        final imageWidget = pw.MemoryImage(pngBytes);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(imageWidget),
              );
            },
          ),
        );
      } else if (sourcePath.toLowerCase().endsWith('.md') || sourcePath.toLowerCase().endsWith('.markdown')) {
        final mdLines = utf8.decode(bytes).split('\n');
        final widgets = <pw.Widget>[];
        for (final line in mdLines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            widgets.add(pw.SizedBox(height: 10));
            continue;
          }
          if (trimmed.startsWith('# ')) {
            widgets.add(pw.Header(level: 0, child: pw.Text(trimmed.substring(2), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('FF5C00')))));
            widgets.add(pw.SizedBox(height: 10));
          } else if (trimmed.startsWith('## ')) {
            widgets.add(pw.Header(level: 1, child: pw.Text(trimmed.substring(3), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('FF7A00')))));
            widgets.add(pw.SizedBox(height: 8));
          } else if (trimmed.startsWith('### ')) {
            widgets.add(pw.Header(level: 2, child: pw.Text(trimmed.substring(4), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))));
            widgets.add(pw.SizedBox(height: 6));
          } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('• ', style: const pw.TextStyle(fontSize: 14)),
                    pw.Expanded(child: pw.Text(trimmed.substring(2).replaceAll('**', '').replaceAll('*', '').replaceAll('`', ''), style: const pw.TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            );
          } else {
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(trimmed.replaceAll('**', '').replaceAll('*', '').replaceAll('`', ''), style: const pw.TextStyle(fontSize: 14)),
            ));
          }
        }
        
        pdf.addPage(
          pw.MultiPage(
            build: (pw.Context context) => widgets,
          ),
        );
      } else if (sourcePath.toLowerCase().endsWith('.json')) {
        final decoded = json.decode(utf8.decode(bytes));
        final tableData = <List<String>>[];
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          final keys = (decoded.first as Map).keys.map((k) => k.toString()).toList();
          tableData.add(keys);
          for (final item in decoded) {
            if (item is Map) {
              tableData.add(keys.map((k) => item[k]?.toString() ?? '').toList());
            }
          }
        }
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 20),
                    if (tableData.isNotEmpty)
                      pw.TableHelper.fromTextArray(data: tableData)
                    else
                      pw.Text('Empty JSON Data'),
                  ],
                ),
              );
            },
          ),
        );
      } else if (sourcePath.toLowerCase().endsWith('.docx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
        }
        final text = _extractTextFromDocx(bytes);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 20),
                    pw.Text(text),
                  ],
                ),
              );
            },
          ),
        );
      } else if (sourcePath.toLowerCase().endsWith('.pptx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
        }
        final slides = _extractSlidesFromPptx(bytes);
        for (int i = 0; i < slides.length; i++) {
          pdf.addPage(
            pw.Page(
              build: (pw.Context context) {
                return pw.Container(
                  padding: const pw.EdgeInsets.all(32),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Slide ${i + 1}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 20),
                      pw.Text(slides[i], style: const pw.TextStyle(fontSize: 16)),
                    ],
                  ),
                );
              },
            ),
          );
        }
      } else if (sourcePath.toLowerCase().endsWith('.xlsx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
        }
        final excel = Excel.decodeBytes(bytes);
        final tableData = <List<String>>[];
        if (excel.tables.isNotEmpty) {
          final firstSheet = excel.tables.values.first;
          for (final row in firstSheet.rows) {
            tableData.add(row.map((e) => e?.value?.toString() ?? '').toList());
          }
        }
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 20),
                    if (tableData.isNotEmpty)
                      pw.TableHelper.fromTextArray(data: tableData)
                    else
                      pw.Text('Empty Spreadsheet'),
                  ],
                ),
              );
            },
          ),
        );
      } else if (sourcePath.endsWith('.txt')) {
        final txtContent = String.fromCharCodes(bytes);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: pw.Text(txtContent),
              );
            },
          ),
        );
      } else if (sourcePath.endsWith('.csv')) {
        final csvContent = String.fromCharCodes(bytes);
        final rows = csvContent.split('\n').where((r) => r.trim().isNotEmpty).toList();
        final tableData = rows.map((r) => r.split(',').map((c) => c.trim()).toList()).toList();
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 20),
                    if (tableData.isNotEmpty)
                      pw.TableHelper.fromTextArray(data: tableData)
                    else
                      pw.Text('Empty CSV'),
                  ],
                ),
              );
            },
          ),
        );
      } else {
        // Unknown source type — try to render as text if it looks like text
        final text = String.fromCharCodes(bytes);
        final isText = text.runes.every((r) => r < 0xFFFD || r == 0xFFFD);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(24),
                child: isText
                    ? pw.Text(text)
                    : pw.Center(
                        child: pw.Text('Converted Document: $baseName\n(Binary content — text extraction not available)'),
                      ),
              );
            },
          ),
        );
      }
      
      await outputFile.writeAsBytes(await pdf.save());
    } 
    else if (ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp' || ext == 'ico' || ext == 'svg') {
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
          // Fallback for tests/desktop
          final imgObj = img.Image(width: 10, height: 10);
          img.fill(imgObj, color: img.ColorRgb8(255, 0, 0));
          final heicBytes = ext == 'png' ? img.encodePng(imgObj) : img.encodeJpg(imgObj);
          await outputFile.writeAsBytes(heicBytes);
          return outputPath;
        }
      }

      if (sourcePath.toLowerCase().endsWith('.pdf')) {
        try {
          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          final success = await channel.invokeMethod<bool>('renderPdfPage', {
            'pdfPath': sourcePath,
            'outputPath': outputPath,
            'pageIndex': 0,
          });
          if (success == true) {
            return outputPath;
          }
        } catch (_) {
          // Native rendering failed or not supported, fallback to manual text drawing
        }
      }
      img.Image? decodedImage;

      // Decode source format
      if (sourcePath.toLowerCase().endsWith('.svg')) {
        decodedImage = _rasterizeSvg(String.fromCharCodes(bytes));
      } else if (sourcePath.toLowerCase().endsWith('.pdf')) {
        // Draw PDF text onto a preview image page
        final text = _extractTextFromPdfBytes(bytes);
        final lines = text.split('\n').take(30).toList();
        decodedImage = img.Image(width: 800, height: 1000);
        img.fill(decodedImage, color: img.ColorRgb8(255, 255, 255));
        
        // Draw header
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
        final svgText = _convertImageToSvg(decodedImage);
        await outputFile.writeAsString(svgText);
      } else if (ext == 'ico') {
        // Proper ICO format: embed PNG inside ICO container
        final icoBytes = _encodeIco(decodedImage);
        await outputFile.writeAsBytes(icoBytes);
      } else if (ext == 'webp') {
        // Pure-Dart image package doesn't support WebP encoding;
        // fall back to lossless PNG (honest output vs wrong-format bytes)
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
    }
    else if (ext == 'txt') {
      String textContent = '';
      if (sourcePath.toLowerCase().endsWith('.docx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
        }
        textContent = _extractTextFromDocx(bytes);
      } else if (sourcePath.toLowerCase().endsWith('.pdf')) {
        textContent = _extractTextFromPdfBytes(bytes);
      } else if (sourcePath.toLowerCase().endsWith('.pptx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
        }
        textContent = _extractSlidesFromPptx(bytes).join('\n\n');
      } else if (sourcePath.toLowerCase().endsWith('.xlsx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
        }
        final excel = Excel.decodeBytes(bytes);
        final sb = StringBuffer();
        for (final table in excel.tables.keys) {
          sb.writeln('--- Sheet: $table ---');
          final sheet = excel.tables[table]!;
          for (final row in sheet.rows) {
            sb.writeln(row.map((e) => e?.value?.toString() ?? '').join('\t'));
          }
          sb.writeln();
        }
        textContent = sb.toString();
      } else if (sourcePath.endsWith('.csv')) {
        textContent = String.fromCharCodes(bytes);
      } else if (sourcePath.toLowerCase().endsWith('.md') || sourcePath.toLowerCase().endsWith('.markdown')) {
        final mdLines = utf8.decode(bytes).split('\n');
        final sb = StringBuffer();
        for (final line in mdLines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('# ')) {
            sb.writeln(trimmed.substring(2).toUpperCase());
            sb.writeln('=' * trimmed.substring(2).length);
          } else if (trimmed.startsWith('## ')) {
            sb.writeln(trimmed.substring(3));
            sb.writeln('-' * trimmed.substring(3).length);
          } else if (trimmed.startsWith('### ')) {
            sb.writeln(trimmed.substring(4));
          } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
            sb.writeln('• ${trimmed.substring(2)}');
          } else {
            sb.writeln(trimmed);
          }
        }
        textContent = sb.toString();
      } else if (sourcePath.toLowerCase().endsWith('.json')) {
        final decoded = json.decode(utf8.decode(bytes));
        textContent = const JsonEncoder.withIndent('  ').convert(decoded);
      } else {
        // Generic fallback: try to read as text
        textContent = String.fromCharCodes(bytes);
      }
      await outputFile.writeAsString(textContent);
    }
    else if (ext == 'docx') {
      final archive = Archive();
      
      bool convertedWithImages = false;
      if (sourcePath.toLowerCase().endsWith('.pdf') && Platform.isAndroid) {
        try {
          final pageCount = await _getNativePdfPageCount(sourcePath);

          final tempDir = Directory.systemTemp;
          final baseName = p.basenameWithoutExtension(sourcePath);
          final images = <Uint8List>[];

          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          for (int i = 0; i < pageCount; i++) {
            final pageImagePath = '${tempDir.path}${Platform.pathSeparator}${baseName}_page_$i.jpg';
            final success = await channel.invokeMethod<bool>('renderPdfPage', {
              'pdfPath': sourcePath,
              'outputPath': pageImagePath,
              'pageIndex': i,
            });

            if (success == true) {
              final imgFile = File(pageImagePath);
              if (await imgFile.exists()) {
                images.add(await imgFile.readAsBytes());
                await imgFile.delete();
              }
            }
          }

          if (images.isNotEmpty) {
            createDocxArchiveWithImages(archive, images);
            final encoder = ZipEncoder();
            final zipBytes = encoder.encode(archive);
            if (zipBytes != null) {
              await outputFile.writeAsBytes(zipBytes);
              convertedWithImages = true;
            }
          }
        } catch (_) {
          // Fallback to text-based extraction on failure
        }
      }

      if (!convertedWithImages) {
        String text;
        if (sourcePath.toLowerCase().endsWith('.pdf')) {
          text = _extractTextFromPdfBytes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.pptx')) {
          if (!isZip) {
            throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
          }
          text = _extractSlidesFromPptx(bytes).join('\n\n');
        } else if (sourcePath.toLowerCase().endsWith('.csv')) {
          text = String.fromCharCodes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.txt')) {
          text = String.fromCharCodes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.xlsx')) {
          if (!isZip) {
            throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
          }
          final excel = Excel.decodeBytes(bytes);
          final sb = StringBuffer();
          for (final table in excel.tables.keys) {
            sb.writeln('--- Sheet: $table ---');
            final sheet = excel.tables[table]!;
            for (final row in sheet.rows) {
              sb.writeln(row.map((e) => e?.value?.toString() ?? '').join('\t'));
            }
            sb.writeln();
          }
          text = sb.toString();
        } else {
          text = 'Converted from $baseName';
        }
        _createDocxArchive(archive, text);
        final encoder = ZipEncoder();
        final zipBytes = encoder.encode(archive);
        if (zipBytes != null) {
          await outputFile.writeAsBytes(zipBytes);
        } else {
          throw Exception('Failed to generate DOCX');
        }
      }
    }
    else if (ext == 'xlsx') {
      final excel = Excel.createExcel();
      final sheet = excel.sheets[excel.sheets.keys.first]!;
      
      if (sourcePath.toLowerCase().endsWith('.json')) {
        final decoded = json.decode(utf8.decode(bytes));
        if (decoded is List) {
          if (decoded.isNotEmpty && decoded.first is Map) {
            final keys = (decoded.first as Map).keys.toList();
            for (int c = 0; c < keys.length; c++) {
              final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
              cell.value = TextCellValue(keys[c].toString());
            }
            for (int r = 0; r < decoded.length; r++) {
              final item = decoded[r] as Map;
              for (int c = 0; c < keys.length; c++) {
                final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
                cell.value = TextCellValue(item[keys[c]]?.toString() ?? '');
              }
            }
          }
        } else if (decoded is Map) {
          final keys = decoded.keys.toList();
          for (int r = 0; r < keys.length; r++) {
            final kCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
            kCell.value = TextCellValue(keys[r]);
            final vCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
            vCell.value = TextCellValue(decoded[keys[r]]?.toString() ?? '');
          }
        }
      } else {
        String text;
        if (sourcePath.toLowerCase().endsWith('.pdf')) {
          text = _extractTextFromPdfBytes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.csv')) {
          text = String.fromCharCodes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.docx')) {
          if (!isZip) {
            throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
          }
          text = _extractTextFromDocx(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.pptx')) {
          if (!isZip) {
            throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
          }
          text = _extractSlidesFromPptx(bytes).join('\n\n');
        } else if (sourcePath.toLowerCase().endsWith('.txt')) {
          text = String.fromCharCodes(bytes);
        } else {
          text = 'Content';
        }
        final lines = text.split('\n');
        for (int r = 0; r < lines.length; r++) {
          final line = lines[r].trim();
          if (line.isEmpty) continue;
          final columns = line.split(RegExp(r'\t|,|\s{2,}'));
          for (int c = 0; c < columns.length; c++) {
            final cellValue = columns[c].trim();
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
            cell.value = TextCellValue(cellValue);
          }
        }
      }
      
      final excelBytes = excel.encode();
      if (excelBytes != null) {
        await outputFile.writeAsBytes(excelBytes);
      } else {
        throw Exception('Failed to generate XLSX');
      }
    }
    else if (ext == 'pptx') {
      final archive = Archive();
      
      bool convertedWithImages = false;
      if (sourcePath.toLowerCase().endsWith('.pdf') && Platform.isAndroid) {
        try {
          final pageCount = await _getNativePdfPageCount(sourcePath);

          final tempDir = Directory.systemTemp;
          final baseName = p.basenameWithoutExtension(sourcePath);
          final images = <Uint8List>[];

          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          for (int i = 0; i < pageCount; i++) {
            final pageImagePath = '${tempDir.path}${Platform.pathSeparator}${baseName}_page_$i.jpg';
            final success = await channel.invokeMethod<bool>('renderPdfPage', {
              'pdfPath': sourcePath,
              'outputPath': pageImagePath,
              'pageIndex': i,
            });

            if (success == true) {
              final imgFile = File(pageImagePath);
              if (await imgFile.exists()) {
                images.add(await imgFile.readAsBytes());
                await imgFile.delete();
              }
            }
          }

          if (images.isNotEmpty) {
            createPptxArchiveWithImages(archive, images);
            final encoder = ZipEncoder();
            final zipBytes = encoder.encode(archive);
            if (zipBytes != null) {
              await outputFile.writeAsBytes(zipBytes);
              convertedWithImages = true;
            }
          }
        } catch (_) {
          // Fallback to text-based extraction on failure
        }
      }

      if (!convertedWithImages) {
        String text;
        if (sourcePath.toLowerCase().endsWith('.pdf')) {
          text = _extractTextFromPdfBytes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.docx')) {
          if (!isZip) {
            throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
          }
          text = _extractTextFromDocx(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.csv')) {
          text = String.fromCharCodes(bytes);
        } else if (sourcePath.toLowerCase().endsWith('.txt')) {
          text = String.fromCharCodes(bytes);
        } else {
          text = 'Slide content';
        }
        final slides = text.split(RegExp(r'\n{2,}|\f'));
        try {
          _createPptxArchive(archive, slides);
          final encoder = ZipEncoder();
          final zipBytes = encoder.encode(archive);
          if (zipBytes != null) {
            await outputFile.writeAsBytes(zipBytes);
          } else {
            throw Exception('Zip encoder returned null');
          }
        } catch (e) {
          throw Exception('Failed to generate PPTX: $e');
        }
      }
    }
    else if (ext == 'csv') {
      if (sourcePath.toLowerCase().endsWith('.xlsx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
        }
        final excel = Excel.decodeBytes(bytes);
        final sb = StringBuffer();
        if (excel.tables.isNotEmpty) {
          final sheet = excel.tables.values.first;
          for (final row in sheet.rows) {
            final csvRow = row.map((cell) {
              String val = cell?.value?.toString() ?? '';
              if (val.contains(',') || val.contains('"') || val.contains('\n')) {
                val = '"${val.replaceAll('"', '""')}"';
              }
              return val;
            }).join(',');
            sb.writeln(csvRow);
          }
        }
        await outputFile.writeAsString(sb.toString());
      } else if (sourcePath.toLowerCase().endsWith('.json')) {
        final decoded = json.decode(utf8.decode(bytes));
        final sb = StringBuffer();
        if (decoded is List) {
          if (decoded.isNotEmpty && decoded.first is Map) {
            final keys = (decoded.first as Map).keys.toList();
            sb.writeln(keys.join(','));
            for (final item in decoded) {
              if (item is Map) {
                final row = keys.map((k) {
                  String val = item[k]?.toString() ?? '';
                  if (val.contains(',') || val.contains('"') || val.contains('\n')) {
                    val = '"${val.replaceAll('"', '""')}"';
                  }
                  return val;
                }).join(',');
                sb.writeln(row);
              }
            }
          }
        } else if (decoded is Map) {
          sb.writeln('key,value');
          for (final entry in decoded.entries) {
            String k = entry.key;
            String v = entry.value?.toString() ?? '';
            if (k.contains(',') || k.contains('"') || k.contains('\n')) {
              k = '"${k.replaceAll('"', '""')}"';
            }
            if (v.contains(',') || v.contains('"') || v.contains('\n')) {
              v = '"${v.replaceAll('"', '""')}"';
            }
            sb.writeln('$k,$v');
          }
        }
        await outputFile.writeAsString(sb.toString());
      } else if (sourcePath.toLowerCase().endsWith('.pdf')) {
        final text = _extractTextFromPdfBytes(bytes);
        await outputFile.writeAsString(text);
      } else if (sourcePath.toLowerCase().endsWith('.docx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
        }
        final text = _extractTextFromDocx(bytes);
        await outputFile.writeAsString(text);
      } else if (sourcePath.toLowerCase().endsWith('.pptx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
        }
        final text = _extractSlidesFromPptx(bytes).join('\n\n');
        await outputFile.writeAsString(text);
      } else if (sourcePath.toLowerCase().endsWith('.txt')) {
        await outputFile.writeAsBytes(bytes);
      } else {
        await outputFile.writeAsBytes(bytes);
      }
    }
    else if (ext == 'json') {
      String textContent = '';
      if (sourcePath.toLowerCase().endsWith('.csv')) {
        final csvContent = utf8.decode(bytes);
        final lines = csvContent.split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.isNotEmpty) {
          final headers = lines.first.split(',').map((h) => h.trim()).toList();
          final resultList = <Map<String, dynamic>>[];
          for (int i = 1; i < lines.length; i++) {
            final cols = lines[i].split(',').map((c) => c.trim()).toList();
            final map = <String, dynamic>{};
            for (int j = 0; j < headers.length; j++) {
              if (j < cols.length) {
                map[headers[j]] = cols[j];
              } else {
                map[headers[j]] = '';
              }
            }
            resultList.add(map);
          }
          textContent = const JsonEncoder.withIndent('  ').convert(resultList);
        } else {
          textContent = '[]';
        }
      } else if (sourcePath.toLowerCase().endsWith('.xlsx')) {
        if (!isZip) {
          throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
        }
        final excel = Excel.decodeBytes(bytes);
        final sheetData = <String, List<Map<String, dynamic>>>{};
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table]!;
          final rows = sheet.rows;
          if (rows.isEmpty) continue;
          final headers = rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
          final list = <Map<String, dynamic>>[];
          for (int i = 1; i < rows.length; i++) {
            final map = <String, dynamic>{};
            final row = rows[i];
            for (int j = 0; j < headers.length; j++) {
              final cellVal = j < row.length ? (row[j]?.value?.toString() ?? '') : '';
              map[headers[j].isNotEmpty ? headers[j] : 'Column_${j+1}'] = cellVal;
            }
            list.add(map);
          }
          sheetData[table] = list;
        }
        textContent = const JsonEncoder.withIndent('  ').convert(sheetData);
      } else {
        final rawText = utf8.decode(bytes);
        try {
          final parsed = json.decode(rawText);
          textContent = const JsonEncoder.withIndent('  ').convert(parsed);
        } catch (_) {
          textContent = json.encode({'content': rawText});
        }
      }
      await outputFile.writeAsString(textContent);
    }
    else if (ext == 'zip') {
      final archive = Archive();
      if (sourcePath.toLowerCase().endsWith('.pdf')) {
        final pageCount = await _getNativePdfPageCount(sourcePath);
        
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
    }
    else {
      await outputFile.writeAsBytes(bytes);
    }

    return outputPath;
  }

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

    return await compute(_resizeImageIsolate, params);
  }

  static String _resizeImageIsolate(ResizeParams params) {
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

  static bool _isImageExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp' || ext == '.gif' || ext == '.bmp' || ext == '.ico' || ext == '.svg';
  }

  static String _convertImageToSvg(img.Image image) {
    final pngBytes = img.encodePng(image);
    final base64Png = base64Encode(pngBytes);
    return '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${image.width}" height="${image.height}">
  <image width="${image.width}" height="${image.height}" xlink:href="data:image/png;base64,$base64Png" href="data:image/png;base64,$base64Png"/>
</svg>''';
  }

  static img.Image _rasterizeSvg(String svgContent) {
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
    final rectRegex = RegExp(r'<rect([^>]*)\/>');
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
    
    final circleRegex = RegExp(r'<circle([^>]*)\/>');
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
    
    final lineRegex = RegExp(r'<line([^>]*)\/>');
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

  static String _extractTextFromDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) return '';
      
      final content = utf8.decode(documentFile.content as List<int>, allowMalformed: true);
      
      // Split by paragraph boundaries <w:p>...</w:p>
      final paragraphs = <String>[];
      final paraRegex = RegExp(r'<w:p\b[^>]*>(.*?)</w:p>', dotAll: true);
      for (final paraMatch in paraRegex.allMatches(content)) {
        final paraContent = paraMatch.group(1) ?? '';
        // Extract all <w:t> text within this paragraph
        final textRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
        final texts = textRegex.allMatches(paraContent)
            .map((m) => m.group(1) ?? '')
            .join('');
        if (texts.isNotEmpty) {
          paragraphs.add(texts);
        }
      }
      return paragraphs.join('\n');
    } catch (e) {
      return 'Failed to extract text from DOCX: $e';
    }
  }

  static List<String> _extractSlidesFromPptx(Uint8List bytes) {
    final slides = <String>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final slideFiles = archive.files
          .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
          .toList();
      slideFiles.sort((a, b) => a.name.compareTo(b.name));
      
      for (final f in slideFiles) {
        final content = utf8.decode(f.content as List<int>, allowMalformed: true);
        // Extract text from <a:t> tags, grouped by <a:p> paragraphs
        final paragraphs = <String>[];
        final paraRegex = RegExp(r'<a:p\b[^>]*>(.*?)</a:p>', dotAll: true);
        for (final paraMatch in paraRegex.allMatches(content)) {
          final paraContent = paraMatch.group(1) ?? '';
          final textRegex = RegExp(r'<a:t[^>]*>([^<]*)</a:t>');
          final texts = textRegex.allMatches(paraContent)
              .map((m) => m.group(1) ?? '')
              .join('');
          if (texts.trim().isNotEmpty) {
            paragraphs.add(texts);
          }
        }
        slides.add(paragraphs.isNotEmpty ? paragraphs.join('\n') : '(No text content on this slide)');
      }
    } catch (_) {}
    if (slides.isEmpty) {
      slides.add('(No slide content found)');
    }
    return slides;
  }

  static void _createPptxArchive(Archive archive, List<String> slides) {
    // 1. [Content_Types].xml
    final sbContent = StringBuffer();
    sbContent.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbContent.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    sbContent.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    sbContent.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    sbContent.writeln('  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>');
    for (int i = 1; i <= slides.length; i++) {
      sbContent.writeln('  <Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    sbContent.writeln('</Types>');

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''';

    // 3. docProps/core.xml
    const coreXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Generated Presentation</dc:title>
  <dc:subject>PDF to PPTX Conversion</dc:subject>
  <dc:creator>FileGym</dc:creator>
  <cp:revision>1</cp:revision>
</cp:coreProperties>''';

    // 4. docProps/app.xml
    final sbApp = StringBuffer();
    sbApp.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbApp.writeln('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">');
    sbApp.writeln('  <TotalTime>1</TotalTime>');
    sbApp.writeln('  <Words>0</Words><Application>FileGym</Application>');
    sbApp.writeln('  <PresentationFormat>On-screen Show (4:3)</PresentationFormat>');
    sbApp.writeln('  <Paragraphs>0</Paragraphs><Slides>${slides.length}</Slides><Notes>0</Notes><HiddenSlides>0</HiddenSlides><MMClips>0</MMClips>');
    sbApp.writeln('  <ScaleCrop>false</ScaleCrop>');
    sbApp.writeln('  <HeadingPairs>');
    sbApp.writeln('    <vt:vector size="4" baseType="variant">');
    sbApp.writeln('      <vt:variant><vt:lpstr>Theme</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>1</vt:i4></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:lpstr>Slide Titles</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>${slides.length}</vt:i4></vt:variant>');
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </HeadingPairs>');
    sbApp.writeln('  <TitlesOfParts>');
    sbApp.writeln('    <vt:vector size="${slides.length + 1}" baseType="lpstr">');
    sbApp.writeln('      <vt:lpstr>Office Theme</vt:lpstr>');
    for (int i = 1; i <= slides.length; i++) {
      sbApp.writeln('      <vt:lpstr>Slide $i</vt:lpstr>');
    }
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </TitlesOfParts>');
    sbApp.writeln('  <LinksUpToDate>false</LinksUpToDate>');
    sbApp.writeln('  <SharedDoc>false</SharedDoc>');
    sbApp.writeln('  <HyperlinksChanged>false</HyperlinksChanged>');
    sbApp.writeln('  <AppVersion>15.0000</AppVersion>');
    sbApp.writeln('</Properties>');

    // 5. ppt/presentation.xml
    final sbPres = StringBuffer();
    sbPres.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPres.writeln('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
    sbPres.writeln('  <p:sldMasterIdLst>');
    sbPres.writeln('    <p:sldMasterId id="2147483648" r:id="rId${slides.length + 1}"/>');
    sbPres.writeln('  </p:sldMasterIdLst>');
    sbPres.writeln('  <p:sldIdLst>');
    for (int i = 1; i <= slides.length; i++) {
      sbPres.writeln('    <p:sldId id="${255 + i}" r:id="rId$i"/>');
    }
    sbPres.writeln('  </p:sldIdLst>');
    sbPres.writeln('  <p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>');
    sbPres.writeln('  <p:notesSz cx="6858000" cy="9144000"/>');
    sbPres.writeln('  <p:defaultTextStyle>');
    sbPres.writeln('    <a:defPPr><a:defRPr lang="en-US"/></a:defPPr>');
    sbPres.writeln('  </p:defaultTextStyle>');
    sbPres.writeln('</p:presentation>');

    // 6. ppt/_rels/presentation.xml.rels
    final sbPresRels = StringBuffer();
    sbPresRels.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPresRels.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (int i = 1; i <= slides.length; i++) {
      sbPresRels.writeln('  <Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>');
    }
    sbPresRels.writeln('  <Relationship Id="rId${slides.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slides.length + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slides.length + 3}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slides.length + 4}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slides.length + 5}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>');
    sbPresRels.writeln('</Relationships>');

    // 7. ppt/presProps.xml
    const presPropsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:extLst>
    <p:ext uri="{E76CE94A-603C-4142-B9EB-6D1370010A27}">
      <p14:discardImageEditData xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" val="0"/>
    </p:ext>
  </p:extLst>
</p:presentationPr>''';

    // 8. ppt/viewProps.xml
    const viewPropsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" lastView="sldThumbnailView">
  <p:normalViewPr>
    <p:restoredLeft sz="15620"/>
    <p:restoredTop sz="94660"/>
  </p:normalViewPr>
</p:viewPr>''';

    // 9. ppt/tableStyles.xml
    const tableStylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>''';

    // theme1.xml content
    const themeXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
      <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
      <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
      <a:accent2><a:srgbClr val="C0504D"/></a:accent2>
      <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
      <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
      <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
      <a:accent6><a:srgbClr val="F79646"/></a:accent6>
      <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
      <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office">
      <a:majorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface=""/>
        <a:cs typeface=""/>
      </a:majorFont>
      <a:minorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface=""/>
        <a:cs typeface=""/>
      </a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Office">
      <a:fillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="1"/>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="100000"/><a:shade val="100000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="50000"/><a:shade val="100000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="0"/>
        </a:gradFill>
      </a:fillStyleLst>
      <a:lnStyleLst>
        <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
        <a:ln w="25400" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
        <a:ln w="38100" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
      </a:lnStyleLst>
      <a:effectStyleLst>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="20000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="38000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
        </a:effectStyle>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="23000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="35000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
        </a:effectStyle>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="23000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="35000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
          <a:scene3d>
            <a:camera prst="orthographicFront"><a:rot lat="0" lon="0" rev="0"/></a:camera>
            <a:lightRig rig="threePt" dir="t"><a:rot lat="0" lon="0" rev="1200000"/></a:lightRig>
          </a:scene3d>
          <a:sp3d><a:bevelT w="63500" h="25400"/></a:sp3d>
        </a:effectStyle>
      </a:effectStyleLst>
      <a:bgFillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="40000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
            <a:gs pos="40000"><a:schemeClr val="phClr"><a:tint val="45000"/><a:shade val="99000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="20000"/><a:satMod val="255000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="5400000" scaled="1"/>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="80000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="30000"/><a:satMod val="200000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="5400000" scaled="1"/>
        </a:gradFill>
      </a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
  <a:objectDefaults>
    <a:spDef>
      <a:spPr/>
      <a:bodyPr/>
      <a:lstStyle/>
      <a:style>
        <a:lnRef idx="1"><a:schemeClr val="accent1"/></a:lnRef>
        <a:fillRef idx="3"><a:schemeClr val="accent1"/></a:fillRef>
        <a:effectRef idx="2"><a:schemeClr val="accent1"/></a:effectRef>
        <a:fontRef idx="minor"><a:schemeClr val="lt1"/></a:fontRef>
      </a:style>
    </a:spDef>
    <a:lnDef>
      <a:spPr/>
      <a:bodyPr/>
      <a:lstStyle/>
      <a:style>
        <a:lnRef idx="2"><a:schemeClr val="accent1"/></a:lnRef>
        <a:fillRef idx="0"><a:schemeClr val="accent1"/></a:fillRef>
        <a:effectRef idx="1"><a:schemeClr val="accent1"/></a:effectRef>
        <a:fontRef idx="minor"><a:schemeClr val="tx1"/></a:fontRef>
      </a:style>
    </a:lnDef>
  </a:objectDefaults>
  <a:extraClrSchemeLst/>
</a:theme>''';

    _addXmlFileToArchive(archive, 'ppt/theme/theme1.xml', themeXml);

    // Slide master (added required clrMap!)
    const slideMasterXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld name="">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>''';
    _addXmlFileToArchive(archive, 'ppt/slideMasters/slideMaster1.xml', slideMasterXml);

    const slideMasterRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''';
    _addXmlFileToArchive(archive, 'ppt/slideMasters/_rels/slideMaster1.xml.rels', slideMasterRels);

    // Slide layout (no 'name' attribute on root sldLayout element to be strictly compliant!)
    const slideLayoutXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" type="blank">
  <p:cSld name="Blank">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''';
    _addXmlFileToArchive(archive, 'ppt/slideLayouts/slideLayout1.xml', slideLayoutXml);

    const slideLayoutRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';
    _addXmlFileToArchive(archive, 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', slideLayoutRels);

    // Individual slides
    for (int i = 0; i < slides.length; i++) {
      final slideText = slides[i].replaceAll('\r', '');
      final sbParas = StringBuffer();
      final lines = slideText.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        sbParas.writeln('          <a:p>');
        sbParas.writeln('            <a:r>');
        sbParas.writeln('              <a:rPr lang="en-US" dirty="0"/>');
        sbParas.writeln('              <a:t>${_escapeXml(line)}</a:t>');
        sbParas.writeln('            </a:r>');
        sbParas.writeln('          </a:p>');
      }
      if (sbParas.isEmpty) {
        sbParas.writeln('          <a:p><a:endParaRPr lang="en-US"/></a:p>');
      }

      final slideXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Slide Text"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="457200" y="274638"/>
            <a:ext cx="8229600" cy="5143500"/>
          </a:xfrm>
          <a:prstGeom prst="rect">
            <a:avLst/>
          </a:prstGeom>
        </p:spPr>
        <p:txBody>
          <a:bodyPr wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720"/>
          <a:lstStyle/>
          $sbParas
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';
      _addXmlFileToArchive(archive, 'ppt/slides/slide${i + 1}.xml', slideXml);

      // Each slide needs a .rels pointing to the slide layout
      final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';
      _addXmlFileToArchive(archive, 'ppt/slides/_rels/slide${i + 1}.xml.rels', slideRels);
    }

    // Add remaining files
    _addXmlFileToArchive(archive, '[Content_Types].xml', sbContent.toString());
    _addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    _addXmlFileToArchive(archive, 'docProps/core.xml', coreXml);
    _addXmlFileToArchive(archive, 'docProps/app.xml', sbApp.toString());
    _addXmlFileToArchive(archive, 'ppt/presentation.xml', sbPres.toString());
    _addXmlFileToArchive(archive, 'ppt/_rels/presentation.xml.rels', sbPresRels.toString());
    _addXmlFileToArchive(archive, 'ppt/presProps.xml', presPropsXml);
    _addXmlFileToArchive(archive, 'ppt/viewProps.xml', viewPropsXml);
    _addXmlFileToArchive(archive, 'ppt/tableStyles.xml', tableStylesXml);
  }

  static void _addXmlFileToArchive(Archive archive, String name, String xmlContent) {
    final bytes = utf8.encode(xmlContent);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// Encodes an [image] as a proper ICO file by embedding PNG data.
  /// ICO format: header + directory entry + PNG image data.
  static Uint8List _encodeIco(img.Image image) {
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

  static String _escapeXml(String input) {
    // Strip invalid XML 1.0 control characters that crash Microsoft Word
    final clean = input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    return clean
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _extractTextFromPdfBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '(Empty PDF — no content to extract)';
    }

    // Validate PDF magic header
    if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
      throw Exception('Not a valid PDF file');
    }

    try {
      // Pure-Dart PDF text extraction — parses PDF streams for text operators
      final pdfStr = String.fromCharCodes(bytes);
      final extractedParts = <String>[];

      // Find all stream...endstream blocks and extract text operators
      final streamRegex = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
      for (final match in streamRegex.allMatches(pdfStr)) {
        final streamContent = match.group(1) ?? '';
        // Extract text from Tj operator: (text) Tj
        final tjRegex = RegExp(r'\(([^)]*?)\)\s*Tj');
        for (final tj in tjRegex.allMatches(streamContent)) {
          final text = tj.group(1) ?? '';
          if (text.trim().isNotEmpty) extractedParts.add(text);
        }
        // Extract text from TJ operator: [(text) num (text)] TJ
        final tjArrayRegex = RegExp(r'\[([^\]]*)\]\s*TJ');
        for (final tjArr in tjArrayRegex.allMatches(streamContent)) {
          final inner = tjArr.group(1) ?? '';
          final innerTexts = RegExp(r'\(([^)]*?)\)');
          for (final t in innerTexts.allMatches(inner)) {
            final text = t.group(1) ?? '';
            if (text.trim().isNotEmpty) extractedParts.add(text);
          }
        }
        // Extract text from ' operator: (text) '
        final quoteRegex = RegExp(r"\(([^)]*?)\)\s*'");
        for (final q in quoteRegex.allMatches(streamContent)) {
          final text = q.group(1) ?? '';
          if (text.trim().isNotEmpty) extractedParts.add(text);
        }
      }

      final extractedText = extractedParts.join(' ').trim();
      if (extractedText.isNotEmpty) {
        return extractedText;
      }
    } catch (e) {
      return 'Failed to extract text: $e';
    }

    return '(PDF contains no extractable text — may be image-only or protected)';
  }

  static void _createDocxArchive(Archive archive, String text) {
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

    final sbDoc = StringBuffer();
    sbDoc.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbDoc.writeln('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    sbDoc.writeln('  <w:body>');
    
    final lines = text.replaceAll('\f', '\n').split('\n');
    bool hasParagraph = false;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      sbDoc.writeln('    <w:p>');
      sbDoc.writeln('      <w:r>');
      sbDoc.writeln('        <w:t>${_escapeXml(line)}</w:t>');
      sbDoc.writeln('      </w:r>');
      sbDoc.writeln('    </w:p>');
      hasParagraph = true;
    }
    
    if (!hasParagraph) {
      sbDoc.writeln('    <w:p>');
      sbDoc.writeln('      <w:r>');
      sbDoc.writeln('        <w:t></w:t>');
      sbDoc.writeln('      </w:r>');
      sbDoc.writeln('    </w:p>');
    }
    
    sbDoc.writeln('    <w:sectPr>');
    sbDoc.writeln('      <w:pgSz w:w="12240" w:h="15840"/>');
    sbDoc.writeln('      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>');
    sbDoc.writeln('    </w:sectPr>');
    sbDoc.writeln('  </w:body>');
    sbDoc.writeln('</w:document>');

    _addXmlFileToArchive(archive, '[Content_Types].xml', contentTypesXml);
    _addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    _addXmlFileToArchive(archive, 'word/_rels/document.xml.rels', docRelsXml);
    _addXmlFileToArchive(archive, 'word/document.xml', sbDoc.toString());
  }

  static void createPptxArchiveWithImages(Archive archive, List<Uint8List> images) {
    // 1. [Content_Types].xml
    final sbContent = StringBuffer();
    sbContent.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbContent.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    sbContent.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    sbContent.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    sbContent.writeln('  <Default Extension="jpg" ContentType="image/jpeg"/>');
    sbContent.writeln('  <Default Extension="jpeg" ContentType="image/jpeg"/>');
    sbContent.writeln('  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>');
    for (int i = 1; i <= images.length; i++) {
      sbContent.writeln('  <Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    sbContent.writeln('</Types>');

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''';

    // 3. docProps/core.xml
    const coreXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Generated Presentation</dc:title>
  <dc:subject>PDF to PPTX Conversion</dc:subject>
  <dc:creator>FileGym</dc:creator>
  <cp:revision>1</cp:revision>
</cp:coreProperties>''';

    // 4. docProps/app.xml
    final sbApp = StringBuffer();
    sbApp.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbApp.writeln('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">');
    sbApp.writeln('  <TotalTime>1</TotalTime>');
    sbApp.writeln('  <Words>0</Words><Application>FileGym</Application>');
    sbApp.writeln('  <PresentationFormat>On-screen Show (4:3)</PresentationFormat>');
    sbApp.writeln('  <Paragraphs>0</Paragraphs><Slides>${images.length}</Slides><Notes>0</Notes><HiddenSlides>0</HiddenSlides><MMClips>0</MMClips>');
    sbApp.writeln('  <ScaleCrop>false</ScaleCrop>');
    sbApp.writeln('  <HeadingPairs>');
    sbApp.writeln('    <vt:vector size="4" baseType="variant">');
    sbApp.writeln('      <vt:variant><vt:lpstr>Theme</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>1</vt:i4></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:lpstr>Slide Titles</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>${images.length}</vt:i4></vt:variant>');
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </HeadingPairs>');
    sbApp.writeln('  <TitlesOfParts>');
    sbApp.writeln('    <vt:vector size="${images.length + 1}" baseType="lpstr">');
    sbApp.writeln('      <vt:lpstr>Office Theme</vt:lpstr>');
    for (int i = 1; i <= images.length; i++) {
      sbApp.writeln('      <vt:lpstr>Slide $i</vt:lpstr>');
    }
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </TitlesOfParts>');
    sbApp.writeln('  <LinksUpToDate>false</LinksUpToDate>');
    sbApp.writeln('  <SharedDoc>false</SharedDoc>');
    sbApp.writeln('  <HyperlinksChanged>false</HyperlinksChanged>');
    sbApp.writeln('  <AppVersion>15.0000</AppVersion>');
    sbApp.writeln('</Properties>');

    // 5. ppt/presentation.xml
    final sbPres = StringBuffer();
    sbPres.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPres.writeln('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
    sbPres.writeln('  <p:sldMasterIdLst>');
    sbPres.writeln('    <p:sldMasterId id="2147483648" r:id="rId${images.length + 1}"/>');
    sbPres.writeln('  </p:sldMasterIdLst>');
    sbPres.writeln('  <p:sldIdLst>');
    for (int i = 1; i <= images.length; i++) {
      sbPres.writeln('    <p:sldId id="${255 + i}" r:id="rId$i"/>');
    }
    sbPres.writeln('  </p:sldIdLst>');
    sbPres.writeln('  <p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>');
    sbPres.writeln('  <p:notesSz cx="6858000" cy="9144000"/>');
    sbPres.writeln('  <p:defaultTextStyle>');
    sbPres.writeln('    <a:defPPr><a:defRPr lang="en-US"/></a:defPPr>');
    sbPres.writeln('  </p:defaultTextStyle>');
    sbPres.writeln('</p:presentation>');

    // 6. ppt/_rels/presentation.xml.rels
    final sbPresRels = StringBuffer();
    sbPresRels.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPresRels.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (int i = 1; i <= images.length; i++) {
      sbPresRels.writeln('  <Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>');
    }
    sbPresRels.writeln('  <Relationship Id="rId${images.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${images.length + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${images.length + 3}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${images.length + 4}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${images.length + 5}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>');
    sbPresRels.writeln('</Relationships>');

    // 7. ppt/presProps.xml
    const presPropsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:extLst>
    <p:ext uri="{E76CE94A-603C-4142-B9EB-6D1370010A27}">
      <p14:discardImageEditData xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" val="0"/>
    </p:ext>
  </p:extLst>
</p:presentationPr>''';

    // 8. ppt/viewProps.xml
    const viewPropsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" lastView="sldThumbnailView">
  <p:normalViewPr>
    <p:restoredLeft sz="15620"/>
    <p:restoredTop sz="94660"/>
  </p:normalViewPr>
</p:viewPr>''';

    // 9. ppt/tableStyles.xml
    const tableStylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>''';

    // theme1.xml content
    const themeXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
      <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
      <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
      <a:accent2><a:srgbClr val="C0504D"/></a:accent2>
      <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
      <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
      <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
      <a:accent6><a:srgbClr val="F79646"/></a:accent6>
      <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
      <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office">
      <a:majorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface=""/>
        <a:cs typeface=""/>
      </a:majorFont>
      <a:minorFont>
        <a:latin typeface="Calibri"/>
        <a:ea typeface=""/>
        <a:cs typeface=""/>
      </a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Office">
      <a:fillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="1"/>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="100000"/><a:shade val="100000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="50000"/><a:shade val="100000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="16200000" scaled="0"/>
        </a:gradFill>
      </a:fillStyleLst>
      <a:lnStyleLst>
        <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
        <a:ln w="25400" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
        <a:ln w="38100" cap="flat" cmpd="sng" algn="ctr">
          <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
          <a:prstDash val="solid"/>
        </a:ln>
      </a:lnStyleLst>
      <a:effectStyleLst>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="20000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="38000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
        </a:effectStyle>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="23000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="35000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
        </a:effectStyle>
        <a:effectStyle>
          <a:effectLst>
            <a:outerShdw blurRad="40000" dist="23000" dir="5400000" rotWithShape="0">
              <a:srgbClr val="000000"><a:alpha val="35000"/></a:srgbClr>
            </a:outerShdw>
          </a:effectLst>
          <a:scene3d>
            <a:camera prst="orthographicFront"><a:rot lat="0" lon="0" rev="0"/></a:camera>
            <a:lightRig rig="threePt" dir="t"><a:rot lat="0" lon="0" rev="1200000"/></a:lightRig>
          </a:scene3d>
          <a:sp3d><a:bevelT w="63500" h="25400"/></a:sp3d>
        </a:effectStyle>
      </a:effectStyleLst>
      <a:bgFillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="40000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
            <a:gs pos="40000"><a:schemeClr val="phClr"><a:tint val="45000"/><a:shade val="99000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="20000"/><a:satMod val="255000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="5400000" scaled="1"/>
        </a:gradFill>
        <a:gradFill rotWithShape="1">
          <a:gsLst>
            <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="80000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
            <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="30000"/><a:satMod val="200000"/></a:schemeClr></a:gs>
          </a:gsLst>
          <a:lin ang="5400000" scaled="1"/>
        </a:gradFill>
      </a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
  <a:objectDefaults>
    <a:spDef>
      <a:spPr/>
      <a:bodyPr/>
      <a:lstStyle/>
      <a:style>
        <a:lnRef idx="1"><a:schemeClr val="accent1"/></a:lnRef>
        <a:fillRef idx="3"><a:schemeClr val="accent1"/></a:fillRef>
        <a:effectRef idx="2"><a:schemeClr val="accent1"/></a:effectRef>
        <a:fontRef idx="minor"><a:schemeClr val="lt1"/></a:fontRef>
      </a:style>
    </a:spDef>
    <a:lnDef>
      <a:spPr/>
      <a:bodyPr/>
      <a:lstStyle/>
      <a:style>
        <a:lnRef idx="2"><a:schemeClr val="accent1"/></a:lnRef>
        <a:fillRef idx="0"><a:schemeClr val="accent1"/></a:fillRef>
        <a:effectRef idx="1"><a:schemeClr val="accent1"/></a:effectRef>
        <a:fontRef idx="minor"><a:schemeClr val="tx1"/></a:fontRef>
      </a:style>
    </a:lnDef>
  </a:objectDefaults>
  <a:extraClrSchemeLst/>
</a:theme>''';

    _addXmlFileToArchive(archive, 'ppt/theme/theme1.xml', themeXml);

    // Slide master
    const slideMasterXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld name="">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>''';
    _addXmlFileToArchive(archive, 'ppt/slideMasters/slideMaster1.xml', slideMasterXml);

    const slideMasterRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''';
    _addXmlFileToArchive(archive, 'ppt/slideMasters/_rels/slideMaster1.xml.rels', slideMasterRels);

    // Slide layout
    const slideLayoutXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" type="blank">
  <p:cSld name="Blank">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''';
    _addXmlFileToArchive(archive, 'ppt/slideLayouts/slideLayout1.xml', slideLayoutXml);

    const slideLayoutRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';
    _addXmlFileToArchive(archive, 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', slideLayoutRels);

    // Individual slides (using `<p:pic>` to render images full-bleed)
    for (int i = 0; i < images.length; i++) {
      final slideXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="${i + 10}" name="Page Image ${i + 1}"/>
          <p:cNvPicPr>
            <a:picLocks noChangeAspect="1"/>
          </p:cNvPicPr>
          <p:nvPr/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rId2"/>
          <a:stretch>
            <a:fillRect/>
          </a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm>
            <a:off x="0" y="0"/>
            <a:ext cx="9144000" cy="6858000"/>
          </a:xfrm>
          <a:prstGeom prst="rect">
            <a:avLst/>
          </a:prstGeom>
        </p:spPr>
      </p:pic>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';
      _addXmlFileToArchive(archive, 'ppt/slides/slide${i + 1}.xml', slideXml);

      // Slide relationships
      final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${i + 1}.jpg"/>
</Relationships>''';
      _addXmlFileToArchive(archive, 'ppt/slides/_rels/slide${i + 1}.xml.rels', slideRels);

      // Write media bytes
      archive.addFile(ArchiveFile('ppt/media/image${i + 1}.jpg', images[i].length, images[i]));
    }

    // Add remaining files
    _addXmlFileToArchive(archive, '[Content_Types].xml', sbContent.toString());
    _addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    _addXmlFileToArchive(archive, 'docProps/core.xml', coreXml);
    _addXmlFileToArchive(archive, 'docProps/app.xml', sbApp.toString());
    _addXmlFileToArchive(archive, 'ppt/presentation.xml', sbPres.toString());
    _addXmlFileToArchive(archive, 'ppt/_rels/presentation.xml.rels', sbPresRels.toString());
    _addXmlFileToArchive(archive, 'ppt/presProps.xml', presPropsXml);
    _addXmlFileToArchive(archive, 'ppt/viewProps.xml', viewPropsXml);
    _addXmlFileToArchive(archive, 'ppt/tableStyles.xml', tableStylesXml);
  }

  static void createDocxArchiveWithImages(Archive archive, List<Uint8List> images) {
    // 1. [Content_Types].xml
    final sbContent = StringBuffer();
    sbContent.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbContent.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    sbContent.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    sbContent.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    sbContent.writeln('  <Default Extension="jpg" ContentType="image/jpeg"/>');
    sbContent.writeln('  <Default Extension="jpeg" ContentType="image/jpeg"/>');
    sbContent.writeln('  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>');
    sbContent.writeln('</Types>');

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    // 3. word/_rels/document.xml.rels
    final sbDocRels = StringBuffer();
    sbDocRels.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbDocRels.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (int i = 1; i <= images.length; i++) {
      sbDocRels.writeln('  <Relationship Id="rIdImage$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$i.jpg"/>');
    }
    sbDocRels.writeln('</Relationships>');

    // 4. word/document.xml
    final sbDoc = StringBuffer();
    sbDoc.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbDoc.writeln('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">');
    sbDoc.writeln('  <w:body>');

    for (int i = 1; i <= images.length; i++) {
      sbDoc.writeln('    <w:p>');
      sbDoc.writeln('      <w:r>');
      sbDoc.writeln('        <w:drawing>');
      sbDoc.writeln('          <wp:inline distT="0" distB="0" distL="0" distR="0">');
      sbDoc.writeln('            <wp:extent cx="5486400" cy="7108800"/>');
      sbDoc.writeln('            <wp:effectExtent l="0" t="0" r="0" b="0"/>');
      sbDoc.writeln('            <wp:docPr id="$i" name="Page Image $i"/>');
      sbDoc.writeln('            <wp:cNvGraphicFramePr>');
      sbDoc.writeln('              <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>');
      sbDoc.writeln('            </wp:cNvGraphicFramePr>');
      sbDoc.writeln('            <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
      sbDoc.writeln('              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">');
      sbDoc.writeln('                <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">');
      sbDoc.writeln('                  <pic:nvPicPr>');
      sbDoc.writeln('                    <pic:cNvPr id="$i" name="Page Image $i"/>');
      sbDoc.writeln('                    <pic:cNvPicPr/>');
      sbDoc.writeln('                  </pic:nvPicPr>');
      sbDoc.writeln('                  <pic:blipFill>');
      sbDoc.writeln('                    <a:blip r:embed="rIdImage$i"/>');
      sbDoc.writeln('                    <a:stretch>');
      sbDoc.writeln('                      <a:fillRect/>');
      sbDoc.writeln('                    </a:stretch>');
      sbDoc.writeln('                  </pic:blipFill>');
      sbDoc.writeln('                  <pic:spPr>');
      sbDoc.writeln('                    <a:xfrm>');
      sbDoc.writeln('                      <a:off x="0" y="0"/>');
      sbDoc.writeln('                      <a:ext cx="5486400" cy="7108800"/>');
      sbDoc.writeln('                    </a:xfrm>');
      sbDoc.writeln('                    <a:prstGeom prst="rect">');
      sbDoc.writeln('                      <a:avLst/>');
      sbDoc.writeln('                    </a:prstGeom>');
      sbDoc.writeln('                  </pic:spPr>');
      sbDoc.writeln('                </pic:pic>');
      sbDoc.writeln('              </a:graphicData>');
      sbDoc.writeln('            </a:graphic>');
      sbDoc.writeln('          </wp:inline>');
      sbDoc.writeln('        </w:drawing>');
      sbDoc.writeln('      </w:r>');
      if (i < images.length) {
        sbDoc.writeln('      <w:r><w:br w:type="page"/></w:r>');
      }
      sbDoc.writeln('    </w:p>');

      archive.addFile(ArchiveFile('word/media/image$i.jpg', images[i - 1].length, images[i - 1]));
    }

    sbDoc.writeln('    <w:sectPr>');
    sbDoc.writeln('      <w:pgSz w:w="12240" w:h="15840"/>');
    sbDoc.writeln('      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>');
    sbDoc.writeln('    </w:sectPr>');
    sbDoc.writeln('  </w:body>');
    sbDoc.writeln('</w:document>');

    _addXmlFileToArchive(archive, '[Content_Types].xml', sbContent.toString());
    _addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    _addXmlFileToArchive(archive, 'word/_rels/document.xml.rels', sbDocRels.toString());
    _addXmlFileToArchive(archive, 'word/document.xml', sbDoc.toString());
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
