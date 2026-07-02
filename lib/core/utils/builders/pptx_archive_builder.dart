import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'xml_utils.dart';
import 'pptx_constants.dart';

/// Builds PPTX (Office Open XML) archives from text slides or images.
class PptxArchiveBuilder {
  /// Creates a text-based PPTX archive from slide strings.
  static void createPptxArchive(Archive archive, List<String> slides) {
    _addScaffolding(archive, slides.length, hasImages: false);

    // Individual slides
    for (int i = 0; i < slides.length; i++) {
      final slideText = slides[i].replaceAll('\r', '');
      final sbParas = StringBuffer();
      final lines = slideText.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        sbParas.writeln('          <a:p>');
        sbParas.writeln('            <a:r>');
        sbParas.writeln('              <a:rPr lang="en-US" dirty="0"/>');
        sbParas.writeln('              <a:t>${XmlUtils.escapeXml(line)}</a:t>');
        sbParas.writeln('            </a:r>');
        sbParas.writeln('          </a:p>');
      }
      if (sbParas.isEmpty) {
        sbParas.writeln('          <a:p><a:endParaRPr lang="en-US"/></a:p>');
      }

      final slideXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Slide Text"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm>
            <a:off x="457200" y="274638"/>
            <a:ext cx="8229600" cy="5143500"/>
          </a:xfrm>
          <a:prstGeom prst="rect">
            <a:avLst/>
          </a:prstGeom>
        </p:spPr>
        <p:txBody>
          <a:bodyPr wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720"/>
          <a:lstStyle/>
          $sbParas
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';
      XmlUtils.addXmlFileToArchive(archive, 'ppt/slides/slide${i + 1}.xml', slideXml);

      final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';
      XmlUtils.addXmlFileToArchive(archive, 'ppt/slides/_rels/slide${i + 1}.xml.rels', slideRels);
    }
  }

  /// Creates a PPTX archive with images (one per slide, full-bleed).
  static void createPptxArchiveWithImages(Archive archive, List<Uint8List> images) {
    _addScaffolding(archive, images.length, hasImages: true);

    for (int i = 0; i < images.length; i++) {
      final slideXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="${i + 10}" name="Page Image ${i + 1}"/>
          <p:cNvPicPr>
            <a:picLocks noChangeAspect="1"/>
          </p:cNvPicPr>
          <p:nvPr/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rId2"/>
          <a:stretch>
            <a:fillRect/>
          </a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm>
            <a:off x="0" y="0"/>
            <a:ext cx="9144000" cy="6858000"/>
          </a:xfrm>
          <a:prstGeom prst="rect">
            <a:avLst/>
          </a:prstGeom>
        </p:spPr>
      </p:pic>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';
      XmlUtils.addXmlFileToArchive(archive, 'ppt/slides/slide${i + 1}.xml', slideXml);

      final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${i + 1}.jpg"/>
</Relationships>''';
      XmlUtils.addXmlFileToArchive(archive, 'ppt/slides/_rels/slide${i + 1}.xml.rels', slideRels);

      archive.addFile(ArchiveFile('ppt/media/image${i + 1}.jpg', images[i].length, images[i]));
    }
  }

  /// Adds all the shared PPTX scaffolding (content types, rels, theme, master, layout, etc.)
  static void _addScaffolding(Archive archive, int slideCount, {required bool hasImages}) {
    // [Content_Types].xml
    final sbContent = StringBuffer();
    sbContent.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbContent.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    sbContent.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    sbContent.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    if (hasImages) {
      sbContent.writeln('  <Default Extension="jpg" ContentType="image/jpeg"/>');
      sbContent.writeln('  <Default Extension="jpeg" ContentType="image/jpeg"/>');
    }
    sbContent.writeln('  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>');
    sbContent.writeln('  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>');
    for (int i = 1; i <= slideCount; i++) {
      sbContent.writeln('  <Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    sbContent.writeln('</Types>');

    // docProps/app.xml
    final sbApp = StringBuffer();
    sbApp.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbApp.writeln('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">');
    sbApp.writeln('  <TotalTime>1</TotalTime>');
    sbApp.writeln('  <Words>0</Words><Application>FileGym</Application>');
    sbApp.writeln('  <PresentationFormat>On-screen Show (4:3)</PresentationFormat>');
    sbApp.writeln('  <Paragraphs>0</Paragraphs><Slides>$slideCount</Slides><Notes>0</Notes><HiddenSlides>0</HiddenSlides><MMClips>0</MMClips>');
    sbApp.writeln('  <ScaleCrop>false</ScaleCrop>');
    sbApp.writeln('  <HeadingPairs>');
    sbApp.writeln('    <vt:vector size="4" baseType="variant">');
    sbApp.writeln('      <vt:variant><vt:lpstr>Theme</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>1</vt:i4></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:lpstr>Slide Titles</vt:lpstr></vt:variant>');
    sbApp.writeln('      <vt:variant><vt:i4>$slideCount</vt:i4></vt:variant>');
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </HeadingPairs>');
    sbApp.writeln('  <TitlesOfParts>');
    sbApp.writeln('    <vt:vector size="${slideCount + 1}" baseType="lpstr">');
    sbApp.writeln('      <vt:lpstr>Office Theme</vt:lpstr>');
    for (int i = 1; i <= slideCount; i++) {
      sbApp.writeln('      <vt:lpstr>Slide $i</vt:lpstr>');
    }
    sbApp.writeln('    </vt:vector>');
    sbApp.writeln('  </TitlesOfParts>');
    sbApp.writeln('  <LinksUpToDate>false</LinksUpToDate>');
    sbApp.writeln('  <SharedDoc>false</SharedDoc>');
    sbApp.writeln('  <HyperlinksChanged>false</HyperlinksChanged>');
    sbApp.writeln('  <AppVersion>15.0000</AppVersion>');
    sbApp.writeln('</Properties>');

    // ppt/presentation.xml
    final sbPres = StringBuffer();
    sbPres.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPres.writeln('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
    sbPres.writeln('  <p:sldMasterIdLst>');
    sbPres.writeln('    <p:sldMasterId id="2147483648" r:id="rId${slideCount + 1}"/>');
    sbPres.writeln('  </p:sldMasterIdLst>');
    sbPres.writeln('  <p:sldIdLst>');
    for (int i = 1; i <= slideCount; i++) {
      sbPres.writeln('    <p:sldId id="${255 + i}" r:id="rId$i"/>');
    }
    sbPres.writeln('  </p:sldIdLst>');
    sbPres.writeln('  <p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>');
    sbPres.writeln('  <p:notesSz cx="6858000" cy="9144000"/>');
    sbPres.writeln('  <p:defaultTextStyle>');
    sbPres.writeln('    <a:defPPr><a:defRPr lang="en-US"/></a:defPPr>');
    sbPres.writeln('  </p:defaultTextStyle>');
    sbPres.writeln('</p:presentation>');

    // ppt/_rels/presentation.xml.rels
    final sbPresRels = StringBuffer();
    sbPresRels.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sbPresRels.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (int i = 1; i <= slideCount; i++) {
      sbPresRels.writeln('  <Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>');
    }
    sbPresRels.writeln('  <Relationship Id="rId${slideCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slideCount + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slideCount + 3}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slideCount + 4}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>');
    sbPresRels.writeln('  <Relationship Id="rId${slideCount + 5}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>');
    sbPresRels.writeln('</Relationships>');

    // Add all scaffolding files
    XmlUtils.addXmlFileToArchive(archive, '[Content_Types].xml', sbContent.toString());
    XmlUtils.addXmlFileToArchive(archive, '_rels/.rels', PptxConstants.rootRelsXml);
    XmlUtils.addXmlFileToArchive(archive, 'docProps/core.xml', PptxConstants.coreXml);
    XmlUtils.addXmlFileToArchive(archive, 'docProps/app.xml', sbApp.toString());
    XmlUtils.addXmlFileToArchive(archive, 'ppt/presentation.xml', sbPres.toString());
    XmlUtils.addXmlFileToArchive(archive, 'ppt/_rels/presentation.xml.rels', sbPresRels.toString());
    XmlUtils.addXmlFileToArchive(archive, 'ppt/presProps.xml', PptxConstants.presPropsXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/viewProps.xml', PptxConstants.viewPropsXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/tableStyles.xml', PptxConstants.tableStylesXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/theme/theme1.xml', PptxConstants.themeXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/slideMasters/slideMaster1.xml', PptxConstants.slideMasterXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/slideMasters/_rels/slideMaster1.xml.rels', PptxConstants.slideMasterRels);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/slideLayouts/slideLayout1.xml', PptxConstants.slideLayoutXml);
    XmlUtils.addXmlFileToArchive(archive, 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', PptxConstants.slideLayoutRels);
  }
}
