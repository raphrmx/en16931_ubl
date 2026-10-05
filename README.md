# EN 16931 UBL

[![Live demo](https://img.shields.io/badge/Live_demo-packages.comapps.be-3c9a70)](https://packages.comapps.be/en16931/)
[![Pub Version](https://img.shields.io/pub/v/en16931_ubl?color=0175C2)](https://pub.dev/packages/en16931_ubl)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/en16931_ubl/ci.yml?branch=main&label=build)](https://github.com/raphrmx/en16931_ubl/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=ZN6D382YQAV5N)

Writes the European electronic invoice as UBL 2.1, the syntax Peppol carries
and most of Europe reads.

## Install

```yaml
dependencies:
  en16931: ^0.1.2
  en16931_ubl: ^0.1.3
```

## Write an invoice out

Build it with [en16931](https://pub.dev/packages/en16931), check it, then hand
it over.

```dart
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';

final invoice = Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 13),
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0123456789',
    electronicAddress: Identifier('0123456789', scheme: Scheme.belgianEnterprise),
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    electronicAddress: Identifier('0987654321', scheme: Scheme.belgianEnterprise),
    address: Address(city: 'Namur', postalCode: '5000', country: 'BE'),
  ),
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

if (validate(invoice).isEmpty) {
  final xml = writeUbl(invoice);
}
```

## Read one back

A supplier invoice goes the other way. What the document does not carry is
left out rather than guessed, so `validate` tells you what the supplier got
wrong instead of the reader hiding it.

```dart
final invoice = readUbl(xml);

for (final violation in validate(invoice)) {
  print(violation); // [BR-16] The invoice has no line (BG-25).
}
```

`readUbl` throws `UblFormatException` on three things only: text that is not
XML, a root that is neither an Invoice nor a CreditNote, and a document with
no issue date. Those leave nothing to report on. Everything else is read as
far as it goes.

A document written beyond the standard is read as far as the standard goes,
and no further. `readUblReporting` says what was left behind, which matters
more than it sounds: an invoice whose lines carry lines of their own comes
back with the parents only, still adds up, and passes.

```dart
final read = readUblReporting(xml);

for (final element in read.skipped) {
  print(element); // 56 x cac:SubInvoiceLine (a line under a line, which ...)
}
```

`ublElementsBeyondTheModel` names what is looked for. It is a short list on
purpose: a narrow signal that is true beats a wide one that cries wolf over
every element the reader is right to ignore.

## Worth knowing up front

The elements come out in the order the UBL schema fixes, which is not the
order the standard lists the terms in. A receiver validates against that
schema before it reads a single business rule, so an invoice whose elements
are out of order is not rejected on its content: it is not read at all.

A credit note goes out under the CreditNote root, with `CreditNoteLine` and
`CreditedQuantity`. The type codes 381, 396 and 532 take that root, and
`isCreditNote` says which.

Amounts are written with two decimals and the currency they are in. A unit
price keeps the decimals it was given.

## What it does not do

It does not decide what an invoice has to contain: that is the model's
business, and `validate` from [en16931](https://pub.dev/packages/en16931) says
whether it holds up. A network or a country puts its own rules on top of the
standard, and those live in a profile package:
[en16931_peppol](https://pub.dev/packages/en16931_peppol) for Peppol BIS
Billing and [en16931_xrechnung](https://pub.dev/packages/en16931_xrechnung)
for Germany. Delivery is a separate choice: the same document goes over
Peppol, through a portal, or as an attachment.

## License

Released under the [MIT licence](https://pub.dev/packages/en16931_ubl/license).

## More from COMAPPS

The EN 16931 family:

| Package | What it does |
| --- | --- |
| [en16931](https://pub.dev/packages/en16931) | The semantic model of the European invoice and the rules of the standard. |
| [en16931_cii](https://pub.dev/packages/en16931_cii) | Writes and reads it as UN/CEFACT CII. |
| [en16931_peppol](https://pub.dev/packages/en16931_peppol) | The Peppol BIS Billing 3.0 profile. |
| [en16931_xrechnung](https://pub.dev/packages/en16931_xrechnung) | The XRechnung profile, for German public bodies. |
| [en16931_facturx](https://pub.dev/packages/en16931_facturx) | The Factur-X profile and its hybrid PDF. |
| [en16931_ublbe](https://pub.dev/packages/en16931_ublbe) | The UBL.BE profile, for Belgian accounting software. |

Every package COMAPPS publishes is listed at
[packages.comapps.be](https://packages.comapps.be).
