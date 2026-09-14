import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:xml/xml.dart';

/// The UBL 2.1 invoice namespace.
const String ublInvoice =
    'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2';

/// The UBL 2.1 credit note namespace.
const String ublCreditNote =
    'urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2';

/// What UBL marks the creditor identifier (BT-90) with.
///
/// The term has no element of its own here: it is written as a party
/// identification of the seller under this scheme, and read back from it.
const String sepaScheme = 'SEPA';

const String _cac =
    'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2';
const String _cbc =
    'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2';

/// The tax scheme identifier VAT is written under.
const String _vatScheme = 'VAT';

/// Writes [invoice] as a UBL 2.1 document.
///
/// The order of the elements is the one the UBL schema fixes, which is not the
/// order the standard lists the terms in. A receiver validates against that
/// schema before it looks at the business rules, so the order is part of being
/// readable at all.
///
/// A credit note goes out under the CreditNote root the syntax gives it,
/// rather than as an invoice carrying a credit note type code.
String writeUbl(Invoice invoice, {bool pretty = true}) {
  final creditNote = isCreditNote(invoice.typeCode);
  final root = creditNote ? 'CreditNote' : 'Invoice';
  final currency = invoice.currency;

  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    root,
    nest: () {
      builder.namespaceUri(null, creditNote ? ublCreditNote : ublInvoice);
      builder.namespaceUri('cac', _cac);
      builder.namespaceUri('cbc', _cbc);
      _header(builder, invoice, creditNote: creditNote);
      _references(builder, invoice);
      _parties(builder, invoice);
      _delivery(builder, invoice);
      _payment(builder, invoice, currency);
      _documentAllowancesAndCharges(builder, invoice, currency);
      _taxTotal(builder, invoice, currency);
      _monetaryTotal(builder, invoice.totals, currency);
      for (final line in invoice.lines) {
        _line(builder, line, currency, creditNote: creditNote);
      }
    },
  );

  final document = builder.buildDocument();
  return pretty
      ? document.toXmlString(
          pretty: true,
          indent: '  ',
          preserveWhitespace: _significantWhitespace,
        )
      : document.toXmlString();
}

/// Whether the space inside an element is part of what it says.
///
/// Printing an XML document for a human to read reflows the text inside it,
/// which is harmless everywhere but one place. Germany writes a discount for
/// early payment into the payment terms (BT-20) and reads it back line by
/// line, so reflowing that element turns a valid invoice into one that breaks
/// BR-DE-18.
bool _significantWhitespace(XmlNode node) =>
    node is XmlElement &&
    node.name.local == 'Note' &&
    node.parentElement?.name.local == 'PaymentTerms';

/// Whether [code] is one of the type codes UBL carries as a credit note.
bool isCreditNote(InvoiceTypeCode code) =>
    _creditNoteTypes.contains(code.value);

/// The type codes that go out under the CreditNote root.
const Set<String> _creditNoteTypes = {'381', '396', '532'};

// --- The head of the document ----------------------------------------------

void _header(XmlBuilder b, Invoice invoice, {required bool creditNote}) {
  _text(b, 'CustomizationID', invoice.specificationIdentifier);
  _text(b, 'ProfileID', invoice.businessProcess);
  _text(b, 'ID', invoice.number);
  _text(b, 'IssueDate', invoice.issueDate.toString());
  _text(b, 'DueDate', invoice.dueDate?.toString());
  _text(
    b,
    creditNote ? 'CreditNoteTypeCode' : 'InvoiceTypeCode',
    invoice.typeCode.value,
  );
  for (final note in invoice.notes) {
    // UBL carries the subject code and the text in one element, separated by
    // a hash, which is what BR-CL-08 reads.
    final text = note.subjectCode == null
        ? note.text
        : '#${note.subjectCode}#${note.text}';
    _text(b, 'Note', text);
  }
  _text(b, 'TaxPointDate', invoice.vatPointDate?.toString());
  _text(b, 'DocumentCurrencyCode', invoice.currency);
  _text(b, 'TaxCurrencyCode', invoice.vatAccountingCurrency);
  _text(b, 'AccountingCost', invoice.buyerAccountingReference);
  _text(b, 'BuyerReference', invoice.buyerReference);
}

