// Modern Receipt Settings Screen
// Cloud-synced settings that work across ALL platforms
// Settings are stored in Firebase and sync automatically
// Uses local printer backend for one-click printing on ANY platform

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Web-specific imports (conditionally used)
import 'web_url_launcher_stub.dart'
  if (dart.library.html) 'web_url_launcher.dart';

import '../../../core/theme/theme_extension_helpers.dart';
import '../../stores/providers.dart';
import 'print_service.dart';
import 'receipt_settings.dart';

/// Provider for Print Helper download URL from Firebase Storage
final printHelperDownloadUrlProvider = FutureProvider<String?>((ref) async {
  try {
    final storageRef = FirebaseStorage.instance.ref('downloads/print-helper/RetailPOS-PrintHelper-Setup.exe');
    return await storageRef.getDownloadURL();
  } catch (e) {
    debugPrint('Print Helper not found in Firebase Storage: $e');
    return null;
  }
});

/// Provider for Print Helper metadata (version, size, upload date)
final printHelperMetadataProvider = FutureProvider<FullMetadata?>((ref) async {
  try {
    final storageRef = FirebaseStorage.instance.ref('downloads/print-helper/RetailPOS-PrintHelper-Setup.exe');
    return await storageRef.getMetadata();
  } catch (e) {
    return null;
  }
});

/// Provider to check if printer backend is available
final printerBackendAvailableProvider = FutureProvider<bool>((ref) async {
  return await PrintService.isBackendAvailable();
});

/// Provider to fetch printers from local backend (works on ALL platforms!)
final backendPrintersProvider = FutureProvider<List<PrinterInfo>>((ref) async {
  debugPrint('🖨️ [Provider] Fetching printers from: ${PrintService.backendUrl}');
  try {
    final isAvailable = await PrintService.isBackendAvailable();
    debugPrint('🖨️ [Provider] Backend available: $isAvailable');
    if (!isAvailable) {
      debugPrint('🔴 [Provider] Printer backend not running at ${PrintService.backendUrl}');
      return [];
    }
    final printers = await PrintService.getPrinters();
    debugPrint('🖨️ [Provider] Got ${printers.length} printers: ${printers.map((p) => p.name).join(", ")}');
    return printers;
  } catch (e, st) {
    debugPrint('❌ [Provider] Error fetching printers: $e');
    debugPrint('Stack: $st');
    return [];
  }
});

/// Provider to get default printer from backend
final defaultPrinterProvider = FutureProvider<String?>((ref) async {
  return await PrintService.getDefaultPrinter();
});

/// Provider for receipt settings stream
final receiptSettingsProvider = StreamProvider.family<ReceiptSettings, String>((ref, storeId) {
  return ReceiptSettingsRepository(storeId: storeId).stream();
});

class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  ConsumerState<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends ConsumerState<ReceiptSettingsScreen> {
  ReceiptSettings _settings = ReceiptSettings.empty();
  bool _loading = true;
  bool _saving = false;
  String? _message;
  bool _isError = false;
  
  // Printer state
  bool _testPrinting = false;
  bool _refreshingPrinters = false;
  
  // Controllers
  late TextEditingController _storeNameCtrl;
  late TextEditingController _storeAddressCtrl;
  late TextEditingController _storePhoneCtrl;
  late TextEditingController _storeEmailCtrl;
  late TextEditingController _gstNumberCtrl;
  late TextEditingController _headerLine1Ctrl;
  late TextEditingController _headerLine2Ctrl;
  late TextEditingController _footerLine1Ctrl;
  late TextEditingController _footerLine2Ctrl;
  late TextEditingController _footerLine3Ctrl;
  late TextEditingController _thankYouCtrl;
  late TextEditingController _currencySymbolCtrl;
  late TextEditingController _serverUrlCtrl;
  
  ReceiptSettingsRepository? _repo;

