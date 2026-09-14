import 'dart:io';

import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';

void main() {
  group('a document written to the standard', () {
    test('is read whole', () {
      final directory = Directory('examples_from_cef');
      if (!directory.existsSync()) {
        markTestSkipped('Run tool/fetch_examples.dart');
        return;
      }
      for (final file in directory.listSync().whereType<File>()) {
        final read = readUblReporting(file.readAsStringSync());
        expect(
          read.isComplete,
          isTrue,
          reason: '${file.uri.pathSegments.last}: ${read.skipped}',
        );
      }
    });

    test('gives the same invoice readUbl gives', () {
      final xml = _invoice();
      expect(readUblReporting(xml).invoice.number, readUbl(xml).number);
      expect(readUblReporting(xml).isComplete, isTrue);
      expect(readUblReporting(xml).skipped, isEmpty);
    });

    test('refuses what readUbl refuses', () {
      expect(
        () => readUblReporting('not xml at all'),
        throwsA(isA<UblFormatException>()),
      );
    });
  });

  group('a document written beyond the standard', () {
    test('says how many lines under lines it could not take', () {
      // What the KoSIT extension documents look like: one line the model can
      // hold, and children under it that it cannot. The totals still add up,
      // because the parent already summed them, so nothing else complains.
      final read = readUblReporting(_invoice(subLines: 3));

      expect(read.invoice.lines, hasLength(1));
      expect(read.isComplete, isFalse);

      final sub = read.skipped.single;
      expect(sub.name, 'cac:SubInvoiceLine');
      expect(sub.count, 3);
      expect(sub.purpose, contains('BG-DEX-01'));
      expect(sub.toString(), '3 x cac:SubInvoiceLine (${sub.purpose})');
    });

    test('names a payment somebody else made', () {
      final read = readUblReporting(_invoice(prepaid: true));
      expect(
        read.skipped.map((element) => element.name),
        contains('cac:PrepaidPayment'),
      );
    });

    test('counts each kind on its own', () {
      final read = readUblReporting(_invoice(subLines: 2, prepaid: true));
      expect(read.skipped, hasLength(2));
      expect(read.skipped.map((e) => e.name), [
        'cac:PrepaidPayment',
        'cac:SubInvoiceLine',
      ]);
    });
  });

  test('every element looked for says what it is', () {
    expect(ublElementsBeyondTheModel, isNotEmpty);
    for (final entry in ublElementsBeyondTheModel.entries) {
      expect(entry.key, startsWith('cac:'));
      expect(entry.value, isNotEmpty);
    }
  });
}

/// A one line invoice, optionally carrying what the model cannot hold.
String _invoice({int subLines = 0, bool prepaid = false}) {
  final children = [
    for (var index = 0; index < subLines; index++)
      '''
      <cac:SubInvoiceLine>
        <cbc:ID>1.${index + 1}</cbc:ID>
        <cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity>
        <cbc:LineExtensionAmount currencyID="EUR">10.00</cbc:LineExtensionAmount>
      </cac:SubInvoiceLine>''',
  ].join('\n');

  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
    xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
    xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:ID>2026-0042</cbc:ID>
  <cbc:IssueDate>2026-09-14</cbc:IssueDate>
  <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
  <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
${prepaid ? _prepaidPayment : ''}
  <cac:InvoiceLine>
    <cbc:ID>1</cbc:ID>
    <cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity>
    <cbc:LineExtensionAmount currencyID="EUR">30.00</cbc:LineExtensionAmount>
$children
  </cac:InvoiceLine>
</Invoice>
''';
}

/// A payment somebody else made, which the model has no term for.
const String _prepaidPayment =
    '  <cac:PrepaidPayment>\n'
    '    <cbc:ID>MobilesBezahlen</cbc:ID>\n'
    '    <cbc:PaidAmount currencyID="EUR">30.00</cbc:PaidAmount>\n'
    '  </cac:PrepaidPayment>';