void _references(XmlBuilder b, Invoice invoice) {
  final period = invoice.invoicingPeriod;
  if (period != null) {
    _group(b, 'InvoicePeriod', () {
      _text(b, 'StartDate', period.start?.toString());
      _text(b, 'EndDate', period.end?.toString());
    });
  }

  if (invoice.purchaseOrderReference != null ||
      invoice.salesOrderReference != null) {
    _group(b, 'OrderReference', () {
      _text(b, 'ID', invoice.purchaseOrderReference);
      _text(b, 'SalesOrderID', invoice.salesOrderReference);
    });
  }

  for (final preceding in invoice.precedingInvoices) {
    _group(b, 'BillingReference', () {
      _group(b, 'InvoiceDocumentReference', () {
        _text(b, 'ID', preceding.reference);
        _text(b, 'IssueDate', preceding.issueDate?.toString());
      });
    });
  }

  _reference(b, 'DespatchDocumentReference', invoice.despatchAdviceReference);
  _reference(b, 'ReceiptDocumentReference', invoice.receivingAdviceReference);
  _reference(b, 'OriginatorDocumentReference', invoice.tenderReference);
  _reference(b, 'ContractDocumentReference', invoice.contractReference);

  final object = invoice.objectIdentifier;
  if (object != null) {
    _group(b, 'AdditionalDocumentReference', () {
      _identifier(b, 'ID', object, schemeAttribute: 'schemeID');
      _text(b, 'DocumentTypeCode', '130');
    });
  }
  for (final document in invoice.supportingDocuments) {
    _group(b, 'AdditionalDocumentReference', () {
      _text(b, 'ID', document.reference);
      _text(b, 'DocumentDescription', document.description);
      final attachment = document.attachment;
      final uri = document.externalUri;
      if (attachment == null && uri == null) return;
      _group(b, 'Attachment', () {
        if (attachment != null) {
          b.element(
            'EmbeddedDocumentBinaryObject',
            namespaceUri: _cbc,
            attributes: {
              'mimeCode': attachment.mimeCode,
              'filename': attachment.filename,
            },
            nest: base64Encode(attachment.bytes),
          );
        }
        if (uri != null) {
          _group(b, 'ExternalReference', () {
            _text(b, 'URI', uri.toString());
          });
        }
      });
    });
  }

  _reference(b, 'ProjectReference', invoice.projectReference);
}

void _reference(XmlBuilder b, String name, String? value) {
  if (value == null) return;
  _group(b, name, () => _text(b, 'ID', value));
}

// --- Who is who ------------------------------------------------------------

