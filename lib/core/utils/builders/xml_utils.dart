import 'dart:convert';
import 'package:archive/archive.dart';

/// Shared XML utilities used across DOCX and PPTX builders.
class XmlUtils {
  /// Escapes XML special characters and strips invalid XML 1.0 control characters.
  static String escapeXml(String input) {
    // Strip invalid XML 1.0 control characters that crash Microsoft Word
    final clean = input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    return clean
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Adds an XML file (UTF-8 encoded) to an Archive.
  static void addXmlFileToArchive(Archive archive, String name, String xmlContent) {
    final bytes = utf8.encode(xmlContent);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
}
