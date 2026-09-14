import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/src/writer.dart' show sepaScheme;
import 'package:xml/xml.dart';

/// A document that is not a UBL invoice this package can read.
class UblFormatException implements FormatException {
  /// A document that could not be read, because of [message].
  const UblFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final String? source;

  @override
  final int? offset;

  @override
  String toString() => 'UblFormatException: $message';
}

/// Reads a UBL 2.1 invoice or credit note into the semantic model.
///
/// What the document does not carry is left out rather than guessed, so an
/// invoice that is missing a term comes back missing it and `validate` says
/// which rule that breaks. Reading is how you find out a supplier sent
/// something wrong, so a document is read as far as it can be.
///
/// Throws [UblFormatException] when the text is not XML, when its root is
/// neither an Invoice nor a CreditNote, or when it carries no issue date.
/// Those three leave nothing to report on.
Invoice readUbl(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (error) {
    throw UblFormatException('Not XML: ${error.message}');
  }

  final root = document.rootElement;
  final creditNote = root.localName == 'CreditNote';
  if (!creditNote && root.localName != 'Invoice') {
    throw const UblFormatException(
      'The root is neither an Invoice nor a CreditNote',
    );
  }

  final issued = _date(root, 'IssueDate');
  if (issued == null) {
    throw const UblFormatException('The document carries no issue date');
  }

  final currency = _text(root, 'DocumentCurrencyCode') ?? '';
  final typeCode = _text(
    root,
    creditNote ? 'CreditNoteTypeCode' : 'InvoiceTypeCode',
  );

  return Invoice(
    number: _text(root, 'ID') ?? '',
    issueDate: issued,
    dueDate: _date(root, 'DueDate'),
    typeCode: InvoiceTypeCode(typeCode ?? ''),
    currency: currency,
    specificationIdentifier: _text(root, 'CustomizationID'),
    businessProcess: _text(root, 'ProfileID'),
    vatAccountingCurrency: _text(root, 'TaxCurrencyCode'),
    vatPointDate: _date(root, 'TaxPointDate'),
    buyerReference: _text(root, 'BuyerReference'),
    buyerAccountingReference: _text(root, 'AccountingCost'),
    notes: _notes(root),
    invoicingPeriod: _period(_child(root, 'InvoicePeriod')),
    purchaseOrderReference: _text(root, 'OrderReference/ID'),
    salesOrderReference: _text(root, 'OrderReference/SalesOrderID'),
    despatchAdviceReference: _text(root, 'DespatchDocumentReference/ID'),
    receivingAdviceReference: _text(root, 'ReceiptDocumentReference/ID'),
    tenderReference: _text(root, 'OriginatorDocumentReference/ID'),
    contractReference: _text(root, 'ContractDocumentReference/ID'),
    projectReference: _text(root, 'ProjectReference/ID'),
    objectIdentifier: _objectIdentifier(root),
    precedingInvoices: _precedingInvoices(root),
    supportingDocuments: _supportingDocuments(root),
    seller: _seller(root),
    buyer: _buyer(root),
    payee: _payee(root),
    taxRepresentative: _taxRepresentative(root),
    delivery: _delivery(root),
    paymentInstructions: _payment(root),
    paymentTerms: _verbatim(root, 'PaymentTerms/Note'),
    allowancesAndCharges: _documentEntries(root),
    vatBreakdown: _breakdown(root),
    totals: _totals(root),
    lines: _lines(root, creditNote: creditNote),
  );
}

// --- The head of the document ----------------------------------------------

List<InvoiceNote> _notes(XmlElement root) {
  final notes = <InvoiceNote>[];
  for (final element in _children(root, 'Note')) {
    final text = element.innerText;
    // UBL carries a subject code in front of the text, between two hashes.
    final match = RegExp(r'^#([^#]+)#(.*)$', dotAll: true).firstMatch(text);
    notes.add(
      match == null
          ? InvoiceNote(text)
          : InvoiceNote(match.group(2)!, subjectCode: match.group(1)),
    );
  }
  return notes;
}

