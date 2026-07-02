import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Extracts slide text content from PPTX (Office Open XML) files.
class PptxTextExtractor {
  /// Returns a list of strings, one per slide, containing extracted text.
  static List<String> extractSlides(Uint8List bytes) {
    final slides = <String>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final slideFiles = archive.files.where((f) {
        var name = f.name.replaceAll('\\', '/').toLowerCase();
        if (name.startsWith('/')) {
          name = name.substring(1);
        }
        return RegExp(r'^ppt/slides/slide_?\d+\.xml$').hasMatch(name);
      }).toList();

      slideFiles.sort((a, b) {
        var aName = a.name.replaceAll('\\', '/').toLowerCase();
        var bName = b.name.replaceAll('\\', '/').toLowerCase();
        if (aName.startsWith('/')) aName = aName.substring(1);
        if (bName.startsWith('/')) bName = bName.substring(1);
        final aNum = int.tryParse(RegExp(r'\d+').stringMatch(aName.split('/').last) ?? '') ?? 0;
        final bNum = int.tryParse(RegExp(r'\d+').stringMatch(bName.split('/').last) ?? '') ?? 0;
        return aNum.compareTo(bNum);
      });
      
      for (final f in slideFiles) {
        final dynamic rawContent = f.content;
        List<int>? contentBytes;
        if (rawContent is List<int>) {
          contentBytes = rawContent;
        } else if (rawContent != null) {
          try {
            contentBytes = List<int>.from(rawContent);
          } catch (_) {}
        }
        if (contentBytes == null) continue;
        var content = utf8.decode(contentBytes, allowMalformed: true);
        // Strip UTF-8 BOM if present at the start of string
        if (content.startsWith('\uFEFF')) {
          content = content.substring(1);
        }
        content = content.trim();

        final document = XmlDocument.parse(content);
        final paragraphs = <String>[];

        // Find all paragraph elements (a:p)
        for (final p in document.findAllElements('p', namespace: '*')) {
          // Within each paragraph, find all text runs (a:t)
          final text = p.findAllElements('t', namespace: '*').map((node) => node.innerText).join('');
          if (text.isNotEmpty) {
            paragraphs.add(text);
          }
        }

        // Fallback: if no text was extracted via paragraph tags, try matching all text tags directly in the slide
        if (paragraphs.isEmpty) {
          final allTexts = document
              .findAllElements('t', namespace: '*')
              .map((node) => node.innerText)
              .where((t) => t.trim().isNotEmpty)
              .toList();
          if (allTexts.isNotEmpty) {
            paragraphs.addAll(allTexts);
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
}
