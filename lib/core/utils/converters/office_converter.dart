import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import '../extractors/docx_text_extractor.dart';
import '../extractors/pptx_text_extractor.dart';
import '../extractors/pdf_text_extractor.dart';
import '../builders/docx_archive_builder.dart';
import '../builders/pptx_archive_builder.dart';
import 'pdf_converter.dart';

/// Handles conversions to DOCX, XLSX, and PPTX formats.
class OfficeConverter {
  static bool _isPdf(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  }

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

  static Future<String> convert({
    required String sourcePath,
    required String targetFormat,
    required Uint8List bytes,
    required String baseName,
    required String outputPath,
    required bool isZip,
  }) async {
    final ext = targetFormat.toLowerCase();
    final outputFile = File(outputPath);

    if (ext == 'docx') {
      await _convertToDocx(sourcePath, bytes, baseName, outputFile, isZip);
    } else if (ext == 'xlsx') {
      await _convertToXlsx(sourcePath, bytes, outputFile, isZip);
    } else if (ext == 'pptx') {
      await _convertToPptx(sourcePath, bytes, baseName, outputFile, isZip);
    } else {
      throw Exception('OfficeConverter does not handle .$ext');
    }
    return outputPath;
  }

  static Future<void> _convertToDocx(String sourcePath, Uint8List bytes, String baseName, File outputFile, bool isZip) async {
    final archive = Archive();
    bool convertedWithImages = false;
    final sourceLower = sourcePath.toLowerCase();
    final isPdf = sourceLower.endsWith('.pdf') || _isPdf(bytes);

    if (isPdf && Platform.isAndroid) {
      try {
        final pageCount = await PdfConverter.getNativePdfPageCount(sourcePath);
        final tempDir = Directory.systemTemp;
        final images = <Uint8List>[];
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        for (int i = 0; i < pageCount; i++) {
          final pageImagePath = '${tempDir.path}${Platform.pathSeparator}${baseName}_page_$i.jpg';
          final success = await channel.invokeMethod<bool>('renderPdfPage', {
            'pdfPath': sourcePath, 'outputPath': pageImagePath, 'pageIndex': i,
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
          DocxArchiveBuilder.createDocxArchiveWithImages(archive, images);
          final zipBytes = ZipEncoder().encode(archive);
          if (zipBytes != null) {
            await outputFile.writeAsBytes(zipBytes);
            convertedWithImages = true;
          }
        }
      } catch (_) {}
    }

    if (!convertedWithImages) {
      String text;
      if (isPdf) {
        text = PdfTextExtractor.extractText(bytes);
      } else if (sourceLower.endsWith('.pptx') || (isZip && _isPptxZip(bytes))) {
        text = PptxTextExtractor.extractSlides(bytes).join('\n\n');
      } else if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
        text = String.fromCharCodes(bytes);
      } else if (sourceLower.endsWith('.txt') || (!isZip && !_isJson(bytes))) {
        text = String.fromCharCodes(bytes);
      } else if (sourceLower.endsWith('.xlsx') || (isZip && _isExcelZip(bytes))) {
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
      DocxArchiveBuilder.createDocxArchive(archive, text);
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes != null) {
        await outputFile.writeAsBytes(zipBytes);
      } else {
        throw Exception('Failed to generate DOCX');
      }
    }
  }

  static Future<void> _convertToXlsx(String sourcePath, Uint8List bytes, File outputFile, bool isZip) async {
    final excel = Excel.createExcel();
    final sheet = excel.sheets[excel.sheets.keys.first]!;
    final sourceLower = sourcePath.toLowerCase();

    if (sourceLower.endsWith('.json') || _isJson(bytes)) {
      final decoded = json.decode(utf8.decode(bytes));
      if (decoded is List) {
        if (decoded.isNotEmpty && decoded.first is Map) {
          final keys = (decoded.first as Map).keys.toList();
          for (int c = 0; c < keys.length; c++) {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(keys[c].toString());
          }
          for (int r = 0; r < decoded.length; r++) {
            final item = decoded[r] as Map;
            for (int c = 0; c < keys.length; c++) {
              sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = TextCellValue(item[keys[c]]?.toString() ?? '');
            }
          }
        }
      } else if (decoded is Map) {
        final keys = decoded.keys.toList();
        for (int r = 0; r < keys.length; r++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(keys[r]);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(decoded[keys[r]]?.toString() ?? '');
        }
      }
    } else {
      String text;
      if (sourceLower.endsWith('.pdf') || _isPdf(bytes)) {
        text = PdfTextExtractor.extractText(bytes);
      } else if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
        text = String.fromCharCodes(bytes);
      } else if (sourceLower.endsWith('.docx') || (isZip && _isWordZip(bytes))) {
        text = DocxTextExtractor.extractText(bytes);
      } else if (sourceLower.endsWith('.pptx') || (isZip && _isPptxZip(bytes))) {
        text = PptxTextExtractor.extractSlides(bytes).join('\n\n');
      } else if (sourceLower.endsWith('.txt') || (!isZip && !_isJson(bytes))) {
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
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(columns[c].trim());
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

  static Future<void> _convertToPptx(String sourcePath, Uint8List bytes, String baseName, File outputFile, bool isZip) async {
    final archive = Archive();
    bool convertedWithImages = false;
    final sourceLower = sourcePath.toLowerCase();
    final isPdf = sourceLower.endsWith('.pdf') || _isPdf(bytes);

    if (isPdf && Platform.isAndroid) {
      try {
        final pageCount = await PdfConverter.getNativePdfPageCount(sourcePath);
        final tempDir = Directory.systemTemp;
        final images = <Uint8List>[];
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        for (int i = 0; i < pageCount; i++) {
          final pageImagePath = '${tempDir.path}${Platform.pathSeparator}${baseName}_page_$i.jpg';
          final success = await channel.invokeMethod<bool>('renderPdfPage', {
            'pdfPath': sourcePath, 'outputPath': pageImagePath, 'pageIndex': i,
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
          PptxArchiveBuilder.createPptxArchiveWithImages(archive, images);
          final zipBytes = ZipEncoder().encode(archive);
          if (zipBytes != null) {
            await outputFile.writeAsBytes(zipBytes);
            convertedWithImages = true;
          }
        }
      } catch (_) {}
    }

    if (!convertedWithImages) {
      String text;
      if (isPdf) {
        text = PdfTextExtractor.extractText(bytes);
      } else if (sourceLower.endsWith('.docx') || (isZip && _isWordZip(bytes))) {
        text = DocxTextExtractor.extractText(bytes);
      } else if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
        text = String.fromCharCodes(bytes);
      } else if (sourceLower.endsWith('.txt') || (!isZip && !_isJson(bytes))) {
        text = String.fromCharCodes(bytes);
      } else {
        text = 'Slide content';
      }
      final slides = text.split(RegExp(r'\n{2,}|\f'));
      try {
        PptxArchiveBuilder.createPptxArchive(archive, slides);
        final zipBytes = ZipEncoder().encode(archive);
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
}