DatePeriod? _period(XmlElement? element) {
  if (element == null) return null;
  final start = _date(element, 'StartDate');
  final end = _date(element, 'EndDate');
  if (start == null && end == null) return const DatePeriod();
  return DatePeriod(start: start, end: end);
}

Identifier? _objectIdentifier(XmlElement root) {
  for (final reference in _children(root, 'AdditionalDocumentReference')) {
    if (_text(reference, 'DocumentTypeCode') != '130') continue;
    return _identifier(reference, 'ID', 'schemeID');
  }
  return null;
}

List<PrecedingInvoiceReference> _precedingInvoices(XmlElement root) {
  final references = <PrecedingInvoiceReference>[];
  for (final billing in _children(root, 'BillingReference')) {
    final reference = _child(billing, 'InvoiceDocumentReference');
    if (reference == null) continue;
    references.add(
      PrecedingInvoiceReference(
        _text(reference, 'ID') ?? '',
        issueDate: _date(reference, 'IssueDate'),
      ),
    );
  }
  return references;
}

List<SupportingDocument> _supportingDocuments(XmlElement root) {
  final documents = <SupportingDocument>[];
  for (final reference in _children(root, 'AdditionalDocumentReference')) {
    if (_text(reference, 'DocumentTypeCode') == '130') continue;
    final attachment = _child(reference, 'Attachment');
    final binary = attachment == null
        ? null
        : _child(attachment, 'EmbeddedDocumentBinaryObject');
    final uri = attachment == null
        ? null
        : _text(attachment, 'ExternalReference/URI');
    documents.add(
      SupportingDocument(
        _text(reference, 'ID') ?? '',
        description: _text(reference, 'DocumentDescription'),
        externalUri: uri == null ? null : Uri.tryParse(uri),
        attachment: binary == null
            ? null
            : Attachment(
                bytes: Uint8List.fromList(base64Decode(binary.innerText)),
                mimeCode: binary.getAttribute('mimeCode') ?? '',
                filename: binary.getAttribute('filename') ?? '',
              ),
      ),
    );
  }
  return documents;
}

// --- Who is who ------------------------------------------------------------

Seller _seller(XmlElement root) {
  final party = _child(root, 'AccountingSupplierParty/Party');
  if (party == null) {
    return const Seller(
      name: '',
      address: Address(country: ''),
    );
  }
  return Seller(
    name: _text(party, 'PartyLegalEntity/RegistrationName') ?? '',
    tradingName: _text(party, 'PartyName/Name'),
    address: _address(_child(party, 'PostalAddress')),
    identifiers: [
      for (final identification in _children(party, 'PartyIdentification'))
        // The creditor identifier (BT-90) sits among these under the SEPA
        // scheme. It is not a party identifier, and reading it as one refuses
        // the invoice under BR-CL-10 while losing the term it really is.
        if (_scheme(identification) != sepaScheme)
          ?_identifier(identification, 'ID', 'schemeID'),
    ],
    legalRegistrationIdentifier: _identifier(
      _child(party, 'PartyLegalEntity'),
      'CompanyID',
      'schemeID',
    ),
    vatIdentifier: _taxSchemeId(party, 'VAT'),
    taxRegistrationIdentifier: _taxSchemeId(party, 'TAX'),
    additionalLegalInformation: _text(
      party,
      'PartyLegalEntity/CompanyLegalForm',
    ),
    electronicAddress: _identifier(party, 'EndpointID', 'schemeID'),
    contact: _contact(_child(party, 'Contact')),
  );
}

Buyer _buyer(XmlElement root) {
  final party = _child(root, 'AccountingCustomerParty/Party');
  if (party == null) {
    return const Buyer(
      name: '',
      address: Address(country: ''),
    );
  }
  return Buyer(
    name:
        _text(party, 'PartyLegalEntity/RegistrationName') ??
        _text(party, 'PartyName/Name') ??
        '',
    address: _address(_child(party, 'PostalAddress')),
    identifier: _identifier(
      _child(party, 'PartyIdentification'),
      'ID',
      'schemeID',
    ),
    legalRegistrationIdentifier: _identifier(
      _child(party, 'PartyLegalEntity'),
      'CompanyID',
      'schemeID',
    ),
    vatIdentifier: _taxSchemeId(party, 'VAT'),
    electronicAddress: _identifier(party, 'EndpointID', 'schemeID'),
    contact: _contact(_child(party, 'Contact')),
  );
}

