import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import '../extractors/docx_text_extractor.dart';
import '../extractors/pptx_text_extractor.dart';
import '../extractors/pdf_text_extractor.dart';

/// Handles conversions to TXT, CSV, and JSON formats.
class TextConverter {
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

    if (ext == 'txt') {
      await _convertToTxt(sourcePath, bytes, outputFile, isZip);
    } else if (ext == 'csv') {
      await _convertToCsv(sourcePath, bytes, outputFile, isZip);
    } else if (ext == 'json') {
      await _convertToJson(sourcePath, bytes, outputFile, baseName, isZip);
    } else {
      throw Exception('TextConverter does not handle .$ext');
    }
    return outputPath;
  }

  static Future<void> _convertToTxt(String sourcePath, Uint8List bytes, File outputFile, bool isZip) async {
    String textContent = '';
    final sourceLower = sourcePath.toLowerCase();

    if (sourceLower.endsWith('.docx') || (isZip && _isWordZip(bytes))) {
      textContent = DocxTextExtractor.extractText(bytes);
    } else if (sourceLower.endsWith('.pdf') || _isPdf(bytes)) {
      textContent = PdfTextExtractor.extractText(bytes);
    } else if (sourceLower.endsWith('.pptx') || (isZip && _isPptxZip(bytes))) {
      textContent = PptxTextExtractor.extractSlides(bytes).join('\n\n');
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
      textContent = sb.toString();
    } else if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
      textContent = String.fromCharCodes(bytes);
    } else if (sourceLower.endsWith('.md') || sourceLower.endsWith('.markdown')) {
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
    } else if (sourceLower.endsWith('.json') || _isJson(bytes)) {
      final decoded = json.decode(utf8.decode(bytes));
      textContent = const JsonEncoder.withIndent('  ').convert(decoded);
    } else {
      textContent = String.fromCharCodes(bytes);
    }
    await outputFile.writeAsString(textContent);
  }

  static Future<void> _convertToCsv(String sourcePath, Uint8List bytes, File outputFile, bool isZip) async {
    final sourceLower = sourcePath.toLowerCase();

    if (sourceLower.endsWith('.xlsx') || (isZip && _isExcelZip(bytes))) {
      final excel = Excel.decodeBytes(bytes);
      final sb = StringBuffer();
      
      Sheet? targetSheet;
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        if (sheet.rows.isNotEmpty) {
          targetSheet = sheet;
          break;
        }
      }
      if (targetSheet == null && excel.tables.isNotEmpty) {
        targetSheet = excel.tables.values.first;
      }

      if (targetSheet != null) {
        final rows = targetSheet.rows;
        final maxCols = rows.fold<int>(0, (prev, row) => row.length > prev ? row.length : prev);
        if (maxCols > 0) {
          for (final row in rows) {
            final rowData = <String>[];
            for (int i = 0; i < maxCols; i++) {
              String val = '';
              if (i < row.length) {
                val = row[i]?.value?.toString() ?? '';
              }
              if (val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r')) {
                val = '"${val.replaceAll('"', '""')}"';
              }
              rowData.add(val);
            }
            sb.writeln(rowData.join(','));
          }
        }
      }
      await outputFile.writeAsString(sb.toString());
    } else if (sourceLower.endsWith('.json') || _isJson(bytes)) {
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
    } else if (sourceLower.endsWith('.pdf') || _isPdf(bytes)) {
      final text = PdfTextExtractor.extractText(bytes);
      await outputFile.writeAsString(text);
    } else if (sourceLower.endsWith('.docx') || (isZip && _isWordZip(bytes))) {
      final text = DocxTextExtractor.extractText(bytes);
      await outputFile.writeAsString(text);
    } else if (sourceLower.endsWith('.pptx') || (isZip && _isPptxZip(bytes))) {
      final text = PptxTextExtractor.extractSlides(bytes).join('\n\n');
      await outputFile.writeAsString(text);
    } else {
      await outputFile.writeAsString(utf8.decode(bytes, allowMalformed: true));
    }
  }

  static Future<void> _convertToJson(String sourcePath, Uint8List bytes, File outputFile, String baseName, bool isZip) async {
    String textContent = '';
    final sourceLower = sourcePath.toLowerCase();

    if (sourceLower.endsWith('.csv') || _isCsv(bytes)) {
      final csvContent = utf8.decode(bytes);
      final lines = csvContent.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isNotEmpty) {
        final headers = lines.first.split(',').map((h) => h.trim()).toList();
        final resultList = <Map<String, dynamic>>[];
        for (int i = 1; i < lines.length; i++) {
          final cols = lines[i].split(',').map((c) => c.trim()).toList();
          final map = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) {
            map[headers[j]] = j < cols.length ? cols[j] : '';
          }
          resultList.add(map);
        }
        textContent = const JsonEncoder.withIndent('  ').convert(resultList);
      } else {
        textContent = '[]';
      }
    } else if (sourceLower.endsWith('.xlsx') || (isZip && _isExcelZip(bytes))) {
      final excel = Excel.decodeBytes(bytes);
      final sheetData = <String, List<Map<String, dynamic>>>{};
      
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        final rows = sheet.rows;
        if (rows.isEmpty) continue;

        // Find max columns in this sheet to normalize row lengths
        final maxCols = rows.fold<int>(0, (prev, row) => row.length > prev ? row.length : prev);
        if (maxCols == 0) continue;

        final tableData = <List<String>>[];
        for (final row in rows) {
          final rowData = <String>[];
          for (int i = 0; i < maxCols; i++) {
            if (i < row.length) {
              rowData.add(row[i]?.value?.toString() ?? '');
            } else {
              rowData.add('');
            }
          }
          tableData.add(rowData);
        }

        // Find the first non-empty row to act as headers
        int headerRowIndex = -1;
        for (int i = 0; i < tableData.length; i++) {
          if (tableData[i].any((c) => c.trim().isNotEmpty)) {
            headerRowIndex = i;
            break;
          }
        }
        if (headerRowIndex == -1) continue;

        // Generate unique header names to prevent duplicate key overwrite
        final rawHeaders = tableData[headerRowIndex];
        final headers = <String>[];
        final seenHeaders = <String, int>{};
        for (int j = 0; j < rawHeaders.length; j++) {
          String h = rawHeaders[j].trim();
          if (h.isEmpty) {
            h = 'Column_${j + 1}';
          }
          if (seenHeaders.containsKey(h)) {
            seenHeaders[h] = seenHeaders[h]! + 1;
            h = '${h}_${seenHeaders[h]}';
          } else {
            seenHeaders[h] = 1;
          }
          headers.add(h);
        }

        final list = <Map<String, dynamic>>[];
        for (int i = headerRowIndex + 1; i < tableData.length; i++) {
          final row = tableData[i];
          final isRowEmpty = row.every((c) => c.trim().isEmpty);
          if (isRowEmpty) continue;

          final map = <String, dynamic>{};
          for (int j = 0; j < headers.length; j++) {
            map[headers[j]] = row[j];
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
}
