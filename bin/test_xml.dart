import 'package:xml/xml.dart';

void main() {
  const xmlStr = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>Hello World</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

  final doc = XmlDocument.parse(xmlStr);
  final psWildcard = doc.findAllElements('p', namespace: '*');
  print('Wildcard p elements: ' + psWildcard.length.toString());
  
  final tsWildcard = doc.findAllElements('t', namespace: '*');
  print('Wildcard t elements: ' + tsWildcard.length.toString());

  final psNoNamespace = doc.findAllElements('p');
  print('No namespace p elements: ' + psNoNamespace.length.toString());

  final psPrefixed = doc.findAllElements('w:p');
  print('Prefixed w:p elements: ' + psPrefixed.length.toString());
}
