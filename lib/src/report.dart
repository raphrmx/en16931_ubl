import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/src/reader.dart';
import 'package:xml/xml.dart';

/// An element a document carries that the semantic model has no room for.
final class SkippedElement {
  /// [count] occurrences of [name] were seen and not read.
  const SkippedElement(this.name, this.count);

  /// The element, as the document names it, `cac:SubInvoiceLine` say.
  final String name;

  /// How many of them the document carries.
  final int count;

  /// What the element is for, in words.
  String get purpose => ublElementsBeyondTheModel[name] ?? 'unknown';

  @override
  String toString() => '$count x $name ($purpose)';
}

/// A document read, and what reading it left behind.
final class UblRead {
  /// The [invoice] that was read, and the elements [skipped] getting there.
  const UblRead({required this.invoice, required this.skipped});

  /// The invoice, exactly as `readUbl` would give it.
  final Invoice invoice;

  /// What the document carried that the model cannot hold.
  final List<SkippedElement> skipped;

  /// Whether the document gave up everything it had.
  bool get isComplete => skipped.isEmpty;
}

/// The elements this package looks for, and what each one is.
///
/// Not every element a document may carry: the ones that lose information
/// worth knowing about. EN 16931 has no sub invoice line and no payment made
/// by somebody else, so a document carrying either comes into the model
/// without it, and the totals still add up because the parent line already
/// summed its children. That is the trap this list exists to spring.
///
/// The list grows when a case turns up. It is deliberately short: a narrow
/// signal that is true beats a wide one that cries wolf over every element
/// the reader is right to ignore.
const Map<String, String> ublElementsBeyondTheModel = {
  'cac:SubInvoiceLine':
      'a line under a line, which the XRechnung extension '
      'adds as BG-DEX-01',
  'cac:PrepaidPayment':
      'a payment made by somebody else, which the XRechnung '
      'extension adds as BG-DEX-09',
};

/// [document] read into an invoice, with what was left behind.
///
/// `readUbl` gives back the invoice and says nothing about what it could not
/// take. That silence is fine for a document written to the standard and a
/// trap for one written beyond it: an invoice of fifty-seven lines comes back
/// with one, adds up, and passes.
///
/// Throws the same [UblFormatException] as `readUbl`, on the same three
/// things.
UblRead readUblReporting(String document) {
  final invoice = readUbl(document);
  final XmlDocument parsed;
  try {
    parsed = XmlDocument.parse(document);
  } on XmlException {
    // readUbl has already refused anything that is not XML.
    return UblRead(invoice: invoice, skipped: const []);
  }

  final counts = <String, int>{};
  for (final element in parsed.descendantElements) {
    final name = element.name.qualified;
    if (!ublElementsBeyondTheModel.containsKey(name)) continue;
    counts[name] = (counts[name] ?? 0) + 1;
  }

  final names = counts.keys.toList()..sort();
  return UblRead(
    invoice: invoice,
    skipped: [for (final name in names) SkippedElement(name, counts[name]!)],
  );
}
