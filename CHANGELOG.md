## 0.1.6

- The package asks for Dart 3.3 instead of 3.11, which is what carried the
  floor: `xml` 7 requires 3.11 of its own accord. The writer builds its
  namespaces through `XmlBuilder.namespace`, the only spelling `xml` 6 has and
  one `xml` 7 still accepts, so the constraint spans both at `>=6.5.0 <8.0.0`.
  A project already on `xml` 7 can still take this package.
- The reader spells two null-aware elements as an `if`-`case`, the form that
  reads the same and does not ask for 3.8.

## 0.1.5

- `homepage` points at the package's card on comapps.web.app, which lists
  every package published under COMAPPS.
- The README badge row carries a Live demo badge, the maintainer again, and a
  licence badge in a colour of its own rather than the grey shields puts in
  every label. Nothing about the library changed.

## 0.1.4

- An attachment whose base64 is wrapped over several lines is read. XML
  allows the line breaks and a mail client writes them, but the decoder
  refused them, so reading any of the test cases UBL.BE publishes threw.
- A delivery that holds nothing the model carries is neither read nor
  written. A document whose delivery holds only its terms, as a Belgian one
  carrying a legal mention does, came back with an empty delivery and went
  out again as an empty element, which Peppol refuses.

## 0.1.3

- Several payment accounts (BG-17 repeated) are written and read. UBL carries
  one account to a payment means, so an invoice offering two writes the group
  twice; both sides put them all in one group, so a document offering two
  accounts came back offering one and nothing complained. The standard's own
  first example is written that way.
- `readUblReporting` gives back the invoice and what the document carried that
  the model has no room for. `readUbl` says nothing about it, which is fine
  for a document written to the standard and a trap for one written beyond
  it: an invoice of fifty-seven lines comes back with one, adds up, and
  passes. `ublElementsBeyondTheModel` names what is looked for.

## 0.1.2

- The README says that delivery is a separate choice, where it used to end on
  what the package does not do.
- The licence badge and the licence section point at the licence page on
  pub.dev. The README carries no link off to a code host any more.
- `xml` moves to 7, which raises the Dart floor to 3.11. The writer names a
  namespace by its prefix and its URI in that order, where version 6 took them
  the other way round.
- The creditor identifier (BT-90) is written and read. UBL gives it no
  element of its own: it is a party identification of the seller under the
  SEPA scheme, so it was lost on the way out and read back as a party
  identifier on the way in, which refused a correct invoice under BR-CL-10.
- The payment terms (BT-20) keep their whitespace. Every other term is
  trimmed, but Germany reads a discount for early payment out of that text
  line by line, and the line break closing the last one has to survive.
- The payment terms keep their line breaks through the printer as well. A
  pretty printed document reflows the text inside it, which is harmless
  everywhere but here, and turned a valid German invoice into one that breaks
  BR-DE-18.

## 0.1.1

- The README names the packages that do what this one does not: the model and
  the rules in `en16931`, and the profiles of Peppol and Germany.

## 0.1.0

First release.

- `writeUbl` writes an EN 16931 invoice out as UBL 2.1, the syntax Peppol
  carries and most of Europe reads.
- The elements come out in the order the UBL schema fixes, which is not the
  order the standard lists the terms in. A receiver validates against that
  schema before it reads a business rule, so an invoice out of order is not
  rejected on its content: it is not read at all. A test holds the order.
- A credit note goes out under the CreditNote root, with CreditNoteLine and
  CreditedQuantity, rather than as an invoice carrying a credit note type
  code. The type codes 381, 396 and 532 are the ones that take that root.
- Monetary amounts are written with two decimals and the currency they are
  in. A unit price keeps the decimals it was given, because rounding it would
  change what is being sold.
- Identifiers carry their scheme where UBL asks for one: the electronic
  address, the party identifiers, the item standard identifier and the item
  classification.
- Nothing here decides what an invoice has to contain. Build it and check it
  with `en16931`, then write it out.
- `readUbl` reads a UBL invoice or credit note back into the model. What the
  document does not carry is left out rather than guessed, so an invoice that
  is missing a term comes back missing it and `validate` says which rule that
  breaks. Reading is how you find out a supplier sent something wrong.
- Elements are matched on their local name, so a document is read whatever
  prefixes it declares its namespaces under.
- `readUbl` throws `UblFormatException` on three things only: text that is not
  XML, a root that is neither an Invoice nor a CreditNote, and a document with
  no issue date. Those leave nothing to report on.
- A test writes a full invoice out, reads it back and writes it again, and
  holds the two documents to be the same byte for byte.
- The eighteen example invoices the standard is published with are read, found
  to break no rule, and written back out unchanged. They are EUPL 1.2, so a
  tool fetches them and a test wakes up when they are there. Reading our own
  output back proves the writer and the reader agree with each other; reading
  these proves they agree with everyone else.
- BT-111 is read as any TaxTotal amount carrying the accounting currency,
  which is how the rule reads it. When the accounting currency is the one the
  invoice is written in, a single TaxTotal stands for both BT-110 and BT-111,
  and the second one is no longer written out. Reading the published examples
  is what turned this up: an invoice declaring the same currency twice came
  back missing BT-111 and reported BR-53 against a document that is correct.
