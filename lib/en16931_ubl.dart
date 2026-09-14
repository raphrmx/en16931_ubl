/// UBL 2.1 for the European electronic invoice.
///
/// UBL is one of the two syntaxes EN 16931 is written in, and the one Peppol
/// carries. This library writes the semantic model out as UBL and reads it
/// back, and nothing else: what an invoice has to contain is the model's
/// business, and sending it is nobody's business here.
library;

export 'src/reader.dart' show UblFormatException, readUbl;
export 'src/report.dart'
    show SkippedElement, UblRead, readUblReporting, ublElementsBeyondTheModel;
export 'src/writer.dart' show isCreditNote, ublCreditNote, ublInvoice, writeUbl;
