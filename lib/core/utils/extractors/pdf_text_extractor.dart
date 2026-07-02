import 'dart:io' show zlib;
import 'dart:typed_data';

/// Extracts text content from PDF files using pure-Dart stream parsing.
class PdfTextExtractor {
  /// Extracts text from PDF bytes by parsing stream/endstream blocks
  /// for text operators (Tj, TJ, ').
  static String extractText(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '(Empty PDF — no content to extract)';
    }

    // Validate PDF magic header
    if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
      throw Exception('Not a valid PDF file');
    }

    try {
      final extractedParts = <String>[];

      int index = 0;
      while (index < bytes.length) {
        // Find 'stream'
        final streamPos = _indexOf(bytes, [115, 116, 114, 101, 97, 109], index); // 'stream'
        if (streamPos == -1) break;

        // The start of stream data is after 'stream' followed by a newline: \r\n (13, 10) or \n (10)
        int streamDataStart = streamPos + 6;
        if (streamDataStart < bytes.length && bytes[streamDataStart] == 13) {
          streamDataStart++;
        }
        if (streamDataStart < bytes.length && bytes[streamDataStart] == 10) {
          streamDataStart++;
        }

        // Find corresponding 'endstream'
        final endstreamPos = _indexOf(bytes, [101, 110, 100, 115, 116, 114, 101, 97, 109], streamDataStart); // 'endstream'
        if (endstreamPos == -1) {
          index = streamDataStart;
          continue;
        }

        // The end of stream data is right before 'endstream' (ignoring any trailing newline \r or \n)
        int streamDataEnd = endstreamPos;
        if (streamDataEnd > streamDataStart && bytes[streamDataEnd - 1] == 10) {
          streamDataEnd--;
        }
        if (streamDataEnd > streamDataStart && bytes[streamDataEnd - 1] == 13) {
          streamDataEnd--;
        }

        if (streamDataEnd > streamDataStart) {
          final streamBytes = bytes.sublist(streamDataStart, streamDataEnd);

          // Check if this stream is compressed.
          // Look backward from streamPos for '/Filter' and '/FlateDecode'
          final lookbackStart = streamPos - 200 > 0 ? streamPos - 200 : 0;
          final headerBytes = bytes.sublist(lookbackStart, streamPos);
          final headerStr = String.fromCharCodes(headerBytes);
          
          bool isCompressed = headerStr.contains('/FlateDecode') || headerStr.contains('/Fl');

          String streamContent;
          if (isCompressed) {
            try {
              final decompressed = zlib.decode(streamBytes);
              streamContent = String.fromCharCodes(decompressed);
            } catch (_) {
              // Fallback if decompression fails
              streamContent = String.fromCharCodes(streamBytes);
            }
          } else {
            streamContent = String.fromCharCodes(streamBytes);
          }

          // Parse text operators from streamContent
          // Tj operator: (text) Tj
          final tjRegex = RegExp(r'\(([^)]*?)\)\s*Tj');
          for (final tj in tjRegex.allMatches(streamContent)) {
            final text = tj.group(1) ?? '';
            if (text.trim().isNotEmpty) extractedParts.add(text);
          }
          // TJ operator: [(text) num (text)] TJ
          final tjArrayRegex = RegExp(r'\[([^\]]*)\]\s*TJ');
          for (final tjArr in tjArrayRegex.allMatches(streamContent)) {
            final inner = tjArr.group(1) ?? '';
            final innerTexts = RegExp(r'\(([^)]*?)\)');
            for (final t in innerTexts.allMatches(inner)) {
              final text = t.group(1) ?? '';
              if (text.trim().isNotEmpty) extractedParts.add(text);
            }
          }
          // ' operator: (text) '
          final quoteRegex = RegExp(r"\(([^)]*?)\)\s*'");
          for (final q in quoteRegex.allMatches(streamContent)) {
            final text = q.group(1) ?? '';
            if (text.trim().isNotEmpty) extractedParts.add(text);
          }
        }

        index = endstreamPos + 9;
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

  static int _indexOf(Uint8List bytes, List<int> pattern, int start) {
    if (pattern.isEmpty) return -1;
    for (int i = start; i <= bytes.length - pattern.length; i++) {
      bool found = true;
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }
}