Payee? _payee(XmlElement root) {
  final party = _child(root, 'PayeeParty');
  if (party == null) return null;
  return Payee(
    name: _text(party, 'PartyName/Name') ?? '',
    identifier: _identifier(
      _child(party, 'PartyIdentification'),
      'ID',
      'schemeID',
    ),
    legalRegistrationIdentifier: _identifier(
      _child(party, 'PartyLegalEntity'),
      'CompanyID',
      'schemeID',
    ),
  );
}

TaxRepresentative? _taxRepresentative(XmlElement root) {
  final party = _child(root, 'TaxRepresentativeParty');
  if (party == null) return null;
  return TaxRepresentative(
    name: _text(party, 'PartyName/Name') ?? '',
    vatIdentifier: _taxSchemeId(party, 'VAT') ?? '',
    address: _address(_child(party, 'PostalAddress')),
  );
}

/// The company identifier a party carries under one tax scheme.
String? _taxSchemeId(XmlElement party, String scheme) {
  for (final element in _children(party, 'PartyTaxScheme')) {
    if (_text(element, 'TaxScheme/ID')?.toUpperCase() != scheme) continue;
    return _text(element, 'CompanyID');
  }
  return null;
}

Address _address(XmlElement? element) {
  if (element == null) return const Address(country: '');
  return Address(
    country: _text(element, 'Country/IdentificationCode') ?? '',
    line1: _text(element, 'StreetName'),
    line2: _text(element, 'AdditionalStreetName'),
    line3: _text(element, 'AddressLine/Line'),
    city: _text(element, 'CityName'),
    postalCode: _text(element, 'PostalZone'),
    countrySubdivision: _text(element, 'CountrySubentity'),
  );
}

Contact? _contact(XmlElement? element) {
  if (element == null) return null;
  return Contact(
    name: _text(element, 'Name'),
    telephone: _text(element, 'Telephone'),
    email: _text(element, 'ElectronicMail'),
  );
}

// --- Delivery and payment --------------------------------------------------

Delivery? _delivery(XmlElement root) {
  final element = _child(root, 'Delivery');
  if (element == null) return null;
  final location = _child(element, 'DeliveryLocation');
  return Delivery(
    name: _text(element, 'DeliveryParty/PartyName/Name'),
    date: _date(element, 'ActualDeliveryDate'),
    locationIdentifier: location == null
        ? null
        : _identifier(location, 'ID', 'schemeID'),
    address: location == null || _child(location, 'Address') == null
        ? null
        : _address(_child(location, 'Address')),
  );
}

/// BG-16, gathered from every payment means the document writes.
///
/// UBL carries one account to a payment means, so an invoice offering two
/// accounts writes the group twice rather than the account twice. Reading
/// only the first group gives back an invoice that offers one account where
/// the sender offered several, and nothing complains: the rules count no
/// accounts. The standard's own first example is written that way.
PaymentInstructions? _payment(XmlElement root) {
  final groups = _children(root, 'PaymentMeans').toList();
  if (groups.isEmpty) return null;
  final element = groups.first;
  final code = _child(element, 'PaymentMeansCode');
  final card = groups
      .map((group) => _child(group, 'CardAccount'))
      .nonNulls
      .firstOrNull;
  final mandate = groups
      .map((group) => _child(group, 'PaymentMandate'))
      .nonNulls
      .firstOrNull;
  return PaymentInstructions(
    means: PaymentMeansCode(code?.innerText ?? ''),
    meansText: code?.getAttribute('name'),
    remittanceInformation: _text(element, 'PaymentID'),
    creditTransfers: [
      for (final group in groups)
        for (final account in _children(group, 'PayeeFinancialAccount'))
          CreditTransferAccount(
            _text(account, 'ID') ?? '',
            name: _text(account, 'Name'),
            providerBic: _text(account, 'FinancialInstitutionBranch/ID'),
          ),
    ],
    card: card == null
        ? null
        : PaymentCard(
            _text(card, 'PrimaryAccountNumberID') ?? '',
            holderName: _text(card, 'HolderName'),
          ),
    directDebit: mandate == null
        ? null
        : DirectDebit(
            mandateReference: _text(mandate, 'ID'),
            creditorIdentifier: _creditorIdentifier(root),
            debitedAccountIdentifier: _text(
              mandate,
              'PayerFinancialAccount/ID',
            ),
          ),
  );
}