void _parties(XmlBuilder b, Invoice invoice) {
  final seller = invoice.seller;
  _group(b, 'AccountingSupplierParty', () {
    _group(b, 'Party', () {
      _identifier(
        b,
        'EndpointID',
        seller.electronicAddress,
        schemeAttribute: 'schemeID',
      );
      for (final identifier in seller.identifiers) {
        _group(b, 'PartyIdentification', () {
          _identifier(b, 'ID', identifier, schemeAttribute: 'schemeID');
        });
      }
      // BT-90 has no element of its own in UBL. The creditor identifier is a
      // party identification of the seller, marked as issued under SEPA.
      final creditor =
          invoice.paymentInstructions?.directDebit?.creditorIdentifier;
      if (creditor != null) {
        _group(b, 'PartyIdentification', () {
          _identifier(
            b,
            'ID',
            Identifier(creditor, scheme: sepaScheme),
            schemeAttribute: 'schemeID',
          );
        });
      }
      if (seller.tradingName != null) {
        _group(b, 'PartyName', () => _text(b, 'Name', seller.tradingName));
      }
      _address(b, seller.address);
      if (seller.vatIdentifier != null) {
        _taxScheme(b, seller.vatIdentifier, _vatScheme);
      }
      if (seller.taxRegistrationIdentifier != null) {
        _taxScheme(b, seller.taxRegistrationIdentifier, 'TAX');
      }
      _group(b, 'PartyLegalEntity', () {
        _text(b, 'RegistrationName', seller.name);
        _identifier(
          b,
          'CompanyID',
          seller.legalRegistrationIdentifier,
          schemeAttribute: 'schemeID',
        );
        _text(b, 'CompanyLegalForm', seller.additionalLegalInformation);
      });
      _contact(b, seller.contact);
    });
  });

  final buyer = invoice.buyer;
  _group(b, 'AccountingCustomerParty', () {
    _group(b, 'Party', () {
      _identifier(
        b,
        'EndpointID',
        buyer.electronicAddress,
        schemeAttribute: 'schemeID',
      );
      if (buyer.identifier != null) {
        _group(b, 'PartyIdentification', () {
          _identifier(b, 'ID', buyer.identifier, schemeAttribute: 'schemeID');
        });
      }
      _group(b, 'PartyName', () => _text(b, 'Name', buyer.name));
      _address(b, buyer.address);
      if (buyer.vatIdentifier != null) {
        _taxScheme(b, buyer.vatIdentifier, _vatScheme);
      }
      _group(b, 'PartyLegalEntity', () {
        _text(b, 'RegistrationName', buyer.name);
        _identifier(
          b,
          'CompanyID',
          buyer.legalRegistrationIdentifier,
          schemeAttribute: 'schemeID',
        );
      });
      _contact(b, buyer.contact);
    });
  });

  final payee = invoice.payee;
  if (payee != null) {
    _group(b, 'PayeeParty', () {
      if (payee.identifier != null) {
        _group(b, 'PartyIdentification', () {
          _identifier(b, 'ID', payee.identifier, schemeAttribute: 'schemeID');
        });
      }
      _group(b, 'PartyName', () => _text(b, 'Name', payee.name));
      if (payee.legalRegistrationIdentifier != null) {
        _group(b, 'PartyLegalEntity', () {
          _identifier(
            b,
            'CompanyID',
            payee.legalRegistrationIdentifier,
            schemeAttribute: 'schemeID',
          );
        });
      }
    });
  }

  final representative = invoice.taxRepresentative;
  if (representative != null) {
    _group(b, 'TaxRepresentativeParty', () {
      _group(b, 'PartyName', () => _text(b, 'Name', representative.name));
      _address(b, representative.address);
      _taxScheme(b, representative.vatIdentifier, _vatScheme);
    });
  }
}

void _address(XmlBuilder b, Address address) {
  _group(b, 'PostalAddress', () {
    _text(b, 'StreetName', address.line1);
    _text(b, 'AdditionalStreetName', address.line2);
    _text(b, 'CityName', address.city);
    _text(b, 'PostalZone', address.postalCode);
    _text(b, 'CountrySubentity', address.countrySubdivision);
    if (address.line3 != null) {
      _group(b, 'AddressLine', () => _text(b, 'Line', address.line3));
    }
    _group(b, 'Country', () {
      _text(b, 'IdentificationCode', address.country);
    });
  });
}

void _taxScheme(XmlBuilder b, String? companyId, String scheme) {
  _group(b, 'PartyTaxScheme', () {
    _text(b, 'CompanyID', companyId);
    _group(b, 'TaxScheme', () => _text(b, 'ID', scheme));
  });
}

void _contact(XmlBuilder b, Contact? contact) {
  if (contact == null) return;
  _group(b, 'Contact', () {
    _text(b, 'Name', contact.name);
    _text(b, 'Telephone', contact.telephone);
    _text(b, 'ElectronicMail', contact.email);
  });
}

// --- Delivery and payment --------------------------------------------------

void _delivery(XmlBuilder b, Invoice invoice) {
  final delivery = invoice.delivery;
  if (delivery == null) return;
  _group(b, 'Delivery', () {
    _text(b, 'ActualDeliveryDate', delivery.date?.toString());
    final address = delivery.address;
    final location = delivery.locationIdentifier;
    if (address != null || location != null) {
      _group(b, 'DeliveryLocation', () {
        _identifier(b, 'ID', location, schemeAttribute: 'schemeID');
        if (address != null) {
          _group(b, 'Address', () {
            _text(b, 'StreetName', address.line1);
            _text(b, 'AdditionalStreetName', address.line2);
            _text(b, 'CityName', address.city);
            _text(b, 'PostalZone', address.postalCode);
            _text(b, 'CountrySubentity', address.countrySubdivision);
            if (address.line3 != null) {
              _group(b, 'AddressLine', () => _text(b, 'Line', address.line3));
            }
            _group(b, 'Country', () {
              _text(b, 'IdentificationCode', address.country);
            });
          });
        }
      });
    }
    if (delivery.name != null) {
      _group(b, 'DeliveryParty', () {
        _group(b, 'PartyName', () => _text(b, 'Name', delivery.name));
      });
    }
  });
}

