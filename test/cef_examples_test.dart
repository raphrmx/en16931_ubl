import 'dart:io';

import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:test/test.dart';

/// The example invoices the standard is published with.
///
/// They are EUPL 1.2 and are not part of this repository. Run
/// `dart run tool/fetch_examples.dart` to pull them in, and these tests wake
/// up. Reading our own output back proves the writer and the reader agree
/// with each other; reading these proves they agree with everyone else.
const String _directory = 'examples_from_cef';

void main() {
  final directory = Directory(_directory);
  if (!directory.existsSync()) {
    test('the published examples', () {}, skip: 'Run tool/fetch_examples.dart');
    return;
  }

  final files = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are examples to read', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late Invoice invoice;

      setUp(() {
        invoice = readUbl(file.readAsStringSync());
      });

      test('is read', () {
        expect(invoice.number, isNotEmpty);
        expect(invoice.lines, isNotEmpty);
        expect(invoice.seller.name, isNotEmpty);
        expect(invoice.buyer.name, isNotEmpty);
      });

      test('breaks no rule', () {
        // These are the documents the standard publishes as examples of
        // itself. One of them reporting a violation means this library reads
        // or checks something wrong, not that the example is wrong.
        expect(
          validate(invoice).map((violation) => violation.toString()),
          isEmpty,
        );
      });

      test('survives being written and read again', () {
        final once = writeUbl(invoice);
        final twice = writeUbl(readUbl(once));
        expect(twice, once);
      });
    });
  }
}
