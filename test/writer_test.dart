import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _seller = Seller(
  name: 'COMAPPS SRL',
  vatIdentifier: 'BE0123456789',
  electronicAddress: Identifier('0123456789', scheme: '0208'),
  address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
);

const _buyer = Buyer(
  name: 'Client SA',
  electronicAddress: Identifier('0987654321', scheme: '0208'),
  address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
);

Invoice _invoice({
  InvoiceTypeCode? typeCode,
  List<InvoiceLine>? lines,
  List<DocumentAllowanceCharge> allowancesAndCharges = const [],
}) => Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 13),
  dueDate: DateTime(2026, 10, 13),
  typeCode: typeCode ?? InvoiceTypeCode.commercialInvoice,
  seller: _seller,
  buyer: _buyer,
  allowancesAndCharges: allowancesAndCharges,
  lines:
      lines ??
      [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Consulting'),
          quantity: 8,
          unitPrice: 150.00,
          vatRate: 21,
          unit: UnitCode.hour,
        ),
      ],
);

XmlElement _root(Invoice invoice) =>
    XmlDocument.parse(writeUbl(invoice)).rootElement;

String? _text(XmlElement root, String path) {
  XmlElement? current = root;
  for (final name in path.split('/')) {
    current = current?.childElements
        .where((element) => element.localName == name)
        .firstOrNull;
  }
  return current?.innerText;
}

