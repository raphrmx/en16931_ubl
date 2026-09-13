import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';

Decimal _d(String value) => Decimal.parse(value);

/// An invoice carrying as many terms as the model has room for, so the round
/// trip has something to lose.
Invoice _rich() => Invoice(
      number: '2026-0042',
      issueDate: CalendarDate(2026, 9, 13),
      dueDate: CalendarDate(2026, 10, 13),
      typeCode: InvoiceTypeCode.commercialInvoice,
      specificationIdentifier: en16931Specification,
      businessProcess: 'urn:fdc:peppol.eu:2017:poacc:billing:01:1.0',
      currency: 'EUR',
      vatPointDate: CalendarDate(2026, 9, 30),
      buyerReference: 'PO-77812',
      buyerAccountingReference: '4000',
      projectReference: 'PRJ-1',
      contractReference: 'CTR-9',
      purchaseOrderReference: 'ORD-5',
      salesOrderReference: 'SO-7',
      despatchAdviceReference: 'DES-2',
      receivingAdviceReference: 'REC-3',
      tenderReference: 'TEN-4',
      objectIdentifier: const Identifier('METER-1', scheme: 'AAU'),
      paymentTerms: 'Payable within 30 days.',
      notes: const [
        InvoiceNote('Thank you.'),
        InvoiceNote('Delivered in full.', subjectCode: 'AAI'),
      ],
      invoicingPeriod: DatePeriod(
        start: CalendarDate(2026, 9, 1),
        end: CalendarDate(2026, 9, 30),
      ),
      precedingInvoices: [
        PrecedingInvoiceReference('2026-0041',
            issueDate: CalendarDate(2026, 8, 1)),
      ],
      supportingDocuments: [
        SupportingDocument(
          'DOC-1',
          description: 'Timesheet',
          attachment: Attachment(
            bytes: Uint8List.fromList(utf8.encode('hours')),
            mimeCode: 'application/pdf',
            filename: 'timesheet.pdf',
          ),
        ),
        SupportingDocument(
          'DOC-2',
          description: 'Terms',
          externalUri: Uri.parse('https://example.be/terms'),
        ),
      ],
      seller: const Seller(
        name: 'COMAPPS SRL',
        tradingName: 'ComApps',
        vatIdentifier: 'BE0123456789',
        taxRegistrationIdentifier: 'BE-TAX-1',
        additionalLegalInformation: 'SRL, capital 20000 EUR',
        identifiers: [Identifier('0123456789', scheme: '0208')],
        legalRegistrationIdentifier: Identifier('0123456789', scheme: '0208'),
        electronicAddress: Identifier('0123456789', scheme: '0208'),
        address: Address(
          line1: 'Rue Example 1',
          line2: 'Box 3',
          line3: 'Floor 2',
          city: 'Bruxelles',
          postalCode: '1000',
          countrySubdivision: 'Brussels',
          country: 'BE',
        ),
        contact: Contact(
          name: 'Billing',
          telephone: '+32 2 000 00 00',
          email: 'billing@example.be',
        ),
      ),
      buyer: const Buyer(
        name: 'Client SA',
        vatIdentifier: 'BE0987654321',
        identifier: Identifier('0987654321', scheme: '0208'),
        legalRegistrationIdentifier: Identifier('0987654321', scheme: '0208'),
        electronicAddress: Identifier('0987654321', scheme: '0208'),
        address: Address(
          line1: 'Avenue Example 2',
          city: 'Namur',
          postalCode: '5000',
          country: 'BE',
        ),
        contact: Contact(name: 'Accounts', email: 'ap@example.be'),
      ),
      payee: const Payee(
        name: 'Factor SA',
        identifier: Identifier('0111111111', scheme: '0208'),
      ),
      delivery: Delivery(
        name: 'Warehouse',
        date: CalendarDate(2026, 9, 10),
        locationIdentifier: const Identifier('LOC-1', scheme: '0088'),
        address:
            const Address(city: 'Liege', postalCode: '4000', country: 'BE'),
      ),
      paymentInstructions: const PaymentInstructions(
        means: PaymentMeansCode.sepaCreditTransfer,
        meansText: 'Bank transfer',
        remittanceInformation: '+++090/9337/55493+++',
        creditTransfers: [
          CreditTransferAccount(
            'BE68539007547034',
            name: 'COMAPPS SRL',
            providerBic: 'GEBABEBB',
          ),
        ],
      ),
      allowancesAndCharges: [
        DocumentAllowanceCharge(
          kind: AllowanceOrCharge.allowance,
          amount: _d('50.00'),
          baseAmount: _d('1200.00'),
          percentage: _d('4.17'),
          vatCategory: VatCategory.standardRate,
          vatRate: _d('21'),
          reason: 'Loyalty discount',
          reasonCode: '95',
        ),
      ],
      lines: [
        InvoiceLine(
          id: '1',
          quantity: _d('8'),
          unit: UnitCode.hour,
          netAmount: _d('1200.00'),
          note: 'September',
          buyerOrderLineReference: '1',
          buyerAccountingReference: '6000',
          objectIdentifier: const Identifier('LINE-OBJ', scheme: 'AAU'),
          period: DatePeriod(
            start: CalendarDate(2026, 9, 1),
            end: CalendarDate(2026, 9, 30),
          ),
          item: const Item(
            name: 'Consulting',
            description: 'Integration work',
            sellerIdentifier: 'SRV-CONS',
            buyerIdentifier: 'BUY-CONS',
            standardIdentifier: Identifier('5412345678901', scheme: '0160'),
            classificationIdentifiers: [Identifier('86121', scheme: 'STI')],
            originCountry: 'BE',
            attributes: [ItemAttribute('Seniority', 'Senior')],
          ),
          price: Price(
            netPrice: _d('150.00'),
            discount: _d('10.00'),
            grossPrice: _d('160.00'),
            baseQuantity: _d('1'),
            baseQuantityUnit: UnitCode.hour,
          ),
          vatCategory: VatCategory.standardRate,
          vatRate: _d('21'),
          allowancesAndCharges: [
            LineAllowanceCharge(
              kind: AllowanceOrCharge.charge,
              amount: _d('5.00'),
              reason: 'Rush',
              reasonCode: 'ZZZ',
            ),
          ],
        ),
      ],
      vatBreakdown: [
        VatBreakdown(
          category: VatCategory.standardRate,
          taxableAmount: _d('1150.00'),
          taxAmount: _d('241.50'),
          rate: _d('21'),
        ),
      ],
      totals: InvoiceTotals(
        sumOfLineNetAmounts: _d('1200.00'),
        sumOfAllowances: _d('50.00'),
        totalWithoutVat: _d('1150.00'),
        totalVat: _d('241.50'),
        totalWithVat: _d('1391.50'),
        paidAmount: _d('100.00'),
        roundingAmount: _d('0.05'),
        amountDueForPayment: _d('1291.55'),
      ),
    );

