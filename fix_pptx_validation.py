import zipfile
import os

def create_fixed_pptx():
    z_in = zipfile.ZipFile('hello_device.pptx')
    z_out = zipfile.ZipFile('fixed.pptx', 'w')
    
    # 1. [Content_Types].xml
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>
  <Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>
  <Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
  <Override PartName="/ppt/slides/slide2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
  <Override PartName="/ppt/slides/slide3.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>"""
    z_out.writestr('[Content_Types].xml', content_types)
    
    # 2. _rels/.rels
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>"""
    z_out.writestr('_rels/.rels', rels)
    
    # 3. docProps/core.xml
    core_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Generated Presentation</dc:title>
  <dc:subject>PDF to PPTX Conversion</dc:subject>
  <dc:creator>Morph File Converter</dc:creator>
  <cp:revision>1</cp:revision>
</cp:coreProperties>"""
    z_out.writestr('docProps/core.xml', core_xml)
    
    # 4. docProps/app.xml
    app_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <TotalTime>1</TotalTime>
  <Words>0</Words><Application>Morph File Converter</Application>
  <PresentationFormat>On-screen Show (4:3)</PresentationFormat>
  <Paragraphs>0</Paragraphs><Slides>3</Slides><Notes>0</Notes><HiddenSlides>0</HiddenSlides><MMClips>0</MMClips>
  <ScaleCrop>false</ScaleCrop>
  <HeadingPairs>
    <vt:vector size="4" baseType="variant">
      <vt:variant><vt:lpstr>Theme</vt:lpstr></vt:variant>
      <vt:variant><vt:i4>1</vt:i4></vt:variant>
      <vt:variant><vt:lpstr>Slide Titles</vt:lpstr></vt:variant>
      <vt:variant><vt:i4>3</vt:i4></vt:variant>
    </vt:vector>
  </HeadingPairs>
  <TitlesOfParts>
    <vt:vector size="4" baseType="lpstr">
      <vt:lpstr>Office Theme</vt:lpstr>
      <vt:lpstr>Slide 1</vt:lpstr>
      <vt:lpstr>Slide 2</vt:lpstr>
      <vt:lpstr>Slide 3</vt:lpstr>
    </vt:vector>
  </TitlesOfParts>
  <LinksUpToDate>false</LinksUpToDate>
  <SharedDoc>false</SharedDoc>
  <HyperlinksChanged>false</HyperlinksChanged>
  <AppVersion>15.0000</AppVersion>
</Properties>"""
    z_out.writestr('docProps/app.xml', app_xml)
    
    # 5. ppt/presentation.xml
    presentation = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId4"/>
  </p:sldMasterIdLst>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId1"/>
    <p:sldId id="257" r:id="rId2"/>
    <p:sldId id="258" r:id="rId3"/>
  </p:sldIdLst>
  <p:sldSz cx="9144000" cy="6858000" type="screen4x3"/>
  <p:notesSz cx="6858000" cy="9144000"/>
  <p:defaultTextStyle>
    <a:defPPr><a:defRPr lang="en-US"/></a:defPPr>
  </p:defaultTextStyle>
</p:presentation>"""
    z_out.writestr('ppt/presentation.xml', presentation)
    
    # 6. ppt/_rels/presentation.xml.rels
    presentation_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
  <Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>
  <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>
  <Relationship Id="rId8" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>
</Relationships>"""
    z_out.writestr('ppt/_rels/presentation.xml.rels', presentation_rels)
    
    # 7. ppt/presProps.xml
    pres_props = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:extLst>
    <p:ext uri="{E76CE94A-603C-4142-B9EB-6D1370010A27}">
      <p14:discardImageEditData xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" val="0"/>
    </p:ext>
  </p:extLst>
</p:presentationPr>"""
    z_out.writestr('ppt/presProps.xml', pres_props)
    
    # 8. ppt/viewProps.xml
    view_props = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" lastView="sldThumbnailView">
  <p:normalViewPr>
    <p:restoredLeft sz="15620"/>
    <p:restoredTop sz="94660"/>
  </p:normalViewPr>
</p:viewPr>"""
    z_out.writestr('ppt/viewProps.xml', view_props)
    
    # 9. ppt/tableStyles.xml
    table_styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>"""
    z_out.writestr('ppt/tableStyles.xml', table_styles)
    
    # 10. ppt/theme/theme1.xml (read from input)
    z_out.writestr('ppt/theme/theme1.xml', z_in.read('ppt/theme/theme1.xml'))
    
    # 11. ppt/slideMasters/slideMaster1.xml (MUST add clrMap element!)
    # The order is: cSld, clrMap, sldLayoutIdLst, txStyles
    slide_master = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld name="">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>"""
    z_out.writestr('ppt/slideMasters/slideMaster1.xml', slide_master)
    
    # 12. ppt/slideMasters/_rels/slideMaster1.xml.rels
    z_out.writestr('ppt/slideMasters/_rels/slideMaster1.xml.rels', z_in.read('ppt/slideMasters/_rels/slideMaster1.xml.rels'))
    
    # 13. ppt/slideLayouts/slideLayout1.xml (Remove the 'name' attribute from sldLayout!)
    slide_layout = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" type="blank">
  <p:cSld name="Blank">
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
</p:sldLayout>"""
    z_out.writestr('ppt/slideLayouts/slideLayout1.xml', slide_layout)
    
    # 14. ppt/slideLayouts/_rels/slideLayout1.xml.rels
    z_out.writestr('ppt/slideLayouts/_rels/slideLayout1.xml.rels', z_in.read('ppt/slideLayouts/_rels/slideLayout1.xml.rels'))
    
    # 15. ppt/slides/slide1.xml, slide2.xml, slide3.xml, and their rels
    z_out.writestr('ppt/slides/slide1.xml', z_in.read('ppt/slides/slide1.xml'))
    z_out.writestr('ppt/slides/_rels/slide1.xml.rels', z_in.read('ppt/slides/_rels/slide1.xml.rels'))
    z_out.writestr('ppt/slides/slide2.xml', z_in.read('ppt/slides/slide2.xml'))
    z_out.writestr('ppt/slides/_rels/slide2.xml.rels', z_in.read('ppt/slides/_rels/slide2.xml.rels'))
    z_out.writestr('ppt/slides/slide3.xml', z_in.read('ppt/slides/slide3.xml'))
    z_out.writestr('ppt/slides/_rels/slide3.xml.rels', z_in.read('ppt/slides/_rels/slide3.xml.rels'))
    
    z_in.close()
    z_out.close()
    print("Fixed PPTX generated as 'fixed.pptx'")

if __name__ == '__main__':
    create_fixed_pptx()