void _payment(XmlBuilder b, Invoice invoice, String currency) {
  final instructions = invoice.paymentInstructions;
  if (instructions != null) {
    // UBL carries one account to a payment means, so an invoice offering
    // several accounts (BG-17 repeats) writes the group again rather than the
    // account again. The card and the mandate belong to the payment as a
    // whole and go with the first.
    final accounts = instructions.creditTransfers;
    if (accounts.isEmpty) {
      _paymentMeans(b, instructions, null, carryTheRest: true);
    } else {
      for (final (index, account) in accounts.indexed) {
        _paymentMeans(b, instructions, account, carryTheRest: index == 0);
      }
    }
  }

  if (invoice.paymentTerms != null) {
    _group(b, 'PaymentTerms', () => _text(b, 'Note', invoice.paymentTerms));
  }
}

void _documentAllowancesAndCharges(
  XmlBuilder b,
  Invoice invoice,
  String currency,
) {
  for (final entry in invoice.allowancesAndCharges) {
    _group(b, 'AllowanceCharge', () {
      _text(b, 'ChargeIndicator', '${entry.kind == AllowanceOrCharge.charge}');
      _text(b, 'AllowanceChargeReasonCode', entry.reasonCode);
      _text(b, 'AllowanceChargeReason', entry.reason);
      if (entry.percentage != null) {
        _text(b, 'MultiplierFactorNumeric', entry.percentage.toString());
      }
      _amount(b, 'Amount', entry.amount, currency);
      _amount(b, 'BaseAmount', entry.baseAmount, currency);
      _group(b, 'TaxCategory', () {
        _text(b, 'ID', entry.vatCategory.code);
        if (entry.vatRate != null) {
          _text(b, 'Percent', entry.vatRate.toString());
        }
        _group(b, 'TaxScheme', () => _text(b, 'ID', _vatScheme));
      });
    });
  }
}

// --- The figures -----------------------------------------------------------

void _taxTotal(XmlBuilder b, Invoice invoice, String currency) {
  _group(b, 'TaxTotal', () {
    _amount(b, 'TaxAmount', invoice.totals.totalVat ?? Decimal.zero, currency);
    for (final entry in invoice.vatBreakdown) {
      _group(b, 'TaxSubtotal', () {
        _amount(b, 'TaxableAmount', entry.taxableAmount, currency);
        _amount(b, 'TaxAmount', entry.taxAmount, currency);
        _group(b, 'TaxCategory', () {
          _text(b, 'ID', entry.category.code);
          if (entry.rate != null) {
            _text(b, 'Percent', entry.rate.toString());
          }
          _text(b, 'TaxExemptionReasonCode', entry.exemptionReasonCode);
          _text(b, 'TaxExemptionReason', entry.exemptionReason);
          _group(b, 'TaxScheme', () => _text(b, 'ID', _vatScheme));
        });
      });
    }
  });

  // BT-111 is the same VAT in the accounting currency, and UBL carries it as
  // a second TaxTotal holding nothing else. When that currency is the one the
  // invoice is written in, the TaxTotal above already carries it and a second
  // one would only repeat it.
  final inAccounting = invoice.totals.totalVatInAccountingCurrency;
  final accountingCurrency = invoice.vatAccountingCurrency;
  if (inAccounting != null &&
      accountingCurrency != null &&
      accountingCurrency != currency) {
    _group(b, 'TaxTotal', () {
      _amount(b, 'TaxAmount', inAccounting, accountingCurrency);
    });
  }
}

