// Receipt & Print Settings - Cloud Synced
// Works across ALL platforms (Web, Mobile, Desktop, Tablet)
// Settings are stored per-store in Firestore
//
// Firestore path: stores/{storeId}/settings/receipt

import 'package:cloud_firestore/cloud_firestore.dart';

/// Paper size options
enum PaperSizeOption {
  thermal58mm,  // 58mm thermal receipt
  thermal80mm,  // 80mm thermal receipt
  a4,           // A4 standard paper
}

extension PaperSizeExtension on PaperSizeOption {
  String get label {
    switch (this) {
      case PaperSizeOption.thermal58mm: return '58mm';
      case PaperSizeOption.thermal80mm: return '80mm';
      case PaperSizeOption.a4: return 'A4';
    }
  }
  
  int get widthMm {
    switch (this) {
      case PaperSizeOption.thermal58mm: return 58;
      case PaperSizeOption.thermal80mm: return 80;
      case PaperSizeOption.a4: return 210;
    }
  }
  
  int get defaultCharWidth {
    switch (this) {
      case PaperSizeOption.thermal58mm: return 32;
      case PaperSizeOption.thermal80mm: return 48;
      case PaperSizeOption.a4: return 80;
    }
  }
}

/// Complete receipt/print settings for a store
class ReceiptSettings {
  // Paper & Format
  final PaperSizeOption paperSize;
  final int charWidth;       // Characters per line
  final int fontSize;        // Font size in points
  final double lineSpacing;  // Line spacing multiplier
  
  // Header Content
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;
  final String? storeEmail;
  final String? gstNumber;
  final String? headerLine1;
  final String? headerLine2;
  final bool showLogo;
  final String? logoUrl;
  
  // Footer Content  
  final String? footerLine1;
  final String? footerLine2;
  final String? footerLine3;
  final bool showThankYou;
  final String? thankYouMessage;
  
  // Receipt Options
  final bool showItemCode;      // Show SKU/barcode
  final bool showItemTax;       // Show tax per item
  final bool showDiscounts;     // Show discount breakdown
  final bool showPaymentDetails;
  final bool showCustomerInfo;
  final bool showDateTime;
  final bool showInvoiceNumber;
  final bool showCashierName;
  final bool printDuplicateCopy;
  
  // Currency
  final String currencySymbol;
  final String currencyCode;
  final int decimalPlaces;
  
  // Auto Print
  final bool autoPrintOnSale;     // Auto print when sale completes
  final int printCopies;          // Number of copies
  
  // Selected Printer (stored per-device but synced for reference)
  final String? selectedPrinterName;  // Name of selected printer
  final bool useDirectPrint;          // One-click print without dialog
  
  // Print Server URL (for network printing from any device)
  final String printServerUrl;        // e.g., http://192.168.1.100:5005
  
  final DateTime? updatedAt;

  const ReceiptSettings({
    this.paperSize = PaperSizeOption.thermal58mm,
    this.charWidth = 32,
    this.fontSize = 9,
    this.lineSpacing = 1.2,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.storeEmail,
    this.gstNumber,
    this.headerLine1,
    this.headerLine2,
    this.showLogo = false,
    this.logoUrl,
    this.footerLine1,
    this.footerLine2,
    this.footerLine3,
    this.showThankYou = true,
    this.thankYouMessage = 'Thank you for shopping with us!',
    this.showItemCode = false,
    this.showItemTax = false,
    this.showDiscounts = true,
    this.showPaymentDetails = true,
    this.showCustomerInfo = true,
    this.showDateTime = true,
    this.showInvoiceNumber = true,
    this.showCashierName = true,
    this.printDuplicateCopy = false,
    this.currencySymbol = '₹',
    this.currencyCode = 'INR',
    this.decimalPlaces = 2,
    this.autoPrintOnSale = false,
    this.printCopies = 1,
    this.selectedPrinterName,
    this.useDirectPrint = true,
    this.printServerUrl = 'http://localhost:5005',
    this.updatedAt,
  });

  factory ReceiptSettings.empty() => const ReceiptSettings();

