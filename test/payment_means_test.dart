import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';

/// An invoice that can be paid into either of two accounts.
Invoice _twoAccounts() => Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 14),
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
  ),
  paymentInstructions: const PaymentInstructions(
    means: PaymentMeansCode.sepaCreditTransfer,
    remittanceInformation: '+++090/9337/55493+++',
    creditTransfers: [
      CreditTransferAccount('BE68539007547034', name: 'Compte courant'),
      CreditTransferAccount('NL03INGB0004489902', name: 'Compte second'),
    ],
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
  group('several accounts (BG-17 repeated)', () {
    test('are written as one payment means each', () {
      // UBL carries one account to a payment means. Writing both into one
      // group is not what the schema allows, and not what the published
      // examples do.
      final xml = writeUbl(_twoAccounts());
      expect(RegExp('<cac:PaymentMeans>').allMatches(xml), hasLength(2));
      expect(
        RegExp('<cac:PayeeFinancialAccount>').allMatches(xml),
        hasLength(2),
      );
      for (final block in RegExp(
        r'<cac:PaymentMeans>[\s\S]*?</cac:PaymentMeans>',
      ).allMatches(xml)) {
        expect(
          RegExp('<cac:PayeeFinancialAccount>').allMatches(block.group(0)!),
          hasLength(1),
        );
      }
    });

    test('repeat the means code in every group', () {
      final xml = writeUbl(_twoAccounts());
      expect(RegExp('<cbc:PaymentMeansCode').allMatches(xml), hasLength(2));
      expect(RegExp('<cbc:PaymentID>').allMatches(xml), hasLength(2));
    });

    test('come back as one instruction carrying both', () {
      final invoice = readUbl(writeUbl(_twoAccounts()));
      final accounts = invoice.paymentInstructions!.creditTransfers;
      expect(accounts, hasLength(2));
      expect(accounts.first.identifier, 'BE68539007547034');
      expect(accounts.last.identifier, 'NL03INGB0004489902');
      expect(accounts.last.name, 'Compte second');
      expect(
        invoice.paymentInstructions!.remittanceInformation,
        '+++090/9337/55493+++',
      );
    });

    test('survive being written and read twice over', () {
      final once = writeUbl(_twoAccounts());
      expect(writeUbl(readUbl(once)), once);
    });

    test('leave the invoice satisfying the standard', () {
      expect(validate(readUbl(writeUbl(_twoAccounts()))), isEmpty);
    });

    test('the card and the mandate are written once, not once per group', () {
      final invoice = Invoice.fromLines(
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
        paymentInstructions: const PaymentInstructions(
          means: PaymentMeansCode.sepaDirectDebit,
          creditTransfers: [
            CreditTransferAccount('BE68539007547034'),
            CreditTransferAccount('NL03INGB0004489902'),
          ],
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
      final xml = writeUbl(invoice);
      expect(RegExp('<cac:PaymentMandate>').allMatches(xml), hasLength(1));
      expect(
        readUbl(xml).paymentInstructions!.directDebit!.mandateReference,
        'MND-1',
      );
    });
  });
}
