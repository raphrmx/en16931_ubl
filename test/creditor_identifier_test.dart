import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';

/// The invoice a direct debit is collected on.
Invoice _invoice() => Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 14),
  dueDate: DateTime(2026, 10, 14),
  buyerReference: 'CMD-778',
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    identifiers: [Identifier('0123456749', scheme: '0208')],
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
  ),
  paymentInstructions: const PaymentInstructions(
    means: PaymentMeansCode.sepaDirectDebit,
    directDebit: DirectDebit(
      mandateReference: 'MND-1',
      creditorIdentifier: 'BE98ZZZ0123456789',
      debitedAccountIdentifier: 'BE68539007547034',
    ),
  ),
  lines: [
    InvoiceLine.of(
      id: '1',
      item: const Item(name: 'Consulting'),
      quantity: 1,
      unitPrice: 100,
      vatRate: 21,
    ),
  ],
);

void main() {
  group('the creditor identifier (BT-90)', () {
    test('is written as a party identification under the SEPA scheme', () {
      // UBL gives the term no element of its own, which is why it was dropped
      // here until the KoSIT test suite refused an invoice over it.
      final xml = writeUbl(_invoice());
      expect(xml, contains('schemeID="SEPA"'));
      expect(xml, contains('BE98ZZZ0123456789'));
    });

    test('comes back on the direct debit and not among the identifiers', () {
      final invoice = readUbl(writeUbl(_invoice()));
      expect(
        invoice.paymentInstructions?.directDebit?.creditorIdentifier,
        'BE98ZZZ0123456789',
      );
      expect(
        invoice.seller.identifiers.map((id) => id.scheme),
        isNot(contains('SEPA')),
        reason: 'reading it as a party identifier breaks BR-CL-10',
      );
      expect(invoice.seller.identifiers, hasLength(1));
    });

    test('leaves the invoice satisfying the standard', () {
      expect(validate(readUbl(writeUbl(_invoice()))), isEmpty);
    });

    test('survives being written and read twice over', () {
      final once = writeUbl(_invoice());
      expect(writeUbl(readUbl(once)), once);
    });

    test('is absent from a document that has no direct debit', () {
      final transfer = Invoice.fromLines(
        number: '1',
        issueDate: DateTime(2026, 9, 14),
        seller: const Seller(
          name: 'COMAPPS SRL',
          vatIdentifier: 'BE0123456789',
          address: Address(
            city: 'Bruxelles',
            postalCode: '1000',
            country: 'BE',
          ),
        ),
        buyer: const Buyer(
          name: 'Client SA',
          address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
        ),
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Consulting'),
            quantity: 1,
            unitPrice: 100,
            vatRate: 21,
          ),
        ],
      );
      expect(writeUbl(transfer), isNot(contains('SEPA')));
    });
  });

  group('the payment terms (BT-20)', () {
    test('keep the line break that closes a discount', () {
      // Germany reads a discount out of that text and needs the break. Every
      // other term is trimmed; this one cannot be.
      const terms = 'Zahlbar netto.\n#SKONTO#TAGE=14#PROZENT=2.00#\n';
      final invoice = Invoice.fromLines(
        number: '1',
        issueDate: DateTime(2026, 9, 14),
        paymentTerms: terms,
        seller: const Seller(
          name: 'COMAPPS SRL',
          vatIdentifier: 'BE0123456789',
          address: Address(
            city: 'Bruxelles',
            postalCode: '1000',
            country: 'BE',
          ),
        ),
        buyer: const Buyer(
          name: 'Client SA',
          address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
        ),
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Consulting'),
            quantity: 1,
            unitPrice: 100,
            vatRate: 21,
          ),
        ],
      );
      expect(readUbl(writeUbl(invoice)).paymentTerms, terms);
    });
  });
}