  factory ReceiptSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ReceiptSettings(
      paperSize: _parsePaperSize(d['paperSize'] as String?),
      charWidth: d['charWidth'] as int? ?? 32,
      fontSize: d['fontSize'] as int? ?? 9,
      lineSpacing: (d['lineSpacing'] as num?)?.toDouble() ?? 1.2,
      storeName: d['storeName'] as String?,
      storeAddress: d['storeAddress'] as String?,
      storePhone: d['storePhone'] as String?,
      storeEmail: d['storeEmail'] as String?,
      gstNumber: d['gstNumber'] as String?,
      headerLine1: d['headerLine1'] as String?,
      headerLine2: d['headerLine2'] as String?,
      showLogo: d['showLogo'] == true,
      logoUrl: d['logoUrl'] as String?,
      footerLine1: d['footerLine1'] as String?,
      footerLine2: d['footerLine2'] as String?,
      footerLine3: d['footerLine3'] as String?,
      showThankYou: d['showThankYou'] != false,
      thankYouMessage: d['thankYouMessage'] as String? ?? 'Thank you for shopping with us!',
      showItemCode: d['showItemCode'] == true,
      showItemTax: d['showItemTax'] == true,
      showDiscounts: d['showDiscounts'] != false,
      showPaymentDetails: d['showPaymentDetails'] != false,
      showCustomerInfo: d['showCustomerInfo'] != false,
      showDateTime: d['showDateTime'] != false,
      showInvoiceNumber: d['showInvoiceNumber'] != false,
      showCashierName: d['showCashierName'] != false,
      printDuplicateCopy: d['printDuplicateCopy'] == true,
      currencySymbol: d['currencySymbol'] as String? ?? '₹',
      currencyCode: d['currencyCode'] as String? ?? 'INR',
      decimalPlaces: d['decimalPlaces'] as int? ?? 2,
      autoPrintOnSale: d['autoPrintOnSale'] == true,
      printCopies: d['printCopies'] as int? ?? 1,
      selectedPrinterName: d['selectedPrinterName'] as String?,
      useDirectPrint: d['useDirectPrint'] != false,
      printServerUrl: d['printServerUrl'] as String? ?? 'http://localhost:5005',
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  static PaperSizeOption _parsePaperSize(String? value) {
    switch (value) {
      case '80mm':
      case 'thermal80mm':
        return PaperSizeOption.thermal80mm;
      case 'A4':
      case 'a4':
        return PaperSizeOption.a4;
      default:
        return PaperSizeOption.thermal58mm;
    }
  }

  Map<String, dynamic> toMap() => {
    'paperSize': paperSize.label,
    'charWidth': charWidth,
    'fontSize': fontSize,
    'lineSpacing': lineSpacing,
    'storeName': storeName,
    'storeAddress': storeAddress,
    'storePhone': storePhone,
    'storeEmail': storeEmail,
    'gstNumber': gstNumber,
    'headerLine1': headerLine1,
    'headerLine2': headerLine2,
    'showLogo': showLogo,
    'logoUrl': logoUrl,
    'footerLine1': footerLine1,
    'footerLine2': footerLine2,
    'footerLine3': footerLine3,
    'showThankYou': showThankYou,
    'thankYouMessage': thankYouMessage,
    'showItemCode': showItemCode,
    'showItemTax': showItemTax,
    'showDiscounts': showDiscounts,
    'showPaymentDetails': showPaymentDetails,
    'showCustomerInfo': showCustomerInfo,
    'showDateTime': showDateTime,
    'showInvoiceNumber': showInvoiceNumber,
    'showCashierName': showCashierName,
    'printDuplicateCopy': printDuplicateCopy,
    'currencySymbol': currencySymbol,
    'currencyCode': currencyCode,
    'decimalPlaces': decimalPlaces,
    'autoPrintOnSale': autoPrintOnSale,
    'printCopies': printCopies,
    'selectedPrinterName': selectedPrinterName,
    'useDirectPrint': useDirectPrint,
    'printServerUrl': printServerUrl,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  ReceiptSettings copyWith({
    PaperSizeOption? paperSize,
    int? charWidth,
    int? fontSize,
    double? lineSpacing,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? storeEmail,
    String? gstNumber,
    String? headerLine1,
    String? headerLine2,
    bool? showLogo,
    String? logoUrl,
    String? footerLine1,
    String? footerLine2,
    String? footerLine3,
    bool? showThankYou,
    String? thankYouMessage,
    bool? showItemCode,
    bool? showItemTax,
    bool? showDiscounts,
    bool? showPaymentDetails,
    bool? showCustomerInfo,
    bool? showDateTime,
    bool? showInvoiceNumber,
    bool? showCashierName,
    bool? printDuplicateCopy,
    String? currencySymbol,
    String? currencyCode,
    int? decimalPlaces,
    bool? autoPrintOnSale,
    int? printCopies,
    String? selectedPrinterName,
    bool clearSelectedPrinter = false,  // Set to true to clear the printer
    bool? useDirectPrint,
    String? printServerUrl,
  }) {
    return ReceiptSettings(
      paperSize: paperSize ?? this.paperSize,
      charWidth: charWidth ?? this.charWidth,
      fontSize: fontSize ?? this.fontSize,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhone: storePhone ?? this.storePhone,
      storeEmail: storeEmail ?? this.storeEmail,
      gstNumber: gstNumber ?? this.gstNumber,
      headerLine1: headerLine1 ?? this.headerLine1,
      headerLine2: headerLine2 ?? this.headerLine2,
      showLogo: showLogo ?? this.showLogo,
      logoUrl: logoUrl ?? this.logoUrl,
      footerLine1: footerLine1 ?? this.footerLine1,
      footerLine2: footerLine2 ?? this.footerLine2,
      footerLine3: footerLine3 ?? this.footerLine3,
      showThankYou: showThankYou ?? this.showThankYou,
      thankYouMessage: thankYouMessage ?? this.thankYouMessage,
      showItemCode: showItemCode ?? this.showItemCode,
      showItemTax: showItemTax ?? this.showItemTax,
      showDiscounts: showDiscounts ?? this.showDiscounts,
      showPaymentDetails: showPaymentDetails ?? this.showPaymentDetails,
      showCustomerInfo: showCustomerInfo ?? this.showCustomerInfo,
      showDateTime: showDateTime ?? this.showDateTime,
      showInvoiceNumber: showInvoiceNumber ?? this.showInvoiceNumber,
      showCashierName: showCashierName ?? this.showCashierName,
      printDuplicateCopy: printDuplicateCopy ?? this.printDuplicateCopy,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      autoPrintOnSale: autoPrintOnSale ?? this.autoPrintOnSale,
      printCopies: printCopies ?? this.printCopies,
      selectedPrinterName: clearSelectedPrinter ? null : (selectedPrinterName ?? this.selectedPrinterName),
      useDirectPrint: useDirectPrint ?? this.useDirectPrint,
      printServerUrl: printServerUrl ?? this.printServerUrl,
      updatedAt: updatedAt,
    );
  }
}

/// Repository for receipt settings - synced to cloud
class ReceiptSettingsRepository {
  final FirebaseFirestore _db;
  final String storeId;

  ReceiptSettingsRepository({
    FirebaseFirestore? firestore,
    required this.storeId,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('stores').doc(storeId).collection('settings').doc('receipt');

  /// Fetch current settings
  Future<ReceiptSettings> fetch() async {
    try {
      final snap = await _doc.get();
      if (!snap.exists) return ReceiptSettings.empty();
      return ReceiptSettings.fromDoc(snap);
    } catch (e) {
      return ReceiptSettings.empty();
    }
  }

  /// Stream settings for real-time updates
  Stream<ReceiptSettings> stream() {
    return _doc.snapshots().map((snap) {
      if (!snap.exists) return ReceiptSettings.empty();
      return ReceiptSettings.fromDoc(snap);
    });
  }

  /// Save settings
  Future<void> save(ReceiptSettings settings) async {
    await _doc.set(settings.toMap(), SetOptions(merge: true));
  }

  /// Clear all settings
  Future<void> clear() async {
    await _doc.delete();
  }
}