// --- The figures -----------------------------------------------------------

List<DocumentAllowanceCharge> _documentEntries(XmlElement root) {
  final entries = <DocumentAllowanceCharge>[];
  for (final element in _children(root, 'AllowanceCharge')) {
    final category = _child(element, 'TaxCategory');
    entries.add(
      DocumentAllowanceCharge(
        kind: _text(element, 'ChargeIndicator') == 'true'
            ? AllowanceOrCharge.charge
            : AllowanceOrCharge.allowance,
        amount: _decimal(element, 'Amount') ?? Decimal.zero,
        baseAmount: _decimal(element, 'BaseAmount'),
        percentage: _decimal(element, 'MultiplierFactorNumeric'),
        vatCategory: _category(_text(category, 'ID')),
        vatRate: category == null ? null : _decimal(category, 'Percent'),
        reason: _text(element, 'AllowanceChargeReason'),
        reasonCode: _text(element, 'AllowanceChargeReasonCode'),
      ),
    );
  }
  return entries;
}

List<VatBreakdown> _breakdown(XmlElement root) {
  final breakdown = <VatBreakdown>[];
  for (final total in _children(root, 'TaxTotal')) {
    for (final subtotal in _children(total, 'TaxSubtotal')) {
      final category = _child(subtotal, 'TaxCategory');
      breakdown.add(
        VatBreakdown(
          category: _category(_text(category, 'ID')),
          taxableAmount: _decimal(subtotal, 'TaxableAmount') ?? Decimal.zero,
          taxAmount: _decimal(subtotal, 'TaxAmount') ?? Decimal.zero,
          rate: category == null ? null : _decimal(category, 'Percent'),
          exemptionReason: _text(category, 'TaxExemptionReason'),
          exemptionReasonCode: _text(category, 'TaxExemptionReasonCode'),
        ),
      );
    }
  }
  return breakdown;
}

InvoiceTotals _totals(XmlElement root) {
  final element = _child(root, 'LegalMonetaryTotal');
  final currency = _text(root, 'DocumentCurrencyCode');
  final vat = _vatTotal(root, currency);
  final accounting = _accountingVatTotal(root);
  if (element == null) {
    return InvoiceTotals(
      sumOfLineNetAmounts: Decimal.zero,
      totalWithoutVat: Decimal.zero,
      totalWithVat: Decimal.zero,
      amountDueForPayment: Decimal.zero,
      totalVat: vat,
      totalVatInAccountingCurrency: accounting,
    );
  }
  return InvoiceTotals(
    sumOfLineNetAmounts:
        _decimal(element, 'LineExtensionAmount') ?? Decimal.zero,
    totalWithoutVat: _decimal(element, 'TaxExclusiveAmount') ?? Decimal.zero,
    totalWithVat: _decimal(element, 'TaxInclusiveAmount') ?? Decimal.zero,
    amountDueForPayment: _decimal(element, 'PayableAmount') ?? Decimal.zero,
    sumOfAllowances: _decimal(element, 'AllowanceTotalAmount'),
    sumOfCharges: _decimal(element, 'ChargeTotalAmount'),
    paidAmount: _decimal(element, 'PrepaidAmount'),
    roundingAmount: _decimal(element, 'PayableRoundingAmount'),
    totalVat: vat,
    totalVatInAccountingCurrency: accounting,
  );
}