void main() {
  group('the document', () {
    test('is a UBL invoice', () {
      final root = _root(_invoice());
      expect(root.localName, 'Invoice');
      expect(root.namespaceUri, ublInvoice);
    });

    test('carries the header terms', () {
      final root = _root(_invoice());
      expect(_text(root, 'CustomizationID'), en16931Specification);
      expect(_text(root, 'ID'), '2026-0042');
      expect(_text(root, 'IssueDate'), '2026-09-13');
      expect(_text(root, 'DueDate'), '2026-10-13');
      expect(_text(root, 'InvoiceTypeCode'), '380');
      expect(_text(root, 'DocumentCurrencyCode'), 'EUR');
    });

    test('keeps the elements in the order the schema fixes', () {
      // A receiver validates against the schema before it reads a single
      // business rule, so an invoice whose elements are out of order is not
      // rejected on its content: it is not read at all.
      final names = _root(
        _invoice(),
      ).childElements.map((element) => element.localName).toList();
      const expected = [
        'CustomizationID',
        'ID',
        'IssueDate',
        'DueDate',
        'InvoiceTypeCode',
        'DocumentCurrencyCode',
        'AccountingSupplierParty',
        'AccountingCustomerParty',
        'TaxTotal',
        'LegalMonetaryTotal',
        'InvoiceLine',
      ];
      expect(names, expected);
    });
  });

  group('the parties', () {
    test('carry the electronic address and its scheme', () {
      final root = _root(_invoice());
      final supplier = root.childElements
          .firstWhere((e) => e.localName == 'AccountingSupplierParty')
          .childElements
          .first;
      final endpoint = supplier.childElements.first;
      expect(endpoint.localName, 'EndpointID');
      expect(endpoint.getAttribute('schemeID'), '0208');
      expect(endpoint.innerText, '0123456789');
    });

    test('carry the VAT identifier under the VAT scheme', () {
      final root = _root(_invoice());
      final party = root.childElements
          .firstWhere((e) => e.localName == 'AccountingSupplierParty')
          .childElements
          .first;
      final taxScheme = party.childElements.firstWhere(
        (e) => e.localName == 'PartyTaxScheme',
      );
      expect(_text(taxScheme, 'CompanyID'), 'BE0123456789');
      expect(_text(taxScheme, 'TaxScheme/ID'), 'VAT');
    });

    test('carry the registered name as the legal entity', () {
      final root = _root(_invoice());
      final party = root.childElements
          .firstWhere((e) => e.localName == 'AccountingSupplierParty')
          .childElements
          .first;
      final legal = party.childElements.firstWhere(
        (e) => e.localName == 'PartyLegalEntity',
      );
      expect(_text(legal, 'RegistrationName'), 'COMAPPS SRL');
    });
  });

  group('the figures', () {
    test('are written with two decimals and their currency', () {
      final root = _root(_invoice());
      final totals = root.childElements.firstWhere(
        (e) => e.localName == 'LegalMonetaryTotal',
      );
      final payable = totals.childElements.firstWhere(
        (e) => e.localName == 'PayableAmount',
      );
      expect(payable.innerText, '1452.00');
      expect(payable.getAttribute('currencyID'), 'EUR');
      expect(_text(totals, 'LineExtensionAmount'), '1200.00');
      expect(_text(totals, 'TaxExclusiveAmount'), '1200.00');
      expect(_text(totals, 'TaxInclusiveAmount'), '1452.00');
    });

    test('carry the VAT breakdown under TaxTotal', () {
      final root = _root(_invoice());
      final total = root.childElements.firstWhere(
        (e) => e.localName == 'TaxTotal',
      );
      expect(_text(total, 'TaxAmount'), '252.00');
      final subtotal = total.childElements.firstWhere(
        (e) => e.localName == 'TaxSubtotal',
      );
      expect(_text(subtotal, 'TaxableAmount'), '1200.00');
      expect(_text(subtotal, 'TaxAmount'), '252.00');
      expect(_text(subtotal, 'TaxCategory/ID'), 'S');
      expect(_text(subtotal, 'TaxCategory/Percent'), '21');
      expect(_text(subtotal, 'TaxCategory/TaxScheme/ID'), 'VAT');
    });

    test('leave a unit price its own decimals', () {
      final invoice = _invoice(
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Screws'),
            quantity: 1000,
            unitPrice: 0.0125,
            vatRate: 21,
          ),
        ],
      );
      final line = _root(
        invoice,
      ).childElements.firstWhere((e) => e.localName == 'InvoiceLine');
      expect(_text(line, 'Price/PriceAmount'), '0.0125');
      expect(_text(line, 'LineExtensionAmount'), '12.50');
    });
  });

  group('a line', () {
    test('carries the quantity with its unit', () {
      final line = _root(
        _invoice(),
      ).childElements.firstWhere((e) => e.localName == 'InvoiceLine');
      final quantity = line.childElements.firstWhere(
        (e) => e.localName == 'InvoicedQuantity',
      );
      expect(quantity.innerText, '8');
      expect(quantity.getAttribute('unitCode'), 'HUR');
      expect(_text(line, 'Item/Name'), 'Consulting');
      expect(_text(line, 'Item/ClassifiedTaxCategory/ID'), 'S');
    });
  });

  group('a document level allowance', () {
    test('is written with its indicator and its VAT category', () {
      final invoice = _invoice(
        allowancesAndCharges: [
          DocumentAllowanceCharge(
            kind: AllowanceOrCharge.allowance,
            amount: Decimal.parse('50.00'),
            vatCategory: VatCategory.standardRate,
            vatRate: Decimal.parse('21'),
            reasonCode: '95',
          ),
        ],
      );
      final entry = _root(
        invoice,
      ).childElements.firstWhere((e) => e.localName == 'AllowanceCharge');
      expect(_text(entry, 'ChargeIndicator'), 'false');
      expect(_text(entry, 'AllowanceChargeReasonCode'), '95');
      expect(_text(entry, 'Amount'), '50.00');
      expect(_text(entry, 'TaxCategory/ID'), 'S');
    });
  });

  group('a credit note', () {
    test('goes out under its own root', () {
      final invoice = _invoice(typeCode: InvoiceTypeCode.creditNote);
      final root = _root(invoice);
      expect(root.localName, 'CreditNote');
      expect(root.namespaceUri, ublCreditNote);
      expect(_text(root, 'CreditNoteTypeCode'), '381');
      final line = root.childElements.firstWhere(
        (e) => e.localName == 'CreditNoteLine',
      );
      expect(
        line.childElements.any((e) => e.localName == 'CreditedQuantity'),
        isTrue,
      );
    });

    test('is recognised by its type code', () {
      expect(isCreditNote(InvoiceTypeCode.creditNote), isTrue);
      expect(isCreditNote(InvoiceTypeCode.commercialInvoice), isFalse);
    });
  });
}
