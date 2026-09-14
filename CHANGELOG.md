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