/// BT-111, the VAT total written in the accounting currency.
///
/// It is any TaxTotal amount carrying that currency, which is how the rule
/// reads it. When the accounting currency is the document currency, one
/// element stands for both BT-110 and BT-111, and the invoice that does that
/// is complete rather than missing a term.
Decimal? _accountingVatTotal(XmlElement root) {
  final currency = _text(root, 'TaxCurrencyCode');
  if (currency == null) return null;
  for (final total in _children(root, 'TaxTotal')) {
    final amount = _child(total, 'TaxAmount');
    if (amount?.getAttribute('currencyID') != currency) continue;
    return Decimal.tryParse(amount!.innerText);
  }
  return null;
}

/// The VAT total, which is the one written in the document currency.
Decimal? _vatTotal(XmlElement root, String? currency) {
  for (final total in _children(root, 'TaxTotal')) {
    final amount = _child(total, 'TaxAmount');
    if (amount == null) continue;
    final written = amount.getAttribute('currencyID');
    if (currency != null && written != null && written != currency) continue;
    return Decimal.tryParse(amount.innerText);
  }
  return null;
}

List<InvoiceLine> _lines(XmlElement root, {required bool creditNote}) {
  final lines = <InvoiceLine>[];
  final name = creditNote ? 'CreditNoteLine' : 'InvoiceLine';
  final quantityName = creditNote ? 'CreditedQuantity' : 'InvoicedQuantity';
  for (final element in _children(root, name)) {
    final quantity = _child(element, quantityName);
    final item = _child(element, 'Item');
    final category = item == null
        ? null
        : _child(item, 'ClassifiedTaxCategory');
    lines.add(
      InvoiceLine(
        id: _text(element, 'ID') ?? '',
        quantity: Decimal.tryParse(quantity?.innerText ?? '') ?? Decimal.zero,
        unit: UnitCode(quantity?.getAttribute('unitCode') ?? ''),
        netAmount: _decimal(element, 'LineExtensionAmount') ?? Decimal.zero,
        item: _item(item),
        price: _price(_child(element, 'Price')),
        vatCategory: _category(_text(category, 'ID')),
        vatRate: category == null ? null : _decimal(category, 'Percent'),
        note: _text(element, 'Note'),
        objectIdentifier: _identifier(
          _child(element, 'DocumentReference'),
          'ID',
          'schemeID',
        ),
        buyerOrderLineReference: _text(element, 'OrderLineReference/LineID'),
        buyerAccountingReference: _text(element, 'AccountingCost'),
        period: _period(_child(element, 'InvoicePeriod')),
        allowancesAndCharges: [
          for (final entry in _children(element, 'AllowanceCharge'))
            LineAllowanceCharge(
              kind: _text(entry, 'ChargeIndicator') == 'true'
                  ? AllowanceOrCharge.charge
                  : AllowanceOrCharge.allowance,
              amount: _decimal(entry, 'Amount') ?? Decimal.zero,
              baseAmount: _decimal(entry, 'BaseAmount'),
              percentage: _decimal(entry, 'MultiplierFactorNumeric'),
              reason: _text(entry, 'AllowanceChargeReason'),
              reasonCode: _text(entry, 'AllowanceChargeReasonCode'),
            ),
        ],
      ),
    );
  }
  return lines;
}

Item _item(XmlElement? element) {
  if (element == null) return const Item(name: '');
  return Item(
    name: _text(element, 'Name') ?? '',
    description: _text(element, 'Description'),
    sellerIdentifier: _text(element, 'SellersItemIdentification/ID'),
    buyerIdentifier: _text(element, 'BuyersItemIdentification/ID'),
    standardIdentifier: _identifier(
      _child(element, 'StandardItemIdentification'),
      'ID',
      'schemeID',
    ),
    classificationIdentifiers: [
      for (final classification in _children(
        element,
        'CommodityClassification',
      ))
        ?_identifier(classification, 'ItemClassificationCode', 'listID'),
    ],
    originCountry: _text(element, 'OriginCountry/IdentificationCode'),
    attributes: [
      for (final property in _children(element, 'AdditionalItemProperty'))
        ItemAttribute(
          _text(property, 'Name') ?? '',
          _text(property, 'Value') ?? '',
        ),
    ],
  );
}