void _monetaryTotal(XmlBuilder b, InvoiceTotals totals, String currency) {
  _group(b, 'LegalMonetaryTotal', () {
    _amount(b, 'LineExtensionAmount', totals.sumOfLineNetAmounts, currency);
    _amount(b, 'TaxExclusiveAmount', totals.totalWithoutVat, currency);
    _amount(b, 'TaxInclusiveAmount', totals.totalWithVat, currency);
    _amount(b, 'AllowanceTotalAmount', totals.sumOfAllowances, currency);
    _amount(b, 'ChargeTotalAmount', totals.sumOfCharges, currency);
    _amount(b, 'PrepaidAmount', totals.paidAmount, currency);
    _amount(b, 'PayableRoundingAmount', totals.roundingAmount, currency);
    _amount(b, 'PayableAmount', totals.amountDueForPayment, currency);
  });
}

void _line(
  XmlBuilder b,
  InvoiceLine line,
  String currency, {
  required bool creditNote,
}) {
  _group(b, creditNote ? 'CreditNoteLine' : 'InvoiceLine', () {
    _text(b, 'ID', line.id);
    _text(b, 'Note', line.note);
    b.element(
      creditNote ? 'CreditedQuantity' : 'InvoicedQuantity',
      namespaceUri: _cbc,
      attributes: {'unitCode': line.unit.value},
      nest: line.quantity.toString(),
    );
    _amount(b, 'LineExtensionAmount', line.netAmount, currency);
    _text(b, 'AccountingCost', line.buyerAccountingReference);
    final period = line.period;
    if (period != null) {
      _group(b, 'InvoicePeriod', () {
        _text(b, 'StartDate', period.start?.toString());
        _text(b, 'EndDate', period.end?.toString());
      });
    }
    if (line.buyerOrderLineReference != null) {
      _group(b, 'OrderLineReference', () {
        _text(b, 'LineID', line.buyerOrderLineReference);
      });
    }
    if (line.objectIdentifier != null) {
      _group(b, 'DocumentReference', () {
        _identifier(
          b,
          'ID',
          line.objectIdentifier,
          schemeAttribute: 'schemeID',
        );
        _text(b, 'DocumentTypeCode', '130');
      });
    }
    for (final entry in line.allowancesAndCharges) {
      _group(b, 'AllowanceCharge', () {
        _text(
          b,
          'ChargeIndicator',
          '${entry.kind == AllowanceOrCharge.charge}',
        );
        _text(b, 'AllowanceChargeReasonCode', entry.reasonCode);
        _text(b, 'AllowanceChargeReason', entry.reason);
        if (entry.percentage != null) {
          _text(b, 'MultiplierFactorNumeric', entry.percentage.toString());
        }
        _amount(b, 'Amount', entry.amount, currency);
        _amount(b, 'BaseAmount', entry.baseAmount, currency);
      });
    }
    _item(b, line);
    _price(b, line, currency);
  });
}

void _item(XmlBuilder b, InvoiceLine line) {
  final item = line.item;
  _group(b, 'Item', () {
    _text(b, 'Description', item.description);
    _text(b, 'Name', item.name);
    if (item.buyerIdentifier != null) {
      _group(b, 'BuyersItemIdentification', () {
        _text(b, 'ID', item.buyerIdentifier);
      });
    }
    if (item.sellerIdentifier != null) {
      _group(b, 'SellersItemIdentification', () {
        _text(b, 'ID', item.sellerIdentifier);
      });
    }
    if (item.standardIdentifier != null) {
      _group(b, 'StandardItemIdentification', () {
        _identifier(
          b,
          'ID',
          item.standardIdentifier,
          schemeAttribute: 'schemeID',
        );
      });
    }
    if (item.originCountry != null) {
      _group(b, 'OriginCountry', () {
        _text(b, 'IdentificationCode', item.originCountry);
      });
    }
    for (final classification in item.classificationIdentifiers) {
      _group(b, 'CommodityClassification', () {
        _identifier(
          b,
          'ItemClassificationCode',
          classification,
          schemeAttribute: 'listID',
        );
      });
    }
    _group(b, 'ClassifiedTaxCategory', () {
      _text(b, 'ID', line.vatCategory.code);
      if (line.vatRate != null) {
        _text(b, 'Percent', line.vatRate.toString());
      }
      _group(b, 'TaxScheme', () => _text(b, 'ID', _vatScheme));
    });
    for (final attribute in item.attributes) {
      _group(b, 'AdditionalItemProperty', () {
        _text(b, 'Name', attribute.name);
        _text(b, 'Value', attribute.value);
      });
    }
  });
}

