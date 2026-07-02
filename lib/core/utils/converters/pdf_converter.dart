import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import '../image_utils.dart';
import '../extractors/docx_text_extractor.dart';
import '../extractors/pptx_text_extractor.dart';

/// Handles all conversions TO PDF and PDF-related utilities.
class PdfConverter {
  static bool _isWordZip(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.files.any((f) {
        var name = f.name.replaceAll('\\', '/').toLowerCase();
        if (name.startsWith('/')) name = name.substring(1);
        return name == 'word/document.xml';
      });
    } catch (_) {}
    return false;
  }

  static bool _isExcelZip(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.files.any((f) {
        var name = f.name.replaceAll('\\', '/').toLowerCase();
        if (name.startsWith('/')) name = name.substring(1);
        return name == 'xl/workbook.xml';
      });
    } catch (_) {}
    return false;
  }

  static bool _isPptxZip(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.files.any((f) {
        var name = f.name.replaceAll('\\', '/').toLowerCase();
        if (name.startsWith('/')) name = name.substring(1);
        return name == 'ppt/presentation.xml';
      });
    } catch (_) {}
    return false;
  }

  static bool _isJson(Uint8List bytes) {
    try {
      final str = utf8.decode(bytes).trim();
      return (str.startsWith('{') && str.endsWith('}')) || (str.startsWith('[') && str.endsWith(']'));
    } catch (_) {}
    return false;
  }

  static bool _isCsv(Uint8List bytes) {
    try {
      final str = utf8.decode(bytes);
      return str.contains('\n') && str.contains(',');
    } catch (_) {}
    return false;
  }

  static bool _isSvg(Uint8List bytes) {
    try {
      final str = utf8.decode(bytes).trim();
      return str.contains('<svg') || str.startsWith('<svg');
    } catch (_) {}
    return false;
  }

  /// Gets PDF page count using native Android PdfRenderer — zero library cost.
  static Future<int> getNativePdfPageCount(String pdfPath) async {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
      final count = await channel.invokeMethod<int>('getPdfPageCount', {
        'pdfPath': pdfPath,
      });
      return count ?? 0;
    }
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final pdfStr = String.fromCharCodes(bytes);
      final countMatch = RegExp(r'/Count\s+(\d+)').firstMatch(pdfStr);
      if (countMatch != null) return int.parse(countMatch.group(1)!);
    } catch (_) {}
    return 1;
  }

  /// Stitches multiple images into a single PDF with layout options.
  static Future<String> stitchImagesToPdf({
    required List<String> imagePaths,
    required String pageSize,
    required String orientation,
    required String margin,
  }) async {
    final pdf = pw.Document();
    final tempDir = Directory.systemTemp;
    final needsDimensions = pageSize.toLowerCase() == 'fit' || orientation.toLowerCase() == 'auto';

    for (final path in imagePaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;

      Uint8List imageBytes;
      final baseName = p.basenameWithoutExtension(path);

      if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
        final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_temp.png';
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
          await channel.invokeMethod('convertHeic', {'heicPath': path, 'outputPath': tempImgPath});
        } else {
          final imgObj = img.Image(width: 10, height: 10);
          await File(tempImgPath).writeAsBytes(img.encodePng(imgObj));
        }
        imageBytes = await File(tempImgPath).readAsBytes();
        try { await File(tempImgPath).delete(); } catch (_) {}
      } else {
        imageBytes = bytes;
      }

      final imageWidget = pw.MemoryImage(imageBytes);
      int imgWidth = 0, imgHeight = 0;
      if (needsDimensions) {
        final dims = ImageUtils.readImageDimensions(imageBytes);
        if (dims != null) { imgWidth = dims[0]; imgHeight = dims[1]; }
      }

      PdfPageFormat format;
      if (pageSize.toLowerCase() == 'a4') {
        format = PdfPageFormat.a4;
      } else if (pageSize.toLowerCase() == 'letter') {
        format = PdfPageFormat.letter;
      } else {
        format = (imgWidth > 0 && imgHeight > 0)
            ? PdfPageFormat(imgWidth.toDouble(), imgHeight.toDouble(), marginAll: 0)
            : PdfPageFormat.a4;
      }

      if (pageSize.toLowerCase() != 'fit') {
        final double width = format.width, height = format.height;
        if (orientation.toLowerCase() == 'portrait') {
          if (width > height) format = format.copyWith(width: height, height: width);
        } else if (orientation.toLowerCase() == 'landscape') {
          if (width < height) format = format.copyWith(width: height, height: width);
        } else if (orientation.toLowerCase() == 'auto' && imgWidth > 0 && imgHeight > 0) {
          if ((imgWidth > imgHeight) != (width > height)) {
            format = format.copyWith(width: height, height: width);
          }
        }
      }

      double marginValue = 0.0;
      if (pageSize.toLowerCase() != 'fit') {
        if (margin.toLowerCase() == 'small') {
          marginValue = 10.0;
        } else if (margin.toLowerCase() == 'medium') {
          marginValue = 25.0;
        }
      }
      format = format.copyWith(marginTop: marginValue, marginBottom: marginValue, marginLeft: marginValue, marginRight: marginValue);

      pdf.addPage(pw.Page(
        pageFormat: format,
        build: (pw.Context context) => pw.Center(
          child: pw.Image(imageWidget, fit: pageSize.toLowerCase() == 'fit' ? pw.BoxFit.fill : pw.BoxFit.contain),
        ),
      ));
    }

    final baseName = imagePaths.isNotEmpty ? p.basenameWithoutExtension(imagePaths.first) : 'stitch';
    final outputPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_stitch_converted.pdf';
    await File(outputPath).writeAsBytes(await pdf.save());
    return outputPath;
  }

  /// Converts any supported source format to PDF.
  static Future<String> convert({
    required String sourcePath,
    required Uint8List bytes,
    required String baseName,
    required String outputPath,
    required bool isZip,
  }) async {
    final pdf = pw.Document();
    final tempDir = Directory.systemTemp;
    final sourceLower = sourcePath.toLowerCase();

    if (ImageUtils.isImageExtension(sourcePath) || sourceLower.endsWith('.heic') || sourceLower.endsWith('.heif')) {
      Uint8List imageBytes;
      if (sourceLower.endsWith('.heic') || sourceLower.endsWith('.heif')) {
        final tempImgPath = '${tempDir.path}${Platform.pathSeparator}${baseName}_temp.png';
        if (Platform.isAndroid) {
          final channel = const MethodChannel('com.akhilbehara.filegym/media_scanner');
          await channel.invokeMethod('convertHeic', {'heicPath': sourcePath, 'outputPath': tempImgPath});
        } else {
          final imgObj = img.Image(width: 10, height: 10);
          await File(tempImgPath).writeAsBytes(img.encodePng(imgObj));
        }
        imageBytes = await File(tempImgPath).readAsBytes();
        await File(tempImgPath).delete();
      } else {
        imageBytes = bytes;
      }
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Could not decode image — file may be corrupted or in an unsupported format');
      final pngBytes = img.encodePng(image);
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(pngBytes)))));
    } else if (sourceLower.endsWith('.svg') || _isSvg(bytes)) {
      final raster = ImageUtils.rasterizeSvg(String.fromCharCodes(bytes));
      final pngBytes = img.encodePng(raster);
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(pngBytes)))));
    } else if (sourceLower.endsWith('.md') || sourceLower.endsWith('.markdown')) {
      final mdLines = utf8.decode(bytes).split('\n');
      final widgets = <pw.Widget>[];
      for (final line in mdLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) { widgets.add(pw.SizedBox(height: 10)); continue; }
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
          widgets.add(pw.Padding(padding: const pw.EdgeInsets.only(left: 10, bottom: 4), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('• ', style: const pw.TextStyle(fontSize: 14)),
            pw.Expanded(child: pw.Text(trimmed.substring(2).replaceAll('**', '').replaceAll('*', '').replaceAll('`', ''), style: const pw.TextStyle(fontSize: 14))),
          ])));
        } else {
          widgets.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Text(trimmed.replaceAll('**', '').replaceAll('*', '').replaceAll('`', ''), style: const pw.TextStyle(fontSize: 14))));
        }
      }
      pdf.addPage(pw.MultiPage(build: (pw.Context context) => widgets));
    } else if (sourceLower.endsWith('.json') || _isJson(bytes)) {
      final decoded = json.decode(utf8.decode(bytes));
      final tableData = <List<String>>[];
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final keys = (decoded.first as Map).keys.map((k) => k.toString()).toList();
        tableData.add(keys);
        for (final item in decoded) {
          if (item is Map) tableData.add(keys.map((k) => item[k]?.toString() ?? '').toList());
        }
      }
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 20),
        if (tableData.isNotEmpty) pw.TableHelper.fromTextArray(data: tableData) else pw.Text('Empty JSON Data'),
      ]))));
    } else if (sourceLower.endsWith('.docx') || (isZip && _isWordZip(bytes))) {
      if (!isZip) throw Exception('Invalid or legacy Word document. Only modern .docx files are supported.');
      final text = DocxTextExtractor.extractText(bytes);
      
      // Check for embedded media/images inside the zip (common in PDF -> DOCX conversions)
      final archive = ZipDecoder().decodeBytes(bytes);
      final mediaFiles = archive.files.where((f) {
        final name = f.name.replaceAll('\\', '/').toLowerCase();
        return name.contains('word/media/') && (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'));
      }).toList();

      if (mediaFiles.isNotEmpty && text.trim().isEmpty) {
        mediaFiles.sort((a, b) {
          final aNum = int.tryParse(RegExp(r'\d+').stringMatch(a.name.split('/').last) ?? '') ?? 0;
          final bNum = int.tryParse(RegExp(r'\d+').stringMatch(b.name.split('/').last) ?? '') ?? 0;
          return aNum.compareTo(bNum);
        });
        for (final file in mediaFiles) {
          final imgBytes = file.content is Uint8List
              ? file.content as Uint8List
              : Uint8List.fromList(file.content as List<int>);
          pdf.addPage(pw.Page(
            build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(imgBytes))),
          ));
        }
      } else {
        final lines = text.split('\n');
        final widgets = <pw.Widget>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            widgets.add(pw.SizedBox(height: 10));
            continue;
          }
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(trimmed, style: const pw.TextStyle(fontSize: 14)),
          ));
        }
        pdf.addPage(pw.MultiPage(build: (pw.Context context) => widgets));
      }
    } else if (sourceLower.endsWith('.pptx') || (isZip && _isPptxZip(bytes))) {
      if (!isZip) throw Exception('Invalid or legacy PowerPoint presentation. Only modern .pptx files are supported.');
      final slides = PptxTextExtractor.extractSlides(bytes);
      
      // Check for embedded media/images inside the zip (common in PDF -> PPTX conversions)
      final archive = ZipDecoder().decodeBytes(bytes);
      final mediaFiles = archive.files.where((f) {
        final name = f.name.replaceAll('\\', '/').toLowerCase();
        return name.contains('ppt/media/') && (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'));
      }).toList();

      final isTextEmpty = slides.every((s) => s.trim().isEmpty || s.contains('(No text content on this slide)') || s.contains('(No slide content found)'));

      if (mediaFiles.isNotEmpty && isTextEmpty) {
        mediaFiles.sort((a, b) {
          final aNum = int.tryParse(RegExp(r'\d+').stringMatch(a.name.split('/').last) ?? '') ?? 0;
          final bNum = int.tryParse(RegExp(r'\d+').stringMatch(b.name.split('/').last) ?? '') ?? 0;
          return aNum.compareTo(bNum);
        });
        for (final file in mediaFiles) {
          final imgBytes = file.content is Uint8List
              ? file.content as Uint8List
              : Uint8List.fromList(file.content as List<int>);
          pdf.addPage(pw.Page(
            build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(imgBytes))),
          ));
        }
      } else {
        for (int i = 0; i < slides.length; i++) {
          pdf.addPage(pw.Page(build: (pw.Context context) => pw.Container(padding: const pw.EdgeInsets.all(32), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Slide ${i + 1}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 20), pw.Text(slides[i], style: const pw.TextStyle(fontSize: 16)),
          ]))));
        }
      }
    } else if (sourceLower.endsWith('.xlsx') || (isZip && _isExcelZip(bytes))) {
      if (!isZip) throw Exception('Invalid or legacy Excel spreadsheet. Only modern .xlsx files are supported.');
      final excel = Excel.decodeBytes(bytes);
      bool hasAddedSheet = false;

      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        final rows = sheet.rows;
        if (rows.isEmpty) continue;

        // Find max columns in this sheet to pad rows uniformly
        final maxCols = rows.fold<int>(0, (prev, row) => row.length > prev ? row.length : prev);
        if (maxCols == 0) continue;

        final tableData = <List<String>>[];
        for (final row in rows) {
          final rowData = <String>[];
          for (int i = 0; i < maxCols; i++) {
            if (i < row.length) {
              final cell = row[i];
              rowData.add(cell?.value?.toString() ?? '');
            } else {
              rowData.add('');
            }
          }
          tableData.add(rowData);
        }

        // Skip sheets with no data at all
        final hasData = tableData.any((r) => r.any((c) => c.trim().isNotEmpty));
        if (!hasData) continue;

        double fontSize = 10.0;
        if (maxCols > 12) {
          fontSize = 5.0;
        } else if (maxCols > 8) {
          fontSize = 7.0;
        } else if (maxCols > 5) {
          fontSize = 8.5;
        }

        pdf.addPage(
          pw.MultiPage(
            pageFormat: maxCols > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            build: (pw.Context context) {
              return [
                pw.Text(
                  'Sheet: $table',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('FF5C00'),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  data: tableData,
                  headerStyle: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('FFFFFF'),
                  ),
                  cellStyle: pw.TextStyle(
                    fontSize: fontSize,
                  ),
                  headerDecoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('FF5C00'),
                  ),
                  rowDecoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColor.fromHex('E0E0E0'), width: 0.5),
                    ),
                  ),
                  oddRowDecoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('FFF5F0'),
                  ),
                ),
              ];
            },
          ),
        );
        hasAddedSheet = true;
      }

      if (!hasAddedSheet) {
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) => pw.Center(
              child: pw.Text('Empty Spreadsheet'),
            ),
          ),
        );
      }
    } else if (sourceLower.endsWith('.txt')) {
      final txtContent = String.fromCharCodes(bytes);
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Text(txtContent))));
    } else if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
      final csvContent = String.fromCharCodes(bytes);
      final rows = csvContent.split('\n').where((r) => r.trim().isNotEmpty).toList();
      final tableData = rows.map((r) => r.split(',').map((c) => c.trim()).toList()).toList();
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(baseName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 20),
        if (tableData.isNotEmpty) pw.TableHelper.fromTextArray(data: tableData) else pw.Text('Empty CSV'),
      ]))));
    } else {
      final text = String.fromCharCodes(bytes);
      final isText = text.runes.every((r) => r < 0xFFFD || r == 0xFFFD);
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Padding(padding: const pw.EdgeInsets.all(24), child: isText
          ? pw.Text(text)
          : pw.Center(child: pw.Text('Converted Document: $baseName\n(Binary content — text extraction not available)')))));
    }

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(await pdf.save());
    return outputPath;
  }
}
