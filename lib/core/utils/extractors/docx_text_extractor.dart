import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Extracts text content from DOCX (Office Open XML) files.
class DocxTextExtractor {
  /// Extracts all text paragraphs from a DOCX file's bytes.
  static String extractText(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? documentFile;

      // 1. Try to find the document file path via relationship mapping in _rels/.rels
      String? targetPath;
      ArchiveFile? relsFile;
      for (final f in archive.files) {
        var name = f.name.replaceAll('\\', '/').toLowerCase();
        if (name.startsWith('/')) name = name.substring(1);
        if (name == '_rels/.rels') {
          relsFile = f;
          break;
        }
      }

      if (relsFile != null) {
        try {
          final dynamic rawRels = relsFile.content;
          List<int>? relsBytes;
          if (rawRels is List<int>) {
            relsBytes = rawRels;
          } else if (rawRels != null) {
            try {
              relsBytes = List<int>.from(rawRels);
            } catch (_) {}
          }
          if (relsBytes != null) {
            final relsContent = utf8.decode(relsBytes, allowMalformed: true);
            final doc = XmlDocument.parse(relsContent);
            for (final rel in doc.findAllElements('Relationship')) {
              final type = rel.getAttribute('Type');
              final target = rel.getAttribute('Target');
              if (type != null && type.contains('relationships/officeDocument') && target != null) {
                targetPath = target;
                break;
              }
            }
          }
        } catch (_) {}
      }

      // 2. Look for the file matching the relationship target path
      if (targetPath != null) {
        var normalizedTarget = targetPath.replaceAll('\\', '/').toLowerCase();
        if (normalizedTarget.startsWith('/')) {
          normalizedTarget = normalizedTarget.substring(1);
        }
        for (final f in archive.files) {
          var name = f.name.replaceAll('\\', '/').toLowerCase();
          if (name.startsWith('/')) name = name.substring(1);
          if (name == normalizedTarget || name == 'word/$normalizedTarget') {
            documentFile = f;
            break;
          }
        }
      }

      // 3. Fallback: Search for word/document.xml directly
      if (documentFile == null) {
        for (final f in archive.files) {
          var name = f.name.replaceAll('\\', '/').toLowerCase();
          if (name.startsWith('/')) name = name.substring(1);
          if (name == 'word/document.xml') {
            documentFile = f;
            break;
          }
        }
      }

      // 4. Second Fallback: Search for any file ending with document.xml
      if (documentFile == null) {
        for (final f in archive.files) {
          var name = f.name.replaceAll('\\', '/').toLowerCase();
          if (name.startsWith('/')) name = name.substring(1);
          if (name.endsWith('/document.xml') || name == 'document.xml') {
            documentFile = f;
            break;
          }
        }
      }
      
      if (documentFile == null) {
        final fileNames = archive.files.map((f) => f.name).take(20).join(', ');
        final suffix = archive.files.length > 20 ? '... (total ${archive.files.length} files)' : '';
        return 'Failed to extract text: word/document.xml not found in the ZIP archive. Files found: [$fileNames$suffix]';
      }
      
      final dynamic rawContent = documentFile.content;
      List<int>? contentBytes;
      if (rawContent is List<int>) {
        contentBytes = rawContent;
      } else if (rawContent != null) {
        try {
          contentBytes = List<int>.from(rawContent);
        } catch (_) {}
      }

      if (contentBytes == null) {
        return 'Failed to extract text: document.xml content is null or unreadable.';
      }

      var content = utf8.decode(contentBytes, allowMalformed: true);

      // Strip UTF-8 BOM if present at the start of string
      if (content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }
      content = content.trim();

      final document = XmlDocument.parse(content);
      final paragraphs = <String>[];

      // Find all paragraph elements (w:p)
      final pElements = document.findAllElements('p', namespace: '*');
      
      for (final p in pElements) {
        // Within each paragraph, find all text runs (w:t)
        final text = p.findAllElements('t', namespace: '*').map((node) => node.innerText).join('');
        if (text.isNotEmpty) {
          paragraphs.add(text);
        }
      }

      // Fallback: If no paragraphs with text were extracted, extract all text tags directly
      if (paragraphs.isEmpty) {
        final tElements = document.findAllElements('t', namespace: '*');
        final allTexts = tElements
            .map((node) => node.innerText)
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if (allTexts.isNotEmpty) {
          paragraphs.addAll(allTexts);
        }
      }

      return paragraphs.join('\n');
    } catch (e) {
      return 'Failed to extract text from DOCX: $e';
    }
  }
}