Price _price(XmlElement? element) {
  if (element == null) return Price(netPrice: Decimal.zero);
  final quantity = _child(element, 'BaseQuantity');
  final unit = quantity?.getAttribute('unitCode');
  final discount = _child(element, 'AllowanceCharge');
  return Price(
    netPrice: _decimal(element, 'PriceAmount') ?? Decimal.zero,
    baseQuantity: quantity == null
        ? null
        : Decimal.tryParse(quantity.innerText),
    baseQuantityUnit: unit == null ? null : UnitCode(unit),
    discount: discount == null ? null : _decimal(discount, 'Amount'),
    grossPrice: discount == null ? null : _decimal(discount, 'BaseAmount'),
  );
}

/// The VAT category [code] names, standard rated when it names none.
///
/// A code the list does not hold cannot be represented, so it comes back as
/// standard rated and BR-CL-17 reports what the document actually said.
VatCategory _category(String? code) => code == null
    ? VatCategory.standardRate
    : VatCategory.tryParse(code) ?? VatCategory.standardRate;

// --- Reading one element ---------------------------------------------------

/// The first child at [path], read by local name so a document that declares
/// its namespaces differently is still read.
XmlElement? _child(XmlElement? element, String path) {
  XmlElement? current = element;
  for (final name in path.split('/')) {
    if (current == null) return null;
    current = current.childElements
        .where((child) => child.localName == name)
        .firstOrNull;
  }
  return current;
}

Iterable<XmlElement> _children(XmlElement element, String name) =>
    element.childElements.where((child) => child.localName == name);

String? _text(XmlElement? element, String path) {
  final found = _child(element, path);
  if (found == null) return null;
  final text = found.innerText.trim();
  return text.isEmpty ? null : text;
}

Decimal? _decimal(XmlElement? element, String path) {
  final text = _text(element, path);
  return text == null ? null : Decimal.tryParse(text);
}

CalendarDate? _date(XmlElement? element, String path) {
  final text = _text(element, path);
  return text == null ? null : CalendarDate.tryParse(text);
}

Identifier? _identifier(
  XmlElement? element,
  String path,
  String schemeAttribute,
) {
  final found = _child(element, path);
  if (found == null) return null;
  final value = found.innerText.trim();
  if (value.isEmpty) return null;
  return Identifier(value, scheme: found.getAttribute(schemeAttribute));
}

/// BT-90, which UBL writes as a party identification under the SEPA scheme.
///
/// It belongs to the seller, and to the payee when there is one. Both are
/// read, because a payee that collects the money is the party the mandate
/// names.
String? _creditorIdentifier(XmlElement root) {
  for (final path in const ['AccountingSupplierParty/Party', 'PayeeParty']) {
    final party = _child(root, path);
    if (party == null) continue;
    for (final identification in _children(party, 'PartyIdentification')) {
      if (_scheme(identification) != sepaScheme) continue;
      final value = _text(identification, 'ID');
      if (value != null && value.trim().isNotEmpty) return value;
    }
  }
  return null;
}

/// The scheme a party identification is issued under, or null when it gives
/// none.
String? _scheme(XmlElement identification) =>
    _child(identification, 'ID')?.getAttribute('schemeID');

/// A term whose whitespace is part of what it says.
///
/// Everything else is trimmed, because space around a value in XML is
/// formatting. BT-20 is the exception: Germany writes a discount for early
/// payment into that text and reads it back line by line, so the line break
/// that closes the last one has to survive being read.
String? _verbatim(XmlElement? element, String path) {
  final found = _child(element, path);
  if (found == null) return null;
  final text = found.innerText;
  return text.trim().isEmpty ? null : text;
}
