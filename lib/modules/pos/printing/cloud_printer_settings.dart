// Cloud Printer Settings Model & Repository
// Stores printer configuration per store in Firestore
//
// Firestore path: stores/{storeId}/settings/printer
// Fields:
//   enabled: whether PrintNode cloud printing is enabled
//   printNodeApiKey: PrintNode API key
//   printNodePrinterId: selected PrintNode printer ID
//   printNodePrinterName: human readable printer name
//   useLocalBackend: whether to use local backend (free option)
//   localBackendUrl: URL of local printer backend
//   updatedAt: timestamp

import 'package:cloud_firestore/cloud_firestore.dart';

/// Printer configuration for a store
class CloudPrinterSettings {
  final bool enabled;  // PrintNode enabled
  final String? printNodeApiKey;
  final int? printNodePrinterId;
  final String? printNodePrinterName;
  final bool useLocalBackend;  // Use local backend instead of PrintNode
  final String? localBackendUrl;  // e.g., http://localhost:5005
  final DateTime? updatedAt;

  const CloudPrinterSettings({
    this.enabled = false,
    this.printNodeApiKey,
    this.printNodePrinterId,
    this.printNodePrinterName,
    this.useLocalBackend = true,  // Default to local (free)
    this.localBackendUrl,
    this.updatedAt,
  });

  /// Create default/empty settings
  factory CloudPrinterSettings.empty() => const CloudPrinterSettings();

  /// Create from Firestore document
  factory CloudPrinterSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CloudPrinterSettings(
      enabled: d['enabled'] == true,
      printNodeApiKey: d['printNodeApiKey'] as String?,
      printNodePrinterId: d['printNodePrinterId'] as int?,
      printNodePrinterName: d['printNodePrinterName'] as String?,
      useLocalBackend: d['useLocalBackend'] != false,  // Default true
      localBackendUrl: d['localBackendUrl'] as String?,
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'useLocalBackend': useLocalBackend,
        if (printNodeApiKey != null) 'printNodeApiKey': printNodeApiKey,
        if (printNodePrinterId != null) 'printNodePrinterId': printNodePrinterId,
        if (printNodePrinterName != null) 'printNodePrinterName': printNodePrinterName,
        if (localBackendUrl != null) 'localBackendUrl': localBackendUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Check if PrintNode is configured
  bool get isConfigured =>
      enabled &&
      printNodeApiKey != null &&
      printNodeApiKey!.isNotEmpty &&
      printNodePrinterId != null;
  
  /// Check if local backend is configured
  bool get isLocalConfigured => useLocalBackend;

  /// Create a copy with modifications
  CloudPrinterSettings copyWith({
    bool? enabled,
    String? printNodeApiKey,
    int? printNodePrinterId,
    String? printNodePrinterName,
    bool? useLocalBackend,
    String? localBackendUrl,
  }) {
    return CloudPrinterSettings(
      enabled: enabled ?? this.enabled,
      printNodeApiKey: printNodeApiKey ?? this.printNodeApiKey,
      printNodePrinterId: printNodePrinterId ?? this.printNodePrinterId,
      printNodePrinterName: printNodePrinterName ?? this.printNodePrinterName,
      useLocalBackend: useLocalBackend ?? this.useLocalBackend,
      localBackendUrl: localBackendUrl ?? this.localBackendUrl,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'CloudPrinterSettings(enabled: $enabled, printer: $printNodePrinterName)';
}

/// Repository for cloud printer settings
class CloudPrinterSettingsRepository {
  final FirebaseFirestore _db;
  final String storeId;

  CloudPrinterSettingsRepository({
    FirebaseFirestore? firestore,
    required this.storeId,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  /// Document reference
  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('stores').doc(storeId).collection('settings').doc('printer');

  /// Fetch current settings
  Future<CloudPrinterSettings> fetch() async {
    try {
      final snap = await _doc.get();
      if (!snap.exists) return CloudPrinterSettings.empty();
      return CloudPrinterSettings.fromDoc(snap);
    } catch (e) {
      return CloudPrinterSettings.empty();
    }
  }

  /// Stream settings for real-time updates
  Stream<CloudPrinterSettings> stream() {
    return _doc.snapshots().map((snap) {
      if (!snap.exists) return CloudPrinterSettings.empty();
      return CloudPrinterSettings.fromDoc(snap);
    });
  }

  /// Save settings
  Future<void> save(CloudPrinterSettings settings) async {
    await _doc.set(settings.toMap(), SetOptions(merge: true));
  }

  /// Update specific fields
  Future<void> update({
    bool? enabled,
    String? printNodeApiKey,
    int? printNodePrinterId,
    String? printNodePrinterName,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (enabled != null) updates['enabled'] = enabled;
    if (printNodeApiKey != null) updates['printNodeApiKey'] = printNodeApiKey;
    if (printNodePrinterId != null) updates['printNodePrinterId'] = printNodePrinterId;
    if (printNodePrinterName != null) updates['printNodePrinterName'] = printNodePrinterName;
    
    await _doc.set(updates, SetOptions(merge: true));
  }

  /// Clear all settings
  Future<void> clear() async {
    await _doc.delete();
  }
}