void _price(XmlBuilder b, InvoiceLine line, String currency) {
  final price = line.price;
  _group(b, 'Price', () {
    _amount(b, 'PriceAmount', price.netPrice, currency, exactScale: true);
    if (price.baseQuantity != null) {
      b.element(
        'BaseQuantity',
        namespaceUri: _cbc,
        attributes: {
          if (price.baseQuantityUnit != null)
            'unitCode': price.baseQuantityUnit!.value,
        },
        nest: price.baseQuantity.toString(),
      );
    }
    if (price.discount != null || price.grossPrice != null) {
      _group(b, 'AllowanceCharge', () {
        _text(b, 'ChargeIndicator', 'false');
        _amount(b, 'Amount', price.discount, currency, exactScale: true);
        _amount(b, 'BaseAmount', price.grossPrice, currency, exactScale: true);
      });
    }
  });
}

// --- Writing one element ---------------------------------------------------

void _group(XmlBuilder b, String name, void Function() nest) {
  b.element(name, namespaceUri: _cac, nest: nest);
}

void _text(XmlBuilder b, String name, String? value) {
  if (value == null) return;
  b.element(name, namespaceUri: _cbc, nest: value);
}

void _identifier(
  XmlBuilder b,
  String name,
  Identifier? identifier, {
  required String schemeAttribute,
}) {
  if (identifier == null) return;
  b.element(
    name,
    namespaceUri: _cbc,
    attributes: {
      if (identifier.scheme != null) schemeAttribute: identifier.scheme!,
    },
    nest: identifier.value,
  );
}

/// Writes a monetary amount with the currency it is in.
///
/// An amount goes out with two decimals, which is what the rules on decimals
/// ask for. A unit price is the exception: it may carry more, and rounding it
/// would change what is being sold.
void _amount(
  XmlBuilder b,
  String name,
  Decimal? value,
  String currency, {
  bool exactScale = false,
}) {
  if (value == null) return;
  b.element(
    name,
    namespaceUri: _cbc,
    attributes: {'currencyID': currency},
    nest: exactScale ? value.toString() : value.toStringAsFixed(2),
  );
}

/// One payment means: how the invoice is paid, and one account it is paid to.
///
/// The means code and the remittance reference are repeated in every group,
/// which is what the published examples do and what lets a reader take them
/// from whichever group it meets first. [carryTheRest] marks the group that
/// also carries the card and the mandate, so neither is written twice.
void _paymentMeans(
  XmlBuilder b,
  PaymentInstructions instructions,
  CreditTransferAccount? account, {
  required bool carryTheRest,
}) {
  _group(b, 'PaymentMeans', () {
    b.element(
      'PaymentMeansCode',
      namespaceUri: _cbc,
      attributes: {
        if (instructions.meansText != null) 'name': instructions.meansText!,
      },
      nest: instructions.means.value,
    );
    _text(b, 'PaymentID', instructions.remittanceInformation);
    final card = instructions.card;
    if (carryTheRest && card != null) {
      _group(b, 'CardAccount', () {
        _text(b, 'PrimaryAccountNumberID', card.primaryAccountNumber);
        _text(b, 'NetworkID', 'NA');
        _text(b, 'HolderName', card.holderName);
      });
    }
    if (account != null) {
      _group(b, 'PayeeFinancialAccount', () {
        _text(b, 'ID', account.identifier);
        _text(b, 'Name', account.name);
        if (account.providerBic != null) {
          _group(b, 'FinancialInstitutionBranch', () {
            _text(b, 'ID', account.providerBic);
          });
        }
      });
    }
    final debit = instructions.directDebit;
    if (carryTheRest && debit != null) {
      _group(b, 'PaymentMandate', () {
        _text(b, 'ID', debit.mandateReference);
        if (debit.debitedAccountIdentifier != null) {
          _group(b, 'PayerFinancialAccount', () {
            _text(b, 'ID', debit.debitedAccountIdentifier);
          });
        }
      });
    }
  });
}
