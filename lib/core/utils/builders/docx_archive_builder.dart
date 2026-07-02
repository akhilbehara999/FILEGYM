import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'xml_utils.dart';

/// Builds DOCX (Office Open XML) archives from text or images.
class DocxArchiveBuilder {
  /// Creates a text-only DOCX archive.
  static void createDocxArchive(Archive archive, String text) {
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
      sbDoc.writeln('        <w:t>${XmlUtils.escapeXml(line)}</w:t>');
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

    XmlUtils.addXmlFileToArchive(archive, '[Content_Types].xml', contentTypesXml);
    XmlUtils.addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    XmlUtils.addXmlFileToArchive(archive, 'word/_rels/document.xml.rels', docRelsXml);
    XmlUtils.addXmlFileToArchive(archive, 'word/document.xml', sbDoc.toString());
  }

  /// Creates a DOCX archive with images (one per page).
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

    XmlUtils.addXmlFileToArchive(archive, '[Content_Types].xml', sbContent.toString());
    XmlUtils.addXmlFileToArchive(archive, '_rels/.rels', relsXml);
    XmlUtils.addXmlFileToArchive(archive, 'word/_rels/document.xml.rels', sbDocRels.toString());
    XmlUtils.addXmlFileToArchive(archive, 'word/document.xml', sbDoc.toString());
  }
}