void main() {
  group('the round trip', () {
    test('loses nothing a rich invoice carries', () {
      final written = writeUbl(_rich());
      final again = writeUbl(readUbl(written));
      expect(again, written);
    });

    test('reads the terms back one by one', () {
      final invoice = readUbl(writeUbl(_rich()));
      expect(invoice.number, '2026-0042');
      expect(invoice.issueDate, CalendarDate(2026, 9, 13));
      expect(invoice.dueDate, CalendarDate(2026, 10, 13));
      expect(invoice.specificationIdentifier, en16931Specification);
      expect(invoice.buyerReference, 'PO-77812');
      expect(invoice.seller.name, 'COMAPPS SRL');
      expect(invoice.seller.tradingName, 'ComApps');
      expect(invoice.seller.vatIdentifier, 'BE0123456789');
      expect(invoice.seller.taxRegistrationIdentifier, 'BE-TAX-1');
      expect(invoice.seller.contact?.email, 'billing@example.be');
      expect(invoice.buyer.vatIdentifier, 'BE0987654321');
      expect(invoice.payee?.name, 'Factor SA');
      expect(invoice.delivery?.date, CalendarDate(2026, 9, 10));
      expect(invoice.delivery?.address?.city, 'Liege');
      expect(invoice.paymentInstructions?.means.value, '58');
      expect(
        invoice.paymentInstructions?.creditTransfers.single.identifier,
        'BE68539007547034',
      );
      expect(invoice.notes, hasLength(2));
      expect(invoice.notes.last.subjectCode, 'AAI');
      expect(invoice.notes.last.text, 'Delivered in full.');
      expect(invoice.precedingInvoices.single.reference, '2026-0041');
      expect(invoice.supportingDocuments, hasLength(2));
      expect(
        utf8.decode(invoice.supportingDocuments.first.attachment!.bytes),
        'hours',
      );
      expect(
        invoice.supportingDocuments.last.externalUri.toString(),
        'https://example.be/terms',
      );
      expect(invoice.objectIdentifier?.value, 'METER-1');
      expect(invoice.allowancesAndCharges.single.reasonCode, '95');
      expect(invoice.totals.paidAmount, _d('100.00'));
      expect(invoice.totals.roundingAmount, _d('0.05'));
      expect(invoice.totals.amountDueForPayment, _d('1291.55'));
      expect(invoice.vatBreakdown.single.taxAmount, _d('241.50'));

      final line = invoice.lines.single;
      expect(line.id, '1');
      expect(line.quantity, _d('8'));
      expect(line.unit, UnitCode.hour);
      expect(line.netAmount, _d('1200.00'));
      expect(line.item.name, 'Consulting');
      expect(line.item.standardIdentifier?.scheme, '0160');
      expect(line.item.classificationIdentifiers.single.scheme, 'STI');
      expect(line.item.attributes.single.value, 'Senior');
      expect(line.price.netPrice, _d('150.00'));
      expect(line.price.grossPrice, _d('160.00'));
      expect(line.allowancesAndCharges.single.kind, AllowanceOrCharge.charge);
      expect(line.period?.start, CalendarDate(2026, 9, 1));
    });

    test('survives a credit note', () {
      final invoice = Invoice.fromLines(
        number: '2026-0050',
        issueDate: DateTime(2026, 9, 13),
        typeCode: InvoiceTypeCode.creditNote,
        seller: const Seller(
          name: 'COMAPPS SRL',
          vatIdentifier: 'BE0123456789',
          address: Address(country: 'BE'),
        ),
        buyer: const Buyer(name: 'Client SA', address: Address(country: 'BE')),
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Refund'),
            quantity: 1,
            unitPrice: 100,
            vatRate: 21,
          ),
        ],
      );
      final written = writeUbl(invoice);
      final read = readUbl(written);
      expect(read.typeCode, InvoiceTypeCode.creditNote);
      expect(read.lines.single.item.name, 'Refund');
      expect(writeUbl(read), written);
    });

    test('keeps an invoice that breaks nothing breaking nothing', () {
      final invoice = Invoice.fromLines(
        number: '2026-0042',
        issueDate: DateTime(2026, 9, 13),
        seller: const Seller(
          name: 'COMAPPS SRL',
          vatIdentifier: 'BE0123456789',
          address: Address(country: 'BE'),
        ),
        buyer: const Buyer(name: 'Client SA', address: Address(country: 'BE')),
        lines: [
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
      expect(validate(invoice), isEmpty);
      expect(validate(readUbl(writeUbl(invoice))), isEmpty);
    });
  });

  group('a document from elsewhere', () {
    test('is read whatever prefixes it declares', () {
      const xml = '''
<ubl:Invoice
    xmlns:ubl="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
    xmlns:a="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
    xmlns:b="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <b:ID>X-1</b:ID>
  <b:IssueDate>2026-09-13</b:IssueDate>
  <b:InvoiceTypeCode>380</b:InvoiceTypeCode>
  <b:DocumentCurrencyCode>EUR</b:DocumentCurrencyCode>
</ubl:Invoice>''';
      final invoice = readUbl(xml);
      expect(invoice.number, 'X-1');
      expect(invoice.currency, 'EUR');
      expect(invoice.typeCode.value, '380');
    });

    test('is read as far as it goes, and validate says the rest', () {
      const xml = '''
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
    xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:ID>X-2</cbc:ID>
  <cbc:IssueDate>2026-09-13</cbc:IssueDate>
</Invoice>''';
      final invoice = readUbl(xml);
      expect(invoice.number, 'X-2');
      expect(invoice.lines, isEmpty);
      final broken = validate(invoice).map((v) => v.rule.id).toSet();
      expect(broken, containsAll(['BR-16', 'BR-06', 'BR-05']));
    });

    test('refuses what it cannot report on', () {
      expect(
          () => readUbl('not xml at all'), throwsA(isA<UblFormatException>()));
      expect(
        () => readUbl('<Order xmlns="urn:x"/>'),
        throwsA(isA<UblFormatException>()),
      );
      final dateless = <String>['<Invoice xmlns="', ublInvoice, '"/>'].join();
      expect(() => readUbl(dateless), throwsA(isA<UblFormatException>()));
    });
  });
}