  @override
  void initState() {
    super.initState();
    _storeNameCtrl = TextEditingController();
    _storeAddressCtrl = TextEditingController();
    _storePhoneCtrl = TextEditingController();
    _storeEmailCtrl = TextEditingController();
    _gstNumberCtrl = TextEditingController();
    _headerLine1Ctrl = TextEditingController();
    _headerLine2Ctrl = TextEditingController();
    _footerLine1Ctrl = TextEditingController();
    _footerLine2Ctrl = TextEditingController();
    _footerLine3Ctrl = TextEditingController();
    _thankYouCtrl = TextEditingController();
    _currencySymbolCtrl = TextEditingController();
    _serverUrlCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeAddressCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storeEmailCtrl.dispose();
    _gstNumberCtrl.dispose();
    _headerLine1Ctrl.dispose();
    _headerLine2Ctrl.dispose();
    _footerLine1Ctrl.dispose();
    _footerLine2Ctrl.dispose();
    _footerLine3Ctrl.dispose();
    _thankYouCtrl.dispose();
    _currencySymbolCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  void _loadSettings(ReceiptSettings settings) {
    _settings = settings;
    _storeNameCtrl.text = settings.storeName ?? '';
    _storeAddressCtrl.text = settings.storeAddress ?? '';
    _storePhoneCtrl.text = settings.storePhone ?? '';
    _storeEmailCtrl.text = settings.storeEmail ?? '';
    _gstNumberCtrl.text = settings.gstNumber ?? '';
    _headerLine1Ctrl.text = settings.headerLine1 ?? '';
    _headerLine2Ctrl.text = settings.headerLine2 ?? '';
    _footerLine1Ctrl.text = settings.footerLine1 ?? '';
    _footerLine2Ctrl.text = settings.footerLine2 ?? '';
    _footerLine3Ctrl.text = settings.footerLine3 ?? '';
    _thankYouCtrl.text = settings.thankYouMessage ?? 'Thank you for shopping with us!';
    _currencySymbolCtrl.text = settings.currencySymbol;
    _serverUrlCtrl.text = settings.printServerUrl;
    // Update the PrintService with the saved URL
    PrintService.setBackendUrl(settings.printServerUrl);
    _loading = false;
    
    // Refresh printer list now that URL is set
    ref.invalidate(backendPrintersProvider);
    ref.invalidate(printerBackendAvailableProvider);
  }

  Future<void> _saveSettings() async {
    if (_repo == null) return;
    
    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final newSettings = _settings.copyWith(
        storeName: _storeNameCtrl.text.trim().isEmpty ? null : _storeNameCtrl.text.trim(),
        storeAddress: _storeAddressCtrl.text.trim().isEmpty ? null : _storeAddressCtrl.text.trim(),
        storePhone: _storePhoneCtrl.text.trim().isEmpty ? null : _storePhoneCtrl.text.trim(),
        storeEmail: _storeEmailCtrl.text.trim().isEmpty ? null : _storeEmailCtrl.text.trim(),
        gstNumber: _gstNumberCtrl.text.trim().isEmpty ? null : _gstNumberCtrl.text.trim(),
        headerLine1: _headerLine1Ctrl.text.trim().isEmpty ? null : _headerLine1Ctrl.text.trim(),
        headerLine2: _headerLine2Ctrl.text.trim().isEmpty ? null : _headerLine2Ctrl.text.trim(),
        footerLine1: _footerLine1Ctrl.text.trim().isEmpty ? null : _footerLine1Ctrl.text.trim(),
        footerLine2: _footerLine2Ctrl.text.trim().isEmpty ? null : _footerLine2Ctrl.text.trim(),
        footerLine3: _footerLine3Ctrl.text.trim().isEmpty ? null : _footerLine3Ctrl.text.trim(),
        thankYouMessage: _thankYouCtrl.text.trim().isEmpty ? null : _thankYouCtrl.text.trim(),
        currencySymbol: _currencySymbolCtrl.text.trim().isEmpty ? '₹' : _currencySymbolCtrl.text.trim(),
        printServerUrl: _serverUrlCtrl.text.trim().isEmpty ? 'http://localhost:5005' : _serverUrlCtrl.text.trim(),
      );

      await _repo!.save(newSettings);
      
      // Update PrintService with new URL
      PrintService.setBackendUrl(newSettings.printServerUrl);
      
      setState(() {
        _settings = newSettings;
        _saving = false;
        _message = '✓ Settings saved and synced to cloud!';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _message = 'Failed to save: $e';
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeId = ref.watch(selectedStoreIdProvider);
    final cs = Theme.of(context).colorScheme;
    
    if (storeId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print Settings')),
        body: const Center(child: Text('Please select a store first')),
      );
    }

    // Initialize repo
    _repo ??= ReceiptSettingsRepository(storeId: storeId);

    // Listen to settings stream
    final settingsAsync = ref.watch(receiptSettingsProvider(storeId));
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Print Settings'),
        centerTitle: false,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            FilledButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          // Load settings once
          if (_loading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() => _loadSettings(settings));
            });
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status message
                if (_message != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isError ? cs.errorContainer : context.appColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isError ? cs.error.withOpacity(0.3) : context.appColors.success.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isError ? Icons.error : Icons.check_circle,
                          color: _isError ? cs.error : context.appColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _isError ? cs.onErrorContainer : context.appColors.success,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _message = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // ════════════════════════════════════════════════════════════
                // SECTION 1: CONNECTED PRINTERS (Most Important - At Top)
                // ════════════════════════════════════════════════════════════
                _buildConnectedPrintersSection(context),
                
                const SizedBox(height: 24),
                
                // ════════════════════════════════════════════════════════════
                // SECTION 2: STORE INFORMATION
                // ════════════════════════════════════════════════════════════
                _buildStoreInfoSection(context),
                
                const SizedBox(height: 24),
                
                // ════════════════════════════════════════════════════════════
                // SECTION 3: RECEIPT LAYOUT OPTIONS
                // ════════════════════════════════════════════════════════════
                _buildReceiptLayoutSection(context),
                
                const SizedBox(height: 24),
                
                // ════════════════════════════════════════════════════════════
                // SECTION 4: PRINT OPTIONS
                // ════════════════════════════════════════════════════════════
                _buildPrintOptionsSection(context),
                
                const SizedBox(height: 24),
                
                // ════════════════════════════════════════════════════════════
                // SECTION 5: RECEIPT PREVIEW
                // ════════════════════════════════════════════════════════════
                _buildSectionHeader(context, 'Receipt Preview', Icons.preview),
                Card(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildReceiptPreview(context),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload),
                    label: Text(_saving ? 'Saving...' : 'Save All Settings'),
                    style: FilledButton.styleFrom(
                      textStyle: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // ════════════════════════════════════════════════════════════
                // SECTION: TEST PRINT (DEBUGGING)
                // ════════════════════════════════════════════════════════════
                _buildTestPrintSection(context),
                
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION: CONNECTED PRINTERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildConnectedPrintersSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final backendAvailableAsync = ref.watch(printerBackendAvailableProvider);
    final printersAsync = ref.watch(backendPrintersProvider);
    final backendAvailable = backendAvailableAsync.valueOrNull ?? false;
    final currentPrinter = _settings.selectedPrinterName;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with status badge
        Row(
          children: [
            Icon(Icons.print, size: 24, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Connected Printers',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
            const Spacer(),
            // Connection status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: backendAvailable ? context.appColors.success.withOpacity(0.15) : context.appColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    backendAvailable ? Icons.wifi : Icons.wifi_off,
                    size: 14,
                    color: backendAvailable ? context.appColors.success : context.appColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    backendAvailable ? 'Print Helper Running' : 'Print Helper Not Running',
                    style: TextStyle(
                      fontSize: context.sizes.fontSm,
                      fontWeight: FontWeight.w600,
                      color: backendAvailable ? context.appColors.success : context.appColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Main card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              // Status banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: backendAvailable ? context.appColors.success.withOpacity(0.1) : context.appColors.warning.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: backendAvailable ? context.appColors.success.withOpacity(0.2) : context.appColors.warning.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        backendAvailable ? Icons.check_circle : Icons.info_outline,
                        color: backendAvailable ? context.appColors.success : context.appColors.warning,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            backendAvailable 
                                ? 'Print Helper is connected' 
                                : 'Print Helper not detected',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: backendAvailable ? context.appColors.success : context.appColors.warning,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            backendAvailable 
                                ? 'Select a printer below to print receipts'
                                : 'Install Print Helper for one-click printing',
                            style: TextStyle(
                              fontSize: context.sizes.fontSm,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!backendAvailable)
                      FilledButton.tonal(
                        onPressed: () => _showPrintHelperDialog(context),
                        child: const Text('Setup'),
                      )
                    else
                      IconButton(
                        icon: _refreshingPrinters
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        onPressed: _refreshingPrinters ? null : _refreshPrinters,
                        tooltip: 'Refresh printers',
                      ),
                  ],
                ),
              ),
              
              // Printer list
              if (backendAvailable)
                printersAsync.when(
                  loading: () {
                    debugPrint('🖨️ [UI] Printers loading...');
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  error: (e, st) {
                    debugPrint('🖨️ [UI] Printers error: $e');
                    debugPrint('🖨️ [UI] Stack: $st');
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error loading printers: $e', style: TextStyle(color: cs.error)),
                    );
                  },
                  data: (printers) {
                    debugPrint('🖨️ [UI] Printers data received: ${printers.length} printers');
                    for (final p in printers) {
                      debugPrint('🖨️ [UI] - ${p.name} (default: ${p.isDefault})');
                    }
                    
                    if (printers.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.print_disabled, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'No printers found',
                              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Make sure your printer is connected and turned on',
                              style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7)),
                            ),
                            const SizedBox(height: 12),
                            if (kIsWeb)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.appColors.warning.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.appColors.warning.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.info_outline, size: 18, color: context.appColors.warning),
                                        const SizedBox(width: 8),
                                        Text(
                                          'HTTPS Limitation',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: context.appColors.warning),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'If you\'re accessing the app via HTTPS, browsers may block local printer connections. Try running the app locally with "flutter run -d chrome".',
                                      style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    
                    return Column(
                      children: [
                        const Divider(height: 1),
                        ...printers.map((printer) {
                          final isSelected = currentPrinter == printer.name;
                          return _buildPrinterTile(context, printer, isSelected);
                        }),
                      ],
                    );
                  },
                ),
              
              // Print Helper download card (if not available)
              if (!backendAvailable)
                _buildPrintHelperCard(context),
            ],
          ),
        ),
        
        // Test print button
        if (backendAvailable && currentPrinter != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testPrinting ? null : _testPrint,
              icon: _testPrinting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: Text(_testPrinting ? 'Printing...' : 'Print Test Receipt'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPrinterTile(BuildContext context, PrinterInfo printer, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: () {
        setState(() {
          _settings = _settings.copyWith(selectedPrinterName: printer.name);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer.withOpacity(0.3) : null,
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),
        ),
        child: Row(
          children: [
            // Printer icon with status
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected ? cs.primary.withOpacity(0.1) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.print,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                if (printer.isDefault)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: context.appColors.warning,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.star, size: 10, color: cs.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Printer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          printer.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? cs.primary : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (printer.isDefault)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.appColors.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Default',
                            style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: context.appColors.warning),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Selection indicator
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant, width: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintHelperCard(BuildContext context) {
    final downloadUrlAsync = ref.watch(printHelperDownloadUrlProvider);
    final metadataAsync = ref.watch(printHelperMetadataProvider);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.appColors.info.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.download_rounded, size: 32, color: context.appColors.info),
          ),
          const SizedBox(height: 16),
          
          // Title
          Text(
            'Install Print Helper',
            style: TextStyle(fontSize: context.sizes.fontXl, fontWeight: FontWeight.bold, color: context.colors.onSurface),
          ),
          const SizedBox(height: 8),
          
          // Description
          Text(
            'Download and install the Print Helper app to enable one-click receipt printing from your browser.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          
          // Show metadata if available
          metadataAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (metadata) {
              if (metadata == null) return const SizedBox.shrink();
              final sizeInMB = (metadata.size ?? 0) / (1024 * 1024);
              final updated = metadata.updated;
              return Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'v${metadata.customMetadata?['version'] ?? '1.0'} • ${sizeInMB.toStringAsFixed(1)} MB${updated != null ? ' • ${_formatDate(updated)}' : ''}',
                      style: TextStyle(fontSize: context.sizes.fontSm, color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Download button - from Firebase Storage
          downloadUrlAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (_, __) => Text(
              'Print Helper not available. Please contact support.',
              style: TextStyle(color: context.appColors.warning),
              textAlign: TextAlign.center,
            ),
            data: (url) {
              if (url == null) {
                return Text(
                  'Print Helper not available. Please contact support.',
                  style: TextStyle(color: context.appColors.warning),
                  textAlign: TextAlign.center,
                );
              }
              
              return FilledButton.icon(
                onPressed: () => _launchDownload(url),
                icon: const Icon(Icons.download),
                label: const Text('Download for Windows'),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          // Help link
          TextButton(
            onPressed: () => _showPrintHelperDialog(context),
            child: const Text('View setup instructions'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showPrintHelperDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline),
            SizedBox(width: 8),
            Text('Print Helper Setup'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Follow these steps to enable one-click printing:', style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.onSurface)),
              const SizedBox(height: 16),
              _buildSetupStep('1', 'Download the Print Helper installer'),
              _buildSetupStep('2', 'Run the installer (RetailPOS-PrintHelper-Setup.exe)'),
              _buildSetupStep('3', 'The Print Helper will start automatically'),
              _buildSetupStep('4', 'Your printers will appear in the list above'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: context.appColors.info, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The Print Helper runs in the system tray and starts automatically with Windows.',
                        style: TextStyle(fontSize: context.sizes.fontMd, color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          Consumer(
            builder: (context, ref, _) {
              final downloadUrlAsync = ref.watch(printHelperDownloadUrlProvider);
              return downloadUrlAsync.when(
                loading: () => const FilledButton(onPressed: null, child: Text('Loading...')),
                error: (_, __) => const FilledButton(onPressed: null, child: Text('Not Available')),
                data: (url) => FilledButton.icon(
                  onPressed: url != null ? () {
                    Navigator.pop(context);
                    _launchDownload(url);
                  } : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: context.appColors.info.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(fontWeight: FontWeight.bold, color: context.appColors.info),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION: STORE INFORMATION
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStoreInfoSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Store Information', Icons.store),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildTextField(
                  controller: _storeNameCtrl,
                  label: 'Store Name',
                  icon: Icons.storefront,
                  hint: 'Enter your store name',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _storeAddressCtrl,
                  label: 'Store Address',
                  icon: Icons.location_on,
                  hint: 'Enter your store address',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _storePhoneCtrl,
                        label: 'Phone',
                        icon: Icons.phone,
                        hint: 'Phone number',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _storeEmailCtrl,
                        label: 'Email',
                        icon: Icons.email,
                        hint: 'Email address',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _gstNumberCtrl,
                  label: 'GST Number',
                  icon: Icons.receipt_long,
                  hint: 'GST/Tax number (optional)',
                ),
                const Divider(height: 32),
                // Header lines
                _buildTextField(
                  controller: _headerLine1Ctrl,
                  label: 'Header Line 1',
                  icon: Icons.title,
                  hint: 'Additional header text',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _headerLine2Ctrl,
                  label: 'Header Line 2',
                  icon: Icons.title,
                  hint: 'Additional header text',
                ),
                const Divider(height: 32),
                // Footer lines
                _buildTextField(
                  controller: _footerLine1Ctrl,
                  label: 'Footer Line 1',
                  icon: Icons.notes,
                  hint: 'e.g., Return policy',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _footerLine2Ctrl,
                  label: 'Footer Line 2',
                  icon: Icons.notes,
                  hint: 'e.g., Website',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _footerLine3Ctrl,
                  label: 'Footer Line 3',
                  icon: Icons.notes,
                  hint: 'e.g., Social media',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _thankYouCtrl,
                  label: 'Thank You Message',
                  icon: Icons.favorite,
                  hint: 'Thank you message',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION: RECEIPT LAYOUT OPTIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildReceiptLayoutSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Receipt Layout', Icons.receipt_long),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Paper size
                Text('Paper Size', style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.onSurface)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildPaperSizeChip(context, PaperSizeOption.thermal58mm, '58mm', Icons.receipt),
                    _buildPaperSizeChip(context, PaperSizeOption.thermal80mm, '80mm', Icons.receipt_long),
                    _buildPaperSizeChip(context, PaperSizeOption.a4, 'A4', Icons.description),
                  ],
                ),
                
                const Divider(height: 32),
                
                // Font size
                Text('Font Size', style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.onSurface)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _settings.fontSize.toDouble(),
                        min: 8,
                        max: 16,
                        divisions: 8,
                        label: '${_settings.fontSize}pt',
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings.copyWith(fontSize: value.round());
                          });
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_settings.fontSize}pt',
                        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
                
                const Divider(height: 32),
                
                // Currency
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _currencySymbolCtrl,
                        label: 'Currency Symbol',
                        icon: Icons.currency_rupee,
                        hint: '₹',
                      ),
                    ),
                  ],
                ),
                
                const Divider(height: 32),
                
                // Toggle options
                Text('Receipt Fields', style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.onSurface)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildToggleChip('Show Date/Time', _settings.showDateTime, (v) {
                      setState(() => _settings = _settings.copyWith(showDateTime: v));
                    }),
                    _buildToggleChip('Show Invoice #', _settings.showInvoiceNumber, (v) {
                      setState(() => _settings = _settings.copyWith(showInvoiceNumber: v));
                    }),
                    _buildToggleChip('Show Cashier', _settings.showCashierName, (v) {
                      setState(() => _settings = _settings.copyWith(showCashierName: v));
                    }),
                    _buildToggleChip('Show Tax Details', _settings.showItemTax, (v) {
                      setState(() => _settings = _settings.copyWith(showItemTax: v));
                    }),
                    _buildToggleChip('Show Item Code', _settings.showItemCode, (v) {
                      setState(() => _settings = _settings.copyWith(showItemCode: v));
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaperSizeChip(BuildContext context, PaperSizeOption size, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _settings.paperSize == size;
    
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: isSelected ? cs.onPrimary : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _settings = _settings.copyWith(paperSize: size);
          });
        }
      },
    );
  }

  Widget _buildToggleChip(String label, bool value, Function(bool) onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      checkmarkColor: Colors.white,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION: TEST PRINT (DEBUGGING)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTestPrintSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final backendAvailableAsync = ref.watch(printerBackendAvailableProvider);
    final backendAvailable = backendAvailableAsync.valueOrNull ?? false;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Test Print', Icons.bug_report),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status info
                Row(
                  children: [
                    Icon(
                      backendAvailable ? Icons.check_circle : Icons.error,
                      color: backendAvailable ? context.appColors.success : cs.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      backendAvailable 
                          ? 'Print Helper is running on localhost:5005'
                          : 'Print Helper not detected',
                      style: TextStyle(
                        color: backendAvailable ? context.appColors.success : cs.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Direct API test buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testHealthEndpoint,
                      icon: const Icon(Icons.favorite, size: 18),
                      label: const Text('Test Health'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _testPrintersEndpoint,
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Test Printers API'),
                    ),
                    if (_settings.selectedPrinterName != null)
                      FilledButton.icon(
                        onPressed: _testPrinting ? null : _testPrint,
                        icon: _testPrinting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.print, size: 18),
                        label: Text(_testPrinting ? 'Printing...' : 'Print Test Page'),
                      ),
                  ],
                ),
                
                // Debug output
                if (_testOutput != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _testOutput!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: context.sizes.fontSm,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  String? _testOutput;
  
  Future<void> _testHealthEndpoint() async {
    setState(() => _testOutput = 'Testing health endpoint...');
    try {
      final response = await PrintService.isBackendAvailable();
      setState(() => _testOutput = 'Health check result: $response\nBackend URL: ${PrintService.backendUrl}');
    } catch (e) {
      setState(() => _testOutput = 'Health check error: $e');
    }
  }
  
  Future<void> _testPrintersEndpoint() async {
    setState(() => _testOutput = 'Fetching printers...');
    try {
      final printers = await PrintService.getPrinters();
      final output = StringBuffer();
      output.writeln('Found ${printers.length} printers:');
      for (final p in printers) {
        output.writeln('  - ${p.name} (default: ${p.isDefault})');
      }
      setState(() => _testOutput = output.toString());
      
      // Also refresh the provider
      ref.invalidate(backendPrintersProvider);
    } catch (e) {
      setState(() => _testOutput = 'Error fetching printers: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION: PRINT OPTIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPrintOptionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Print Options', Icons.settings),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Auto print
                SwitchListTile(
                  title: const Text('Auto Print'),
                  subtitle: const Text('Automatically print after each sale'),
                  value: _settings.autoPrintOnSale,
                  onChanged: (v) {
                    setState(() => _settings = _settings.copyWith(autoPrintOnSale: v));
                  },
                  secondary: const Icon(Icons.print),
                ),
                
                const Divider(),
                
                // Print duplicate
                SwitchListTile(
                  title: const Text('Print Duplicate Copy'),
                  subtitle: const Text('Print two copies of each receipt'),
                  value: _settings.printDuplicateCopy,
                  onChanged: (v) {
                    setState(() => _settings = _settings.copyWith(printDuplicateCopy: v));
                  },
                  secondary: const Icon(Icons.copy),
                ),
                
                const Divider(),
                
                // Number of copies
                ListTile(
                  leading: const Icon(Icons.content_copy),
                  title: const Text('Number of Copies'),
                  subtitle: Text('${_settings.printCopies} copies'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _settings.printCopies > 1
                            ? () {
                                setState(() {
                                  _settings = _settings.copyWith(
                                    printCopies: _settings.printCopies - 1,
                                  );
                                });
                              }
                            : null,
                      ),
                      Text(
                        '${_settings.printCopies}',
                        style: TextStyle(fontSize: context.sizes.fontXl, fontWeight: FontWeight.bold, color: context.colors.onSurface),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _settings.printCopies < 5
                            ? () {
                                setState(() {
                                  _settings = _settings.copyWith(
                                    printCopies: _settings.printCopies + 1,
                                  );
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: context.colors.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildReceiptPreview(BuildContext context) {
    final cs = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Store name
          Text(
            _storeNameCtrl.text.isNotEmpty ? _storeNameCtrl.text : 'Your Store Name',
            style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.bold, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          if (_storeAddressCtrl.text.isNotEmpty) ...[            const SizedBox(height: 4),
            Text(
              _storeAddressCtrl.text,
              style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (_storePhoneCtrl.text.isNotEmpty) ...[            const SizedBox(height: 2),
            Text(
              _storePhoneCtrl.text,
              style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant),
            ),
          ],
          if (_gstNumberCtrl.text.isNotEmpty) ...[            const SizedBox(height: 2),
            Text(
              'GST: ${_gstNumberCtrl.text}',
              style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant),
            ),
          ],
          
          const Divider(height: 16),
          
          // Receipt info
          if (_settings.showDateTime)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Date:', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
                  Text('${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      style: TextStyle(fontSize: context.sizes.fontXs)),
                ],
              ),
            ),
          if (_settings.showInvoiceNumber)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Receipt #:', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
                  Text('INV-001234', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurface)),
                ],
              ),
            ),
          
          const Divider(height: 16),
          
          // Items preview
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Sample Item', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface))),
              Text('${_currencySymbolCtrl.text.isNotEmpty ? _currencySymbolCtrl.text : "₹"}100.00',
                  style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Another Item', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface))),
              Text('${_currencySymbolCtrl.text.isNotEmpty ? _currencySymbolCtrl.text : "₹"}50.00',
                  style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface)),
            ],
          ),
          
          const Divider(height: 16),
          
          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.bold, color: cs.onSurface)),
              Text('${_currencySymbolCtrl.text.isNotEmpty ? _currencySymbolCtrl.text : "₹"}150.00',
                  style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.bold, color: cs.onSurface)),
            ],
          ),
          
          const Divider(height: 16),
          
          // Thank you message
          Text(
            _thankYouCtrl.text.isNotEmpty ? _thankYouCtrl.text : 'Thank you!',
            style: TextStyle(fontSize: context.sizes.fontXs, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ══════════════════════════════════════════════════════════════════════════
  void _launchDownload(String url) {
    if (kIsWeb) {
      launchUrlInNewTab(url);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  Future<void> _refreshPrinters() async {
    setState(() => _refreshingPrinters = true);
    ref.invalidate(backendPrintersProvider);
    ref.invalidate(printerBackendAvailableProvider);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _refreshingPrinters = false);
  }

  Future<void> _testPrint() async {
    final printerName = _settings.selectedPrinterName;
    if (printerName == null) return;

    setState(() {
      _testPrinting = true;
      _message = null;
    });

    try {
      // Generate test PDF
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.Page(
          pageFormat: _getPageFormat(),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  _storeNameCtrl.text.isNotEmpty ? _storeNameCtrl.text : 'Test Receipt',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Test Print', style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 4),
                pw.Text(DateTime.now().toString(), style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text('If you can read this,'),
                pw.Text('your printer is working!'),
                pw.SizedBox(height: 16),
                pw.Text(
                  _thankYouCtrl.text.isNotEmpty ? _thankYouCtrl.text : 'Thank you!',
                  style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      
      // Send to printer via backend
      final result = await PrintService.printPdf(pdfBytes, printerName: printerName);
      
      if (result.success) {
        setState(() {
          _message = '✓ Test page sent to $printerName';
          _isError = false;
        });
      } else {
        setState(() {
          _message = result.message;
          _isError = true;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Print error: $e';
        _isError = true;
      });
    } finally {
      setState(() => _testPrinting = false);
    }
  }

  PdfPageFormat _getPageFormat() {
    switch (_settings.paperSize) {
      case PaperSizeOption.thermal58mm:
        return PdfPageFormat.roll57;
      case PaperSizeOption.thermal80mm:
        return PdfPageFormat.roll80;
      case PaperSizeOption.a4:
        return PdfPageFormat.a4;
    }
  }
}
