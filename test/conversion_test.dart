// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:filegym/core/utils/file_converter.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:filegym/core/intelligence/file_intelligence_engine.dart';
import 'package:excel/excel.dart';

import 'package:filegym/core/utils/builders/docx_archive_builder.dart';
import 'package:filegym/core/utils/extractors/pdf_text_extractor.dart';

void main() {
  test('PDF to PPTX conversion test', () async {
    // 1. Generate a PDF file
    final pdf = pw.Document(compress: false);
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Text("Hello World PDF"),
          );
        },
      ),
    );
    
    final pdfFile = File('test_input.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    
    print("Generated PDF file: ${pdfFile.path}");
    
    // 2. Convert PDF to PPTX
    try {
      final outputPath = await FileConverter.convert(
        sourcePath: pdfFile.path,
        targetFormat: 'pptx',
      );
      print("Conversion success! Output: $outputPath");
      
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), isTrue);

      final archiveBytes = await outputFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final slideFile = archive.findFile('ppt/slides/slide1.xml');
      expect(slideFile, isNotNull);
      final slideXml = utf8.decode(slideFile!.content as List<int>);
      print("Slide XML: $slideXml");
      expect(slideXml, contains('Hello'));
      expect(slideXml, contains('World'));
      expect(slideXml, contains('PDF'));

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
    } catch (e, stackTrace) {
      print("Conversion failed with error: $e");
      print("StackTrace: $stackTrace");
      rethrow;
    } finally {
      if (await pdfFile.exists()) {
        await pdfFile.delete();
      }
    }
  });

  test('createPptxArchiveWithImages creates valid pptx structure', () {
    final archive = Archive();
    final images = [
      Uint8List.fromList([1, 2, 3, 4]),
      Uint8List.fromList([5, 6, 7, 8]),
    ];
    
    FileConverter.createPptxArchiveWithImages(archive, images);
    
    // Check that slides exist
    expect(archive.findFile('ppt/slides/slide1.xml'), isNotNull);
    expect(archive.findFile('ppt/slides/slide2.xml'), isNotNull);
    expect(archive.findFile('ppt/slides/slide3.xml'), isNull);
    
    // Check slide relations
    expect(archive.findFile('ppt/slides/_rels/slide1.xml.rels'), isNotNull);
    expect(archive.findFile('ppt/slides/_rels/slide2.xml.rels'), isNotNull);
    
    // Check embedded media
    expect(archive.findFile('ppt/media/image1.jpg'), isNotNull);
    expect(archive.findFile('ppt/media/image2.jpg'), isNotNull);
    
    // Check Content_Types
    final contentTypes = archive.findFile('[Content_Types].xml');
    expect(contentTypes, isNotNull);
    final contentTypesXml = utf8.decode(contentTypes!.content as List<int>);
    expect(contentTypesXml, contains('ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"'));
  });

  test('createDocxArchiveWithImages creates valid docx structure', () {
    final archive = Archive();
    final images = [
      Uint8List.fromList([1, 2, 3, 4]),
      Uint8List.fromList([5, 6, 7, 8]),
    ];
    
    FileConverter.createDocxArchiveWithImages(archive, images);
    
    // Check word document
    expect(archive.findFile('word/document.xml'), isNotNull);
    expect(archive.findFile('word/_rels/document.xml.rels'), isNotNull);
    
    // Check embedded media
    expect(archive.findFile('word/media/image1.jpg'), isNotNull);
    expect(archive.findFile('word/media/image2.jpg'), isNotNull);
    
    // Check document contents has images
    final docFile = archive.findFile('word/document.xml');
    final docXml = utf8.decode(docFile!.content as List<int>);
    expect(docXml, contains('<w:drawing>'));
    
    // Check Content_Types
    final contentTypes = archive.findFile('[Content_Types].xml');
    expect(contentTypes, isNotNull);
    final contentTypesXml = utf8.decode(contentTypes!.content as List<int>);
    expect(contentTypesXml, contains('ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"'));
  });

  test('HEIC to JPG conversion', () async {
    final tempDir = Directory.systemTemp;
    final heicFile = File('${tempDir.path}/test_input.heic');
    await heicFile.writeAsBytes(Uint8List.fromList([0, 1, 2, 3]));

    try {
      final outputPath = await FileConverter.convert(
        sourcePath: heicFile.path,
        targetFormat: 'jpg',
      );
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), isTrue);
      await outputFile.delete();
    } finally {
      if (await heicFile.exists()) {
        await heicFile.delete();
      }
    }
  });

  test('Markdown to PDF and Markdown to TXT conversion', () async {
    final tempDir = Directory.systemTemp;
    final mdFile = File('${tempDir.path}/test_doc.md');
    await mdFile.writeAsString('''# Title
## Header 2
- Bullet item 1
- Bullet item 2
Normal paragraph text.''');

    try {
      // 1. Markdown to PDF
      final pdfPath = await FileConverter.convert(
        sourcePath: mdFile.path,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);
      await pdfFile.delete();

      // 2. Markdown to TXT
      final txtPath = await FileConverter.convert(
        sourcePath: mdFile.path,
        targetFormat: 'txt',
      );
      final txtFile = File(txtPath);
      expect(await txtFile.exists(), isTrue);
      final txtContent = await txtFile.readAsString();
      expect(txtContent, contains('TITLE'));
      expect(txtContent, contains('Header 2'));
      expect(txtContent, contains('• Bullet item 1'));
      await txtFile.delete();
    } finally {
      if (await mdFile.exists()) {
        await mdFile.delete();
      }
    }
  });

  test('PDF to ZIP image extraction', () async {
    final pdf = pw.Document(compress: false);
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(child: pw.Text("Page 1"));
        },
      ),
    );
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(child: pw.Text("Page 2"));
        },
      ),
    );

    final tempDir = Directory.systemTemp;
    final pdfFile = File('${tempDir.path}/test_pages.pdf');
    await pdfFile.writeAsBytes(await pdf.save());

    try {
      final zipPath = await FileConverter.convert(
        sourcePath: pdfFile.path,
        targetFormat: 'zip',
      );
      final zipFile = File(zipPath);
      expect(await zipFile.exists(), isTrue);

      final zipBytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      expect(archive.findFile('test_pages_page_1.jpg'), isNotNull);
      expect(archive.findFile('test_pages_page_2.jpg'), isNotNull);
      await zipFile.delete();
    } finally {
      if (await pdfFile.exists()) {
        await pdfFile.delete();
      }
    }
  });

  test('Data & Spreadsheets JSON/CSV/XLSX cross conversions', () async {
    final tempDir = Directory.systemTemp;
    final jsonFile = File('${tempDir.path}/data.json');
    final data = [
      {'name': 'Alice', 'age': '30'},
      {'name': 'Bob', 'age': '25'},
    ];
    await jsonFile.writeAsString(json.encode(data));

    final csvFile = File('${tempDir.path}/data.csv');
    await csvFile.writeAsString('name,age\nAlice,30\nBob,25\n');

    try {
      // 1. JSON to CSV
      final csvOutPath = await FileConverter.convert(
        sourcePath: jsonFile.path,
        targetFormat: 'csv',
      );
      final csvOut = File(csvOutPath);
      expect(await csvOut.exists(), isTrue);
      final csvContent = await csvOut.readAsString();
      expect(csvContent, contains('Alice,30'));
      expect(csvContent, contains('Bob,25'));
      await csvOut.delete();

      // 2. CSV to JSON
      final jsonOutPath = await FileConverter.convert(
        sourcePath: csvFile.path,
        targetFormat: 'json',
      );
      final jsonOut = File(jsonOutPath);
      expect(await jsonOut.exists(), isTrue);
      final jsonContent = await jsonOut.readAsString();
      final decodedCsvJson = json.decode(jsonContent) as List;
      expect(decodedCsvJson.length, equals(2));
      expect(decodedCsvJson[0]['name'], equals('Alice'));
      await jsonOut.delete();

      // 3. JSON to XLSX
      final xlsxOutPath = await FileConverter.convert(
        sourcePath: jsonFile.path,
        targetFormat: 'xlsx',
      );
      final xlsxOut = File(xlsxOutPath);
      expect(await xlsxOut.exists(), isTrue);

      // 4. XLSX to JSON
      final jsonFromXlsxPath = await FileConverter.convert(
        sourcePath: xlsxOutPath,
        targetFormat: 'json',
      );
      final jsonFromXlsxFile = File(jsonFromXlsxPath);
      expect(await jsonFromXlsxFile.exists(), isTrue);
      final xlsxJsonContent = await jsonFromXlsxFile.readAsString();
      final xlsxDecoded = json.decode(xlsxJsonContent) as Map;
      expect(xlsxDecoded.keys, contains('Sheet1'));
      expect(xlsxDecoded['Sheet1'][0]['name'], contains('Alice'));

      await xlsxOut.delete();
      await jsonFromXlsxFile.delete();
    } finally {
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
      if (await csvFile.exists()) {
        await csvFile.delete();
      }
    }
  });

  test('Batch images to PDF stitching', () async {
    final tempDir = Directory.systemTemp;
    final img1 = File('${tempDir.path}/img1.png');
    final img2 = File('${tempDir.path}/img2.jpg');

    final dummyImage1 = img.Image(width: 10, height: 10);
    img.fill(dummyImage1, color: img.ColorRgb8(255, 0, 0));
    await img1.writeAsBytes(img.encodePng(dummyImage1));

    final dummyImage2 = img.Image(width: 20, height: 20);
    img.fill(dummyImage2, color: img.ColorRgb8(0, 255, 0));
    await img2.writeAsBytes(img.encodeJpg(dummyImage2));

    try {
      final batchPath = '${img1.path};${img2.path}';
      
      // 1. Analyze batch
      final analysis = await FileIntelligenceEngine.analyze(batchPath);
      expect(analysis.trueType, equals('Batch Images'));
      expect(analysis.fileName, equals('2 Images Batch'));
      expect(analysis.availableConversions.first.format, equals('PDF'));

      // 2. Convert batch to PDF
      final pdfPath = await FileConverter.convert(
        sourcePath: batchPath,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);

      // Verify the PDF contains pages by checking the header
      final pdfBytes = await pdfFile.readAsBytes();
      final pdfString = String.fromCharCodes(pdfBytes.take(10));
      expect(pdfString, startsWith('%PDF-'));
      expect(pdfBytes.length, greaterThan(0));

      await pdfFile.delete();
    } finally {
      if (await img1.exists()) await img1.delete();
      if (await img2.exists()) await img2.delete();
    }
  });

  test('Image format conversions (PNG/JPG/WEBP)', () async {
    final tempDir = Directory.systemTemp;
    final pngInputFile = File('${tempDir.path}/test_image_input.png');

    final dummyImage = img.Image(width: 50, height: 50);
    img.fill(dummyImage, color: img.ColorRgb8(0, 0, 255));
    await pngInputFile.writeAsBytes(img.encodePng(dummyImage));

    try {
      // 1. PNG to JPG
      final jpgPath = await FileConverter.convert(
        sourcePath: pngInputFile.path,
        targetFormat: 'jpg',
        quality: 90,
      );
      final jpgFile = File(jpgPath);
      expect(await jpgFile.exists(), isTrue);

      // Verify it's a valid JPEG image by decoding it
      final decodedJpg = img.decodeJpg(await jpgFile.readAsBytes());
      expect(decodedJpg, isNotNull);
      expect(decodedJpg!.width, equals(50));
      expect(decodedJpg.height, equals(50));

      // 2. JPG to WEBP (falls back to PNG in pure Dart but returns correct output path extension/bytes)
      final webpPath = await FileConverter.convert(
        sourcePath: jpgPath,
        targetFormat: 'webp',
      );
      final webpFile = File(webpPath);
      expect(await webpFile.exists(), isTrue);
      expect(webpPath.endsWith('.webp'), isTrue);

      await jpgFile.delete();
      await webpFile.delete();
    } finally {
      if (await pngInputFile.exists()) {
        await pngInputFile.delete();
      }
    }
  });

  test('Legacy Office formats rejection test', () async {
    final tempDir = Directory.systemTemp;
    final xlsFile = File('${tempDir.path}/test_legacy.xls');
    final docFile = File('${tempDir.path}/test_legacy.doc');
    final pptFile = File('${tempDir.path}/test_legacy.ppt');

    await xlsFile.writeAsBytes([1, 2, 3]);
    await docFile.writeAsBytes([1, 2, 3]);
    await pptFile.writeAsBytes([1, 2, 3]);

    try {
      await expectLater(
        FileConverter.convert(sourcePath: xlsFile.path, targetFormat: 'pdf'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Legacy Microsoft Office formats (.xls) are not supported'))),
      );

      await expectLater(
        FileConverter.convert(sourcePath: docFile.path, targetFormat: 'pdf'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Legacy Microsoft Office formats (.doc) are not supported'))),
      );

      await expectLater(
        FileConverter.convert(sourcePath: pptFile.path, targetFormat: 'pdf'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Legacy Microsoft Office formats (.ppt) are not supported'))),
      );
    } finally {
      if (await xlsFile.exists()) await xlsFile.delete();
      if (await docFile.exists()) await docFile.delete();
      if (await pptFile.exists()) await pptFile.delete();
    }
  });

  test('Zip signature validation test for DOCX, XLSX, PPTX', () async {
    final tempDir = Directory.systemTemp;
    final fakeDocxFile = File('${tempDir.path}/fake.docx');
    // Not a zip file, just plain text
    await fakeDocxFile.writeAsString('This is not a zip file');

    try {
      await expectLater(
        FileConverter.convert(sourcePath: fakeDocxFile.path, targetFormat: 'pdf'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Only modern .docx files are supported'))),
      );
    } finally {
      if (await fakeDocxFile.exists()) await fakeDocxFile.delete();
    }
  });

  test('XLSX to PDF conversion test', () async {
    final tempDir = Directory.systemTemp;
    final jsonFile = File('${tempDir.path}/xlsx_test_data.json');
    final data = [
      {'name': 'Alice', 'age': '30'},
      {'name': 'Bob', 'age': '25'},
    ];
    await jsonFile.writeAsString(json.encode(data));

    try {
      // 1. Convert JSON to XLSX
      final xlsxPath = await FileConverter.convert(
        sourcePath: jsonFile.path,
        targetFormat: 'xlsx',
      );
      final xlsxFile = File(xlsxPath);
      expect(await xlsxFile.exists(), isTrue);

      // Print cell values to see what toString() returns
      final excelBytes = await xlsxFile.readAsBytes();
      final excel = Excel.decodeBytes(excelBytes);
      if (excel.tables.isNotEmpty) {
        final sheet = excel.tables.values.first;
        for (final row in sheet.rows) {
          for (final cell in row) {
            print('Cell value: ${cell?.value} | toString(): ${cell?.value?.toString()} | runtimeType: ${cell?.value.runtimeType}');
          }
        }
      }

      // 2. Convert XLSX to PDF
      final pdfPath = await FileConverter.convert(
        sourcePath: xlsxPath,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);
      print('XLSX to PDF successful, output: $pdfPath');

      await xlsxFile.delete();
      await pdfFile.delete();
    } catch (e, stackTrace) {
      print('XLSX to PDF failed with error: $e');
      print('StackTrace: $stackTrace');
      rethrow;
    } finally {
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
    }
  });

  test('Large XLSX to PDF conversion test (100 rows)', () async {
    final tempDir = Directory.systemTemp;
    final jsonFile = File('${tempDir.path}/xlsx_large_test_data.json');
    final data = List.generate(100, (i) => {'index': '$i', 'name': 'User $i', 'value': 'Value $i'});
    await jsonFile.writeAsString(json.encode(data));

    try {
      // 1. Convert JSON to XLSX
      final xlsxPath = await FileConverter.convert(
        sourcePath: jsonFile.path,
        targetFormat: 'xlsx',
      );
      final xlsxFile = File(xlsxPath);
      expect(await xlsxFile.exists(), isTrue);

      // 2. Convert XLSX to PDF
      final pdfPath = await FileConverter.convert(
        sourcePath: xlsxPath,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);
      print('Large XLSX to PDF successful, output: $pdfPath');

      await xlsxFile.delete();
      await pdfFile.delete();
    } catch (e, stackTrace) {
      print('Large XLSX to PDF failed with error: $e');
      print('StackTrace: $stackTrace');
      rethrow;
    } finally {
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
    }
  });

  test('Varying row lengths XLSX to PDF conversion test', () async {
    final tempDir = Directory.systemTemp;
    final xlsxFile = File('${tempDir.path}/xlsx_varying_rows.xlsx');
    
    final excel = Excel.createExcel();
    final sheet = excel.sheets[excel.sheets.keys.first]!;
    
    // Row 0 has 3 cells
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Header1');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Header2');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Header3');
    
    // Row 1 has 2 cells
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Val1');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('Val2');
    
    // Row 2 has 4 cells
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('A');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('B');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('C');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2)).value = TextCellValue('D');

    final excelBytes = excel.encode();
    await xlsxFile.writeAsBytes(excelBytes!);

    try {
      final pdfPath = await FileConverter.convert(
        sourcePath: xlsxFile.path,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);
      print('Varying row lengths XLSX to PDF successful!');
      await pdfFile.delete();
    } catch (e, stackTrace) {
      print('Varying row lengths XLSX to PDF failed with error: $e');
      print('StackTrace: $stackTrace');
      rethrow;
    } finally {
      if (await xlsxFile.exists()) {
        await xlsxFile.delete();
      }
    }
  });

  test('Print CellValue types', () {
    print('TextCellValue: ${TextCellValue('Hello')} | toString: ${TextCellValue('Hello').toString()}');
    print('IntCellValue: ${IntCellValue(123)} | toString: ${IntCellValue(123).toString()}');
    print('DoubleCellValue: ${DoubleCellValue(12.34)} | toString: ${DoubleCellValue(12.34).toString()}');
    print('BoolCellValue: ${BoolCellValue(true)} | toString: ${BoolCellValue(true).toString()}');
  });

  test('XLSX to CSV and JSON robust conversions with empty leading rows, varying lengths, and duplicate headers', () async {
    final tempDir = Directory.systemTemp;
    final xlsxFile = File('${tempDir.path}/xlsx_robust_test.xlsx');
    
    final excel = Excel.createExcel();
    final sheet = excel.sheets[excel.sheets.keys.first]!;
    
    // Rows 0 and 1 are completely empty
    
    // Row 2 is the header row, containing duplicate names and empty cells
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Name');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('Age');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('Name'); // Duplicate
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2)).value = TextCellValue(''); // Empty header
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2)).value = TextCellValue('Role');

    // Row 3 is a data row with fewer elements
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Alice');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)).value = IntCellValue(30);

    // Row 4 is a data row with all elements
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Bob');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4)).value = IntCellValue(25);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 4)).value = TextCellValue('Bobby');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 4)).value = TextCellValue('Val');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4)).value = TextCellValue('Developer');

    final excelBytes = excel.encode();
    await xlsxFile.writeAsBytes(excelBytes!);

    try {
      // 1. XLSX to CSV
      final csvPath = await FileConverter.convert(
        sourcePath: xlsxFile.path,
        targetFormat: 'csv',
      );
      final csvFile = File(csvPath);
      expect(await csvFile.exists(), isTrue);
      
      final csvContent = await csvFile.readAsString();
      print('CSV Output:\n$csvContent');
      
      final csvLines = csvContent.split('\n').where((l) => l.isNotEmpty).toList();
      // Ensure all rows are padded to the maximum column count (5 columns)
      for (final line in csvLines) {
        expect(line.split(',').length, 5);
      }
      expect(csvLines[2], 'Name,Age,Name,,Role');
      expect(csvLines[3], 'Alice,30,,,');

      // 2. XLSX to JSON
      final jsonPath = await FileConverter.convert(
        sourcePath: xlsxFile.path,
        targetFormat: 'json',
      );
      final jsonFile = File(jsonPath);
      expect(await jsonFile.exists(), isTrue);

      final jsonContent = await jsonFile.readAsString();
      print('JSON Output:\n$jsonContent');

      final jsonDecoded = json.decode(jsonContent) as Map<String, dynamic>;
      final firstSheetData = jsonDecoded.values.first as List;
      
      expect(firstSheetData.length, 2);
      
      // Check resolved headers (duplicate Name becomes Name_2, empty becomes Column_4)
      final aliceObj = firstSheetData[0] as Map<String, dynamic>;
      expect(aliceObj.containsKey('Name'), isTrue);
      expect(aliceObj.containsKey('Name_2'), isTrue);
      expect(aliceObj.containsKey('Column_4'), isTrue);
      expect(aliceObj['Name'], 'Alice');
      expect(aliceObj['Age'], '30');
      expect(aliceObj['Name_2'], '');
      expect(aliceObj['Column_4'], '');
      expect(aliceObj['Role'], '');

      final bobObj = firstSheetData[1] as Map<String, dynamic>;
      expect(bobObj['Name'], 'Bob');
      expect(bobObj['Age'], '25');
      expect(bobObj['Name_2'], 'Bobby');
      expect(bobObj['Column_4'], 'Val');
      expect(bobObj['Role'], 'Developer');

      await csvFile.delete();
      await jsonFile.delete();
    } finally {
      if (await xlsxFile.exists()) {
        await xlsxFile.delete();
      }
    }
  });

  test('DOCX to PDF and DOCX to TXT conversion', () async {
    final tempDir = Directory.systemTemp;
    final docxFile = File('${tempDir.path}/test_doc.docx');
    
    // Build a text-only DOCX archive
    final archive = Archive();
    DocxArchiveBuilder.createDocxArchive(archive, 'Hello from Docx Converter\nSecond Line of text');
    final bytes = ZipEncoder().encode(archive);
    await docxFile.writeAsBytes(Uint8List.fromList(bytes!));

    try {
      // Test DOCX to TXT
      final txtPath = await FileConverter.convert(
        sourcePath: docxFile.path,
        targetFormat: 'txt',
      );
      final txtFile = File(txtPath);
      expect(await txtFile.exists(), isTrue);
      final txtContent = await txtFile.readAsString();
      expect(txtContent, contains('Hello from Docx Converter'));
      expect(txtContent, contains('Second Line of text'));
      await txtFile.delete();

      // Test DOCX to PDF
      final pdfPath = await FileConverter.convert(
        sourcePath: docxFile.path,
        targetFormat: 'pdf',
      );
      final pdfFile = File(pdfPath);
      expect(await pdfFile.exists(), isTrue);
      final pdfBytes = await pdfFile.readAsBytes();
      final pdfText = PdfTextExtractor.extractText(pdfBytes);
      expect(pdfText, contains('Hello from Docx Converter'));
      expect(pdfText, contains('Second Line of text'));
      await pdfFile.delete();
    } finally {
      if (await docxFile.exists()) {
        await docxFile.delete();
      }
    }
  });

  test('Robust content type detection for uppercase/mixed-case and extensionless files', () async {
    final tempDir = Directory.systemTemp;

    // 1. Prepare valid zip bytes for a minimal docx file
    final archiveDocx = Archive();
    DocxArchiveBuilder.createDocxArchive(archiveDocx, 'Robust Docx Content');
    final docxBytes = Uint8List.fromList(ZipEncoder().encode(archiveDocx)!);

    // Save with mixed case extension (.DoCx)
    final docxMixedFile = File('${tempDir.path}/test_mixed.DoCx');
    await docxMixedFile.writeAsBytes(docxBytes);

    // Save with no extension (just 'docx_raw')
    final docxNoExtFile = File('${tempDir.path}/docx_raw');
    await docxNoExtFile.writeAsBytes(docxBytes);

    // 2. Prepare JSON bytes
    final jsonBytes = utf8.encode(json.encode([{'header': 'json_val'}]));
    // Save with mixed case (.JsOn) and no extension
    final jsonMixedFile = File('${tempDir.path}/test_mixed.JsOn');
    await jsonMixedFile.writeAsBytes(jsonBytes);
    final jsonNoExtFile = File('${tempDir.path}/json_raw');
    await jsonNoExtFile.writeAsBytes(jsonBytes);

    // 3. Prepare CSV bytes
    final csvBytes = utf8.encode('header,value\ncsv_val_1,csv_val_2');
    // Save with mixed case (.CsV) and no extension
    final csvMixedFile = File('${tempDir.path}/test_mixed.CsV');
    await csvMixedFile.writeAsBytes(csvBytes);
    final csvNoExtFile = File('${tempDir.path}/csv_raw');
    await csvNoExtFile.writeAsBytes(csvBytes);

    try {
      // Test mixed case DOCX -> TXT
      final docxTxtMixedPath = await FileConverter.convert(
        sourcePath: docxMixedFile.path,
        targetFormat: 'txt',
      );
      expect(await File(docxTxtMixedPath).readAsString(), contains('Robust Docx Content'));

      // Test extension-less DOCX -> TXT
      final docxTxtNoExtPath = await FileConverter.convert(
        sourcePath: docxNoExtFile.path,
        targetFormat: 'txt',
      );
      expect(await File(docxTxtNoExtPath).readAsString(), contains('Robust Docx Content'));

      // Test mixed case JSON -> XLSX
      final jsonXlsxMixedPath = await FileConverter.convert(
        sourcePath: jsonMixedFile.path,
        targetFormat: 'xlsx',
      );
      expect(await File(jsonXlsxMixedPath).exists(), isTrue);

      // Test extension-less JSON -> XLSX
      final jsonXlsxNoExtPath = await FileConverter.convert(
        sourcePath: jsonNoExtFile.path,
        targetFormat: 'xlsx',
      );
      expect(await File(jsonXlsxNoExtPath).exists(), isTrue);

      // Test mixed case CSV -> PDF
      final csvPdfMixedPath = await FileConverter.convert(
        sourcePath: csvMixedFile.path,
        targetFormat: 'pdf',
      );
      expect(await File(csvPdfMixedPath).exists(), isTrue);

      // Test extension-less CSV -> PDF
      final csvPdfNoExtPath = await FileConverter.convert(
        sourcePath: csvNoExtFile.path,
        targetFormat: 'pdf',
      );
      expect(await File(csvPdfNoExtPath).exists(), isTrue);

    } finally {
      if (await docxMixedFile.exists()) await docxMixedFile.delete();
      if (await docxNoExtFile.exists()) await docxNoExtFile.delete();
      if (await jsonMixedFile.exists()) await jsonMixedFile.delete();
      if (await jsonNoExtFile.exists()) await jsonNoExtFile.delete();
      if (await csvMixedFile.exists()) await csvMixedFile.delete();
      if (await csvNoExtFile.exists()) await csvNoExtFile.delete();
    }
  });

  test('ZIP entries path normalization with leading slashes and backslashes', () async {
    final tempDir = Directory.systemTemp;

    // 1. Word ZIP with leading slash
    final archiveDoc = Archive();
    archiveDoc.addFile(ArchiveFile('/word/document.xml', 10, utf8.encode('<root/>')));
    final zipBytesDoc = Uint8List.fromList(ZipEncoder().encode(archiveDoc)!);
    final docZipFile = File('${tempDir.path}/leading_slash_docx.zip');
    await docZipFile.writeAsBytes(zipBytesDoc);

    // 2. PowerPoint ZIP with leading backslash
    final archivePpt = Archive();
    archivePpt.addFile(ArchiveFile('\\ppt\\presentation.xml', 10, utf8.encode('<root/>')));
    final zipBytesPpt = Uint8List.fromList(ZipEncoder().encode(archivePpt)!);
    final pptZipFile = File('${tempDir.path}/leading_backslash_pptx.zip');
    await pptZipFile.writeAsBytes(zipBytesPpt);

    // 3. Excel ZIP with mixed-case and leading slash
    final archiveExcel = Archive();
    archiveExcel.addFile(ArchiveFile('/xl/workbook.xml', 10, utf8.encode('<root/>')));
    final zipBytesExcel = Uint8List.fromList(ZipEncoder().encode(archiveExcel)!);
    final xlsxZipFile = File('${tempDir.path}/leading_slash_xlsx.zip');
    await xlsxZipFile.writeAsBytes(zipBytesExcel);

    try {
      final analysisDoc = await FileIntelligenceEngine.analyze(docZipFile.path);
      expect(analysisDoc.trueType, equals('Word Document (DOCX)'));
      expect(analysisDoc.trueMimeType, equals('application/vnd.openxmlformats-officedocument.wordprocessingml.document'));

      final analysisPpt = await FileIntelligenceEngine.analyze(pptZipFile.path);
      expect(analysisPpt.trueType, equals('PowerPoint Presentation (PPTX)'));
      expect(analysisPpt.trueMimeType, equals('application/vnd.openxmlformats-officedocument.presentationml.presentation'));

      final analysisExcel = await FileIntelligenceEngine.analyze(xlsxZipFile.path);
      expect(analysisExcel.trueType, equals('Excel Spreadsheet (XLSX)'));
      expect(analysisExcel.trueMimeType, equals('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
    } finally {
      if (await docZipFile.exists()) await docZipFile.delete();
      if (await pptZipFile.exists()) await pptZipFile.delete();
      if (await xlsxZipFile.exists()) await xlsxZipFile.delete();
    }
  });
}

