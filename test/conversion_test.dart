import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:filegym/core/utils/file_converter.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:filegym/core/intelligence/file_intelligence_engine.dart';

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
}
